import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';

void main() {
  group('EscPosGenerator', () {
    test('init bytes are ESC @', () {
      expect(EscPosGenerator.init, equals(Uint8List.fromList([0x1B, 0x40])));
    });

    test('cutFull bytes are GS V 0', () {
      expect(
        EscPosGenerator.cutFull,
        equals(Uint8List.fromList([0x1D, 0x56, 0x00])),
      );
    });

    test('cutPartial bytes are GS V 1', () {
      expect(
        EscPosGenerator.cutPartial,
        equals(Uint8List.fromList([0x1D, 0x56, 0x01])),
      );
    });

    test('feedLine is LF', () {
      expect(EscPosGenerator.feedLine, equals(Uint8List.fromList([0x0A])));
    });

    test('boldOn bytes', () {
      expect(
        EscPosGenerator.boldOn,
        equals(Uint8List.fromList([0x1B, 0x45, 0x01])),
      );
    });

    test('boldOff bytes', () {
      expect(
        EscPosGenerator.boldOff,
        equals(Uint8List.fromList([0x1B, 0x45, 0x00])),
      );
    });

    test('alignLeft bytes', () {
      expect(
        EscPosGenerator.alignLeft,
        equals(Uint8List.fromList([0x1B, 0x61, 0x00])),
      );
    });

    test('alignCenter bytes', () {
      expect(
        EscPosGenerator.alignCenter,
        equals(Uint8List.fromList([0x1B, 0x61, 0x01])),
      );
    });

    test('alignRight bytes', () {
      expect(
        EscPosGenerator.alignRight,
        equals(Uint8List.fromList([0x1B, 0x61, 0x02])),
      );
    });

    test('feedLines(n) produces ESC d n', () {
      final result = EscPosGenerator.feedLines(3);
      expect(result, equals(Uint8List.fromList([0x1B, 0x64, 0x03])));
    });

    test('feedLines clamps to 0-255', () {
      final clamped = EscPosGenerator.feedLines(300);
      expect(clamped[2], 255);

      final clampedNeg = EscPosGenerator.feedLines(-5);
      expect(clampedNeg[2], 0);
    });

    test('text() returns ASCII bytes for simple string', () {
      final result = EscPosGenerator.text('Hello');
      expect(
        result,
        equals(Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F])),
      );
    });

    test('textLine() ends with LF', () {
      final result = EscPosGenerator.textLine('Hi');
      expect(result.last, 0x0A);
      // 'H'=0x48, 'i'=0x69, LF=0x0A
      expect(result, equals(Uint8List.fromList([0x48, 0x69, 0x0A])));
    });

    test('separator() returns line of dashes + newline', () {
      final result = EscPosGenerator.separator(width: 5, char: '-');
      // '-----\n'
      final expected = EscPosGenerator.textLine('-----');
      expect(result, equals(expected));
      expect(result.last, 0x0A);
      expect(result.length, 6); // 5 dashes + LF
    });

    test('separator() defaults to 42 dashes', () {
      final result = EscPosGenerator.separator();
      // 42 dashes + LF
      expect(result.length, 43);
      expect(result.last, 0x0A);
    });

    test('buildTicket() starts with init and ends with cutPartial', () {
      final ticket = EscPosGenerator.buildTicket([
        EscPosGenerator.textLine('Test'),
      ]);

      // Starts with init: [0x1B, 0x40]
      expect(ticket[0], 0x1B);
      expect(ticket[1], 0x40);

      // Ends with cutPartial: [0x1D, 0x56, 0x01]
      expect(ticket[ticket.length - 3], 0x1D);
      expect(ticket[ticket.length - 2], 0x56);
      expect(ticket[ticket.length - 1], 0x01);
    });

    test('buildTicket() contains feedLines(4) before cut', () {
      final ticket = EscPosGenerator.buildTicket([]);

      // init(2) + feedLines(4)(3) + cutPartial(3) = 8 bytes
      expect(ticket.length, 8);

      // feedLines(4) = [0x1B, 0x64, 0x04]
      expect(ticket[2], 0x1B);
      expect(ticket[3], 0x64);
      expect(ticket[4], 0x04);
    });
  });
}
