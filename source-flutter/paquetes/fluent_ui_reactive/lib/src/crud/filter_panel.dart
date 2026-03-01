import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

/// Type of filter field rendered in [FilterPanel].
enum FilterFieldType {
  /// Free-text filter with debounce.
  text,

  /// Dropdown selection from a fixed list of options.
  select,

  /// Date range with "from" and "to" pickers.
  dateRange,

  /// Toggle switch for boolean values.
  boolean,
}

/// Defines a single filter field for [FilterPanel].
class FilterField {
  /// Creates a filter field definition.
  const FilterField({
    required this.key,
    required this.label,
    required this.type,
    this.options,
  });

  /// Key used in the filters map emitted by [FilterPanel.onChanged].
  final String key;

  /// Human-readable label shown above the field.
  final String label;

  /// The type of input control to render.
  final FilterFieldType type;

  /// For [FilterFieldType.select]: list of (value, label) pairs.
  final List<(String, String)>? options;
}

/// A collapsible side panel with filter controls for CRUD lists.
///
/// Renders a 240px-wide panel (when expanded) with fields defined by
/// [fields]. Emits a map of active filters via [onChanged] whenever
/// any filter value changes.
///
/// ### Example
/// ```dart
/// FilterPanel(
///   fields: [
///     FilterField(key: 'nombre', label: 'Nombre', type: FilterFieldType.text),
///     FilterField(
///       key: 'estado',
///       label: 'Estado',
///       type: FilterFieldType.select,
///       options: [('activo', 'Activo'), ('inactivo', 'Inactivo')],
///     ),
///   ],
///   onChanged: (filters) => setState(() => _filters = filters),
/// )
/// ```
class FilterPanel extends StatefulWidget {
  /// Creates a [FilterPanel].
  const FilterPanel({
    required this.fields,
    required this.onChanged,
    super.key,
    this.initialFilters = const {},
  });

  /// The filter fields to render.
  final List<FilterField> fields;

  /// Called whenever a filter value changes. The map contains only
  /// non-null, non-empty filter values keyed by [FilterField.key].
  final void Function(Map<String, dynamic> filters) onChanged;

  /// Initial filter values to pre-populate.
  final Map<String, dynamic> initialFilters;

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  bool _expanded = false;
  final Map<String, dynamic> _filters = {};
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, Timer> _debounceTimers = {};

  @override
  void initState() {
    super.initState();
    _filters.addAll(widget.initialFilters);

    // Create text controllers for text fields
    for (final field in widget.fields) {
      if (field.type == FilterFieldType.text) {
        final initial = widget.initialFilters[field.key]?.toString() ?? '';
        _textControllers[field.key] = TextEditingController(text: initial);
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _textControllers.values) {
      ctrl.dispose();
    }
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  int get _activeFilterCount {
    var count = 0;
    for (final entry in _filters.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.isEmpty) continue;
      if (value is Map) {
        // dateRange: count if at least one date is set
        if (value['from'] != null || value['to'] != null) count++;
        continue;
      }
      count++;
    }
    return count;
  }

  void _emitFilters() {
    // Build a clean map without empty values
    final clean = <String, dynamic>{};
    for (final entry in _filters.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.isEmpty) continue;
      if (value is Map && value['from'] == null && value['to'] == null) {
        continue;
      }
      clean[entry.key] = value;
    }
    widget.onChanged(clean);
  }

  void _clearAll() {
    setState(() {
      _filters.clear();
      for (final ctrl in _textControllers.values) {
        ctrl.clear();
      }
    });
    _emitFilters();
  }

  void _setFilter(String key, dynamic value) {
    setState(() {
      if (value == null ||
          (value is String && value.isEmpty) ||
          (value is Map && value['from'] == null && value['to'] == null)) {
        _filters.remove(key);
      } else {
        _filters[key] = value;
      }
    });
    _emitFilters();
  }

  // ---------------------------------------------------------------------------
  // Field builders
  // ---------------------------------------------------------------------------

  Widget _buildTextField(FilterField field) {
    final ctrl = _textControllers[field.key]!;
    return InfoLabel(
      label: field.label,
      child: TextBox(
        controller: ctrl,
        placeholder: 'Filtrar\u2026',
        onChanged: (value) {
          _debounceTimers[field.key]?.cancel();
          _debounceTimers[field.key] = Timer(
            const Duration(milliseconds: 400),
            () => _setFilter(field.key, value),
          );
        },
        suffix: ctrl.text.isNotEmpty
            ? Button(
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                ),
                onPressed: () {
                  ctrl.clear();
                  _setFilter(field.key, null);
                },
                child: const Icon(FluentIcons.cancel, size: 12),
              )
            : null,
      ),
    );
  }

  Widget _buildSelectField(FilterField field) {
    final currentValue = _filters[field.key] as String?;
    return InfoLabel(
      label: field.label,
      child: ComboBox<String>(
        value: currentValue,
        isExpanded: true,
        placeholder: const Text('Todos'),
        items: [
          const ComboBoxItem<String>(
            value: null,
            child: Text('Todos'),
          ),
          if (field.options != null)
            ...field.options!.map(
              (opt) => ComboBoxItem<String>(
                value: opt.$1,
                child: Text(opt.$2),
              ),
            ),
        ],
        onChanged: (val) => _setFilter(field.key, val),
      ),
    );
  }

  Widget _buildBooleanField(FilterField field) {
    final currentValue = _filters[field.key] as bool?;
    return InfoLabel(
      label: field.label,
      child: ToggleSwitch(
        checked: currentValue ?? false,
        onChanged: (val) => _setFilter(field.key, val ? true : null),
      ),
    );
  }

  Widget _buildDateRangeField(FilterField field) {
    final range = _filters[field.key] as Map<String, DateTime?>? ?? {};
    return InfoLabel(
      label: field.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DatePicker(
            header: 'Desde',
            selected: range['from'],
            onChanged: (date) {
              final updated = Map<String, DateTime?>.from(range);
              updated['from'] = date;
              _setFilter(field.key, updated);
            },
          ),
          const SizedBox(height: 8),
          DatePicker(
            header: 'Hasta',
            selected: range['to'],
            onChanged: (date) {
              final updated = Map<String, DateTime?>.from(range);
              updated['to'] = date;
              _setFilter(field.key, updated);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildField(FilterField field) {
    switch (field.type) {
      case FilterFieldType.text:
        return _buildTextField(field);
      case FilterFieldType.select:
        return _buildSelectField(field);
      case FilterFieldType.boolean:
        return _buildBooleanField(field);
      case FilterFieldType.dateRange:
        return _buildDateRangeField(field);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final activeCount = _activeFilterCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle button
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(
                  FluentIcons.filter,
                  color: _expanded
                      ? theme.accentColor
                      : theme.inactiveColor,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
              if (activeCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: InfoBadge(
                    source: Text('$activeCount'),
                  ),
                ),
            ],
          ),
        ),
        // Panel
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: _expanded ? 240 : 0,
          child: _expanded
              ? SingleChildScrollView(
                  child: Container(
                    width: 240,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.resources.cardBackgroundFillColorDefault,
                      border: Border(
                        left: BorderSide(
                          color: theme.resources.controlStrokeColorDefault,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Filtros', style: theme.typography.bodyStrong),
                        const SizedBox(height: 16),
                        for (final field in widget.fields) ...[
                          _buildField(field),
                          const SizedBox(height: 12),
                        ],
                        if (activeCount > 0) ...[
                          const SizedBox(height: 4),
                          Button(
                            onPressed: _clearAll,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(FluentIcons.cancel, size: 12),
                                SizedBox(width: 6),
                                Text('Limpiar filtros'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
