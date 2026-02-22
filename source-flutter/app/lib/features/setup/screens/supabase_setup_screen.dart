import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/router/app_router.dart';

/// First-run screen shown when no Supabase credentials are configured.
///
/// Lets the user enter the project URL and anon key, tests the connection,
/// saves them to SharedPreferences via [SupabaseConfigService], reinitializes
/// [Supabase], then navigates to the login screen.
class SupabaseSetupScreen extends ConsumerStatefulWidget {
  const SupabaseSetupScreen({super.key});

  @override
  ConsumerState<SupabaseSetupScreen> createState() =>
      _SupabaseSetupScreenState();
}

class _SupabaseSetupScreenState extends ConsumerState<SupabaseSetupScreen> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _obscureKey = true;

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final anonKey = _keyController.text.trim();

    setState(() {
      _error = null;
      _loading = true;
    });

    // Basic validation
    if (url.isEmpty || anonKey.isEmpty) {
      setState(() {
        _error = 'Completa ambos campos.';
        _loading = false;
      });
      return;
    }

    final config = SupabaseConfig(url: url, anonKey: anonKey);
    if (!config.isValid) {
      setState(() {
        _error =
            'URL inválida. Debe ser https://xxxxx.supabase.co\n'
            'El anon key debe tener más de 20 caracteres.';
        _loading = false;
      });
      return;
    }

    try {
      // Re-initialize Supabase with the new credentials.
      // dispose() + initialize() is the supported way to switch projects.
      await Supabase.instance.dispose();
      await Supabase.initialize(url: url, anonKey: anonKey);

      // Persist so they survive app restarts.
      await SupabaseConfigService.save(url, anonKey);

      if (mounted) {
        // Update providers so the router re-evaluates redirects.
        ref.read(supabaseConfiguredProvider.notifier).state = true;
        ref.read(supabaseUrlProvider.notifier).state = url;
        context.go(PilarRoutes.login);
      }
    } catch (e) {
      setState(() {
        _error = 'No se pudo conectar al proyecto:\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      content: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Header ----
                  Text('Configurar servidor',
                      style: theme.typography.titleLarge,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Ingresa las credenciales de tu proyecto Supabase.\n'
                    'Las encontrarás en Project Settings → API.',
                    style: theme.typography.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // ---- URL ----
                  InfoLabel(
                    label: 'Project URL',
                    child: TextBox(
                      controller: _urlController,
                      placeholder: 'https://xxxxx.supabase.co',
                      enabled: !_loading,
                      keyboardType: TextInputType.url,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Anon key ----
                  InfoLabel(
                    label: 'Anon Key',
                    child: TextBox(
                      controller: _keyController,
                      placeholder: 'eyJhbGci...',
                      enabled: !_loading,
                      obscureText: _obscureKey,
                      suffix: IconButton(
                        icon: Icon(
                          _obscureKey ? FluentIcons.red_eye : FluentIcons.hide3,
                          size: 16,
                        ),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ---- Error ----
                  if (_error != null) ...[
                    InfoBar(
                      title: const Text('Error de conexión'),
                      content: Text(_error!),
                      severity: InfoBarSeverity.error,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ---- Save button ----
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: ProgressRing(strokeWidth: 2),
                          )
                        : const Text('Guardar y conectar'),
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
