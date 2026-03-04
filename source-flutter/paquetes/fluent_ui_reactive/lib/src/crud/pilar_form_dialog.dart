import 'package:fluent_ui/fluent_ui.dart';

/// [ContentDialog] con manejo estándar de estado de guardado/error para PILAR.
///
/// Reemplaza el patrón manual `_saving`/`_error` + [ContentDialog] en dialogs
/// CRUD. El callback [onSave] puede lanzar cualquier valor para mostrar un
/// [InfoBar] de error integrado. Si completa sin error, el diálogo se cierra
/// automáticamente.
///
/// ### Ejemplo
/// ```dart
/// PilarFormDialog(
///   title: 'Nuevo contacto',
///   constraints: const BoxConstraints(maxWidth: 680),
///   saveLabel: 'Crear',
///   onSave: () async {
///     if (nombre.isEmpty) throw 'El nombre es requerido.';
///     await Supabase.instance.client.from('contactos').insert(data);
///   },
///   content: _ContactoFormFields(...),
/// )
/// ```
class PilarFormDialog extends StatefulWidget {
  const PilarFormDialog({
    super.key,
    required this.title,
    required this.content,
    required this.onSave,
    this.constraints = const BoxConstraints(maxWidth: 680),
    this.saveLabel = 'Guardar',
    this.cancelLabel = 'Cancelar',
  });

  /// Título del diálogo.
  final String title;

  /// Contenido del formulario. Se envuelve en [SingleChildScrollView].
  final Widget content;

  /// Lógica de guardado. Si lanza, el error se muestra en [InfoBar].
  /// Si completa normalmente, el diálogo se cierra.
  final Future<void> Function() onSave;

  final BoxConstraints constraints;

  /// Etiqueta del botón de acción principal. Default: `'Guardar'`.
  final String saveLabel;

  /// Etiqueta del botón de cancelación. Default: `'Cancelar'`.
  final String cancelLabel;

  @override
  State<PilarFormDialog> createState() => _PilarFormDialogState();
}

class _PilarFormDialogState extends State<PilarFormDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _handleSave() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: widget.constraints,
      title: Text(widget.title),
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
            widget.content,
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _saving ? null : _handleSave,
          child: _saving
              ? const SizedBox.square(dimension: 16, child: ProgressRing())
              : Text(widget.saveLabel),
        ),
      ],
    );
  }
}
