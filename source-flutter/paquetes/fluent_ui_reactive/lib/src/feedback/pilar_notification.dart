import 'package:fluent_ui/fluent_ui.dart';

import 'package:fluent_ui_reactive/src/feedback/pilar_copy_button.dart';

/// Widget de notificación estándar para PILAR ERP.
///
/// Construye un [InfoBar] con título, cuerpo, botón de copiar opcional y
/// un botón de cierre. Pensado para usarse dentro de [displayInfoBar] pero
/// también como widget inline en cualquier pantalla.
///
/// ## Uso con displayInfoBar (overlay temporal)
/// ```dart
/// displayInfoBar(
///   context,
///   duration: const Duration(seconds: 8),
///   builder: (ctx, close) => PilarNotification(
///     title: 'Error',
///     message: PilarErrorRegistry.translate(e.toString()),
///     originalMessage: e.toString(),
///     severity: InfoBarSeverity.error,
///     close: close,
///     showCopy: true,
///   ),
/// );
/// ```
///
/// ## Uso inline (permanente en pantalla)
/// ```dart
/// PilarNotification(
///   title: 'Sin conexión',
///   message: 'No se pudo cargar la lista de facturas.',
///   severity: InfoBarSeverity.warning,
/// )
/// ```
class PilarNotification extends StatelessWidget {
  /// Título corto (p. ej. "Error", "Advertencia", "Completado").
  final String title;

  /// Mensaje legible para el usuario.
  final String message;

  /// Mensaje original/técnico copiado al portapapeles.
  /// Si es null se copia [message].
  final String? originalMessage;

  /// Severidad visual del InfoBar.
  final InfoBarSeverity severity;

  /// Callback para cerrar el overlay. Null cuando se usa como widget inline.
  final VoidCallback? close;

  /// Etiqueta del botón de cierre. Por defecto 'Cerrar'.
  final String? actionLabel;

  /// Muestra el [PilarCopyButton] junto al botón de cierre.
  final bool showCopy;

  /// Ancho máximo del InfoBar. Por defecto 400.
  final double maxWidth;

  const PilarNotification({
    super.key,
    required this.title,
    required this.message,
    this.originalMessage,
    this.severity = InfoBarSeverity.info,
    this.close,
    this.actionLabel,
    this.showCopy = false,
    this.maxWidth = 400,
  });

  @override
  Widget build(BuildContext context) {
    final isLong = message.length > 80;
    final hasActions = showCopy || close != null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 260),
      child: InfoBar(
        title: Text(title),
        content: Text(message),
        severity: severity,
        isLong: isLong,
        action: hasActions
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showCopy)
                    PilarCopyButton(text: originalMessage ?? message),
                  if (close != null)
                    HyperlinkButton(
                      onPressed: close,
                      child: Text(actionLabel ?? 'Cerrar'),
                    ),
                ],
              )
            : null,
      ),
    );
  }
}
