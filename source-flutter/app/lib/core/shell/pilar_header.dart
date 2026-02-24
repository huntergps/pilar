import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/alertas_provider.dart';
import '../providers/usuario_provider.dart';
import '../router/app_router.dart';
import '../../features/alertas/widgets/alertas_panel.dart';
import '../../features/notificaciones/providers/notificaciones_provider.dart';
import '../../features/notificaciones/widgets/notificaciones_dialog.dart';

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
    final badgeCount = ref.watch(notificacionesBadgeProvider).valueOrNull ?? 0;
    final alertasCount = ref.watch(alertasCountProvider).valueOrNull ?? 0;
    final alertas = ref.watch(alertasActivasProvider).valueOrNull ?? [];

    // Determina el color del icono de alertas según la severidad más alta.
    final alertaColor = alertas.any((a) => a.severidad == 'critical' || a.severidad == 'error')
        ? Colors.errorPrimaryColor
        : const Color(0xFFF59E0B);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ---- Alert icon — solo visible cuando hay alertas activas ----
        if (alertasCount > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
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
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
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
          padding: const EdgeInsetsDirectional.only(end: 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(FluentIcons.ringer),
                onPressed: () => _openNotificationsDialog(context),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
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

        // ---- User avatar + name ----
        if (usuario != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FlyoutTarget(
              controller: _userMenuController,
              child: HoverButton(
                onPressed: () => _openUserMenu(context),
                builder: (context, states) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Avatar circle — first letter of email on accent bg.
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: theme.accentColor,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          usuario.email.isNotEmpty
                              ? usuario.email[0].toUpperCase()
                              : '?',
                          style: theme.typography.caption?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Display name or email.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          usuario.nombre ?? usuario.email,
                          style: theme.typography.caption,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        FluentIcons.chevron_down,
                        size: 8,
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ],
                  ),
                ),
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

    Future<void> signOut() async {
      Navigator.of(flyoutCtx).maybePop();
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) context.go(PilarRoutes.login);
    }

    void switchEmpresa() {
      Navigator.of(flyoutCtx).maybePop();
      if (context.mounted) context.go(PilarRoutes.selectEmpresa);
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.accentColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (usuario?.email ?? '?')[0].toUpperCase(),
                      style: theme.typography.bodyStrong
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (usuario?.nombre != null)
                          Text(
                            usuario!.nombre!,
                            style: theme.typography.bodyStrong,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          usuario?.email ?? '',
                          style: theme.typography.caption
                              ?.copyWith(color: theme.inactiveColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          usuario?.rolNombre ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // ---- Switch empresa ----
            HoverButton(
              onPressed: switchEmpresa,
              builder: (ctx, states) => Container(
                color: states.isHovered
                    ? theme.resources.subtleFillColorSecondary
                    : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(FluentIcons.company_directory,
                        size: 16, color: theme.inactiveColor),
                    const SizedBox(width: 10),
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(FluentIcons.sign_out,
                        size: 16,
                        color: theme.resources.systemFillColorCritical),
                    const SizedBox(width: 10),
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
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
