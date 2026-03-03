import 'package:intl/intl.dart';

/// Formateadores de visualizacion para PILAR ERP.
///
/// Todos los metodos aceptan `null` y retornan '-' como fallback.
/// Usan locale `es_EC` para formato ecuatoriano.
class PilarFormatters {
  PilarFormatters._();

  static final _money = NumberFormat('#,##0.00', 'es_EC');
  static final _quantity = NumberFormat('#,##0.######', 'es_EC');
  static final _percent = NumberFormat('##0.00', 'es_EC');
  static final _date = DateFormat('dd/MM/yyyy', 'es_EC');
  static final _datetime = DateFormat('dd/MM/yyyy HH:mm', 'es_EC');

  static String money(num? v) => v == null ? '-' : '\$ ${_money.format(v)}';
  static String quantity(num? v) => v == null ? '-' : _quantity.format(v);
  static String percent(num? v) =>
      v == null ? '-' : '${_percent.format(v)} %';
  static String date(DateTime? v) => v == null ? '-' : _date.format(v);
  static String datetime(DateTime? v) => v == null ? '-' : _datetime.format(v);
}
