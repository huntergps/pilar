import 'package:fluent_ui/fluent_ui.dart';

/// A form wrapper for fluent_ui with styled Save/Cancel buttons and loading state.
///
/// Wraps Flutter's [Form] widget with [fluent_ui] styling conventions:
/// - Uses [FilledButton] for the save action with an inline [ProgressRing]
///   while saving.
/// - Uses [Button] for the cancel action (optional).
/// - Displays a themed [InfoBar] with [InfoBarSeverity.error] when [onSave]
///   throws an exception.
///
/// ## Example
///
/// ```dart
/// PilarForm(
///   onSave: () async {
///     final factura = Factura(numero: _numero, ...);
///     await ref.read(facturaRepoProvider).upsert(factura);
///   },
///   onCancel: () => context.pop(),
///   children: [
///     PilarTextField(name: 'numero', label: 'Número', required: true),
///     PilarNumberField(name: 'total', label: 'Total', currency: true),
///     PilarDateField(name: 'fecha', label: 'Fecha emisión'),
///   ],
/// )
/// ```
class PilarForm extends StatefulWidget {
  /// Creates a [PilarForm].
  ///
  /// [children] is a list of form field widgets (e.g. [PilarTextField],
  /// [PilarNumberField], [PilarDateField]).
  ///
  /// [onSave] is called after successful validation and [FormState.save].
  /// It may be asynchronous and may throw an exception; any thrown exception
  /// is shown as an error [InfoBar] below the fields.
  const PilarForm({
    required this.onSave,
    required this.children,
    super.key,
    this.formKey,
    this.onCancel,
    this.saveLabel = 'Guardar',
    this.cancelLabel = 'Cancelar',
    this.autovalidate = false,
    this.padding = const EdgeInsets.all(16),
  });

  /// Optional external [GlobalKey] for the underlying [Form].
  ///
  /// If null, an internal key is created automatically.
  final GlobalKey<FormState>? formKey;

  /// The form field widgets displayed inside the form.
  final List<Widget> children;

  /// Called after validation passes and [FormState.save] is invoked.
  ///
  /// The returned [Future] is awaited while a [ProgressRing] is shown inside
  /// the save button. If this callback throws, the error is displayed in an
  /// [InfoBar].
  final Future<void> Function() onSave;

  /// Called when the Cancel button is pressed.
  ///
  /// If null, no Cancel button is rendered.
  final VoidCallback? onCancel;

  /// Label for the save button. Defaults to `'Guardar'`.
  final String saveLabel;

  /// Label for the cancel button. Defaults to `'Cancelar'`.
  final String cancelLabel;

  /// When true, fields validate on every user interaction using
  /// [AutovalidateMode.onUserInteraction]. Defaults to false.
  final bool autovalidate;

  /// Padding around the entire form content. Defaults to `EdgeInsets.all(16)`.
  final EdgeInsetsGeometry padding;

  @override
  State<PilarForm> createState() => _PilarFormState();
}

class _PilarFormState extends State<PilarForm> {
  final _internalKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _errorMessage;

  /// Returns the effective [GlobalKey<FormState>]: the external key provided
  /// by the caller, or the internal one created by this widget.
  GlobalKey<FormState> get _formKey => widget.formKey ?? _internalKey;

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.onSave();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Form(
        key: _formKey,
        autovalidateMode: widget.autovalidate
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...widget.children,
            const SizedBox(height: 16),
            if (_errorMessage != null) ...[
              InfoBar(
                title: const Text('Error'),
                content: Text(_errorMessage!),
                severity: InfoBarSeverity.error,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onCancel != null) ...[
                  Button(
                    onPressed: _isSaving ? null : widget.onCancel,
                    child: Text(widget.cancelLabel),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: _isSaving ? null : _handleSave,
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : Text(widget.saveLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
