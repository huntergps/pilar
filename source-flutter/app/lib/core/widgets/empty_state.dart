import 'package:fluent_ui/fluent_ui.dart';

/// Estado vacío consistente para listas y pantallas sin contenido.
///
/// Uso:
/// ```dart
/// PilarEmptyState(message: 'No hay conversaciones')
/// PilarEmptyState(
///   icon: FluentIcons.inbox,
///   message: 'Bandeja vacía',
///   action: Button(child: Text('Crear'), onPressed: ...),
/// )
/// ```
class PilarEmptyState extends StatelessWidget {
  const PilarEmptyState({
    super.key,
    required this.message,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.action,
    this.iconSize = 48.0,
  });

  final String message;

  /// Texto secundario opcional bajo el mensaje principal.
  final String? subtitle;

  final IconData? icon;

  /// Color del ícono. Si es null, usa `theme.inactiveColor.withValues(alpha: 0.5)`.
  final Color? iconColor;

  final Widget? action;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? FluentIcons.inbox,
              size: iconSize,
              color: iconColor ?? theme.inactiveColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.typography.subtitle?.copyWith(color: theme.inactiveColor),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: theme.typography.body?.copyWith(
                    color: theme.resources.textFillColorSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
