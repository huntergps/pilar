import 'dart:typed_data';

/// Generador de comandos ESC/P (Epson Standard Code for Printers).
///
/// Usado para impresoras matriciales (dot-matrix) como Epson FX/LX/DFX,
/// Olivetti, OKI, etc. Típicamente para formularios continuos, facturas
/// en papel de carbón (1 original + N copias).
///
/// Diferencias clave vs ESC/POS (térmica de ticket):
/// - ESC/P usa más comandos de posicionamiento absoluto
/// - No tiene comando de corte (la hoja continua se avanza manualmente)
/// - Soporta impresión en color con cintas de colores (mod. seleccionados)
/// - Columnas: típicamente 80 o 132 caracteres en modo condensado
///
/// Referencia: Epson ESC/P Reference Manual
class EscpGenerator {
  static const _esc = 0x1B;
  static const _cr = 0x0D;
  static const _lf = 0x0A;
  static const _ff = 0x0C; // Form Feed — avanza a siguiente hoja

  // ---------------------------------------------------------------------------
  // Inicialización
  // ---------------------------------------------------------------------------

  /// Inicializar impresora (ESC @)
  static final Uint8List init = Uint8List.fromList([_esc, 0x40]);

  // ---------------------------------------------------------------------------
  // Avance de papel
  // ---------------------------------------------------------------------------

  static final Uint8List lineFeed = Uint8List.fromList([_lf]);
  static final Uint8List carriageReturn = Uint8List.fromList([_cr]);
  static final Uint8List crLf = Uint8List.fromList([_cr, _lf]);

  /// Form Feed — avanza al inicio de la siguiente hoja
  static final Uint8List formFeed = Uint8List.fromList([_ff]);

  /// Avanzar [n] líneas (ESC J n) — 1/216 pulgadas × n
  static Uint8List feedDots(int n) =>
      Uint8List.fromList([_esc, 0x4A, n.clamp(0, 255)]);

  // ---------------------------------------------------------------------------
  // Estilo de texto
  // ---------------------------------------------------------------------------

  /// Negrita ON (ESC E)
  static final Uint8List boldOn = Uint8List.fromList([_esc, 0x45]);

  /// Negrita OFF (ESC F)
  static final Uint8List boldOff = Uint8List.fromList([_esc, 0x46]);

  /// Subrayado ON (ESC - 1)
  static final Uint8List underlineOn = Uint8List.fromList([_esc, 0x2D, 0x01]);

  /// Subrayado OFF (ESC - 0)
  static final Uint8List underlineOff =
      Uint8List.fromList([_esc, 0x2D, 0x00]);

  /// Modo condensado ON (ESC SI) — 17.1 cpi, 132 columnas en papel 80col
  static final Uint8List condensedOn = Uint8List.fromList([_esc, 0x0F]);

  /// Modo condensado OFF (ESC DC2)
  static final Uint8List condensedOff = Uint8List.fromList([_esc, 0x12]);

  /// Doble ancho ON (ESC W 1)
  static final Uint8List doubleWidthOn =
      Uint8List.fromList([_esc, 0x57, 0x01]);

  /// Doble ancho OFF (ESC W 0)
  static final Uint8List doubleWidthOff =
      Uint8List.fromList([_esc, 0x57, 0x00]);

  // ---------------------------------------------------------------------------
  // Fuente y pitch
  // ---------------------------------------------------------------------------

  /// Seleccionar fuente Roman 10 cpi (ESC P) — modo normal
  static final Uint8List font10cpi = Uint8List.fromList([_esc, 0x50]);

  /// Seleccionar fuente 12 cpi / elite (ESC M)
  static final Uint8List font12cpi = Uint8List.fromList([_esc, 0x4D]);

  // ---------------------------------------------------------------------------
  // Posicionamiento horizontal
  // ---------------------------------------------------------------------------

  /// Tab horizontal (0x09) — avanza al siguiente tabulador
  static final Uint8List tab = Uint8List.fromList([0x09]);

  /// Establecer tabuladores horizontales en columnas [cols] (ESC D)
  /// Máximo 32 tabuladores, columnas en orden ascendente, terminar con 0.
  static Uint8List setTabs(List<int> cols) {
    final bytes = [_esc, 0x44, ...cols.take(32).map((c) => c.clamp(1, 255)), 0x00];
    return Uint8List.fromList(bytes);
  }

  // ---------------------------------------------------------------------------
  // Helpers de texto
  // ---------------------------------------------------------------------------

  static Uint8List text(String value) =>
      Uint8List.fromList(value.codeUnits.where((c) => c < 256).toList());

  static Uint8List textLine(String value) =>
      Uint8List.fromList([...text(value), _cr, _lf]);

  static Uint8List separator({int width = 80, String char = '-'}) =>
      textLine(char * width);

  // ---------------------------------------------------------------------------
  // Builder de documento completo
  // ---------------------------------------------------------------------------

  /// Construye un documento matricial listo para enviar vía TCP.
  /// [parts] son bloques de bytes generados con los helpers de esta clase.
  /// [feedLines] controla cuántas líneas en blanco al final antes del FF.
  static Uint8List buildDocument(
    List<Uint8List> parts, {
    int feedLines = 6,
    bool formFeedAtEnd = true,
  }) {
    final builder = BytesBuilder();
    builder.add(init);
    for (final part in parts) {
      builder.add(part);
    }
    for (var i = 0; i < feedLines; i++) {
      builder.add(crLf);
    }
    if (formFeedAtEnd) builder.add(formFeed);
    return builder.takeBytes();
  }
}
