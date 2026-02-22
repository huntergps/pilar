# Seguridad


### Autenticacion y Autorizacion

#### Dos Aplicaciones Separadas

```
╔══════════════════════════════════════════════════════════════════════════╗
║  PILAR se compone de DOS aplicaciones independientes:                  ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  APP 1: PILAR ADMIN (Panel de Gestion SaaS)                           ║
║  ─────────────────────────────────────────                             ║
║  - Aplicacion web SEPARADA para el equipo de la empresa desarrolladora ║
║  - Gestionada por el personal de soporte/desarrollo                    ║
║  - Funcionalidades:                                                    ║
║    • Crear/suspender/eliminar empresas (tenants)                       ║
║    • Administrar planes y suscripciones                                ║
║    • Monitorear uso, cobros de suscripcion, estadisticas               ║
║    • Gestionar usuarios globales y asignarlos a empresas               ║
║    • Configuracion global de la plataforma                             ║
║    • Soporte tecnico (tickets, logs, diagnostico)                      ║
║    • Gestionar certificados digitales de las empresas                  ║
║  - Los usuarios del panel admin pueden acceder a cualquier empresa     ║
║    que se les asigne, con roles especificos por empresa                ║
║  - Identificado por: app_metadata.is_saas_admin = true                 ║
║  - Stack: Flutter Web (deploy en subdominio: admin.pilar.ec)           ║
║  - Misma base Supabase, diferente frontend                             ║
║                                                                        ║
║  APP 2: PILAR ERP (Aplicacion para Clientes)                          ║
║  ────────────────────────────────────────────                          ║
║  - Aplicacion multi-plataforma para las empresas clientes              ║
║  - Cada usuario puede pertenecer a MULTIPLES empresas                  ║
║  - En cada empresa tiene un ROL diferente                              ║
║  - Ejemplo: Maria es "contadora" en Empresa A y "vendedora" en B      ║
║  - Al iniciar sesion, elige la empresa activa (switch empresa)         ║
║  - El JWT se actualiza con empresa_id + rol de la empresa              ║
║  - NO tiene acceso al panel de administracion SaaS                     ║
║  - Stack: Flutter (Web + Android + iOS + Desktop)                      ║
║  - Deploy: app.pilar.ec (web) + stores (mobile)                       ║
║                                                                        ║
╠══════════════════════════════════════════════════════════════════════════╣
║  AMBAS APPS comparten:                                                 ║
║  - Misma instancia Supabase (PostgreSQL + Auth + Storage)              ║
║  - Mismas Edge Functions                                               ║
║  - Mismas tablas y RLS policies                                        ║
║  - Supabase Auth unificado (un usuario = una cuenta)                   ║
║  - La diferenciacion se hace por app_metadata.is_saas_admin            ║
╚══════════════════════════════════════════════════════════════════════════╝
```

#### Modelo de Datos - Roles y Permisos

```sql
-- ============================================
-- ROLES DEL SISTEMA (CREATE TABLE formal)
-- ============================================

CREATE TABLE roles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id),   -- NULL = rol global del sistema
  codigo          VARCHAR(50) NOT NULL,            -- 'ADMIN', 'CONTADOR', 'VENDEDOR', 'BODEGUERO'
  nombre          VARCHAR(100) NOT NULL,
  descripcion     TEXT,
  es_sistema      BOOLEAN DEFAULT false,           -- Roles predefinidos no editables
  activo          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, codigo)
);

ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON roles
  FOR ALL TO authenticated
  USING (empresa_id IS NULL OR empresa_id = (SELECT private.get_empresa_id()));

-- Permisos granulares por modulo y accion
CREATE TABLE permisos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo          VARCHAR(100) UNIQUE NOT NULL,    -- '<modulo>.<recurso>.<accion>'
  modulo          VARCHAR(50) NOT NULL,            -- nombre del módulo que registra el permiso
  recurso         VARCHAR(50) NOT NULL,            -- recurso dentro del módulo
  accion          VARCHAR(20) NOT NULL,            -- 'crear', 'ver', 'editar', 'eliminar', 'aprobar'
  descripcion     TEXT,
  es_sistema      BOOLEAN DEFAULT false
);

-- RELACION USUARIO ↔ EMPRESA ↔ ROL (multi-empresa)
CREATE TABLE usuarios_empresa (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      UUID NOT NULL REFERENCES auth.users(id),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  rol_id          UUID NOT NULL REFERENCES roles(id),
  activo          BOOLEAN DEFAULT true,
  fecha_ingreso   DATE DEFAULT CURRENT_DATE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(usuario_id, empresa_id)
);

ALTER TABLE usuarios_empresa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON usuarios_empresa
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Tabla pivote roles-permisos
CREATE TABLE roles_permisos (
  rol_id          UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permiso_id      UUID NOT NULL REFERENCES permisos(id) ON DELETE CASCADE,
  PRIMARY KEY (rol_id, permiso_id)
);

-- Indices para performance
CREATE INDEX idx_usuarios_empresa_user ON usuarios_empresa(usuario_id);
CREATE INDEX idx_usuarios_empresa_empresa ON usuarios_empresa(empresa_id);

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

-- Ejemplo permisos (formato: 'modulo.recurso.accion')
INSERT INTO permisos (codigo, modulo, recurso, accion, es_sistema) VALUES
  ('modulo_a.recurso_x.crear', 'modulo_a', 'recurso_x', 'crear', true),
  ('modulo_a.recurso_x.ver', 'modulo_a', 'recurso_x', 'ver', true),
  ('modulo_a.recurso_x.anular', 'modulo_a', 'recurso_x', 'anular', true),
  ('administracion.usuario.gestionar', 'administracion', 'usuario', 'gestionar', true);
  -- ... (se completa por módulo)

-- Asignar permisos a roles
INSERT INTO roles_permisos (rol_id, permiso_id) VALUES
  ('admin', 'modulo_a.recurso_x.crear'),
  ('admin', 'modulo_a.recurso_x.ver'),
  ('admin', 'administracion.usuario.gestionar');
  -- ... (se completa para cada rol)
```

#### Gestion de Sesiones de Usuario

Control de sesiones activas por usuario, con limite configurable y timeout por inactividad.

```sql
-- SESIONES DE USUARIO (tracking de dispositivos conectados)
CREATE TABLE sesiones_usuario (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      UUID NOT NULL REFERENCES auth.users(id),
  empresa_id      UUID REFERENCES empresas(id),
  dispositivo     TEXT,                   -- "Chrome 120 / macOS", "PILAR Android"
  ip_address      INET,
  user_agent      TEXT,
  inicio          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ultimo_acceso   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  activa          BOOLEAN NOT NULL DEFAULT true,
  token_id        TEXT                    -- Referencia al refresh token de Supabase Auth
);

CREATE INDEX idx_sesiones_usuario_user ON sesiones_usuario(usuario_id) WHERE activa = true;

-- Config en parametros_sistema:
-- max_sesiones_simultaneas: 5 (default)
-- timeout_inactividad_minutos: 30 (default)
```

```sql
-- RPC: Listar sesiones activas de un usuario
CREATE OR REPLACE FUNCTION get_active_sessions(p_usuario_id UUID)
RETURNS TABLE (
  session_id UUID, dispositivo TEXT, ip_address INET,
  inicio TIMESTAMPTZ, ultimo_acceso TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.dispositivo, s.ip_address, s.inicio, s.ultimo_acceso
  FROM sesiones_usuario s
  WHERE s.usuario_id = p_usuario_id AND s.activa = true
  ORDER BY s.ultimo_acceso DESC;
END;
$$;

-- RPC: Cerrar una sesion remota
CREATE OR REPLACE FUNCTION terminate_session(p_session_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Marcar sesion como inactiva
  UPDATE sesiones_usuario SET activa = false WHERE id = p_session_id;
  -- 2. Invalidar refresh token via Supabase Auth admin API (Edge Function)
  -- 3. El dispositivo sera forzado a re-autenticarse en su proximo request
  RETURN FOUND;
END;
$$;
```

#### Permisos a Nivel de Campo

Control granular de visibilidad y editabilidad de campos por rol y tabla.

```sql
-- PERMISOS POR CAMPO (control granular de formularios)
CREATE TABLE permisos_campo (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  rol_id          UUID NOT NULL REFERENCES roles(id),
  tabla           VARCHAR(100) NOT NULL,  -- Nombre de la tabla (definida por el módulo correspondiente)
  campo           VARCHAR(100) NOT NULL,  -- Campo de esa tabla
  visible         BOOLEAN NOT NULL DEFAULT true,
  editable        BOOLEAN NOT NULL DEFAULT true,
  UNIQUE(empresa_id, rol_id, tabla, campo)
);

ALTER TABLE permisos_campo ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON permisos_campo
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_permisos_campo_rol ON permisos_campo(empresa_id, rol_id, tabla);
```

```sql
-- RPC: Obtener permisos de campo para un rol en una tabla
CREATE OR REPLACE FUNCTION get_field_permissions(
  p_empresa_id UUID, p_rol_id UUID, p_tabla VARCHAR
)
RETURNS TABLE (campo VARCHAR, visible BOOLEAN, editable BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT pc.campo, pc.visible, pc.editable
  FROM permisos_campo pc
  WHERE pc.empresa_id = p_empresa_id
    AND pc.rol_id = p_rol_id
    AND pc.tabla = p_tabla;
END;
$$;

-- Flutter: los widgets consultan permisos al renderizar formularios.
-- Campos con visible=false se ocultan del formulario.
-- Campos con editable=false se muestran en modo read-only.
--
-- Cada módulo configura las restricciones de campo pertinentes a sus tablas
-- durante su proceso de activación (seed data en su migración).
```

#### Flujo de Autenticacion Multi-Empresa

```
1. LOGIN
   - Email/password via Supabase Auth
   - Se obtiene lista de empresas del usuario:
     SELECT ue.*, e.razon_social, r.nombre as rol_nombre
     FROM usuarios_empresa ue
     JOIN empresas e ON e.id = ue.empresa_id
     JOIN roles r ON r.id = ue.rol_id
     WHERE ue.user_id = auth.uid() AND ue.activo = true

2. SELECCIONAR EMPRESA (si tiene mas de una)
   - Pantalla de seleccion de empresa (si tiene >1)
   - Si solo tiene 1, entra directo

3. ACTUALIZAR JWT (app_metadata)
   - Edge Function actualiza app_metadata con empresa_id y rol:
     await supabase.auth.admin.updateUserById(userId, {
       app_metadata: {
         empresa_id: selectedEmpresaId,
         rol: selectedRole,
         permisos: [...permisosDelRol]
       }
     })
   - El JWT se regenera con los nuevos claims

4. VALIDACION EN FLUTTER
   - Riverpod provider lee permisos del JWT
   - App Launcher muestra solo modulos permitidos
   - Botones/acciones se muestran segun permisos
   - Si intenta acceder sin permiso → 403

5. SWITCH EMPRESA
   - Desde el menu de usuario, puede cambiar de empresa
   - Se repite paso 3 con la nueva empresa
   - La UI se recarga con datos de la nueva empresa
```

#### RLS con Roles

```sql
-- Policy que combina multi-tenancy + roles
-- Solo usuarios con permiso pueden ver registros de su empresa
CREATE POLICY "tenant_and_role" ON <tabla>
  FOR SELECT TO authenticated
  USING (
    empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid)
    AND 'modulo.recurso.ver' = ANY(
      ARRAY(SELECT jsonb_array_elements_text(
        (SELECT auth.jwt() -> 'app_metadata' -> 'permisos')
      ))
    )
  );

-- O mas simple: verificar solo empresa_id en RLS y permisos en el frontend/Edge Functions
-- (recomendado para rendimiento)
CREATE POLICY "tenant_isolation" ON <tabla>
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));
-- + Verificacion de permisos en el Riverpod provider (frontend)
-- + Verificacion de permisos en Edge Functions (backend)
```

#### PILAR ADMIN - Estructura de la App SaaS

```
pilar_admin/ (proyecto Flutter Web separado)
  lib/
    features/
      ├── dashboard/          # Metricas globales, graficos de uso
      ├── empresas/           # CRUD empresas (crear, suspender, configurar)
      │     ├── detalle/      # Detalle empresa (plan, modulos, usuarios, config)
      │     └── modulos/      # Activar/desactivar modulos por empresa
      ├── usuarios/           # Todos los usuarios del SaaS
      │     ├── listado/      # SfDataGrid con filtros
      │     ├── asignar/      # Asignar usuario a empresa con rol
      │     └── permisos/     # Ver permisos efectivos de un usuario
      ├── suscripciones/      # Planes, pagos, cobros SaaS
      │     ├── planes/       # CRUD planes (basico, profesional, enterprise)
      │     └── cobros/       # Historial de cobros y comprobantes de suscripcion
      ├── soporte/            # Tickets de soporte de las empresas
      │     ├── tickets/      # Listado y gestion de tickets
      │     └── diagnostico/  # Herramientas de diagnostico (logs, queries)
      └── configuracion/      # Parametros globales de la plataforma

-- RLS: Los saas_admin pueden ver TODAS las empresas
-- Los usuarios normales solo ven SU empresa activa
CREATE POLICY "empresa_access" ON empresas
  FOR ALL TO authenticated
  USING (
    (SELECT (auth.jwt() -> 'app_metadata' ->> 'is_saas_admin')::boolean) = true
    OR id = (SELECT private.get_empresa_id())
  );

-- Los saas_admin tambien pueden tener roles en empresas especificas
-- Esto permite que un soporte tecnico entre como "admin" de una empresa
-- para diagnosticar problemas sin necesitar un usuario separado
INSERT INTO usuarios_empresa (user_id, empresa_id, rol_id) VALUES
  ('<soporte_user_id>', '<empresa_cliente>', 'admin');
-- Cuando el saas_admin selecciona esa empresa, opera con permisos de admin
```

```
Supabase Auth:
  - Email/password + MFA (TOTP)
  - flutter_secure_storage para tokens en dispositivo
  - JWT con claims: empresa_id, rol, permisos, is_saas_admin
  - Refresh token automatico
```

### Proteccion de Datos Sensibles

```
- Archivos sensibles: Encriptados en Supabase Storage (AES-256)
  (NUNCA se descargan al dispositivo del usuario)
- Secretos: Encriptados en Vault (Supabase)
- Operaciones criptograficas: Solo en Edge Functions (server-side)
- Datos fiscales: Protegidos por RLS
- Comunicacion con servicios externos: HTTPS/TLS 1.3 desde Edge Functions
- Backups automaticos (Point-in-Time Recovery)
```

### Cumplimiento

```
- Cifrado en transito (TLS) y en reposo (AES-256)
- Audit log de todas las operaciones sensibles y financieras
- Retencion de documentos segun regulacion local vigente
- No eliminacion de documentos emitidos legalmente
```

## Cumplimiento de Privacidad de Datos

Las regulaciones de privacidad de datos varían por país. PILAR implementa controles genéricos compatibles con los principales marcos regulatorios (GDPR, LGPD, y equivalentes locales). Los módulos de localización pueden extender estos controles con requisitos específicos de cada jurisdicción.

### Cifrado de Columnas Sensibles (G-SEG-05) — P2

```
- Extension pgcrypto (disponible nativamente en Supabase)
- Columnas cifradas con AES-256 (datos de alta sensibilidad por módulo)
- Funciones: encrypt_sensitive(value TEXT) → BYTEA, decrypt_sensitive(encrypted BYTEA) → TEXT
- Clave de cifrado almacenada en Supabase Vault (schema supabase_vault)
- RLS asegura que solo roles autorizados puedan invocar decrypt_sensitive
- Datos se muestran enmascarados por defecto (ej: ****5678). Desenmascara solo con permiso explicito
```

### Backup Bajo Demanda y Exportacion de Datos (G-SEG-06) — P2

```sql
-- Edge Function: export-company-data
-- Genera JSON/CSV de todos los datos de una empresa
-- Almacena en Supabase Storage (bucket privado, expira en 24h)
-- Caso de uso: portabilidad de datos (cumplimiento regulatorio local), migracion, auditoria

CREATE OR REPLACE FUNCTION request_backup(p_empresa_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
-- 1. Valida que el usuario tiene rol admin en la empresa
-- 2. Invoca Edge Function export-company-data via pg_net
-- 3. Returns: {status: 'PROCESSING', download_url: NULL, estimated_minutes: N}
-- 4. Edge Function genera ZIP → sube a Storage → actualiza estado a COMPLETADO con URL
-- Nota: backups automaticos diarios son responsabilidad de Supabase (PITR).
--       Esta funcion es exportacion bajo demanda del usuario.
$$;
```

---

## Roles de PostgreSQL vs Roles de Negocio

Supabase/PostgreSQL tiene dos capas de roles completamente separadas que no deben confundirse:

### Capa 1 — Roles de PostgreSQL (transporte/acceso)

| Rol PG | Quién lo usa | Permisos |
|--------|-------------|---------|
| `anon` | Peticiones sin JWT (usuarios no autenticados) | Solo lectura de tablas públicas (si la policy lo permite) |
| `authenticated` | Peticiones con JWT válido de Supabase Auth | Acceso sujeto a las policies RLS de cada tabla |
| `service_role` | Edge Functions con `SUPABASE_SERVICE_ROLE_KEY` | Bypass total de RLS — acceso irrestricto a BD |

Estos roles son gestionados por Supabase y **no se modifican ni se crean roles PG adicionales** en PILAR. No corresponden a cargos ni jerarquías dentro de una empresa: son simplemente el "canal de transporte" que Supabase usa para saber qué nivel de acceso tiene una conexión entrante.

### Capa 2 — Roles de Negocio (tabla `roles`)

Son los roles de la aplicación: `SUPER_ADMIN`, `ADMIN`, `GERENTE`, `CONTADOR`, `FACTURADOR`, etc. (ver seed en esta misma sección).

- Se almacenan en la tabla `roles` (empresa_id = NULL para roles del sistema; empresa_id específico para roles personalizados por empresa).
- Se asignan via `usuarios_empresa` (un usuario puede tener un rol diferente en cada empresa).
- Las policies RLS los consultan a través de `private.has_permission('modulo.recurso.accion')`.
- Son completamente independientes de los roles PG: un usuario `authenticated` en PG puede tener el rol de negocio `CONTADOR` en empresa A y `VENDEDOR` en empresa B.

### Puente: Custom Claims via Auth Hook

El `app_metadata` del JWT conecta ambas capas sin exponer lógica de negocio al motor PG:

```
JWT (emitido por Supabase Auth)
├── app_metadata.empresa_id    → leído por private.get_empresa_id() en cada policy RLS
├── app_metadata.rol           → leído por private.has_permission() para verificar permisos
├── app_metadata.permisos      → array de códigos de permiso del rol activo
└── app_metadata.is_saas_admin → leído por private.is_saas_admin() para acceso multi-empresa
```

Solo el `service_role` puede escribir en `app_metadata` (vía Supabase Auth Admin API). El usuario final no puede modificar estos valores desde el frontend, lo que garantiza el aislamiento multi-tenant.

```sql
-- Cómo una policy RLS usa ambas capas conjuntamente:
-- El rol PG 'authenticated' determina QUÉ policy aplica.
-- El claim app_metadata.empresa_id determina QUÉ filas ve.
CREATE POLICY "ejemplo_combinado" ON facturas
  FOR SELECT
  TO authenticated                                            -- capa PG
  USING (empresa_id = (SELECT private.get_empresa_id()));    -- capa negocio (via JWT claim)
```

### Regla práctica

| Contexto | Rol PG | Rol de negocio aplicable |
|----------|--------|--------------------------|
| Flutter frontend (usuario logueado) | `authenticated` | El rol asignado en `usuarios_empresa` para la empresa activa |
| Flutter frontend (sin sesión) | `anon` | Ninguno — solo tablas públicas |
| Edge Function con JWT del usuario | `authenticated` | Igual que el frontend |
| Edge Function con SERVICE_ROLE_KEY | `service_role` | Ninguno (bypass RLS) — la función debe implementar su propia verificación |
| Webhook externo (Kushki, SRI, etc.) | `service_role` | Ninguno — la Edge Function verifica firma del proveedor |

**Reglas de seguridad críticas:**
- Nunca exponer `SUPABASE_SERVICE_ROLE_KEY` en el frontend (Flutter). Usar siempre la `anon` key pública.
- Las Edge Functions con `service_role` deben implementar su propia lógica de autorización porque RLS no aplica para ellas.
- El `app_metadata` es de solo escritura para el backend: el cliente puede leerlo desde el JWT pero no modificarlo.

