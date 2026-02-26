import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/features/notificaciones/providers/notificaciones_provider.dart';

void main() {
  // ---------------------------------------------------------------------------
  // NotificacionItem.fromJson
  // ---------------------------------------------------------------------------

  group('NotificacionItem.fromJson', () {
    test('parsea notificación completa correctamente', () {
      final json = {
        'id': 'notif-001',
        'tipo': 'alerta_sri',
        'titulo': 'Factura autorizada',
        'cuerpo': 'La factura #001-001-000000123 fue autorizada por el SRI.',
        'leida': false,
        'created_at': '2026-02-26T10:15:00Z',
        'icono': 'document_checkmark',
        'accion_url': '/facturacion/facturas/fact-001',
      };

      final n = NotificacionItem.fromJson(json);

      expect(n.id, 'notif-001');
      expect(n.tipo, 'alerta_sri');
      expect(n.titulo, 'Factura autorizada');
      expect(n.cuerpo, 'La factura #001-001-000000123 fue autorizada por el SRI.');
      expect(n.leida, isFalse);
      expect(n.creadaAt.year, 2026);
      expect(n.creadaAt.month, 2);
      expect(n.creadaAt.day, 26);
      expect(n.icono, 'document_checkmark');
      expect(n.accionUrl, '/facturacion/facturas/fact-001');
    });

    test('usa defaults para campos opcionales', () {
      final json = {
        'id': 'notif-002',
        'titulo': 'Notificación mínima',
        'created_at': '2026-02-26T00:00:00Z',
      };

      final n = NotificacionItem.fromJson(json);

      expect(n.tipo, 'sistema');
      expect(n.leida, isFalse);
      expect(n.cuerpo, isNull);
      expect(n.icono, isNull);
      expect(n.accionUrl, isNull);
    });

    test('parsea notificación ya leída', () {
      final json = {
        'id': 'notif-003',
        'titulo': 'Notificación leída',
        'leida': true,
        'created_at': '2026-01-10T08:00:00Z',
      };

      final n = NotificacionItem.fromJson(json);
      expect(n.leida, isTrue);
    });

    test('creadaAt parsea correctamente zona UTC', () {
      final json = {
        'id': 'notif-004',
        'titulo': 'Test fecha',
        'created_at': '2026-02-26T15:30:45.123Z',
      };

      final n = NotificacionItem.fromJson(json);
      expect(n.creadaAt.isUtc, isTrue);
      expect(n.creadaAt.hour, 15);
      expect(n.creadaAt.minute, 30);
      expect(n.creadaAt.second, 45);
    });

    test('diferentes tipos de notificación', () {
      for (final tipo in ['alerta_sri', 'usuario_invitado', 'modulo_activado', 'sistema']) {
        final json = {
          'id': 'notif-$tipo',
          'tipo': tipo,
          'titulo': 'Test $tipo',
          'created_at': '2026-02-26T00:00:00Z',
        };
        final n = NotificacionItem.fromJson(json);
        expect(n.tipo, tipo);
      }
    });
  });
}
