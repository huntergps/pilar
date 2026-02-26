// UC-05: EmpresaCard en el dashboard
// Verifica que la card muestra la identidad de la empresa correctamente,
// con y sin campos opcionales.

import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/features/dashboard/widgets/empresa_card.dart';

import '../../helpers/test_utils.dart';

void main() {
  group('UC-05 — EmpresaCard', () {
    testWidgets('UC-05a: Muestra nombre comercial como titular', (tester) async {
      final config = fakeEmpresaConfig(
        nombre: 'Ferretería El Clavo S.A.',
        nombreComercial: 'ElClavo',
      );

      await tester.pumpWidget(
        buildFluentApp(EmpresaCard(empresa: config)),
      );

      // nombreComercial tiene prioridad sobre nombre legal
      expect(find.text('ElClavo'), findsOneWidget);
    });

    testWidgets(
        'UC-05b: Sin nombreComercial → usa nombre legal como titular',
        (tester) async {
      final config = fakeEmpresaConfig(
        nombre: 'Ferretería El Clavo S.A.',
      );

      await tester.pumpWidget(
        buildFluentApp(EmpresaCard(empresa: config)),
      );

      expect(find.text('Ferretería El Clavo S.A.'), findsAtLeastNWidgets(1));
    });

    testWidgets('UC-05c: Muestra RUC cuando está disponible', (tester) async {
      final config = fakeEmpresaConfig(ruc: '1234567890001');

      await tester.pumpWidget(
        buildFluentApp(EmpresaCard(empresa: config)),
      );

      expect(find.textContaining('1234567890001'), findsOneWidget);
    });

    testWidgets('UC-05d: Sin RUC → no muestra chip de RUC', (tester) async {
      final config = fakeEmpresaConfig(ruc: null);

      await tester.pumpWidget(
        buildFluentApp(EmpresaCard(empresa: config)),
      );

      expect(find.textContaining('RUC'), findsNothing);
    });

    testWidgets('UC-05e: Muestra teléfono cuando existe', (tester) async {
      final config = fakeEmpresaConfig(telefono: '0999000111');

      await tester.pumpWidget(
        buildFluentApp(EmpresaCard(empresa: config)),
      );

      expect(find.textContaining('0999000111'), findsOneWidget);
    });

    testWidgets('UC-05f: Muestra email cuando existe', (tester) async {
      final config = fakeEmpresaConfig(email: 'info@empresa.com');

      await tester.pumpWidget(
        buildFluentApp(EmpresaCard(empresa: config)),
      );

      expect(find.textContaining('info@empresa.com'), findsOneWidget);
    });

    testWidgets(
        'UC-05g: Config mínima (solo nombre y moneda) → renderiza sin errores',
        (tester) async {
      final config = fakeEmpresaConfig(
        nombre: 'Empresa Mínima',
        ruc: null,
        telefono: null,
        email: null,
      );

      await tester.pumpWidget(
        buildFluentApp(EmpresaCard(empresa: config)),
      );

      // Solo comprobamos que renderiza sin crash
      expect(find.byType(EmpresaCard), findsOneWidget);
    });
  });
}
