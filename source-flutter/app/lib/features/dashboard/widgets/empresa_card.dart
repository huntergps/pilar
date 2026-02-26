import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/providers/empresa_provider.dart';

// ---------------------------------------------------------------------------
// Card principal
// ---------------------------------------------------------------------------

/// Card moderna que resume la identidad de la empresa activa en el dashboard.
///
/// Destaca el **nombre comercial** como titular. Si no existe nombre comercial
/// muestra el nombre legal en su lugar. Cuando ambos difieren, el nombre legal
/// aparece en secundario debajo del titular.
///
/// Incluye: RUC (si existe), moneda funcional, teléfono y email.
class EmpresaCard extends StatelessWidget {
  final EmpresaConfig empresa;

  const EmpresaCard({super.key, required this.empresa});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    final String nombreComercial =
        empresa.nombreComercial?.trim().isNotEmpty == true
            ? empresa.nombreComercial!.trim()
            : empresa.nombre;

    final bool mostrarLegal =
        empresa.nombreComercial?.trim().isNotEmpty == true &&
            empresa.nombreComercial!.trim() != empresa.nombre.trim();

    final bool tieneContacto =
        empresa.telefono != null || empresa.email != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Card(
        padding: EdgeInsets.zero,
        // NOTE: No usar IntrinsicHeight aquí — es incompatible con LayoutBuilder.
        // Se usa Column (mainAxisSize.min) para la franja superior de acento.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Franja de acento (3 px en la parte superior) ----
              Container(height: 3, color: theme.accentColor),

              // ---- Contenido ----
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                child: LayoutBuilder(builder: (ctx, constraints) {
                  final logoSize = constraints.maxWidth < 480 ? 52.0 : 68.0;
                  final gap = constraints.maxWidth < 480 ? 14.0 : 20.0;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ---- Logo / Iniciales ----
                      _LogoAvatar(
                        logoUrl: empresa.logoUrl,
                        nombre: nombreComercial,
                        size: logoSize,
                      ),

                      SizedBox(width: gap),

                      // ---- Info ----
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Nombre comercial — titular principal
                            Text(
                              nombreComercial,
                              style: (theme.typography.titleLarge ??
                                      theme.typography.title)
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),

                            // Nombre legal — solo si difiere del comercial
                            if (mostrarLegal) ...[
                              const SizedBox(height: 2),
                              Text(
                                empresa.nombre,
                                style: theme.typography.caption?.copyWith(
                                  color: theme.inactiveColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],

                            const SizedBox(height: 10),

                            // Chips: RUC + Moneda
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (empresa.ruc != null)
                                  _MetaChip(
                                      label: 'RUC', value: empresa.ruc!),
                                _MetaChip(
                                    label: 'Moneda',
                                    value: empresa.monedaFuncional),
                              ],
                            ),

                            // Contacto: teléfono + email
                            if (tieneContacto) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 16,
                                runSpacing: 4,
                                children: [
                                  if (empresa.telefono != null)
                                    _ContactItem(
                                      icon: FluentIcons.phone,
                                      label: empresa.telefono!,
                                      theme: theme,
                                    ),
                                  if (empresa.email != null)
                                    _ContactItem(
                                      icon: FluentIcons.mail,
                                      label: empresa.email!,
                                      theme: theme,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logo / Iniciales
// ---------------------------------------------------------------------------

class _LogoAvatar extends StatelessWidget {
  final String? logoUrl;
  final String nombre;
  final double size;

  const _LogoAvatar({
    required this.logoUrl,
    required this.nombre,
    required this.size,
  });

  String get _initials {
    final words = nombre.trim().split(RegExp(r'[\s\-]+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    final s = nombre.trim();
    return s.substring(0, s.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    if (logoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          logoUrl!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildInitials(theme),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _buildInitials(theme),
        ),
      );
    }
    return _buildInitials(theme);
  }

  Widget _buildInitials(FluentThemeData theme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.accentColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: theme.accentColor,
            fontSize: size * 0.33,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chip de metadato (RUC, Moneda)
// ---------------------------------------------------------------------------

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        '$label: $value',
        style: theme.typography.caption?.copyWith(
          color: theme.accentColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item de contacto (teléfono, email)
// ---------------------------------------------------------------------------

class _ContactItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final FluentThemeData theme;

  const _ContactItem({
    required this.icon,
    required this.label,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.inactiveColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
