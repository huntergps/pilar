import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// ContactoPicker
// ---------------------------------------------------------------------------
// Widget de búsqueda y selección de contactos.
// Llama a la RPC entidades_buscar_contactos para búsqueda server-side
// con soporte pg_trgm (resultados incluso con errores tipográficos leves).
//
// Uso:
//   ContactoPicker(
//     onSelected: (contacto) => setState(() => _contactoId = contacto['id']),
//     filtro: 'clientes',  // 'todos' | 'clientes' | 'proveedores'
//   )
// ---------------------------------------------------------------------------

class ContactoPicker extends ConsumerStatefulWidget {
  /// Callback cuando el usuario selecciona un contacto.
  /// Recibe un Map con los campos del contacto.
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
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  Map<String, dynamic>? _seleccionado;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _seleccionado = widget.initialValue;
      _ctrl.text = widget.initialValue!['razon_social'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _buscar(String query) async {
    if (query.trim().length < 2) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final data = await Supabase.instance.client.rpc(
        'entidades_buscar_contactos',
        params: {
          'p_query': query.trim(),
          'p_filtro': widget.filtro,
          'p_solo_activos': true,
          'p_limit': 20,
          'p_offset': 0,
        },
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

  void _seleccionar(Map<String, dynamic> contacto) {
    setState(() {
      _seleccionado = contacto;
      _resultados = [];
      _ctrl.text = contacto['razon_social'] as String? ?? '';
    });
    widget.onSelected(contacto);
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
        Row(
          children: [
            Expanded(
              child: TextBox(
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
            ),
          ],
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
                final c = _resultados[i];
                final sub = [
                  c['numero_id'] as String?,
                  if (c['es_cliente'] as bool? ?? false) 'Cliente',
                  if (c['es_proveedor'] as bool? ?? false) 'Proveedor',
                ].whereType<String>().join(' · ');
                return ListTile(
                  title: Text(c['razon_social'] as String? ?? ''),
                  subtitle: sub.isNotEmpty ? Text(sub) : null,
                  onPressed: () => _seleccionar(c),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
