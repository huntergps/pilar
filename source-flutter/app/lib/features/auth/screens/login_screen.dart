import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_auth_ui_fluent/supabase_auth_ui_fluent.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/pilar_breakpoints.dart';

/// Full-page centered login screen.
///
/// Layout:
/// - Desktop (>=900px): content constrained to 440px, centered on the page.
/// - Mobile/tablet (<900px): full width with 24px horizontal padding.
///
/// Authentication flow:
/// - Email/password via [SupaEmailAuth] (sign-in + sign-up + forgot password).
/// - Google OAuth via [SupaSocialsAuth].
/// - On success both paths call [context.go(PilarRoutes.dashboard)].
///   The router redirect will intercept and send the user to
///   [PilarRoutes.selectEmpresa] when no empresa_id is in the JWT yet.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Redirect to dashboard (or select-empresa) when the user signs in.
    ref.listen(authStateProvider, (prev, next) {
      next.whenData((authState) {
        if (authState.event == AuthChangeEvent.signedIn) {
          context.go(PilarRoutes.dashboard);
        }
      });
    });

    final theme = FluentTheme.of(context);
    final isDesktop = context.isDesktop;

    return ScaffoldPage(
      content: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 0 : 24,
                vertical: 48,
              ),
              child: isDesktop
                  ? Card(
                      padding: const EdgeInsets.all(32),
                      child: _LoginContent(theme: theme),
                    )
                  : _LoginContent(theme: theme),
            ),
          ),
        ),
      ),
    );
  }
}

/// Muestra un [ContentDialog] explicando que se envió un correo de confirmación.
///
/// Incluye el email destinatario y un botón de reenvío por si el correo
/// no llegó, usando `supabase.auth.resend()`.
void _showEmailConfirmationBanner(BuildContext context, String email) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmailConfirmationDialog(email: email),
  );
}

class _EmailConfirmationDialog extends StatefulWidget {
  final String email;
  const _EmailConfirmationDialog({required this.email});

  @override
  State<_EmailConfirmationDialog> createState() =>
      _EmailConfirmationDialogState();
}

class _EmailConfirmationDialogState extends State<_EmailConfirmationDialog> {
  bool _resending = false;
  bool _resent = false;

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      if (mounted) setState(() => _resent = true);
    } catch (_) {
      // Si falla el reenvío no bloqueamos al usuario.
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Icon(FluentIcons.mail, color: theme.accentColor),
          const SizedBox(width: 8),
          const Text('Confirma tu correo'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Te enviamos un enlace de confirmación a:',
            style: theme.typography.body,
          ),
          const SizedBox(height: 4),
          Text(widget.email, style: theme.typography.bodyStrong),
          const SizedBox(height: 16),
          Text(
            'Abre el correo y haz clic en el enlace para activar tu cuenta. '
            'Después regresa aquí e inicia sesión.',
            style: theme.typography.body,
          ),
          if (_resent) ...[
            const SizedBox(height: 12),
            const InfoBar(
              title: Text('Correo reenviado'),
              content: Text('Revisa también la carpeta de spam.'),
              severity: InfoBarSeverity.success,
            ),
          ],
        ],
      ),
      actions: [
        if (!_resent)
          HyperlinkButton(
            onPressed: _resending ? null : _resend,
            child: _resending
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      SizedBox(width: 6),
                      Text('Reenviando...'),
                    ],
                  )
                : const Text('No recibí el correo — reenviar'),
          ),
        FilledButton(
          child: const Text('Entendido'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// Inner content of the login form, shared between desktop (Card) and mobile.
class _LoginContent extends StatelessWidget {
  final FluentThemeData theme;

  const _LoginContent({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Logo ---
        Center(
          child: SvgPicture.asset(
            'assets/logos/pilar_logo.svg',
            height: 72,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(
              theme.accentColor,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(height: 32),

        // --- Email / password form ---
        SupaEmailAuth(
          onSignInComplete: (r) => context.go(PilarRoutes.dashboard),
          onSignUpComplete: (r) {
            if (r.session != null) {
              // Supabase no requiere confirmación → sesión inmediata.
              context.go(PilarRoutes.dashboard);
            } else {
              // Email de confirmación enviado: informar claramente al usuario.
              final email = r.user?.email ?? '';
              _showEmailConfirmationBanner(context, email);
            }
          },
          onPasswordResetEmailSent: () =>
              context.push(PilarRoutes.resetPassword),
          localization: const SupaEmailAuthLocalization(
            enterEmail: 'Correo electrónico',
            validEmailError: 'Ingresa un correo electrónico válido',
            enterPassword: 'Contraseña',
            passwordLengthError:
                'La contraseña debe tener al menos 6 caracteres',
            signIn: 'Iniciar sesión',
            signUp: 'Crear cuenta',
            forgotPassword: '¿Olvidaste tu contraseña?',
            dontHaveAccount: '¿No tienes cuenta? Regístrate',
            haveAccount: '¿Ya tienes cuenta? Inicia sesión',
            sendPasswordReset: 'Enviar enlace de recuperación',
            passwordResetSent: 'Revisa tu correo para restablecer tu contraseña',
            backToSignIn: 'Volver al inicio de sesión',
            unexpectedError: 'Error inesperado. Intenta de nuevo.',
            requiredFieldError: 'Este campo es requerido',
            confirmPasswordError: 'Las contraseñas no coinciden',
            confirmPassword: 'Confirmar contraseña',
          ),
        ),

        const SizedBox(height: 16),

        // --- Divider "o continúa con" ---
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'o continúa con',
                style: FluentTheme.of(context).typography.caption,
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),

        const SizedBox(height: 16),

        // --- OAuth (Google) ---
        SupaSocialsAuth(
          socialProviders: const [OAuthProvider.google],
          onSuccess: (session) => context.go(PilarRoutes.dashboard),
          localization: const SupaSocialsAuthLocalization(
            successSignInMessage: 'Sesión iniciada correctamente',
            oAuthButtonLabels: {
              OAuthProvider.google: 'Continuar con Google',
            },
          ),
        ),
      ],
    );
  }
}
