import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class EcuadorProvincia {
  final int id;
  final String nombre;

  const EcuadorProvincia({required this.id, required this.nombre});

  factory EcuadorProvincia.fromJson(Map<String, dynamic> json) =>
      EcuadorProvincia(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
      );
}

class EcuadorCiudad {
  final int id;
  final int provinciaId;
  final String nombre;

  const EcuadorCiudad({
    required this.id,
    required this.provinciaId,
    required this.nombre,
  });

  factory EcuadorCiudad.fromJson(Map<String, dynamic> json) => EcuadorCiudad(
        id: (json['id'] as num).toInt(),
        provinciaId: (json['provincia_id'] as num).toInt(),
        nombre: json['nombre'] as String,
      );
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provincias de Ecuador ordenadas alfabéticamente.
/// Sin autoDispose: se cachean durante toda la sesión (datos estáticos).
final provinciasEcProvider = FutureProvider<List<EcuadorProvincia>>((ref) async {
  final data = await Supabase.instance.client
      .from('provincias')
      .select('id, nombre')
      .eq('pais_id', 1) // Ecuador
      .eq('activo', true)
      .order('nombre');
  return (data as List)
      .map((r) => EcuadorProvincia.fromJson(r as Map<String, dynamic>))
      .toList();
});

/// Ciudades de una provincia específica, ordenadas alfabéticamente.
/// Family por [provinciaId]. Sin autoDispose para cachear mientras navega.
final ciudadesPorProvinciaProvider =
    FutureProvider.family<List<EcuadorCiudad>, int>((ref, provinciaId) async {
  final data = await Supabase.instance.client
      .from('ciudades')
      .select('id, provincia_id, nombre')
      .eq('provincia_id', provinciaId)
      .eq('activo', true)
      .order('nombre');
  return (data as List)
      .map((r) => EcuadorCiudad.fromJson(r as Map<String, dynamic>))
      .toList();
});
