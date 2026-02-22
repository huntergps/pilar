/// Sistema extensible de traducción de errores técnicos a mensajes legibles.
///
/// ## Arquitectura
///
/// ```
/// PilarErrorRegistry          — registro central (singleton)
///     └─ List<PilarErrorTranslator>
///            ├─ NetworkErrorTranslator   (pre-registrado)
///            ├─ AuthErrorTranslator      (pre-registrado)
///            └─ <ModuloXxxTranslator>    (registrado por cada módulo)
/// ```
///
/// ## Cómo usar en un módulo nuevo
///
/// ```dart
/// // En la inicialización del módulo (ej: main() o module.init()):
/// PilarErrorRegistry.register(SriErrorTranslator());
///
/// // SriErrorTranslator implementa PilarErrorTranslator:
/// class SriErrorTranslator extends PilarErrorTranslator {
///   @override
///   String? translate(String raw, String locale) {
///     if (raw.contains('70')) return _msg(locale, 'Clave de acceso duplicada');
///     return null; // no manejo este error
///   }
/// }
/// ```
///
/// ## Cómo traducir en código
///
/// ```dart
/// final mensaje = PilarErrorRegistry.translate(exception.toString());
/// context.showErrorSnackBar(mensaje);
/// ```
library;

// ---------------------------------------------------------------------------
// Interfaz base
// ---------------------------------------------------------------------------

/// Contrato que debe implementar cada traductor de errores de módulo.
///
/// [translate] recibe el mensaje de error crudo y el locale activo.
/// Debe devolver el mensaje traducido si lo reconoce, o `null` para
/// indicar que el siguiente traductor en la cadena debe intentarlo.
abstract class PilarErrorTranslator {
  const PilarErrorTranslator();

  /// Traduce [raw] al [locale] dado.
  ///
  /// Devuelve `null` si este traductor no reconoce el error.
  String? translate(String raw, String locale);
}

// ---------------------------------------------------------------------------
// Registro central
// ---------------------------------------------------------------------------

/// Registro central de traductores de errores para PILAR ERP.
///
/// Los traductores se consultan en orden de registro; el primero que
/// devuelva un valor no-null gana. Los traductores de foundation se
/// pre-registran automáticamente.
abstract final class PilarErrorRegistry {
  static final List<PilarErrorTranslator> _translators = [
    const _NetworkErrorTranslator(),
    const _AuthErrorTranslator(),
  ];

  /// Registra un traductor adicional (p.ej. desde un módulo de negocio).
  ///
  /// Los traductores registrados después tienen mayor prioridad que los
  /// de foundation (se prueban primero).
  static void register(PilarErrorTranslator translator) {
    _translators.insert(0, translator);
  }

  /// Traduce [raw] a un mensaje legible en [locale].
  ///
  /// - Prueba los traductores en orden; usa el primero que responda.
  /// - Si ninguno reconoce el error y el mensaje es corto y no técnico,
  ///   lo devuelve tal cual.
  /// - De lo contrario usa el mensaje genérico de fallback.
  ///
  /// El [raw] original siempre está disponible para el botón de copiar —
  /// esta función solo decide qué mostrar al usuario.
  static String translate(String raw, {String locale = 'es'}) {
    final lower = raw.toLowerCase();

    for (final translator in _translators) {
      final result = translator.translate(lower, locale);
      if (result != null) return result;
    }

    // Mensaje corto y sin términos técnicos → mostrar directamente.
    if (raw.length <= 100 &&
        !raw.contains('Exception') &&
        !raw.contains('Error:') &&
        !raw.contains('errno')) {
      return raw;
    }

    return _fallback(locale);
  }

  static String _fallback(String locale) => switch (locale) {
        'en' => 'An unexpected error occurred. Use the copy button for details.',
        _ => 'Ocurrió un error inesperado. '
            'Usa el botón de copiar para obtener los detalles.',
      };
}

// ---------------------------------------------------------------------------
// Traductores de foundation (pre-registrados)
// ---------------------------------------------------------------------------

/// Errores de red y conectividad.
class _NetworkErrorTranslator extends PilarErrorTranslator {
  const _NetworkErrorTranslator();

  @override
  String? translate(String raw, String locale) {
    // Sin conexión / operación de red bloqueada
    if (raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('connection failed') ||
        raw.contains('operation not permitted') ||
        raw.contains('network is unreachable') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection refused')) {
      return _msg(locale,
          es: 'No se pudo conectar al servidor. '
              'Verifica tu conexión a internet.',
          en: 'Could not connect to the server. '
              'Check your internet connection.');
    }

    // Timeout
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return _msg(locale,
          es: 'La conexión tardó demasiado. Intenta de nuevo.',
          en: 'The connection timed out. Please try again.');
    }

    // SSL / TLS
    if (raw.contains('handshake') || raw.contains('certificate')) {
      return _msg(locale,
          es: 'Error de seguridad en la conexión. '
              'Verifica la configuración del servidor.',
          en: 'Connection security error. Check the server configuration.');
    }

    return null;
  }
}

/// Errores de autenticación (Supabase Auth / JWT).
class _AuthErrorTranslator extends PilarErrorTranslator {
  const _AuthErrorTranslator();

  @override
  String? translate(String raw, String locale) {
    // Credenciales inválidas
    if (raw.contains('invalid login credentials') ||
        raw.contains('invalid email or password')) {
      return _msg(locale,
          es: 'Correo electrónico o contraseña incorrectos.',
          en: 'Invalid email or password.');
    }

    // Usuario ya registrado (puede ser que no haya confirmado su correo)
    if (raw.contains('user already registered') ||
        raw.contains('already been registered')) {
      return _msg(locale,
          es: 'Este correo ya tiene una cuenta registrada. '
              'Si aún no confirmaste tu correo, revisa tu bandeja de entrada.',
          en: 'This email is already registered. '
              'If you have not confirmed your email yet, check your inbox.');
    }

    // Correo no confirmado
    if (raw.contains('email not confirmed')) {
      return _msg(locale,
          es: 'Debes confirmar tu correo electrónico antes de continuar. '
              'Revisa tu bandeja de entrada.',
          en: 'Please confirm your email address before continuing. '
              'Check your inbox.');
    }

    // Rate limiting
    if (raw.contains('too many requests') || raw.contains('rate limit')) {
      return _msg(locale,
          es: 'Demasiados intentos. Espera unos minutos antes de reintentar.',
          en: 'Too many attempts. Please wait a few minutes before trying again.');
    }

    // Contraseña débil
    if (raw.contains('password should be') ||
        raw.contains('weak password') ||
        raw.contains('password is too short')) {
      return _msg(locale,
          es: 'La contraseña es demasiado débil. '
              'Usa al menos 6 caracteres con letras y números.',
          en: 'Password is too weak. '
              'Use at least 6 characters with letters and numbers.');
    }

    // Sesión / token expirado
    if (raw.contains('token has expired') ||
        raw.contains('invalid refresh token') ||
        raw.contains('session_not_found') ||
        raw.contains('jwt expired')) {
      return _msg(locale,
          es: 'Tu sesión ha expirado. Por favor inicia sesión nuevamente.',
          en: 'Your session has expired. Please sign in again.');
    }

    // Correo no encontrado (recuperación de contraseña)
    if (raw.contains('user not found') || raw.contains('email not found')) {
      return _msg(locale,
          es: 'No existe una cuenta con ese correo electrónico.',
          en: 'No account found with that email address.');
    }

    return null;
  }
}

// ---------------------------------------------------------------------------
// Helper de localización interno
// ---------------------------------------------------------------------------

String _msg(String locale, {required String es, required String en}) =>
    locale == 'en' ? en : es;
