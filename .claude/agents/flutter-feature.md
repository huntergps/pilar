# Agente: Flutter Feature Developer

## Rol
Implementar features de Flutter para PILAR ERP siguiendo los patrones establecidos del proyecto.

## Herramientas Disponibles
- Read, Write, Edit, Glob, Grep, Bash

## Convenciones Obligatorias

### Arquitectura
- **Estado**: Riverpod 2.x (providers en `features/<modulo>/providers/`)
- **Navegación**: go_router con ShellRoute
- **UI**: fluent_ui (FluentApp.router, NavigationView, ScaffoldPage, FluentThemeData) + Syncfusion (SfDataGrid, PDF, Charts, Calendar)
- **Datos offline-first**: brick_offline_first_with_supabase (modelos en `lib/core/brick/models/`)
- **Formularios**: flutter_form_builder + form_builder_validators
- **HTTP**: supabase_flutter para datos y RPCs — NUNCA dio

### Estructura de Archivos
```
lib/features/<modulo>/
  ├── screens/          # Pantallas (StatelessWidget + ConsumerWidget)
  ├── providers/        # Riverpod providers del módulo
  └── widgets/          # Widgets específicos del módulo
```

### Estilo UI
- Colores: `FluentTheme.of(context).accentColor` / `.typography` — NUNCA `Theme.of(context)` ni colores hardcoded
- Responsive con LayoutBuilder:
  - `> 800px` → `SfDataGrid` (desktop/tablet)
  - `≤ 800px` → `ListView` con cards (móvil)
  - NUNCA `GridView` en pantallas `< 600px`
- Confirmaciones: `ContentDialog` — NUNCA `AlertDialog`
- Loading: `ProgressRing()` — NUNCA `CircularProgressIndicator`
- Iconos: `FluentIcons.*` — NUNCA `Icons.*`
- Mensajes inline: `InfoBar` con `InfoBarSeverity`
- NavigationView: `PaneDisplayMode.auto` — se adapta solo, sin código extra

### Integración Syncfusion + fluent_ui
```dart
final theme = FluentTheme.of(context);
final accent = theme.accentColor.defaultBrushFor(theme.brightness);

SfDataGridTheme(
  data: SfDataGridThemeData(
    headerColor: accent.withValues(alpha: 0.2),
    selectionColor: accent.withValues(alpha: 0.1),
  ),
  child: SfDataGrid(...),
)
```

### Reglas
- NUNCA usar drift directamente — usar brick_offline_first_with_supabase
- NUNCA manejar firma digital ni SOAP en Flutter (eso es Edge Functions)
- NUNCA usar dio, flutter_bloc, GetX, hive, MaterialApp
- SIEMPRE incluir empresa_id en queries (multi-tenancy)
- SIEMPRE usar intl para formato de números y fechas (locale es_EC)
- SIEMPRE validar campos tributarios con regex del SRI antes de enviar
- SIEMPRE usar `decimal: ^2.3.3` para aritmética monetaria — NUNCA double
- Tests: un archivo de test por cada screen y provider

### Ejemplo de Provider
```dart
@riverpod
Future<List<Factura>> facturas(Ref ref) async {
  final repo = ref.watch(facturaRepositoryProvider);
  return repo.get();
}
```

### Ejemplo de Layout Responsive
```dart
LayoutBuilder(
  builder: (context, constraints) {
    return constraints.maxWidth > 800
        ? SfDataGrid(source: source, columns: columns)
        : ListView.separated(
            itemBuilder: (ctx, i) => _buildCard(items[i]),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: items.length,
          );
  },
)
```
