import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/usuario_provider.dart';
import '../../features/notificaciones/providers/notificaciones_provider.dart';
import '../../features/notificaciones/widgets/notificaciones_dialog.dart';

/// The right-hand side of the [TitleBar] inside [PilarShell].
///
/// Contains, from left to right:
/// - Notification bell [IconButton] with an unread-count dot badge.
/// - User avatar + display name with a chevron (future: flyout user menu).
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

  // ---- User menu (future flyout) ------------------------------------------

  void _openUserMenu(BuildContext context) {
    // TODO: open flyout with profile / switch empresa / sign out actions.
    // Awaiting FlyoutTarget wiring — currently a no-op placeholder.
    // ignore: avoid_returning_null_for_void
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final usuario = ref.watch(usuarioActualProvider);
    final badgeCount = ref.watch(notificacionesBadgeProvider).valueOrNull ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
