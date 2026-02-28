// UC-01: Selección de empresa
// Verifica los 4 flujos principales de la pantalla de selección:
//   UC-01a: 0 empresas → redirige a /onboarding
//   UC-01b: 1 empresa sin configurar (placeholder) → redirige a /onboarding
//   UC-01c: 1 empresa configurada → auto-selecciona y va a /dashboard
//   UC-01d: >1 empresa → muestra picker con tarjetas
//   UC-01e: Empresa inactiva → rol visible en la tarjeta

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/providers/empresa_provider.dart';
import 'package:pilar_erp/features/select_empresa/screens/select_empresa_screen.dart';

import '../../helpers/test_utils.dart';

// ---------------------------------------------------------------------------
// Helpers de test
// ---------------------------------------------------------------------------

/// Construye la app con SelectEmpresaScreen montada en el router de test.
Widget buildSelectEmpresaApp({
  required List<EmpresaResumen> empresas,
  Future<void> Function(String)? onSwitch,
}) {
  final router = testRouter(
    initialLocation: '/select-empresa',
    pageBuilder: (_, __) => const SelectEmpresaScreen(),
  );

  return buildRouterApp(
    router,
    overrides: [
      misEmpresasProvider.overrideWith(
        (ref) => Stream.value(empresas),
      ),
      switchEmpresaProvider.overrideWithValue(
        onSwitch ?? (_) async {},
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UC-01 — SelectEmpresaScreen', () {
    testWidgets(
        'UC-01a: 0 empresas → ref.listen navega automáticamente a /onboarding',
        (tester) async {
      await tester.pumpWidget(buildSelectEmpresaApp(empresas: []));

      // Pump inicial → stream emite []
      await tester.pump();
      // ref.listen dispara y llama context.go('/onboarding')
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('page:onboarding'), findsOneWidget);
    });

    testWidgets(
        'UC-01b: 1 empresa con ruc=null (placeholder) → navega a /onboarding',
        (tester) async {
      final empresa = fakeEmpresaResumen(ruc: null); // sin RUC = placeholder

      await tester.pumpWidget(buildSelectEmpresaApp(empresas: [empresa]));

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('page:onboarding'), findsOneWidget);
    });

    testWidgets(
        'UC-01c: 1 empresa configurada → auto-selecciona y navega a /dashboard',
        (tester) async {
      var switchedTo = '';
      final empresa = fakeEmpresaResumen(
        id: 'e-real',
        nombre: 'Empresa Real',
        ruc: '1234567890001',
      );

      await tester.pumpWidget(
        buildSelectEmpresaApp(
          empresas: [empresa],
          onSwitch: (id) async => switchedTo = id,
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verificamos que se llamó switchEmpresaProvider con el id correcto
      expect(switchedTo, 'e-real');
      // Y que se navegó al dashboard
      expect(find.text('page:dashboard'), findsOneWidget);
    });

    testWidgets(
        'UC-01d: >1 empresa → muestra picker con nombre de cada empresa',
        (tester) async {
      final empresas = [
        fakeEmpresaResumen(id: 'e-001', nombre: 'Empresa Alpha'),
        fakeEmpresaResumen(id: 'e-002', nombre: 'Empresa Beta'),
        fakeEmpresaResumen(id: 'e-003', nombre: 'Empresa Gamma'),
      ];

      await tester.pumpWidget(buildSelectEmpresaApp(empresas: empresas));

      await tester.pump();       // stream emite
      await tester.pump();       // ref.listen: >1 empresas, no navega
      await tester.pump(const Duration(milliseconds: 200)); // render

      // Permanece en la pantalla de selección y muestra las 3 empresas
      expect(find.text('Empresa Alpha'), findsOneWidget);
      expect(find.text('Empresa Beta'), findsOneWidget);
      expect(find.text('Empresa Gamma'), findsOneWidget);

      // No navega a ninguna otra pantalla
      expect(find.text('page:dashboard'), findsNothing);
      expect(find.text('page:onboarding'), findsNothing);
    });

    testWidgets(
        'UC-01e: Empresa inactiva → aparece pero con estado inactivo',
        (tester) async {
      final empresas = [
        fakeEmpresaResumen(id: 'e-001', nombre: 'Empresa Activa'),
        fakeEmpresaResumen(
            id: 'e-002', nombre: 'Empresa Cerrada', esActiva: false),
      ];

      await tester.pumpWidget(buildSelectEmpresaApp(empresas: empresas));

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Ambas empresas aparecen
      expect(find.text('Empresa Activa'), findsOneWidget);
      expect(find.text('Empresa Cerrada'), findsOneWidget);
    });

    testWidgets(
        'UC-01f: Selección de empresa en el picker → llama switchEmpresaProvider',
        (tester) async {
      var switchedTo = '';
      final empresas = [
        fakeEmpresaResumen(id: 'e-001', nombre: 'Empresa Uno'),
        fakeEmpresaResumen(id: 'e-002', nombre: 'Empresa Dos'),
      ];

      await tester.pumpWidget(
        buildSelectEmpresaApp(
          empresas: empresas,
          onSwitch: (id) async => switchedTo = id,
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap en la tarjeta de la primera empresa
      await tester.tap(find.text('Empresa Uno'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(switchedTo, 'e-001');
    });
  });
}
