import 'package:fluent_ui/fluent_ui.dart';

/// A date field for fluent_ui forms that bridges [DatePicker] with Flutter's
/// [FormField] system.
///
/// Renders a fluent_ui [DatePicker] wrapped in a [FormField<DateTime>] so it
/// participates in [Form] validation and [FormState.save] / [FormState.reset]
/// lifecycle calls. An [InfoLabel.rich] is displayed above the picker.
///
/// ## API notes on [DatePicker]
///
/// The fluent_ui [DatePicker] signature:
/// - `selected: DateTime?` — currently selected date; null shows empty fields.
/// - `onChanged: ValueChanged<DateTime>?` — called when the user picks a date.
///   Passing null disables the picker.
/// - `onCancel: VoidCallback?` — called when the user dismisses without
///   selecting.
/// - `startDate: DateTime?` — earliest selectable date.
/// - `endDate: DateTime?` — latest selectable date.
///
/// ## Example
///
/// ```dart
/// PilarDateField(
///   name: 'fecha_emision',
///   label: 'Fecha de emisión',
///   required: true,
///   initialValue: DateTime.now(),
///   firstDate: DateTime(2020),
///   lastDate: DateTime(2030, 12, 31),
///   onSaved: (date) => _fechaEmision = date,
/// )
/// ```
class PilarDateField extends StatefulWidget {
  /// Creates a [PilarDateField].
  const PilarDateField({
    required this.name,
    required this.label,
    super.key,
    this.required = false,
    this.initialValue,
    this.onChanged,
    this.onSaved,
    this.firstDate,
    this.lastDate,
    this.validator,
    this.enabled = true,
    this.infoMessage,
    this.placeholder = 'Seleccionar fecha...',
  });

  /// Identifier for this field.
  final String name;

  /// Label text rendered above the picker via [InfoLabel.rich].
  final String label;

  /// When true, appends an asterisk (*) to the label and enforces a non-null
  /// validation rule.
  final bool required;

  /// Initial selected date. If null, the [DatePicker] shows empty fields.
  final DateTime? initialValue;

  /// Called whenever the user selects a new date. Passes null only when the
  /// user cancels the picker.
  final void Function(DateTime? value)? onChanged;

  /// Called when the form is saved via [FormState.save].
  final void Function(DateTime? value)? onSaved;

  /// Earliest selectable date passed to [DatePicker.startDate].
  final DateTime? firstDate;

  /// Latest selectable date passed to [DatePicker.endDate].
  final DateTime? lastDate;

  /// Custom validator called after the built-in required check.
  final String? Function(DateTime?)? validator;

  /// Whether the picker is interactive.
  ///
  /// When false, [DatePicker.onChanged] is set to null, which disables the
  /// control per fluent_ui's convention.
  final bool enabled;

  /// Optional informational message shown alongside the label.
  final String? infoMessage;

  /// Placeholder text shown below the [DatePicker] when no date is selected.
  ///
  /// Note: [DatePicker] does not have a native placeholder prop. This text is
  /// rendered as a small [Text] widget beneath the picker only when no date
  /// has been selected.
  final String? placeholder;

  @override
  State<PilarDateField> createState() => _PilarDateFieldState();
}

class _PilarDateFieldState extends State<PilarDateField> {
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialValue;
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
      child: FormField<DateTime>(
        initialValue: _selectedDate,
        onSaved: widget.onSaved,
        validator: (value) {
          if (widget.required && value == null) {
            return '${widget.label} es requerida';
          }
          return widget.validator?.call(value);
        },
        builder: (field) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DatePicker(
                selected: _selectedDate,
                onChanged: widget.enabled
                    ? (date) {
                        setState(() => _selectedDate = date);
                        field.didChange(date);
                        widget.onChanged?.call(date);
                      }
                    : null,
                onCancel: () {
                  // User dismissed the picker without selecting — no change.
                  widget.onChanged?.call(null);
                },
                startDate: widget.firstDate,
                endDate: widget.lastDate,
              ),
              // Show placeholder hint when no date has been selected yet.
              if (_selectedDate == null && widget.placeholder != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 4),
                  child: Text(
                    widget.placeholder!,
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ),
              // Validation error text.
              if (field.hasError)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 4),
                  child: Text(
                    field.errorText!,
                    style: theme.typography.caption?.copyWith(
                      color: Colors.red.defaultBrushFor(theme.brightness),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
