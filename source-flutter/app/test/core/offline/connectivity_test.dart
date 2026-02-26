import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pilar_erp/core/offline/connectivity_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // isOfflineError
  // ---------------------------------------------------------------------------

  group('isOfflineError', () {
    test('detecta SocketException', () {
      expect(
        isOfflineError(Exception('SocketException: Failed to connect')),
        isTrue,
      );
    });

    test('detecta connection refused', () {
      expect(
        isOfflineError(Exception('connection refused to host')),
        isTrue,
      );
    });

    test('detecta failed host lookup', () {
      expect(
        isOfflineError(Exception('failed host lookup: supabase.co')),
        isTrue,
      );
    });

    test('detecta network is unreachable', () {
      expect(
        isOfflineError(Exception('network is unreachable')),
        isTrue,
      );
    });

    test('detecta connection timed out', () {
      expect(
        isOfflineError(Exception('connection timed out after 30s')),
        isTrue,
      );
    });

    test('detecta ClientException', () {
      expect(
        isOfflineError(Exception('ClientException: Connection closed')),
        isTrue,
      );
    });

    test('detecta connection reset', () {
      expect(
        isOfflineError(Exception('connection reset by peer')),
        isTrue,
      );
    });

    test('detecta HandshakeException', () {
      expect(
        isOfflineError(Exception('HandshakeException: Handshake error')),
        isTrue,
      );
    });

    test('no es offline error: 401 Unauthorized', () {
      expect(
        isOfflineError(Exception('HTTP 401 Unauthorized')),
        isFalse,
      );
    });

    test('no es offline error: permiso denegado (42501)', () {
      expect(
        isOfflineError(Exception('permission denied for table modulos')),
        isFalse,
      );
    });

    test('no es offline error: error de formato JSON', () {
      expect(
        isOfflineError(Exception('FormatException: Unexpected character')),
        isFalse,
      );
    });

    test('no es offline error: string vacío', () {
      expect(isOfflineError(Exception('')), isFalse);
    });

    test('es case-insensitive (detecta SOCKETEXCEPTION en mayúsculas)', () {
      expect(
        isOfflineError(Exception('SOCKETEXCEPTION: error')),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ConnectivityNotifier — máquina de estados
  // ---------------------------------------------------------------------------

  group('ConnectivityNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('inicia en estado online (true)', () {
      // En test (no-web) build() retorna true e inicia el timer de sondeo.
      // El timer se cancela en tearDown al llamar container.dispose().
      expect(container.read(connectivityProvider), isTrue);
    });

    test('reportOffline() cambia estado a false', () {
      container.read(connectivityProvider.notifier).reportOffline();
      expect(container.read(connectivityProvider), isFalse);
    });

    test('reportOnline() restaura estado a true', () {
      container.read(connectivityProvider.notifier).reportOffline();
      expect(container.read(connectivityProvider), isFalse);

      container.read(connectivityProvider.notifier).reportOnline();
      expect(container.read(connectivityProvider), isTrue);
    });

    test('reportOnline() es idempotente cuando ya está online', () {
      expect(container.read(connectivityProvider), isTrue);
      container.read(connectivityProvider.notifier).reportOnline();
      expect(container.read(connectivityProvider), isTrue);
    });

    test('reportOffline() es idempotente cuando ya está offline', () {
      container.read(connectivityProvider.notifier).reportOffline();
      expect(container.read(connectivityProvider), isFalse);

      container.read(connectivityProvider.notifier).reportOffline();
      expect(container.read(connectivityProvider), isFalse);
    });

    test('transiciones offline → online → offline', () {
      final notifier = container.read(connectivityProvider.notifier);

      notifier.reportOffline();
      expect(container.read(connectivityProvider), isFalse);

      notifier.reportOnline();
      expect(container.read(connectivityProvider), isTrue);

      notifier.reportOffline();
      expect(container.read(connectivityProvider), isFalse);
    });
  });
}
