# Guía de Implementación de Módulos

**Estado**: Referencia canónica — seguir este checklist al implementar cualquier módulo nuevo
**Relacionado con**: `arquitectura-modular.md`, ADR-009, `module-service-bus-contract.md`, `alter-table-patterns.md`

---

## Visión general del proceso

Implementar un módulo en PILAR requiere 4 capas coordinadas:

```
1. SQL (PostgreSQL)        → Tablas, RLS, funciones, MSB
2. Registro de módulo      → INSERT en catálogo de módulos
3. Flutter (Dart)          → PilarModule + pantallas + providers
4. Documentación           → module.md completo
```

El proceso es el mismo para módulos Core y Auxiliares, con diferencias en la capa MSB (los Core exponen funciones gateway; los Auxiliares las consumen).

---

## Checklist completo por pasos

### PASO 1: Decidir el tipo de módulo

| Pregunta | Si la respuesta es SÍ |
|----------|----------------------|
| ¿Este módulo provee servicios que otros módulos consumirán? | Es un módulo **Core** |
| ¿Este módulo solo consume servicios de módulos Core sin proveer los propios? | Es un módulo **Auxiliar** |
| ¿Debe estar activo siempre, incluso sin configuración? | Es **Infraestructura** |

Confirmar que el módulo no duplica funcionalidad de uno existente. Ver `modules/README.md` y `foundation/indice.md`.

### PASO 2: Crear la estructura de directorios

```bash
# Para un módulo Core nuevo llamado "tributacion":
mkdir -p modules/core/tributacion/migrations
mkdir -p modules/core/tributacion/functions  # solo si tiene Edge Functions
touch modules/core/tributacion/module.md

# Para un módulo Auxiliar nuevo llamado "taller":
mkdir -p modules/extensiones/taller/migrations
touch modules/extensiones/taller/module.md
```

### PASO 3: Crear las migraciones SQL (ver estructura detallada abajo)

### PASO 4: Registrar el módulo en el catálogo

### PASO 5: Implementar PilarModule en Dart

### PASO 6: Registrar en ModuleRegistry

### PASO 7: (Solo Core) Exponer funciones MSB

### PASO 8: (Solo Auxiliar) Usar MSB en lugar de INSERT directo

### PASO 9: Escribir el module.md

### PASO 10: Agregar tests de RLS

---

## Estructura de directorios obligatoria

```
modules/<tipo>/<nombre_modulo>/
├── module.md                    ← OBLIGATORIO: spec completa del módulo
├── migrations/
│   ├── 000_shared_deps.sql      ← Opcional: stubs de tablas externas necesarias
│   ├── 001_<nombre>_tables.sql  ← Tablas principales del módulo + RLS
│   ├── 002_module_bus.sql       ← Solo módulos Core: funciones gateway MSB
│   ├── 003_extend_<tabla>.sql   ← Si el módulo extiende tablas de otros módulos
│   ├── 004_post_install.sql     ← post_install_rpc y pre_uninstall_check_rpc
│   └── 005_indexes.sql          ← Índices adicionales (opcional, puede ir en 001)
└── functions/                   ← Solo si hay Edge Functions
    ├── <nombre-funcion>/
    │   └── index.ts
    └── _shared/                 ← Helpers compartidos entre las EF del módulo
        └── utils.ts
```

---

## Archivos mínimos requeridos y su contenido boilerplate

### `migrations/001_<nombre>_tables.sql` (tablas + RLS)

```sql
-- ============================================================
-- modules/<tipo>/<nombre>/migrations/001_<nombre>_tables.sql
-- Módulo: <Nombre del Módulo>
-- Tipo: Core | Auxiliar | Infraestructura
-- Descripción breve del módulo
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- TABLA PRINCIPAL
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS <nombre>_<entidad> (
    -- Campos obligatorios en TODAS las tablas con empresa_id:
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id      UUID        NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    version         INTEGER     NOT NULL DEFAULT 1,  -- bloqueo optimista (obligatorio en documentos)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Campos propios del módulo:
    -- <campo>      <tipo>      <constraints>
);

-- Índice obligatorio: empresa_id siempre indexado
CREATE INDEX IF NOT EXISTS idx_<nombre>_<entidad>_empresa
    ON <nombre>_<entidad> (empresa_id);

-- Índices adicionales según queries esperadas:
-- CREATE INDEX IF NOT EXISTS idx_<nombre>_<entidad>_<campo>
--     ON <nombre>_<entidad> (empresa_id, <campo>);

-- Trigger para updated_at automático
CREATE OR REPLACE TRIGGER trg_<nombre>_<entidad>_updated_at
    BEFORE UPDATE ON <nombre>_<entidad>
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY (OBLIGATORIO)
-- ────────────────────────────────────────────────────────────

ALTER TABLE <nombre>_<entidad> ENABLE ROW LEVEL SECURITY;

-- SELECT: solo registros de la empresa del usuario autenticado
CREATE POLICY "<nombre>_<entidad>_empresa_select"
    ON <nombre>_<entidad> FOR SELECT TO authenticated
    USING (empresa_id = (SELECT private.get_empresa_id()));

-- INSERT: solo puede crear registros para su propia empresa
CREATE POLICY "<nombre>_<entidad>_empresa_insert"
    ON <nombre>_<entidad> FOR INSERT TO authenticated
    WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

-- UPDATE: solo puede actualizar sus propios registros
CREATE POLICY "<nombre>_<entidad>_empresa_update"
    ON <nombre>_<entidad> FOR UPDATE TO authenticated
    USING  (empresa_id = (SELECT private.get_empresa_id()))
    WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

-- DELETE: solo puede eliminar sus propios registros
CREATE POLICY "<nombre>_<entidad>_empresa_delete"
    ON <nombre>_<entidad> FOR DELETE TO authenticated
    USING (empresa_id = (SELECT private.get_empresa_id()));

-- Comentario de tabla (documentación inline)
COMMENT ON TABLE <nombre>_<entidad> IS
    '[<nombre>] <Descripción de la tabla>';
```

### `migrations/004_post_install.sql` (hooks de ciclo de vida)

```sql
-- ============================================================
-- modules/<tipo>/<nombre>/migrations/004_post_install.sql
-- Hooks de ciclo de vida del módulo
-- ============================================================

-- post_install_rpc: se ejecuta al activar el módulo para una empresa
CREATE OR REPLACE FUNCTION <nombre>_post_install(p_empresa_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
    -- Verificar idempotencia
    IF EXISTS (SELECT 1 FROM <nombre>_configuracion WHERE empresa_id = p_empresa_id) THEN
        RETURN jsonb_build_object('ok', TRUE, 'idempotente', TRUE);
    END IF;

    -- Insertar configuración por defecto
    INSERT INTO <nombre>_configuracion (empresa_id) VALUES (p_empresa_id);

    RETURN jsonb_build_object('ok', TRUE, 'modulo', '<nombre>');
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', SQLERRM);
END;
$$;

-- pre_uninstall_check_rpc: se ejecuta al intentar desactivar el módulo
CREATE OR REPLACE FUNCTION <nombre>_pre_uninstall_check(p_empresa_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
DECLARE
    v_bloqueos JSONB := '[]'::JSONB;
    v_pendientes INTEGER := 0;
BEGIN
    -- Verificar documentos en estado intermedio (adaptar según el módulo)
    SELECT COUNT(*) INTO v_pendientes
    FROM <nombre>_<entidad>
    WHERE empresa_id = p_empresa_id AND estado IN ('pendiente', 'procesando');

    IF v_pendientes > 0 THEN
        v_bloqueos := v_bloqueos || jsonb_build_object(
            'tipo', 'documentos_pendientes',
            'cantidad', v_pendientes,
            'mensaje', format('%s registro(s) en estado pendiente', v_pendientes)
        );
    END IF;

    RETURN jsonb_build_object(
        'puede_desactivar', jsonb_array_length(v_bloqueos) = 0,
        'bloqueos',          v_bloqueos
    );
END;
$$;

-- Registrar RPCs en el catálogo
UPDATE modulos SET
    post_install_rpc        = '<nombre>_post_install',
    pre_uninstall_check_rpc = '<nombre>_pre_uninstall_check'
WHERE id = '<nombre>';
```

---

## Cómo registrar el módulo en el catálogo

El registro va en la primera migración del módulo o en un archivo dedicado:

```sql
-- ============================================================
-- Registrar módulo en el catálogo global
-- ============================================================

-- 1. Insertar el módulo
INSERT INTO modulos (
    id,                  -- Identificador único (snake_case, sin guiones)
    nombre,              -- Nombre legible para UI
    descripcion,         -- Descripción breve (1-2 líneas)
    tipo,                -- 'infraestructura' | 'core' | 'auxiliar'
    version,             -- Semver: '1.0.0'
    icono,               -- Nombre de ícono Material: 'inventory_2'
    estado,              -- 'uninstalled' (default al registrar)
    desactivable,        -- TRUE para core/auxiliar, FALSE para infraestructura
    auto_install         -- TRUE si se activa automáticamente con dependencias
)
VALUES (
    '<nombre>',
    '<Nombre legible>',
    '<Descripción del módulo>',
    'core',              -- o 'auxiliar' o 'infraestructura'
    '1.0.0',
    'inventory_2',
    'uninstalled',
    TRUE,
    FALSE
)
ON CONFLICT (id) DO UPDATE SET
    nombre      = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion,
    version     = EXCLUDED.version;

-- 2. Registrar dependencias
INSERT INTO modulo_dependencias (modulo_id, depende_de, requerido)
VALUES
    -- Todos los módulos dependen de foundation (implícito pero documentado)
    ('<nombre>', 'foundation', TRUE),
    -- Dependencias adicionales del módulo:
    ('<nombre>', '<otro_modulo>', TRUE)   -- requerido=TRUE bloquea activación
    -- ('<nombre>', '<opcional>', FALSE)  -- requerido=FALSE solo advertencia
ON CONFLICT (modulo_id, depende_de) DO NOTHING;

-- 3. Asociar con planes SaaS (qué planes incluyen este módulo)
INSERT INTO plan_modulos (plan_id, modulo_id)
SELECT id, '<nombre>'
FROM planes_saas
WHERE codigo IN ('profesional', 'empresarial')  -- ajustar según el módulo
ON CONFLICT DO NOTHING;
```

---

## Cómo implementar `PilarModule` en Dart

### Archivo: `lib/features/<nombre>/<nombre>_module.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../core/shell/pilar_module.dart';
import '../../core/shell/pilar_menu.dart';
import '../../core/shell/dashboard_widget_def.dart';
import 'screens/<nombre>_list_screen.dart';
import 'screens/<nombre>_detail_screen.dart';

class <Nombre>Module implements PilarModule {
  const <Nombre>Module();

  // ──────────────────────────────────────────────────────────
  // Identidad del módulo
  // Debe coincidir EXACTAMENTE con modulos.id en PostgreSQL
  // ──────────────────────────────────────────────────────────
  @override
  String get id => '<nombre>';

  @override
  String get nombre => '<Nombre legible>';

  @override
  String get descripcion => '<Descripción breve del módulo>';

  @override
  IconData get icono => Icons.inventory_2;  // Ajustar según el módulo

  @override
  Color? get color => const Color(0xFF1565C0);  // Color temático del módulo

  @override
  List<String> get dependencias => ['<dep1>', '<dep2>'];  // IDs de módulos requeridos

  // ──────────────────────────────────────────────────────────
  // Navegación
  // ──────────────────────────────────────────────────────────
  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: '/<nombre>',
      builder: (context, state) => const <Nombre>ListScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => <Nombre>DetailScreen(
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ];

  // ──────────────────────────────────────────────────────────
  // Menú de navegación
  // ──────────────────────────────────────────────────────────
  @override
  List<PilarMenuGroup> get menuItems => [
    PilarMenuGroup(
      titulo: nombre,
      icono: icono,
      color: color,
      items: [
        PilarMenuItem(
          titulo: '<Entidad Principal>',
          ruta: '/<nombre>',
          icono: Icons.list,
        ),
        // Más ítems de menú según el módulo
      ],
    ),
  ];

  // ──────────────────────────────────────────────────────────
  // Widgets para el Dashboard
  // ──────────────────────────────────────────────────────────
  @override
  List<DashboardWidgetDef> get dashboardWidgets => [
    DashboardWidgetDef(
      id: '<nombre>_kpi_total',
      titulo: 'Total <Entidad>',
      icono: icono,
      color: color,
      builder: (context) => const <Nombre>KpiWidget(),
    ),
  ];

  // ──────────────────────────────────────────────────────────
  // Slots que este módulo inyecta en pantallas de otros módulos
  // ──────────────────────────────────────────────────────────
  @override
  Map<String, WidgetBuilder> get slotWidgets => {
    // 'contacto_detail_extra': (ctx) => <Nombre>ContactoPanel(),
    // Declarar slots solo si el módulo inyecta UI en otros módulos
  };

  // ──────────────────────────────────────────────────────────
  // Hooks de ciclo de vida
  // ──────────────────────────────────────────────────────────
  @override
  Future<void> onActivate(Ref ref) async {
    // Pre-cargar datos necesarios al activar
    // Ejemplo: cargar configuración del módulo en cache local
  }

  @override
  Future<bool> onDeactivate(Ref ref) async {
    // Limpiar recursos al desactivar
    // Retornar false para bloquear la desactivación desde cliente
    return true;
  }
}
```

---

## Cómo registrar en `ModuleRegistry`

```dart
// lib/core/shell/module_registry.dart

import '../features/inventario/inventario_module.dart';
import '../features/<nombre>/<nombre>_module.dart';  // <── añadir import

class ModuleRegistry {
  ModuleRegistry._();

  static final Map<String, PilarModule> _allModules = {
    // Módulos existentes:
    'inventario': const InventarioModule(),
    'ventas':     const VentasModule(),
    // ... otros módulos existentes ...

    // Nuevo módulo (añadir aquí):
    '<nombre>': const <Nombre>Module(),  // <── añadir esta línea
  };

  static List<PilarModule> activeModules(List<String> idsActivos) {
    return idsActivos
        .map((id) => _allModules[id])
        .whereType<PilarModule>()
        .toList();
  }

  static PilarModule? get(String id) => _allModules[id];
}
```

---

## Para módulos Core: cómo exponer funciones en el MSB

Ver `module-service-bus-contract.md` para el patrón completo. Resumen:

```sql
-- En migrations/002_module_bus.sql del módulo Core:

-- La función vive en schema public con nombre compuesto para compatibilidad PostgREST
CREATE OR REPLACE FUNCTION module_bus_<nombre>_<operacion>(
    p_empresa_id UUID,
    p_param_1    <tipo>,
    ...
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
DECLARE
    v_activo BOOLEAN;
BEGIN
    -- 1. Verificar módulo activo
    SELECT EXISTS(
        SELECT 1 FROM modulos_empresa
        WHERE empresa_id = p_empresa_id AND modulo_id = '<nombre>'
    ) INTO v_activo;

    IF NOT v_activo THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'MODULE_NOT_ACTIVE', 'modulo', '<nombre>');
    END IF;

    -- 2. Lógica real
    -- ...

    RETURN jsonb_build_object('ok', TRUE, ...);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'INTERNAL_ERROR', 'msg', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION module_bus_<nombre>_<operacion>(...) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION module_bus_<nombre>_<operacion>(...) TO authenticated;
```

---

## Para módulos Auxiliares: cómo usar el MSB

```dart
// En el repository del módulo Auxiliar:
// NUNCA hacer supabase.from('facturas').insert({...})
// SIEMPRE usar supabase.rpc('module_bus_<core>_<operacion>', {...})

class TallerRepository {
  final SupabaseClient _supabase;

  // Crear factura de servicio técnico a través del MSB de Facturación
  Future<MsbResult> crearFacturaServicio({
    required String empresaId,
    required String clienteId,
    required List<LineaServicio> lineas,
  }) async {
    // CORRECTO: llamar al MSB, no a la tabla directamente
    final response = await _supabase.rpc(
      'module_bus_facturacion_create_invoice',
      params: {
        'p_empresa_id':  empresaId,
        'p_cliente_id':  clienteId,
        'p_lineas':      lineas.map((l) => l.toJson()).toList(),
        'p_tipo_documento': '01',
        'p_referencia_origen': 'TALLER',
      },
    );

    return MsbResult.fromJson(response as Map<String, dynamic>);
  }

  // Consultar stock disponible a través del MSB de Inventario
  Future<Decimal> stockDisponible({
    required String empresaId,
    required String productoId,
  }) async {
    final response = await _supabase.rpc(
      'module_bus_inventario_get_available_stock',
      params: {
        'p_empresa_id':  empresaId,
        'p_producto_id': productoId,
      },
    );

    final result = MsbResult.fromJson(response as Map<String, dynamic>);
    if (!result.ok) return Decimal.zero;  // Modo degradado si inventario no activo

    return Decimal.parse(result.json['disponible'].toString());
  }
}
```

---

## Qué documentar en `module.md`

El `module.md` es la spec primaria del módulo. Debe cubrir:

```markdown
# Módulo <Nombre>

**Tipo**: Core | Auxiliar | Infraestructura
**ID**: `<nombre>` (debe coincidir con modulos.id en PostgreSQL)
**Depende de**: `<modulo1>`, `<modulo2>`
**Dependientes conocidos**: `<moduloA>`, `<moduloB>`

## Descripción

<Qué hace este módulo, para qué tipo de empresa es útil, qué problema resuelve>

## Tablas

| Tabla | Descripción | Propietario |
|-------|-------------|-------------|
| `<nombre>_<entidad>` | <Descripción> | Módulo <nombre> |

## RPCs expuestas (solo módulos Core)

| Función MSB | Parámetros | Retorna | Notas |
|-------------|-----------|---------|-------|
| `module_bus_<nombre>_<op>()` | ... | JSONB | ... |

## MSB que consume (solo módulos Auxiliares)

| MSB llamado | Por qué | Modo degradado si no activo |
|-------------|---------|----------------------------|
| `module_bus_facturacion_create_invoice()` | Emitir factura de venta | Guardar sin factura; crear al activar facturación |

## Flujos principales

### Flujo 1: <Nombre del flujo>

1. Paso 1
2. Paso 2
3. ...

## Configuración del módulo

Tabla `<nombre>_configuracion` — parámetros configurables por empresa.

## Edge Functions

| Función | Disparador | Descripción |
|---------|-----------|-------------|
| `<nombre-ef>` | ... | ... |

## Comportamiento al desactivar

- Los datos de <entidad> persisten en BD, marcados con is_archived=TRUE
- Las reservas activas se cancelan automáticamente
- ...
```

---

## Errores comunes y cómo evitarlos

| Error | Consecuencia | Cómo evitarlo |
|-------|-------------|---------------|
| No habilitar RLS | Filtración de datos entre empresas | Siempre `ENABLE ROW LEVEL SECURITY` + 4 policies |
| Usar `FLOAT` en montos | Errores de centavo en cálculos | Usar `DECIMAL(14,2)` siempre |
| INSERT directo en tablas Core desde módulo Auxiliar | Acoplamiento fuerte, bugs si el Core no está activo | Siempre usar `module_bus_<core>_<op>()` |
| Olvidar `empresa_id` en queries de SECURITY DEFINER | Exposición cross-tenant | Todo `SECURITY DEFINER` debe incluir `WHERE empresa_id = p_empresa_id` |
| FK constraints hacia tablas de módulos activables | Errores si el módulo no está activo | Usar soft reference UUID nullable |
| `id` en `ModuleRegistry` diferente al id en PostgreSQL | El módulo no se activa correctamente en Flutter | Verificar que ambos IDs son idénticos |
| Migración no idempotente | Fallo en re-ejecución | Usar `IF NOT EXISTS`, `ON CONFLICT DO NOTHING` en todos los DDL |
| `post_install_rpc` lento (>15s) | Timeout en activación | Dividir en fase rápida (sync) + cola pgmq (async) |
| No implementar `pre_uninstall_check_rpc` | Módulo desactivado con documentos pendientes | Siempre implementar el check para módulos con documentos |
| No registrar columnas en `modulo_campos_extension` | Pérdida de trazabilidad del schema | Siempre insertar en `modulo_campos_extension` al hacer ALTER TABLE |

---

## Links a archivos de referencia de Foundation

| Necesitas | Lee |
|-----------|-----|
| Patrón RLS completo | `foundation/adrs/ADR-003_rls-pattern.md` |
| Patrón de funciones MSB | `foundation/module-service-bus-contract.md` |
| Cómo extender tablas de otros módulos | `foundation/alter-table-patterns.md` |
| Garantías de activación/post_install | `foundation/module-activation-guarantees.md` |
| Cómo implementar desactivación | `foundation/module-deactivation-guide.md` |
| Tests de RLS obligatorios | `foundation/rls-testing-guide.md` |
| Precisión numérica (DECIMAL) | `foundation/precision-rounding-rules.md` |
| Qué módulo posee qué campo | `foundation/field-ownership-matrix.md` |
| Cómo funciona el sistema modular | `foundation/arquitectura-modular.md` |
| Sistema de background jobs | `foundation/background-jobs.md` |
| Pubspec y paquetes aprobados | `foundation/pubspec-referencia.md` |
| Convenciones de código Flutter | `foundation/estructura-proyecto.md` |
| Cómo documentar RPCs | `foundation/apis/rpcs-por-modulo.md` |
