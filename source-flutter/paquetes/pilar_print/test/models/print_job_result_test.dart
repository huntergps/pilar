import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';

void main() {
  group('PrintJobResult', () {
    test('ok() has isOk=true and null errorMessage', () {
      final result = PrintJobResult.ok();

      expect(result.isOk, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('error() has isOk=false and errorMessage set', () {
      final result = PrintJobResult.error('Sin papel');

      expect(result.isOk, isFalse);
      expect(result.errorMessage, 'Sin papel');
    });

    test('isError is inverse of isOk', () {
      final ok = PrintJobResult.ok();
      final err = PrintJobResult.error('fallo');

      expect(ok.isError, isFalse);
      expect(err.isError, isTrue);
    });

    test('toString() for ok result', () {
      final result = PrintJobResult.ok();

      expect(result.toString(), 'PrintJobResult(ok)');
    });

    test('toString() for error result', () {
      final result = PrintJobResult.error('Timeout');

      expect(result.toString(), 'PrintJobResult(error: Timeout)');
    });
  });
}
