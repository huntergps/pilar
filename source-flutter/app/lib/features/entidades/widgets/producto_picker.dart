import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// ProductoPicker
// ---------------------------------------------------------------------------
// Búsqueda y selección de productos via AutoSuggestBox (overlay).
// Usa la RPC entidades_buscar_productos con soporte pg_trgm.
//
// Uso:
//   ProductoPicker(
//     onSelected: (producto) => setState(() => _productoId = producto['id']),
//     tipo: 'PRODUCTO',   // null = todos los tipos
//   )
// ---------------------------------------------------------------------------

class ProductoPicker extends ConsumerStatefulWidget {
  /// Callback cuando el usuario selecciona un producto.
  final void Function(Map<String, dynamic> producto) onSelected;

  /// Filtrar por tipo: 'PRODUCTO' | 'SERVICIO' | 'CONSUMO' | 'ENSAMBLAJE' | null (todos).
  final String? tipo;

  /// Placeholder cuando no hay ningún producto seleccionado.
  final String placeholder;

  /// Producto preseleccionado (ej: al editar un registro existente).
  final Map<String, dynamic>? initialValue;

  const ProductoPicker({
    super.key,
    required this.onSelected,
    this.tipo,
    this.placeholder = 'Buscar producto...',
    this.initialValue,
  });

  @override
  ConsumerState<ProductoPicker> createState() => _ProductoPickerState();
}

class _ProductoPickerState extends ConsumerState<ProductoPicker> {
  final _ctrl = TextEditingController();
  List<AutoSuggestBoxItem<Map<String, dynamic>>> _items = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _ctrl.text = _labelProducto(widget.initialValue!);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String _labelProducto(Map<String, dynamic> p) {
    final codigo = p['codigo'] as String?;
    final nombre = p['nombre'] as String? ?? '';
    return codigo != null ? '[$codigo] $nombre' : nombre;
  }

  void _onChanged(String text, TextChangedReason reason) {
    if (reason == TextChangedReason.cleared) {
      setState(() => _items = []);
      return;
    }
    if (reason != TextChangedReason.userInput) return;

    _debounce?.cancel();
    final query = text.trim();
    if (query.length < 2) {
      setState(() => _items = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _buscar(query));
  }

  Future<void> _buscar(String query) async {
    try {
      final params = <String, dynamic>{
        'p_query': query,
        'p_tipo': widget.tipo ?? 'todos',
        'p_solo_activos': true,
        'p_limit': 20,
        'p_offset': 0,
      };

      final data = await Supabase.instance.client.rpc(
        'entidades_buscar_productos',
        params: params,
      ) as List;

      if (!mounted) return;
      setState(() {
        _items = data.cast<Map<String, dynamic>>().map((p) {
          final codigo = p['codigo'] as String?;
          final pv = p['precio_venta'];
          final pvStr =
              pv != null ? '\$${(pv as num).toStringAsFixed(2)}' : '';
          final sub = [
            if (codigo != null) codigo,
            _labelTipo(p['tipo'] as String?),
            pvStr,
          ].where((s) => s.isNotEmpty).join(' · ');
          return AutoSuggestBoxItem<Map<String, dynamic>>(
            value: p,
            label: _labelProducto(p),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p['nombre'] as String? ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          );
        }).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutoSuggestBox<Map<String, dynamic>>(
      controller: _ctrl,
      items: _items,
      placeholder: widget.placeholder,
      // La API ya filtra — no filtrar localmente.
      sorter: (text, items) => items,
      onChanged: _onChanged,
      onSelected: (item) {
        if (item.value != null) widget.onSelected(item.value!);
      },
    );
  }

  static String _labelTipo(String? tipo) => switch (tipo) {
        'PRODUCTO' => 'Producto',
        'SERVICIO' => 'Servicio',
        'CONSUMO' => 'Consumo',
        'ENSAMBLAJE' => 'Ensamblaje',
        _ => tipo ?? '',
      };
}
