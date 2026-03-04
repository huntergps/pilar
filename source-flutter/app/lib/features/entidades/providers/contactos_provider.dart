import 'package:brick_core/query.dart';
import 'package:brick_gen/brick_gen.dart';
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
  Future<List<Map<String, dynamic>>> fetchData() async {
    // Plataformas nativas: Brick lee desde SQLite (caché offline) y sincroniza
    // con Supabase en segundo plano.
    if (!kIsWeb && PilarRepository.isInitialized) {
      final models = await PilarRepository.instance.get<Contacto>(
        query: Query.where('activo', true),
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
