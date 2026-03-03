import 'package:intl/intl.dart';

/// Formateadores de visualización genéricos para PILAR ERP.
///
/// Todos los métodos aceptan `null` y retornan '-' como fallback.
/// El locale y símbolo de moneda se configuran por empresa; estos formateadores
/// usan valores neutros por defecto.
///
/// Formateadores específicos por país (símbolo $, formato SRI, etc.) van en sus
/// módulos de extensión: `modules/extensiones/facturacion_ec/`.
class PilarFormatters {
  PilarFormatters._();

  static NumberFormat _moneyFmt(String locale) =>
      NumberFormat('#,##0.00', locale);
  static NumberFormat _quantityFmt(String locale) =>
      NumberFormat('#,##0.######', locale);
  static NumberFormat _percentFmt(String locale) =>
      NumberFormat('##0.00', locale);
  static DateFormat _dateFmt(String locale) =>
      DateFormat('dd/MM/yyyy', locale);
  static DateFormat _datetimeFmt(String locale) =>
      DateFormat('dd/MM/yyyy HH:mm', locale);

  static String money(num? v, {String locale = 'en_US', String symbol = ''}) {
    if (v == null) return '-';
    final formatted = _moneyFmt(locale).format(v);
    return symbol.isEmpty ? formatted : '$symbol $formatted';
  }

  static String quantity(num? v, {String locale = 'en_US'}) =>
      v == null ? '-' : _quantityFmt(locale).format(v);

  static String percent(num? v, {String locale = 'en_US'}) =>
      v == null ? '-' : '${_percentFmt(locale).format(v)} %';

  static String date(DateTime? v, {String locale = 'en_US'}) =>
      v == null ? '-' : _dateFmt(locale).format(v);

  static String datetime(DateTime? v, {String locale = 'en_US'}) =>
      v == null ? '-' : _datetimeFmt(locale).format(v);
}
