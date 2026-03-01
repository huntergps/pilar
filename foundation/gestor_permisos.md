# Gestor de Roles y Permisos — Foundation Layer

## Resumen

El gestor de roles y permisos es un **servicio transversal de foundation** que controla qué acciones puede ejecutar cada usuario dentro de su empresa. Implementado como pantalla en el módulo de Administración (`GestorPermisosScreen`), permite a los administradores de empresa configurar roles y asignar permisos de forma granular sin salir del ERP.

Basado en el modelo **RBAC (Role-Based Access Control)** con jerarquía de 3 niveles y soporte de roles globales (sistema) y roles personalizados por empresa.

---

## Arquitectura

```
Foundation (Core Services)
├── Tabla: roles                ← Catálogo de roles (globales + por empresa)
├── Tabla: permisos             ← Catálogo de permisos con jerarquía 3 niveles
├── Tabla: roles_permisos       ← Asignación permiso ↔ rol
├── Tabla: usuarios_empresa_roles ← Asignación usuario ↔ rol (por empresa)
├── custom_access_token_hook    ← Inyecta empresa_id + rol + permisos en JWT
└── private.has_permission()    ← Guard en RPCs y RLS policies

Módulo Administración
└── GestorPermisosScreen        ← UI CRUD de roles y asignación de permisos
```

---

## Modelos de Datos

### Tabla `roles`

```sql
CREATE TABLE roles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      VARCHAR(50) UNIQUE NOT NULL,   -- ej: 'ADMIN', 'VENDEDOR', 'CONTADOR'
  nombre      VARCHAR(100) NOT NULL,
  descripcion TEXT,
  es_sistema  BOOLEAN NOT NULL DEFAULT false, -- true = global (no editable por empresa)
  empresa_id  UUID REFERENCES empresas(id),   -- NULL = global
  activo      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

**Roles del sistema (globales, `es_sistema = true`, `empresa_id = NULL`)**:

| Código | Nombre | Descripción |
|--------|--------|-------------|
| `SUPER_ADMIN` | Super Administrador | Acceso total. Solo para SaaS admin. |
| `ADMIN` | Administrador | Acceso completo a la empresa. |
| `GERENTE` | Gerente | Lectura global + aprobaciones. |
| `VENDEDOR` | Vendedor | Cotizaciones, OV, cobros básicos. |
| `FACTURADOR` | Facturador | Facturas, NC, ND, cobros. |
| `CONTADOR` | Contador | Asientos, declaraciones, reportes. |
| `COMPRADOR` | Comprador | OC, proveedores, retenciones. |
| `BODEGUERO` | Bodeguero | Inventario, guías, movimientos. |
| `CAJERO` | Cajero | POS, cobros, caja chica. |
| `LECTURA` | Solo Lectura | Visualización sin mutación. |
| `SAAS_ADMIN` | Administrador SaaS | Gestión multi-empresa (nivel plataforma). |

Los roles de sistema son **inmutables** desde la UI. Solo son visibles como referencia para copiar o asignar a usuarios.

### Tabla `permisos`

```sql
CREATE TABLE permisos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      VARCHAR(100) UNIQUE NOT NULL,  -- ej: 'ventas.ordenes.crear'
  modulo      VARCHAR(50) NOT NULL,           -- ej: 'ventas'
  recurso     VARCHAR(50) NOT NULL,           -- ej: 'ordenes'
  accion      VARCHAR(50) NOT NULL,           -- ej: 'crear' | 'menu' | 'ejecutar'
  descripcion TEXT,
  nivel       SMALLINT NOT NULL DEFAULT 1 CHECK (nivel BETWEEN 0 AND 2),
  parent_id   UUID REFERENCES permisos(id),   -- parent = ítem de menú (nivel=0)
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### Jerarquía de 3 Niveles

| Nivel | `accion` | Descripción | Ejemplo |
|-------|----------|-------------|---------|
| **0** | `menu` | Visibilidad del ítem de menú/navegación | `ventas.ordenes.menu` |
| **1** | `listar` / `crear` / `editar` / `eliminar` / `inactivar` | CRUD sobre la tabla | `ventas.ordenes.crear` |
| **2** | `ejecutar` | Sub-acción granular | `ventas.ordenes.aprobar_descuento` |

**Convención de códigos**: `<modulo>.<recurso>.<accion>`

Ejemplos:
- `administracion.empresa.menu` — ver el menú de empresa en Administración
- `administracion.roles.ver` — listar roles y permisos
- `administracion.roles.gestionar` — crear/editar/eliminar roles y asignar permisos
- `ventas.ordenes.menu` — ver el ítem "Órdenes de Venta" en el sidebar
- `ventas.ordenes.crear` — crear una OV
- `ventas.ordenes.aprobar_descuento` — aprobar descuentos > umbral

---

## RPCs

Todas requieren el permiso correspondiente. Las verificaciones están en `private.has_permission()`.

| Función | Permiso requerido | Descripción |
|---------|------------------|-------------|
| `admin_get_roles()` | `administracion.roles.ver` | Lista todos los roles visibles (globales + propios de la empresa). |
| `admin_get_permisos_rol(p_rol_id UUID)` | `administracion.roles.ver` | Catálogo completo de permisos con flag `tiene_permiso` para el rol dado. Incluye `nivel` y `parent_id`. |
| `admin_get_usuarios_rol(p_rol_id UUID)` | `administracion.roles.ver` | Lista usuarios de la empresa que tienen asignado el rol dado. |
| `admin_toggle_permiso_rol(p_rol_id UUID, p_permiso_id UUID, p_otorgar BOOLEAN)` | `administracion.roles.gestionar` | Otorga o revoca un permiso a un rol de empresa. Bloquea roles de sistema (`es_sistema = true`). |
| `admin_toggle_usuario_rol(p_usuario_id UUID, p_rol_id UUID, p_asignar BOOLEAN)` | `administracion.roles.gestionar` | Asigna o retira un rol a un usuario en la empresa activa. |

---

## Flujo JWT — Permisos en Token

El `custom_access_token_hook` (migración `018_auth_hook.sql`) inyecta en cada JWT:

```json
{
  "app_metadata": {
    "empresa_id": "...",
    "rol_codigo": "ADMIN",
    "rol_nombre": "Administrador",
    "permisos": ["administracion.empresa.menu", "administracion.roles.ver", "ventas.ordenes.menu", "..."]
  }
}
```

Los permisos en el JWT son un **array plano de códigos**. Para verificar acceso:

```dart
// Flutter — guard de UI
final permisos = session.user.appMetadata['permisos'] as List<dynamic>? ?? [];
if (!permisos.contains('ventas.ordenes.crear')) { ... }
```

```sql
-- PostgreSQL — guard de RPC
IF NOT private.has_permission('ventas.ordenes.crear') THEN
  RAISE EXCEPTION 'permission_denied';
END IF;
```

**Importante**: los permisos se leen del JWT (cached). Tras modificar permisos de un usuario, este debe cerrar sesión y volver a entrar (o el admin debe invalidar la sesión) para que el nuevo JWT refleje los cambios.

---

## Pantalla Flutter — `GestorPermisosScreen`

**Ruta**: `/admin/permisos`
**Archivo**: `lib/features/administracion/screens/gestor_permisos_screen.dart`
**Permiso de acceso**: `administracion.roles.ver`

### Layout (3 paneles)

```
┌────────────────┬──────────────────────────────────────┬─────────────────────────────┐
│  Lista Roles   │         Permisos del Rol              │    Usuarios con este Rol    │
│  (≥900px)      │  (SfDataGrid jerarquía 3 niveles)    │    (lista usuarios)         │
├────────────────┤                                        │                             │
│ • ADMIN     ✅ │  Módulo: Ventas                       │  👤 Erik Salazar            │
│ • VENDEDOR  ✅ │  ├── ventas.ordenes.menu  [menú] ✅   │  👤 Steven Hunter           │
│ • CONTADOR  ✅ │  ├── ventas.ordenes.listar [CRUD] ✅  │                             │
│ • [+ Crear]   │  ├── ventas.ordenes.crear [CRUD] ✅   │  [+ Asignar usuario]        │
│                │  └── ventas.ordenes.aprobar [ejec] ✅ │  [− Quitar usuario]         │
└────────────────┴──────────────────────────────────────┴─────────────────────────────┘
```

En pantallas `<900px`: vista de un solo panel con navegación por pestañas.

### Providers

| Provider | Tipo | Descripción |
|----------|------|-------------|
| `rolesAdminProvider` | `FutureProvider<List<RolItem>>` | Carga roles via `admin_get_roles()`. |
| `permisosRolProvider(rolId)` | `FutureProvider.family<List<PermisoEstado>, String>` | Permisos del rol con flag `tienePermiso`. |
| `usuariosRolProvider(rolId)` | `FutureProvider.family<List<UsuarioRolItem>, String>` | Usuarios con el rol asignado. |
| `_rolSeleccionadoProvider` | `StateProvider<RolItem?>` | Rol actualmente seleccionado en la lista. |

### Modelos

```dart
class RolItem {
  final String id, codigo, nombre;
  final String? descripcion, empresaId;
  final bool esSistema, activo;
}

class PermisoEstado {
  final String id, codigo, modulo, recurso, accion;
  final String? descripcion, parentId;
  final int nivel;     // 0=menu | 1=CRUD | 2=sub-acción
  bool tienePermiso;
}

class UsuarioRolItem {
  final String usuarioId, nombre, email;
}
```

### Visualización de permisos por nivel

La tabla de permisos agrupa por módulo y recurso, mostrando filas diferenciadas:

| Tipo de fila | Columnas activas | Color fondo |
|---|---|---|
| **Nivel 0** (menú) | Sólo columna `menú` | Gris claro |
| **Nivel 1** (CRUD) | `listar` / `crear` / `editar` / `eliminar` / `inactivar` | Blanco |
| **Nivel 2** (ejecutar) | Sólo columna `ejecutar` | Azul muy claro |

Roles con `es_sistema = true` muestran permisos en **solo lectura** (switches deshabilitados).

---

## Convenciones

- **Roles de sistema**: no se pueden editar ni eliminar desde la UI. Son plantillas de referencia.
- **Roles de empresa**: empresa_id = empresa activa. Solo visibles y editables por el admin de esa empresa.
- **Mínimo viable**: todo usuario debe tener al menos un rol. `has_permission()` retorna false si no tiene ninguno.
- **ADMIN y SUPER_ADMIN**: siempre tienen todos los permisos. Cualquier migración que inserte permisos nuevos debe asignarlos automáticamente a estos roles.
- **Patrón en migración**: al crear permisos nuevos, siempre asignar a ADMIN y SUPER_ADMIN:

```sql
INSERT INTO public.roles_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN public.permisos p
WHERE r.codigo IN ('ADMIN', 'SUPER_ADMIN')
  AND p.codigo IN ('nuevo.permiso.codigo')
ON CONFLICT DO NOTHING;
```

---

## Migraciones

| Migración | Descripción |
|-----------|-------------|
| `20260101000053_admin_roles_rpcs.sql` | RPCs base: `admin_get_roles`, `admin_get_permisos_rol`, `admin_get_usuarios_rol`. |
| `20260101000054_roles_permisos_empresa.sql` | Soporte de roles personalizados por empresa (empresa_id en roles). |
| `20260101000055_permisos_nivel_parent.sql` | Añade columnas `nivel` (0/1/2) y `parent_id` a `permisos`. Actualiza `admin_get_permisos_rol`. |
| `20260101000056_permisos_infraestructura_v2.sql` | Permisos de los módulos de infraestructura con esquema de 3 niveles. |
| `20260101000057_fix_permission_guards_v2.sql` | Corrige guards en RPCs existentes para usar `administracion.roles.ver`. |
| `20260101000058_fix_permission_guards_v3.sql` | Ajustes finales de guards y permisos de `dashboard.menu`. |
