import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/empresa_provider.dart';
import '../shell/pilar_shell.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/onboarding/screens/onboarding_wizard.dart';
import '../../features/select_empresa/screens/select_empresa_screen.dart';
import '../../features/setup/screens/supabase_setup_screen.dart';
import '../../features/administracion/screens/admin_panel_screen.dart';
import '../../features/administracion/screens/empresa_screen.dart';
import '../../features/administracion/screens/usuarios_screen.dart';
import '../../features/administracion/screens/modulos_screen.dart';
import '../../features/administracion/screens/configuracion_screen.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// True when Supabase was successfully initialized with real credentials.
///
/// Initialized at startup in main(). The setup screen can mutate it at runtime
/// via [supabaseConfiguredProvider.notifier] so the router re-evaluates.
final supabaseConfiguredProvider = StateProvider<bool>((ref) => false);

/// The current Supabase project URL. Initialized in main() after loading config.
final supabaseUrlProvider = StateProvider<String>((ref) => '');

// ---------------------------------------------------------------------------
// Route path constants
// ---------------------------------------------------------------------------

/// Typed route path constants for the entire PILAR ERP app.
abstract final class PilarRoutes {
  static const String setup = '/setup';
  static const String login = '/auth/login';
  static const String resetPassword = '/auth/reset-password';
  static const String onboarding = '/onboarding';
  static const String selectEmpresa = '/select-empresa';
  static const String dashboard = '/dashboard';
  static const String admin = '/admin';
  static const String adminEmpresa = '/admin/empresa';
  static const String adminUsuarios = '/admin/usuarios';
  static const String adminModulos = '/admin/modulos';
  static const String adminConfiguracion = '/admin/configuracion';
}

// ---------------------------------------------------------------------------
// Router provider
// ---------------------------------------------------------------------------

/// The application router, exposed as a Riverpod [Provider].
///
/// Redirect priority:
/// 1. Supabase not configured → [PilarRoutes.setup] (first-run).
/// 2. Not authenticated + not on an auth route → [PilarRoutes.login].
/// 3. Authenticated + on an auth route → dashboard or select-empresa.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);

  return GoRouter(
    initialLocation: PilarRoutes.dashboard,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    redirect: (context, state) {
      final isConfigured = ref.read(supabaseConfiguredProvider);
      final loc = state.matchedLocation;

      // 1. No Supabase credentials → setup screen.
      if (!isConfigured) {
        return loc == PilarRoutes.setup ? null : PilarRoutes.setup;
      }

      final session = ref.read(sessionProvider);
      final isLoggedIn = session != null;
      final isAuthRoute = loc.startsWith('/auth');

      // 2. Not authenticated → login.
      if (!isLoggedIn && !isAuthRoute) return PilarRoutes.login;

      // 3. Authenticated on auth screen → into the app.
      if (isLoggedIn && isAuthRoute) {
        final empresaId = ref.read(empresaActivaIdProvider);
        return empresaId != null
            ? PilarRoutes.dashboard
            : PilarRoutes.selectEmpresa;
      }

      return null;
    },
    routes: [
      // ---- First-run setup (no shell, no auth required) ----
      GoRoute(
        path: PilarRoutes.setup,
        builder: (_, __) => const SupabaseSetupScreen(),
      ),

      // ---- Public auth routes (no shell) ----
      GoRoute(
        path: PilarRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: PilarRoutes.resetPassword,
        builder: (_, __) => const ResetPasswordScreen(),
      ),

      // ---- Onboarding (empresa setup after first login, no shell) ----
      GoRoute(
        path: PilarRoutes.onboarding,
        builder: (_, __) => const OnboardingWizardScreen(),
      ),

      // ---- Empresa selector (no shell) ----
      GoRoute(
        path: PilarRoutes.selectEmpresa,
        builder: (_, __) => const SelectEmpresaScreen(),
      ),

      // ---- Authenticated shell ----
      ShellRoute(
        builder: (context, state, child) => PilarShell(child: child),
        routes: [
          GoRoute(
            path: PilarRoutes.dashboard,
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: PilarRoutes.admin,
            builder: (_, __) => const AdminPanelScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminEmpresa,
            builder: (_, __) => const EmpresaScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminUsuarios,
            builder: (_, __) => const UsuariosScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminModulos,
            builder: (_, __) => const ModulosScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminConfiguracion,
            builder: (_, __) => const ConfiguracionScreen(),
          ),
        ],
      ),
    ],
  );
});

// ---------------------------------------------------------------------------
// Auth-state change notifier
// ---------------------------------------------------------------------------

/// Bridges Riverpod's [authStateProvider] to go_router's [Listenable]-based
/// [GoRouter.refreshListenable] so the router re-evaluates redirects whenever
/// the user signs in, signs out, or the session is refreshed.
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(supabaseConfiguredProvider, (_, __) => notifyListeners());
  }
}
