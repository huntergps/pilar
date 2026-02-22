import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/router/app_router.dart' show PilarRoutes, supabaseUrlProvider;

/// Pantalla de configuración general del sistema.
///
/// Incluye la sección "Servidor" para cambiar las credenciales Supabase
/// en instalaciones que no usan --dart-define en tiempo de compilación.
class ConfiguracionScreen extends ConsumerWidget {
  const ConfiguracionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final compiledIn = SupabaseConfigService.isCompiledIn;
    final currentUrl = ref.watch(supabaseUrlProvider);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Configuración')),
      content: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ---- Servidor Supabase ----
          _Section(
            title: 'Servidor',
            children: [
              _ConfigRow(
                icon: FluentIcons.cloud,
                label: 'URL del proyecto',
                value: currentUrl,
              ),
              if (!compiledIn) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Button(
                      child: const Text('Cambiar servidor'),
                      onPressed: () => _confirmChange(context),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Las credenciales están fijadas en tiempo de compilación '
                  'y no se pueden cambiar desde aquí.',
                  style: theme.typography.caption
                      ?.copyWith(color: theme.inactiveColor),
                ),
              ],
            ],
          ),

          const SizedBox(height: 32),

          // ---- Próximamente ----
          _Section(
            title: 'SRI / Facturación electrónica',
            children: [
              Text(
                'Próximamente — configuración de ambientes SRI, '
                'certificado digital y parámetros de facturación.',
                style: theme.typography.body,
              ),
            ],
          ),

          const SizedBox(height: 32),

          _Section(
            title: 'Notificaciones',
            children: [
              Text(
                'Próximamente — configuración de canales de notificación '
                '(email, WhatsApp, Telegram).',
                style: theme.typography.body,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmChange(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('Cambiar servidor'),
        content: const Text(
          'Se cerrará la sesión actual y se limpiarán las credenciales guardadas. '
          '¿Deseas continuar?',
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: const Text('Continuar'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await Supabase.instance.client.auth.signOut();
      await SupabaseConfigService.clear();
      if (context.mounted) context.go(PilarRoutes.setup);
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.typography.bodyStrong),
        const SizedBox(height: 4),
        const Divider(),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ConfigRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.inactiveColor),
        const SizedBox(width: 8),
        Text('$label: ', style: theme.typography.bodyStrong),
        Expanded(
          child: Text(
            value,
            style: theme.typography.body,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
