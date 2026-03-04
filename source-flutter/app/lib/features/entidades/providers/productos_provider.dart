import 'package:brick_core/query.dart';
import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
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
  Future<List<Map<String, dynamic>>> fetchData({bool awaitRemote = false}) async {
    // Plataformas nativas: Brick lee desde SQLite (caché offline) y sincroniza
    // con Supabase en segundo plano. Cuando awaitRemote=true (cambio Realtime),
    // forzamos una lectura remota para reflejar el cambio en el caché local.
    if (!kIsWeb && PilarRepository.isInitialized) {
      final policy = awaitRemote
          ? OfflineFirstGetPolicy.awaitRemote
          : OfflineFirstGetPolicy.localOnly;
      final models = await PilarRepository.instance.get<Producto>(
        query: Query.where('activo', true),
        policy: policy,
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

// ---------------------------------------------------------------------------
// productoBusquedaProvider — búsqueda fuzzy server-side (para pickers)
// ---------------------------------------------------------------------------

/// Busca productos por texto libre usando pg_trgm en el servidor.
/// Familia por query string — retorna lista vacía si query < 2 chars.
///
/// Uso en picker:
/// ```dart
/// final results = await ref.read(productoBusquedaProvider(
///   (query: texto, tipo: 'producto')).future);
/// ```
final productoBusquedaProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String query, String? tipo})>(
  (ref, params) async {
    if (params.query.length < 2) return const [];
    final data = await Supabase.instance.client.rpc(
      'entidades_buscar_productos',
      params: {
        'p_query': params.query,
        'p_tipo': params.tipo ?? 'todos',
        'p_solo_activos': true,
        'p_limit': 20,
        'p_offset': 0,
      },
    );
    return (data as List).cast<Map<String, dynamic>>();
  },
);
