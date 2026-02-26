import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

SizedBox spacer(double height) => SizedBox(height: height);

// ---------------------------------------------------------------------------
// Durations
// ---------------------------------------------------------------------------

const _kInfoDuration = Duration(seconds: 4);
const _kErrorDuration = Duration(seconds: 8);

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

/// Muestra notificaciones [InfoBar] overlay usando [displayInfoBar].
///
/// Los errores se traducen automáticamente vía [PilarErrorRegistry].
/// El botón de copiar guarda el mensaje técnico original en el portapapeles.
extension ShowInfoBar on BuildContext {
  void showSnackBar(String message, {String? actionLabel}) {
    displayInfoBar(
      this,
      duration: _kInfoDuration,
      alignment: Alignment.topCenter,
      builder: (context, close) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
        child: PilarNotification(
          title: 'Información',
          message: message,
          severity: InfoBarSeverity.info,
          close: close,
          actionLabel: actionLabel,
        ),
      ),
    );
  }

  void showErrorSnackBar(String message, {String? actionLabel}) {
    displayInfoBar(
      this,
      duration: _kErrorDuration,
      alignment: Alignment.topCenter,
      builder: (context, close) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
        child: PilarNotification(
          title: 'Error',
          message: PilarErrorRegistry.translate(message),
          originalMessage: message,
          severity: InfoBarSeverity.error,
          close: close,
          actionLabel: actionLabel,
          showCopy: true,
        ),
      ),
    );
  }

  void showSuccessSnackBar(String message, {String? actionLabel}) {
    displayInfoBar(
      this,
      duration: _kInfoDuration,
      alignment: Alignment.topCenter,
      builder: (context, close) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
        child: PilarNotification(
          title: 'Completado',
          message: message,
          severity: InfoBarSeverity.success,
          close: close,
          actionLabel: actionLabel,
        ),
      ),
    );
  }

  void showWarningSnackBar(String message, {String? actionLabel}) {
    displayInfoBar(
      this,
      duration: _kErrorDuration,
      alignment: Alignment.topCenter,
      builder: (context, close) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
        child: PilarNotification(
          title: 'Advertencia',
          message: PilarErrorRegistry.translate(message),
          originalMessage: message,
          severity: InfoBarSeverity.warning,
          close: close,
          actionLabel: actionLabel,
          showCopy: true,
        ),
      ),
    );
  }
}
