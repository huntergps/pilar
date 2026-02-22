# Arquitectura Modular del Sistema

## Clasificación de Módulos

El criterio es **arquitectónico** (quién provee servicios a quién), no operacional:

| Tipo | Criterio | Comportamiento |
|------|----------|----------------|
| **Infraestructura** | Siempre activos, no desactivables. Base del sistema. | No requieren activación; sus rutas y menús están siempre presentes. |
| **Core** | Proveen servicios vía `module_bus.*`. Backbone del ERP. | Activables por empresa; otros módulos pueden depender de ellos. |
| **Auxiliar** | Consumen servicios de Core. Nunca INSERT directo en tablas Core. | Activables por empresa/plan; se desactivan sin afectar a otros módulos. |

> **Regla del Module Service Bus**: los módulos Auxiliares llaman a `module_bus.*` — funciones gateway que verifican si el módulo Core destino está activo. Si no está activo retornan NO-OP en lugar de error.

> **Auth y Catálogos no son módulos**: Auth es un servicio de plataforma (Supabase Auth); los catálogos (países, monedas, bancos, tarifas fiscales) son seed data en migraciones SQL de Foundation, no módulos activables.

---

## Implementación del Sistema Modular

Flutter es compilado — no puede añadir código en runtime como Python. Sin embargo, PILAR puede **activar/desactivar módulos registrados en tiempo de compilación** gracias a `modulos_empresa` en PostgreSQL + providers Riverpod que reconstruyen el router y el menú según los módulos activos.

| Concepto Odoo | Equivalente PILAR |
|---------------|-------------------|
| `addons_path` escaneo en disco | `ModuleRegistry._allModules` en Dart (compilado, mapa estático) |
| `ir_module_module` | Tabla `modulos` con campo `estado` |
| `ir_module_module_dependency` | Tabla `modulo_dependencias` |
| `_state_update()` recursivo | `resolve_module_dependencies()` (CTE recursivo en PostgreSQL) |
| `button_immediate_install()` | `activate_module()` en PostgreSQL + invalidación de provider Riverpod |
| `Registry.load()` | `ModuleRegistry.activeModules()` + reconstrucción de `appRouter` |
| `_inherit` (extensión de modelo Python) | `ModuleSlot` + composición de providers Riverpod |
| `ir.rule` (seguridad a nivel de registro) | RLS con `private.get_empresa_id()` en cada tabla |
| Vista `inherit_id` + `xpath` | `ModuleSlot` con `slotId` definidos en pantallas core |
| `post_init_hook` | `PilarModule.onActivate(Ref ref)` |
| Nuevo addon en `addons_path` | Nueva carpeta `features/` + registro en `ModuleRegistry._allModules` |

---

## Capa PostgreSQL: Tablas y Funciones

### Tabla `modulos`

```sql
ALTER TABLE modulos ADD COLUMN IF NOT EXISTS version          TEXT DEFAULT '1.0';
ALTER TABLE modulos ADD COLUMN IF NOT EXISTS estado           TEXT DEFAULT 'uninstalled'
    CHECK (estado IN ('uninstalled', 'installed', 'to_install', 'to_remove', 'uninstallable'));
ALTER TABLE modulos ADD COLUMN IF NOT EXISTS auto_install     BOOLEAN DEFAULT FALSE;
ALTER TABLE modulos ADD COLUMN IF NOT EXISTS post_install_rpc TEXT;
```

### Tabla `modulo_dependencias`

```sql
CREATE TABLE IF NOT EXISTS modulo_dependencias (
    modulo_id   TEXT NOT NULL REFERENCES modulos(id) ON DELETE CASCADE,
    depende_de  TEXT NOT NULL REFERENCES modulos(id),
    requerido   BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (modulo_id, depende_de)
);

CREATE INDEX IF NOT EXISTS idx_modulo_dependencias_depende_de
    ON modulo_dependencias(depende_de);
```

El seed completo de módulos y dependencias está en la migración `001_core_foundation.sql`.

### `resolve_module_dependencies(p_modulo_id)`

Resuelve el árbol completo de dependencias en orden topológico:

```sql
CREATE OR REPLACE FUNCTION resolve_module_dependencies(p_modulo_id TEXT)
RETURNS TABLE(modulo_id TEXT, nivel INT)
LANGUAGE sql STABLE AS $$
    WITH RECURSIVE deps AS (
        SELECT p_modulo_id AS modulo_id, 0 AS nivel
        UNION ALL
        SELECT md.depende_de, deps.nivel + 1
        FROM modulo_dependencias md
        JOIN deps ON deps.modulo_id = md.modulo_id
        WHERE md.requerido = TRUE
    )
    SELECT DISTINCT ON (modulo_id) modulo_id, MAX(nivel) AS nivel
    FROM deps
    GROUP BY modulo_id
    ORDER BY modulo_id, MAX(nivel) DESC;
$$;
```

### `activate_module(p_empresa_id, p_modulo_id)`

Activa un módulo para una empresa incluyendo todas sus dependencias:

```sql
CREATE OR REPLACE FUNCTION activate_module(
    p_empresa_id UUID,
    p_modulo_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_modulos_a_activar TEXT[];
    v_modulo             TEXT;
    v_activados          TEXT[] := '{}';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM modulos WHERE id = p_modulo_id) THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'Módulo no encontrado: ' || p_modulo_id);
    END IF;

    SELECT array_agg(modulo_id ORDER BY nivel DESC)
    INTO v_modulos_a_activar
    FROM resolve_module_dependencies(p_modulo_id);

    IF EXISTS (
        SELECT 1 FROM unnest(v_modulos_a_activar) AS m(id)
        WHERE NOT EXISTS (SELECT 1 FROM modulos WHERE modulos.id = m.id)
    ) THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'Una o más dependencias no están registradas');
    END IF;

    FOREACH v_modulo IN ARRAY v_modulos_a_activar LOOP
        INSERT INTO modulos_empresa (empresa_id, modulo_id)
        VALUES (p_empresa_id, v_modulo)
        ON CONFLICT (empresa_id, modulo_id) DO NOTHING;

        IF FOUND THEN
            v_activados := array_append(v_activados, v_modulo);
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'ok',        TRUE,
        'activados', to_jsonb(v_activados),
        'total',     array_length(v_activados, 1)
    );
END;
$$;
```

### `deactivate_module(p_empresa_id, p_modulo_id)`

Desactiva un módulo verificando que ningún otro módulo activo depende de él:

```sql
CREATE OR REPLACE FUNCTION deactivate_module(
    p_empresa_id UUID,
    p_modulo_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_dependientes TEXT[];
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM modulos_empresa
        WHERE empresa_id = p_empresa_id AND modulo_id = p_modulo_id
    ) THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'El módulo no está activo para esta empresa');
    END IF;

    SELECT array_agg(me.modulo_id)
    INTO v_dependientes
    FROM modulos_empresa me
    JOIN modulo_dependencias md ON md.modulo_id = me.modulo_id
    WHERE me.empresa_id = p_empresa_id
      AND md.depende_de  = p_modulo_id
      AND md.requerido   = TRUE
      AND me.modulo_id  != p_modulo_id;

    IF v_dependientes IS NOT NULL AND array_length(v_dependientes, 1) > 0 THEN
        RETURN jsonb_build_object(
            'ok',           FALSE,
            'error',        'No se puede desactivar: otros módulos activos dependen de este',
            'dependientes', to_jsonb(v_dependientes)
        );
    END IF;

    DELETE FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = p_modulo_id;

    RETURN jsonb_build_object('ok', TRUE, 'desactivado', p_modulo_id);
END;
$$;
```

---

## Capa Flutter: ModuleRegistry y PilarModule

### Interface `PilarModule`

Cada módulo implementa esta interfaz para integrarse con el sistema:

```dart
abstract class PilarModule {
  /// Identificador único (debe coincidir con modulos.id en PostgreSQL)
  String get id;
  String get nombre;
  String get descripcion;
  IconData get icono;
  Color? get color;

  /// IDs de módulos requeridos (debe coincidir con modulo_dependencias donde requerido=TRUE)
  List<String> get dependencias;

  /// Rutas go_router que este módulo aporta al router global
  List<RouteBase> get routes;

  /// Grupos de menú que aparecen en el ModuleMenuBar cuando este módulo está activo
  List<PilarMenuGroup> get menuItems;

  /// Widgets KPI que este módulo aporta al Dashboard
  List<DashboardWidgetDef> get dashboardWidgets;

  /// Widgets que este módulo inyecta en slots de pantallas de otros módulos
  /// Clave: slotId, Valor: WidgetBuilder
  Map<String, WidgetBuilder> get slotWidgets;

  /// Hook post-activación. Se ejecuta tras activar el módulo para la empresa.
  Future<void> onActivate(Ref ref) async {}

  /// Hook pre-desactivación.
  Future<void> onDeactivate(Ref ref) async {}
}
```

### `ModuleRegistry`

Registro estático de todos los módulos compilados. La activación por empresa es dinámica y viene de PostgreSQL:

```dart
class ModuleRegistry {
  ModuleRegistry._();

  /// Todos los módulos registrados en la app (compilados).
  /// Cada módulo se añade aquí al implementarse.
  static final Map<String, PilarModule> _allModules = {
    // '<modulo_id>': ModuloModule(),
  };

  /// Retorna solo los módulos cuyo ID está activo para la empresa autenticada.
  static List<PilarModule> activeModules(List<String> idsActivos) {
    return idsActivos
        .map((id) => _allModules[id])
        .whereType<PilarModule>()
        .toList();
  }

  static PilarModule? get(String id) => _allModules[id];
}
```

### Router dinámico con Riverpod

```dart
@riverpod
GoRouter appRouter(Ref ref) {
  final modulosActivos = ref.watch(modulosActivosProvider);

  final rutasModulos = modulosActivos
      .expand((modulo) => modulo.routes)
      .toList();

  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (context, state, child) => PilarShell(child: child),
        routes: [
          // Rutas de infraestructura (siempre presentes)
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/admin',     builder: (_, __) => const AdministracionScreen()),
          // Rutas dinámicas de módulos activos
          ...rutasModulos,
        ],
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    ],
  );
}
```

### Sistema de slots (`ModuleSlot`)

Permite que módulos activos inyecten widgets en pantallas de otros módulos sin acoplamiento directo:

```dart
class ModuleSlot extends ConsumerWidget {
  /// Identificador del slot donde se inyectarán widgets
  final String slotId;
  final Map<String, dynamic> context;

  const ModuleSlot({required this.slotId, this.context = const {}, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modulosActivos = ref.watch(modulosActivosProvider);

    final builders = modulosActivos
        .map((m) => m.slotWidgets[slotId])
        .whereType<WidgetBuilder>()
        .toList();

    if (builders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: builders.map((b) => b(context)).toList(),
    );
  }
}
```

Cada módulo declara los slots que provee en `slotWidgets` y los slots que consume se colocan en las pantallas con `ModuleSlot(slotId: '...')`.

---

## Ciclo de Vida: Activar un Módulo

Flujo completo cuando un administrador activa un módulo:

```
1. Admin hace tap en "Activar [Módulo]" en la pantalla de administración

2. Flutter llama activate_module(empresa_id, 'modulo_id') via RPC

3. PostgreSQL ejecuta resolve_module_dependencies('modulo_id')
   → CTE recursivo retorna todos los módulos requeridos en orden topológico

4. INSERT INTO modulos_empresa para cada módulo en la cadena,
   respetando orden (dependencias primero)

5. Supabase Realtime emite evento INSERT en canal 'modulos_empresa'
   → Solo el cliente de la empresa afectada lo recibe (canal filtrado por empresa_id)

6. Brick intercepta el evento Realtime y actualiza SQLite local

7. modulosActivosProvider se invalida automáticamente
   → Riverpod recalcula la lista leyendo SQLite local

8. appRouter (GoRouter) se reconstruye con las rutas del módulo activado

9. App Launcher muestra el ícono del módulo (antes desactivado, ahora activo)
   → ModuleMenuBar incluye el menú del módulo

10. PilarModule.onActivate(ref) se ejecuta si el módulo necesita setup inicial
```

---

## Añadir un Módulo Nuevo

```
1. Crear migración SQL con tablas + RLS + índices
   → Incluir: CREATE TABLE, RLS (empresa_id = (SELECT private.get_empresa_id())),
              índices sobre empresa_id y columnas de búsqueda frecuente

2. Añadir INSERT INTO modulos + modulo_dependencias en la misma migración

3. Crear lib/features/<modulo>/<modulo>_module.dart implementando PilarModule
   → Declarar id, nombre, descripcion, icono, color
   → Implementar routes, menuItems, dashboardWidgets, slotWidgets

4. Registrar en ModuleRegistry._allModules
   → '<modulo>': NuevoModuloModule()

5. Definir los slots que el módulo inyecta en pantallas de otros módulos (slotWidgets)
   → En la pantalla destino añadir: ModuleSlot(slotId: '...')

6. (Opcional) Crear Edge Functions si el módulo necesita procesamiento backend

7. (Opcional) Añadir funciones al Module Service Bus si el módulo provee servicios a otros
   → CREATE FUNCTION module_bus.<modulo>.<funcion>() SECURITY DEFINER
   → Verificar si el módulo está activo antes de ejecutar (retornar NO-OP si no)
```

### Estructura de archivos

```
lib/features/<modulo>/
├── <modulo>_module.dart       # class <Modulo>Module implements PilarModule
├── screens/
│   ├── <modulo>_list_screen.dart
│   └── <modulo>_detail_screen.dart
├── providers/
│   └── <modulo>_providers.dart
├── widgets/
│   └── <modulo>_card.dart
└── models/                    # Solo si el módulo tiene modelos Brick propios
    └── <modulo>.dart          # @ConnectOfflineFirstWithSupabase
```
