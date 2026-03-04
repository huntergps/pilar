import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

class CuentaItem {
  final String id;
  final String nombre;
  final String tipo;
  final bool activo;
  final bool esDefecto;
  final Map<String, dynamic> configJson;
  final Map<String, dynamic> metaJson;
  final String? usuarioId;
  final String? usuarioNombre;
  final bool esPersonal;

  const CuentaItem({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.activo,
    required this.esDefecto,
    required this.configJson,
    this.metaJson = const {},
    this.usuarioId,
    this.usuarioNombre,
    required this.esPersonal,
  });

  /// true si el webhook de Telegram fue registrado exitosamente.
  bool get telegramWebhookOk =>
      tipo == 'telegram' && (metaJson['webhook_ok'] as bool? ?? false);

  factory CuentaItem.fromMap(Map<String, dynamic> m) {
    final uid = m['usuario_id'] as String?;
    return CuentaItem(
      id: m['id'] as String,
      nombre: m['nombre'] as String? ?? '',
      tipo: m['tipo'] as String? ?? '',
      activo: m['activo'] as bool? ?? false,
      esDefecto: m['es_defecto'] as bool? ?? false,
      configJson: (m['config_json'] as Map?)?.cast<String, dynamic>() ?? {},
      metaJson: (m['meta_json'] as Map?)?.cast<String, dynamic>() ?? {},
      usuarioId: uid,
      usuarioNombre: m['usuario_nombre'] as String?,
      esPersonal: m['es_personal'] as bool? ?? (uid != null),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider de lectura
// ---------------------------------------------------------------------------

final comCuentasProvider =
    FutureProvider.autoDispose<List<CuentaItem>>((ref) async {
  ref.watch(authStateProvider);
  try {
    final data = await Supabase.instance.client
        .rpc('com_get_todas_cuentas') as List;
    return data
        .cast<Map<String, dynamic>>()
        .map(CuentaItem.fromMap)
        .toList();
  } catch (_) {
    // Fallback: query directa (no admin o RPC no disponible)
    final session = Supabase.instance.client.auth.currentSession;
    final empresaId = session?.user.appMetadata['empresa_id'] as String?;
    final query = Supabase.instance.client
        .from('com_cuentas')
        .select('id, nombre, tipo, activo, es_defecto, config_json, meta_json, usuario_id');
    final data = (empresaId != null
            ? await query.eq('empresa_id', empresaId).order('nombre')
            : await query.order('nombre')) as List;
    return data
        .cast<Map<String, dynamic>>()
        .map(CuentaItem.fromMap)
        .toList();
  }
});

// ---------------------------------------------------------------------------
// CuentasComunicacionNotifier
//
// Wraps all write/mutation Supabase operations from
// cuentas_comunicacion_screen.dart.
// Read operations remain in comCuentasProvider (FutureProvider) in the screen.
// ---------------------------------------------------------------------------

class CuentasComunicacionNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  // ── Toggle activo ─────────────────────────────────────────────────────────

  Future<({bool ok, String? error})> toggleActivo({
    required String cuentaId,
    required bool nuevoValor,
  }) async {
    try {
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'activo': nuevoValor}).eq('id', cuentaId);
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Establecer como defecto ───────────────────────────────────────────────

  Future<({bool ok, String? error})> setDefecto({
    required String cuentaId,
    required String tipo,
  }) async {
    try {
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'es_defecto': false})
          .eq('tipo', tipo)
          .neq('id', cuentaId);
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'es_defecto': true, 'activo': true}).eq('id', cuentaId);
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Cambiar ownership (personal ↔ empresa) ────────────────────────────────

  Future<({bool ok, String? error})> cambiarOwnership({
    required String cuentaId,
    required String? userId,
  }) async {
    try {
      await Supabase.instance.client.rpc('com_set_cuenta_usuario', params: {
        'p_cuenta_id': cuentaId,
        'p_usuario_id': userId,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Eliminar cuenta ───────────────────────────────────────────────────────

  Future<({bool ok, String? error})> eliminarCuenta({
    required String cuentaId,
  }) async {
    try {
      await Supabase.instance.client
          .from('com_cuentas')
          .delete()
          .eq('id', cuentaId);
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Registrar webhook Telegram ────────────────────────────────────────────

  Future<({bool ok, String? error})> registrarWebhookTelegram({
    required String cuentaId,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'com-telegram-setup',
        body: {'account_id': cuentaId},
      );
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Guardar cuenta (crear o actualizar) ───────────────────────────────────

  Future<({bool ok, String? accountId, String? error})> guardarCuenta({
    required Map<String, dynamic> payload,
    String? cuentaIdExistente,
  }) async {
    try {
      if (cuentaIdExistente != null) {
        await Supabase.instance.client
            .from('com_cuentas')
            .update(payload)
            .eq('id', cuentaIdExistente);
        return (ok: true, accountId: cuentaIdExistente, error: null);
      } else {
        final result = await Supabase.instance.client
            .from('com_cuentas')
            .insert(payload)
            .select('id')
            .single();
        return (ok: true, accountId: result['id'] as String?, error: null);
      }
    } catch (e) {
      return (ok: false, accountId: null, error: e.toString());
    }
  }

  // ── Gestionar roles de cuenta ─────────────────────────────────────────────

  Future<({bool ok, String? error})> toggleRolCuenta({
    required String cuentaId,
    required String rolId,
    required bool agregar,
  }) async {
    try {
      if (agregar) {
        await Supabase.instance.client.from('com_cuentas_roles').insert({
          'cuenta_id': cuentaId,
          'rol_id': rolId,
        });
      } else {
        await Supabase.instance.client
            .from('com_cuentas_roles')
            .delete()
            .eq('cuenta_id', cuentaId)
            .eq('rol_id', rolId);
      }
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }
}

final cuentasComunicacionProvider =
    AsyncNotifierProvider<CuentasComunicacionNotifier, void>(
        CuentasComunicacionNotifier.new);

// ---------------------------------------------------------------------------
// Providers de roles — movidos desde cuentas_comunicacion_screen.dart
// ---------------------------------------------------------------------------

/// Roles asignados a una cuenta específica (acceso restringido por rol).
/// Retorna lista de maps con: rol_id, roles.nombre, roles.codigo.
final cuentaRolesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, cuentaId) async {
  final rows = await Supabase.instance.client
      .from('com_cuentas_roles')
      .select('rol_id, roles(nombre, codigo)')
      .eq('cuenta_id', cuentaId) as List;
  return rows.cast<Map<String, dynamic>>();
});

/// Todos los roles del sistema disponibles para asignar a cuentas.
final rolesEmpresaProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authStateProvider);
  final rows = await Supabase.instance.client
      .from('roles')
      .select('id, nombre, codigo')
      .filter('empresa_id', 'is', null)
      .order('nombre') as List;
  return rows.cast<Map<String, dynamic>>();
});
