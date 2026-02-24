import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/providers/empresa_provider.dart';
import '../../../core/router/app_router.dart' show PilarRoutes, supabaseUrlProvider;

/// Pantalla de configuración general del sistema.
///
/// Incluye:
/// - Sección "Servidor": cambiar credenciales Supabase.
/// - Sección "Personalización": login_titulo, color_primario, color_secundario.
class ConfiguracionScreen extends ConsumerStatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  ConsumerState<ConfiguracionScreen> createState() =>
      _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends ConsumerState<ConfiguracionScreen> {
  final _loginTituloCtrl = TextEditingController();
  final _colorPrimarioCtrl = TextEditingController();
  final _colorSecundarioCtrl = TextEditingController();

  bool _brandingInitialized = false;
  bool _brandingSaving = false;

  @override
  void dispose() {
    _loginTituloCtrl.dispose();
    _colorPrimarioCtrl.dispose();
    _colorSecundarioCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Branding save
  // ---------------------------------------------------------------------------

  Future<void> _saveBranding() async {
    final data = <String, dynamic>{};
    final titulo = _loginTituloCtrl.text.trim();
    final primario = _colorPrimarioCtrl.text.trim();
    final secundario = _colorSecundarioCtrl.text.trim();

    if (titulo.isNotEmpty) data['login_titulo'] = titulo;
    if (primario.isNotEmpty) data['color_primario'] = primario;
    if (secundario.isNotEmpty) data['color_secundario'] = secundario;

    if (data.isEmpty) return;

    setState(() => _brandingSaving = true);
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_update_branding',
        params: {'p_data': data},
      );
      if (result is Map && result['ok'] == true) {
        ref.invalidate(empresaConfigProvider);
        if (mounted) {
          displayInfoBar(
            context,
            builder: (_, close) => InfoBar(
              title: const Text('Personalización guardada'),
              severity: InfoBarSeverity.success,
              onClose: close,
            ),
          );
        }
      } else {
        if (mounted) {
          displayInfoBar(
            context,
            builder: (_, close) => InfoBar(
              title: const Text('Error al guardar'),
              content: Text(result?['error']?.toString() ?? 'Error desconocido'),
              severity: InfoBarSeverity.error,
              onClose: close,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _brandingSaving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final compiledIn = SupabaseConfigService.isCompiledIn;
    final currentUrl = ref.watch(supabaseUrlProvider);
    final empresaAsync = ref.watch(empresaConfigProvider);

    // Pre-fill branding controllers once
    empresaAsync.whenData((empresa) {
      if (!_brandingInitialized && empresa != null) {
        _brandingInitialized = true;
        _loginTituloCtrl.text = empresa.loginTitulo ?? '';
        _colorPrimarioCtrl.text = empresa.colorPrimario ?? '';
        _colorSecundarioCtrl.text = empresa.colorSecundario ?? '';
      }
    });

    return ScaffoldPage(
      header: const PageHeader(title: Text('Configuración')),
      content: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ---- Personalización (Branding) ----
          _Section(
            title: 'Personalización',
            children: [
              InfoLabel(
                label: 'Título en pantalla de inicio de sesión',
                child: TextBox(
                  controller: _loginTituloCtrl,
                  placeholder: 'Ej: Bienvenido a Mi Empresa',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InfoLabel(
                      label: 'Color primario (hex)',
                      child: TextBox(
                        controller: _colorPrimarioCtrl,
                        placeholder: '#0078D4',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InfoLabel(
                      label: 'Color secundario (hex)',
                      child: TextBox(
                        controller: _colorSecundarioCtrl,
                        placeholder: '#005A9E',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _brandingSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : FilledButton(
                          onPressed: _saveBranding,
                          child: const Text('Guardar personalización'),
                        ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

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
