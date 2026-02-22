import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// A text field for fluent_ui forms with [InfoLabel] wrapping and full
/// [FormField] integration.
///
/// Uses [TextFormBox] from `fluent_ui` — NOT Material's [TextFormField]. The
/// label is rendered via [InfoLabel.rich] above the input, displaying an
/// asterisk (*) when [required] is true.
///
/// ## Example inside [PilarForm]
///
/// ```dart
/// PilarTextField(
///   name: 'numero',
///   label: 'Número de factura',
///   required: true,
///   prefix: const Icon(FluentIcons.document),
///   onSaved: (value) => _numero = value,
/// )
///
/// PilarTextField(
///   name: 'notas',
///   label: 'Notas adicionales',
///   maxLines: null,
///   placeholder: 'Escriba observaciones...',
/// )
/// ```
class PilarTextField extends StatelessWidget {
  /// Creates a [PilarTextField].
  const PilarTextField({
    required this.name,
    required this.label,
    super.key,
    this.placeholder,
    this.required = false,
    this.validator,
    this.onSaved,
    this.onChanged,
    this.controller,
    this.initialValue,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.prefix,
    this.autovalidateMode,
    this.infoMessage,
  });

  /// Identifier for this field (used to reference in [FormField.onSaved]
  /// callbacks or for logging/debugging).
  final String name;

  /// Label text rendered above the input via [InfoLabel.rich].
  final String label;

  /// Placeholder shown inside the [TextFormBox] when empty.
  ///
  /// Defaults to the value of [label] when null.
  final String? placeholder;

  /// When true, appends an asterisk (*) to the label and adds a non-empty
  /// validation rule automatically.
  final bool required;

  /// Custom validator function. If [required] is true, the non-empty check
  /// runs first, then this validator is called.
  final String? Function(String?)? validator;

  /// Called when the form is saved via [FormState.save].
  final void Function(String?)? onSaved;

  /// Called on every character change.
  final void Function(String)? onChanged;

  /// Optional external [TextEditingController].
  ///
  /// Cannot be combined with [initialValue].
  final TextEditingController? controller;

  /// Initial text value. Ignored when [controller] is provided.
  final String? initialValue;

  /// Whether the field is interactive. Defaults to true.
  final bool enabled;

  /// When true, the text cannot be edited but is still selectable.
  final bool readOnly;

  /// Maximum number of lines. Use `null` for unlimited multiline input.
  /// Defaults to `1` (single-line).
  final int? maxLines;

  /// Maximum number of characters allowed.
  final int? maxLength;

  /// Keyboard type hint for mobile platforms.
  final TextInputType? keyboardType;

  /// Input formatters applied to the [TextFormBox].
  final List<TextInputFormatter>? inputFormatters;

  /// Widget displayed as a prefix inside the [TextFormBox], typically an
  /// [Icon] using [FluentIcons].
  final Widget? prefix;

  /// Overrides the autovalidate mode for this field.
  final AutovalidateMode? autovalidateMode;

  /// Optional informational tooltip shown via [InfoLabel.rich].
  ///
  /// Note: The base [InfoLabel] constructor (non-rich) supports an
  /// `infoMessage` parameter. For [InfoLabel.rich], display this as a
  /// [Tooltip] on the label if needed in a future iteration.
  final String? infoMessage;

  @override
  Widget build(BuildContext context) {
    final labelSpan = TextSpan(
      children: [
        TextSpan(text: label),
        if (required)
          TextSpan(
            text: ' *',
            style: TextStyle(
              color: Colors.red.defaultBrushFor(
                FluentTheme.of(context).brightness,
              ),
            ),
          ),
      ],
    );

    return InfoLabel.rich(
      label: labelSpan,
      child: TextFormBox(
        placeholder: placeholder ?? label,
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        enabled: enabled,
        readOnly: readOnly,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        prefix: prefix,
        onChanged: onChanged,
        onSaved: onSaved,
        autovalidateMode: autovalidateMode,
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return '$label es requerido';
          }
          return validator?.call(value);
        },
      ),
    );
  }
}
