import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/contactos_provider.dart';

// ---------------------------------------------------------------------------
// Pantalla principal
// ---------------------------------------------------------------------------

class ContactosScreen extends ConsumerWidget {
  const ContactosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CrudScaffold<Map<String, dynamic>>(
      title: 'Contactos',
      value: ref.watch(contactosProvider),
      showSearch: true,
      searchFields: (c) => [
        c['razon_social'] as String? ?? '',
        c['nombre_comercial'] as String? ?? '',
        c['numero_id'] as String? ?? '',
        c['email'] as String? ?? '',
      ],
      columns: const [
        PilarColumn(field: 'razon_social', label: 'Nombre / Razón Social', width: 220),
        PilarColumn(field: 'numero_id', label: 'RUC / CI', width: 120),
        PilarColumn(field: 'tipo_entidad', label: 'Tipo', width: 100),
        PilarColumn(field: '_cliente', label: 'Cliente', width: 80),
        PilarColumn(field: '_proveedor', label: 'Proveedor', width: 90),
        PilarColumn(field: 'email', label: 'Email', width: 180),
        PilarColumn(field: 'telefono', label: 'Teléfono', width: 120),
      ],
      rowToMap: (c) => {
        'razon_social': c['razon_social'] ?? '',
        'numero_id': c['numero_id'] ?? '',
        'tipo_entidad': _labelTipo(c['tipo_entidad'] as String?),
        '_cliente': (c['es_cliente'] as bool? ?? false) ? 'Sí' : '',
        '_proveedor': (c['es_proveedor'] as bool? ?? false) ? 'Sí' : '',
        'email': c['email'] ?? '',
        'telefono': c['telefono'] ?? c['celular'] ?? '',
      },
      onNew: () => _showDialog(context, ref, null),
      onRowTap: (c) => _showDialog(context, ref, c),
      onDelete: (c) async {
        await Supabase.instance.client
            .from('contactos')
            .update({'activo': false})
            .eq('id', c['id'] as String);
        ref.invalidate(contactosProvider);
      },
      deleteConfirmText: (c) =>
          '¿Eliminar a "${c['razon_social']}"? Esta acción no se puede deshacer.',
    );
  }

  static String _labelTipo(String? tipo) => switch (tipo) {
        'PERSONA_NATURAL' => 'Persona Natural',
        'SOCIEDAD' => 'Sociedad',
        'GOBIERNO' => 'Gobierno',
        _ => tipo ?? '',
      };

  void _showDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? contacto,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _ContactoDialog(
        contacto: contacto,
        onSaved: () => ref.invalidate(contactosProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog: crear / editar contacto
// ---------------------------------------------------------------------------

class _ContactoDialog extends StatefulWidget {
  final Map<String, dynamic>? contacto;
  final VoidCallback onSaved;

  const _ContactoDialog({this.contacto, required this.onSaved});

  @override
  State<_ContactoDialog> createState() => _ContactoDialogState();
}

class _ContactoDialogState extends State<_ContactoDialog> {
  final _razonCtrl = TextEditingController();
  final _comercialCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _celularCtrl = TextEditingController();

  String _tipoEntidad = 'PERSONA_NATURAL';
  String _tipoIdSri = '05'; // Cédula por defecto
  bool _esCliente = false;
  bool _esProveedor = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.contacto;
    if (c != null) {
      _razonCtrl.text = c['razon_social'] as String? ?? '';
      _comercialCtrl.text = c['nombre_comercial'] as String? ?? '';
      _idCtrl.text = c['numero_id'] as String? ?? '';
      _emailCtrl.text = c['email'] as String? ?? '';
      _telefonoCtrl.text = c['telefono'] as String? ?? '';
      _celularCtrl.text = c['celular'] as String? ?? '';
      _tipoEntidad = c['tipo_entidad'] as String? ?? 'PERSONA_NATURAL';
      _tipoIdSri = c['tipo_id_sri'] as String? ?? '05';
      _esCliente = c['es_cliente'] as bool? ?? false;
      _esProveedor = c['es_proveedor'] as bool? ?? false;
    }
  }

  @override
  void dispose() {
    _razonCtrl.dispose();
    _comercialCtrl.dispose();
    _idCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _celularCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext ctx) async {
    if (_razonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El nombre / razón social es requerido.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final data = {
        'razon_social': _razonCtrl.text.trim(),
        'nombre_comercial': _comercialCtrl.text.trim().isNotEmpty
            ? _comercialCtrl.text.trim()
            : null,
        'numero_id': _idCtrl.text.trim().isNotEmpty ? _idCtrl.text.trim() : null,
        'tipo_entidad': _tipoEntidad,
        'tipo_id_sri': _tipoIdSri,
        'es_cliente': _esCliente,
        'es_proveedor': _esProveedor,
        'email': _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
        'telefono':
            _telefonoCtrl.text.trim().isNotEmpty ? _telefonoCtrl.text.trim() : null,
        'celular':
            _celularCtrl.text.trim().isNotEmpty ? _celularCtrl.text.trim() : null,
      };

      final id = widget.contacto?['id'] as String?;
      if (id != null) {
        await Supabase.instance.client
            .from('contactos')
            .update(data)
            .eq('id', id);
      } else {
        await Supabase.instance.client.from('contactos').insert(data);
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
    final isEdit = widget.contacto != null;
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 680),
      title: Text(isEdit ? 'Editar contacto' : 'Nuevo contacto'),
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
            // Tipo entidad + tipo ID
            Row(
              children: [
                Expanded(
                  child: InfoLabel(
                    label: 'Tipo de entidad',
                    child: ComboBox<String>(
                      value: _tipoEntidad,
                      items: const [
                        ComboBoxItem(value: 'PERSONA_NATURAL', child: Text('Persona Natural')),
                        ComboBoxItem(value: 'SOCIEDAD', child: Text('Sociedad')),
                        ComboBoxItem(value: 'GOBIERNO', child: Text('Gobierno')),
                      ],
                      onChanged: (v) => setState(() => _tipoEntidad = v!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: 'Tipo de identificación',
                    child: ComboBox<String>(
                      value: _tipoIdSri,
                      items: const [
                        ComboBoxItem(value: '04', child: Text('RUC')),
                        ComboBoxItem(value: '05', child: Text('Cédula')),
                        ComboBoxItem(value: '06', child: Text('Pasaporte')),
                        ComboBoxItem(value: '07', child: Text('Consumidor Final')),
                        ComboBoxItem(value: '08', child: Text('Identificación exterior')),
                      ],
                      onChanged: (v) => setState(() => _tipoIdSri = v!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'No. de identificación',
              child: TextBox(controller: _idCtrl, placeholder: 'RUC, cédula o pasaporte'),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Razón social *',
              child: TextBox(
                controller: _razonCtrl,
                placeholder: 'Nombre completo o razón social',
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Nombre comercial',
              child: TextBox(
                controller: _comercialCtrl,
                placeholder: 'Nombre comercial (opcional)',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InfoLabel(
                    label: 'Email',
                    child: TextBox(controller: _emailCtrl, placeholder: 'correo@ejemplo.com'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: 'Teléfono',
                    child: TextBox(controller: _telefonoCtrl, placeholder: '02-xxx-xxxx'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: 'Celular',
                    child: TextBox(controller: _celularCtrl, placeholder: '09x-xxx-xxxx'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  checked: _esCliente,
                  onChanged: (v) => setState(() => _esCliente = v ?? false),
                  content: const Text('Es cliente'),
                ),
                const SizedBox(width: 24),
                Checkbox(
                  checked: _esProveedor,
                  onChanged: (v) => setState(() => _esProveedor = v ?? false),
                  content: const Text('Es proveedor'),
                ),
              ],
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
