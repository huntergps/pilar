import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Datos del usuario autenticado actualmente.
///
/// Se construye directamente desde el JWT (Session) para no requerir
/// una llamada de red adicional en el inicio de la app.
class UsuarioActual {
  const UsuarioActual({
    required this.id,
    required this.email,
    this.nombre,
    this.avatarUrl,
    required this.rolCodigo,
    required this.rolNombre,
  });

  final String id;
  final String email;

  /// Nombre completo del usuario extraido de userMetadata.
  final String? nombre;

  /// URL del avatar del usuario (puede ser null).
  final String? avatarUrl;

  /// Codigo del rol asignado en la empresa activa, p.ej. "ADMIN".
  final String rolCodigo;

  /// Nombre legible del rol, p.ej. "Administrador".
  final String rolNombre;

  factory UsuarioActual.fromSession(Session session) {
    return UsuarioActual(
      id: session.user.id,
      email: session.user.email ?? '',
      nombre: session.user.userMetadata?['nombre_completo'] as String?,
      avatarUrl: session.user.userMetadata?['avatar_url'] as String?,
      rolCodigo:
          session.user.appMetadata['rol_codigo'] as String? ?? 'LECTURA',
      rolNombre:
          session.user.appMetadata['rol_nombre'] as String? ?? 'Lectura',
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Usuario autenticado actualmente.
/// Null cuando no hay sesion activa.
final usuarioActualProvider = Provider<UsuarioActual?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return UsuarioActual.fromSession(session);
});

/// Verifica si el usuario tiene un permiso especifico.
///
/// Los permisos se leen del campo `permisos` en appMetadata del JWT.
///
/// Uso:
/// ```dart
/// final puedeFacturar = ref.watch(hasPermissionProvider('facturacion.crear'));
/// ```
final hasPermissionProvider =
    Provider.family<bool, String>((ref, permiso) {
  final session = ref.watch(sessionProvider);
  if (session == null) return false;
  final permisos =
      session.user.appMetadata['permisos'] as List<dynamic>? ?? const [];
  return permisos.contains(permiso);
});
