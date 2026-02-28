import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';

void main() {
  group('PrintFormat', () {
    test('has escpos, zpl, pdf, escp, texto values', () {
      expect(PrintFormat.values, containsAll([
        PrintFormat.escpos,
        PrintFormat.zpl,
        PrintFormat.pdf,
        PrintFormat.escp,
        PrintFormat.texto,
      ]));
      expect(PrintFormat.values.length, 5);
    });
  });

  group('PrintDocument', () {
    test('escpos() creates ESC/POS document with rawBytes', () {
      final bytes = Uint8List.fromList([0x1B, 0x40, 0x48, 0x69]);
      final doc = PrintDocument.escpos(bytes);

      expect(doc.format, PrintFormat.escpos);
      expect(doc.rawBytes, equals(bytes));
      expect(doc.pdfBytes, isNull);
    });

    test('zpl() creates ZPL document with rawBytes', () {
      final bytes = Uint8List.fromList([0x5E, 0x58, 0x41]);
      final doc = PrintDocument.zpl(bytes);

      expect(doc.format, PrintFormat.zpl);
      expect(doc.rawBytes, equals(bytes));
      expect(doc.pdfBytes, isNull);
    });

    test('pdf() creates PDF document with pdfBytes', () {
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
      final doc = PrintDocument.pdf(bytes);

      expect(doc.format, PrintFormat.pdf);
      expect(doc.pdfBytes, equals(bytes));
      expect(doc.rawBytes, isNull);
    });
  });
}
