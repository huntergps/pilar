import 'package:fluent_ui/fluent_ui.dart';

// =============================================================================
// UserCard — widget reutilizable: avatar circular + nombre + email/subtítulo
//
// Uso típico:
//   UserCard(nombre: 'Steven', email: 'huntergps79@yahoo.es', avatarUrl: url)
//
// Variantes:
//   - avatarRadius: 24 (default) para listas, 16 para items compactos
//   - leading: reemplaza el avatar por cualquier widget (ej. icono de canal)
//   - trailing: widget a la derecha (badge, botón, chip, etc.)
//   - sublabel: tercera línea bajo el email (ej. nombre del rol)
//   - isOnline: muestra punto verde de presencia sobre el avatar
//   - dimmed: opacidad reducida (usuarios inactivos)
//   - onTap: callback al tocar la fila
// =============================================================================

class UserCard extends StatelessWidget {
  const UserCard({
    super.key,
    required this.nombre,
    this.email,
    this.sublabel,
    this.avatarUrl,
    this.leading,
    this.avatarRadius = 24,
    this.trailing,
    this.onTap,
    this.isOnline = false,
    this.dimmed = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
  });

  /// Nombre de display (bodyStrong).
  final String nombre;

  /// Email u otro subtítulo (caption, inactiveColor). Null = no se muestra.
  final String? email;

  /// Tercera línea opcional bajo el email (ej. nombre del rol, accentColor).
  final String? sublabel;

  /// URL de foto de perfil. Null = muestra inicial del nombre.
  /// Ignorado si [leading] está presente.
  final String? avatarUrl;

  /// Reemplaza el avatar por un widget personalizado (ej. icono de canal).
  /// Cuando se usa, [avatarUrl], [avatarRadius] e [isOnline] no aplican.
  final Widget? leading;

  /// Radio del CircleAvatar. Default 24 (diámetro 48px).
  final double avatarRadius;

  /// Widget opcional al extremo derecho.
  final Widget? trailing;

  /// Callback al tocar. Null = no interactivo.
  final VoidCallback? onTap;

  /// Muestra un punto verde de presencia online sobre el avatar.
  final bool isOnline;

  /// Reduce la opacidad (usuario inactivo).
  final bool dimmed;

  /// Padding interno del tile.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // ---- Leading (avatar o widget personalizado) ----
    Widget leadingWidget;
    if (leading != null) {
      leadingWidget = leading!;
    } else {
      final inicial =
          nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : '?';

      Widget avatar = CircleAvatar(
        radius: avatarRadius,
        backgroundColor: theme.accentColor.withValues(alpha: 0.15),
        backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
            ? NetworkImage(avatarUrl!)
            : null,
        onBackgroundImageError:
            avatarUrl != null && avatarUrl!.isNotEmpty ? (_, __) {} : null,
        child: avatarUrl == null || avatarUrl!.isEmpty
            ? Text(
                inicial,
                style: theme.typography.bodyStrong?.copyWith(
                  fontSize: avatarRadius * 0.75,
                  color: theme.accentColor,
                ),
              )
            : null,
      );

      if (isOnline) {
        avatar = Stack(
          children: [
            avatar,
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: avatarRadius * 0.5,
                height: avatarRadius * 0.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.successPrimaryColor,
                  border: Border.all(color: theme.cardColor, width: 1.5),
                ),
              ),
            ),
          ],
        );
      }

      leadingWidget = avatar;
    }

    // ---- Contenido ----
    Widget content = Padding(
      padding: padding,
      child: Row(
        children: [
          leadingWidget,
          SizedBox(width: leading != null ? 10 : avatarRadius * 0.5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nombre,
                  style: theme.typography.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
                if (email != null && email!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email!,
                    style: theme.typography.caption
                        ?.copyWith(color: theme.inactiveColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (sublabel != null && sublabel!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    sublabel!,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.accentColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    if (dimmed) {
      content = Opacity(opacity: 0.45, child: content);
    }

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return content;
  }
}
