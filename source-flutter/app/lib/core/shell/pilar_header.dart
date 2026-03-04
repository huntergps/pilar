import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/alertas_provider.dart';
import '../providers/auth_actions_provider.dart';
import '../providers/perfil_provider.dart';
import '../providers/presencia_provider.dart';
import '../providers/sync_count_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/usuario_provider.dart';
import '../router/app_router.dart';
import '../../features/alertas/widgets/alertas_panel.dart';
import '../../features/notificaciones/providers/notificaciones_provider.dart';
import '../../features/notificaciones/widgets/notificaciones_dialog.dart';
import '../../features/perfil/screens/perfil_screen.dart'
    show PerfilDialog, CambiarContrasenaDialog;
import '../widgets/user_card.dart';
import '../../core/theme/pilar_spacing.dart';

export '../providers/sync_count_provider.dart' show pendingSyncCountProvider;

/// The right-hand side of the [TitleBar] inside [PilarShell].
///
/// Contains, from left to right:
/// - Alert icon [IconButton] — visible only when there are active company alerts.
/// - Notification bell [IconButton] with an unread-count dot badge.
/// - User avatar + display name with a chevron (flyout user menu).
/// - Window control buttons ([WindowButtons]) on Windows only.
///
/// [isDesktop] is passed from [PilarShell] to avoid re-computing
/// the Platform check on every build.
class PilarHeader extends ConsumerStatefulWidget {
  /// Whether the current platform is Windows / macOS / Linux.
  final bool isDesktop;

  const PilarHeader({super.key, required this.isDesktop});

  @override
  ConsumerState<PilarHeader> createState() => _PilarHeaderState();
}

class _PilarHeaderState extends ConsumerState<PilarHeader> {
  /// Controller for the user-menu flyout.
  ///
  /// Stored in state so it is not re-created on every [build] call.
  final FlyoutController _userMenuController = FlyoutController();

  @override
  void dispose() {
    _userMenuController.dispose();
    super.dispose();
  }

  // ---- Notification bell ---------------------------------------------------

  void _openNotificationsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const NotificacionesDialog(),
    );
  }

  // ---- User menu flyout -----------------------------------------------------

  void _openUserMenu(BuildContext context) {
    _userMenuController.showFlyout(
      builder: (ctx) => _UserMenuFlyout(context: context),
    );
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final usuario = ref.watch(usuarioActualProvider);
    final perfil = ref.watch(perfilUsuarioProvider).valueOrNull;
    final badgeCount = ref.watch(notificacionesBadgeProvider).valueOrNull ?? 0;
    final alertasCount = ref.watch(alertasCountProvider).valueOrNull ?? 0;
    final alertas = ref.watch(alertasActivasProvider).valueOrNull ?? [];
    final pendingSync = ref.watch(pendingSyncCountProvider);

    // Determina el color del icono de alertas según la severidad más alta.
    final alertaColor = alertas.any((a) => a.severidad == 'critical' || a.severidad == 'error')
        ? Colors.errorPrimaryColor
        : const Color(0xFFF59E0B);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ---- Sync badge — solo visible cuando hay cambios pendientes ----
        if (pendingSync > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Spacing.xs),
            child: Tooltip(
              message: '$pendingSync ${pendingSync == 1 ? 'cambio pendiente' : 'cambios pendientes'} de sincronización',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(FluentIcons.sync),
                    onPressed: () => context.go(PilarRoutes.adminSyncLog),
                  ),
                  Positioned(
                    right: Spacing.xs,
                    top: Spacing.xs,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.xs, vertical: Spacing.xxs),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$pendingSync',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ---- Alert icon — solo visible cuando hay alertas activas ----
        if (alertasCount > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Spacing.xs),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: Icon(
                    FluentIcons.shield_alert,
                    color: alertaColor,
                  ),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertasPanel(),
                  ),
                ),
                Positioned(
                  right: Spacing.xs,
                  top: Spacing.xs,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.xs, vertical: Spacing.xxs),
                    decoration: BoxDecoration(
                      color: alertaColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$alertasCount',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ---- Notification bell with unread-count dot ----
        Padding(
          padding: const EdgeInsetsDirectional.only(end: Spacing.xs),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(FluentIcons.ringer),
                onPressed: () => _openNotificationsDialog(context),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: Spacing.sm,
                  top: Spacing.sm,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ---- Theme toggle ----
        Tooltip(
          message: FluentTheme.of(context).brightness == Brightness.dark
              ? 'Cambiar a tema claro'
              : 'Cambiar a tema oscuro',
          child: IconButton(
            icon: Icon(
              FluentTheme.of(context).brightness == Brightness.dark
                  ? FluentIcons.sunny
                  : FluentIcons.clear_night,
              size: 20,
            ),
            onPressed: () {
              final current = ref.read(appConfigProvider).themeMode;
              ref.read(appConfigProvider.notifier).setThemeMode(
                    current == ThemeMode.dark
                        ? ThemeMode.light
                        : ThemeMode.dark,
                  );
            },
          ),
        ),

        // ---- User avatar + estado + chevron ----
        if (usuario != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Spacing.sm),
            child: FlyoutTarget(
              controller: _userMenuController,
              child: HoverButton(
                onPressed: () => _openUserMenu(context),
                builder: (context, states) {
                  final estado = ref.watch(estadoPresenciaProvider);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: states.isHovered
                          ? theme.resources.subtleFillColorSecondary
                          : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HeaderAvatar(
                          avatarUrl: perfil?.avatarUrl,
                          initial: perfil?.initial ??
                              (usuario.email.isNotEmpty
                                  ? usuario.email[0].toUpperCase()
                                  : '?'),
                          size: 28,
                          theme: theme,
                          estado: estado,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Text(
                          perfil != null && perfil.displayName.isNotEmpty
                              ? perfil.displayName
                              : usuario.email,
                          style: theme.typography.caption?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: Spacing.xs),
                        Icon(
                          FluentIcons.chevron_down,
                          size: 8,
                          color: theme.resources.textFillColorSecondary,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Window control buttons (Windows only)
// ---------------------------------------------------------------------------

/// Custom minimize / maximize / close buttons for Windows.
///
/// macOS provides its own native traffic-light controls; Linux and web
/// do not need this widget. [PilarShell] renders this only on Windows.
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minimize
        IconButton(
          icon: const Icon(FluentIcons.chrome_minimize, size: 10),
          onPressed: windowManager.minimize,
        ),
        // Maximize / restore
        IconButton(
          icon: const Icon(FluentIcons.toggle_filled, size: 10),
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        // Close
        IconButton(
          icon: const Icon(FluentIcons.chrome_close, size: 10),
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// User menu flyout
// ---------------------------------------------------------------------------

class _UserMenuFlyout extends ConsumerWidget {
  /// Shell [BuildContext] — used for navigation (go_router).
  final BuildContext context;

  const _UserMenuFlyout({required this.context});

  @override
  Widget build(BuildContext flyoutCtx, WidgetRef ref) {
    final theme = FluentTheme.of(flyoutCtx);
    final usuario = ref.watch(usuarioActualProvider);
    final perfil = ref.watch(perfilUsuarioProvider).valueOrNull;
    final estadoActual = ref.watch(estadoPresenciaProvider);

    final displayName = perfil?.displayName ?? usuario?.nombre ?? usuario?.email ?? '';

    Future<void> signOut() async {
      Navigator.of(flyoutCtx).maybePop();
      await ref.read(authActionsProvider.notifier).signOut();
      if (context.mounted) context.go(PilarRoutes.login);
    }

    void switchEmpresa() {
      Navigator.of(flyoutCtx).maybePop();
      if (context.mounted) context.go(PilarRoutes.selectEmpresa);
    }

    void goToPerfil() {
      Navigator.of(flyoutCtx).maybePop();
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => PerfilDialog(
            onVerPerfilCompleto: () {
              if (context.mounted) context.go(PilarRoutes.perfil);
            },
          ),
        );
      }
    }

    void changePassword() {
      Navigator.of(flyoutCtx).maybePop();
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => const CambiarContrasenaDialog(),
        );
      }
    }

    return FlyoutContent(
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- User info header ----
            UserCard(
              nombre: displayName.isNotEmpty ? displayName : (usuario?.email ?? ''),
              email: displayName.isNotEmpty ? (usuario?.email ?? '') : null,
              sublabel: usuario?.rolNombre,
              avatarUrl: perfil?.avatarUrl,
              avatarRadius: 18,
              padding: const EdgeInsets.all(Spacing.md),
            ),
            const Divider(),

            // ---- Selector de estado de presencia ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: EstadoPresencia.values.map((estado) {
                  final seleccionado = estadoActual == estado;
                  return HoverButton(
                    onPressed: () {
                      ref.read(estadoPresenciaProvider.notifier).state = estado;
                      Navigator.of(flyoutCtx).maybePop();
                    },
                    builder: (ctx, states) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm, vertical: Spacing.sm),
                      decoration: BoxDecoration(
                        color: seleccionado
                            ? theme.accentColor.withValues(alpha: 0.12)
                            : states.isHovered
                                ? theme.resources.subtleFillColorSecondary
                                : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: estado.color,
                            ),
                          ),
                          const SizedBox(width: Spacing.ms),
                          Text(
                            estado.label,
                            style: theme.typography.body?.copyWith(
                              fontWeight: seleccionado
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          const Spacer(),
                          if (seleccionado)
                            Icon(FluentIcons.check_mark,
                                size: 12, color: theme.accentColor),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(),

            // ---- Cambiar contraseña ----
            HoverButton(
              onPressed: changePassword,
              builder: (ctx, states) => Container(
                color: states.isHovered
                    ? theme.resources.subtleFillColorSecondary
                    : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.ms),
                child: Row(
                  children: [
                    Icon(FluentIcons.lock,
                        size: 16, color: theme.inactiveColor),
                    const SizedBox(width: Spacing.ms),
                    Text('Cambiar contraseña',
                        style: theme.typography.body),
                  ],
                ),
              ),
            ),

            // ---- Mi perfil ----
            HoverButton(
              onPressed: goToPerfil,
              builder: (ctx, states) => Container(
                color: states.isHovered
                    ? theme.resources.subtleFillColorSecondary
                    : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.ms),
                child: Row(
                  children: [
                    Icon(FluentIcons.contact,
                        size: 16, color: theme.inactiveColor),
                    const SizedBox(width: Spacing.ms),
                    Text('Mi perfil', style: theme.typography.body),
                  ],
                ),
              ),
            ),

            // ---- Switch empresa ----
            HoverButton(
              onPressed: switchEmpresa,
              builder: (ctx, states) => Container(
                color: states.isHovered
                    ? theme.resources.subtleFillColorSecondary
                    : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.ms),
                child: Row(
                  children: [
                    Icon(FluentIcons.company_directory,
                        size: 16, color: theme.inactiveColor),
                    const SizedBox(width: Spacing.ms),
                    Text('Cambiar empresa',
                        style: theme.typography.body),
                  ],
                ),
              ),
            ),

            const Divider(),

            // ---- Sign out ----
            HoverButton(
              onPressed: signOut,
              builder: (ctx, states) => Container(
                color: states.isHovered
                    ? theme.resources.subtleFillColorSecondary
                    : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.ms),
                child: Row(
                  children: [
                    Icon(FluentIcons.sign_out,
                        size: 16,
                        color: theme.resources.systemFillColorCritical),
                    const SizedBox(width: Spacing.ms),
                    Text(
                      'Cerrar sesión',
                      style: theme.typography.body?.copyWith(
                        color: theme.resources.systemFillColorCritical,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget compartido: avatar con foto o inicial
// ---------------------------------------------------------------------------

class _HeaderAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  final double size;
  final FluentThemeData theme;
  final EstadoPresencia estado;

  const _HeaderAvatar({
    required this.avatarUrl,
    required this.initial,
    required this.size,
    required this.theme,
    required this.estado,
  });

  @override
  Widget build(BuildContext context) {
    // Dot ocupa ~35% del avatar, con margen para borde blanco.
    final dotSize = (size * 0.35).clamp(8.0, 14.0);
    // SizedBox ligeramente mayor para que el dot no quede recortado.
    final totalSize = size + dotSize * 0.5;

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.accentColor,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _Initial(initial: initial, size: size, theme: theme),
            )
          : _Initial(initial: initial, size: size, theme: theme),
    );

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: avatar),
          Positioned(
            right: Spacing.none,
            bottom: Spacing.none,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: estado.color,
                border: Border.all(
                  color: theme.micaBackgroundColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String initial;
  final double size;
  final FluentThemeData theme;

  const _Initial({
    required this.initial,
    required this.size,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: (size >= 32 ? theme.typography.bodyStrong : theme.typography.caption)
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}
