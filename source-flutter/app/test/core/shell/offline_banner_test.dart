// UC-03: Banner offline
// Verifica que OfflineStatusBar se muestra solo cuando no hay conexión.

import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/offline/connectivity_service.dart';
import 'package:pilar_erp/core/offline/offline_banner.dart';

import '../../helpers/test_utils.dart';

void main() {
  group('UC-03 — OfflineStatusBar', () {
    testWidgets(
        'UC-03a: Cuando ONLINE → no renderiza el banner (SizedBox.shrink)',
        (tester) async {
      await tester.pumpWidget(
        buildFluentApp(
          const OfflineStatusBar(),
          startsOnline: true, // connectivityProvider = true
        ),
      );

      expect(find.text('Sin conexión · Mostrando datos guardados'),
          findsNothing);
      expect(find.byType(OfflineStatusBar), findsOneWidget); // widget existe
    });

    testWidgets('UC-03b: Cuando OFFLINE → muestra banner con texto correcto',
        (tester) async {
      await tester.pumpWidget(
        buildFluentApp(
          const OfflineStatusBar(),
          startsOnline: false, // connectivityProvider = false
        ),
      );

      expect(find.text('Sin conexión · Mostrando datos guardados'),
          findsOneWidget);
    });

    testWidgets(
        'UC-03c: Transición online → offline → banner aparece dinámicamente',
        (tester) async {
      late FakeConnectivityNotifier fakeConn;

      await tester.pumpWidget(
        buildFluentApp(
          const OfflineStatusBar(),
          overrides: [
            connectivityProvider.overrideWith(() {
              fakeConn = FakeConnectivityNotifier(true);
              return fakeConn;
            }),
          ],
        ),
      );

      // Online: sin banner
      await tester.pump();
      expect(find.text('Sin conexión · Mostrando datos guardados'),
          findsNothing);

      // Se va el internet
      fakeConn.goOffline();
      await tester.pump();

      expect(find.text('Sin conexión · Mostrando datos guardados'),
          findsOneWidget);
    });

    testWidgets(
        'UC-03d: Transición offline → online → banner desaparece',
        (tester) async {
      late FakeConnectivityNotifier fakeConn;

      await tester.pumpWidget(
        buildFluentApp(
          const OfflineStatusBar(),
          overrides: [
            connectivityProvider.overrideWith(() {
              fakeConn = FakeConnectivityNotifier(false);
              return fakeConn;
            }),
          ],
        ),
      );

      // Offline: banner visible
      await tester.pump();
      expect(find.text('Sin conexión · Mostrando datos guardados'),
          findsOneWidget);

      // Vuelve la conexión
      fakeConn.goOnline();
      await tester.pump();

      expect(find.text('Sin conexión · Mostrando datos guardados'),
          findsNothing);
    });
  });
}
