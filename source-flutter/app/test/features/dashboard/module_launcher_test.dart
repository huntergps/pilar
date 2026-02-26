// UC-02 + UC-04: Module Launcher Grid
//
// COMPORTAMIENTO REAL del widget (confirmado leyendo el código):
// - Solo renderiza tiles de módulos que tienen ruta definida en _routeForModulo.
// - Actualmente solo 'administracion' tiene ruta → PilarRoutes.adminEmpresa.
// - Si ningún módulo es navegable → muestra "No hay módulos disponibles".
// - El tile 'administracion' también requiere hasPermissionProvider = true.

import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/providers/usuario_provider.dart';
import 'package:pilar_erp/features/dashboard/widgets/module_launcher_grid.dart';

import '../../helpers/test_utils.dart';

void main() {
  group('UC-02 + UC-04 — ModuleLauncherGrid', () {
    testWidgets(
        'UC-02a: Sin módulos → muestra "No hay módulos disponibles"',
        (tester) async {
      await tester.pumpWidget(
        buildFluentApp(
          const ModuleLauncherGrid(modulos: []),
          overrides: [
            hasPermissionProvider.overrideWith((ref, _) => false),
          ],
        ),
      );

      expect(find.text('No hay módulos disponibles'), findsOneWidget);
    });

    testWidgets(
        'UC-02b: Módulos sin ruta definida (facturacion, ventas) '
        '→ son filtrados, muestra estado vacío',
        (tester) async {
      // El widget filtra módulos que no tienen ruta en _routeForModulo.
      // Actualmente solo 'administracion' tiene ruta.
      final modulos = [
        fakeModulo(id: 'facturacion', nombre: 'Facturación', orden: 1),
        fakeModulo(id: 'ventas', nombre: 'Ventas', orden: 2),
        fakeModulo(id: 'inventario', nombre: 'Inventario', orden: 3),
      ];

      await tester.pumpWidget(
        buildFluentApp(
          ModuleLauncherGrid(modulos: modulos),
          overrides: [
            hasPermissionProvider.overrideWith((ref, _) => false),
          ],
        ),
      );

      // Módulos sin ruta no aparecen
      expect(find.text('Facturación'), findsNothing);
      expect(find.text('Ventas'), findsNothing);
      expect(find.text('Inventario'), findsNothing);
      expect(find.text('No hay módulos disponibles'), findsOneWidget);
    });

    testWidgets(
        'UC-04a: Módulo "administracion" + CON permiso → tile visible',
        (tester) async {
      final modulos = [
        fakeModulo(id: 'administracion', nombre: 'Administración', orden: 0),
      ];

      await tester.pumpWidget(
        buildFluentApp(
          ModuleLauncherGrid(modulos: modulos),
          overrides: [
            // Usuario con permiso de administración
            hasPermissionProvider.overrideWith((ref, _) => true),
          ],
        ),
      );

      await tester.pump();

      expect(find.text('Administración'), findsOneWidget);
      expect(find.text('No hay módulos disponibles'), findsNothing);
    });

    testWidgets(
        'UC-04b: Módulo "administracion" + SIN permiso → tile NO visible',
        (tester) async {
      final modulos = [
        fakeModulo(id: 'administracion', nombre: 'Administración', orden: 0),
      ];

      await tester.pumpWidget(
        buildFluentApp(
          ModuleLauncherGrid(modulos: modulos),
          overrides: [
            // Sin permisos de administración
            hasPermissionProvider.overrideWith((ref, _) => false),
          ],
        ),
      );

      await tester.pump();

      expect(find.text('Administración'), findsNothing);
      expect(find.text('No hay módulos disponibles'), findsOneWidget);
    });

    testWidgets(
        'UC-02c: Módulo sin ruta + módulo con ruta + sin permiso → '
        'solo muestra el vacío (admin bloqueado por permiso)',
        (tester) async {
      final modulos = [
        fakeModulo(id: 'ventas', nombre: 'Ventas', orden: 1),
        fakeModulo(id: 'administracion', nombre: 'Administración', orden: 0),
      ];

      await tester.pumpWidget(
        buildFluentApp(
          ModuleLauncherGrid(modulos: modulos),
          overrides: [
            hasPermissionProvider.overrideWith((ref, _) => false),
          ],
        ),
      );

      await tester.pump();

      // 'Ventas' no tiene ruta, 'Administración' bloqueada por permiso
      expect(find.text('No hay módulos disponibles'), findsOneWidget);
    });
  });
}
