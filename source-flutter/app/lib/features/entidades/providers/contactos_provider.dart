import 'package:brick_core/query.dart';
import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/brick_data_provider.dart';

// ---------------------------------------------------------------------------
// ContactosBrickNotifier — lista offline-first con Realtime
// ---------------------------------------------------------------------------

class ContactosBrickNotifier extends BrickDataNotifier {
  @override
  String get supabaseTable => 'contactos';

  @override
  Future<List<Map<String, dynamic>>> fetchData({bool awaitRemote = false}) async {
    // Plataformas nativas: Brick lee desde SQLite (caché offline) y sincroniza
    // con Supabase en segundo plano. Cuando awaitRemote=true (cambio Realtime),
    // forzamos una lectura remota para reflejar el cambio en el caché local.
    if (!kIsWeb && PilarRepository.isInitialized) {
      final policy = awaitRemote
          ? OfflineFirstGetPolicy.awaitRemote
          : OfflineFirstGetPolicy.localOnly;
      final models = await PilarRepository.instance.get<Contacto>(
        query: Query.where('activo', true),
        policy: policy,
      );
      return models.map((c) => c.toMap()).toList()
        ..sort((a, b) =>
            (a['razon_social'] as String).compareTo(b['razon_social'] as String));
    }

    // Web / fallback: llamada directa a Supabase (no hay SQLite en web)
    final data = await Supabase.instance.client
        .from(supabaseTable)
        .select(
          'id, razon_social, nombre_comercial, numero_id, tipo_entidad, '
          'tipo_identificacion, es_cliente, es_proveedor, es_empleado, '
          'email, telefono, celular, activo',
        )
        .eq('activo', true)
        .order('razon_social');
    return List<Map<String, dynamic>>.from(data as List);
  }
}

final contactosProvider = AsyncNotifierProvider.autoDispose<
    ContactosBrickNotifier, List<Map<String, dynamic>>>(
  ContactosBrickNotifier.new,
);


// ---------------------------------------------------------------------------
// contactoBusquedaProvider — búsqueda fuzzy server-side (para pickers)
// ---------------------------------------------------------------------------

/// Busca contactos por texto libre usando pg_trgm en el servidor.
/// Familia por query string — retorna lista vacía si query < 2 chars.
///
/// Uso en picker:
/// ```dart
/// final results = await ref.read(contactoBusquedaProvider(query).future);
/// ```
final contactoBusquedaProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String query, String? filtro})>(
  (ref, params) async {
    if (params.query.length < 2) return const [];
    final data = await Supabase.instance.client.rpc(
      'entidades_buscar_contactos',
      params: {
        'p_query': params.query,
        if (params.filtro != null) 'p_filtro': params.filtro,
        'p_solo_activos': true,
        'p_limit': 20,
        'p_offset': 0,
      },
    );
    return (data as List).cast<Map<String, dynamic>>();
  },
);
