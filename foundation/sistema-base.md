# Sistema Base PILAR

El **Sistema Base** es el núcleo funcional de PILAR: puede desplegarse solo, sin ningún módulo de negocio, y ya gestiona empresas, usuarios, roles y el lanzador de módulos. Sobre este sistema base se activan los módulos Core y Auxiliares según el plan SaaS de cada empresa.

---

## Índice

1. [Qué incluye el Sistema Base](#1-qué-incluye)
2. [Autenticación (Supabase Auth)](#2-autenticación)
3. [Multi-tenancy: Empresas & Establecimientos](#3-multi-tenancy-empresas--establecimientos)
4. [Usuarios & Roles](#4-usuarios--roles)
5. [Permisos Granulares](#5-permisos-granulares)
6. [Module Launcher](#6-module-launcher)
7. [Panel de Administración](#7-panel-de-administración)
8. [Core Foundation (servicios compartidos)](#8-core-foundation)
   - 8.1 Secuencias · 8.2 Adjuntos · 8.3 Audit Trail · 8.4 Configuración · 8.5 Sesiones · [8.6 Alertas de Empresa](#86-alertas-de-empresa)
9. [Función RLS: `private.get_empresa_id()`](#9-función-rls)
10. [RPCs del Sistema Base](#10-rpcs-del-sistema-base)
11. [Flujo de Onboarding](#11-flujo-de-onboarding)
12. [Estructura Flutter](#12-estructura-flutter)

---

## 1. Qué incluye

```
SISTEMA BASE (funcional sin módulos de negocio)
├── Auth              Supabase Auth: login, registro, MFA, OAuth, magic link
├── Empresas          Multi-tenancy: empresa (country-agnostic)
├── Usuarios          N usuarios x N empresas, roles por empresa
├── Roles & Permisos  SUPER_ADMIN / SAAS_ADMIN / ADMIN / GERENTE / CONTADOR / FACTURADOR / VENDEDOR / COMPRADOR / BODEGUERO / CAJERO / LECTURA + permisos granulares (definidos por cada módulo al activarse)
├── Module Launcher   App Launcher dinámico según módulos activos + planes SaaS
├── Admin Panel       Configurar empresa, gestionar usuarios, activar módulos
└── Core Foundation   Adjuntos, notificaciones, alertas, audit trail, catálogos, secuencias
```

Cuando el sistema base arranca **sin ningún módulo activado**, el usuario ve:
- Pantalla de login (con branding de su empresa)
- Dashboard vacío con placeholder "No tienes módulos activos"
- Panel de Administración completo para configurar la empresa y activar módulos

---

## 2. Autenticación

### Stack Auth

| Componente | Tecnología | Rol |
|-----------|-----------|-----|
| Auth server | Supabase Auth | JWT, sesiones, MFA, OAuth |
| Flutter UI | `supabase_auth_ui` | Widgets: SupaEmailAuth, SupaSocialsAuth, SupaMagicAuth, SupaResetPassword |
| Cliente | `supabase_flutter` | SupabaseClient, session listener |
| Estado | Riverpod `authProvider` | Stream de sesión activa |

### Métodos de Auth soportados

| Método | Widget | Configurable por empresa |
|--------|--------|--------------------------|
| Email + contraseña | `SupaEmailAuth` | Siempre disponible |
| Magic link (email) | `SupaMagicAuth` | Activable en Administración |
| OAuth (Google, Microsoft) | `SupaSocialsAuth` | Activable en Administración |
| MFA (TOTP) | Built-in Supabase | Obligatorio para ADMIN+ |

### Flujo de sesión

```
1. Usuario ingresa credenciales
2. Supabase Auth emite JWT con:
   - sub: auth.users.id
   - app_metadata.empresa_id: empresa activa (ver sección 4)
   - app_metadata.role: rol en empresa activa
3. Flutter recibe session y guarda access_token + refresh_token en SecureStorage
4. Todas las llamadas RLS usan private.get_empresa_id() → extrae empresa_id del JWT
5. Al cambiar de empresa → llamar RPC set_empresa_activa(empresa_id) → luego supabase.auth.refreshSession() → custom_access_token_hook inyecta el nuevo empresa_id en el JWT
```

### Tabla auth.users (Supabase managed)

Supabase gestiona esta tabla. PILAR extiende los metadatos:

```sql
-- PILAR no crea auth.users — Supabase Auth lo gestiona
-- Campos relevantes del JWT:
-- auth.users.id               → usuarios_empresa.usuario_id
-- auth.users.email            → email del usuario
-- auth.users.raw_user_meta_data → { 'nombre': 'Juan', 'avatar_url': '...' }
-- auth.users.app_metadata     → { 'empresa_id': uuid }
--                               (inyectado por custom_access_token_hook en cada JWT generado)
```

---

## 3. Multi-tenancy: Empresas

### Diagrama

```
empresa
  └── usuarios_empresa (N:N con auth.users)
```

### Tabla: `empresas` (Foundation — genérica)

```sql
CREATE TABLE empresas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identidad
  nombre              VARCHAR(300) NOT NULL,
  nombre_comercial    VARCHAR(300),
  ruc                 VARCHAR(13) NOT NULL UNIQUE,
  tipo_ruc            VARCHAR(20) DEFAULT 'SOCIEDAD',  -- PERSONA_NATURAL | SOCIEDAD

  -- Dirección fiscal
  provincia_id        INTEGER,
  ciudad_id           INTEGER,
  direccion           TEXT,
  telefono            VARCHAR(20),
  email               VARCHAR(200),
  web                 VARCHAR(300),

  -- Branding
  logo_url            TEXT,
  color_primario      VARCHAR(7) DEFAULT '#1565C0',
  color_secundario    VARCHAR(7) DEFAULT '#0288D1',
  fuente_preferida    VARCHAR(50) DEFAULT 'Roboto',

  -- SaaS
  plan_id             UUID REFERENCES planes_suscripcion(id),
  plan_activo_desde   DATE,
  plan_activo_hasta   DATE,
  estado              VARCHAR(20) DEFAULT 'TRIAL',  -- TRIAL | ACTIVO | SUSPENDIDO | CANCELADO
  trial_hasta         DATE,

  -- Auth
  metodos_auth        TEXT[] DEFAULT '{email}',
  dominio_sso         VARCHAR(200),

  -- Auditoría
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 4. Usuarios & Roles

### Relación N:M

Un usuario de Supabase Auth puede pertenecer a **N empresas** con **roles distintos** en cada una:

```
auth.users (id=uuid, email)
     ↕  N:M
usuarios_empresa (usuario_id, empresa_id, rol_id, activo)
     ↓
roles (SUPER_ADMIN | SAAS_ADMIN | ADMIN | GERENTE | CONTADOR | FACTURADOR | VENDEDOR | COMPRADOR | BODEGUERO | CAJERO | LECTURA | custom)
```

### Tabla: `usuarios_empresa`

```sql
CREATE TABLE usuarios_empresa (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id      UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  rol_id          UUID NOT NULL REFERENCES roles(id),

  -- Acceso
  activo          BOOLEAN DEFAULT true,
  invitado_por    UUID REFERENCES auth.users(id),
  invitado_en     TIMESTAMPTZ DEFAULT NOW(),
  ultimo_acceso   TIMESTAMPTZ,

  -- Preferencias de UI por empresa
  preferencias    JSONB DEFAULT '{}',
  -- {
  --   "tema": "dark",
  --   "fuente": "Roboto",
  --   "densidad": "normal",
  --   "idioma": "es",
  --   "modulo_inicio": "dashboard"
  -- }

  -- Perfil por empresa (override de auth.users.raw_user_meta_data global)
  nombre_display  VARCHAR(100),   -- nombre visible en esta empresa (override del nombre global)
  avatar_url      TEXT,           -- foto de perfil para esta empresa
  telefono        VARCHAR(20),    -- teléfono de contacto en esta empresa
  email_contacto  VARCHAR(255),   -- email alternativo en esta empresa
  zona_horaria    VARCHAR(50) DEFAULT 'America/Guayaquil', -- zona horaria del usuario en esta empresa

  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(usuario_id, empresa_id)
);

ALTER TABLE usuarios_empresa ENABLE ROW LEVEL SECURITY;

-- Usuario ve sus propias membresías
CREATE POLICY "ver_propias" ON usuarios_empresa
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid());

-- Admin de empresa ve todos los usuarios de su empresa
CREATE POLICY "admin_ver_empresa" ON usuarios_empresa
  FOR SELECT TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND private.has_permission('administracion.usuarios.ver')
  );

-- Solo ADMIN puede gestionar usuarios
CREATE POLICY "admin_gestionar" ON usuarios_empresa
  FOR ALL TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND private.has_permission('administracion.usuarios.gestionar')
  );

CREATE INDEX idx_usuarios_empresa_usuario ON usuarios_empresa(usuario_id);
CREATE INDEX idx_usuarios_empresa_empresa ON usuarios_empresa(empresa_id);
```

### Perfil de usuario por empresa

Cada usuario tiene un **perfil independiente por empresa** almacenado en las columnas de `usuarios_empresa`. Esto permite que el mismo usuario use un nombre diferente en cada empresa donde es miembro.

**Patrón de resolución de nombre (cascada):**
```
nombre_display (override empresa) → nombreGlobal (raw_user_meta_data) → email (login)
```

**Storage de avatares:** `avatares/{usuario_id}/{empresa_id}/avatar.jpg` (bucket `avatares`)

**Trigger `copy_perfil_on_empresa_join`:** Al añadir un usuario a una nueva empresa, copia automáticamente `nombre_display`, `avatar_url`, `telefono`, `email_contacto` y `zona_horaria` de su membresía más reciente con datos.

**RPCs de perfil:**
| RPC | Descripción |
|-----|-------------|
| `get_mi_perfil()` | Perfil fusionado del usuario JWT en su empresa activa (STABLE) |
| `update_mi_perfil(p_data JSONB)` | Actualiza campos del perfil propio |
| `admin_get_perfil_usuario(p_usuario_id)` | Admin lee perfil de otro usuario |
| `admin_update_perfil_usuario(p_usuario_id, p_data)` | Admin edita perfil de otro usuario |

**Provider Flutter:** `lib/core/providers/perfil_provider.dart` → `perfilUsuarioProvider`
Se invalida automáticamente en `pilar_shell.dart` al cambiar de empresa activa.

### Tabla: `roles`

```sql
CREATE TABLE roles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id) ON DELETE CASCADE,
  -- NULL empresa_id = rol global del sistema (SUPER_ADMIN)

  codigo          VARCHAR(30) NOT NULL,               -- 'SUPER_ADMIN', 'ADMIN', 'VENDEDOR', etc.
  nombre          VARCHAR(100) NOT NULL,
  descripcion     TEXT,
  es_sistema      BOOLEAN DEFAULT false,              -- true = no editable por empresa
  dashboard_plantilla_rol JSONB DEFAULT '[]',         -- KPIs predeterminados por rol

  created_at      TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(empresa_id, codigo)
);

-- Roles del sistema (empresa_id = NULL, es_sistema = true, no editables por empresa)
INSERT INTO roles (empresa_id, codigo, nombre, descripcion, es_sistema) VALUES
  -- Plataforma PILAR (solo para el equipo interno)
  (NULL, 'SUPER_ADMIN',  'Super Administrador',     'Acceso total a todas las empresas y configuración de plataforma', true),
  -- Empresa - Administración
  (NULL, 'SAAS_ADMIN',   'Administrador SaaS',       'Gestiona la cuenta SaaS, suscripciones y módulos activos', true),
  (NULL, 'ADMIN',        'Administrador de Empresa',  'Acceso completo a módulos activos, gestión de usuarios y configuración', true),
  (NULL, 'GERENTE',      'Gerente',                   'Acceso a reportes, aprobaciones, dashboards gerenciales', true),
  -- Módulos operativos
  (NULL, 'CONTADOR',     'Contador',                  'Acceso a módulos financieros y reportes', true),
  (NULL, 'FACTURADOR',   'Facturador',                'Emisión de documentos de venta, cobranzas, clientes', true),
  (NULL, 'VENDEDOR',     'Vendedor',                  'Gestión comercial, clientes asignados', true),
  (NULL, 'COMPRADOR',    'Comprador',                 'Gestión de adquisiciones, proveedores', true),
  (NULL, 'BODEGUERO',    'Bodeguero',                 'Movimientos de almacén y transferencias', true),
  (NULL, 'CAJERO',       'Cajero',                    'Operación de punto de venta, cobros', true),
  -- Solo lectura
  (NULL, 'LECTURA',      'Solo Lectura',              'Ver registros en todos los módulos, sin crear ni editar', true);
```

### Roles y capacidades predeterminadas

| Rol | Descripción | Capacidades |
|-----|-------------|------------|
| `SUPER_ADMIN` | Administrador global de la plataforma PILAR | Todo. Accede a todas las empresas. Solo para el equipo PILAR. |
| `SAAS_ADMIN` | Administrador SaaS | Gestiona la cuenta SaaS, suscripciones, módulos activos. |
| `ADMIN` | Administrador de empresa | Gestionar usuarios, roles, módulos, configuración. Todos los módulos activos. |
| `GERENTE` | Gerente | Acceso a reportes, aprobaciones, dashboards gerenciales. |
| `CONTADOR` | Contador | Acceso a módulos financieros y reportes (definidos por los módulos activos). |
| `FACTURADOR` | Facturador | Emisión de documentos de venta, cobranzas, clientes. |
| `VENDEDOR` | Vendedor | Gestión comercial, clientes asignados. |
| `COMPRADOR` | Comprador | Gestión de adquisiciones, proveedores. |
| `BODEGUERO` | Bodeguero | Movimientos de almacén y transferencias. |
| `CAJERO` | Cajero | Operación de punto de venta, cobros. |
| `LECTURA` | Solo lectura | Ver registros en todos los módulos activos, sin crear ni editar. |

---

## 5. Permisos Granulares

Los permisos siguen el patrón `modulo.recurso.accion`:

```sql
CREATE TABLE permisos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      VARCHAR(100) NOT NULL UNIQUE,
  -- Formato: 'modulo.recurso.accion'
  -- Ejemplos: 'administracion.usuarios.gestionar'
  --           '<modulo>.<recurso>.crear'
  --           '<modulo>.<recurso>.aprobar'
  --           '<modulo>.<recurso>.ver'
  -- Los permisos de cada módulo se insertan en las migraciones de ese módulo
  nombre      VARCHAR(200) NOT NULL,
  modulo      VARCHAR(30) NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Permisos asignados a roles
CREATE TABLE roles_permisos (
  rol_id      UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permiso_id  UUID NOT NULL REFERENCES permisos(id) ON DELETE CASCADE,
  PRIMARY KEY (rol_id, permiso_id)
);
```

### Función helper: `private.has_permission()`

```sql
-- Verifica si el usuario autenticado tiene un permiso específico en su empresa activa
CREATE OR REPLACE FUNCTION private.has_permission(p_permiso VARCHAR)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM usuarios_empresa ue
    JOIN roles r ON r.id = ue.rol_id
    JOIN roles_permisos rp ON rp.rol_id = r.id
    JOIN permisos p ON p.id = rp.permiso_id
    WHERE ue.usuario_id    = auth.uid()
      AND ue.empresa_id    = private.get_empresa_id()
      AND ue.activo        = true
      AND p.codigo         = p_permiso
  )
  OR EXISTS (
    -- SUPER_ADMIN tiene todos los permisos
    SELECT 1
    FROM usuarios_empresa ue
    JOIN roles r ON r.id = ue.rol_id
    WHERE ue.usuario_id = auth.uid()
      AND r.codigo      = 'SUPER_ADMIN'
  );
$$;
```

---

## 6. Module Launcher

El App Launcher es la pantalla principal del ERP. Muestra un **grid de módulos activos** para la empresa del usuario. Al hacer click en un módulo, el router navega al módulo correspondiente.

### Tablas del sistema de módulos

```sql
-- Módulos disponibles en el sistema (seed data, no editable)
CREATE TABLE modulos (
  id          VARCHAR(30) PRIMARY KEY,
  nombre      VARCHAR(100) NOT NULL,
  descripcion TEXT,
  icono       VARCHAR(50),                -- Material Icons name (ej: 'point_of_sale')
  orden       INTEGER DEFAULT 0,
  tipo        VARCHAR(20) NOT NULL,
  -- 'infraestructura': siempre activos (Dashboard, Administración, Comunicación)
  -- 'core':            proveen servicios via module_bus
  -- 'auxiliar':        activables por empresa/plan
  activo      BOOLEAN DEFAULT true
);

-- Módulos habilitados por empresa (controlado por plan + activación manual)
CREATE TABLE modulos_empresa (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  modulo_id        VARCHAR(30) NOT NULL REFERENCES modulos(id),
  habilitado       BOOLEAN DEFAULT true,
  fecha_activacion DATE DEFAULT CURRENT_DATE,
  activado_por     UUID REFERENCES auth.users(id),

  UNIQUE(empresa_id, modulo_id)
);

ALTER TABLE modulos_empresa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON modulos_empresa
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Planes SaaS

```sql
CREATE TABLE planes_suscripcion (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo              VARCHAR(20) UNIQUE NOT NULL,
  nombre              VARCHAR(100) NOT NULL,
  descripcion         TEXT,
  precio_mensual      DECIMAL(14,2) NOT NULL DEFAULT 0,
  precio_anual        DECIMAL(14,2) NOT NULL DEFAULT 0,
  max_usuarios        INTEGER,                        -- NULL = ilimitado
  max_empresas        INTEGER DEFAULT 1,
  max_documentos_mes  INTEGER,                        -- NULL = ilimitado
  max_storage_mb      INTEGER DEFAULT 500,
  modulos_incluidos   TEXT[],                         -- NULL = todos los módulos
  activo              BOOLEAN DEFAULT true,
  orden               INTEGER DEFAULT 0,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO planes_suscripcion (codigo, nombre, precio_mensual, precio_anual, max_usuarios, modulos_incluidos) VALUES
  ('FREE',       'Gratuito',      0,      0,      1,    ARRAY['modulo_a','modulo_b']),
  ('STARTER',    'Starter',       29.99,  299.90, 3,    ARRAY['modulo_a','modulo_b','modulo_c']),
  ('PRO',        'Profesional',   59.99,  599.90, 10,   ARRAY['modulo_a','modulo_b','modulo_c','modulo_d']),
  ('ENTERPRISE', 'Empresarial',   99.99,  999.90, NULL, NULL);  -- NULL = todos
```

### RPC: obtener módulos activos

```sql
-- Retorna los módulos que el usuario puede ver en el App Launcher
CREATE OR REPLACE FUNCTION get_modulos_activos()
RETURNS TABLE (
  id          VARCHAR(30),
  nombre      VARCHAR(100),
  icono       VARCHAR(50),
  orden       INTEGER,
  tipo        VARCHAR(20)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  -- Módulos de infraestructura: siempre visibles
  SELECT m.id, m.nombre, m.icono, m.orden, m.tipo
  FROM modulos m
  WHERE m.tipo = 'infraestructura' AND m.activo = true

  UNION ALL

  -- Módulos Core y Auxiliares: solo si están habilitados para la empresa
  SELECT m.id, m.nombre, m.icono, m.orden, m.tipo
  FROM modulos m
  JOIN modulos_empresa me ON me.modulo_id = m.id
  WHERE me.empresa_id = private.get_empresa_id()
    AND me.habilitado = true
    AND m.activo      = true
    AND m.tipo        IN ('core', 'auxiliar')

  ORDER BY orden ASC;
$$;
```

### Flutter: App Launcher Widget

```dart
// features/dashboard/widgets/app_launcher.dart
class AppLauncher extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modulosAsync = ref.watch(modulosActivosProvider);

    return modulosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => ErrorWidget(e),
      data: (modulos) {
        if (modulos.isEmpty) return const _EmptyModulosPlaceholder();

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: PilarSizes.appLauncherColumns(context),  // 2/3/4/5 según breakpoint
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          itemCount: modulos.length,
          itemBuilder: (ctx, i) => AppLauncherTile(modulo: modulos[i]),
        );
      },
    );
  }
}
```

---

## 7. Panel de Administración

El módulo **Administración** es de tipo `infraestructura` (siempre activo). Agrupa toda la configuración del sistema para la empresa.

### Secciones del Panel

```
admin/
├── empresa/
│   └── datos-generales/    Identificación fiscal, nombre, dirección, logo, colores
├── usuarios/
│   ├── lista/              Ver usuarios activos, invitar, desactivar
│   ├── roles/              Crear roles personalizados, asignar permisos
│   └── invitaciones/       Invitaciones pendientes de aceptar
├── modulos/
│   ├── activos/            Qué módulos están habilitados
│   ├── activar/            Activar módulo del plan + confirmar
│   └── plan/               Ver plan actual, límites, upgrade
├── integraciones/
│   └── notificaciones/     Configurar canales de notificación
└── preferencias/
    ├── login/              Branding: logo, colores, métodos auth habilitados
    ├── notificaciones/     Configurar qué notificaciones enviar y por qué canal
    └── seguridad/          MFA obligatorio, política contraseñas, sesiones
```

### Pantalla: Gestión de Módulos

```
┌─────────────────────────────────────────────────────────────┐
│  MÓDULOS  |  Plan Profesional — 8/10 módulos activos        │
├─────────────────────────────────────────────────────────────┤
│  ✅ Módulo A       ✅ Módulo B       ✅ Módulo C             │
│  ✅ Módulo D       ✅ Módulo E       ✅ Módulo F             │
│  ✅ Módulo G       ✅ Módulo H       ⬜ Módulo I [Activar]   │
│                                     🔒 Módulo J [Upgrade]   │
├─────────────────────────────────────────────────────────────┤
│  [Ver planes]                     [Gestionar suscripción]    │
└─────────────────────────────────────────────────────────────┘
```

### RPC: activar módulo

```sql
CREATE OR REPLACE FUNCTION admin_activate_module(p_modulo_id VARCHAR)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id UUID := private.get_empresa_id();
  v_plan       RECORD;
  v_modulo     RECORD;
BEGIN
  -- Verificar permiso
  IF NOT private.has_permission('administracion.modulos.gestionar') THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERMISSION_DENIED');
  END IF;

  -- Verificar que el módulo existe y es activable
  SELECT * INTO v_modulo FROM modulos WHERE id = p_modulo_id AND tipo != 'infraestructura';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'MODULE_NOT_FOUND');
  END IF;

  -- Verificar que el plan incluye el módulo
  SELECT ps.* INTO v_plan
  FROM empresas e
  JOIN planes_suscripcion ps ON ps.id = e.plan_id
  WHERE e.id = v_empresa_id;

  IF v_plan.modulos_incluidos IS NOT NULL
     AND NOT (p_modulo_id = ANY(v_plan.modulos_incluidos)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'MODULE_NOT_IN_PLAN');
  END IF;

  -- Activar (upsert)
  INSERT INTO modulos_empresa (empresa_id, modulo_id, habilitado, activado_por)
  VALUES (v_empresa_id, p_modulo_id, true, auth.uid())
  ON CONFLICT (empresa_id, modulo_id)
  DO UPDATE SET habilitado = true, fecha_activacion = CURRENT_DATE, activado_por = auth.uid();

  RETURN jsonb_build_object('success', true, 'modulo_id', p_modulo_id);
END;
$$;
```

---

## 8. Core Foundation

La **Core Foundation** es la infraestructura compartida que existe antes que cualquier módulo de negocio. No es un módulo activable: siempre está presente.

### 8.1 Secuencias

```sql
-- Secuencias genéricas (para módulos que necesitan numeración correlativa)
CREATE TABLE secuencias (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id),
  codigo      VARCHAR(50) NOT NULL,     -- Código del tipo de documento (definido por cada módulo)
  prefijo     VARCHAR(10),              -- Prefijo opcional (ej: 'DOC-', 'REF-')
  siguiente   BIGINT NOT NULL DEFAULT 1,
  padding     INTEGER DEFAULT 6,        -- Ceros a la izquierda: 000001
  UNIQUE(empresa_id, codigo)
);

ALTER TABLE secuencias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON secuencias FOR ALL TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 8.2 Adjuntos (Attachments polimórfico)

```sql
CREATE TABLE adjuntos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),

  -- Referencia polimórfica
  tabla_origen    VARCHAR(60) NOT NULL,  -- Nombre de la tabla del módulo que origina el adjunto
  registro_id     UUID NOT NULL,

  nombre_archivo  VARCHAR(300) NOT NULL,
  tipo_mime       VARCHAR(100),
  tamano_bytes    INTEGER,
  storage_path    TEXT NOT NULL,         -- Path en Supabase Storage
  url_publica     TEXT,                  -- URL pública si aplica

  subido_por      UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE adjuntos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON adjuntos
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_adjuntos_registro ON adjuntos(empresa_id, tabla_origen, registro_id);
```

### 8.3 Audit Trail

```sql
CREATE TABLE registro_actividad (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  usuario_id      UUID REFERENCES auth.users(id),

  -- Qué cambió
  tabla_origen    VARCHAR(60) NOT NULL,
  registro_id     UUID NOT NULL,
  accion          VARCHAR(20) NOT NULL,  -- 'CREATE' | 'UPDATE' | 'DELETE' | 'CONFIRM' | 'CANCEL'
  datos_antes     JSONB,
  datos_despues   JSONB,
  campos_cambiados TEXT[],               -- ['estado', 'total']

  -- Contexto
  ip_address      INET,
  user_agent      TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE registro_actividad ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON registro_actividad
  FOR SELECT TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
-- INSERT es solo via SECURITY DEFINER function (no desde cliente)

CREATE INDEX idx_actividad_registro ON registro_actividad(empresa_id, tabla_origen, registro_id);
CREATE INDEX idx_actividad_fecha    ON registro_actividad(empresa_id, created_at DESC);
```

### 8.4 Configuración de empresa

```sql
CREATE TABLE configuracion_empresa (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id) UNIQUE,

  -- Preferencias globales de la empresa
  moneda_id           UUID REFERENCES monedas(id),     -- Moneda base (por defecto USD)
  decimales_monto     INTEGER DEFAULT 2,
  decimales_cantidad  INTEGER DEFAULT 6,
  idioma              VARCHAR(10) DEFAULT 'es',

  -- Configuración extendida por módulos (cada módulo añade sus propios campos
  -- via ALTER TABLE o mediante la columna config_extra como JSONB)
  config_extra        JSONB DEFAULT '{}',

  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE configuracion_empresa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON configuracion_empresa
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 8.5 Sesiones de usuario

Rastrea dispositivos activos y permite revocar sesiones remotamente.

```sql
CREATE TABLE sesiones_usuario (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id      UUID REFERENCES empresas(id),
  dispositivo     TEXT,                   -- "Chrome 120 / macOS", "PILAR Android"
  ip_address      INET,
  user_agent      TEXT,
  inicio          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ultimo_acceso   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  activa          BOOLEAN NOT NULL DEFAULT true,
  token_id        TEXT,                   -- Referencia al refresh token de Supabase Auth
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE sesiones_usuario ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_sessions" ON sesiones_usuario
  FOR ALL TO authenticated
  USING (usuario_id = auth.uid());
-- Admin puede ver sesiones de su empresa
CREATE POLICY "admin_ver_sesiones" ON sesiones_usuario
  FOR SELECT TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND private.has_permission('administracion.seguridad.ver')
  );

CREATE INDEX idx_sesiones_usuario ON sesiones_usuario(usuario_id, activa);
```

Config en `parametros_sistema`:
- `max_sesiones_simultaneas`: 5 (default)
- `timeout_inactividad_minutos`: 30 (default)

### 8.6 Alertas de Empresa

Las **alertas de empresa** son mensajes persistentes visibles para todos (o un subconjunto de roles) dentro de una empresa. A diferencia de `notificaciones_usuario` (efímeras, por usuario, se marcan como leídas), una alerta permanece **activa** hasta que alguien la **resuelva** o **ignore**.

#### Casos de uso

| Origen | Ejemplo |
|--------|---------|
| SRI / facturación | "Certificado digital vence en 7 días" |
| Inventario | "Stock negativo en producto X" |
| Contabilidad | "Período fiscal sin cerrar" |
| Tesorería | "Cheque rechazado sin gestionar" |
| Sistema | "Copia de seguridad fallida" |

#### Tabla `alertas_empresa`

```sql
CREATE TABLE alertas_empresa (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,

  -- Origen
  origen_modulo   VARCHAR(60) NOT NULL,    -- 'facturacion', 'inventario', etc.
  codigo_alerta   VARCHAR(100),            -- Clave semántica, ej: 'SRI_CERT_EXPIRING'
  registro_id     UUID,                    -- Soft ref al registro relacionado (sin FK)

  -- Contenido
  severidad       VARCHAR(20) NOT NULL DEFAULT 'warning',  -- 'info'|'warning'|'error'|'critical'
  titulo          VARCHAR(300) NOT NULL,
  cuerpo          TEXT,
  datos           JSONB NOT NULL DEFAULT '{}',  -- Metadata extra (días restantes, etc.)
  accion_url      TEXT,                         -- Deep-link opcional para navegar al problema

  -- Visibilidad
  roles_destino   TEXT[],                  -- NULL = todos; ['ADMIN','CONTADOR'] = solo esos roles

  -- Ciclo de vida
  estado          VARCHAR(20) NOT NULL DEFAULT 'activa',   -- 'activa'|'resuelta'|'ignorada'
  resuelta_por    UUID REFERENCES auth.users(id),
  resuelta_at     TIMESTAMPTZ,
  nota_resolucion TEXT,
  expira_at       TIMESTAMPTZ,            -- NULL = no expira (expiran automáticamente vía pg_cron)

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índice para queries de alertas activas (más frecuentes)
CREATE INDEX idx_alertas_empresa_activas
  ON alertas_empresa(empresa_id, severidad, created_at DESC)
  WHERE estado = 'activa';

-- Índice parcial de deduplicación: evita alertas activas duplicadas del mismo tipo
CREATE UNIQUE INDEX idx_alertas_dedup
  ON alertas_empresa(empresa_id, codigo_alerta)
  WHERE estado = 'activa' AND codigo_alerta IS NOT NULL;

-- Realtime habilitado
ALTER TABLE alertas_empresa REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE alertas_empresa;
```

#### Ciclo de vida

```
[Módulo llama crear_alerta()]
         ↓
    estado = 'activa'
         ↓
  visible en PilarHeader
  (badge con color por severidad)
         ↓
   Usuario abre AlertasPanel
         ↓
    ┌────┴────┐
  Resolver  Ignorar
    ↓         ↓
 'resuelta'  'ignorada'
  (con nota opcional)
```

**Deduplicación**: Si un módulo llama `crear_alerta()` con el mismo `codigo_alerta` y ya existe una alerta activa con ese código para la empresa, la llamada hace `ON CONFLICT DO UPDATE` (actualiza `titulo`, `cuerpo`, `datos` y `updated_at`) en lugar de crear un duplicado. Esto garantiza que un proceso recurrente (ej: pg_cron revisando certificados) no genere spam de alertas.

#### RPCs

| Función | Descripción |
|---------|-------------|
| `crear_alerta(origen, severidad, titulo, ...)` | Crea o actualiza (upsert por `codigo_alerta`) |
| `resolver_alerta(p_alerta_id, p_nota?)` | Marca como resuelta con nota opcional |
| `ignorar_alerta(p_alerta_id)` | Marca como ignorada |
| `get_alertas_activas(p_limite, p_offset)` | Lista alertas activas visibles para el rol del usuario |
| `get_count_alertas_activas()` | Conteo para badge del header (sin paginación) |

`crear_alerta` solo puede ser llamada con `SECURITY DEFINER` desde el backend (Edge Functions, pg_cron, otros RPCs). **No está expuesta al cliente Flutter.**

`get_alertas_activas` aplica la visibilidad por `roles_destino`: si es NULL muestra a todos; si tiene valores, filtra por el rol del usuario en la empresa.

#### pg_cron jobs

| Job | Schedule | Acción |
|-----|----------|--------|
| `pilar_expire_alertas` | Cada hora `:00` | `UPDATE estado='ignorada' WHERE expira_at < NOW() AND estado='activa'` |
| `pilar_cleanup_old_alertas` | Diario 03:30 | `DELETE WHERE estado IN ('resuelta','ignorada') AND updated_at < NOW() - INTERVAL '1 year'` |

#### Cómo los módulos crean alertas

Cualquier módulo (Edge Function, pg_cron, RPC) puede crear alertas llamando a `crear_alerta()`. La función tiene `SECURITY DEFINER` y no requiere que el usuario tenga ningún permiso especial.

```sql
-- Ejemplo desde un job pg_cron en facturacion_ec:
SELECT crear_alerta(
  p_empresa_id    := v_empresa_id,
  p_origen_modulo := 'facturacion_ec',
  p_codigo_alerta := 'SRI_CERT_EXPIRING',   -- clave de deduplicación
  p_severidad     := 'critical',
  p_titulo        := 'Certificado SRI vence en ' || v_dias || ' días',
  p_cuerpo        := 'El certificado .p12 expira el ' || to_char(v_fecha, 'DD/MM/YYYY') ||
                     '. Renuévelo para evitar interrupciones en la facturación.',
  p_datos         := jsonb_build_object('dias_restantes', v_dias, 'empresa_id', v_empresa_id),
  p_roles_destino := ARRAY['ADMIN', 'CONTADOR'],
  p_expira_at     := NULL   -- permanece hasta que alguien la resuelva
);
```

```typescript
// Ejemplo desde una Edge Function (Deno):
const { error } = await supabaseAdmin.rpc('crear_alerta', {
  p_empresa_id:    empresaId,
  p_origen_modulo: 'tesoreria',
  p_codigo_alerta: 'CHEQUE_RECHAZADO_' + chequeId,
  p_severidad:     'error',
  p_titulo:        `Cheque #${numero} rechazado por el banco`,
  p_datos:         { cheque_id: chequeId, monto, banco },
  p_roles_destino: ['ADMIN', 'TESORERO'],
});
```

#### Flutter — integración en PilarShell

```dart
// En PilarHeader (lib/core/shell/pilar_header.dart):
final alertasCount = ref.watch(alertasCountProvider).valueOrNull ?? 0;
final alertas      = ref.watch(alertasActivasProvider).valueOrNull ?? [];

// Badge rojo si hay critical/error, ámbar si solo warning/info
final alertaColor = alertas.any((a) => a.severidad == 'critical' || a.severidad == 'error')
    ? Colors.errorPrimaryColor
    : const Color(0xFFF59E0B);

// Icono FluentIcons.shield_alert — visible solo cuando alertasCount > 0
// Al pulsar → showDialog<void>(builder: (_) => const AlertasPanel())
```

`alertasCountProvider` usa Realtime (INSERT + UPDATE en `alertas_empresa`) + refresh periódico de 60 s como fallback. El proveedor se invalida al cambiar sesión o empresa activa.

---

## 9. Función RLS

La función `private.get_empresa_id()` es el corazón del multi-tenancy. Toda policy RLS la usa.

```sql
-- Schema privado (no expuesto via API)
CREATE SCHEMA IF NOT EXISTS private;

-- Cachea empresa_id del JWT: ~99.99% más rápido que inline JWT parsing por fila
CREATE OR REPLACE FUNCTION private.get_empresa_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::UUID;
$$;

-- Al cambiar de empresa: set_empresa_activa() actualiza ultimo_acceso,
-- luego el cliente llama refreshSession() → custom_access_token_hook inyecta el nuevo empresa_id
```

### Patrón obligatorio para todas las tablas

```sql
-- SIEMPRE este patrón (con subquery para caching):
ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON <tabla>
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Para tablas donde un usuario solo ve sus propios registros:
CREATE POLICY "own_records" ON usuarios_empresa
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid());

-- NUNCA este patrón (sin subquery = parsea JWT por cada fila):
-- USING (empresa_id = (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::UUID)
```

---

## 10. RPCs del Sistema Base

| Función | Descripción | Auth |
|---------|-------------|------|
| `get_modulos_activos()` | Lista módulos visibles en el App Launcher | Autenticado |
| `get_mis_empresas()` | Lista las empresas a las que pertenece el usuario | Autenticado |
| `set_empresa_activa(empresa_id)` | Cambia la empresa activa en el JWT | Autenticado |
| `admin_invite_user(email, rol_id)` | Invita a un usuario a la empresa | `administracion.usuarios.gestionar` |
| `admin_activate_module(modulo_id)` | Activa un módulo para la empresa | `administracion.modulos.gestionar` |
| `admin_deactivate_module(modulo_id)` | Desactiva un módulo | `administracion.modulos.gestionar` |
| `admin_update_empresa(data)` | Actualiza datos de la empresa | `administracion.empresa.editar` |
| `admin_get_usuarios()` | Lista usuarios de la empresa con roles | `administracion.usuarios.ver` |
| `admin_change_user_role(usuario_id, rol_id)` | Cambia rol de usuario | `administracion.usuarios.gestionar` |
| `admin_deactivate_user(usuario_id)` | Desactiva acceso de usuario | `administracion.usuarios.gestionar` |
| `get_audit_trail(tabla, registro_id)` | Historial de cambios de un registro | Autenticado |
| `get_next_sequence(codigo)` | Obtiene siguiente número de secuencia | Autenticado |
| `get_notificaciones(p_limite, p_offset)` | Lista notificaciones del usuario (leídas + no leídas) | Autenticado |
| `marcar_notificacion_leida(p_notificacion_id)` | Marca una notificación como leída | Autenticado |
| `marcar_todas_notificaciones_leidas()` | Marca todas las notificaciones del usuario como leídas | Autenticado |
| `get_count_notificaciones_no_leidas()` | Conteo para badge del header | Autenticado |
| `crear_alerta(p_empresa_id, p_origen_modulo, p_severidad, p_titulo, ...)` | Crea o actualiza alerta activa (upsert por `codigo_alerta`) | SECURITY DEFINER (solo backend) |
| `resolver_alerta(p_alerta_id, p_nota?)` | Resuelve una alerta con nota opcional | Autenticado (cualquier rol visible) |
| `ignorar_alerta(p_alerta_id)` | Ignora una alerta | Autenticado (cualquier rol visible) |
| `get_alertas_activas(p_limite, p_offset)` | Lista alertas activas filtradas por rol del usuario | Autenticado |
| `get_count_alertas_activas()` | Conteo de alertas activas para badge del header | Autenticado |

### RPC: `get_mis_empresas()`

```sql
CREATE OR REPLACE FUNCTION get_mis_empresas()
RETURNS TABLE (
  empresa_id    UUID,
  empresa_nombre VARCHAR(300),
  empresa_ruc   VARCHAR(13),
  logo_url      TEXT,
  rol_codigo    VARCHAR(30),
  rol_nombre    VARCHAR(100),
  es_activa     BOOLEAN        -- La empresa activa en el JWT actual
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    e.id,
    e.nombre,
    e.ruc,
    e.logo_url,
    r.codigo,
    r.nombre,
    e.id = private.get_empresa_id()
  FROM usuarios_empresa ue
  JOIN empresas e ON e.id = ue.empresa_id
  JOIN roles r    ON r.id = ue.rol_id
  WHERE ue.usuario_id = auth.uid()
    AND ue.activo = true
    AND e.estado  = 'ACTIVO'
  ORDER BY e.nombre;
$$;
```

### RPC: `set_empresa_activa(empresa_id)`

```sql
CREATE OR REPLACE FUNCTION set_empresa_activa(p_empresa_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rol RECORD;
BEGIN
  -- Verificar que el usuario pertenece a la empresa
  SELECT r.codigo, r.nombre INTO v_rol
  FROM usuarios_empresa ue
  JOIN roles r ON r.id = ue.rol_id
  WHERE ue.usuario_id = auth.uid()
    AND ue.empresa_id = p_empresa_id
    AND ue.activo = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPRESA_NO_AUTORIZADA');
  END IF;

  -- Actualizar último acceso
  UPDATE usuarios_empresa
  SET ultimo_acceso = NOW()
  WHERE usuario_id = auth.uid() AND empresa_id = p_empresa_id;

  -- El cliente Flutter debe llamar a supabase.auth.refreshSession() después de esta RPC.
  -- custom_access_token_hook (019_auth_hook.sql) inyecta automáticamente el empresa_id
  -- de ultimo_acceso DESC en el nuevo JWT. No se requiere llamada a la Admin API.
  RETURN jsonb_build_object(
    'success',     true,
    'empresa_id',  p_empresa_id,
    'rol',         v_rol.codigo
  );
END;
$$;
```

---

## 11. Flujo de Onboarding

Cuando un usuario nuevo se registra en PILAR:

```
1. REGISTRO
   ↓ supabase.auth.signUp(email, password)
   ↓ Supabase Auth crea auth.users record
   ↓ Trigger: after_auth_user_created()
      - Crea empresa con RUC vacío (TRIAL)
      - Crea usuarios_empresa con rol ADMIN
      - Inserta módulos de infraestructura en modulos_empresa
      - Inserta módulos del plan FREE en modulos_empresa
      - Crea configuracion_empresa con defaults
      - (app_metadata.empresa_id es inyectado por custom_access_token_hook al generar el JWT)

2. VERIFICAR EMAIL
   ↓ Usuario hace click en link de verificación
   ↓ Supabase Auth verifica email

3. ONBOARDING WIZARD (primer login)
   ↓ Flutter detecta empresa.ruc IS NULL → redirige a /onboarding
   Paso 1: Datos de empresa (nombre, identificación fiscal, dirección)
   Paso 2: Activar módulos del plan
   Paso 3: Invitar usuarios
   ↓ Completar → redirige a /dashboard (App Launcher)

4. ESTADO FINAL
   ↓ empresa.estado = 'TRIAL' (30 días)
   ↓ App Launcher muestra módulos del plan FREE
   ↓ Panel de Administración disponible para configurar
```

### Trigger: `after_auth_user_created`

```sql
CREATE OR REPLACE FUNCTION private.after_auth_user_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id   UUID;
  v_rol_id       UUID;
  v_plan_id      UUID;
BEGIN
  -- Obtener plan FREE
  SELECT id INTO v_plan_id FROM planes_suscripcion WHERE codigo = 'FREE';

  -- Crear empresa placeholder
  INSERT INTO empresas (nombre, ruc, plan_id, estado, trial_hasta)
  VALUES (
    COALESCE(NEW.raw_user_meta_data->>'nombre', 'Mi Empresa'),
    '9999999999999',              -- RUC placeholder → usuario debe actualizar
    v_plan_id,
    'TRIAL',
    CURRENT_DATE + INTERVAL '30 days'
  )
  RETURNING id INTO v_empresa_id;

  -- Obtener rol ADMIN
  SELECT id INTO v_rol_id FROM roles WHERE codigo = 'ADMIN' AND empresa_id IS NULL;

  -- Asociar usuario a empresa como ADMIN
  INSERT INTO usuarios_empresa (usuario_id, empresa_id, rol_id)
  VALUES (NEW.id, v_empresa_id, v_rol_id);

  -- Activar módulos de infraestructura (siempre activos)
  INSERT INTO modulos_empresa (empresa_id, modulo_id)
  SELECT v_empresa_id, id FROM modulos WHERE tipo = 'infraestructura';

  -- Activar módulos del plan FREE
  INSERT INTO modulos_empresa (empresa_id, modulo_id)
  SELECT v_empresa_id, unnest(modulos_incluidos)
  FROM planes_suscripcion WHERE id = v_plan_id
  ON CONFLICT (empresa_id, modulo_id) DO NOTHING;

  -- Crear configuración default
  INSERT INTO configuracion_empresa (empresa_id) VALUES (v_empresa_id);

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION private.after_auth_user_created();
```

---

## 12. Estructura Flutter

### Providers del sistema base

```dart
// core/providers/auth_provider.dart
@riverpod
Stream<AuthState> authState(AuthStateRef ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
}

// core/providers/empresa_provider.dart
@riverpod
Future<List<EmpresaResumen>> misEmpresas(MisEmpresasRef ref) async {
  final response = await Supabase.instance.client.rpc('get_mis_empresas');
  return (response as List).map((e) => EmpresaResumen.fromJson(e)).toList();
}

@riverpod
Future<List<ModuloItem>> modulosActivos(ModulosActivosRef ref) async {
  final response = await Supabase.instance.client.rpc('get_modulos_activos');
  return (response as List).map((m) => ModuloItem.fromJson(m)).toList();
}
```

### Rutas del sistema base (go_router)

```dart
// core/router/router_config.dart
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull?.session != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isAuthRoute) return '/auth/login';
      if (isLoggedIn && isAuthRoute)  return '/dashboard';
      return null;
    },
    routes: [
      // Auth
      GoRoute(path: '/auth/login',          builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/register',       builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/auth/reset-password', builder: (_, __) => const ResetPasswordScreen()),

      // Onboarding
      GoRoute(path: '/onboarding',          builder: (_, __) => const OnboardingWizard()),

      // Selector de empresa (cuando usuario tiene N empresas)
      GoRoute(path: '/select-empresa',      builder: (_, __) => const SelectEmpresaScreen()),

      // Shell principal con PilarShell (header + nav + content)
      ShellRoute(
        builder: (ctx, state, child) => PilarShell(child: child),
        routes: [
          GoRoute(path: '/dashboard',       builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/admin',           builder: (_, __) => const AdminPanelScreen()),
          // Rutas de módulos se registran dinámicamente al activarse
        ],
      ),
    ],
  );
});
```

### Estructura de directorios para el sistema base

```
lib/
├── main.dart                  # Entry point principal
├── app.dart                   # Configuración de la aplicación (flavors adicionales definidos por módulos)
│
├── core/
│   ├── router/
│   │   └── router_config.dart
│   ├── providers/
│   │   ├── auth_provider.dart
│   │   ├── empresa_provider.dart
│   │   └── modulos_provider.dart
│   ├── shell/
│   │   ├── pilar_shell.dart
│   │   ├── pilar_app_launcher.dart
│   │   └── pilar_navigation.dart
│   └── theme/
│       ├── pilar_theme.dart
│       └── pilar_sizes.dart   # Breakpoints + escalado
│
└── features/
    ├── auth/
    │   ├── screens/
    │   │   ├── login_screen.dart
    │   │   ├── register_screen.dart
    │   │   └── reset_password_screen.dart
    │   └── providers/
    │       └── auth_providers.dart
    ├── onboarding/
    │   └── screens/
    │       └── onboarding_wizard.dart
    ├── select_empresa/
    │   └── screens/
    │       └── select_empresa_screen.dart
    ├── dashboard/
    │   ├── screens/
    │   │   └── dashboard_screen.dart
    │   └── widgets/
    │       └── app_launcher.dart
    └── administracion/
        ├── screens/
        │   ├── admin_panel_screen.dart
        │   ├── empresa_screen.dart
        │   ├── usuarios_screen.dart
        └── screens/
            └── modulos_screen.dart
```

---

## Referencias cruzadas

| Documento | Relación |
|-----------|----------|
| `foundation/arquitectura.md` | Patrones multi-tenancy, RLS, capas |
| `foundation/arquitectura-modular.md` | Module Service Bus, ciclo de vida de módulos |
| `foundation/seguridad.md` | RLS avanzado, cifrado, privacidad |
| `foundation/adrs/ADR-003_rls-pattern.md` | Decisión de arquitectura: `private.get_empresa_id()` |
| `foundation/adrs/ADR-004_flutter-single-codebase.md` | Decisión: un solo codebase Flutter |
| `foundation/adrs/ADR-005_no-firebase-si-supabase.md` | Por qué Supabase Auth y no Firebase |
