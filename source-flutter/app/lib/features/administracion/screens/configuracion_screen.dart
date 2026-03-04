import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/providers/auth_actions_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/usuario_provider.dart';
import '../../../core/router/app_router.dart' show PilarRoutes, supabaseUrlProvider;
import '../../../core/theme/pilar_spacing.dart';

// ---------------------------------------------------------------------------
// Pantalla principal
// ---------------------------------------------------------------------------

/// Pantalla de configuración personal del usuario.
///
/// Secciones:
/// - **Apariencia**: tema, color de acento personal, tipografía por nivel, espaciado, efecto ventana.
/// - **Servidor** (solo admin): credenciales Supabase.
class ConfiguracionScreen extends ConsumerStatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  ConsumerState<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends ConsumerState<ConfiguracionScreen> {
  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme      = FluentTheme.of(context);
    final compiledIn = SupabaseConfigService.isCompiledIn;
    final currentUrl = ref.watch(supabaseUrlProvider);
    final config     = ref.watch(appConfigProvider);
    final configSvc  = ref.read(appConfigProvider.notifier);
    final puedeAdmin = ref.watch(
        hasPermissionProvider('administracion.empresa.editar'));

    final isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('Configuración')),
      children: [
        // ================================================================
        // SECCIÓN: APARIENCIA
        // ================================================================
        const _SectionHeader(title: 'Apariencia'),
        const SizedBox(height: Spacing.md),

        // --- Modo de tema ---
        InfoLabel(
          label: 'Modo de tema',
          child: ComboBox<ThemeMode>(
            value: config.themeMode,
            items: const [
              ComboBoxItem(value: ThemeMode.system, child: Text('Sistema (automático)')),
              ComboBoxItem(value: ThemeMode.light,  child: Text('Claro')),
              ComboBoxItem(value: ThemeMode.dark,   child: Text('Oscuro')),
            ],
            onChanged: (mode) {
              if (mode != null) configSvc.setThemeMode(mode);
            },
          ),
        ),
        const SizedBox(height: Spacing.ml),

        // --- Modo de navegación ---
        InfoLabel(
          label: 'Modo de navegación',
          child: ComboBox<PaneDisplayMode>(
            value: config.paneDisplayMode,
            items: const [
              ComboBoxItem(value: PaneDisplayMode.auto,     child: Text('Automático (recomendado)')),
              ComboBoxItem(value: PaneDisplayMode.expanded, child: Text('Expandido')),
              ComboBoxItem(value: PaneDisplayMode.compact,  child: Text('Compacto (solo iconos)')),
              ComboBoxItem(value: PaneDisplayMode.minimal,  child: Text('Mínimo (hamburguesa)')),
            ],
            onChanged: (mode) {
              if (mode != null) configSvc.setDisplayMode(mode);
            },
          ),
        ),
        const SizedBox(height: Spacing.ml),

        // --- Color de acento (usuario puede sobreescribir el color de empresa) ---
        InfoLabel(
          label: 'Color de acento',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ColorSwatchRow(
                selected: config.accentColor,
                onSelected: (color) => configSvc.setAccentColor(color),
                includeNoneOption: true,
                noneLabel: 'Empresa / Sistema',
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                config.accentColor == null
                    ? 'Usando color de la empresa o del sistema operativo.'
                    : 'Color personalizado activo — sobreescribe el color de la empresa.',
                style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.ml),

        // --- Tipografía (expander con 7 sliders individuales) ---
        Expander(
          header: Row(
            children: [
              const Text('Escala de tipografía'),
              const Spacer(),
              if (!_isDefaultTypography(config))
                Padding(
                  padding: const EdgeInsets.only(right: Spacing.sm),
                  child: Button(
                    child: const Text('Restablecer'),
                    onPressed: () => configSvc.resetTypography(),
                  ),
                ),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Column(
              children: [
                _TypoSlider('Display',       config.displayFactor,    configSvc.setDisplayFactor),
                _TypoSlider('Título grande', config.titleLargeFactor, configSvc.setTitleLargeFactor),
                _TypoSlider('Título',        config.titleFactor,      configSvc.setTitleFactor),
                _TypoSlider('Cuerpo grande', config.bodyLargeFactor,  configSvc.setBodyLargeFactor),
                _TypoSlider('Cuerpo fuerte', config.bodyStrongFactor, configSvc.setBodyStrongFactor),
                _TypoSlider('Cuerpo',        config.bodyFactor,       configSvc.setBodyFactor),
                _TypoSlider('Subtítulo',     config.captionFactor,    configSvc.setCaptionFactor),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.ml),

        // --- Densidad de espaciado ---
        InfoLabel(
          label: 'Densidad de espaciado',
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  value: config.spacingFactor,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  label: config.spacingFactor.toStringAsFixed(1),
                  onChanged: configSvc.setSpacingFactor,
                ),
              ),
              const SizedBox(width: Spacing.ms),
              SizedBox(
                width: 42,
                child: Text(
                  config.spacingFactor.toStringAsFixed(1),
                  style: theme.typography.bodyStrong,
                ),
              ),
              Button(
                child: const Text('Reset'),
                onPressed: () => configSvc.resetSpacing(),
              ),
            ],
          ),
        ),

        // --- Efecto de ventana (solo desktop) ---
        if (isDesktop) ...[
          const SizedBox(height: Spacing.ml),
          InfoLabel(
            label: 'Efecto de ventana',
            child: ComboBox<WindowEffect>(
              value: config.windowEffect,
              items: [
                if (!kIsWeb && Platform.isWindows) ...[
                  const ComboBoxItem(value: WindowEffect.acrylic, child: Text('Acrílico')),
                  const ComboBoxItem(value: WindowEffect.mica,    child: Text('Mica')),
                ],
                if (!kIsWeb && Platform.isMacOS)
                  const ComboBoxItem(value: WindowEffect.sidebar, child: Text('Sidebar')),
                const ComboBoxItem(value: WindowEffect.disabled,  child: Text('Sin efecto')),
              ],
              onChanged: (effect) {
                if (effect != null) configSvc.setWindowEffect(effect);
              },
            ),
          ),
        ],

        const SizedBox(height: Spacing.md),

        // Restablecer toda la apariencia
        Row(
          children: [
            Button(
              child: const Text('Restablecer apariencia'),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => ContentDialog(
                    title: const Text('Restablecer apariencia'),
                    content: const Text(
                      'Se devolverán todos los ajustes de apariencia a los valores predeterminados. ¿Continuar?',
                    ),
                    actions: [
                      Button(
                        child: const Text('Cancelar'),
                        onPressed: () => Navigator.pop(dialogCtx, false),
                      ),
                      FilledButton(
                        child: const Text('Restablecer'),
                        onPressed: () => Navigator.pop(dialogCtx, true),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) configSvc.reset();
              },
            ),
          ],
        ),

        // ================================================================
        // SECCIÓN SOLO ADMIN: Servidor
        // ================================================================
        if (puedeAdmin) ...[
          const SizedBox(height: Spacing.xl),

          const _SectionHeader(title: 'Servidor'),
          const SizedBox(height: Spacing.md),

          _ConfigRow(
            icon: FluentIcons.cloud,
            label: 'URL del proyecto',
            value: currentUrl,
          ),

          if (!compiledIn) ...[
            const SizedBox(height: Spacing.ms),
            Row(
              children: [
                Button(
                  child: const Text('Cambiar servidor'),
                  onPressed: () => _confirmChange(context),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Las credenciales están fijadas en tiempo de compilación '
              'y no se pueden cambiar desde aquí.',
              style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
            ),
          ],

          const SizedBox(height: Spacing.xl),
        ],
      ],
    );
  }

  bool _isDefaultTypography(config) =>
      config.displayFactor == 1.0 &&
      config.titleLargeFactor == 1.0 &&
      config.titleFactor == 1.0 &&
      config.bodyLargeFactor == 1.0 &&
      config.bodyStrongFactor == 1.0 &&
      config.bodyFactor == 1.0 &&
      config.captionFactor == 1.0;

  Future<void> _confirmChange(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => ContentDialog(
        title: const Text('Cambiar servidor'),
        content: const Text(
          'Se cerrará la sesión actual y se limpiarán las credenciales guardadas. '
          '¿Deseas continuar?',
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(dialogCtx, false),
          ),
          FilledButton(
            child: const Text('Continuar'),
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(authActionsProvider.notifier).signOut();
      await SupabaseConfigService.clear();
      if (context.mounted) context.go(PilarRoutes.setup);
    }
  }
}

// ---------------------------------------------------------------------------
// Widget: sección header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.typography.bodyStrong),
        const SizedBox(height: Spacing.xs),
        const Divider(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Widget: fila de swatches de color
// ---------------------------------------------------------------------------

/// Row of circular color swatches. Tapping one calls [onSelected].
/// When [includeNoneOption] is true, a first "reset/none" circle is shown.
class _ColorSwatchRow extends StatelessWidget {
  final AccentColor? selected;
  final void Function(AccentColor?) onSelected;
  final bool includeNoneOption;
  final String noneLabel;

  const _ColorSwatchRow({
    required this.selected,
    required this.onSelected,
    this.includeNoneOption = false,
    this.noneLabel = 'Ninguno',
  });

  static const _colorNames = {
    'yellow':  'Amarillo',
    'orange':  'Naranja',
    'red':     'Rojo',
    'magenta': 'Magenta',
    'purple':  'Morado',
    'blue':    'Azul',
    'teal':    'Verde azulado',
    'green':   'Verde',
  };

  String _name(AccentColor c) {
    for (final entry in _colorNames.entries) {
      if (c == _colorFor(entry.key)) return entry.value;
    }
    return 'Personalizado';
  }

  AccentColor _colorFor(String name) {
    return switch (name) {
      'yellow'  => Colors.yellow,
      'orange'  => Colors.orange,
      'red'     => Colors.red,
      'magenta' => Colors.magenta,
      'purple'  => Colors.purple,
      'blue'    => Colors.blue,
      'teal'    => Colors.teal,
      'green'   => Colors.green,
      _         => Colors.blue,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bodyColor = theme.typography.body?.color ?? Colors.white;

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        if (includeNoneOption)
          Tooltip(
            message: noneLabel,
            child: _SwatchCircle(
              color: theme.micaBackgroundColor,
              isSelected: selected == null,
              checkColor: bodyColor,
              border: BorderSide(color: theme.inactiveColor, width: 1.5),
              onTap: () => onSelected(null),
            ),
          ),
        ...Colors.accentColors.map((c) => Tooltip(
          message: _name(c),
          child: _SwatchCircle(
            color: c,
            isSelected: selected?.toARGB32() == c.toARGB32(),
            onTap: () => onSelected(c),
          ),
        )),
      ],
    );
  }
}

class _SwatchCircle extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final Color checkColor;
  final BorderSide? border;
  final VoidCallback onTap;

  const _SwatchCircle({
    required this.color,
    required this.isSelected,
    this.checkColor = Colors.white,
    this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: checkColor, width: 2.5)
              : border != null
                  ? Border.fromBorderSide(border!)
                  : null,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
        child: isSelected
            ? Icon(FluentIcons.check_mark, size: 16, color: checkColor)
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget: slider de tipografía individual
// ---------------------------------------------------------------------------

class _TypoSlider extends StatelessWidget {
  final String label;
  final double value;
  final void Function(double) onChanged;

  const _TypoSlider(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDefault = (value - 1.0).abs() < 0.001;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.ms),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.typography.body?.copyWith(
                color: isDefault ? null : theme.accentColor,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              label: value.toStringAsFixed(2),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 44,
            child: Text(
              value.toStringAsFixed(2),
              style: theme.typography.bodyStrong?.copyWith(
                color: isDefault ? theme.inactiveColor : theme.accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget: fila de info de servidor
// ---------------------------------------------------------------------------

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
        const SizedBox(width: Spacing.sm),
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
