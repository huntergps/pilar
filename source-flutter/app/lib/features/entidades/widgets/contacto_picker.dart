import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/contactos_provider.dart';
import '../../../core/theme/pilar_spacing.dart';

// ---------------------------------------------------------------------------
// ContactoPicker
// ---------------------------------------------------------------------------
// Búsqueda y selección de contactos via TextBox + overlay propio.
// Usa la RPC entidades_buscar_contactos con soporte pg_trgm.
//
// NOTA: No usa AutoSuggestBox porque la versión pub.dev de fluent_ui 4.14.0
// tiene un bug donde el overlay no se actualiza con items asíncronos
// (falta setState en itemsSubscription). Implementamos overlay propio con
// ValueNotifier para evitar el bug.
//
// Uso:
//   ContactoPicker(
//     onSelected: (contacto) => setState(() => _contactoId = contacto['id']),
//     filtro: 'clientes',  // 'todos' | 'clientes' | 'proveedores'
//   )
// ---------------------------------------------------------------------------

class ContactoPicker extends ConsumerStatefulWidget {
  /// Callback cuando el usuario selecciona un contacto.
  final void Function(Map<String, dynamic> contacto) onSelected;

  /// 'todos' | 'clientes' | 'proveedores'
  final String filtro;

  /// Placeholder cuando no hay ningún contacto seleccionado.
  final String placeholder;

  /// Contacto preseleccionado (ej: al editar un registro existente).
  final Map<String, dynamic>? initialValue;

  const ContactoPicker({
    super.key,
    required this.onSelected,
    this.filtro = 'todos',
    this.placeholder = 'Buscar contacto...',
    this.initialValue,
  });

  @override
  ConsumerState<ContactoPicker> createState() => _ContactoPickerState();
}

class _ContactoPickerState extends ConsumerState<ContactoPicker> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _resultsNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  final _textBoxKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    if (widget.initialValue != null) {
      _ctrl.text = widget.initialValue!['razon_social'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    _hideOverlay();
    _resultsNotifier.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      // Delay so tap events on dropdown items can fire before overlay closes.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focusNode.hasFocus) _hideOverlay();
      });
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      _resultsNotifier.value = [];
      _hideOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _buscar(q));
  }

  Future<void> _buscar(String query) async {
    try {
      final data = await ref.read(
        contactoBusquedaProvider((query: query, filtro: widget.filtro)).future,
      );
      if (!mounted) return;
      _resultsNotifier.value = data;
      if (_resultsNotifier.value.isNotEmpty && _focusNode.hasFocus) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    } catch (_) {
      if (!mounted) return;
      _resultsNotifier.value = [];
      _hideOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return; // already visible; ValueNotifier updates it
    final w = (_textBoxKey.currentContext?.findRenderObject() as RenderBox?)
            ?.size
            .width ??
        300.0;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _ContactoDropdown(
        link: _layerLink,
        notifier: _resultsNotifier,
        width: w,
        onSelect: _onSelect,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onSelect(Map<String, dynamic> c) {
    _ctrl.text = c['razon_social'] as String? ?? '';
    _hideOverlay();
    _resultsNotifier.value = [];
    widget.onSelected(c);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextBox(
        key: _textBoxKey,
        controller: _ctrl,
        focusNode: _focusNode,
        placeholder: widget.placeholder,
        onChanged: _onChanged,
        suffix: IconButton(
          icon: const Icon(FluentIcons.clear, size: 12),
          onPressed: () {
            _ctrl.clear();
            _onChanged('');
          },
        ),
        suffixMode: OverlayVisibilityMode.editing,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dropdown overlay
// ---------------------------------------------------------------------------

class _ContactoDropdown extends StatelessWidget {
  final LayerLink link;
  final ValueNotifier<List<Map<String, dynamic>>> notifier;
  final double width;
  final void Function(Map<String, dynamic>) onSelect;

  const _ContactoDropdown({
    required this.link,
    required this.notifier,
    required this.width,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      child: Align(
        alignment: Alignment.topLeft,
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: notifier,
          builder: (ctx, results, _) {
            if (results.isEmpty) return const SizedBox.shrink();
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 280,
                minWidth: width,
                maxWidth: width,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.resources.cardBackgroundFillColorDefault,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: theme.resources.controlStrokeColorDefault,
                    width: 0.5,
                  ),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  itemCount: results.length,
                  itemBuilder: (ctx, i) => _ContactoTile(
                    contacto: results[i],
                    onSelect: onSelect,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ContactoTile extends StatefulWidget {
  final Map<String, dynamic> contacto;
  final void Function(Map<String, dynamic>) onSelect;

  const _ContactoTile({
    required this.contacto,
    required this.onSelect,
  });

  @override
  State<_ContactoTile> createState() => _ContactoTileState();
}

class _ContactoTileState extends State<_ContactoTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final c = widget.contacto;
    final sub = [
      c['numero_id'] as String?,
      if (c['es_cliente'] as bool? ?? false) 'Cliente',
      if (c['es_proveedor'] as bool? ?? false) 'Proveedor',
    ].whereType<String>().join(' · ');

    return GestureDetector(
      onTap: () => widget.onSelect(c),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.ms, vertical: Spacing.sm),
          color: _hover
              ? theme.resources.subtleFillColorSecondary
              : Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c['razon_social'] as String? ?? '',
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body,
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.resources.textFillColorSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
