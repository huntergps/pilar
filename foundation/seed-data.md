# Seed Data — PILAR ERP

> Fuente única de verdad para los datos iniciales del sistema. Define qué se carga en la base de datos antes de que cualquier empresa comience a operar.
> Última revisión: 2026-02-19

---

## Índice

1. [Introducción](#1-introducción)
2. [Seed: Roles del sistema](#2-seed-roles-del-sistema)
3. [Seed: Permisos granulares](#3-seed-permisos-granulares)
4. [Seed: Asignación de permisos a roles](#4-seed-roles_permisos)
5. [Seed: Unidades de medida](#5-seed-unidades-de-medida)
6. [Seed: Parámetros del sistema](#6-seed-parámetros-del-sistema)
7. [Catálogos externos (migraciones separadas)](#7-catálogos-externos)
8. [Procedimiento de actualización](#8-procedimiento-de-actualización)

---

## 1. Introducción

### Qué es este archivo

Este documento es la **fuente de verdad** para el seed data global de PILAR: todos los registros que deben existir en la base de datos antes de que cualquier empresa comience a operar. No incluye datos de empresa ni datos de usuario; solo registros del sistema (roles, permisos, módulos, unidades de medida, parámetros) que son iguales para todas las instancias.

El seed data que depende de normativa local (tarifas impositivas, retenciones, parámetros de seguridad social) se documenta en los módulos de extensión correspondientes — no en foundation.

### Cuándo se cargan los datos

Los seeds se aplican en el orden de las migraciones ensambladas por `./scripts/build-supabase.sh`. El código fuente de foundation vive en `foundation/migrations/`; cada módulo tiene su propio directorio de migraciones. El directorio `supabase/migrations/` es **generado** y no se edita directamente.

```
foundation/migrations/
├── 001_core.sql             -- 16 tablas base: empresas, roles, permisos, módulos, secuencias
├── 002_functions.sql        -- private.get_empresa_id(), has_permission(), trigger auth
├── 003_seed_roles.sql       -- 11 roles del sistema + 18 permisos de infraestructura
├── 004_seed_modules.sql     -- 4 planes SaaS + 24 módulos + dependencias + catálogos
└── 005_helpers.sql          -- check_permission(), Storage buckets
```

Los catálogos globales voluminosos (países, monedas, UoM) se almacenan como migraciones adicionales en `foundation/migrations/`. Los catálogos específicos de un país (bancos, provincias, tarifas tributarias) van en las migraciones del módulo de extensión correspondiente — no en foundation.

### Convención de nomenclatura

- `foundation/003_seed_roles.sql` — roles del sistema + permisos de infraestructura (dashboard, administracion, comunicacion).
- Cada módulo incluye su propio archivo `NNN_seed_permissions.sql` — permisos específicos de ese módulo + asignaciones a roles. Se carga **sólo si el módulo está en el build**.
- Los seeds de catálogos externos muy voluminosos van en archivos separados para facilitar su mantenimiento independiente.
- Los seeds de normativa local (IVA, retenciones, parámetros fiscales) se definen en las migraciones del módulo de extensión correspondiente — no en foundation.
- Todos los seeds usan `ON CONFLICT ... DO NOTHING` o `DO UPDATE` para ser idempotentes (re-ejecutables sin error).

---

## 2. Seed: Roles del Sistema

Los roles del sistema tienen `empresa_id = NULL` y `es_sistema = true`. No son editables por las empresas. Una empresa puede crear roles personalizados (con su propio `empresa_id`), pero los roles de sistema siempre estarán disponibles.

**Archivo:** `supabase/migrations/001_seed_roles.sql`

```sql
-- =============================================================================
-- SEED: Roles del sistema PILAR
-- Todos con empresa_id = NULL (globales) y es_sistema = true (no editables)
-- =============================================================================

INSERT INTO roles (id, empresa_id, codigo, nombre, descripcion, es_sistema)
VALUES
  -- -------------------------------------------------------------------------
  -- Plataforma PILAR (uso interno del equipo PILAR, no disponible para clientes)
  -- -------------------------------------------------------------------------
  (
    gen_random_uuid(),
    NULL,
    'SUPER_ADMIN',
    'Super Administrador',
    'Acceso total a todas las empresas y configuración de la plataforma PILAR. Solo para el equipo interno.',
    true
  ),

  -- -------------------------------------------------------------------------
  -- Administración de empresa
  -- -------------------------------------------------------------------------
  (
    gen_random_uuid(),
    NULL,
    'SAAS_ADMIN',
    'Administrador SaaS',
    'Gestiona la cuenta SaaS: facturación, módulos activos, límites del plan. Sin acceso a datos operativos.',
    true
  ),
  (
    gen_random_uuid(),
    NULL,
    'ADMIN',
    'Administrador de Empresa',
    'Acceso completo a todos los módulos activos. Gestiona usuarios, roles, configuración y certificados digitales.',
    true
  ),
  (
    gen_random_uuid(),
    NULL,
    'GERENTE',
    'Gerente',
    'Acceso a reportes gerenciales, dashboards, aprobaciones de documentos y KPIs. Sin acceso a configuración del sistema.',
    true
  ),

  -- -------------------------------------------------------------------------
  -- Roles operativos (acceso limitado a los módulos de su competencia)
  -- -------------------------------------------------------------------------
  (
    gen_random_uuid(),
    NULL,
    'CONTADOR',
    'Contador',
    'Contabilidad, tesorería, tributación y reportes financieros. Puede cerrar períodos y generar declaraciones fiscales.',
    true
  ),
  (
    gen_random_uuid(),
    NULL,
    'FACTURADOR',
    'Facturador',
    'Emisión de facturas, notas de crédito/débito, cobranzas y gestión de clientes. Sin acceso a configuración contable.',
    true
  ),
  (
    gen_random_uuid(),
    NULL,
    'VENDEDOR',
    'Vendedor',
    'Cotizaciones, órdenes de venta y clientes asignados. Acceso a CRM si el módulo está activo.',
    true
  ),
  (
    gen_random_uuid(),
    NULL,
    'COMPRADOR',
    'Comprador',
    'Órdenes de compra, recepción de mercadería y gestión de proveedores. Puede emitir retenciones.',
    true
  ),
  (
    gen_random_uuid(),
    NULL,
    'BODEGUERO',
    'Bodeguero',
    'Control de stock: movimientos, transferencias entre ubicaciones y despachos.',
    true
  ),
  (
    gen_random_uuid(),
    NULL,
    'CAJERO',
    'Cajero',
    'Operaciones de caja: cobros, pagos y arqueos de efectivo.',
    true
  ),

  -- -------------------------------------------------------------------------
  -- Solo lectura
  -- -------------------------------------------------------------------------
  (
    gen_random_uuid(),
    NULL,
    'LECTURA',
    'Solo Lectura',
    'Ver registros en todos los módulos activos. Sin crear, editar ni eliminar.',
    true
  )

ON CONFLICT (empresa_id, codigo) DO NOTHING;
-- NOTA: el UNIQUE es (empresa_id, codigo); para empresa_id NULL usar:
-- ON CONFLICT ON CONSTRAINT roles_empresa_id_codigo_key DO NOTHING
```

### Resumen de roles

| Rol | Tipo | Uso |
|-----|------|-----|
| `SUPER_ADMIN` | Plataforma | Solo equipo PILAR. Accede a todas las empresas. |
| `SAAS_ADMIN` | Empresa | Gestión de cuenta SaaS, sin datos operativos. |
| `ADMIN` | Empresa | Administrador completo de la empresa. |
| `GERENTE` | Empresa | Reportes, aprobaciones, KPIs. Sin config de sistema. |
| `CONTADOR` | Operativo | Contabilidad, tesorería, tributación. |
| `FACTURADOR` | Operativo | Facturación, cobros, clientes. |
| `VENDEDOR` | Operativo | Cotizaciones, órdenes de venta, CRM. |
| `COMPRADOR` | Operativo | Compras, recepción, retenciones. |
| `BODEGUERO` | Operativo | Inventario, transferencias, guías. |
| `CAJERO` | Operativo | POS exclusivamente. |
| `LECTURA` | Transversal | Ver todo, modificar nada. |

---

## 3. Seed: Permisos Granulares

Los permisos siguen el patrón `modulo.recurso.accion`. A diferencia de un monolito, **cada módulo es responsable de su propio seed de permisos**: los permisos se insertan sólo cuando ese módulo está incluido en el build.

### Modelo distribuido

| Ubicación | Contenido |
|-----------|-----------|
| `foundation/migrations/003_seed_roles.sql` | 18 permisos de infraestructura (dashboard, administracion, comunicacion) |
| `<modulo>/migrations/NNN_seed_permissions.sql` (core) | Permisos propios del módulo core |
| `<modulo>/migrations/NNN_seed_permissions.sql` (extensión) | Permisos propios del módulo extensión |

> **Ventaja**: si un módulo no está activo, sus permisos nunca existen en la BD — no hay permisos huérfanos.

### Estructura de cada `NNN_seed_permissions.sql`

Patrón estándar que sigue cada archivo:

```sql
-- =============================================================================
-- SEED: Permisos del módulo <nombre>
-- =============================================================================

-- PARTE 1: Insertar permisos del módulo
INSERT INTO permisos (id, codigo, nombre, modulo) VALUES
  (gen_random_uuid(), '<modulo>.recurso.ver',      'Ver ...',    '<modulo>'),
  (gen_random_uuid(), '<modulo>.recurso.crear',    'Crear ...',  '<modulo>'),
  -- ...
ON CONFLICT (codigo) DO NOTHING;

-- PARTE 2: ADMIN y SUPER_ADMIN reciben todos los permisos del módulo
INSERT INTO roles_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM roles r
JOIN permisos p ON p.modulo = '<modulo>'
WHERE r.codigo IN ('ADMIN', 'SUPER_ADMIN') AND r.empresa_id IS NULL
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

-- PARTE 3: SAAS_ADMIN sólo acciones 'ver'
INSERT INTO roles_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM roles r
JOIN permisos p ON p.modulo = '<modulo>' AND p.accion = 'ver'
WHERE r.codigo = 'SAAS_ADMIN' AND r.empresa_id IS NULL
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

-- PARTE 4: Roles operativos específicos del módulo
INSERT INTO roles_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM roles r
JOIN permisos p ON p.codigo IN (
  '<modulo>.recurso.ver',
  '<modulo>.recurso.crear'
  -- sólo los permisos que corresponden al rol
)
WHERE r.codigo = 'ROL_OPERATIVO' AND r.empresa_id IS NULL
ON CONFLICT (rol_id, permiso_id) DO NOTHING;
```

### Convención de archivo por módulo

Cada módulo define su seed de permisos en un archivo `NNN_seed_permissions.sql` dentro de su directorio de migraciones. Foundation define los permisos de infraestructura en `foundation/migrations/003_seed_roles.sql`.

> Los módulos que no tienen acciones configurables por rol no necesitan archivo de permisos.

---

## 4. Seed: roles_permisos

La asignación de permisos a roles sigue el mismo modelo distribuido: **cada módulo asigna sus propios permisos a los roles del sistema** dentro de su `NNN_seed_permissions.sql`.

### Patrones de asignación por rol

Todos los archivos `NNN_seed_permissions.sql` siguen el mismo conjunto de patrones:

| Rol | Patrón |
|-----|--------|
| `ADMIN`, `SUPER_ADMIN` | `JOIN permisos p ON p.modulo = '<modulo>'` — todos los permisos del módulo |
| `SAAS_ADMIN` | `p.modulo = '<modulo>' AND p.accion = 'ver'` — sólo lectura |
| `GERENTE` | `p.accion IN ('ver', 'exportar', 'aprobar')` + permisos específicos de gestión |
| `LECTURA` | `p.modulo = '<modulo>' AND p.accion = 'ver'` |
| Rol operativo | Lista explícita `p.codigo IN (...)` según responsabilidades del módulo |

### Roles operativos por módulo

Cada módulo asigna sus permisos a los roles operativos que correspondan dentro de su propio archivo `NNN_seed_permissions.sql`. Los roles del sistema (FACTURADOR, VENDEDOR, COMPRADOR, BODEGUERO, CAJERO, CONTADOR) están definidos en foundation como roles disponibles; cada módulo decide qué permisos asignarles.

> Los roles operativos y sus permisos específicos se documentan en el `module.md` de cada módulo.

### Foundation: asignaciones transversales (infraestructura)

Las asignaciones de permisos de infraestructura (dashboard, administracion, comunicacion) están en `foundation/migrations/003_seed_roles.sql`:

```sql
-- ADMIN/SUPER_ADMIN: todos los permisos existentes (incluye los que se van agregando con cada módulo)
INSERT INTO roles_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permisos p
WHERE r.codigo IN ('ADMIN', 'SUPER_ADMIN') AND r.empresa_id IS NULL
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

-- SAAS_ADMIN: sólo permisos de administración de cuenta SaaS
INSERT INTO roles_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM roles r
JOIN permisos p ON p.codigo IN (
  'administracion.empresa.ver',
  'administracion.empresa.editar',
  'administracion.usuarios.ver',
  'administracion.usuarios.gestionar',
  'administracion.modulos.gestionar',
  'administracion.integraciones.gestionar',
  'dashboard.kpis.ver'
)
WHERE r.codigo = 'SAAS_ADMIN' AND r.empresa_id IS NULL
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

-- Roles operativos: sus permisos se asignan en el NNN_seed_permissions.sql de cada módulo.
-- Ver sección "Roles operativos por módulo" arriba para el detalle completo.
```

---

## 5. Seed: Unidades de Medida

Las unidades de medida (UoM) son globales del sistema. Cada unidad pertenece a una categoría y tiene un factor de conversión a la unidad base de su categoría (la unidad base siempre tiene `factor = 1.000000`).

**Archivo:** `supabase/migrations/001_seed_uom.sql`

```sql
-- =============================================================================
-- SEED: Categorías de unidades de medida
-- =============================================================================

INSERT INTO categorias_uom (id, nombre, tipo) VALUES
  ('uom_unidad',    'Unidad',        'UNIDAD'),
  ('uom_peso',      'Peso',          'PESO'),
  ('uom_volumen',   'Volumen',       'VOLUMEN'),
  ('uom_longitud',  'Longitud',      'LONGITUD'),
  ('uom_area',      'Área',          'AREA'),
  ('uom_tiempo',    'Tiempo',        'TIEMPO'),
  ('uom_digital',   'Digital',       'DIGITAL')
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- SEED: Unidades de medida
-- factor_conversion: cuántas unidades base equivale a 1 de esta unidad
--   Ejemplo: 1 docena = 12 und → factor = 12.000000
--            1 gramo  = 0.001 kg → factor = 0.001000
-- =============================================================================

INSERT INTO unidades_medida
  (id, categoria_id, nombre, abreviatura, factor_conversion, es_base, activo)
VALUES

  -- ---------------------------------------------------------------------------
  -- UNIDAD (base: und)
  -- ---------------------------------------------------------------------------
  ('uom_und',        'uom_unidad',   'Unidad',        'und',  1.000000, true,  true),
  ('uom_par',        'uom_unidad',   'Par',            'par',  2.000000, false, true),
  ('uom_docena',     'uom_unidad',   'Docena',         'doc',  12.00000, false, true),
  ('uom_ciento',     'uom_unidad',   'Ciento',         'cto',  100.0000, false, true),
  ('uom_millar',     'uom_unidad',   'Millar',         'mil',  1000.000, false, true),
  ('uom_caja',       'uom_unidad',   'Caja',           'caj',  1.000000, false, true),
  -- La caja no tiene factor fijo; se configura por producto en producto_presentaciones

  -- ---------------------------------------------------------------------------
  -- PESO (base: kg)
  -- ---------------------------------------------------------------------------
  ('uom_kg',         'uom_peso',     'Kilogramo',      'kg',   1.000000, true,  true),
  ('uom_gramo',      'uom_peso',     'Gramo',          'g',    0.001000, false, true),
  ('uom_mg',         'uom_peso',     'Miligramo',      'mg',   0.000001, false, true),
  ('uom_libra',      'uom_peso',     'Libra',          'lb',   0.453592, false, true),
  ('uom_onza',       'uom_peso',     'Onza',           'oz',   0.028350, false, true),
  ('uom_tonelada',   'uom_peso',     'Tonelada',       'tn',   1000.000, false, true),
  ('uom_quintal',    'uom_peso',     'Quintal',        'qq',   45.35920, false, true),

  -- ---------------------------------------------------------------------------
  -- VOLUMEN (base: litro)
  -- ---------------------------------------------------------------------------
  ('uom_litro',      'uom_volumen',  'Litro',          'l',    1.000000, true,  true),
  ('uom_mililitro',  'uom_volumen',  'Mililitro',      'ml',   0.001000, false, true),
  ('uom_galon',      'uom_volumen',  'Galón',          'gal',  3.785410, false, true),
  ('uom_cuarto',     'uom_volumen',  'Cuarto de galón','qt',   0.946353, false, true),
  ('uom_metro3',     'uom_volumen',  'Metro cúbico',   'm³',   1000.000, false, true),
  ('uom_cm3',        'uom_volumen',  'Centímetro cúbico','cm³',0.000001, false, true),

  -- ---------------------------------------------------------------------------
  -- LONGITUD (base: metro)
  -- ---------------------------------------------------------------------------
  ('uom_metro',      'uom_longitud', 'Metro',          'm',    1.000000, true,  true),
  ('uom_centimetro', 'uom_longitud', 'Centímetro',     'cm',   0.010000, false, true),
  ('uom_milimetro',  'uom_longitud', 'Milímetro',      'mm',   0.001000, false, true),
  ('uom_pie',        'uom_longitud', 'Pie',            'ft',   0.304800, false, true),
  ('uom_pulgada',    'uom_longitud', 'Pulgada',        'in',   0.025400, false, true),
  ('uom_yarda',      'uom_longitud', 'Yarda',          'yd',   0.914400, false, true),
  ('uom_km',         'uom_longitud', 'Kilómetro',      'km',   1000.000, false, true),

  -- ---------------------------------------------------------------------------
  -- ÁREA (base: metro cuadrado)
  -- ---------------------------------------------------------------------------
  ('uom_m2',         'uom_area',     'Metro cuadrado', 'm²',   1.000000, true,  true),
  ('uom_cm2',        'uom_area',     'Centímetro cuadrado','cm²',0.0001, false, true),
  ('uom_ha',         'uom_area',     'Hectárea',       'ha',   10000.00, false, true),

  -- ---------------------------------------------------------------------------
  -- TIEMPO (base: hora)
  -- ---------------------------------------------------------------------------
  ('uom_hora',       'uom_tiempo',   'Hora',           'h',    1.000000, true,  true),
  ('uom_minuto',     'uom_tiempo',   'Minuto',         'min',  0.016667, false, true),
  ('uom_dia',        'uom_tiempo',   'Día',            'día',  8.000000, false, true),
  -- día laboral = 8 horas (jornada estándar); para días calendario usar factor 24
  ('uom_semana',     'uom_tiempo',   'Semana',         'sem',  40.00000, false, true),
  ('uom_mes',        'uom_tiempo',   'Mes',            'mes',  160.0000, false, true),
  ('uom_anio',       'uom_tiempo',   'Año',            'año',  1920.000, false, true),

  -- ---------------------------------------------------------------------------
  -- DIGITAL (base: megabyte)
  -- ---------------------------------------------------------------------------
  ('uom_mb',         'uom_digital',  'Megabyte',       'MB',   1.000000, true,  true),
  ('uom_kb',         'uom_digital',  'Kilobyte',       'KB',   0.000977, false, true),
  ('uom_gb',         'uom_digital',  'Gigabyte',       'GB',   1024.000, false, true),
  ('uom_tb',         'uom_digital',  'Terabyte',       'TB',   1048576., false, true)

ON CONFLICT (id) DO UPDATE SET
  nombre            = EXCLUDED.nombre,
  abreviatura       = EXCLUDED.abreviatura,
  factor_conversion = EXCLUDED.factor_conversion,
  es_base           = EXCLUDED.es_base;
```

---

## 6. Seed: Parámetros del Sistema

Los parámetros del sistema se almacenan en `parametros_sistema` con `clave` única y `categoria` para agruparlos. Son globales (sin `empresa_id`): aplican igual para todas las instancias.

Los parámetros se dividen en dos grupos según su origen:

| Categoría | Archivo fuente | Descripción |
|-----------|---------------|-------------|
| `SISTEMA` | `foundation/migrations/` | Configuración de comportamiento PILAR (vigencias, decimales, límites de UI). Se carga siempre. |
| `IESS`, `LABORAL`, `SRI`, `FINANCIERO` | migraciones del módulo de extensión fiscal correspondiente | Parámetros de cumplimiento local. Solo se cargan cuando el módulo de extensión está incluido en el build. |

### Parámetros de categoría `SISTEMA` (foundation — siempre activos)

**Archivo:** `foundation/migrations/` (parte de `001_core.sql` o migración de seed foundation)

```sql
-- =============================================================================
-- SEED: Parámetros del sistema — Configuración PILAR (country-agnostic)
-- =============================================================================

INSERT INTO parametros_sistema (clave, valor, descripcion, categoria, vigente_desde) VALUES

  ('sistema_dias_vencimiento_cotizacion',
   '30',
   'Días de vigencia predeterminados para cotizaciones/proformas',
   'SISTEMA',
   '2024-01-01'),

  ('sistema_dias_aviso_vencimiento_factura',
   '5',
   'Días de anticipación para alertar sobre documentos próximos a vencer',
   'SISTEMA',
   '2024-01-01'),

  ('sistema_dias_aviso_vencimiento_certificado',
   '30',
   'Días de anticipación para alertar sobre vencimiento del certificado digital de firma electrónica',
   'SISTEMA',
   '2024-01-01'),

  ('sistema_max_lineas_por_documento',
   '200',
   'Máximo de líneas permitidas por documento para rendimiento del grid',
   'SISTEMA',
   '2024-01-01'),

  ('sistema_decimales_monto',
   '2',
   'Decimales para montos monetarios (DECIMAL 14,2). No modificar sin migración.',
   'SISTEMA',
   '2024-01-01'),

  ('sistema_decimales_cantidad',
   '6',
   'Decimales para cantidades (DECIMAL 18,6). No modificar sin migración.',
   'SISTEMA',
   '2024-01-01')

ON CONFLICT (clave) DO UPDATE SET
  valor        = EXCLUDED.valor,
  descripcion  = EXCLUDED.descripcion,
  categoria    = EXCLUDED.categoria,
  vigente_desde = EXCLUDED.vigente_desde;
```

### Estructura de la tabla `parametros_sistema`

```sql
CREATE TABLE parametros_sistema (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clave         VARCHAR(80)  NOT NULL UNIQUE,
  valor         TEXT         NOT NULL,
  descripcion   TEXT,
  categoria     VARCHAR(30)  NOT NULL,        -- 'SISTEMA' (foundation) | categorías de módulos de extensión
  vigente_desde DATE         NOT NULL,
  vigente_hasta DATE,                         -- NULL = vigente actualmente
  notas         TEXT,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_parametros_categoria ON parametros_sistema(categoria);
```

> Los parámetros no tienen `empresa_id`: son globales de la plataforma. Las empresas que necesiten sobreescribir un valor (ej. política interna de descuentos) usan la tabla `configuracion_empresa`.

---

## 7. Catálogos Externos

Estos catálogos son muy voluminosos y se mantienen en migraciones SQL separadas. No se documentan en detalle aquí: son datos estáticos con baja frecuencia de cambio.

| Archivo migración | Contenido | Tamaño estimado | Fuente |
|-------------------|-----------|-----------------|--------|
| `foundation/migrations/001_seed_paises.sql` | 249 países ISO 3166-1 alpha-2/alpha-3, nombre en español | ~249 filas | ISO — datos públicos |
| `foundation/migrations/001_seed_monedas.sql` | 228 monedas ISO 4217 con símbolo y decimales | ~228 filas | ISO — datos públicos |
| 🇪🇨 Catálogo geográfico Ecuador | 24 provincias + cantones/parroquias (INEC), 459 bancos/cooperativas (SBS) | ~2000 filas | INEC + SBS Ecuador |
| 🇪🇨 Catálogo fiscal Ecuador | Tarifas IVA, retenciones, formas de pago SRI, catálogos SRI | ~30 filas | SRI Ecuador |

### Ejemplo de estructura: `paises`

```sql
CREATE TABLE paises (
  id          VARCHAR(2)  PRIMARY KEY,        -- Código ISO 3166-1 alpha-2 (ej: 'EC', 'US')
  alpha3      VARCHAR(3)  NOT NULL UNIQUE,     -- Código ISO 3166-1 alpha-3 (ej: 'ECU', 'USA')
  nombre      VARCHAR(100) NOT NULL,           -- Nombre en español
  activo      BOOLEAN DEFAULT true
);

-- Muestra (el seed completo son 249 filas):
INSERT INTO paises (id, alpha3, nombre) VALUES
  ('EC', 'ECU', 'Ecuador'),
  ('CO', 'COL', 'Colombia'),
  ('PE', 'PER', 'Perú'),
  ('US', 'USA', 'Estados Unidos'),
  ('ES', 'ESP', 'España')
ON CONFLICT (id) DO NOTHING;
```

### Nota sobre catálogos de normativa local

Los catálogos de tarifas impositivas y retenciones son específicos de cada país. Las migraciones SQL de seed para estos catálogos se encuentran en las migraciones del módulo de extensión correspondiente y solo se cargan cuando ese módulo está activo en el build.

---

## 8. Procedimiento de Actualización

### Principios

1. **Nunca eliminar registros de catálogos**: usar `activo = false` para deshabilitar.
2. **Idempotencia obligatoria**: todo INSERT de seed debe usar `ON CONFLICT ... DO NOTHING` o `DO UPDATE`.
3. **Tarifas con vigencias**: insertar nuevo registro con `vigente_desde`, nunca modificar el anterior (preserva histórico).
4. **Parámetros de sistema**: actualizar `valor` y `vigente_desde` directamente; el campo `vigente_hasta` permite mantener historial si se crea un nuevo registro en lugar de sobreescribir.
5. **Roles y permisos**: agregar sin eliminar. Si un permiso se elimina del sistema, marcarlo `activo = false`; no hacer DELETE porque empresas o roles pueden tener referencias.

### Actualizar un parámetro de sistema (ejemplo: cambio de límite de cotización)

Cuando cambia el límite de días de vigencia de cotizaciones:

```sql
-- Paso 1: cerrar el parámetro anterior con su fecha de fin (si se quiere conservar histórico)
UPDATE parametros_sistema
SET vigente_hasta = '2025-12-31'
WHERE clave = 'sistema_dias_vencimiento_cotizacion';

-- Paso 2: insertar el nuevo parámetro con su vigencia
INSERT INTO parametros_sistema (clave, valor, descripcion, categoria, vigente_desde)
VALUES (
  'sistema_dias_vencimiento_cotizacion',
  '45',
  'Días de vigencia predeterminados para cotizaciones/proformas (actualizado 2026)',
  'SISTEMA',
  '2026-01-01'
)
ON CONFLICT (clave) DO UPDATE SET
  valor         = EXCLUDED.valor,
  descripcion   = EXCLUDED.descripcion,
  vigente_desde = EXCLUDED.vigente_desde;
```

> Para parámetros de cumplimiento local, ver las migraciones del módulo de extensión fiscal correspondiente.

### Agregar un permiso nuevo

Los permisos nuevos van en el archivo `NNN_seed_permissions.sql` del módulo correspondiente, **no** en foundation. Ejemplo para añadir un permiso a cualquier módulo:

```sql
-- En: <modulo>/migrations/NNN_seed_permissions.sql (o nuevo archivo si ya existe)

-- 1. Agregar el permiso al catálogo
INSERT INTO permisos (id, codigo, nombre, modulo)
VALUES (gen_random_uuid(), '<modulo>.<recurso>.gestionar', 'Gestionar <recurso>', '<modulo>')
ON CONFLICT (codigo) DO NOTHING;

-- 2. Asignarlo a los roles que corresponda
INSERT INTO roles_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM roles r
JOIN permisos p ON p.codigo = '<modulo>.<recurso>.gestionar'
WHERE r.codigo IN ('ADMIN', 'SUPER_ADMIN', 'GERENTE') AND r.empresa_id IS NULL
ON CONFLICT (rol_id, permiso_id) DO NOTHING;
```

### Agregar una unidad de medida

```sql
INSERT INTO unidades_medida (id, categoria_id, nombre, abreviatura, factor_conversion, es_base, activo)
VALUES ('uom_arroba', 'uom_peso', 'Arroba', '@', 11.50000, false, true)
ON CONFLICT (id) DO UPDATE SET
  nombre            = EXCLUDED.nombre,
  factor_conversion = EXCLUDED.factor_conversion,
  activo            = EXCLUDED.activo;
```

### Deshabilitar un rol personalizado obsoleto

```sql
-- NUNCA hacer DELETE en roles del sistema (es_sistema = true)
-- Para roles personalizados de empresa, desactivar:
UPDATE roles
SET activo = false
WHERE codigo = 'ROL_OBSOLETO'
  AND empresa_id = 'uuid-de-la-empresa'
  AND es_sistema = false;

-- Reasignar usuarios que tenían ese rol antes de desactivarlo:
UPDATE usuarios_empresa
SET rol_id = (SELECT id FROM roles WHERE codigo = 'LECTURA' AND empresa_id IS NULL)
WHERE rol_id = (SELECT id FROM roles WHERE codigo = 'ROL_OBSOLETO' AND empresa_id = 'uuid-de-la-empresa');
```

### Estrategia `noupdate` — Cuándo Proteger vs Actualizar Registros

Inspirado en el flag `noupdate` de `ir.model.data` de Odoo, PILAR usa dos estrategias de `ON CONFLICT` según el tipo de dato:

| Estrategia | SQL | Cuándo usar |
|------------|-----|-------------|
| **Protegido** (`DO NOTHING`) | `ON CONFLICT (id) DO NOTHING` | Datos que el usuario puede personalizar: nombres de roles, descripciones, configuraciones. Si ya existe → respetar la versión del usuario |
| **Actualizable** (`DO UPDATE`) | `ON CONFLICT (id) DO UPDATE SET campo = EXCLUDED.campo` | Metadatos técnicos que solo controla el desarrollo: versión del módulo, factores de conversión UoM, tarifas impositivas vigentes. Actualizar en cada migration push |

**Regla práctica**:
- `DO NOTHING` → datos que las empresas pueden personalizar (roles, categorías, listas de precios)
- `DO UPDATE SET campo1, campo2` → datos técnicos de normativa/sistema (UoM, tarifas impositivas, versiones de módulo)
- **NUNCA** `DO UPDATE SET *` en tablas que tienen `empresa_id` — riesgo de sobreescribir personalizaciones de otras empresas

```sql
-- EJEMPLO CORRECTO — rol del sistema (protegido):
INSERT INTO roles (id, nombre, es_sistema) VALUES ('admin', 'Administrador', TRUE)
ON CONFLICT (id) DO NOTHING;
-- Si la empresa renombró 'Administrador' a 'Super Admin' → se respeta

-- EJEMPLO CORRECTO — módulo del sistema (metadatos actualizables):
INSERT INTO modulos (id, nombre, version, descripcion)
VALUES ('<modulo>', '<Nombre>', '1.2', '<Descripción del módulo>')
ON CONFLICT (id) DO UPDATE SET
  version     = EXCLUDED.version,      -- solo campos técnicos
  descripcion = EXCLUDED.descripcion;
  -- id, tipo, nombre: NO actualizar (pueden afectar RLS y permisos)

-- EJEMPLO INCORRECTO — DO UPDATE en tabla con empresa_id:
INSERT INTO listas_precio (id, empresa_id, nombre, factor) VALUES (...)
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre;  -- ¡PELIGROSO!
-- Puede sobreescribir el nombre que la empresa personalizó
```

### Checklist de actualización de seed data

```
[ ] Verificar la fuente oficial y el número de resolución/norma
[ ] Actualizar este documento (foundation/seed-data.md) con el nuevo valor
[ ] Crear nueva migración SQL: supabase migration new actualizar_<concepto>_<YYYY>
[ ] Escribir el SQL con ON CONFLICT idempotente
[ ] Aplicar en entorno local: supabase db push
[ ] Verificar con: supabase db lint
[ ] Commit y push a main
[ ] Aplicar en producción con el procedimiento de despliegue de migraciones
```

---

## Referencias cruzadas

| Documento | Relación |
|-----------|----------|
| `foundation/sistema-base.md` | Tablas `roles`, `permisos`, `roles_permisos`, `parametros_sistema` |
| `foundation/arquitectura-modular.md` | Sistema modular y clasificación de módulos |
| `foundation/seguridad.md` | RLS y políticas de acceso para tablas de roles/permisos |
