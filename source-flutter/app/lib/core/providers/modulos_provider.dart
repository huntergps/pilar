import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';
import 'empresa_provider.dart';

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
// Provider — módulos activos
// ---------------------------------------------------------------------------

/// Lista de módulos activos para la empresa y usuario actuales.
///
/// Usa la RPC `get_modulos_activos` directamente (todas las plataformas):
/// - Infraestructura: siempre visibles.
/// - Core/auxiliar: solo si están habilitados para la empresa activa.
///
/// Suscripción Realtime a `modulo_empresas` para que la lista se actualice
/// automáticamente cuando el admin activa o desactiva un módulo sin necesidad
/// de que otros usuarios conectados recarguen la app.
final modulosActivosProvider = StreamProvider.autoDispose<List<ModuloItem>>((ref) {
  ref.watch(authStateProvider);
  final empresaId = ref.watch(empresaActivaIdProvider);

  if (empresaId == null) {
    return Stream.value(const <ModuloItem>[]);
  }

  final controller = StreamController<List<ModuloItem>>();

  Future<void> fetch() async {
    try {
      final data =
          await Supabase.instance.client.rpc('get_modulos_activos');
      if (!controller.isClosed) {
        controller.add((data as List)
            .map((e) => ModuloItem.fromJson(e as Map<String, dynamic>))
            .toList());
      }
    } catch (_) {
      if (!controller.isClosed) controller.add(const []);
    }
  }

  // Carga inicial
  fetch();

  // Realtime: re-fetch cuando se activa/desactiva un módulo para esta empresa
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
