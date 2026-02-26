// UC-02 + UC-05: Dashboard principal
// Verifica que el dashboard renderiza la card de empresa y los módulos
// activos correctamente. También verifica el estado vacío (sin módulos).

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/providers/empresa_provider.dart';
import 'package:pilar_erp/core/providers/modulos_provider.dart';
import 'package:pilar_erp/core/providers/usuario_provider.dart';
import 'package:pilar_erp/features/dashboard/screens/dashboard_screen.dart';

import '../../helpers/test_utils.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget buildDashboardApp({
  List<ModuloItem> modulos = const [],
  EmpresaConfig? empresa,
  bool hasAdminPerm = false,
}) {
  final config = empresa ?? fakeEmpresaConfig();

  return buildFluentApp(
    const DashboardScreen(),
    overrides: [
      modulosActivosProvider.overrideWith(
        (ref) => Stream.value(modulos),
      ),
      empresaConfigProvider.overrideWith(
        (ref) => Stream.value(config),
      ),
      hasPermissionProvider.overrideWith(
        (ref, _) => hasAdminPerm,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UC-02 + UC-05 — DashboardScreen', () {
    testWidgets(
        'UC-02a: Sin módulos activos → dashboard renderiza sin crash',
        (tester) async {
      await tester.pumpWidget(buildDashboardApp(modulos: []));

      await tester.pump();
      await tester.pump();

      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets(
        'UC-02b: Módulo "administracion" con permiso → tile visible en launcher',
        (tester) async {
      // Solo 'administracion' tiene ruta definida actualmente.
      // Los demás módulos son filtrados por ModuleLauncherGrid.
      final modulos = [
        fakeModulo(id: 'administracion', nombre: 'Administración', orden: 0),
      ];

      await tester.pumpWidget(
        buildDashboardApp(modulos: modulos, hasAdminPerm: true),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Administración'), findsOneWidget);
    });

    testWidgets(
        'UC-05a: EmpresaCard muestra nombre comercial si está definido',
        (tester) async {
      final config = fakeEmpresaConfig(
        nombre: 'Ferretería El Clavo S.A.',
        nombreComercial: 'ElClavo',
      );

      await tester.pumpWidget(buildDashboardApp(empresa: config));

      await tester.pump();
      await tester.pump();

      expect(find.text('ElClavo'), findsOneWidget);
    });

    testWidgets(
        'UC-05b: EmpresaCard muestra nombre legal cuando no hay comercial',
        (tester) async {
      final config = fakeEmpresaConfig(nombre: 'Empresa Sin Nombre Comercial');

      await tester.pumpWidget(buildDashboardApp(empresa: config));

      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('Empresa Sin Nombre Comercial'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets(
        'UC-04a: Dashboard con módulo admin + permiso → tile "Administración" visible',
        (tester) async {
      // La grid solo muestra el tile si el módulo está en la lista Y hay permiso.
      final modulos = [
        fakeModulo(id: 'administracion', nombre: 'Administración', orden: 0),
      ];
      await tester.pumpWidget(
        buildDashboardApp(modulos: modulos, hasAdminPerm: true),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Administración'), findsOneWidget);
    });

    testWidgets(
        'UC-04b: Dashboard con módulo admin pero SIN permiso → tile no visible',
        (tester) async {
      final modulos = [
        fakeModulo(id: 'administracion', nombre: 'Administración', orden: 0),
      ];
      await tester.pumpWidget(
        buildDashboardApp(modulos: modulos, hasAdminPerm: false),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Administración'), findsNothing);
    });

    testWidgets(
        'UC-02c: Módulos sin ruta → launcher muestra "No hay módulos disponibles"',
        (tester) async {
      // Módulos que todavía no tienen ruta en _routeForModulo son filtrados.
      final modulos = [
        fakeModulo(id: 'facturacion', nombre: 'Facturación', orden: 1),
        fakeModulo(id: 'ventas', nombre: 'Ventas', orden: 2),
      ];

      await tester.pumpWidget(buildDashboardApp(modulos: modulos));

      await tester.pump();
      await tester.pump();

      expect(find.text('No hay módulos disponibles'), findsOneWidget);
    });

    testWidgets(
        'UC-03b: Dashboard OFFLINE → OfflineStatusBar NO visible '
        '(está en PilarShell, no en la pantalla directa)',
        (tester) async {
      // DashboardScreen no incluye OfflineStatusBar directamente;
      // ese widget vive en PilarShell. Verificamos que la pantalla
      // renderiza bien incluso cuando la conectividad es false.
      await tester.pumpWidget(
        buildFluentApp(
          const DashboardScreen(),
          startsOnline: false,
          overrides: [
            modulosActivosProvider.overrideWith((ref) => Stream.value([])),
            empresaConfigProvider
                .overrideWith((ref) => Stream.value(fakeEmpresaConfig())),
            hasPermissionProvider.overrideWith((ref, _) => false),
          ],
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });
}
