import 'package:brick_core/query.dart';
import 'package:brick_gen/brick_gen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/brick_data_provider.dart';

// ---------------------------------------------------------------------------
// ProductosBrickNotifier — lista offline-first con Realtime
// ---------------------------------------------------------------------------

class ProductosBrickNotifier extends BrickDataNotifier {
  @override
  String get supabaseTable => 'productos';

  @override
  Future<List<Map<String, dynamic>>> fetchData() async {
    // Plataformas nativas: Brick lee desde SQLite (caché offline) y sincroniza
    // con Supabase en segundo plano.
    if (!kIsWeb && PilarRepository.isInitialized) {
      final models = await PilarRepository.instance.get<Producto>(
        query: Query.where('activo', true),
      );
      return models.map((p) => p.toMap()).toList()
        ..sort((a, b) =>
            (a['nombre'] as String).compareTo(b['nombre'] as String));
    }

    // Web / fallback: llamada directa a Supabase (no hay SQLite en web)
    final data = await Supabase.instance.client
        .from(supabaseTable)
        .select('id, codigo, nombre, tipo, precio_venta, precio_costo, descripcion, activo')
        .eq('activo', true)
        .order('nombre');
    return List<Map<String, dynamic>>.from(data as List);
  }
}

final productosProvider = AsyncNotifierProvider.autoDispose<
    ProductosBrickNotifier, List<Map<String, dynamic>>>(
  ProductosBrickNotifier.new,
);
