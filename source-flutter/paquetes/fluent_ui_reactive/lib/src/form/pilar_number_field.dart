import 'package:decimal/decimal.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// A numeric form field for fluent_ui that uses [Decimal] for all values,
/// never `double`.
///
/// Wraps [TextFormBox] from `fluent_ui` with:
/// - An [InfoLabel.rich] label with optional asterisk for required fields.
/// - Currency mode: `$` prefix, right-aligned text, and 2-decimal formatting.
/// - Input restricted to digits and a single decimal point.
/// - Validation for required, min, and max constraints.
///
/// ## Example
///
/// ```dart
/// // Simple numeric field
/// PilarNumberField(
///   name: 'cantidad',
///   label: 'Cantidad',
///   required: true,
///   min: Decimal.one,
///   onSaved: (value) => _cantidad = value,
/// )
///
/// // Currency field
/// PilarNumberField(
///   name: 'total',
///   label: 'Total a pagar',
///   currency: true,
///   initialValue: Decimal.parse('150.00'),
///   onChanged: (value) => setState(() => _total = value),
/// )
/// ```
class PilarNumberField extends StatefulWidget {
  /// Creates a [PilarNumberField].
  const PilarNumberField({
    required this.name,
    required this.label,
    super.key,
    this.required = false,
    this.currency = false,
    this.initialValue,
    this.onChanged,
    this.onSaved,
    this.min,
    this.max,
    this.validator,
    this.enabled = true,
    this.readOnly = false,
    this.placeholder,
    this.decimalPlaces = 2,
    this.infoMessage,
  });

  /// Identifier for this field.
  final String name;

  /// Label text rendered above the input.
  final String label;

  /// When true, appends an asterisk (*) to the label and enforces a non-null
  /// validation rule.
  final bool required;

  /// When true, displays a `$` prefix, aligns text to the right, and formats
  /// the initial value with 2 decimal places.
  final bool currency;

  /// Initial [Decimal] value. Formatted as a string in the underlying
  /// [TextFormBox].
  final Decimal? initialValue;

  /// Called when the parsed [Decimal] value changes. Passes `null` when the
  /// text cannot be parsed.
  final void Function(Decimal? value)? onChanged;

  /// Called when the form is saved. Passes `null` when the text field is
  /// empty or unparseable.
  final void Function(Decimal? value)? onSaved;

  /// Minimum allowed value. Validation fails if the entered value is below
  /// this threshold.
  final Decimal? min;

  /// Maximum allowed value. Validation fails if the entered value exceeds
  /// this threshold.
  final Decimal? max;

  /// Custom validator called after built-in required/min/max checks.
  final String? Function(Decimal?)? validator;

  /// Whether the field is interactive. Defaults to true.
  final bool enabled;

  /// When true, the text cannot be edited but is still selectable.
  final bool readOnly;

  /// Placeholder text. Defaults to `'0.00'` in currency mode, `'0'`
  /// otherwise.
  final String? placeholder;

  /// Number of decimal places used for display when [initialValue] is set in
  /// non-currency mode. Defaults to `2`.
  final int decimalPlaces;

  /// Optional informational message shown alongside the label.
  final String? infoMessage;

  @override
  State<PilarNumberField> createState() => _PilarNumberFieldState();
}

class _PilarNumberFieldState extends State<PilarNumberField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initialText = _formatInitial(widget.initialValue);
    _controller = TextEditingController(text: initialText);
  }

  String _formatInitial(Decimal? value) {
    if (value == null) return '';
    if (widget.currency) return value.toStringAsFixed(2);
    return value.toStringAsFixed(widget.decimalPlaces);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    final labelSpan = TextSpan(
      children: [
        TextSpan(text: widget.label),
        if (widget.required)
          TextSpan(
            text: ' *',
            style: TextStyle(
              color: Colors.red.defaultBrushFor(theme.brightness),
            ),
          ),
      ],
    );

    return InfoLabel.rich(
      label: labelSpan,
      child: TextFormBox(
        controller: _controller,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        placeholder: widget.placeholder ?? (widget.currency ? '0.00' : '0'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
        ],
        prefix: widget.currency
            ? const Padding(
                padding: EdgeInsetsDirectional.only(start: 8),
                child: Text('\$'),
              )
            : null,
        textAlign: widget.currency ? TextAlign.right : TextAlign.start,
        onChanged: (text) {
          final parsed = Decimal.tryParse(text);
          widget.onChanged?.call(parsed);
        },
        onSaved: (text) {
          final parsed =
              (text != null && text.isNotEmpty) ? Decimal.tryParse(text) : null;
          widget.onSaved?.call(parsed);
        },
        validator: (text) {
          final parsed = (text != null && text.isNotEmpty)
              ? Decimal.tryParse(text)
              : null;

          if (widget.required && parsed == null) {
            return '${widget.label} es requerido';
          }

          if (parsed != null) {
            if (widget.min != null && parsed < widget.min!) {
              return 'Mínimo: ${widget.min}';
            }
            if (widget.max != null && parsed > widget.max!) {
              return 'Máximo: ${widget.max}';
            }
          }

          return widget.validator?.call(parsed);
        },
      ),
    );
  }
}
