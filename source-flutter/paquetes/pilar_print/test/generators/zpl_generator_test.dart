import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';

void main() {
  group('ZplGenerator', () {
    test('labelStart is ^XA', () {
      expect(ZplGenerator.labelStart, '^XA');
    });

    test('labelEnd is ^XZ', () {
      expect(ZplGenerator.labelEnd, '^XZ');
    });

    test('labelSize returns correct ZPL', () {
      final result = ZplGenerator.labelSize(width: 609, length: 406);
      expect(result, '^PW609^LL406');
    });

    test('labelSize with custom dimensions', () {
      final result = ZplGenerator.labelSize(width: 800, length: 600);
      expect(result, '^PW800^LL600');
    });

    test('fieldOrigin returns correct ZPL', () {
      expect(ZplGenerator.fieldOrigin(30, 100), '^FO30,100');
    });

    test('fieldOrigin at zero', () {
      expect(ZplGenerator.fieldOrigin(0, 0), '^FO0,0');
    });

    test('fieldData returns correct ZPL', () {
      expect(ZplGenerator.fieldData('HELLO'), '^FDHELLO^FS');
    });

    test('fieldData escapes ^ in value', () {
      final result = ZplGenerator.fieldData('TEST^VALUE');
      expect(result, r'^FDTEST\^VALUE^FS');
    });

    test('font returns correct ZPL', () {
      final result = ZplGenerator.font(
        letter: '0',
        orientation: 'N',
        height: 40,
        width: 30,
      );
      expect(result, '^A0N,40,30');
    });

    test('font with defaults', () {
      final result = ZplGenerator.font();
      expect(result, '^AAN,30,20');
    });

    test('barcode128 returns correct ZPL', () {
      final result = ZplGenerator.barcode128(
        height: 50,
        printInterpretation: true,
        position: 'N',
      );
      expect(result, '^BC,50,Y,N');
    });

    test('barcode128 without interpretation', () {
      final result = ZplGenerator.barcode128(
        height: 80,
        printInterpretation: false,
      );
      expect(result, '^BC,80,N,N');
    });

    test('qrCode returns correct ZPL', () {
      expect(ZplGenerator.qrCode(magnification: 4), '^BQN,2,4');
      expect(ZplGenerator.qrCode(magnification: 8), '^BQN,2,8');
    });

    test('buildLabel contains labelStart and labelEnd', () {
      final label = ZplGenerator.buildLabel(
        nombre: 'Producto Test',
        codigo: '1234567890',
        precio: r'$9.99',
      );

      final text = String.fromCharCodes(label);

      expect(text, contains('^XA'));
      expect(text, contains('^XZ'));
      expect(text, contains('Producto Test'));
      expect(text, contains('1234567890'));
      expect(text, contains(r'$9.99'));
    });

    test('buildLabel uses default dimensions', () {
      final label = ZplGenerator.buildLabel(
        nombre: 'A',
        codigo: 'B',
        precio: 'C',
      );

      final text = String.fromCharCodes(label);

      expect(text, contains('^PW609^LL406'));
    });
  });
}
