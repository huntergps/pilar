import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/pilar_spacing.dart';
import '../../../core/widgets/loading_spinner.dart';

// ---------------------------------------------------------------------------
// SharedPreferences keys for data-grid preferences
// ---------------------------------------------------------------------------

const _kRowHeight = 'pref_row_height';
const _kGridLines = 'pref_grid_lines';

// ---------------------------------------------------------------------------
// Providers for grid preferences (so other screens can watch them)
// ---------------------------------------------------------------------------

/// Row height preference for SfDataGrid screens. Default: 52 (Normal).
final prefRowHeightProvider = StateProvider<double>((ref) => 52);

/// Whether to show horizontal dividers between rows in SfDataGrid.
final prefGridLinesProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Pantalla de preferencias del usuario.
///
/// Usa [FormScaffold] con secciones para Apariencia y Tabla de datos.
/// Los cambios se aplican inmediatamente y se persisten en SharedPreferences
/// (tabla de datos) o via [ConfigService] (tema y color de acento).
class PreferenciasScreen extends ConsumerStatefulWidget {
  const PreferenciasScreen({super.key});

  @override
  ConsumerState<PreferenciasScreen> createState() => _PreferenciasScreenState();
}

class _PreferenciasScreenState extends ConsumerState<PreferenciasScreen> {
  // Apariencia
  late ThemeMode _themeMode;
  AccentColor? _accentColor;

  // Tabla de datos
  double _rowHeight = 52;
  bool _gridLines = false;

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final config = ref.read(appConfigProvider);
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _themeMode = config.themeMode;
      _accentColor = config.accentColor;
      _rowHeight = (prefs.getDouble(_kRowHeight) ?? 52).clamp(40, 64);
      _gridLines = prefs.getBool(_kGridLines) ?? false;
      _loaded = true;
    });
  }

  Future<void> _guardar() async {
    final configSvc = ref.read(appConfigProvider.notifier);

    // Apariencia
    configSvc.setThemeMode(_themeMode);
    configSvc.setAccentColor(_accentColor);

    // Tabla de datos
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kRowHeight, _rowHeight);
    await prefs.setBool(_kGridLines, _gridLines);

    // Update providers so other screens pick up changes immediately
    ref.read(prefRowHeightProvider.notifier).state = _rowHeight;
    ref.read(prefGridLinesProvider.notifier).state = _gridLines;

    if (mounted) {
      displayInfoBar(
        context,
        builder: (_, close) => InfoBar(
          title: const Text('Preferencias guardadas'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const ScaffoldPage(
        header: PageHeader(title: Text('Preferencias')),
        content: const PilarLoadingCenter(),
      );
    }

    final theme = FluentTheme.of(context);

    return FormScaffold(
      title: 'Preferencias',
      onSave: _guardar,
      sections: [
        // ==================================================================
        // Apariencia
        // ==================================================================
        FormSection(
          title: 'Apariencia',
          columns: 1,
          children: [
            InfoLabel(
              label: 'Tema',
              child: ComboBox<ThemeMode>(
                value: _themeMode,
                isExpanded: true,
                items: const [
                  ComboBoxItem(value: ThemeMode.system, child: Text('Sistema')),
                  ComboBoxItem(value: ThemeMode.light, child: Text('Claro')),
                  ComboBoxItem(value: ThemeMode.dark, child: Text('Oscuro')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _themeMode = v);
                },
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Color de acento', style: theme.typography.body),
                const SizedBox(height: Spacing.sm),
                _ColorSwatchRow(
                  selected: _accentColor,
                  onSelected: (c) => setState(() => _accentColor = c),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  _accentColor == null
                      ? 'Usando color de la empresa o del sistema operativo.'
                      : 'Color personalizado activo.',
                  style: theme.typography.caption
                      ?.copyWith(color: theme.inactiveColor),
                ),
              ],
            ),
          ],
        ),

        // ==================================================================
        // Tabla de datos
        // ==================================================================
        FormSection(
          title: 'Tabla de datos',
          columns: 2,
          children: [
            InfoLabel(
              label: 'Densidad de filas',
              child: ComboBox<double>(
                value: _rowHeight,
                isExpanded: true,
                items: const [
                  ComboBoxItem(value: 40, child: Text('Compacta (40px)')),
                  ComboBoxItem(value: 52, child: Text('Normal (52px)')),
                  ComboBoxItem(value: 64, child: Text('Amplia (64px)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _rowHeight = v);
                },
              ),
            ),
            InfoLabel(
              label: 'Mostrar lineas entre filas',
              child: Align(
                alignment: Alignment.centerLeft,
                child: ToggleSwitch(
                  checked: _gridLines,
                  onChanged: (v) => setState(() => _gridLines = v),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Color swatch row (reutiliza el patron de configuracion_screen)
// ---------------------------------------------------------------------------

class _ColorSwatchRow extends StatelessWidget {
  final AccentColor? selected;
  final void Function(AccentColor?) onSelected;

  const _ColorSwatchRow({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bodyColor = theme.typography.body?.color ?? Colors.white;

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        // "Sin color" option — fallback to empresa / OS
        Tooltip(
          message: 'Empresa / Sistema',
          child: _SwatchCircle(
            color: theme.micaBackgroundColor,
            isSelected: selected == null,
            checkColor: bodyColor,
            border: BorderSide(color: theme.inactiveColor, width: 1.5),
            onTap: () => onSelected(null),
          ),
        ),
        ...Colors.accentColors.map((c) => Tooltip(
              message: _colorName(c),
              child: _SwatchCircle(
                color: c,
                isSelected: selected?.toARGB32() == c.toARGB32(),
                onTap: () => onSelected(c),
              ),
            )),
      ],
    );
  }

  static String _colorName(AccentColor c) {
    // Compare by ARGB value for reliability
    if (c.toARGB32() == Colors.yellow.toARGB32()) return 'Amarillo';
    if (c.toARGB32() == Colors.orange.toARGB32()) return 'Naranja';
    if (c.toARGB32() == Colors.red.toARGB32()) return 'Rojo';
    if (c.toARGB32() == Colors.magenta.toARGB32()) return 'Magenta';
    if (c.toARGB32() == Colors.purple.toARGB32()) return 'Morado';
    if (c.toARGB32() == Colors.blue.toARGB32()) return 'Azul';
    if (c.toARGB32() == Colors.teal.toARGB32()) return 'Verde azulado';
    if (c.toARGB32() == Colors.green.toARGB32()) return 'Verde';
    return 'Color';
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
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: isSelected
            ? Icon(FluentIcons.check_mark, size: 16, color: checkColor)
            : null,
      ),
    );
  }
}
