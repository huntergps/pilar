import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connectivity_service.dart';
import '../../core/theme/pilar_spacing.dart';

/// Narrow banner shown at the top of the shell body when the app is offline.
///
/// Renders as a zero-height [SizedBox] when online, so it has no impact on
/// layout when connected.
class OfflineStatusBar extends ConsumerWidget {
  const OfflineStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(connectivityProvider);
    if (isOnline) return const SizedBox.shrink();

    final theme = FluentTheme.of(context);

    return Container(
      width: double.infinity,
      color: Colors.red.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(FluentIcons.plug_disconnected, size: 13, color: Colors.white),
          const SizedBox(width: Spacing.sm),
          Text(
            'Sin conexión · Mostrando datos guardados',
            style: theme.typography.caption?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
