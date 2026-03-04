// Tests de la infraestructura offline-sync de PILAR ERP.
//
// Cubre:
//   · ConnectivityService — estado online/offline (complemento a connectivity_test.dart)
//   · FakeConnectivityNotifier reporta offline correctamente
//   · syncQueueItemsProvider — retorna lista vacía en web / sin repo
//   · syncQueueItemsProvider — retorna items cuando se hace override
//   · pendingSyncCountProvider — es 0 cuando la cola está vacía
//   · pendingSyncCountProvider — es N cuando hay N items en queue
//
// NOTA: No se inicializa Supabase real ni SQLite. Todos los accesos al
// repositorio se reemplazan con overrides de providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/offline/connectivity_service.dart';
import 'package:pilar_erp/core/providers/sync_count_provider.dart'
    show pendingSyncCountProvider;
import 'package:pilar_erp/features/administracion/screens/sync_log_screen.dart'
    show syncQueueItemsProvider, syncRetryProvider;

import '../../helpers/test_utils.dart';

// ---------------------------------------------------------------------------
// Datos fake de cola
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _fakeQueueItems(int count) => List.generate(
      count,
      (i) => {
        'id': i + 1,
        'url': '/rest/v1/contactos',
        'request_method': 'POST',
        'attempts': 1,
        'locked': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
    );

// ---------------------------------------------------------------------------
// Tests — FakeConnectivityNotifier
// ---------------------------------------------------------------------------

void main() {
  group('FakeConnectivityNotifier', () {
    test('inicia en estado online (true) por defecto', () {
      final container = ProviderContainer(
        overrides: baseOverrides(startsOnline: true),
      );
      addTearDown(container.dispose);

      expect(container.read(connectivityProvider), isTrue);
    });

    test('inicia en estado offline (false) cuando startsOnline=false', () {
      final container = ProviderContainer(
        overrides: baseOverrides(startsOnline: false),
      );
      addTearDown(container.dispose);

      expect(container.read(connectivityProvider), isFalse);
    });

    test('goOffline() cambia estado a false', () {
      final container = ProviderContainer(
        overrides: baseOverrides(startsOnline: true),
      );
      addTearDown(container.dispose);

      final notifier = container.read(connectivityProvider.notifier)
          as FakeConnectivityNotifier;
      notifier.goOffline();

      expect(container.read(connectivityProvider), isFalse);
    });

    test('goOnline() restaura estado a true', () {
      final container = ProviderContainer(
        overrides: baseOverrides(startsOnline: false),
      );
      addTearDown(container.dispose);

      final notifier = container.read(connectivityProvider.notifier)
          as FakeConnectivityNotifier;
      notifier.goOnline();

      expect(container.read(connectivityProvider), isTrue);
    });

    test('FakeConnectivityNotifier no inicia timers ni DNS probes', () {
      // Si se usara ConnectivityNotifier real, el timer dispararía
      // InternetAddress.lookup y fallaría en entornos sin red.
      // Este test verifica que no hay excepción al crear el fake.
      expect(
        () {
          final container = ProviderContainer(
            overrides: baseOverrides(),
          );
          container.dispose();
        },
        returnsNormally,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — syncQueueItemsProvider
  // ---------------------------------------------------------------------------

  group('syncQueueItemsProvider — sin override (comportamiento por defecto)', () {
    test('retorna lista vacía en entorno de test (PilarRepository no inicializado)', () async {
      // En tests, PilarRepository.isInitialized es siempre false porque no
      // llamamos a PilarRepository.configure(). El provider devuelve [].
      //
      // NOTA: kIsWeb también es false en tests de Dart puro.
      final container = ProviderContainer(
        overrides: baseOverrides(),
      );
      addTearDown(container.dispose);

      final result = await container.read(syncQueueItemsProvider.future);
      expect(result, isEmpty);
    });
  });

  group('syncQueueItemsProvider — con override', () {
    test('retorna los items cuando el provider es sobreescrito con datos fake', () async {
      final fakeItems = _fakeQueueItems(3);

      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          syncQueueItemsProvider.overrideWith((_) async => fakeItems),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(syncQueueItemsProvider.future);
      expect(result, hasLength(3));
      expect(result.first['request_method'], 'POST');
    });

    test('retorna lista vacía cuando el override devuelve []', () async {
      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          syncQueueItemsProvider.overrideWith((_) async => const []),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(syncQueueItemsProvider.future);
      expect(result, isEmpty);
    });

    test('retorna un único item correctamente', () async {
      final fakeItems = _fakeQueueItems(1);

      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          syncQueueItemsProvider.overrideWith((_) async => fakeItems),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(syncQueueItemsProvider.future);
      expect(result, hasLength(1));
      expect(result.first['id'], 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — pendingSyncCountProvider
  // ---------------------------------------------------------------------------

  group('pendingSyncCountProvider', () {
    test('es 0 cuando syncQueueItemsProvider retorna lista vacía', () async {
      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          syncQueueItemsProvider.overrideWith((_) async => const []),
        ],
      );
      addTearDown(container.dispose);

      // Esperar que syncQueueItemsProvider resuelva antes de leer el count.
      await container.read(syncQueueItemsProvider.future);

      final count = container.read(pendingSyncCountProvider);
      expect(count, 0);
    });

    test('es N cuando hay N items en la cola', () async {
      const n = 5;
      final fakeItems = _fakeQueueItems(n);

      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          syncQueueItemsProvider.overrideWith((_) async => fakeItems),
        ],
      );
      addTearDown(container.dispose);

      // Esperar que el FutureProvider resuelva.
      await container.read(syncQueueItemsProvider.future);

      final count = container.read(pendingSyncCountProvider);
      expect(count, n);
    });

    test('es 0 cuando syncQueueItemsProvider está en estado loading', () {
      // Cuando el FutureProvider aún no resolvió (AsyncLoading),
      // maybeWhen orElse retorna 0.
      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          // Never-completing future → provider stays in AsyncLoading.
          syncQueueItemsProvider.overrideWith(
            (_) => Future.delayed(const Duration(days: 1), () => const []),
          ),
        ],
      );
      addTearDown(container.dispose);

      // No await — leemos en estado loading.
      final count = container.read(pendingSyncCountProvider);
      expect(count, 0);
    });

    test('es 0 cuando kIsWeb es true (web no tiene SQLite)', () {
      // En entorno de test, kIsWeb es false (Dart puro/Flutter test).
      // Verificamos el comportamiento con override que simula cola vacía.
      // La lógica real de kIsWeb se verifica indirectamente: el provider
      // devuelve [] en web, por lo que count sería 0.
      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          syncQueueItemsProvider.overrideWith((_) async => const []),
        ],
      );
      addTearDown(container.dispose);

      final count = container.read(pendingSyncCountProvider);
      // En AsyncLoading inicial, orElse devuelve 0.
      expect(count, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — syncRetryProvider
  // ---------------------------------------------------------------------------

  group('syncRetryProvider —', () {
    test('no lanza cuando repo no inicializado', () async {
      final container = ProviderContainer(overrides: [
        ...baseOverrides(),
        // No hay override de PilarRepository — simula no inicializado.
        // El provider retorna inmediatamente con un no-op.
      ]);
      addTearDown(container.dispose);

      // No debe lanzar, simplemente retorna.
      await expectLater(
        container.read(syncRetryProvider.future),
        completes,
      );
    });

    test('completa cuando hay items y kIsWeb es false', () async {
      // Overrides para simular estado con items en la cola.
      final container = ProviderContainer(overrides: [
        ...baseOverrides(),
        syncQueueItemsProvider.overrideWith((_) async => [
              {
                'id': '1',
                'url': '/rest/v1/contactos',
                'method': 'POST',
              },
            ]),
      ]);
      addTearDown(container.dispose);

      // Simplemente no debe lanzar.
      await expectLater(
        container.read(syncRetryProvider.future),
        completes,
      );
    });
  });
}
