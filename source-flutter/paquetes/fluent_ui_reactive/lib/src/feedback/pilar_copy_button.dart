import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// Botón de copiar al portapapeles con feedback visual animado.
///
/// Al presionar:
/// 1. Copia [text] al portapapeles.
/// 2. Cambia el ícono a `check_mark` por [feedbackDuration].
/// 3. Vuelve al ícono de copiar.
///
/// ## Uso
/// ```dart
/// PilarCopyButton(text: errorMessage)
/// PilarCopyButton(text: codigoSRI, tooltip: 'Copiar código')
/// ```
class PilarCopyButton extends StatefulWidget {
  /// Texto que se copiará al portapapeles.
  final String text;

  /// Tooltip mostrado antes de copiar. Por defecto 'Copiar'.
  final String tooltip;

  /// Tooltip mostrado después de copiar. Por defecto '¡Copiado!'.
  final String copiedTooltip;

  /// Tiempo que se muestra el ícono de confirmación. Por defecto 2 s.
  final Duration feedbackDuration;

  /// Tamaño del ícono. Por defecto 14.
  final double iconSize;

  const PilarCopyButton({
    super.key,
    required this.text,
    this.tooltip = 'Copiar',
    this.copiedTooltip = '¡Copiado!',
    this.feedbackDuration = const Duration(seconds: 2),
    this.iconSize = 14,
  });

  @override
  State<PilarCopyButton> createState() => _PilarCopyButtonState();
}

class _PilarCopyButtonState extends State<PilarCopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(widget.feedbackDuration);
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _copied ? widget.copiedTooltip : widget.tooltip,
      child: IconButton(
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            _copied ? FluentIcons.check_mark : FluentIcons.copy,
            size: widget.iconSize,
            key: ValueKey(_copied),
          ),
        ),
        onPressed: _copied ? null : _copy,
      ),
    );
  }
}
