import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:uuid/uuid.dart';
import 'package:brick_gen/brick_gen.dart';

import '../providers/contactos_provider.dart';
import '../providers/contacto_write_provider.dart';
import '../../../core/providers/brick_write_provider.dart';
import '../../../core/theme/pilar_spacing.dart';

// ---------------------------------------------------------------------------
// Pantalla principal — workspace con pestañas aislado por módulo
// ---------------------------------------------------------------------------

class ContactosScreen extends StatelessWidget {
  const ContactosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        workspaceTabsProvider.overrideWith(WorkspaceTabsNotifier.new),
      ],
      child: const _ContactosWorkspace(),
    );
  }
}

// ---------------------------------------------------------------------------
// Workspace: gestiona las pestañas del módulo
// ---------------------------------------------------------------------------

class _ContactosWorkspace extends ConsumerStatefulWidget {
  const _ContactosWorkspace();

  @override
  ConsumerState<_ContactosWorkspace> createState() =>
      _ContactosWorkspaceState();
}

class _ContactosWorkspaceState extends ConsumerState<_ContactosWorkspace> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openListaTab());
  }

  void _openListaTab() {
    ref.read(workspaceTabsProvider.notifier).open(
          WorkspaceTab(
            id: 'contactos-lista',
            title: 'Contactos',
            icon: FluentIcons.contact,
            closeable: false,
            body: _ContactosLista(onOpenTab: _openFormTab),
          ),
        );
  }

  void _openFormTab(Map<String, dynamic>? contacto) {
    final tabs = ref.read(workspaceTabsProvider.notifier);
    final isNew = contacto == null;
    final id = isNew ? 'contacto-nuevo' : 'contacto-${contacto['id']}';
    final title = isNew
        ? 'Nuevo contacto'
        : (contacto['razon_social'] as String? ??
            contacto['numero_id'] as String? ??
            'Editar');

    tabs.open(WorkspaceTab(
      id: id,
      title: title,
      icon: isNew ? FluentIcons.add : FluentIcons.edit,
      body: _ContactoForm(
        contacto: contacto,
        onSaved: () => tabs.close(id),
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

class _ContactosLista extends ConsumerWidget {
  const _ContactosLista({required this.onOpenTab, super.key});

  final void Function(Map<String, dynamic>?) onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CrudScaffold<Map<String, dynamic>>(
      title: 'Contactos',
      value: ref.watch(contactosProvider),
      showSearch: true,
      exportLabel: 'contactos',
      searchFields: (c) => [
        c['razon_social'] as String? ?? '',
        c['nombre_comercial'] as String? ?? '',
        c['numero_id'] as String? ?? '',
        c['email'] as String? ?? '',
      ],
      columns: const [
        PilarColumn(
            field: 'razon_social', label: 'Nombre / Razón Social', width: 220),
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
      onNew: () => onOpenTab(null),
      onRowTap: onOpenTab,
      onDelete: (c) async {
        final contacto = Contacto(
          id: c['id'] as String,
          razonSocial: c['razon_social'] as String? ?? '',
          nombreComercial: c['nombre_comercial'] as String?,
          numeroId: c['numero_id'] as String?,
          tipoEntidad: c['tipo_entidad'] as String? ?? 'PERSONA_NATURAL',
          tipoIdentificacion: c['tipo_identificacion'] as String? ?? '05',
          esCliente: c['es_cliente'] as bool? ?? false,
          esProveedor: c['es_proveedor'] as bool? ?? false,
          esEmpleado: c['es_empleado'] as bool? ?? false,
          email: c['email'] as String?,
          telefono: c['telefono'] as String?,
          celular: c['celular'] as String?,
          activo: false,
        );
        try {
          await ref.read(contactoWriteProvider.notifier).delete(contacto);
        } on OfflineWriteException catch (e) {
          if (context.mounted) {
            displayInfoBar(
              context,
              builder: (_, close) => InfoBar(
                title: Text(e.isConflict
                    ? 'Conflicto: otro usuario modificó este registro.'
                    : 'Sin conexión: se eliminará cuando recuperes la red.'),
                severity: e.isConflict ? InfoBarSeverity.error : InfoBarSeverity.warning,
                onClose: close,
              ),
            );
          }
        }
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
}

// ---------------------------------------------------------------------------
// Pestaña formulario: crear / editar contacto
// ---------------------------------------------------------------------------

class _ContactoForm extends ConsumerStatefulWidget {
  final Map<String, dynamic>? contacto;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const _ContactoForm({
    this.contacto,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  ConsumerState<_ContactoForm> createState() => _ContactoFormState();
}

class _ContactoFormState extends ConsumerState<_ContactoForm> {
  final _razonCtrl = TextEditingController();
  final _comercialCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _celularCtrl = TextEditingController();

  String _tipoEntidad = 'PERSONA_NATURAL';
  String _tipoIdentificacion = '05';
  bool _esCliente = false;
  bool _esProveedor = false;

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
      _tipoIdentificacion = c['tipo_identificacion'] as String? ?? '05';
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

  Future<void> _doSave() async {
    if (_razonCtrl.text.trim().isEmpty) {
      throw 'El nombre / razón social es requerido.';
    }

    final id = widget.contacto?['id'] as String? ?? const Uuid().v4();

    final contacto = Contacto(
      id: id,
      razonSocial: _razonCtrl.text.trim(),
      nombreComercial: _comercialCtrl.text.trim().isNotEmpty
          ? _comercialCtrl.text.trim()
          : null,
      numeroId: _idCtrl.text.trim().isNotEmpty ? _idCtrl.text.trim() : null,
      tipoEntidad: _tipoEntidad,
      tipoIdentificacion: _tipoIdentificacion,
      esCliente: _esCliente,
      esProveedor: _esProveedor,
      esEmpleado: widget.contacto?['es_empleado'] as bool? ?? false,
      email: _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
      telefono: _telefonoCtrl.text.trim().isNotEmpty
          ? _telefonoCtrl.text.trim()
          : null,
      celular: _celularCtrl.text.trim().isNotEmpty
          ? _celularCtrl.text.trim()
          : null,
      activo: true,
    );

    try {
      await ref.read(contactoWriteProvider.notifier).save(contacto);
    } on OfflineWriteException catch (e) {
      if (e.isConflict) {
        throw 'Conflicto: otro usuario modificó este registro. '
            'Recarga los datos e intenta de nuevo.';
      } else {
        throw 'Sin conexión: el cambio se guardará cuando recuperes la red.';
      }
    }

    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.contacto != null;
    return FormScaffold(
      title: isEdit ? 'Editar contacto' : 'Nuevo contacto',
      saveLabel: isEdit ? 'Guardar' : 'Crear',
      onSave: _doSave,
      onCancel: widget.onCancel,
      sections: [
        FormSection(
          title: 'Identificación',
          columns: 2,
          children: [
            InfoLabel(
              label: 'Tipo de entidad',
              child: ComboBox<String>(
                value: _tipoEntidad,
                items: const [
                  ComboBoxItem(
                      value: 'PERSONA_NATURAL',
                      child: Text('Persona Natural')),
                  ComboBoxItem(value: 'SOCIEDAD', child: Text('Sociedad')),
                  ComboBoxItem(value: 'GOBIERNO', child: Text('Gobierno')),
                ],
                onChanged: (v) => setState(() => _tipoEntidad = v!),
              ),
            ),
            InfoLabel(
              label: 'Tipo de identificación',
              child: ComboBox<String>(
                value: _tipoIdentificacion,
                items: const [
                  ComboBoxItem(value: '04', child: Text('RUC')),
                  ComboBoxItem(value: '05', child: Text('Cédula')),
                  ComboBoxItem(value: '06', child: Text('Pasaporte')),
                  ComboBoxItem(value: '07', child: Text('Consumidor Final')),
                  ComboBoxItem(
                      value: '08', child: Text('Identificación exterior')),
                ],
                onChanged: (v) => setState(() => _tipoIdentificacion = v!),
              ),
            ),
            InfoLabel(
              label: 'No. de identificación',
              child: TextBox(
                controller: _idCtrl,
                placeholder: 'RUC, cédula o pasaporte',
              ),
            ),
          ],
        ),
        FormSection(
          title: 'Información principal',
          children: [
            InfoLabel(
              label: 'Razón social *',
              child: TextBox(
                controller: _razonCtrl,
                placeholder: 'Nombre completo o razón social',
              ),
            ),
            InfoLabel(
              label: 'Nombre comercial',
              child: TextBox(
                controller: _comercialCtrl,
                placeholder: 'Nombre comercial (opcional)',
              ),
            ),
          ],
        ),
        FormSection(
          title: 'Contacto',
          columns: 3,
          children: [
            InfoLabel(
              label: 'Email',
              child:
                  TextBox(controller: _emailCtrl, placeholder: 'correo@ejemplo.com'),
            ),
            InfoLabel(
              label: 'Teléfono',
              child:
                  TextBox(controller: _telefonoCtrl, placeholder: '02-xxx-xxxx'),
            ),
            InfoLabel(
              label: 'Celular',
              child: TextBox(
                  controller: _celularCtrl, placeholder: '09x-xxx-xxxx'),
            ),
          ],
        ),
        FormSection(
          children: [
            Row(
              children: [
                Checkbox(
                  checked: _esCliente,
                  onChanged: (v) => setState(() => _esCliente = v ?? false),
                  content: const Text('Es cliente'),
                ),
                const SizedBox(width: Spacing.lg),
                Checkbox(
                  checked: _esProveedor,
                  onChanged: (v) => setState(() => _esProveedor = v ?? false),
                  content: const Text('Es proveedor'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
