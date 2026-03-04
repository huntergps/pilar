import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../shell/pilar_shell.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/mfa_challenge_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/onboarding/screens/onboarding_wizard.dart';
import '../../features/select_empresa/screens/select_empresa_screen.dart';
import '../../features/setup/screens/supabase_setup_screen.dart';
import '../../features/administracion/screens/empresa_screen.dart';
import '../../features/administracion/screens/usuarios_screen.dart';
import '../../features/administracion/screens/modulos_screen.dart';
import '../../features/administracion/screens/configuracion_screen.dart';
import '../../features/administracion/screens/archivos_screen.dart';
import '../../features/administracion/screens/cuentas_comunicacion_screen.dart';
import '../../features/administracion/screens/gestor_permisos_screen.dart';
import '../../features/administracion/screens/impresoras_screen.dart';
import '../../features/administracion/screens/sync_log_screen.dart';
import '../../features/comunicacion/screens/chat_tab.dart'
    show ChatScope, ChatTab;
import '../../features/comunicacion/screens/conversaciones_tab.dart';
import '../../features/comunicacion/screens/email_tab.dart';
import '../../features/comunicacion/screens/historial_tab.dart';
import '../../features/perfil/screens/perfil_screen.dart';
import '../../features/entidades/screens/contactos_screen.dart';
import '../../features/entidades/screens/familias_screen.dart';
import '../../features/entidades/screens/productos_screen.dart';

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
  static const String mfaChallenge = '/auth/mfa';
  static const String resetPassword = '/auth/reset-password';
  static const String onboarding = '/onboarding';
  static const String selectEmpresa = '/select-empresa';
  static const String dashboard = '/dashboard';
  static const String admin = '/admin';
  static const String adminEmpresa = '/admin/empresa';
  static const String adminUsuarios = '/admin/usuarios';
  static const String adminModulos = '/admin/modulos';
  static const String adminArchivos = '/admin/archivos';
  static const String adminComunicacion = '/admin/comunicacion';
  static const String adminPermisos = '/admin/permisos';
  static const String adminImpresoras = '/admin/impresoras';
  static const String adminSyncLog = '/admin/sync-log';
  static const String adminConfiguracion = '/admin/configuracion';
  static const String entidadesContactos = '/entidades/contactos';
  static const String entidadesProductos = '/entidades/productos';
  static const String entidadesFamilias = '/entidades/familias';
  static const String perfil = '/perfil';
  static const String configuracion = '/configuracion';
  static const String comunicacion = '/comunicacion';
  static const String comunicacionEmail = '/comunicacion/email';
  static const String comunicacionHistorial = '/comunicacion/historial';
  static const String comunicacionChat = '/comunicacion/chat';
  static const String misMensajesEmail = '/mis-mensajes/email';
  static const String misMensajesChat = '/mis-mensajes/chat';
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

      // Read session directly from the Supabase client (synchronous, always
      // up-to-date). Using ref.read(sessionProvider) here would cause a race
      // condition on mobile: the Riverpod StreamProvider may not yet reflect
      // the new session at the moment the redirect fires.
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final isLoggedIn = session != null;
      final isAuthRoute = loc.startsWith('/auth');

      // 2. Not authenticated → login.
      if (!isLoggedIn && !isAuthRoute) return PilarRoutes.login;

      // 3. Authenticated on auth screen → into the app.
      //    Exception: /auth/mfa must stay accessible for the MFA challenge.
      if (isLoggedIn && isAuthRoute && loc != PilarRoutes.mfaChallenge) {
        final empresaId = session.user.appMetadata['empresa_id'] as String?;
        return empresaId != null
            ? PilarRoutes.dashboard
            : PilarRoutes.selectEmpresa;
      }

      // 4. Authenticated anywhere without empresa_id → empresa setup.
      //    Handles the email-confirmation deep link: the user arrives at
      //    /dashboard (initial location) after confirming their email without
      //    ever passing through an /auth/* route, so condition 3 never fires.
      if (isLoggedIn) {
        const setupRoutes = [PilarRoutes.selectEmpresa, PilarRoutes.onboarding];
        if (!setupRoutes.contains(loc)) {
          final empresaId = session.user.appMetadata['empresa_id'] as String?;
          if (empresaId == null) return PilarRoutes.selectEmpresa;
        }
      }

      // 5. Sin permiso de administración → bloquear rutas /admin/*.
      if (isLoggedIn && loc.startsWith('/admin')) {
        final permisos =
            session.user.appMetadata['permisos'] as List<dynamic>? ?? [];
        if (!permisos.contains('administracion.empresa.menu')) {
          return PilarRoutes.dashboard;
        }
      }

      return null;
    },
    routes: [
      // ---- First-run setup (no shell, no auth required) ----
      GoRoute(
        path: PilarRoutes.setup,
        builder: (_, __) => const SupabaseSetupScreen(),
      ),

      // ---- Auth callback (PKCE deep link — supabase_flutter handles session) ----
      GoRoute(
        path: '/auth/callback',
        builder: (_, __) => const SizedBox.shrink(),
      ),

      // ---- Public auth routes (no shell) ----
      GoRoute(
        path: PilarRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: PilarRoutes.mfaChallenge,
        builder: (_, __) => const MfaChallengeScreen(),
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
          // ---- Empresa — canales de empresa (usuario_id IS NULL) ----
          GoRoute(
            path: PilarRoutes.comunicacion,
            builder: (_, __) => const ConversacionesTab(esEmpresa: true),
          ),
          GoRoute(
            path: PilarRoutes.comunicacionEmail,
            builder: (_, __) => const EmailTab(esEmpresa: true),
          ),
          GoRoute(
            path: PilarRoutes.comunicacionHistorial,
            builder: (_, __) => const HistorialTab(),
          ),
          GoRoute(
            path: PilarRoutes.comunicacionChat,
            builder: (_, __) => const ChatTab(scope: ChatScope.empresa),
          ),
          // ---- Mis mensajes — canales personales del usuario ----
          GoRoute(
            path: PilarRoutes.misMensajesEmail,
            builder: (_, __) => const EmailTab(esEmpresa: false),
          ),
          GoRoute(
            path: PilarRoutes.misMensajesChat,
            builder: (_, __) => const ChatTab(scope: ChatScope.personal),
          ),
          GoRoute(
            path: PilarRoutes.admin,
            redirect: (_, __) => PilarRoutes.adminEmpresa,
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
            path: PilarRoutes.adminArchivos,
            builder: (_, __) => const ArchivosScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminComunicacion,
            builder: (_, __) => const CuentasComunicacionScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminPermisos,
            builder: (_, __) => const GestorPermisosScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminImpresoras,
            builder: (_, __) => const ImpresorasScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminSyncLog,
            builder: (_, __) => const SyncLogScreen(),
          ),
          GoRoute(
            path: PilarRoutes.adminConfiguracion,
            redirect: (_, __) => PilarRoutes.configuracion,
          ),
          GoRoute(
            path: PilarRoutes.entidadesContactos,
            builder: (_, __) => const ContactosScreen(),
          ),
          GoRoute(
            path: PilarRoutes.entidadesProductos,
            builder: (_, __) => const ProductosScreen(),
          ),
          GoRoute(
            path: PilarRoutes.entidadesFamilias,
            builder: (_, __) => const FamiliasScreen(),
          ),
          GoRoute(
            path: PilarRoutes.perfil,
            builder: (_, __) => const PerfilPage(),
          ),
          GoRoute(
            path: PilarRoutes.configuracion,
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
