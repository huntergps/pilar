import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';

/// Pantalla de verificacion MFA (TOTP) post-login.
///
/// Se muestra cuando el usuario tiene 2FA activo y la sesion esta en AAL1.
/// Solicita el codigo de 6 digitos de la app autenticadora, verifica contra
/// Supabase MFA, y redirige al dashboard al alcanzar AAL2.
class MfaChallengeScreen extends ConsumerStatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  ConsumerState<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends ConsumerState<MfaChallengeScreen> {
  final _codeCtrl = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkAalLevel();
  }

  /// Si la sesion ya es AAL2, redirige al dashboard directamente.
  void _checkAalLevel() {
    try {
      final aal = Supabase.instance.client.auth.mfa
          .getAuthenticatorAssuranceLevel();
      if (aal.currentLevel == AuthenticatorAssuranceLevels.aal2 && mounted) {
        context.go(PilarRoutes.dashboard);
      }
    } catch (_) {
      // Ignore — stay on MFA screen.
    }
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Ingresa un codigo de 6 digitos');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final auth = Supabase.instance.client.auth;
      final factors = await auth.mfa.listFactors();
      final totp = factors.totp.where((f) => f.status == FactorStatus.verified);

      if (totp.isEmpty) {
        setState(() {
          _verifying = false;
          _error = 'No se encontro un factor TOTP verificado.';
        });
        return;
      }

      final factorId = totp.first.id;
      final challenge = await auth.mfa.challenge(factorId: factorId);
      await auth.mfa.verify(
        factorId: factorId,
        challengeId: challenge.id,
        code: code,
      );

      if (mounted) context.go(PilarRoutes.dashboard);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(FluentIcons.lock, size: 48, color: theme.accentColor),
                const SizedBox(height: 24),
                Text(
                  'Verificacion en dos pasos',
                  style: theme.typography.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingresa el codigo de 6 digitos de tu app autenticadora',
                  style: theme.typography.body
                      ?.copyWith(color: theme.inactiveColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextBox(
                  controller: _codeCtrl,
                  placeholder: '000000',
                  enabled: !_verifying,
                  autofocus: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: theme.typography.title?.copyWith(
                    letterSpacing: 8,
                  ),
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  InfoBar(
                    title: const Text('Error'),
                    content: Text(_error!),
                    severity: InfoBarSeverity.error,
                    onClose: () => setState(() => _error = null),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: _verifying ? null : _verify,
                  child: _verifying
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: ProgressRing(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Verificando...'),
                          ],
                        )
                      : const Text('Verificar'),
                ),
                const SizedBox(height: 24),
                Text(
                  'No tienes acceso a tu app autenticadora?\nContacta al administrador de tu empresa.',
                  style: theme.typography.caption
                      ?.copyWith(color: theme.inactiveColor),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
