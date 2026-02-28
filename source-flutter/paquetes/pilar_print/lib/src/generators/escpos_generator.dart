import 'dart:typed_data';

/// Basic ESC/POS byte generator.
/// Reference: https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/
class EscPosGenerator {
  static const _esc = 0x1B;
  static const _gs = 0x1D;

  // --- Commands ---
  static final Uint8List init = Uint8List.fromList([_esc, 0x40]);
  static final Uint8List cutFull = Uint8List.fromList([_gs, 0x56, 0x00]);
  static final Uint8List cutPartial = Uint8List.fromList([_gs, 0x56, 0x01]);
  static final Uint8List feedLine = Uint8List.fromList([0x0A]);
  static final Uint8List boldOn = Uint8List.fromList([_esc, 0x45, 0x01]);
  static final Uint8List boldOff = Uint8List.fromList([_esc, 0x45, 0x00]);
  static final Uint8List alignLeft = Uint8List.fromList([_esc, 0x61, 0x00]);
  static final Uint8List alignCenter = Uint8List.fromList([_esc, 0x61, 0x01]);
  static final Uint8List alignRight = Uint8List.fromList([_esc, 0x61, 0x02]);
  static final Uint8List doubleHeightOn =
      Uint8List.fromList([_esc, 0x21, 0x10]);
  static final Uint8List doubleHeightOff =
      Uint8List.fromList([_esc, 0x21, 0x00]);

  static Uint8List feedLines(int n) =>
      Uint8List.fromList([_esc, 0x64, n.clamp(0, 255)]);

  static Uint8List text(String value, {String encoding = 'utf-8'}) {
    // Simple ASCII encoding - for full unicode use a proper encoder
    return Uint8List.fromList(
      value.codeUnits.where((c) => c < 256).toList(),
    );
  }

  static Uint8List textLine(String value) {
    return Uint8List.fromList([...text(value), 0x0A]);
  }

  static Uint8List separator({int width = 42, String char = '-'}) {
    return textLine(char * width);
  }

  /// Build a complete ticket from lines.
  static Uint8List buildTicket(List<Uint8List> parts) {
    final builder = BytesBuilder();
    builder.add(init);
    for (final part in parts) {
      builder.add(part);
    }
    builder.add(feedLines(4));
    builder.add(cutPartial);
    return builder.takeBytes();
  }
}
