import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/providers/empresa_provider.dart';

void main() {
  // ---------------------------------------------------------------------------
  // EmpresaResumen
  // ---------------------------------------------------------------------------

  group('EmpresaResumen.fromJson', () {
    test('parsea todos los campos correctamente', () {
      final json = {
        'empresa_id': 'e1-abc',
        'nombre': 'Ferretería El Clavo',
        'ruc': '1234567890001',
        'logo_url': 'https://cdn.example.com/logo.png',
        'rol_codigo': 'ADMIN',
        'rol_nombre': 'Administrador',
        'es_activa': true,
      };

      final e = EmpresaResumen.fromJson(json);

      expect(e.empresaId, 'e1-abc');
      expect(e.nombre, 'Ferretería El Clavo');
      expect(e.ruc, '1234567890001');
      expect(e.logoUrl, 'https://cdn.example.com/logo.png');
      expect(e.rolCodigo, 'ADMIN');
      expect(e.rolNombre, 'Administrador');
      expect(e.esActiva, isTrue);
    });

    test('usa defaults cuando faltan campos opcionales', () {
      final json = {
        'empresa_id': 'e2-def',
        'nombre': 'Solo Nombre',
      };

      final e = EmpresaResumen.fromJson(json);

      expect(e.ruc, isNull);
      expect(e.logoUrl, isNull);
      expect(e.rolCodigo, 'LECTURA');
      expect(e.rolNombre, 'Lectura');
      expect(e.esActiva, isTrue);
    });

    test('empresa inactiva se parsea correctamente', () {
      final json = {
        'empresa_id': 'e3-ghi',
        'nombre': 'Empresa Cerrada',
        'es_activa': false,
      };

      final e = EmpresaResumen.fromJson(json);
      expect(e.esActiva, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // EmpresaConfig
  // ---------------------------------------------------------------------------

  group('EmpresaConfig.fromJson', () {
    test('parsea config completa con todos los campos', () {
      final json = {
        'empresa_id': 'e1-abc',
        'nombre': 'Ferretería El Clavo',
        'nombre_comercial': 'ElClavo',
        'ruc': '1234567890001',
        'tipo_ruc': 'RUC',
        'provincia_id': 1,
        'ciudad_id': 101,
        'direccion': 'Av. Patria 123',
        'telefono': '0999000111',
        'email': 'info@elclavo.com',
        'web': 'https://elclavo.com',
        'logo_url': 'https://cdn.example.com/logo.png',
        'color_primario': '#0078D4',
        'color_secundario': '#005A9E',
        'login_titulo': 'Bienvenido a ElClavo',
        'moneda_funcional': 'USD',
        'color_forzado_en': '2026-01-15T10:30:00.000Z',
      };

      final c = EmpresaConfig.fromJson(json);

      expect(c.empresaId, 'e1-abc');
      expect(c.nombre, 'Ferretería El Clavo');
      expect(c.nombreComercial, 'ElClavo');
      expect(c.ruc, '1234567890001');
      expect(c.tipoRuc, 'RUC');
      expect(c.provinciaId, 1);
      expect(c.ciudadId, 101);
      expect(c.direccion, 'Av. Patria 123');
      expect(c.telefono, '0999000111');
      expect(c.email, 'info@elclavo.com');
      expect(c.web, 'https://elclavo.com');
      expect(c.logoUrl, 'https://cdn.example.com/logo.png');
      expect(c.colorPrimario, '#0078D4');
      expect(c.colorSecundario, '#005A9E');
      expect(c.loginTitulo, 'Bienvenido a ElClavo');
      expect(c.monedaFuncional, 'USD');
      expect(c.colorForzadoEn, isNotNull);
      expect(c.colorForzadoEn!.year, 2026);
      expect(c.colorForzadoEn!.month, 1);
      expect(c.colorForzadoEn!.day, 15);
    });

    test('usa USD como moneda funcional por defecto', () {
      final json = {
        'empresa_id': 'e1-abc',
        'nombre': 'Empresa Mínima',
      };

      final c = EmpresaConfig.fromJson(json);

      expect(c.monedaFuncional, 'USD');
    });

    test('colorForzadoEn es null cuando no está en JSON', () {
      final json = {
        'empresa_id': 'e1-abc',
        'nombre': 'Sin color forzado',
      };

      final c = EmpresaConfig.fromJson(json);
      expect(c.colorForzadoEn, isNull);
    });

    test('colorForzadoEn es null cuando el valor es null explícito', () {
      final json = {
        'empresa_id': 'e1-abc',
        'nombre': 'Empresa',
        'color_forzado_en': null,
      };

      final c = EmpresaConfig.fromJson(json);
      expect(c.colorForzadoEn, isNull);
    });

    test('parsea fecha con formato ISO 8601 sin milisegundos', () {
      final json = {
        'empresa_id': 'e1-abc',
        'nombre': 'Empresa',
        'color_forzado_en': '2026-02-26T00:00:00Z',
      };

      final c = EmpresaConfig.fromJson(json);
      expect(c.colorForzadoEn, isNotNull);
      expect(c.colorForzadoEn!.year, 2026);
    });

    test('campos opcionales son null por defecto', () {
      final json = {
        'empresa_id': 'e1-abc',
        'nombre': 'Empresa Mínima',
      };

      final c = EmpresaConfig.fromJson(json);

      expect(c.nombreComercial, isNull);
      expect(c.ruc, isNull);
      expect(c.tipoRuc, isNull);
      expect(c.provinciaId, isNull);
      expect(c.ciudadId, isNull);
      expect(c.direccion, isNull);
      expect(c.telefono, isNull);
      expect(c.email, isNull);
      expect(c.web, isNull);
      expect(c.logoUrl, isNull);
      expect(c.colorPrimario, isNull);
      expect(c.colorSecundario, isNull);
      expect(c.loginTitulo, isNull);
    });
  });
}
