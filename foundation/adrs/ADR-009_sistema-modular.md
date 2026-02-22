# ADR-009: Sistema Modular — Activacion por Empresa con Dependencias y Registry Compilado

**Estado**: Aceptado
**Fecha**: 2026-02
**Autores**: Arquitecto principal
**Tags**: arquitectura, modulos, flutter, postgresql, activacion, dependencias, registry

---

## Contexto

PILAR tiene modulos organizados en tres tipos con comportamientos distintos de activacion:

- **Infraestructura**: siempre activos, no desactivables
- **Core**: proveen servicios via Module Service Bus
- **Auxiliares**: activables individualmente por empresa

El problema a resolver es doble:

**En la base de datos**: los modulos deben poder activarse y desactivarse por empresa, con resolucion automatica de dependencias (activar un modulo auxiliar activa sus dependencias Core si no lo estan), verificacion de que un modulo no puede desactivarse si hay otros activos que dependen de el, y un estado inicial coherente de la base de datos al crear una empresa nueva.

**En Flutter**: el framework es compilado — a diferencia de Odoo (Python), no puede importar codigo nuevo en tiempo de ejecucion descargando un modulo. Sin embargo, si puede: registrar todos los modulos en tiempo de compilacion, activar o desactivar la presentacion de rutas y menus segun que modulos esten activos para la empresa autenticada, e inyectar widgets de un modulo en pantallas de otro via un sistema de slots declarativo.

### Investigacion del Sistema Modular de Odoo 18

Se investigo el codigo fuente de Odoo 18 para entender como resuelve el mismo problema en Python:

**Descubrimiento de modulos**: Odoo escanea `addons_path` buscando directorios con `__manifest__.py`. Cada manifest declara `name`, `version`, `depends`, `auto_install` y `post_install`. El equivalente en PILAR es la tabla `modulos` con columnas para estos mismos atributos.

**Tabla ir_module_module**: estados `uninstalled / installed / to_install / to_remove / uninstallable`. PILAR adopta exactamente estos mismos estados en la columna `estado` de la tabla `modulos`. El campo `auto_install` se mapea 1:1.

**Grafo de dependencias**: Odoo tiene `ir_module_module_dependency` con resolucion recursiva. La funcion `_get_modules_to_load()` recorre el grafo y calcula un orden topologico. PILAR implementa el equivalente en PostgreSQL con `modulo_dependencias` y la funcion `resolve_module_dependencies()`.

**MetaModel y Registry**: Python puede construir la clase de un modelo fusionando `_inherit` de multiples modulos en runtime — esto es imposible en Dart/Flutter compilado. La adaptacion es el `ModuleRegistry` que registra todos los modulos en tiempo de compilacion y filtra cuales mostrar segun los activos.

**Vistas XML con inherit_id + xpath**: Odoo permite que un modulo inyecte campos en la pantalla de otro sin modificar el original. El equivalente en Flutter es el sistema de `ModuleSlot` — un widget nombrado donde otros modulos pueden inyectar sus propios widgets.

**base_data.sql**: Odoo inicializa la BD desde cero con un script SQL que crea empresa demo, usuario admin, roles y datos de catalogo. El equivalente en PILAR es la migracion `001_base_data.sql`.

La diferencia fundamental: Odoo puede instalar un modulo en runtime (descargar codigo Python, reiniciar registry). Flutter no puede. Esta restriccion es la que guia toda la arquitectura de la capa Flutter.

---

## Decision

Se implementa un sistema modular de dos capas: **PostgreSQL** (estado, dependencias, activacion) y **Flutter** (registry compilado, rutas dinamicas, slots).

### Capa PostgreSQL

#### Enriquecimiento de la Tabla modulos Existente

```sql
-- Agregar columnas a la tabla modulos ya existente
ALTER TABLE modulos ADD COLUMN IF NOT EXISTS version         TEXT    DEFAULT '1.0';
ALTER TABLE modulos ADD COLUMN IF NOT EXISTS estado          TEXT    DEFAULT 'uninstalled'
    CONSTRAINT modulos_estado_check
    CHECK (estado IN ('uninstalled', 'installed', 'to_install', 'to_remove', 'uninstallable'));
ALTER TABLE modulos ADD COLUMN IF NOT EXISTS auto_install    BOOLEAN DEFAULT FALSE;
ALTER TABLE modulos ADD COLUMN IF NOT EXISTS post_install_rpc TEXT;  -- funcion RPC a llamar post-activacion

-- Indices
CREATE INDEX IF NOT EXISTS idx_modulos_estado    ON modulos(estado);
CREATE INDEX IF NOT EXISTS idx_modulos_tipo      ON modulos(tipo);
```

Los estados siguen la misma semantica que Odoo:
- `uninstalled`: disponible pero no activo para ninguna empresa
- `installed`: modulo disponible y operativo en el sistema
- `to_install`: marcado para proxima instalacion (usado por activate_module)
- `to_remove`: marcado para proxima desinstalacion
- `uninstallable`: incompatible con la version actual del sistema

#### Tabla de Dependencias

```sql
CREATE TABLE IF NOT EXISTS modulo_dependencias (
  modulo_id   TEXT    NOT NULL REFERENCES modulos(id) ON DELETE CASCADE,
  depende_de  TEXT    NOT NULL REFERENCES modulos(id) ON DELETE RESTRICT,
  requerido   BOOLEAN NOT NULL DEFAULT TRUE,
  -- requerido=TRUE  → debe estar activo para que modulo_id funcione
  -- requerido=FALSE → mejora funcionalidad pero no es obligatorio
  PRIMARY KEY (modulo_id, depende_de)
);

CREATE INDEX IF NOT EXISTS idx_modulo_dependencias_depende_de
  ON modulo_dependencias(depende_de);
```

Dependencias declaradas (patron generico — los valores reales dependen de los modulos implementados):

```sql
-- requerido=TRUE  → dep. obligatoria: mi_modulo no puede activarse sin dep_core
-- requerido=FALSE → dep. opcional: mi_modulo funciona en modo degradado sin dep_opcional
INSERT INTO modulo_dependencias (modulo_id, depende_de, requerido) VALUES
  -- Auxiliar con dependencia requerida de un modulo Core
  ('mi_auxiliar',   'dep_core',      TRUE),
  -- Auxiliar con dependencia opcional de otro auxiliar
  ('mi_auxiliar',   'dep_opcional',  FALSE)
ON CONFLICT (modulo_id, depende_de) DO NOTHING;
```

#### Funcion de Resolucion de Dependencias

```sql
-- Resolucion recursiva de dependencias (equivalente a _get_modules_to_load de Odoo)
-- Retorna todos los modulos que deben estar activos para activar p_modulo_id,
-- en orden topologico (las dependencias primero)
CREATE OR REPLACE FUNCTION resolve_module_dependencies(
  p_empresa_id UUID,
  p_modulo_id  TEXT
)
RETURNS TABLE(modulo_id TEXT, orden INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE dep_tree AS (
    -- Nodo raiz
    SELECT
      md.depende_de  AS modulo_id,
      1              AS nivel,
      md.requerido
    FROM modulo_dependencias md
    WHERE md.modulo_id = p_modulo_id
      AND md.requerido = TRUE

    UNION ALL

    -- Dependencias transitivas
    SELECT
      md2.depende_de AS modulo_id,
      dt.nivel + 1   AS nivel,
      md2.requerido
    FROM modulo_dependencias md2
    INNER JOIN dep_tree dt ON md2.modulo_id = dt.modulo_id
    WHERE md2.requerido = TRUE
  ),
  -- Excluir modulos ya activos para la empresa
  pendientes AS (
    SELECT DISTINCT dt.modulo_id, MAX(dt.nivel) AS max_nivel
    FROM dep_tree dt
    WHERE NOT EXISTS (
      SELECT 1 FROM modulos_empresa me
      WHERE me.empresa_id = p_empresa_id
        AND me.modulo_id  = dt.modulo_id
        AND me.activo     = TRUE
    )
    GROUP BY dt.modulo_id
  )
  SELECT p.modulo_id, p.max_nivel AS orden
  FROM pendientes p
  ORDER BY p.max_nivel DESC;  -- dependencias de mayor profundidad primero
END;
$$;
```

#### Funcion de Activacion con Dependencias Automaticas

```sql
-- Activa un modulo para una empresa, activando antes sus dependencias requeridas.
-- Equivalente a button_immediate_install() de Odoo.
-- Retorna JSONB con resultado: { ok, modulos_activados, error }
CREATE OR REPLACE FUNCTION activate_module(
  p_empresa_id UUID,
  p_modulo_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_modulos_a_activar TEXT[];
  v_modulo            TEXT;
  v_post_install_rpc  TEXT;
  v_resultado         JSONB;
BEGIN
  -- Lock por empresa para evitar activaciones concurrentes (equivalente a
  -- LOCK ir_module_module EXCLUSIVE de Odoo, pero por empresa en multi-tenant)
  IF NOT pg_try_advisory_xact_lock(
    hashtext('pilar_modulo_activation'),
    p_empresa_id::bigint
  ) THEN
    RETURN jsonb_build_object(
      'ok',    FALSE,
      'error', 'Hay otra operacion de modulo en progreso para esta empresa'
    );
  END IF;

  -- Verificar que el modulo existe y no es uninstallable
  IF NOT EXISTS (
    SELECT 1 FROM modulos
    WHERE id = p_modulo_id AND estado != 'uninstallable'
  ) THEN
    RETURN jsonb_build_object(
      'ok',    FALSE,
      'error', 'Modulo ' || p_modulo_id || ' no existe o no es instalable'
    );
  END IF;

  -- Verificar que el solicitante pertenece a la empresa
  IF (SELECT private.get_empresa_id()) != p_empresa_id THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'Empresa no autorizada');
  END IF;

  -- Resolver dependencias pendientes en orden topologico
  SELECT ARRAY_AGG(rd.modulo_id ORDER BY rd.orden DESC)
  INTO v_modulos_a_activar
  FROM resolve_module_dependencies(p_empresa_id, p_modulo_id) rd;

  -- Agregar el modulo principal al final del array (se activa despues de sus deps)
  v_modulos_a_activar := COALESCE(v_modulos_a_activar, '{}') || p_modulo_id;

  -- Activar cada modulo en orden
  FOREACH v_modulo IN ARRAY v_modulos_a_activar LOOP
    INSERT INTO modulos_empresa (empresa_id, modulo_id, activo, fecha_activacion)
    VALUES (p_empresa_id, v_modulo, TRUE, NOW())
    ON CONFLICT (empresa_id, modulo_id)
    DO UPDATE SET activo = TRUE, fecha_activacion = NOW();

    -- Ejecutar post_install_rpc si existe (inicializacion de datos del modulo)
    SELECT post_install_rpc INTO v_post_install_rpc
    FROM modulos WHERE id = v_modulo;

    IF v_post_install_rpc IS NOT NULL THEN
      EXECUTE 'SELECT ' || v_post_install_rpc || '($1)' USING p_empresa_id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok',               TRUE,
    'modulos_activados', v_modulos_a_activar
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', FALSE, 'error', SQLERRM);
END;
$$;
```

#### Funcion de Desactivacion con Verificacion de Dependientes

```sql
-- Desactiva un modulo para una empresa.
-- Falla si hay otros modulos activos que dependen de este.
-- Equivalente a button_immediate_uninstall() de Odoo.
CREATE OR REPLACE FUNCTION deactivate_module(
  p_empresa_id UUID,
  p_modulo_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_dependientes TEXT[];
BEGIN
  -- Lock por empresa (mismo mecanismo que activate_module)
  IF NOT pg_try_advisory_xact_lock(
    hashtext('pilar_modulo_activation'),
    p_empresa_id::bigint
  ) THEN
    RETURN jsonb_build_object(
      'ok',    FALSE,
      'error', 'Hay otra operacion de modulo en progreso para esta empresa'
    );
  END IF;

  -- Verificar autorizacion de empresa
  IF (SELECT private.get_empresa_id()) != p_empresa_id THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'Empresa no autorizada');
  END IF;

  -- Los modulos de Infraestructura no son desactivables
  IF EXISTS (
    SELECT 1 FROM modulos
    WHERE id = p_modulo_id AND tipo = 'infraestructura'
  ) THEN
    RETURN jsonb_build_object(
      'ok',    FALSE,
      'error', 'Los modulos de Infraestructura no pueden desactivarse'
    );
  END IF;

  -- Verificar que ningun otro modulo activo depende de este
  SELECT ARRAY_AGG(me.modulo_id)
  INTO v_dependientes
  FROM modulos_empresa me
  INNER JOIN modulo_dependencias md ON md.modulo_id = me.modulo_id
  WHERE me.empresa_id = p_empresa_id
    AND me.activo     = TRUE
    AND md.depende_de = p_modulo_id
    AND md.requerido  = TRUE
    AND me.modulo_id != p_modulo_id;

  IF v_dependientes IS NOT NULL AND ARRAY_LENGTH(v_dependientes, 1) > 0 THEN
    RETURN jsonb_build_object(
      'ok',           FALSE,
      'error',        'No se puede desactivar: otros modulos activos dependen de este',
      'dependientes', v_dependientes
    );
  END IF;

  -- Desactivar
  UPDATE modulos_empresa
  SET activo = FALSE, fecha_desactivacion = NOW()
  WHERE empresa_id = p_empresa_id AND modulo_id = p_modulo_id;

  RETURN jsonb_build_object('ok', TRUE, 'modulo_desactivado', p_modulo_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', FALSE, 'error', SQLERRM);
END;
$$;
```

#### Migracion 001 — Equivalente al base_data.sql de Odoo

La primera migracion (`001_base_data.sql`) es el equivalente del `base_data.sql` de Odoo: inicializa la base de datos desde cero con todo lo necesario para que el sistema arranque. Incluye:

```sql
-- 1. Los modulos del sistema con sus metadatos
-- (los IDs reales corresponden a los modulos implementados)
INSERT INTO modulos (id, nombre, tipo, version, estado, auto_install, descripcion) VALUES
  -- Infraestructura (siempre activos, auto_install=TRUE)
  ('<infra_1>',  'Nombre Infra 1', 'infraestructura', '1.0', 'installed',   TRUE,  'descripcion'),
  -- Core (instalados pero no auto-activados por empresa)
  ('<core_1>',   'Nombre Core 1',  'core',             '1.0', 'installed',   FALSE, 'descripcion'),
  -- Auxiliares (desinstalados por defecto, activables por empresa)
  ('<aux_1>',    'Nombre Aux 1',   'auxiliar',         '1.0', 'uninstalled', FALSE, 'descripcion')
ON CONFLICT (id) DO NOTHING;

-- 2. Activar los modulos de Infraestructura en modulos_empresa para la empresa nueva
-- (ejecutado por el trigger de creacion de empresa, no hardcodeado aqui)

-- 3. Roles predefinidos del sistema
INSERT INTO roles (id, nombre, descripcion) VALUES
  ('superadmin', 'Super Administrador', 'Acceso total al SaaS (no por empresa)'),
  ('admin',      'Administrador',       'Configuracion total de la empresa'),
  ('gerente',    'Gerente',             'Dashboard y reportes, sin edicion'),
  ('empleado',   'Empleado',            'Portal autoservicio limitado')
  -- (roles adicionales especificos de los modulos instalados)
ON CONFLICT (id) DO NOTHING;

-- 4. Trigger: al crear una empresa, activar automaticamente los modulos de Infraestructura
CREATE OR REPLACE FUNCTION tr_empresa_activar_infraestructura()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO modulos_empresa (empresa_id, modulo_id, activo, fecha_activacion)
  SELECT NEW.id, m.id, TRUE, NOW()
  FROM modulos m
  WHERE m.tipo = 'infraestructura'
  ON CONFLICT (empresa_id, modulo_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_empresa_infraestructura
AFTER INSERT ON empresas
FOR EACH ROW EXECUTE FUNCTION tr_empresa_activar_infraestructura();
```

#### RLS para Tablas de Sistema de Modulos

```sql
-- modulos: lectura publica para todos los usuarios autenticados
ALTER TABLE modulos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "modulos_select" ON modulos
  FOR SELECT TO authenticated USING (true);

-- modulo_dependencias: lectura publica
ALTER TABLE modulo_dependencias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "modulo_dependencias_select" ON modulo_dependencias
  FOR SELECT TO authenticated USING (true);

-- modulos_empresa: cada empresa ve solo sus activaciones
ALTER TABLE modulos_empresa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "modulos_empresa_select" ON modulos_empresa
  FOR SELECT TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
-- INSERT/UPDATE solo via funciones SECURITY DEFINER (activate_module / deactivate_module)
```

---

### Capa Flutter

#### Interfaz PilarModule

Cada modulo Flutter implementa una interfaz que declara sus rutas, menus, widgets de dashboard y slots de inyeccion:

```dart
/// Interfaz base que todo modulo Flutter debe implementar.
/// Equivalente conceptual al __manifest__.py de Odoo, pero en Dart.
abstract class PilarModule {
  /// Identificador unico (debe coincidir con modulos.id en PostgreSQL)
  String get id;

  /// Nombre legible para el App Launcher
  String get nombre;

  /// Icono del modulo en el App Launcher
  IconData get icono;

  /// IDs de modulos de los que este depende (para validacion en cliente)
  List<String> get dependencias;

  /// Rutas go_router que este modulo aporta al router global
  List<RouteBase> get routes;

  /// Grupos de menu (barra superior en desktop, tabs en tablet, drawer en movil)
  List<PilarMenuGroup> get menuItems;

  /// Widgets para el dashboard principal (tarjetas KPI, graficos, alertas)
  List<DashboardWidgetDef> get dashboardWidgets;

  /// Widgets de inyeccion en slots de otros modulos.
  /// Key: nombre del slot (ej: 'orden_venta.after_lines')
  /// Value: lista de builders de widgets a inyectar en ese slot
  Map<String, List<Widget Function(BuildContext, WidgetRef)>> get slotWidgets;

  /// Llamado cuando el usuario activa este modulo en Administracion
  Future<void> onActivate(Ref ref) async {}

  /// Llamado cuando el usuario desactiva este modulo
  Future<void> onDeactivate(Ref ref) async {}
}
```

#### Ejemplo de Implementacion — Modulo Generico

```dart
class MiModuloModule implements PilarModule {
  @override
  String get id => 'mi_modulo';

  @override
  String get nombre => 'Mi Modulo';

  @override
  IconData get icono => Icons.widgets_rounded;

  @override
  List<String> get dependencias => ['dep_core'];

  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: '/mi-modulo',
      builder: (_, __) => const MiModuloListScreen(),
      routes: [
        GoRoute(
          path: 'nuevo',
          builder: (_, __) => const MiModuloFormScreen(),
        ),
        GoRoute(
          path: ':id',
          builder: (ctx, state) => MiModuloDetailScreen(
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ];

  @override
  List<PilarMenuGroup> get menuItems => [
    PilarMenuGroup(
      label: 'Mi Modulo',
      items: [
        PilarMenuItem(label: 'Listado',  path: '/mi-modulo'),
        PilarMenuItem(label: 'Nuevo',    path: '/mi-modulo/nuevo'),
      ],
    ),
  ];

  @override
  List<DashboardWidgetDef> get dashboardWidgets => [
    DashboardWidgetDef(
      id:      'mi_modulo_kpi',
      titulo:  'KPI del Modulo',
      builder: (ctx, ref) => const MiModuloKpi(),
      ancho:   2, // columnas en el grid del dashboard
    ),
  ];

  @override
  Map<String, List<Widget Function(BuildContext, WidgetRef)>> get slotWidgets => {
    // Inyectar seccion en la pantalla de otro modulo (sin modificar el modulo origen)
    'otra_entidad.detalle.tabs': [
      (ctx, ref) => const MiModuloTabEnOtraEntidad(),
    ],
  };
}
```

#### ModuleRegistry — Registry Central Compilado

```dart
/// Registry de todos los modulos de PILAR, registrados en tiempo de compilacion.
/// La seleccion de cuales mostrar se hace en runtime segun modulos_empresa.
///
/// Anadir un nuevo modulo = agregar una linea aqui + migracion SQL.
class ModuleRegistry {
  ModuleRegistry._();

  /// Todos los modulos disponibles en esta build de la aplicacion.
  /// Clave = PilarModule.id (debe coincidir con modulos.id en PostgreSQL).
  /// Anadir un nuevo modulo = agregar una entrada aqui + migracion SQL.
  static final Map<String, PilarModule> _allModules = {
    // Infraestructura (siempre registrados y activos)
    '<infra_1>':  InfraModule1(),
    '<infra_2>':  InfraModule2(),
    // Core
    '<core_1>':   CoreModule1(),
    '<core_2>':   CoreModule2(),
    // Auxiliares
    '<aux_1>':    AuxModule1(),
    '<aux_2>':    AuxModule2(),
    // ... (un entry por modulo implementado)
  };

  /// Retorna el PilarModule para un ID dado (o null si no existe en esta build).
  static PilarModule? get(String id) => _allModules[id];

  /// Filtra los modulos registrados segun los IDs activos para la empresa.
  /// Los modulos no encontrados en activeIds son silenciosamente ignorados
  /// (pueden existir en BD pero aun no estar implementados en esta version).
  static List<PilarModule> activeModules(List<String> activeIds) {
    return activeIds
        .map((id) => _allModules[id])
        .whereType<PilarModule>()
        .toList();
  }

  /// Todos los slots disponibles, agregados de todos los modulos activos.
  /// Usado por ModuleSlot para resolver que widgets inyectar.
  static Map<String, List<Widget Function(BuildContext, WidgetRef)>>
      aggregatedSlots(List<String> activeIds) {
    final result = <String, List<Widget Function(BuildContext, WidgetRef)>>{};
    for (final module in activeModules(activeIds)) {
      module.slotWidgets.forEach((slotId, builders) {
        result.putIfAbsent(slotId, () => []).addAll(builders);
      });
    }
    return result;
  }
}
```

#### Provider Riverpod — Modulos Activos

```dart
/// Carga desde Supabase/SQLite los IDs de modulos activos para la empresa.
@riverpod
Future<List<String>> modulosActivosIds(Ref ref) async {
  final empresaId = ref.watch(empresaIdProvider);
  // Brick repository — lee de SQLite local (offline-first, ver ADR-001)
  final repo = ref.watch(modulosEmpresaRepositoryProvider);
  final registros = await repo.get<ModuloEmpresa>(
    query: Query(where: [
      Where('empresaId').isExactly(empresaId),
      Where('activo').isExactly(true),
    ]),
  );
  return registros.map((r) => r.moduloId).toList();
}

/// Lista de instancias PilarModule activas para la empresa autenticada.
@riverpod
List<PilarModule> modulosActivos(Ref ref) {
  final activeIds = ref.watch(modulosActivosIdsProvider).valueOrNull ?? [];
  return ModuleRegistry.activeModules(activeIds);
}
```

#### Router Dinamico — Rutas segun Modulos Activos

```dart
/// Router go_router construido dinamicamente desde los modulos activos.
/// Se reconstruye cuando cambia la lista de modulos activos (activacion/desactivacion).
@riverpod
GoRouter appRouter(Ref ref) {
  // Rutas estaticas del shell (siempre presentes)
  final coreRoutes = <RouteBase>[
    GoRoute(path: '/login',        builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/setup-wizard', builder: (_, __) => const SetupWizardScreen()),
  ];

  // Rutas aportadas por cada modulo activo
  final modulosActivos = ref.watch(modulosActivosProvider);
  final moduleRoutes   = modulosActivos.expand((m) => m.routes).toList();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => PilarShell(child: child),
        routes: [...coreRoutes, ...moduleRoutes],
      ),
    ],
    redirect: (ctx, state) {
      final estaAutenticado = ref.read(authStateProvider).isAuthenticated;
      if (!estaAutenticado && state.matchedLocation != '/login') {
        return '/login';
      }
      return null;
    },
  );
}
```

#### Sistema de Slots — Equivalente a xpath de Odoo

```dart
/// Widget que actua como punto de inyeccion para widgets de otros modulos.
/// Equivalente al sistema inherit_id + position="after" de las vistas XML de Odoo.
///
/// Uso en la pantalla de una entidad del modulo A:
///   ModuleSlot(slotId: 'entidad_a.after_lines')
///
/// El modulo B puede inyectar alli su seccion
/// registrando en ModuloB.slotWidgets['entidad_a.after_lines'].
class ModuleSlot extends ConsumerWidget {
  const ModuleSlot({
    super.key,
    required this.slotId,
    this.emptyWidget = const SizedBox.shrink(),
  });

  /// Identificador del slot. Convencion: 'entidad.pantalla.posicion'
  /// Ejemplos:
  ///   'entidad_a.after_lines'   → despues de las lineas del formulario
  ///   'entidad_a.detalle.tabs'  → tab adicional en la pantalla de detalle
  ///   'entidad_a.acciones'      → botones adicionales en la barra de acciones
  ///   'dashboard.kpi_row'       → fila de KPIs en el dashboard
  final String slotId;

  /// Widget mostrado si ningun modulo activo inyecta en este slot
  final Widget emptyWidget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIds = ref.watch(modulosActivosIdsProvider).valueOrNull ?? [];
    final slots     = ModuleRegistry.aggregatedSlots(activeIds);
    final builders  = slots[slotId] ?? [];

    if (builders.isEmpty) return emptyWidget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: builders.map((b) => b(context, ref)).toList(),
    );
  }
}
```

#### Estructura de Archivos para un Modulo Nuevo

Convension para agregar cualquier modulo nuevo al codebase:

```
lib/features/nuevo_modulo/
├── nuevo_modulo_module.dart     # implements PilarModule — rutas, menus, slots
├── screens/
│   ├── nuevo_modulo_list_screen.dart
│   └── nuevo_modulo_form_screen.dart
├── providers/
│   └── nuevo_modulo_providers.dart
├── widgets/
│   └── nuevo_modulo_kpi_card.dart
└── models/                      # Modelos Brick (si el modulo tiene entidades propias)
    └── nuevo_modulo_entity.dart
```

Ademas de los archivos Flutter, agregar un modulo nuevo requiere:
1. Implementar `PilarModule` en `nuevo_modulo_module.dart`
2. Registrar en `ModuleRegistry._allModules`
3. Migracion SQL en `supabase/migrations/NNN_nuevo_modulo.sql`
4. INSERT en tabla `modulos` + INSERT en `modulo_dependencias` si aplica

---

## Hallazgos Adicionales — Patrones de Odoo Adoptados

Tras una investigación profunda del código fuente de Odoo 18 con 5 agentes especializados (base init, install pipeline, inheritance, security, views/menus), se identificaron los siguientes patrones que PILAR adopta o adapta.

### 1. Bandera `noupdate` para Datos Semilla

Odoo tiene `ir.model.data.noupdate BOOLEAN`. Con `noupdate=True`, los registros ya existentes en la BD **no se modifican** aunque el XML de datos haya cambiado entre versiones del módulo. Esto protege personalizaciones del usuario (ej: el usuario renombró un rol → Odoo no lo sobreescribe al actualizar).

PILAR implementa el mismo principio en SQL con dos estrategias según el tipo de dato:

```sql
-- PROTEGIDOS (noupdate equivalente = DO NOTHING):
-- Roles del sistema, catálogos configurables — nunca sobreescribir
INSERT INTO roles (id, nombre, es_sistema)
VALUES ('admin', 'Administrador', TRUE)
ON CONFLICT (id) DO NOTHING;  -- usuario puede haberlo renombrado → respetar

-- ACTUALIZABLES (noupdate=False en Odoo — DO UPDATE):
-- Versión del módulo, descripciones técnicas — actualizar en cada migration push
INSERT INTO modulos (id, nombre, version, descripcion)
VALUES ('mi_modulo', 'Mi Módulo', '1.2', 'descripcion actualizada')
ON CONFLICT (id) DO UPDATE SET
  version     = EXCLUDED.version,
  descripcion = EXCLUDED.descripcion;
  -- id, tipo: nunca actualizables (podrían romper FK y RLS)
```

**Regla práctica**: `DO NOTHING` para datos que las empresas pueden personalizar; `DO UPDATE SET campos_técnicos` para metadatos del sistema que solo el desarrollo controla.

### 2. Lock para Activaciones Concurrentes

Odoo usa `LOCK TABLE ir_module_module IN EXCLUSIVE MODE NOWAIT` + `LOCK ir_cron FOR UPDATE NOWAIT` en `button_immediate_install()` para impedir que dos procesos instalen módulos simultáneamente (evita races conditions en el grafo de dependencias).

PILAR implementa el equivalente con `pg_try_advisory_xact_lock` — más adecuado para multi-tenant porque lockea por empresa, no por tabla global:

```sql
-- Dentro de activate_module() / deactivate_module(), al inicio:
-- Previene que dos admins activen módulos simultáneamente en la misma empresa
IF NOT pg_try_advisory_xact_lock(
  hashtext('pilar_modulo_activation'),  -- namespace fijo
  p_empresa_id::bigint                  -- distingue entre empresas
) THEN
  RETURN jsonb_build_object(
    'ok',    FALSE,
    'error', 'Hay otra operacion de modulo en progreso para esta empresa. Intentar en unos segundos.'
  );
END IF;
-- El lock se libera automáticamente al hacer COMMIT o ROLLBACK de la transacción.
-- No requiere UNLOCK manual.
```

Ventaja sobre `LOCK TABLE`: un advisory lock por empresa no bloquea a otras empresas del sistema multi-tenant. `pg_try_advisory_xact_lock` falla inmediatamente (NOWAIT implícito) en lugar de quedar bloqueado indefinidamente.

### 3. Desactivación No Elimina Tablas — Datos Preservados

`module_uninstall()` en Odoo elimina registros de `ir.model.data` y sus objetos referenciados, pero **nunca hace DROP TABLE**. Las tablas SQL del módulo persisten con todos sus datos históricos.

PILAR sigue exactamente el mismo principio: `deactivate_module()` solo hace `UPDATE modulos_empresa SET activo = FALSE`. Las tablas del módulo permanecen en la BD íntegras.

Beneficios:
- Una empresa que prueba un modulo auxiliar, lo desactiva y luego lo reactiva recupera todos sus datos historicos
- RLS garantiza que una empresa con el módulo inactivo no puede acceder a sus propias tablas ni a las de otras empresas
- No existen migraciones de `DROP TABLE` que puedan fallar por foreign keys o triggers pendientes
- Compatible con auditorías: los datos nunca se destruyen por una desactivación de módulo

### 4. Posiciones del Sistema de Slots (Equivalente a `position=` de Odoo)

Odoo define 5 posiciones para herencia de vistas XML: `inside`, `before`, `after`, `replace`, `attributes`. El sistema `ModuleSlot` de PILAR cubre los mismos casos:

| Odoo `position` | Equivalente PILAR | Caso de uso en PILAR |
|-----------------|-------------------|----------------------|
| `inside` | `ModuleSlot` dentro de un formulario | Modulo auxiliar inyecta seccion en formulario de un modulo Core |
| `after` | `ModuleSlot` al final de una sección | Modulo auxiliar añade tab al detalle de una entidad Core |
| `before` | `ModuleSlot` antes de botones de acción | Modulo auxiliar añade boton antes de la accion principal |
| `replace` | `Consumer` condicional por módulo activo | Modulo auxiliar reemplaza un widget base con version extendida |
| `attributes` | Parámetros adicionales al `ModuleSlot` | `ModuleSlot(slotId: 'x', params: {'param': true})` |

Para los casos `replace` (no inyectar sino reemplazar el widget base):

```dart
// Equivalente a position="replace" de Odoo
Consumer(builder: (ctx, ref, _) {
  final activos = ref.watch(modulosActivosIdsProvider).valueOrNull ?? [];
  if (activos.contains('mi_auxiliar')) {
    return const BotonesAccionConExtension();  // widget ampliado del módulo auxiliar
  }
  return const BotonesAccionStandard();        // widget base del módulo core
})
```

### 5. Portal de Autoservicio — Patrón `access_token`

Odoo usa `PortalMixin` con `access_token = UUID` que permite a clientes externos acceder a un registro sin usuario Odoo. La URL `/web/portal?token=xyz` valida el token y retorna el documento sin requerir login.

PILAR implementa este mismo patron en cualquier entidad que necesite acceso de lectura externa sin autenticacion completa:

```sql
-- Cualquier tabla con acceso portal añade:
portal_token        UUID        DEFAULT gen_random_uuid() NOT NULL,
portal_expires_at   TIMESTAMPTZ NULL  -- NULL = no expira; fecha = token con vencimiento

-- Índice para búsqueda por token (acceso O(log n) desde Edge Function)
CREATE INDEX idx_<tabla>_portal_token ON <tabla>(portal_token) WHERE portal_token IS NOT NULL;
```

```typescript
// Edge Function: portal-view (verify_jwt: false — acceso por token, no por JWT)
const { token } = await req.json();
const { data: doc } = await supabase
  .from('<tabla>')
  .select('id, numero, total, estado, archivo_url')
  .eq('portal_token', token)
  .gt('portal_expires_at', new Date().toISOString())  // o IS NULL
  .single();
```

Aplica a: documentos para consulta externa (link en email/WhatsApp), solicitudes para seguimiento, eventos para confirmacion/cancelacion del usuario externo.

### 6. Verificación de Inicialización de Base de Datos

Odoo's `is_initialized()` = `SELECT table_exists(cr, 'ir_module_module')`. Una sola verificación de existencia de tabla como señal de que la BD fue inicializada. PILAR usa el mismo patrón:

```sql
-- Función de estado del sistema (llamada por la Edge Function de health-check)
CREATE OR REPLACE FUNCTION public.is_database_initialized()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS(
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'modulos'
  );
$$;
```

La migración `001_core_foundation.sql` crea la tabla `modulos` — si existe, el sistema está inicializado. No se necesita verificar 24 tablas; basta con la tabla raíz del sistema de módulos.

### 7. Grupos de Seguridad y Membresía Transitiva

Odoo implementa `implied_ids` en `res.groups`: si un usuario está en `group_erp_manager`, automáticamente hereda todos los permisos de `group_user`. La clausura transitiva se computa vía `all_implied_ids` (cacheado con `@ormcache`).

PILAR implementa el equivalente con roles jerárquicos. El rol `ADMIN` hereda todos los permisos, el rol `GERENTE` hereda ver+aprobar+reportes. La jerarquía está definida en `roles_permisos` (seed) y cacheada en el provider Riverpod:

```dart
// Caché de permisos del usuario actual — se invalida solo en cambio de empresa/rol
@riverpod
Future<Set<String>> misPermisos(Ref ref) async {
  final usuarioEmpresa = ref.watch(usuarioEmpresaProvider);
  // Lee de Brick SQLite (offline-first) — no round-trip a Supabase en cada check
  final permisos = await permisosRepo.get<PermisoUsuario>(
    query: Query(where: [Where('usuarioEmpresaId').isExactly(usuarioEmpresa.id)]),
  );
  return permisos.map((p) => p.codigo).toSet();
}

// Uso en cualquier widget (O(1) lookup en Set):
final tienePermiso = ref.watch(misPermisosProvider).valueOrNull
    ?.contains('<modulo>.<entidad>.<accion>') ?? false;
```

Importante: en Odoo los grupos `group_user`, `group_portal`, `group_public` son **disjuntos** (un usuario no puede estar en dos). PILAR implementa el mismo invariante: un usuario en una empresa tiene exactamente **un rol activo** (campo `rol_id` en `usuarios_empresa`, no array).

---

## Alternativas Rechazadas

### 1. Instalacion Dinamica de Codigo Flutter en Runtime

Descargar modulos como bytecode Dart o plugins en tiempo de ejecucion, similar a como Odoo descarga y carga codigo Python al instalar un modulo.

- Flutter compila a codigo nativo (AOT) en iOS/Android y a WebAssembly para web — el runtime no puede cargar codigo arbitrario descargado de un servidor. Dart no tiene equivalente a `importlib` de Python.
- En Android existe la posibilidad de Dynamic Feature Modules (Play Feature Delivery), pero solo para Android y con restricciones severas en el contenido (no puede redefinir providers Riverpod globales).
- La firma digital de iOS prohibe ejecutar codigo no incluido en el IPA original.
- **Rechazado por**: imposibilidad tecnica en las plataformas objetivo (iOS, WebAssembly).

### 2. Servidor de Modulos Externo — Microservicios por Modulo

Cada modulo es un microservicio separado con su propia API REST. Flutter llama al microservicio del modulo activo.

- Latencia adicional por HTTP para cada operacion interna entre modulos (ej: un modulo auxiliar crea un documento → llamada HTTP a servicio Core A → llamada HTTP a servicio Core B).
- Consistencia transaccional imposible: confirmar una operacion requiere atomicidad entre multiples modulos Core — con microservicios requeriria saga patterns o 2PC, complejidad fuera de alcance del equipo.
- El costo operativo de mantener 24 servicios separados en produccion es prohibitivo para el modelo SaaS Ecuador (clientes con bajo presupuesto).
- Ya existe el Module Service Bus en PostgreSQL (ADR-002) que resuelve la comunicacion inter-modulo de forma sincrona y transaccional.
- **Rechazado por**: complejidad operativa, latencia y problema de consistencia transaccional.

### 3. Feature Flags Simples sin Grafo de Dependencias

Usar un booleano por modulo en la configuracion de empresa, sin resolver dependencias automaticamente. El administrador activa manualmente cada modulo en el orden correcto.

- El administrador puede activar un modulo auxiliar sin activar el modulo Core del que depende, resultando en errores en runtime al intentar usar las funcionalidades que requieren ese Core.
- Sin orden topologico garantizado, la inicializacion de datos del modulo (post_install_rpc) puede fallar si los datos de la dependencia no existen.
- Odoo resolvio este problema en 2008 con su grafo de dependencias — PILAR no tiene razon para repetir el mismo error.
- **Rechazado por**: genera estados inconsistentes en la BD que son dificiles de diagnosticar en produccion.

### 4. Todos los Modulos Siempre Activos — Sin Activacion por Empresa

Compilar todos los modulos activos para todas las empresas, sin activacion selectiva. Una empresa pequena tendria acceso a todos los modulos auxiliares aunque no los use.

- El modelo de negocio SaaS de PILAR es por modulo activo: las empresas pagan solo lo que usan. Sin activacion selectiva no hay forma de facturar diferenciado.
- La UI con todos los modulos simultaneos es abrumadora para usuarios de empresas pequenas que solo necesitan un subconjunto.
- Las tablas de modulos auxiliares tendrian registros de todas las empresas aunque el modulo no este activo — confusion en auditorias y RLS mas complejo.
- **Rechazado por**: inviable para el modelo de negocio y genera mala UX para empresas con pocos modulos.

### 5. Copiar Exactamente el Sistema ir.module.module de Odoo sin Adaptacion

Implementar en PostgreSQL + Dart una replica del sistema Python de Odoo: tabla `ir_module_module`, `ir_module_module_dependency`, metaclase `MetaModel`, `Registry` dinamico, y vistas XML con `inherit_id`.

- El Registry dinamico de Odoo fusiona clases Python en memoria en tiempo de instalacion — Dart no tiene metaclases ni reflexion suficiente para hacer lo equivalente.
- Las vistas XML de Odoo generan HTML/QWeb en el servidor — Flutter genera widgets en el cliente. No hay equivalente 1:1.
- Copiar `ir_module_module` implica copiar tambien el ORM de Odoo (campos `Many2one`, `One2many`, `Char`, `Float`...) — un proyecto de anios de trabajo.
- **Rechazado por**: la arquitectura de Odoo esta profundamente acoplada a Python/ORM/QWeb. PILAR adopta los conceptos (estados de modulo, grafo de dependencias, inyeccion de vistas) pero los reimplementa en el stack PostgreSQL + Dart/Flutter de forma idiomatica.

---

## Consecuencias

### Positivas

- El grafo de dependencias en PostgreSQL garantiza que nunca se puede tener un modulo activo con sus dependencias inactivas — el mismo invariante que Odoo pero ejecutado por la BD, no por el framework Python.
- `activate_module()` y `deactivate_module()` son funciones SECURITY DEFINER auditables, testables con `pgTAP` y observables desde Supabase Studio.
- El `ModuleRegistry` compilado implica que el bundle de Flutter siempre contiene todos los modulos — no hay descarga parcial. El costo es un binario algo mayor, compensado por el hecho de que Flutter hace tree-shaking del codigo no referenciado.
- El sistema de slots (`ModuleSlot`) permite que un modulo auxiliar inyecte una seccion en la pantalla de un modulo Core sin que el modulo Core tenga una dependencia directa del modulo auxiliar — el mismo principio de Odoo `inherit_id` pero tipado en Dart.
- Anadir un nuevo modulo tiene un procedimiento claro y repetible: 1 archivo Dart + 1 linea en registry + 1 migracion SQL. No hay magia.
- El trigger `tr_empresa_infraestructura` garantiza que toda empresa nueva tiene los 3 modulos de Infraestructura activos desde el primer segundo, sin pasos manuales — equivalente al `base_data.sql` de Odoo.

### Negativas / Restricciones

- Todos los modulos estan compilados en el binario Flutter aunque la empresa no los tenga activos. Anadir un modulo grande aumenta el tamaño del bundle para todas las empresas, no solo las que lo usan. Mitigado con lazy loading de assets (imagenes, PDFs) y tree-shaking de Dart.
- Activar un modulo en produccion requiere que la migracion SQL ya este aplicada en Supabase (`supabase db push` o migracion ya ejecutada). Si el administrador activa el modulo desde Flutter antes de que corra la migracion, la funcion `activate_module()` puede insertar en `modulos_empresa` pero las tablas del modulo no existiran — el desarrollador debe asegurarse de desplegar migraciones antes de habilitar el modulo en el plan SaaS.
- La funcion `post_install_rpc` ejecuta SQL dinamico con `EXECUTE` — requiere validacion estricta del nombre de la funcion para evitar inyeccion SQL (el nombre viene de la columna `modulos.post_install_rpc`, nunca de input del usuario).
- El sistema de slots es voluntario: si un modulo no llama a `ModuleSlot` en su pantalla, ningun otro modulo puede inyectar alli. Requiere que los modulos Core definan sus puntos de extension de forma anticipada.
- Desactivar un modulo Core que tiene modulos Auxiliares activos dependientes retorna error y lista los dependientes — el administrador debe desactivar primero los Auxiliares. Este orden inverso puede sorprender a usuarios acostumbrados a Odoo, que desinstala en cascada.

---

## Referencias

- ADR-002 — Module Service Bus (las funciones gateway del bus verifican `modulos_empresa.activo`)
- ADR-003 — Patron RLS (`modulos_empresa` usa `private.get_empresa_id()` en sus policies)
- ADR-004 — Flutter single codebase (la restriccion de compilacion AOT es la razon del ModuleRegistry)
- Odoo source: `odoo/modules/module.py` — `load_manifest`, `get_modules` (referencia conceptual)
- Odoo source: `odoo/modules/registry.py` — `Registry.__new__`, `_init_modules` (referencia conceptual)
- Odoo source: `odoo/addons/base/data/base_data.sql` — inicializacion BD (referencia conceptual)
