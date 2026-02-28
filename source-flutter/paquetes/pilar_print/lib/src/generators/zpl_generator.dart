import 'dart:typed_data';

/// Basic ZPL II generator for Zebra label printers.
/// Reference: https://www.zebra.com/content/dam/zebra_new_ia/en-us/manuals/printers/common/programming/zpl-zbi2-pm-en.pdf
class ZplGenerator {
  /// Start label
  static const String labelStart = '^XA';

  /// End label
  static const String labelEnd = '^XZ';

  /// Set label dimensions: width in dots, length in dots
  static String labelSize({int width = 609, int length = 406}) =>
      '^PW$width^LL$length';

  /// Field origin: x, y in dots
  static String fieldOrigin(int x, int y) => '^FO$x,$y';

  /// Font: letter (A-Z, 0), orientation (N/R/I/B), height, width in dots
  static String font({
    String letter = 'A',
    String orientation = 'N',
    int height = 30,
    int width = 20,
  }) =>
      '^A$letter$orientation,$height,$width';

  /// Field data
  static String fieldData(String value) =>
      '^FD${value.replaceAll('^', '\\^')}^FS';

  /// Code 128 barcode: height in dots, printInterpretation, above/below
  static String barcode128({
    int height = 50,
    bool printInterpretation = true,
    String position = 'N', // N=below, A=above
  }) =>
      '^BC,$height,${printInterpretation ? 'Y' : 'N'},$position';

  /// QR code: magnification 1-10
  static String qrCode({int magnification = 4}) => '^BQN,2,$magnification';

  /// Build a simple product label.
  static Uint8List buildLabel({
    required String nombre,
    required String codigo,
    required String precio,
    int labelWidthDots = 609,
    int labelLengthDots = 406,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(labelStart);
    buffer.writeln(labelSize(width: labelWidthDots, length: labelLengthDots));

    // Nombre del producto
    buffer.writeln(fieldOrigin(30, 30));
    buffer.writeln(font(letter: '0', height: 40, width: 30));
    buffer.writeln(fieldData(nombre));

    // Codigo de barras
    buffer.writeln(fieldOrigin(30, 100));
    buffer.writeln(barcode128(height: 80));
    buffer.writeln(fieldData(codigo));

    // Precio
    buffer.writeln(fieldOrigin(30, 230));
    buffer.writeln(font(letter: '0', height: 50, width: 40));
    buffer.writeln(fieldData(precio));

    buffer.writeln(labelEnd);

    return Uint8List.fromList(buffer.toString().codeUnits);
  }
}
