/// Utilidades compartidas para widget tests de PILAR ERP.
///
/// Provee:
/// - [FakeConnectivityNotifier]: reemplaza ConnectivityNotifier sin timers ni DNS probes.
/// - [buildFluentApp]: wrapper mínimo de FluentApp + ProviderScope para tests sin router.
/// - [buildRouterApp]: wrapper con GoRouter para screens que usan context.go().
/// - Factories de datos fake: [fakeEmpresaResumen], [fakeEmpresaConfig], [fakeModulo].
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pilar_erp/core/offline/connectivity_service.dart';
import 'package:pilar_erp/core/providers/empresa_provider.dart';
import 'package:pilar_erp/core/providers/modulos_provider.dart';

// ---------------------------------------------------------------------------
// FakeConnectivityNotifier — sin timers ni DNS
// ---------------------------------------------------------------------------

/// Reemplaza [ConnectivityNotifier] en tests.
///
/// Extiende [ConnectivityNotifier] para satisfacer el type constraint de
/// `NotifierProvider.overrideWith`. Sobreescribe `build()` sin llamar a
/// `super.build()`, lo que evita que se inicien timers o DNS probes.
class FakeConnectivityNotifier extends ConnectivityNotifier {
  FakeConnectivityNotifier(this._initial);
  final bool _initial;

  @override
  bool build() => _initial; // sin timer, sin DNS

  void goOffline() => state = false;
  void goOnline() => state = true;
}

// ---------------------------------------------------------------------------
// Override base — siempre incluir en cualquier test
// ---------------------------------------------------------------------------

/// Lista mínima de overrides que deben estar en TODOS los tests para evitar
/// accesos a Supabase y timers infinitos.
List<Override> baseOverrides({bool startsOnline = true}) => [
      connectivityProvider
          .overrideWith(() => FakeConnectivityNotifier(startsOnline)),
    ];

// ---------------------------------------------------------------------------
// Wrappers
// ---------------------------------------------------------------------------

/// Envuelve [child] en FluentApp + ProviderScope. Para tests sin router.
Widget buildFluentApp(
  Widget child, {
  List<Override> overrides = const [],
  bool startsOnline = true,
}) {
  return ProviderScope(
    overrides: [
      ...baseOverrides(startsOnline: startsOnline),
      ...overrides,
    ],
    child: FluentApp(home: child),
  );
}

/// Envuelve un [GoRouter] en FluentApp.router + ProviderScope.
/// Úsalo para screens que navegan con context.go().
Widget buildRouterApp(
  GoRouter router, {
  List<Override> overrides = const [],
  bool startsOnline = true,
}) {
  return ProviderScope(
    overrides: [
      ...baseOverrides(startsOnline: startsOnline),
      ...overrides,
    ],
    child: FluentApp.router(routerConfig: router),
  );
}

/// Construye un GoRouter de prueba con rutas stub para las navegaciones clave.
///
/// La ruta [initialLocation] sirve el widget bajo test.
/// Las rutas /onboarding y /dashboard son stubs que renderizan un [Text]
/// con un identificador único, permitiendo verificar que la navegación ocurrió.
GoRouter testRouter({
  required String initialLocation,
  required Widget Function(BuildContext, GoRouterState) pageBuilder,
  Map<String, String> extraRoutes = const {},
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: initialLocation, builder: pageBuilder),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const ScaffoldPage(
          content: Center(child: Text('page:onboarding')),
        ),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const ScaffoldPage(
          content: Center(child: Text('page:dashboard')),
        ),
      ),
      GoRoute(
        path: '/select-empresa',
        builder: (_, __) => const ScaffoldPage(
          content: Center(child: Text('page:select-empresa')),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Factories de datos fake
// ---------------------------------------------------------------------------

EmpresaResumen fakeEmpresaResumen({
  String id = 'e-001',
  String nombre = 'Empresa Test',
  String? ruc = '1234567890001',
  String? logoUrl,
  bool esActiva = true,
  String rolCodigo = 'ADMIN',
  String rolNombre = 'Administrador',
}) =>
    EmpresaResumen(
      empresaId: id,
      nombre: nombre,
      ruc: ruc,
      logoUrl: logoUrl,
      esActiva: esActiva,
      rolCodigo: rolCodigo,
      rolNombre: rolNombre,
    );

EmpresaConfig fakeEmpresaConfig({
  String id = 'e-001',
  String nombre = 'Empresa Test',
  String? nombreComercial,
  String? ruc = '1234567890001',
  String? telefono,
  String? email,
  String? colorPrimario,
  String monedaFuncional = 'USD',
}) =>
    EmpresaConfig(
      empresaId: id,
      nombre: nombre,
      nombreComercial: nombreComercial,
      ruc: ruc,
      telefono: telefono,
      email: email,
      colorPrimario: colorPrimario,
      monedaFuncional: monedaFuncional,
    );

ModuloItem fakeModulo({
  String id = 'administracion',
  String nombre = 'Administración',
  String icono = 'settings',
  int orden = 0,
  String tipo = 'infraestructura',
}) =>
    ModuloItem(
      id: id,
      nombre: nombre,
      icono: icono,
      orden: orden,
      tipo: tipo,
    );
