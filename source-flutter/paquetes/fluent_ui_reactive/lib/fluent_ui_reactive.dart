/// fluent_ui_reactive — Reactive fluent_ui widgets for PILAR ERP.
///
/// Widgets that automatically update when local SQLite (Brick) data changes,
/// using Riverpod [AsyncValue] as the reactive bridge.
///
/// ## Reactive pattern
///
/// ```dart
/// // 1. Define a StreamProvider wrapping Brick's subscribe()
/// @riverpod
/// Stream<List<Factura>> facturas(Ref ref) =>
///     ref.watch(facturaRepoProvider).subscribe();
///
/// // 2. Use a reactive widget in a ConsumerWidget
/// PilarStreamGrid<Factura>(
///   value: ref.watch(facturasProvider),
///   columns: [...],
///   rowToMap: (f) => {'numero': f.numero, 'total': f.total},
/// )
/// ```
///
/// When SQLite changes → Stream emits → Riverpod updates [AsyncValue]
/// → Widget rebuilds automatically. No manual refresh needed.
library fluent_ui_reactive;

// Core
export 'src/core/pilar_async_builder.dart';
export 'src/core/pilar_theme_ext.dart';

// Models
export 'src/display/models.dart';

// Display — reactive data display widgets
export 'src/display/pilar_stream_grid.dart';
export 'src/display/pilar_stream_list.dart';

// Input — reactive input widgets with async data sources
export 'src/input/pilar_entity_combo_box.dart';
export 'src/input/pilar_search_field.dart';

// Form — fluent_ui form components with validation
export 'src/form/pilar_form.dart';
export 'src/form/pilar_text_field.dart';
export 'src/form/pilar_number_field.dart';
export 'src/form/pilar_date_field.dart';

// Feedback — notifications, error handling
export 'src/feedback/pilar_copy_button.dart';
export 'src/feedback/pilar_notification.dart';
export 'src/feedback/pilar_error_registry.dart';

// Workspace — dynamic tab management
export 'src/workspace/workspace_tabs.dart';

// CRUD scaffolds — generic list + form screens
export 'src/crud/form_section.dart';
export 'src/crud/form_scaffold.dart';
export 'src/crud/pilar_form_dialog.dart';
export 'src/crud/crud_scaffold.dart';
export 'src/crud/filter_panel.dart';
export 'src/crud/export_button.dart';
