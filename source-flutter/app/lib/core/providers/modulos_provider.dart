import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'empresa_provider.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// Item de modulo activo para la empresa actual.
///
/// [icono] es el nombre del icono como string (p.ej. "FluentIcons.home")
/// para que el shell lo resuelva en tiempo de ejecucion sin depender de
/// imports especificos del paquete fluent_ui aqui.
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

  /// Nombre del icono como string (p.ej. "home", "people", "money").
  /// El shell lo mapea a FluentIcons en tiempo de ejecucion.
  final String icono;

  /// Orden de aparicion en el menu de navegacion.
  final int orden;

  /// Categoria del modulo: 'infraestructura' | 'core' | 'auxiliar'.
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
/// Usado en la pantalla de administracion de modulos.
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

  /// Categoria: 'infraestructura' | 'core' | 'auxiliar'.
  final String tipo;

  /// true si el modulo esta activo para esta empresa.
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
// Provider
// ---------------------------------------------------------------------------

/// Lista de modulos activos para la empresa y usuario actuales.
///
/// Se invalida automaticamente al:
/// - Cambiar la sesion (authStateProvider).
/// - Cambiar la empresa activa (empresaActivaIdProvider).
final modulosActivosProvider = FutureProvider<List<ModuloItem>>((ref) async {
  ref.watch(authStateProvider);
  ref.watch(empresaActivaIdProvider);

  final client = ref.watch(supabaseClientProvider);
  try {
    final data = await client.rpc('get_modulos_activos');
    return (data as List)
        .map((e) => ModuloItem.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    // RPC no existe aún o error de red: mostrar shell vacío sin módulos dinámicos.
    return const <ModuloItem>[];
  }
});

/// Todos los modulos del sistema con estado de activacion para la empresa actual.
///
/// Usado en la pantalla de administracion de modulos para mostrar
/// y gestionar activaciones.
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
