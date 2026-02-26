import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Realtime — escucha cambios en usuarios_empresa e invitaciones_pendientes
// ---------------------------------------------------------------------------

/// Emite un entero incremental cada vez que `usuarios_empresa` o
/// `invitaciones_pendientes` cambian en Supabase Realtime.
///
/// [UsuariosScreen] escucha este provider con `ref.listen` para invalidar
/// [adminUsuariosProvider] automáticamente sin que el usuario refresque.
final adminUsuariosRealtimeProvider = StreamProvider<int>((ref) {
  final ctrl = StreamController<int>();
  var counter = 0;

  void notify(PostgresChangePayload payload) {
    if (!ctrl.isClosed) ctrl.add(++counter);
  }

  final channel = Supabase.instance.client
      .channel('pilar-admin-usuarios')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'usuarios_empresa',
        callback: notify,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'invitaciones_pendientes',
        callback: notify,
      )
      .subscribe();

  ref.onDispose(() {
    Supabase.instance.client.removeChannel(channel);
    ctrl.close();
  });

  return ctrl.stream;
});

// ---------------------------------------------------------------------------
// Usuarios admin provider
// ---------------------------------------------------------------------------

/// Lista de usuarios de la empresa activa vía RPC `admin_get_usuarios`.
///
/// Incluye tanto usuarios con membresía confirmada como invitaciones pendientes
/// (campo `invitacion_estado != null`).
///
/// Se invalida automáticamente cuando [adminUsuariosRealtimeProvider] emite
/// un evento, y también cuando el estado de auth cambia.
final adminUsuariosProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authStateProvider);

  final data = await Supabase.instance.client.rpc('admin_get_usuarios');
  return (data as List).map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    // Normaliza roles: siempre List<Map<String, dynamic>>
    final rawRoles = m['roles'];
    if (rawRoles is List) {
      m['roles'] = rawRoles
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } else {
      m['roles'] = <Map<String, dynamic>>[];
    }
    return m;
  }).toList();
});

// ---------------------------------------------------------------------------
// Roles provider
// ---------------------------------------------------------------------------

/// Roles del sistema disponibles para asignar (excluye SUPER_ADMIN, SAAS_ADMIN).
final rolesProvider =
    FutureProvider<List<({String id, String codigo, String nombre})>>((ref) async {
  ref.watch(authStateProvider);

  final data = await Supabase.instance.client
      .from('roles')
      .select('id, codigo, nombre')
      .filter('empresa_id', 'is', null)
      .eq('activo', true)
      .order('nombre');

  return (data as List)
      .map((e) => (
            id: e['id'] as String,
            codigo: e['codigo'] as String,
            nombre: e['nombre'] as String,
          ))
      .where((r) => !['SUPER_ADMIN', 'SAAS_ADMIN'].contains(r.codigo))
      .toList();
});
