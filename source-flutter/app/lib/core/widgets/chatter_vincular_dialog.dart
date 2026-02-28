// ChatterVincularDialog — dialog para vincular una conversación o mostrar
// en el ChatterWidget, con búsqueda real vía RPC chatter_buscar_entidad.
//
// Uso desde chatter_widget.dart (botón "+ Vincular"):
//   await showDialog(
//     context: context,
//     builder: (_) => ChatterVincularDialog(
//       onVincular: (tipo, id) { ... },
//     ),
//   );
//
// Uso desde un módulo externo para vincular una conversación específica:
//   await showDialog(
//     context: context,
//     builder: (_) => ChatterVincularDialog(
//       conversacionId: conv.id,
//     ),
//   );

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Tipos de entidad disponibles
// ---------------------------------------------------------------------------

typedef _EntidadTipo = ({String tipo, String label});

const List<_EntidadTipo> _kTiposEntidad = [
  (tipo: 'contactos', label: 'Contactos'),
  (tipo: 'facturas', label: 'Facturas'),
  (tipo: 'cotizaciones', label: 'Cotizaciones'),
  (tipo: 'ordenes_venta', label: 'Órdenes de Venta'),
  (tipo: 'ordenes_compra', label: 'Órdenes de Compra'),
  (tipo: 'productos', label: 'Productos'),
];

// ---------------------------------------------------------------------------
// Resultado de búsqueda
// ---------------------------------------------------------------------------

typedef _Resultado = ({String id, String etiqueta, String? secundario});

// ---------------------------------------------------------------------------
// Widget principal
// ---------------------------------------------------------------------------

/// Dialog para vincular una conversación o mostrar en el ChatterWidget.
/// Busca registros de negocio usando RPC `chatter_buscar_entidad`.
///
/// - Si se pasa [conversacionId], vincula esa conversación al registro
///   seleccionado llamando a la RPC `com_vincular_conversacion`.
/// - Si es null, el caller recibe el resultado mediante [onVincular].
class ChatterVincularDialog extends ConsumerStatefulWidget {
  /// UUID de la conversación a vincular. Null si el caller maneja la acción.
  final String? conversacionId;

  /// Callback invocado cuando el usuario confirma la selección.
  /// Recibe (entidadTipo, entidadId).
  final void Function(String entidadTipo, String entidadId)? onVincular;

  const ChatterVincularDialog({
    this.conversacionId,
    this.onVincular,
    super.key,
  });

  @override
  ConsumerState<ChatterVincularDialog> createState() =>
      _ChatterVincularDialogState();
}

class _ChatterVincularDialogState
    extends ConsumerState<ChatterVincularDialog> {
  String _tipoSeleccionado = _kTiposEntidad.first.tipo;
  Timer? _debounce;
  List<_Resultado> _resultados = [];
  bool _cargando = false;
  bool _confirmando = false;
  String? _error;
  _Resultado? _seleccionado;

  @override
  void initState() {
    super.initState();
    // Carga inicial sin filtro de búsqueda
    _buscar('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lógica de búsqueda
  // ---------------------------------------------------------------------------

  void _onBusquedaChanged(String valor) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _buscar(valor),
    );
  }

  Future<void> _buscar(String query) async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _seleccionado = null;
      _error = null;
    });

    try {
      final data = await Supabase.instance.client.rpc(
        'chatter_buscar_entidad',
        params: {
          'p_tipo': _tipoSeleccionado,
          'p_busqueda': query.trim().isEmpty ? null : query.trim(),
          'p_limit': 20,
        },
      ) as List;

      if (!mounted) return;
      setState(() {
        _resultados = data.map((e) {
          final m = e as Map<String, dynamic>;
          return (
            id: m['entidad_id'] as String,
            etiqueta: m['etiqueta'] as String? ?? m['entidad_id'] as String,
            secundario: m['secundario'] as String?,
          );
        }).toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _resultados = [];
        _cargando = false;
      });
    }
  }

  void _onTipoCambiado(String? nuevoTipo) {
    if (nuevoTipo == null || nuevoTipo == _tipoSeleccionado) return;
    setState(() {
      _tipoSeleccionado = nuevoTipo;
      _seleccionado = null;
      _resultados = [];
    });
    _buscar('');
  }

  // ---------------------------------------------------------------------------
  // Confirmar vinculación
  // ---------------------------------------------------------------------------

  Future<void> _confirmar() async {
    final sel = _seleccionado;
    if (sel == null) return;

    setState(() => _confirmando = true);
    try {
      if (widget.conversacionId != null) {
        await Supabase.instance.client.rpc(
          'com_vincular_conversacion',
          params: {
            'p_conversacion_id': widget.conversacionId,
            'p_entidad_tipo': _tipoSeleccionado,
            'p_entidad_id': sel.id,
          },
        );
      }
      widget.onVincular?.call(_tipoSeleccionado, sel.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _confirmando = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: const Text('Vincular a registro'),
      constraints: const BoxConstraints(maxWidth: 480),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error global
          if (_error != null) ...[
            InfoBar(
              title: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
            const SizedBox(height: 10),
          ],

          // Selector de tipo
          Text('Tipo de registro', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          ComboBox<String>(
            value: _tipoSeleccionado,
            isExpanded: true,
            items: _kTiposEntidad
                .map(
                  (t) => ComboBoxItem<String>(
                    value: t.tipo,
                    child: Text(t.label),
                  ),
                )
                .toList(),
            onChanged: _onTipoCambiado,
          ),
          const SizedBox(height: 12),

          // Campo de búsqueda
          Text('Buscar', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          TextBox(
            placeholder: 'Escribe nombre, número, RUC...',
            onChanged: _onBusquedaChanged,
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.search, size: 13),
            ),
          ),
          const SizedBox(height: 10),

          // Resultados
          SizedBox(
            height: 220,
            child: _buildResultados(theme),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: _confirmando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _seleccionado != null && !_confirmando
              ? _confirmar
              : null,
          child: _confirmando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Text('Vincular'),
        ),
      ],
    );
  }

  Widget _buildResultados(FluentThemeData theme) {
    if (_cargando) {
      return const Center(child: ProgressRing());
    }

    if (_resultados.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron resultados',
          style: theme.typography.body?.copyWith(
            color: theme.resources.textFillColorSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _resultados.length,
      itemBuilder: (context, index) {
        final r = _resultados[index];
        final seleccionado = _seleccionado?.id == r.id;

        return GestureDetector(
          onTap: () => setState(() => _seleccionado = r),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: seleccionado
                  ? theme.accentColor.withValues(alpha: 0.10)
                  : theme.resources.cardBackgroundFillColorDefault,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: seleccionado
                    ? theme.accentColor.withValues(alpha: 0.5)
                    : theme.resources.cardStrokeColorDefault,
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  checked: seleccionado,
                  onChanged: (_) => setState(() => _seleccionado = r),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.etiqueta,
                        style: theme.typography.bodyStrong
                            ?.copyWith(fontSize: 13),
                      ),
                      if (r.secundario != null && r.secundario!.isNotEmpty)
                        Text(
                          r.secundario!,
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (seleccionado)
                  Icon(
                    FluentIcons.check_mark,
                    size: 14,
                    color: theme.accentColor,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
