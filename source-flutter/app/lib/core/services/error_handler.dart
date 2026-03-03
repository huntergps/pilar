import 'package:flutter/foundation.dart';

/// Configura captura global de errores Flutter.
/// Llama a esto en main() antes de runApp().
void setupGlobalErrorHandling() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _logError('FlutterError', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _logError('PlatformDispatcher', error, stack);
    return true;
  };
}

void _logError(String source, Object error, StackTrace? stack) {
  if (kDebugMode) {
    debugPrint('[$source] $error\n$stack');
  }
  // TODO: Integrar Sentry cuando se configure DSN
  // Sentry.captureException(error, stackTrace: stack);
}
