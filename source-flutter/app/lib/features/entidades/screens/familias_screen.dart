import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:uuid/uuid.dart';
import 'package:brick_gen/brick_gen.dart';

import '../providers/familias_provider.dart';
import '../providers/familia_write_provider.dart';
import '../../../core/providers/brick_write_provider.dart';

// ---------------------------------------------------------------------------
// FamiliasScreen — gestión de familias de productos
// ---------------------------------------------------------------------------

class FamiliasScreen extends StatelessWidget {
  const FamiliasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        workspaceTabsProvider.overrideWith(WorkspaceTabsNotifier.new),
      ],
      child: const _FamiliasWorkspace(),
    );
  }
}

class _FamiliasWorkspace extends ConsumerStatefulWidget {
  const _FamiliasWorkspace();

  @override
  ConsumerState<_FamiliasWorkspace> createState() => _FamiliasWorkspaceState();
}

class _FamiliasWorkspaceState extends ConsumerState<_FamiliasWorkspace> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openListaTab());
  }

  void _openListaTab() {
    ref.read(workspaceTabsProvider.notifier).open(
          WorkspaceTab(
            id: 'familias-lista',
            title: 'Familias de productos',
            icon: FluentIcons.product_catalog,
            closeable: false,
            body: _FamiliasLista(onOpenTab: _openFormTab),
          ),
        );
  }

  void _openFormTab(Map<String, dynamic>? familia) {
    final tabs = ref.read(workspaceTabsProvider.notifier);
    final isNew = familia == null;
    final id = isNew ? 'familia-nueva' : 'familia-${familia['id']}';
    final title = isNew ? 'Nueva familia' : (familia['nombre'] as String? ?? 'Editar');

    tabs.open(WorkspaceTab(
      id: id,
      title: title,
      icon: isNew ? FluentIcons.add : FluentIcons.edit,
      body: _FamiliaForm(
        familia: familia,
        onSaved: () {
          ref.read(familiasProvider.notifier).refresh();
          tabs.close(id);
        },
        onCancel: () => tabs.close(id),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => const WorkspaceTabs();
}

// ---------------------------------------------------------------------------
// Lista
// ---------------------------------------------------------------------------

class _FamiliasLista extends ConsumerWidget {
  const _FamiliasLista({required this.onOpenTab});
  final void Function(Map<String, dynamic>?) onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CrudScaffold<Map<String, dynamic>>(
      title: 'Familias de productos',
      value: ref.watch(familiasProvider),
      showSearch: true,
      exportLabel: 'familias',
      searchFields: (f) => [
        f['nombre'] as String? ?? '',
        f['descripcion'] as String? ?? '',
      ],
      columns: const [
        PilarColumn(field: 'nombre', label: 'Nombre', width: 220),
        PilarColumn(field: 'descripcion', label: 'Descripción', width: 300),
      ],
      rowToMap: (f) => {
        'nombre': f['nombre'] ?? '',
        'descripcion': f['descripcion'] ?? '',
      },
      onNew: () => onOpenTab(null),
      onRowTap: onOpenTab,
      onDelete: (f) async {
        final familia = ProductoFamilia(
          id: f['id'] as String,
          nombre: f['nombre'] as String? ?? '',
          descripcion: f['descripcion'] as String?,
          activo: false,
        );
        try {
          await ref.read(familiaWriteProvider.notifier).delete(familia);
        } on OfflineWriteException catch (e) {
          if (context.mounted) {
            displayInfoBar(
              context,
              builder: (_, close) => InfoBar(
                title: Text(
                  e.isConflict ? 'Conflicto' : 'Sin conexión',
                ),
                content: Text(
                  e.isConflict
                      ? 'Otro usuario modificó este registro. Recarga e intenta de nuevo.'
                      : 'Sin conexión. El cambio se guardará cuando recuperes la red.',
                ),
                severity: e.isConflict
                    ? InfoBarSeverity.error
                    : InfoBarSeverity.warning,
                onClose: close,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            displayInfoBar(
              context,
              builder: (_, close) => InfoBar(
                title: const Text('Error'),
                content: Text('No se pudo eliminar la familia: $e'),
                severity: InfoBarSeverity.error,
                onClose: close,
              ),
            );
          }
        }
      },
      deleteConfirmText: (f) =>
          '¿Eliminar familia "${f['nombre']}"? Los productos de esta familia quedarán sin familia asignada.',
    );
  }
}

// ---------------------------------------------------------------------------
// Formulario
// ---------------------------------------------------------------------------

class _FamiliaForm extends ConsumerStatefulWidget {
  final Map<String, dynamic>? familia;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const _FamiliaForm({this.familia, required this.onSaved, required this.onCancel});

  @override
  ConsumerState<_FamiliaForm> createState() => _FamiliaFormState();
}

class _FamiliaFormState extends ConsumerState<_FamiliaForm> {
  final _nombreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final f = widget.familia;
    if (f != null) {
      _nombreCtrl.text = f['nombre'] as String? ?? '';
      _descCtrl.text = f['descripcion'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSave() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      throw 'El nombre de la familia es requerido.';
    }

    final id = widget.familia?['id'] as String? ?? const Uuid().v4();
    final descVal =
        _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null;

    final familia = ProductoFamilia(
      id: id,
      nombre: _nombreCtrl.text.trim(),
      descripcion: descVal,
      activo: true,
    );

    try {
      await ref.read(familiaWriteProvider.notifier).save(familia);
    } on OfflineWriteException catch (e) {
      if (e.isConflict) {
        throw 'Conflicto: otro usuario modificó este registro. '
            'Recarga e intenta de nuevo.';
      } else {
        throw 'Sin conexión. El cambio se guardará cuando recuperes la red.';
      }
    }

    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.familia != null;
    return FormScaffold(
      title: isEdit ? 'Editar familia' : 'Nueva familia',
      saveLabel: isEdit ? 'Guardar' : 'Crear',
      onSave: _doSave,
      onCancel: widget.onCancel,
      sections: [
        FormSection(
          title: 'Información',
          children: [
            InfoLabel(
              label: 'Nombre *',
              child: TextBox(
                controller: _nombreCtrl,
                placeholder: 'Nombre de la familia de productos',
              ),
            ),
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
