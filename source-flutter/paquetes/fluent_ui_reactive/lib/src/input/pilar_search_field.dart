import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

/// A reactive [AutoSuggestBox] that queries local SQLite (via Brick) as the
/// user types, with built-in debounce to avoid flooding the database.
///
/// Each keystroke (after [debounceDuration]) calls [suggestionsProvider] which
/// should forward the query string directly to a Brick repository `get()` call.
/// Because Brick reads from the local SQLite mirror, suggestions appear
/// instantly without any network round-trip.
///
/// ## Example
///
/// ```dart
/// PilarSearchField<Producto>(
///   suggestionsProvider: (query) => productoRepo.get(
///     query: Query.where('nombre', query, compare: Compare.contains),
///   ),
///   displayText: (p) => p.nombre,
///   onSelected: (producto) => _agregarLinea(producto),
///   placeholder: 'Buscar producto...',
/// )
/// // Each keystroke → query to local SQLite → suggestions without network.
/// // Debounce 300 ms prevents query flooding.
/// ```
class PilarSearchField<T> extends StatefulWidget {
  /// Called with the current query string (after debounce) to retrieve
  /// matching suggestions from Brick / SQLite.
  ///
  /// Return an empty list when there are no matches; do not return null.
  final Future<List<T>> Function(String query) suggestionsProvider;

  /// Converts a suggestion item to the string displayed in the list row and
  /// placed in the text field when an item is selected.
  final String Function(T item) displayText;

  /// Called when the user taps a suggestion in the dropdown.
  final void Function(T item) onSelected;

  /// Hint text displayed when the field is empty.
  ///
  /// Defaults to `'Buscar...'`.
  final String placeholder;

  /// When `false` the field rejects all user interaction.
  final bool enabled;

  /// How long to wait after the last keystroke before calling
  /// [suggestionsProvider]. Lower values feel more responsive but produce more
  /// SQLite queries. Defaults to 300 ms.
  final Duration debounceDuration;

  /// Optional custom builder for each row in the suggestions dropdown.
  ///
  /// When null, each row is rendered as `Text(displayText(item))`.
  final Widget Function(T item)? suggestionBuilder;

  /// Optional external [TextEditingController].
  ///
  /// When provided the widget does **not** dispose it on destruction — that is
  /// the caller's responsibility. When null, an internal controller is created
  /// and disposed automatically.
  final TextEditingController? controller;

  /// Called on every text change (after debounce), with the current raw query
  /// string. Useful for syncing the query value into a parent form state.
  final void Function(String)? onChanged;

  /// Pre-populates the text field. Only used when [controller] is null.
  final String? initialValue;

  const PilarSearchField({
    super.key,
    required this.suggestionsProvider,
    required this.displayText,
    required this.onSelected,
    this.placeholder = 'Buscar...',
    this.enabled = true,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.suggestionBuilder,
    this.controller,
    this.onChanged,
    this.initialValue,
  });

  @override
  State<PilarSearchField<T>> createState() => _PilarSearchFieldState<T>();
}

class _PilarSearchFieldState<T> extends State<PilarSearchField<T>> {
  /// Current set of suggestions shown in the dropdown.
  List<T> _suggestions = [];

  /// Whether a debounced query is in-flight.
  bool _isLoading = false;

  /// Active debounce timer. Cancelled and replaced on every keystroke.
  Timer? _debounceTimer;

  /// Effective text controller — either the caller-supplied one or an
  /// internally created one.
  late final TextEditingController _controller;

  /// `true` when [_controller] was created internally and must be disposed.
  late final bool _ownController;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownController = false;
    } else {
      _controller = TextEditingController(text: widget.initialValue ?? '');
      _ownController = true;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    if (_ownController) _controller.dispose();
    super.dispose();
  }

  /// Handles each text-change event coming from [AutoSuggestBox.onChanged].
  ///
  /// 1. Cancels the pending debounce timer (if any).
  /// 2. Clears suggestions immediately when [query] is empty.
  /// 3. Otherwise starts a new timer; on expiry calls [suggestionsProvider]
  ///    and updates state if the widget is still mounted.
  void _onTextChanged(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    _debounceTimer = Timer(widget.debounceDuration, () async {
      try {
        final results = await widget.suggestionsProvider(query);
        if (mounted) {
          setState(() {
            _suggestions = results;
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _isLoading = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return AutoSuggestBox<T>(
      controller: _controller,
      enabled: widget.enabled,
      placeholder: widget.placeholder,
      items: _suggestions.map((item) {
        return AutoSuggestBoxItem<T>(
          value: item,
          label: widget.displayText(item),
          child: widget.suggestionBuilder != null
              ? widget.suggestionBuilder!(item)
              : null,
        );
      }).toList(),
      onChanged: (text, reason) {
        if (reason == TextChangedReason.userInput) {
          _onTextChanged(text);
        }
        widget.onChanged?.call(text);
      },
      onSelected: (item) {
        if (item.value != null) {
          widget.onSelected(item.value as T);
        }
      },
      trailingIcon: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          : const Icon(FluentIcons.search, size: 16),
      noResultsFoundBuilder: (_) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Sin resultados',
          style: theme.typography.body,
        ),
      ),
    );
  }
}
