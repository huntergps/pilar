import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/productos_provider.dart';

// ---------------------------------------------------------------------------
// Pantalla principal
// ---------------------------------------------------------------------------

class ProductosScreen extends ConsumerWidget {
  const ProductosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CrudScaffold<Map<String, dynamic>>(
      title: 'Productos y Servicios',
      value: ref.watch(productosProvider),
      showSearch: true,
      searchFields: (p) => [
        p['codigo'] as String? ?? '',
        p['nombre'] as String? ?? '',
        p['descripcion'] as String? ?? '',
      ],
      columns: const [
        PilarColumn(field: 'codigo', label: 'Código', width: 100),
        PilarColumn(field: 'nombre', label: 'Nombre', width: 220),
        PilarColumn(field: 'tipo', label: 'Tipo', width: 100),
        PilarColumn(field: '_pventa', label: 'P. Venta', width: 100),
        PilarColumn(field: '_pcosto', label: 'P. Costo', width: 100),
      ],
      rowToMap: (p) => {
        'codigo': p['codigo'] ?? '',
        'nombre': p['nombre'] ?? '',
        'tipo': _labelTipo(p['tipo'] as String?),
        '_pventa': _formatPrecio(p['precio_venta']),
        '_pcosto': _formatPrecio(p['precio_costo']),
      },
      onNew: () => _showDialog(context, ref, null),
      onRowTap: (p) => _showDialog(context, ref, p),
      onDelete: (p) async {
        await Supabase.instance.client
            .from('productos')
            .update({'activo': false})
            .eq('id', p['id'] as String);
        ref.invalidate(productosProvider);
      },
      deleteConfirmText: (p) =>
          '¿Eliminar "${p['nombre']}"? Esta acción no se puede deshacer.',
    );
  }

  static String _labelTipo(String? tipo) => switch (tipo) {
        'PRODUCTO' => 'Producto',
        'SERVICIO' => 'Servicio',
        'CONSUMO' => 'Consumo',
        'ENSAMBLAJE' => 'Ensamblaje',
        _ => tipo ?? '',
      };

  static String _formatPrecio(dynamic value) {
    if (value == null) return '';
    final d = double.tryParse(value.toString());
    if (d == null) return value.toString();
    return '\$${d.toStringAsFixed(2)}';
  }

  void _showDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? producto,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _ProductoDialog(
        producto: producto,
        onSaved: () => ref.invalidate(productosProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog: crear / editar producto
// ---------------------------------------------------------------------------

class _ProductoDialog extends StatefulWidget {
  final Map<String, dynamic>? producto;
  final VoidCallback onSaved;

  const _ProductoDialog({this.producto, required this.onSaved});

  @override
  State<_ProductoDialog> createState() => _ProductoDialogState();
}

class _ProductoDialogState extends State<_ProductoDialog> {
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _ventaCtrl = TextEditingController();
  final _costoCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _tipo = 'PRODUCTO';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    if (p != null) {
      _codigoCtrl.text = p['codigo'] as String? ?? '';
      _nombreCtrl.text = p['nombre'] as String? ?? '';
      _tipo = p['tipo'] as String? ?? 'PRODUCTO';
      final pv = p['precio_venta'];
      if (pv != null) _ventaCtrl.text = pv.toString();
      final pc = p['precio_costo'];
      if (pc != null) _costoCtrl.text = pc.toString();
      _descCtrl.text = p['descripcion'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _ventaCtrl.dispose();
    _costoCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext ctx) async {
    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es requerido.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final pv = double.tryParse(_ventaCtrl.text.replaceAll(',', '.'));
      final pc = double.tryParse(_costoCtrl.text.replaceAll(',', '.'));

      final data = {
        'codigo': _codigoCtrl.text.trim().isNotEmpty ? _codigoCtrl.text.trim() : null,
        'nombre': _nombreCtrl.text.trim(),
        'tipo': _tipo,
        'precio_venta': pv,
        'precio_costo': pc,
        'descripcion': _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
      };

      final id = widget.producto?['id'] as String?;
      if (id != null) {
        await Supabase.instance.client.from('productos').update(data).eq('id', id);
      } else {
        await Supabase.instance.client.from('productos').insert(data);
      }

      widget.onSaved();
      if (ctx.mounted) Navigator.of(ctx).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.producto != null;
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Text(isEdit ? 'Editar producto/servicio' : 'Nuevo producto/servicio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              InfoBar(
                title: const Text('Error'),
                content: Text(_error!),
                severity: InfoBarSeverity.error,
                onClose: () => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
            ],
            InfoLabel(
              label: 'Tipo',
              child: ComboBox<String>(
                value: _tipo,
                items: const [
                  ComboBoxItem(value: 'PRODUCTO', child: Text('Producto')),
                  ComboBoxItem(value: 'SERVICIO', child: Text('Servicio')),
                  ComboBoxItem(value: 'CONSUMO', child: Text('Consumo')),
                  ComboBoxItem(value: 'ENSAMBLAJE', child: Text('Ensamblaje')),
                ],
                onChanged: (v) => setState(() => _tipo = v!),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: InfoLabel(
                    label: 'Código',
                    child: TextBox(controller: _codigoCtrl, placeholder: 'SKU o código'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: InfoLabel(
                    label: 'Nombre *',
                    child: TextBox(
                      controller: _nombreCtrl,
                      placeholder: 'Nombre del producto o servicio',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InfoLabel(
                    label: 'Precio de venta',
                    child: TextBox(
                      controller: _ventaCtrl,
                      placeholder: '0.00',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: 'Precio de costo',
                    child: TextBox(
                      controller: _costoCtrl,
                      placeholder: '0.00',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Descripción',
              child: TextBox(
                controller: _descCtrl,
                placeholder: 'Descripción opcional',
                maxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _save(context),
          child: _saving
              ? const SizedBox.square(dimension: 16, child: ProgressRing())
              : Text(isEdit ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}
