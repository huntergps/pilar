import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:brick_gen/brick_gen.dart';

import '../providers/productos_provider.dart';

// ---------------------------------------------------------------------------
// Pantalla principal — workspace con pestañas aislado por módulo
// ---------------------------------------------------------------------------

class ProductosScreen extends StatelessWidget {
  const ProductosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        workspaceTabsProvider.overrideWith(WorkspaceTabsNotifier.new),
      ],
      child: const _ProductosWorkspace(),
    );
  }
}

// ---------------------------------------------------------------------------
// Workspace: gestiona las pestañas del módulo
// ---------------------------------------------------------------------------

class _ProductosWorkspace extends ConsumerStatefulWidget {
  const _ProductosWorkspace();

  @override
  ConsumerState<_ProductosWorkspace> createState() =>
      _ProductosWorkspaceState();
}

class _ProductosWorkspaceState extends ConsumerState<_ProductosWorkspace> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openListaTab());
  }

  void _openListaTab() {
    ref.read(workspaceTabsProvider.notifier).open(
          WorkspaceTab(
            id: 'productos-lista',
            title: 'Productos y Servicios',
            icon: FluentIcons.product,
            closeable: false,
            body: _ProductosLista(onOpenTab: _openFormTab),
          ),
        );
  }

  void _openFormTab(Map<String, dynamic>? producto) {
    final tabs = ref.read(workspaceTabsProvider.notifier);
    final isNew = producto == null;
    final id = isNew ? 'producto-nuevo' : 'producto-${producto['id']}';
    final title = isNew
        ? 'Nuevo producto/servicio'
        : (producto['nombre'] as String? ??
            producto['codigo'] as String? ??
            'Editar');

    tabs.open(WorkspaceTab(
      id: id,
      title: title,
      icon: isNew ? FluentIcons.add : FluentIcons.edit,
      body: _ProductoForm(
        producto: producto,
        onSaved: () {
          ref.read(productosProvider.notifier).refresh();
          tabs.close(id);
        },
        onCancel: () => tabs.close(id),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return const WorkspaceTabs();
  }
}

// ---------------------------------------------------------------------------
// Pestaña lista
// ---------------------------------------------------------------------------

class _ProductosLista extends ConsumerWidget {
  const _ProductosLista({required this.onOpenTab, super.key});

  final void Function(Map<String, dynamic>?) onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CrudScaffold<Map<String, dynamic>>(
      title: 'Productos y Servicios',
      value: ref.watch(productosProvider),
      showSearch: true,
      exportLabel: 'productos',
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
      onNew: () => onOpenTab(null),
      onRowTap: onOpenTab,
      onDelete: (p) async {
        if (!kIsWeb && PilarRepository.isInitialized) {
          await PilarRepository.instance.upsert<Producto>(Producto(
            id: p['id'] as String,
            codigo: p['codigo'] as String?,
            nombre: p['nombre'] as String? ?? '',
            tipo: p['tipo'] as String? ?? 'PRODUCTO',
            precioVenta: (p['precio_venta'] as num?)?.toDouble(),
            precioCosto: (p['precio_costo'] as num?)?.toDouble(),
            descripcion: p['descripcion'] as String?,
            activo: false,
          ));
        } else {
          await Supabase.instance.client.rpc(
            'entidades_actualizar_producto',
            params: {
              'p_id': p['id'] as String,
              'p_data': {'activo': false},
            },
          );
        }
        ref.read(productosProvider.notifier).refresh();
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
}

// ---------------------------------------------------------------------------
// Pestaña formulario: crear / editar producto
// ---------------------------------------------------------------------------

class _ProductoForm extends StatefulWidget {
  final Map<String, dynamic>? producto;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const _ProductoForm({
    this.producto,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  State<_ProductoForm> createState() => _ProductoFormState();
}

class _ProductoFormState extends State<_ProductoForm> {
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _ventaCtrl = TextEditingController();
  final _costoCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _tipo = 'PRODUCTO';

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

  Future<void> _doSave() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      throw 'El nombre es requerido.';
    }

    final pv = double.tryParse(_ventaCtrl.text.replaceAll(',', '.'));
    final pc = double.tryParse(_costoCtrl.text.replaceAll(',', '.'));
    final codigoVal = _codigoCtrl.text.trim().isNotEmpty
        ? _codigoCtrl.text.trim()
        : null;
    final descVal = _descCtrl.text.trim().isNotEmpty
        ? _descCtrl.text.trim()
        : null;

    final id = widget.producto?['id'] as String? ?? const Uuid().v4();

    if (!kIsWeb && PilarRepository.isInitialized) {
      // Offline-first: escribe en SQLite primero, sincroniza con Supabase en background.
      await PilarRepository.instance.upsert<Producto>(Producto(
        id: id,
        codigo: codigoVal,
        nombre: _nombreCtrl.text.trim(),
        tipo: _tipo,
        precioVenta: pv,
        precioCosto: pc,
        descripcion: descVal,
        activo: true,
      ));
    } else {
      // Web: llamada directa a Supabase (no hay SQLite en web).
      final data = {
        'codigo': codigoVal,
        'nombre': _nombreCtrl.text.trim(),
        'tipo': _tipo,
        'precio_venta': pv,
        'precio_costo': pc,
        'descripcion': descVal,
      };
      if (widget.producto != null) {
        await Supabase.instance.client.rpc(
          'entidades_actualizar_producto',
          params: {'p_id': id, 'p_data': data},
        );
      } else {
        await Supabase.instance.client.rpc(
          'entidades_crear_producto',
          params: {'p_data': data},
        );
      }
    }

    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.producto != null;
    return FormScaffold(
      title: isEdit ? 'Editar producto/servicio' : 'Nuevo producto/servicio',
      saveLabel: isEdit ? 'Guardar' : 'Crear',
      onSave: _doSave,
      onCancel: widget.onCancel,
      sections: [
        FormSection(
          title: 'Información básica',
          children: [
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
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: InfoLabel(
                    label: 'Código',
                    child: TextBox(
                      controller: _codigoCtrl,
                      placeholder: 'SKU o código',
                    ),
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
          ],
        ),
        FormSection(
          title: 'Precios',
          columns: 2,
          children: [
            InfoLabel(
              label: 'Precio de venta',
              child: TextBox(
                controller: _ventaCtrl,
                placeholder: '0.00',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            InfoLabel(
              label: 'Precio de costo',
              child: TextBox(
                controller: _costoCtrl,
                placeholder: '0.00',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        FormSection(
          children: [
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
      ],
    );
  }
}
