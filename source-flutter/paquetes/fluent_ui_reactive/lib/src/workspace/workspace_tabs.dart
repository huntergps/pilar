import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Una pestaña dentro del workspace dinámico.
///
/// Cada tab tiene un [id] único, un [title] y un [body] con el widget a mostrar.
/// El [isDirty] flag indica cambios sin guardar (muestra un punto en el tab).
/// El [closeable] flag controla si el tab puede cerrarse.
@immutable
class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.title,
    required this.body,
    this.icon,
    this.isDirty = false,
    this.closeable = true,
  });

  final String id;
  final String title;
  final Widget body;
  final IconData? icon;
  final bool isDirty;
  final bool closeable;

  WorkspaceTab copyWith({
    String? title,
    Widget? body,
    IconData? icon,
    bool? isDirty,
    bool? closeable,
  }) {
    return WorkspaceTab(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      icon: icon ?? this.icon,
      isDirty: isDirty ?? this.isDirty,
      closeable: closeable ?? this.closeable,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is WorkspaceTab && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

// ---------------------------------------------------------------------------
// State Notifier
// ---------------------------------------------------------------------------

/// Estado del workspace de pestañas.
class WorkspaceTabsState {
  const WorkspaceTabsState({
    this.tabs = const [],
    this.selectedIndex = 0,
  });

  final List<WorkspaceTab> tabs;
  final int selectedIndex;

  WorkspaceTab? get selectedTab =>
      tabs.isEmpty ? null : tabs[selectedIndex.clamp(0, tabs.length - 1)];

  WorkspaceTabsState copyWith({
    List<WorkspaceTab>? tabs,
    int? selectedIndex,
  }) {
    return WorkspaceTabsState(
      tabs: tabs ?? this.tabs,
      selectedIndex: selectedIndex ?? this.selectedIndex,
    );
  }
}

/// Gestiona la lista de pestañas del workspace y la pestaña seleccionada.
///
/// Uso:
/// ```dart
/// final tabs = ref.read(workspaceTabsProvider.notifier);
/// tabs.open(WorkspaceTab(id: 'cliente-42', title: 'Empresa ACME', body: ...));
/// tabs.close('cliente-42');
/// tabs.markDirty('cliente-42');
/// ```
class WorkspaceTabsNotifier extends Notifier<WorkspaceTabsState> {
  @override
  WorkspaceTabsState build() => const WorkspaceTabsState();

  /// Abre una nueva pestaña o activa la existente si [tab.id] ya está abierta.
  void open(WorkspaceTab tab) {
    final existing = state.tabs.indexWhere((t) => t.id == tab.id);
    if (existing >= 0) {
      state = state.copyWith(selectedIndex: existing);
      return;
    }
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(
      tabs: newTabs,
      selectedIndex: newTabs.length - 1,
    );
  }

  /// Cierra la pestaña con [id]. Si hay otras pestañas, activa la adyacente.
  void close(String id) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final tab = state.tabs[idx];
    if (!tab.closeable) return;

    final newTabs = [...state.tabs]..removeAt(idx);
    int newSelected = state.selectedIndex;
    if (newTabs.isEmpty) {
      newSelected = 0;
    } else if (newSelected >= newTabs.length) {
      newSelected = newTabs.length - 1;
    }
    state = state.copyWith(tabs: newTabs, selectedIndex: newSelected);
  }

  /// Cierra todas las pestañas que tienen [closeable] = true.
  void closeAll() {
    final remaining = state.tabs.where((t) => !t.closeable).toList();
    state = state.copyWith(tabs: remaining, selectedIndex: 0);
  }

  /// Activa la pestaña en la posición [index].
  void select(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = state.copyWith(selectedIndex: index);
  }

  /// Activa la pestaña con [id].
  void selectById(String id) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx >= 0) state = state.copyWith(selectedIndex: idx);
  }

  /// Marca la pestaña [id] como con cambios sin guardar ([isDirty] = true).
  void markDirty(String id) => _updateTab(id, (t) => t.copyWith(isDirty: true));

  /// Limpia el flag de cambios no guardados en la pestaña [id].
  void markClean(String id) =>
      _updateTab(id, (t) => t.copyWith(isDirty: false));

  /// Actualiza el título de la pestaña [id].
  void updateTitle(String id, String newTitle) =>
      _updateTab(id, (t) => t.copyWith(title: newTitle));

  void _updateTab(String id, WorkspaceTab Function(WorkspaceTab) update) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final newTabs = [...state.tabs];
    newTabs[idx] = update(newTabs[idx]);
    state = state.copyWith(tabs: newTabs);
  }
}

/// Provider global del workspace de pestañas.
///
/// Úsalo con un [ProviderScope] sobreescrito para aislar workspaces
/// independientes por módulo:
/// ```dart
/// ProviderScope(
///   overrides: [workspaceTabsProvider.overrideWith(WorkspaceTabsNotifier.new)],
///   child: WorkspaceTabs(),
/// )
/// ```
final workspaceTabsProvider =
    NotifierProvider<WorkspaceTabsNotifier, WorkspaceTabsState>(
  WorkspaceTabsNotifier.new,
);

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Widget de pestañas dinámicas para el workspace de PILAR ERP.
///
/// Renderiza los [WorkspaceTab]s del [workspaceTabsProvider] usando el
/// [TabView] de fluent_ui. Soporta cierre de pestañas, indicador de cambios
/// no guardados (punto azul) y un placeholder cuando no hay pestañas abiertas.
///
/// ### Ejemplo básico
/// ```dart
/// const WorkspaceTabs()
/// ```
///
/// ### Con placeholder personalizado
/// ```dart
/// WorkspaceTabs(
///   emptyBuilder: (_) => const Text('Abre un registro para comenzar'),
/// )
/// ```
class WorkspaceTabs extends ConsumerWidget {
  const WorkspaceTabs({
    super.key,
    this.emptyBuilder,
    this.tabWidthBehavior = TabWidthBehavior.sizeToContent,
    this.showScrollButtons = true,
  });

  /// Widget a mostrar cuando no hay pestañas abiertas.
  final WidgetBuilder? emptyBuilder;

  /// Comportamiento de ancho de los tabs (por defecto: ajustar al contenido).
  final TabWidthBehavior tabWidthBehavior;

  /// Si se muestran los botones de scroll cuando hay muchas pestañas.
  final bool showScrollButtons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceTabsProvider);
    final notifier = ref.read(workspaceTabsProvider.notifier);

    if (state.tabs.isEmpty) {
      return emptyBuilder?.call(context) ?? const _DefaultEmptyState();
    }

    final currentIndex =
        state.selectedIndex.clamp(0, state.tabs.length - 1);

    return TabView(
      currentIndex: currentIndex,
      onChanged: notifier.select,
      onNewPressed: null,
      tabWidthBehavior: tabWidthBehavior,
      showScrollButtons: showScrollButtons,
      closeButtonVisibility: CloseButtonVisibilityMode.always,
      tabs: state.tabs.map((tab) {
        return Tab(
          text: _TabTitle(tab: tab),
          icon: tab.icon != null ? Icon(tab.icon, size: 14) : null,
          body: tab.body,
          semanticLabel: tab.title,
          onClosed: tab.closeable
              ? () {
                  if (!tab.isDirty) {
                    notifier.close(tab.id);
                  } else {
                    _confirmClose(context, tab, notifier);
                  }
                }
              : null,
        );
      }).toList(),
    );
  }

  Future<void> _confirmClose(
    BuildContext context,
    WorkspaceTab tab,
    WorkspaceTabsNotifier notifier,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('Cambios sin guardar'),
        content: Text(
            '"${tab.title}" tiene cambios sin guardar. ¿Cerrar de todas formas?'),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.errorPrimaryColor),
            ),
            child: const Text('Cerrar sin guardar'),
          ),
        ],
      ),
    );
    if (ok == true) notifier.close(tab.id);
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _TabTitle extends StatelessWidget {
  const _TabTitle({required this.tab});
  final WorkspaceTab tab;

  @override
  Widget build(BuildContext context) {
    if (!tab.isDirty) return Text(tab.title);
    final theme = FluentTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tab.title),
        const SizedBox(width: 4),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: theme.accentColor,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class _DefaultEmptyState extends StatelessWidget {
  const _DefaultEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.open_pane,
            size: 48,
            color: theme.resources.textFillColorDisabled,
          ),
          const SizedBox(height: 12),
          Text(
            'No hay pestañas abiertas',
            style: theme.typography.subtitle?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
