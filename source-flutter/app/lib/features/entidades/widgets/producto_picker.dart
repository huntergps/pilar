import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// ProductoPicker
// ---------------------------------------------------------------------------
// Widget de búsqueda y selección de productos.
// Llama a la RPC entidades_buscar_productos con soporte pg_trgm.
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
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  Map<String, dynamic>? _seleccionado;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _seleccionado = widget.initialValue;
      _ctrl.text = _labelProducto(widget.initialValue!);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _labelProducto(Map<String, dynamic> p) {
    final codigo = p['codigo'] as String?;
    final nombre = p['nombre'] as String? ?? '';
    return codigo != null ? '[$codigo] $nombre' : nombre;
  }

  Future<void> _buscar(String query) async {
    if (query.trim().length < 2) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final params = <String, dynamic>{
        'p_query': query.trim(),
        'p_tipo': 'todos',
        'p_solo_activos': true,
        'p_limit': 20,
        'p_offset': 0,
      };
      if (widget.tipo != null) params['p_tipo'] = widget.tipo!;

      final data = await Supabase.instance.client.rpc(
        'entidades_buscar_productos',
        params: params,
      );
      if (mounted) {
        setState(() {
          _resultados = List<Map<String, dynamic>>.from(data as List);
          _buscando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _seleccionar(Map<String, dynamic> producto) {
    setState(() {
      _seleccionado = producto;
      _resultados = [];
      _ctrl.text = _labelProducto(producto);
    });
    widget.onSelected(producto);
    _focusNode.unfocus();
  }

  void _limpiar() {
    setState(() {
      _seleccionado = null;
      _resultados = [];
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextBox(
          controller: _ctrl,
          focusNode: _focusNode,
          placeholder: widget.placeholder,
          suffix: _buscando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : _seleccionado != null
                  ? IconButton(
                      icon: const Icon(FluentIcons.clear, size: 12),
                      onPressed: _limpiar,
                    )
                  : null,
          onChanged: _buscar,
        ),
        if (_resultados.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: FluentTheme.of(context).menuColor,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _resultados.length,
              itemBuilder: (context, i) {
                final p = _resultados[i];
                final codigo = p['codigo'] as String?;
                final pv = p['precio_venta'];
                final pvStr = pv != null
                    ? '\$${(pv as num).toStringAsFixed(2)}'
                    : '';
                final sub = [
                  if (codigo != null) codigo,
                  _labelTipo(p['tipo'] as String?),
                  pvStr,
                ].where((s) => s.isNotEmpty).join(' · ');
                return ListTile(
                  title: Text(p['nombre'] as String? ?? ''),
                  subtitle: sub.isNotEmpty ? Text(sub) : null,
                  onPressed: () => _seleccionar(p),
                );
              },
            ),
          ),
        ],
      ],
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
