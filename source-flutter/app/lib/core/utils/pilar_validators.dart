/// Validadores para formularios PILAR ERP.
///
/// Todos los metodos retornan `null` si el valor es valido,
/// o un mensaje de error si es invalido.
/// Campos opcionales (null/vacio) retornan null (valido) a menos que
/// se use [required].
class PilarValidators {
  PilarValidators._();

  static String? required(String? v, [String label = 'Este campo']) {
    if (v == null || v.trim().isEmpty) return '$label es requerido';
    return null;
  }

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final re = RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$');
    return re.hasMatch(v.trim()) ? null : 'Email invalido';
  }

  /// RUC Ecuador: 13 digitos, primer digito segun provincia (01-24).
  static String? ruc(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final s = v.trim();
    if (!RegExp(r'^\d{13}$').hasMatch(s)) return 'RUC debe tener 13 digitos';
    final prov = int.parse(s.substring(0, 2));
    if (prov < 1 || prov > 24) return 'Codigo de provincia invalido';
    return null;
  }

  /// Cedula Ecuador: 10 digitos con algoritmo de modulo 10.
  static String? cedula(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final s = v.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(s)) return 'Cedula debe tener 10 digitos';
    final prov = int.parse(s.substring(0, 2));
    if (prov < 1 || prov > 24) return 'Codigo de provincia invalido';
    final digits = s.split('').map(int.parse).toList();
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      int d = digits[i];
      if (i.isEven) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == digits[9] ? null : 'Cedula invalida';
  }

  static String? telefono(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (!RegExp(r'^\+?[\d\s\-()]{7,15}$').hasMatch(v.trim())) {
      return 'Telefono invalido';
    }
    return null;
  }

  static String? minLength(String? v, int min) {
    if (v == null || v.length < min) return 'Minimo $min caracteres';
    return null;
  }
}
