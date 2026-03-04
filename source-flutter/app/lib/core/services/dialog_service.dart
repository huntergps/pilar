import 'package:fluent_ui/fluent_ui.dart';

/// Servicio de diálogos estándar de PILAR ERP.
///
/// Centraliza el boilerplate de [showDialog] + [ContentDialog] para
/// evitar la duplicación de 19+ `showDialog(builder: ...)` en pantallas.
///
/// Todos los métodos retornan [Future] para que el llamador pueda
/// await la respuesta del usuario.
///
/// Uso típico:
/// ```dart
/// final ok = await PilarDialogService.confirmar(
///   context,
///   title: '¿Eliminar elemento?',
///   message: 'Esta acción no se puede deshacer.',
///   isDanger: true,
/// );
/// if (ok) { ... }
/// ```
abstract final class PilarDialogService {
  PilarDialogService._();

  // ---------------------------------------------------------------------------
  // Confirmar (Sí / No)
  // ---------------------------------------------------------------------------

  /// Muestra un diálogo de confirmación y retorna `true` si el usuario confirma.
  ///
  /// [isDanger] — usa colores de acento rojo para acciones destructivas.
  static Future<bool> confirmar(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirmar',
    String cancelLabel = 'Cancelar',
    bool isDanger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ContentDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          Button(
            child: Text(cancelLabel),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
          ),
          FilledButton(
            style: isDanger
                ? ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(
                      const Color(0xFFD13438),
                    ),
                  )
                : null,
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Info / alerta simple
  // ---------------------------------------------------------------------------

  /// Muestra un diálogo informativo con un solo botón "Cerrar".
  static Future<void> informar(
    BuildContext context, {
    required String title,
    required String message,
    String closeLabel = 'Cerrar',
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ContentDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: Text(closeLabel),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // InfoBar toast
  // ---------------------------------------------------------------------------

  /// Muestra un [InfoBar] de éxito en la parte superior de la pantalla.
  static void toastExito(BuildContext context, String mensaje) {
    displayInfoBar(
      context,
      builder: (ctx, close) => InfoBar(
        title: Text(mensaje),
        severity: InfoBarSeverity.success,
        action: IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
      ),
    );
  }

  /// Muestra un [InfoBar] de error en la parte superior de la pantalla.
  static void toastError(BuildContext context, String mensaje) {
    displayInfoBar(
      context,
      builder: (ctx, close) => InfoBar(
        title: const Text('Error'),
        content: Text(mensaje),
        severity: InfoBarSeverity.error,
        action: IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
      ),
    );
  }

  /// Muestra un [InfoBar] de advertencia.
  static void toastAdvertencia(BuildContext context, String mensaje) {
    displayInfoBar(
      context,
      builder: (ctx, close) => InfoBar(
        title: Text(mensaje),
        severity: InfoBarSeverity.warning,
        action: IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
      ),
    );
  }
}
