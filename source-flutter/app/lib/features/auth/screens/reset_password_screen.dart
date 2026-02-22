import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_auth_ui_fluent/supabase_auth_ui_fluent.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';

/// Screen that lets the user set a new password after clicking a recovery link.
///
/// Supabase sends a recovery email with a magic link. When the user clicks it,
/// the app receives an [AuthChangeEvent.passwordRecovery] event — at that
/// point [SupaResetPassword] is already visible and ready for the new password.
///
/// On success the user is redirected to [PilarRoutes.login] so they can sign in
/// with the updated credentials.
class ResetPasswordScreen extends ConsumerWidget {
  const ResetPasswordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for the passwordRecovery deep-link event.
    // No navigation needed here — the user is already on this screen.
    ref.listen(authStateProvider, (_, next) {
      next.whenData((state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          // The recovery token has been consumed by Supabase.
          // SupaResetPassword handles the actual password update UI.
        }
      });
    });

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Restablecer contraseña'),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(PilarRoutes.login);
            }
          },
        ),
      ),
      content: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ingresa tu nueva contraseña',
                    style: FluentTheme.of(context).typography.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SupaResetPassword(
                    onSuccess: (_) => context.go(PilarRoutes.login),
                    localization: const SupaResetPasswordLocalization(
                      enterPassword: 'Nueva contraseña',
                      passwordLengthError:
                          'La contraseña debe tener al menos 6 caracteres',
                      updatePassword: 'Actualizar contraseña',
                      passwordResetSent:
                          '¡Contraseña actualizada! Inicia sesión.',
                      unexpectedError:
                          'Error inesperado. Intenta de nuevo.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
