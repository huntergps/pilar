import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';

void main() {
  group('TipoConexion', () {
    test('has tcp, bluetooth, gateway, sistema values', () {
      expect(TipoConexion.values, containsAll([
        TipoConexion.tcp,
        TipoConexion.bluetooth,
        TipoConexion.gateway,
        TipoConexion.sistema,
      ]));
      expect(TipoConexion.values.length, 4);
    });
  });

  group('ConfiguracionLocal', () {
    test('fromJson with TCP config', () {
      final json = {
        'virtual_nombre': 'Cocina',
        'tipo_conexion': 'tcp',
        'ip': '192.168.1.100',
        'puerto': 9100,
      };

      final config = ConfiguracionLocal.fromJson(json);

      expect(config.virtualNombre, 'Cocina');
      expect(config.tipoConexion, TipoConexion.tcp);
      expect(config.ip, '192.168.1.100');
      expect(config.puerto, 9100);
      expect(config.btAddress, isNull);
      expect(config.printerName, isNull);
    });

    test('fromJson with Bluetooth config', () {
      final json = {
        'virtual_nombre': 'Portatil',
        'tipo_conexion': 'bluetooth',
        'bt_address': 'AA:BB:CC:DD:EE:FF',
      };

      final config = ConfiguracionLocal.fromJson(json);

      expect(config.tipoConexion, TipoConexion.bluetooth);
      expect(config.btAddress, 'AA:BB:CC:DD:EE:FF');
      expect(config.ip, isNull);
      expect(config.puerto, isNull);
    });

    test('fromJson migrates legacy qztray → gateway', () {
      final json = {
        'virtual_nombre': 'WebPOS',
        'tipo_conexion': 'qztray',
        'qz_printer_name': 'EPSON TM-T20III',
      };

      final config = ConfiguracionLocal.fromJson(json);

      // Legacy 'qztray' is migrated to 'gateway'
      expect(config.tipoConexion, TipoConexion.gateway);
      // Legacy 'qz_printer_name' is migrated to printerName
      expect(config.printerName, 'EPSON TM-T20III');
    });

    test('fromJson with gateway config (ws:// QZ Tray)', () {
      final json = {
        'virtual_nombre': 'WebPOS',
        'tipo_conexion': 'gateway',
        'gateway_url': 'ws://localhost:8182',
        'printer_name': 'EPSON TM-T20III',
      };

      final config = ConfiguracionLocal.fromJson(json);

      expect(config.tipoConexion, TipoConexion.gateway);
      expect(config.gatewayUrl, 'ws://localhost:8182');
      expect(config.printerName, 'EPSON TM-T20III');
    });

    test('fromJson with gateway config (http:// custom server)', () {
      final json = {
        'virtual_nombre': 'PrintServer',
        'tipo_conexion': 'gateway',
        'gateway_url': 'http://192.168.1.50:3000/print',
        'printer_name': 'HP LaserJet',
      };

      final config = ConfiguracionLocal.fromJson(json);

      expect(config.tipoConexion, TipoConexion.gateway);
      expect(config.gatewayUrl, 'http://192.168.1.50:3000/print');
      expect(config.printerName, 'HP LaserJet');
    });

    test('fromJson migrates legacy pdf → sistema', () {
      final json = {
        'virtual_nombre': 'PDF',
        'tipo_conexion': 'pdf',
      };

      final config = ConfiguracionLocal.fromJson(json);

      // Legacy 'pdf' is migrated to 'sistema'
      expect(config.tipoConexion, TipoConexion.sistema);
    });

    test('fromJson with sistema config', () {
      final json = {
        'virtual_nombre': 'Factura',
        'tipo_conexion': 'sistema',
        'printer_name': 'HP Color LaserJet Pro M454',
      };

      final config = ConfiguracionLocal.fromJson(json);

      expect(config.tipoConexion, TipoConexion.sistema);
      expect(config.printerName, 'HP Color LaserJet Pro M454');
    });

    test('fromJson with unknown tipo_conexion falls back to sistema', () {
      final json = {
        'virtual_nombre': 'X',
        'tipo_conexion': 'serial_port',
      };

      final config = ConfiguracionLocal.fromJson(json);

      expect(config.tipoConexion, TipoConexion.sistema);
    });

    test('toJson round-trip for TCP', () {
      final original = ConfiguracionLocal(
        virtualNombre: 'Cocina',
        tipoConexion: TipoConexion.tcp,
        ip: '10.0.0.50',
        puerto: 9100,
      );

      final json = original.toJson();
      final restored = ConfiguracionLocal.fromJson(json);

      expect(restored.virtualNombre, original.virtualNombre);
      expect(restored.tipoConexion, original.tipoConexion);
      expect(restored.ip, original.ip);
      expect(restored.puerto, original.puerto);
      expect(restored.btAddress, original.btAddress);
      expect(restored.printerName, original.printerName);
    });

    test('toJson round-trip for gateway', () {
      final original = ConfiguracionLocal(
        virtualNombre: 'WPOS',
        tipoConexion: TipoConexion.gateway,
        gatewayUrl: 'ws://localhost:8182',
        printerName: 'EPSON TM-T20III',
      );

      final json = original.toJson();
      final restored = ConfiguracionLocal.fromJson(json);

      expect(restored.tipoConexion, TipoConexion.gateway);
      expect(restored.gatewayUrl, 'ws://localhost:8182');
      expect(restored.printerName, 'EPSON TM-T20III');
    });

    test('toJson round-trip for sistema', () {
      final original = ConfiguracionLocal(
        virtualNombre: 'A4',
        tipoConexion: TipoConexion.sistema,
        printerName: 'HP LaserJet',
      );

      final json = original.toJson();
      final restored = ConfiguracionLocal.fromJson(json);

      expect(restored.tipoConexion, TipoConexion.sistema);
      expect(restored.printerName, 'HP LaserJet');
    });

    test('all nullable fields are null when not provided', () {
      final config = ConfiguracionLocal(
        virtualNombre: 'Minimal',
        tipoConexion: TipoConexion.sistema,
      );

      expect(config.ip, isNull);
      expect(config.puerto, isNull);
      expect(config.btAddress, isNull);
      expect(config.gatewayUrl, isNull);
      expect(config.printerName, isNull);
    });
  });
}
