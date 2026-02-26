import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'empresa_provider.dart';
import '../offline/connectivity_service.dart';
import 'repository_provider.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// Item de modulo activo para la empresa actual.
class ModuloItem {
  const ModuloItem({
    required this.id,
    required this.nombre,
    required this.icono,
    required this.orden,
    required this.tipo,
  });

  final String id;
  final String nombre;
  final String icono;
  final int orden;
  final String tipo;

  factory ModuloItem.fromJson(Map<String, dynamic> json) {
    return ModuloItem(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      icono: json['icono'] as String? ?? 'apps',
      orden: json['orden'] as int? ?? 99,
      tipo: json['tipo'] as String? ?? 'core',
    );
  }
}

/// Modulo con su estado de activacion para la empresa actual.
class ModuloEstado {
  const ModuloEstado({
    required this.id,
    required this.nombre,
    required this.icono,
    required this.orden,
    required this.tipo,
    required this.habilitado,
  });

  final String id;
  final String nombre;
  final String icono;
  final int orden;
  final String tipo;
  final bool habilitado;

  factory ModuloEstado.fromJson(Map<String, dynamic> json) {
    return ModuloEstado(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      icono: json['icono'] as String? ?? 'apps',
      orden: json['orden'] as int? ?? 99,
      tipo: json['tipo'] as String? ?? 'core',
      habilitado: json['habilitado'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<ModuloItem> _buildModuloItems(
  List<Modulo> modulos,
  List<ModuloEmpresa> modulosEmpresa,
) {
  final enabledIds = modulosEmpresa
      .where((me) => me.habilitado)
      .map((me) => me.moduloId)
      .toSet();

  return modulos
      .where((m) => enabledIds.contains(m.id))
      .map((m) => ModuloItem(
            id: m.id,
            nombre: m.nombre,
            icono: m.icono ?? 'apps',
            orden: m.orden ?? 99,
            tipo: m.tipo,
          ))
      .toList()
    ..sort((a, b) => a.orden.compareTo(b.orden));
}

// ---------------------------------------------------------------------------
// Provider — módulos activos
// ---------------------------------------------------------------------------

/// Lista de modulos activos para la empresa y usuario actuales.
///
/// Patrón local-first + background sync:
/// 1. Emite desde SQLite (Brick) inmediatamente.
/// 2. Sincroniza en background desde Supabase.
/// 3. Emite datos actualizados.
final modulosActivosProvider = StreamProvider<List<ModuloItem>>((ref) async* {
  ref.watch(authStateProvider);
  final empresaId = ref.watch(empresaActivaIdProvider);

  // Web o sin empresa: RPC directa
  if (kIsWeb || empresaId == null) {
    if (empresaId == null) { yield const <ModuloItem>[]; return; }
    final client = ref.watch(supabaseClientProvider);
    try {
      final data = await client.rpc('get_modulos_activos');
      yield (data as List)
          .map((e) => ModuloItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      yield const <ModuloItem>[];
    }
    return;
  }

  final repo = ref.read(repositoryProvider);
  if (repo == null) { yield const <ModuloItem>[]; return; }

  // 1. Local primero — datos de SQLite inmediatamente
  try {
    final results = await Future.wait<dynamic>([
      repo.get<Modulo>(
        policy: OfflineFirstGetPolicy.localOnly,
        query: Query.where('activo', true),
      ),
      repo.get<ModuloEmpresa>(
        policy: OfflineFirstGetPolicy.localOnly,
        query: Query.where('empresaId', empresaId),
      ),
    ]);
    yield _buildModuloItems(
      results[0] as List<Modulo>,
      results[1] as List<ModuloEmpresa>,
    );
  } catch (_) {
    yield const <ModuloItem>[];
  }

  // 2. Background sync — Brick trae datos frescos de Supabase y actualiza SQLite
  try {
    final results = await Future.wait<dynamic>([
      repo.get<Modulo>(
        policy: OfflineFirstGetPolicy.awaitRemote,
        query: Query.where('activo', true),
      ),
      repo.get<ModuloEmpresa>(
        policy: OfflineFirstGetPolicy.awaitRemote,
        query: Query.where('empresaId', empresaId),
      ),
    ]);
    yield _buildModuloItems(
      results[0] as List<Modulo>,
      results[1] as List<ModuloEmpresa>,
    );
    ref.read(connectivityProvider.notifier).reportOnline();
  } catch (e) {
    if (isOfflineError(e)) {
      ref.read(connectivityProvider.notifier).reportOffline();
    }
  }
});

/// Todos los modulos del sistema con estado de activacion.
/// Usado en la pantalla de administracion de modulos.
/// Solo-online: requiere conectividad para datos frescos.
final todosModulosProvider = FutureProvider<List<ModuloEstado>>((ref) async {
  ref.watch(authStateProvider);
  ref.watch(empresaActivaIdProvider);

  final client = ref.watch(supabaseClientProvider);
  try {
    final data = await client.rpc('get_todos_modulos');
    return (data as List)
        .map((e) => ModuloEstado.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return const <ModuloEstado>[];
  }
});
