import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';

// ---------------------------------------------------------------------------
// Internal data model
// ---------------------------------------------------------------------------

/// Descriptor for a single admin hub card.
class _AdminSection {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  const _AdminSection(this.icon, this.title, this.subtitle, this.route);
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Administration hub screen.
///
/// Displays a Wrap grid of [_AdminCard] tiles, each navigating to a
/// sub-section of the admin area (Empresa, Usuarios, Módulos, Configuración).
class AdminPanelScreen extends ConsumerWidget {
  const AdminPanelScreen({super.key});

  static const _sections = [
    _AdminSection(
      FluentIcons.company_directory,
      'Empresa',
      'Datos, logo y branding',
      PilarRoutes.adminEmpresa,
    ),
    _AdminSection(
      FluentIcons.people,
      'Usuarios',
      'Gestionar accesos y roles',
      PilarRoutes.adminUsuarios,
    ),
    _AdminSection(
      FluentIcons.tiles,
      'Módulos',
      'Activar funcionalidades',
      PilarRoutes.adminModulos,
    ),
    _AdminSection(
      FluentIcons.settings,
      'Configuración',
      'Servidor y parámetros generales',
      PilarRoutes.adminConfiguracion,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Administración')),
      content: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children:
              _sections.map((s) => _AdminCard(section: s)).toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin card tile
// ---------------------------------------------------------------------------

class _AdminCard extends StatelessWidget {
  final _AdminSection section;

  const _AdminCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return SizedBox(
      width: 200,
      height: 160,
      child: Card(
        padding: EdgeInsets.zero,
        child: HoverButton(
          onPressed: () => context.push(section.route),
          builder: (ctx, states) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: states.isHovered
                  ? theme.accentColor.withValues(alpha: 0.08)
                  : null,
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    section.icon,
                    size: 22,
                    color: theme.accentColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(section.title, style: theme.typography.bodyStrong),
                const SizedBox(height: 4),
                Text(
                  section.subtitle,
                  style: theme.typography.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
