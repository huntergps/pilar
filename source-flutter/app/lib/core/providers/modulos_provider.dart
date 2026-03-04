import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';
import 'empresa_provider.dart';
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

  factory ModuloItem.fromBrick(Modulo m) {
    return ModuloItem(
      id: m.id,
      nombre: m.nombre,
      icono: m.icono ?? 'apps',
      orden: m.orden ?? 99,
      tipo: m.tipo,
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
// Provider — módulos activos
// ---------------------------------------------------------------------------

/// Lista de módulos activos para la empresa y usuario actuales.
///
/// - **Native**: Lee `Modulo` + `ModuloEmpresa` desde SQLite (Brick offline-first),
///   con sync en background desde Supabase.
/// - **Web**: RPC `get_modulos_activos` directa.
///
/// Suscripción Realtime a `modulo_empresas` para actualización automática
/// cuando el admin activa o desactiva un módulo.
final modulosActivosProvider = StreamProvider.autoDispose<List<ModuloItem>>((ref) {
  ref.watch(authStateProvider);
  final empresaId = ref.watch(empresaActivaIdProvider);

  if (empresaId == null) {
    return Stream.value(const <ModuloItem>[]);
  }

  final controller = StreamController<List<ModuloItem>>();

  Future<void> fetch() async {
    try {
      // Native: offline-first con Brick
      final repo = ref.read(repositoryProvider);
      if (!kIsWeb && repo != null) {
        final moduloEmpresas = await repo.get<ModuloEmpresa>(
          policy: OfflineFirstGetPolicy.awaitRemote,
          query: Query(where: [
            Where.exact('empresaId', empresaId),
            Where.exact('habilitado', true),
          ]),
        );
        if (moduloEmpresas.isNotEmpty) {
          final moduloIds = moduloEmpresas.map((me) => me.moduloId).toSet();
          final todosModulos = await repo.get<Modulo>(
            policy: OfflineFirstGetPolicy.localOnly,
            query: Query(where: [Where.exact('activo', true)]),
          );
          final activos = todosModulos
              .where((m) => moduloIds.contains(m.id) || m.tipo == 'infraestructura')
              .map(ModuloItem.fromBrick)
              .toList()
            ..sort((a, b) => a.orden.compareTo(b.orden));
          if (!controller.isClosed) controller.add(activos);
          return;
        }
      }

      // Web / fallback RPC
      final data = await Supabase.instance.client.rpc('get_modulos_activos');
      if (!controller.isClosed) {
        controller.add((data as List)
            .map((e) => ModuloItem.fromJson(e as Map<String, dynamic>))
            .toList());
      }
    } catch (_) {
      if (!controller.isClosed) controller.add(const []);
    }
  }

  fetch();

  // Realtime: re-fetch cuando se activa/desactiva un módulo
  final channel = Supabase.instance.client
      .channel('modulos_empresa_$empresaId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'modulo_empresas',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'empresa_id',
          value: empresaId,
        ),
        callback: (_) => fetch(),
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  return controller.stream;
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
