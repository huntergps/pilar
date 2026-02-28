import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PrintService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // Reset singleton state by reconfiguring with empty list
      PrintService.instance.configure([]);
    });

    test('instance is singleton (same reference)', () {
      final a = PrintService.instance;
      final b = PrintService.instance;

      expect(identical(a, b), isTrue);
    });

    test('configure() sets catalog', () {
      final impresoras = [
        const ImpresoraVirtual(
          id: '1',
          nombre: 'Cocina',
          tipoDoc: TipoDocumento.escpos,
        ),
        const ImpresoraVirtual(
          id: '2',
          nombre: 'Etiquetas',
          tipoDoc: TipoDocumento.zpl,
        ),
      ];

      PrintService.instance.configure(impresoras);

      expect(PrintService.instance.catalogo.length, 2);
      expect(PrintService.instance.catalogo[0].nombre, 'Cocina');
      expect(PrintService.instance.catalogo[1].nombre, 'Etiquetas');
    });

    test('catalogo returns configured printers', () {
      expect(PrintService.instance.catalogo, isEmpty);

      PrintService.instance.configure([
        const ImpresoraVirtual(
          id: '1',
          nombre: 'PDF',
          tipoDoc: TipoDocumento.pdf,
        ),
      ]);

      expect(PrintService.instance.catalogo, hasLength(1));
    });

    test('print() returns error when virtual not found', () async {
      final doc = PrintDocument.escpos(Uint8List.fromList([0x1B, 0x40]));

      final result = await PrintService.instance.print('NoExiste', doc);

      expect(result.isOk, isFalse);
      expect(result.isError, isTrue);
      expect(
        result.errorMessage,
        contains('no encontrada en el catalogo'),
      );
    });

    test('print() returns error when config not found', () async {
      PrintService.instance.configure([
        const ImpresoraVirtual(
          id: '1',
          nombre: 'Cocina',
          tipoDoc: TipoDocumento.escpos,
        ),
      ]);

      final doc = PrintDocument.escpos(Uint8List.fromList([0x1B, 0x40]));
      final result = await PrintService.instance.print('Cocina', doc);

      expect(result.isOk, isFalse);
      expect(result.errorMessage, contains('no configurada'));
    });

    test('saveConfig and loadConfig round-trip', () async {
      final config = ConfiguracionLocal(
        virtualNombre: 'TestPrinter',
        tipoConexion: TipoConexion.tcp,
        ip: '192.168.1.50',
        puerto: 9100,
      );

      await PrintService.instance.saveConfig(config);
      final loaded = await PrintService.instance.loadConfig('TestPrinter');

      expect(loaded, isNotNull);
      expect(loaded!.virtualNombre, 'TestPrinter');
      expect(loaded.tipoConexion, TipoConexion.tcp);
      expect(loaded.ip, '192.168.1.50');
      expect(loaded.puerto, 9100);
    });

    test('deleteConfig removes saved config', () async {
      final config = ConfiguracionLocal(
        virtualNombre: 'Borrar',
        tipoConexion: TipoConexion.sistema,
      );

      await PrintService.instance.saveConfig(config);
      await PrintService.instance.deleteConfig('Borrar');
      final loaded = await PrintService.instance.loadConfig('Borrar');

      expect(loaded, isNull);
    });

    test('loadConfig returns null for non-existent key', () async {
      final loaded = await PrintService.instance.loadConfig('NoExiste');
      expect(loaded, isNull);
    });
  });
}
