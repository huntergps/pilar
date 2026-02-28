import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';

void main() {
  group('TipoDocumento', () {
    test('has escpos, zpl, pdf, escp, texto values', () {
      expect(TipoDocumento.values, containsAll([
        TipoDocumento.escpos,
        TipoDocumento.zpl,
        TipoDocumento.pdf,
        TipoDocumento.escp,
        TipoDocumento.texto,
      ]));
      expect(TipoDocumento.values.length, 5);
    });
  });

  group('ImpresoraVirtual', () {
    test('fromJson with valid data', () {
      final json = {
        'id': 'abc-123',
        'nombre': 'Cocina',
        'tipo_doc': 'escpos',
        'descripcion': 'Impresora de cocina',
      };

      final impresora = ImpresoraVirtual.fromJson(json);

      expect(impresora.id, 'abc-123');
      expect(impresora.nombre, 'Cocina');
      expect(impresora.tipoDoc, TipoDocumento.escpos);
      expect(impresora.descripcion, 'Impresora de cocina');
    });

    test('fromJson with unknown tipo_doc falls back to pdf', () {
      final json = {
        'id': 'xyz-456',
        'nombre': 'Desconocida',
        'tipo_doc': 'thermal_magic',
        'descripcion': null,
      };

      final impresora = ImpresoraVirtual.fromJson(json);

      expect(impresora.tipoDoc, TipoDocumento.pdf);
    });

    test('fromJson with null descripcion', () {
      final json = {
        'id': 'id-1',
        'nombre': 'Etiquetas',
        'tipo_doc': 'zpl',
      };

      final impresora = ImpresoraVirtual.fromJson(json);

      expect(impresora.descripcion, isNull);
      expect(impresora.tipoDoc, TipoDocumento.zpl);
    });

    test('toJson round-trip', () {
      final original = ImpresoraVirtual(
        id: 'round-trip',
        nombre: 'Ticket',
        tipoDoc: TipoDocumento.escpos,
        descripcion: 'Impresora POS',
      );

      final json = original.toJson();
      final restored = ImpresoraVirtual.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.nombre, original.nombre);
      expect(restored.tipoDoc, original.tipoDoc);
      expect(restored.descripcion, original.descripcion);
    });

    test('toJson produces correct keys', () {
      final impresora = ImpresoraVirtual(
        id: 'id-1',
        nombre: 'Test',
        tipoDoc: TipoDocumento.pdf,
      );

      final json = impresora.toJson();

      expect(json['id'], 'id-1');
      expect(json['nombre'], 'Test');
      expect(json['tipo_doc'], 'pdf');
      expect(json['descripcion'], isNull);
    });
  });
}
