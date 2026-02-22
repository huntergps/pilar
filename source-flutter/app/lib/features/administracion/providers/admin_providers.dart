import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Usuarios admin provider
// ---------------------------------------------------------------------------

/// Lista de usuarios de la empresa activa obtenida via RPC `admin_get_usuarios`.
///
/// Devuelve cada usuario como [Map<String, dynamic>] con los campos:
/// - `email`          — correo electronico
/// - `nombre`         — nombre completo
/// - `rol_nombre`     — nombre del rol asignado
/// - `activo`         — bool, si la cuenta esta activa
/// - `ultimo_acceso`  — ISO 8601 string con la fecha del ultimo acceso
///
/// Se invalida automaticamente cuando cambia la sesion.
final adminUsuariosProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authStateProvider);

  final data =
      await Supabase.instance.client.rpc('admin_get_usuarios');
  return (data as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
});
