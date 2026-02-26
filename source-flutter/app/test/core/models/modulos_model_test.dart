import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/providers/modulos_provider.dart';

void main() {
  // ---------------------------------------------------------------------------
  // ModuloItem.fromJson
  // ---------------------------------------------------------------------------

  group('ModuloItem.fromJson', () {
    test('parsea todos los campos correctamente', () {
      final json = {
        'id': 'mod-facturacion',
        'nombre': 'Facturación',
        'icono': 'document',
        'orden': 3,
        'tipo': 'core',
      };

      final m = ModuloItem.fromJson(json);

      expect(m.id, 'mod-facturacion');
      expect(m.nombre, 'Facturación');
      expect(m.icono, 'document');
      expect(m.orden, 3);
      expect(m.tipo, 'core');
    });

    test('usa defaults para campos opcionales', () {
      final json = {
        'id': 'mod-test',
        'nombre': 'Test',
      };

      final m = ModuloItem.fromJson(json);

      expect(m.icono, 'apps');
      expect(m.orden, 99);
      expect(m.tipo, 'core');
    });

    test('respeta orden 0 (infraestructura)', () {
      final json = {
        'id': 'mod-dashboard',
        'nombre': 'Dashboard',
        'icono': 'home',
        'orden': 0,
        'tipo': 'infraestructura',
      };

      final m = ModuloItem.fromJson(json);
      expect(m.orden, 0);
      expect(m.tipo, 'infraestructura');
    });
  });

  // ---------------------------------------------------------------------------
  // ModuloEstado.fromJson
  // ---------------------------------------------------------------------------

  group('ModuloEstado.fromJson', () {
    test('parsea módulo habilitado correctamente', () {
      final json = {
        'id': 'mod-ventas',
        'nombre': 'Ventas',
        'icono': 'cart',
        'orden': 2,
        'tipo': 'core',
        'habilitado': true,
      };

      final m = ModuloEstado.fromJson(json);

      expect(m.id, 'mod-ventas');
      expect(m.nombre, 'Ventas');
      expect(m.habilitado, isTrue);
    });

    test('parsea módulo deshabilitado correctamente', () {
      final json = {
        'id': 'mod-citas',
        'nombre': 'Citas y Belleza',
        'icono': 'cut',
        'orden': 10,
        'tipo': 'extension',
        'habilitado': false,
      };

      final m = ModuloEstado.fromJson(json);
      expect(m.habilitado, isFalse);
    });

    test('habilitado es false por defecto', () {
      final json = {
        'id': 'mod-nuevo',
        'nombre': 'Nuevo',
      };

      final m = ModuloEstado.fromJson(json);
      expect(m.habilitado, isFalse);
    });
  });
}
