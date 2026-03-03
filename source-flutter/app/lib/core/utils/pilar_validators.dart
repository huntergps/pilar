/// Validadores genéricos para formularios PILAR ERP.
///
/// Todos los métodos retornan `null` si el valor es válido,
/// o un mensaje de error si es inválido.
/// Campos opcionales (null/vacío) retornan null (válido) a menos que
/// se use [required].
///
/// Validadores específicos por país van en sus módulos de extensión:
/// - Ecuador: `modules/extensiones/facturacion_ec/` → SriValidators (RUC, cédula)
class PilarValidators {
  PilarValidators._();

  static String? required(String? v, [String label = 'Este campo']) {
    if (v == null || v.trim().isEmpty) return '$label es requerido';
    return null;
  }

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final re = RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$');
    return re.hasMatch(v.trim()) ? null : 'Email inválido';
  }

  static String? telefono(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (!RegExp(r'^\+?[\d\s\-()]{7,15}$').hasMatch(v.trim())) {
      return 'Teléfono inválido';
    }
    return null;
  }

  static String? minLength(String? v, int min) {
    if (v == null || v.length < min) return 'Mínimo $min caracteres';
    return null;
  }

  static String? maxLength(String? v, int max) {
    if (v != null && v.length > max) return 'Máximo $max caracteres';
    return null;
  }
}
