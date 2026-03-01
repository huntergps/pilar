import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// EstadoPresencia — estado global del usuario visible para otros
// ---------------------------------------------------------------------------

enum EstadoPresencia {
  online,
  ausente,
  ocupado,
  noComunicar;

  String get label => switch (this) {
        EstadoPresencia.online => 'En línea',
        EstadoPresencia.ausente => 'Ausente',
        EstadoPresencia.ocupado => 'Ocupado',
        EstadoPresencia.noComunicar => 'No molestar',
      };

  /// Color del punto de estado.
  Color get color => switch (this) {
        EstadoPresencia.online => Colors.successPrimaryColor,
        EstadoPresencia.ausente => const Color(0xFFF59E0B),  // amber
        EstadoPresencia.ocupado => Colors.errorPrimaryColor,
        EstadoPresencia.noComunicar => const Color(0xFF8B8B8B), // gris
      };

  /// Icono pequeño representativo.
  IconData get icon => switch (this) {
        EstadoPresencia.online => FluentIcons.circle_fill,
        EstadoPresencia.ausente => FluentIcons.away_status,
        EstadoPresencia.ocupado => FluentIcons.status_circle_block,
        EstadoPresencia.noComunicar => FluentIcons.status_circle_ring,
      };
}

/// Estado de presencia actual del usuario local.
/// Por defecto: [EstadoPresencia.online].
///
/// Este provider es leído por [PilarHeader] (punto en el avatar) y por
/// [PresenceNotifier] (se incluye en el payload de Supabase Presence para
/// que otros usuarios vean el estado real).
final estadoPresenciaProvider = StateProvider<EstadoPresencia>(
  (ref) => EstadoPresencia.online,
);
