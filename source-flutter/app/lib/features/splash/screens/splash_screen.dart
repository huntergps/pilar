import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/config/pilar_constants.dart';
import '../../../core/theme/pilar_breakpoints.dart';
import '../../../core/theme/pilar_spacing.dart';

/// Pantalla de arranque mostrada mientras [main] inicializa la app.
///
/// Layout idéntico al [LoginScreen]:
/// - Desktop (≥900px): contenido centrado en un [Card] de 440px, padding 32.
/// - Mobile/tablet: full width con 24px de padding horizontal.
///
/// Usa [micaBackgroundColor] (solidBackgroundFillColorBase, sólido) como
/// fondo para evitar transparencias del scaffoldBackgroundColor de fluent_ui,
/// que es layerOnAcrylicFillColorDefault — casi transparente (0x09ffffff).
class SplashScreen extends StatelessWidget {
  /// Mensaje de la operación actual (p.ej. "Conectando a Supabase…").
  final String status;

  /// Progreso de 0.0 a 1.0.
  final double progress;

  const SplashScreen({
    super.key,
    required this.status,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDesktop = context.isDesktop;

    return ColoredBox(
      // micaBackgroundColor = resources.solidBackgroundFillColorBase:
      //   light → Color(0xFFf3f3f3) | dark → Color(0xFF202020)  (100% opaco)
      color: theme.micaBackgroundColor,
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            // Misma restricción que LoginScreen
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 0 : 24,
                vertical: Spacing.xxl,
              ),
              child: isDesktop
                  ? _SplashContent(
                        theme: theme,
                        status: status,
                        progress: progress,
                    )
                  : _SplashContent(
                      theme: theme,
                      status: status,
                      progress: progress,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  final FluentThemeData theme;
  final String status;
  final double progress;

  const _SplashContent({
    required this.theme,
    required this.status,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Logo (mismo tamaño y estilo que LoginScreen) ────────────────────
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

        const SizedBox(height: Spacing.xl),

        // ── Barra de progreso ───────────────────────────────────────────────
        ProgressBar(
          value: progress * 100,
          strokeWidth: 3,
        ),

        const SizedBox(height: Spacing.ms),

        // ── Texto de estado ─────────────────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            status,
            key: ValueKey(status),
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: Spacing.xs),

        // ── Versión / subtítulo (igual que el footer del login) ─────────────
        Text(
          kAppName,
          style: theme.typography.caption?.copyWith(
            color: theme.resources.textFillColorDisabled,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
