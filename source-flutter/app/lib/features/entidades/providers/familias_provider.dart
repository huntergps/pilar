import 'package:brick_core/query.dart';
import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/brick_data_provider.dart';

// ---------------------------------------------------------------------------
// FamiliasBrickNotifier — lista offline-first con Realtime
// ---------------------------------------------------------------------------

class FamiliasBrickNotifier extends BrickDataNotifier {
  @override
  String get supabaseTable => 'producto_familias';

  @override
  Future<List<Map<String, dynamic>>> fetchData({bool awaitRemote = false}) async {
    if (!kIsWeb && PilarRepository.isInitialized) {
      final policy = awaitRemote
          ? OfflineFirstGetPolicy.awaitRemote
          : OfflineFirstGetPolicy.localOnly;
      final models = await PilarRepository.instance.get<ProductoFamilia>(
        query: Query.where('activo', true),
        policy: policy,
      );
      return models.map((f) => f.toMap()).toList()
        ..sort((a, b) => (a['nombre'] as String).compareTo(b['nombre'] as String));
    }

    final data = await Supabase.instance.client
        .from(supabaseTable)
        .select('id, nombre, descripcion, activo')
        .eq('activo', true)
        .order('nombre');
    return List<Map<String, dynamic>>.from(data as List);
  }
}

final familiasProvider = AsyncNotifierProvider.autoDispose<
    FamiliasBrickNotifier, List<Map<String, dynamic>>>(
  FamiliasBrickNotifier.new,
);
