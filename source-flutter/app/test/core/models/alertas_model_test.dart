import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/providers/alertas_provider.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AlertaItem.fromJson
  // ---------------------------------------------------------------------------

  group('AlertaItem.fromJson', () {
    test('parsea alerta completa correctamente', () {
      final json = {
        'id': 'alerta-001',
        'origen_modulo': 'facturacion',
        'codigo_alerta': 'CERT_VENCE_PRONTO',
        'registro_id': 'cert-abc',
        'severidad': 'warning',
        'titulo': 'Certificado SRI vence en 15 días',
        'cuerpo': 'El certificado digital vence el 2026-03-15.',
        'datos': {'dias_restantes': 15},
        'accion_url': '/administracion/sri/certificado',
        'roles_destino': ['ADMIN', 'CONTADOR'],
        'expira_at': '2026-03-15T23:59:59Z',
        'created_at': '2026-02-26T10:00:00Z',
      };

      final a = AlertaItem.fromJson(json);

      expect(a.id, 'alerta-001');
      expect(a.origenModulo, 'facturacion');
      expect(a.codigoAlerta, 'CERT_VENCE_PRONTO');
      expect(a.registroId, 'cert-abc');
      expect(a.severidad, 'warning');
      expect(a.titulo, 'Certificado SRI vence en 15 días');
      expect(a.cuerpo, 'El certificado digital vence el 2026-03-15.');
      expect(a.datos, {'dias_restantes': 15});
      expect(a.accionUrl, '/administracion/sri/certificado');
      expect(a.rolesDestino, ['ADMIN', 'CONTADOR']);
      expect(a.expiraAt, isNotNull);
      expect(a.expiraAt!.year, 2026);
      expect(a.expiraAt!.month, 3);
      expect(a.expiraAt!.day, 15);
      expect(a.creadaAt.year, 2026);
    });

    test('usa defaults para campos opcionales ausentes', () {
      final json = {
        'id': 'alerta-002',
        'titulo': 'Alerta mínima',
        'created_at': '2026-02-26T10:00:00Z',
      };

      final a = AlertaItem.fromJson(json);

      expect(a.origenModulo, 'sistema');
      expect(a.severidad, 'warning');
      expect(a.codigoAlerta, isNull);
      expect(a.registroId, isNull);
      expect(a.cuerpo, isNull);
      expect(a.datos, isEmpty);
      expect(a.accionUrl, isNull);
      expect(a.rolesDestino, isNull);
      expect(a.expiraAt, isNull);
    });

    test('datos vacío cuando el campo está ausente', () {
      final json = {
        'id': 'alerta-003',
        'titulo': 'Test',
        'created_at': '2026-02-26T00:00:00Z',
      };

      final a = AlertaItem.fromJson(json);
      expect(a.datos, isEmpty);
    });

    test('diferentes niveles de severidad', () {
      for (final sev in ['info', 'warning', 'error', 'critical']) {
        final json = {
          'id': 'alerta-$sev',
          'titulo': 'Test $sev',
          'severidad': sev,
          'created_at': '2026-02-26T00:00:00Z',
        };
        final a = AlertaItem.fromJson(json);
        expect(a.severidad, sev);
      }
    });
  });
}
