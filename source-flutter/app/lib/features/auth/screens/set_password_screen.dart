import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';

/// Pantalla que se muestra al usuario invitado la primera vez que accede.
///
/// Flujo:
///   1. Admin envía invitación → invite-user pone needs_password=true en user_metadata.
///   2. Usuario hace clic en el link del email → queda autenticado (magic link).
///   3. GoRouter detecta needs_password=true → redirige aquí.
///   4. El usuario establece su contraseña → supabase.auth.updateUser borra el flag.
///   5. Router redirige al dashboard (o select-empresa si no tiene empresa_id).
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final pass = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (pass.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final response = await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          password: pass,
          data: {'needs_password': false},
        ),
      );

      if (!mounted) return;

      if (response.user == null) {
        setState(() {
          _loading = false;
          _error = 'Error al guardar la contraseña. Intenta de nuevo.';
        });
        return;
      }

      // Sesión actualizada — dejar que el router redirija al destino correcto.
      // El flag needs_password=false ya fue guardado; el router no volverá aquí.
      final session = Supabase.instance.client.auth.currentSession;
      final empresaId = session?.user.appMetadata['empresa_id'] as String?;
      context.go(empresaId != null ? PilarRoutes.dashboard : PilarRoutes.selectEmpresa);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error inesperado. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return SafeArea(
      child: ScaffoldPage(
        content: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo / icono
                    Icon(
                      FluentIcons.lock,
                      size: 48,
                      color: theme.accentColor,
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Establece tu contraseña',
                      style: theme.typography.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crea una contraseña para acceder a PILAR en el futuro.',
                      style: theme.typography.body?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Campo contraseña
                    InfoLabel(
                      label: 'Contraseña',
                      child: PasswordBox(
                        controller: _passCtrl,
                        placeholder: 'Mínimo 6 caracteres',
                        revealMode: PasswordRevealMode.peekAlways,
                        onSubmitted: (_) => _guardar(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Campo confirmar contraseña
                    InfoLabel(
                      label: 'Confirmar contraseña',
                      child: PasswordBox(
                        controller: _confirmCtrl,
                        placeholder: 'Repite la contraseña',
                        revealMode: PasswordRevealMode.peekAlways,
                        onSubmitted: (_) => _guardar(),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Error
                    if (_error != null) ...[
                      InfoBar(
                        title: Text(_error!),
                        severity: InfoBarSeverity.error,
                      ),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 8),

                    // Botón guardar
                    FilledButton(
                      onPressed: _loading ? null : _guardar,
                      child: _loading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          : const Text('Guardar contraseña'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
