import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// ContactoPicker
// ---------------------------------------------------------------------------
// Búsqueda y selección de contactos via AutoSuggestBox (overlay).
// Usa la RPC entidades_buscar_contactos con soporte pg_trgm.
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
  List<AutoSuggestBoxItem<Map<String, dynamic>>> _items = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _ctrl.text =
          widget.initialValue!['razon_social'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
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
      final data = await Supabase.instance.client.rpc(
        'entidades_buscar_contactos',
        params: {
          'p_query': query,
          'p_filtro': widget.filtro,
          'p_solo_activos': true,
          'p_limit': 20,
          'p_offset': 0,
        },
      ) as List;
      if (!mounted) return;
      setState(() {
        _items = data.cast<Map<String, dynamic>>().map((c) {
          final sub = [
            c['numero_id'] as String?,
            if (c['es_cliente'] as bool? ?? false) 'Cliente',
            if (c['es_proveedor'] as bool? ?? false) 'Proveedor',
          ].whereType<String>().join(' · ');
          return AutoSuggestBoxItem<Map<String, dynamic>>(
            value: c,
            label: c['razon_social'] as String? ?? '',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c['razon_social'] as String? ?? '',
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
}
