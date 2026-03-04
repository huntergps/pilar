import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/repository_provider.dart';

// ---------------------------------------------------------------------------
// Realtime — escucha cambios en usuarios_empresa e invitaciones_pendientes
// ---------------------------------------------------------------------------

/// Emite un entero incremental cada vez que `usuarios_empresa` o
/// `invitaciones_pendientes` cambian en Supabase Realtime.
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
final adminUsuariosProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authStateProvider);

  final data = await Supabase.instance.client.rpc('admin_get_usuarios');
  return (data as List).map((e) {
    final m = Map<String, dynamic>.from(e as Map);
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
// Roles provider — offline-first
// ---------------------------------------------------------------------------

/// Roles del sistema disponibles para asignar (excluye SUPER_ADMIN, SAAS_ADMIN).
///
/// - **Native**: Lee desde SQLite (Brick), filtra en Dart.
/// - **Web**: Query directa a tabla `roles`.
final rolesProvider =
    FutureProvider<List<({String id, String codigo, String nombre})>>((ref) async {
  ref.watch(authStateProvider);

  final empresaId = ref.watch(empresaActivaIdProvider);

  // Native: offline-first con Brick
  final repo = ref.read(repositoryProvider);
  if (!kIsWeb && repo != null) {
    try {
      final roles = await repo.get<Rol>(
        policy: OfflineFirstGetPolicy.awaitRemote,
        query: Query(where: [Where.exact('activo', true)]),
      );
      return roles
          .where((r) =>
              !['SUPER_ADMIN', 'SAAS_ADMIN'].contains(r.codigo) &&
              (r.empresaId == null || r.empresaId == empresaId))
          .map((r) => (id: r.id, codigo: r.codigo, nombre: r.nombre))
          .toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));
    } catch (_) {
      // fall through to direct query
    }
  }

  // Web fallback
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

// ---------------------------------------------------------------------------
// ModulosAdminNotifier — activar / desactivar módulos
// ---------------------------------------------------------------------------

/// Notifier para activar o desactivar módulos de la empresa.
///
/// Uso:
/// ```dart
/// final result = await ref.read(modulosAdminProvider.notifier)
///     .toggleModulo(moduloId: id, activar: true);
/// if (result.ok) { ref.invalidate(todosModulosProvider); }
/// ```
class ModulosAdminNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Activa o desactiva un módulo. Retorna `{ok: bool, error: String?}`.
  Future<({bool ok, String? error})> toggleModulo({
    required String moduloId,
    required bool activar,
  }) async {
    final rpc = activar ? 'admin_activate_module' : 'admin_deactivate_module';
    final result = await Supabase.instance.client
        .rpc(rpc, params: {'p_modulo_id': moduloId});

    if (result is Map && result['ok'] == true) {
      return (ok: true, error: null);
    }
    final error =
        result is Map ? result['error'] as String? : 'Error desconocido';
    return (ok: false, error: error ?? 'Error desconocido');
  }
}

final modulosAdminProvider =
    AsyncNotifierProvider<ModulosAdminNotifier, void>(ModulosAdminNotifier.new);
