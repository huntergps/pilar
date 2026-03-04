import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/brick_write_provider.dart';
import 'familias_provider.dart';

// ---------------------------------------------------------------------------
// FamiliaWriteNotifier
// ---------------------------------------------------------------------------

/// Notifier de escritura para [ProductoFamilia].
///
/// Usa [BrickWriteNotifier] para escribir vía Brick en native y vía Supabase
/// directo en web. Invalida [familiasProvider] al terminar con éxito.
///
/// ### Uso en pantallas
///
/// ```dart
/// // Guardar (INSERT o UPDATE)
/// await ref.read(familiaWriteProvider.notifier).save(familia);
///
/// // Eliminar (soft-delete: activo = false)
/// await ref.read(familiaWriteProvider.notifier).delete(familia);
///
/// // Observar estado de escritura
/// final writeState = ref.watch(familiaWriteProvider);
/// writeState.when(
///   data: (_) => ...,
///   loading: () => const ProgressRing(),
///   error: (e, _) {
///     if (e is OfflineWriteException && e.isConflict) {
///       // Mostrar diálogo de conflicto de versión
///     }
///   },
/// );
/// ```
class FamiliaWriteNotifier extends AutoDisposeAsyncNotifier<void>
    with BrickWriteNotifier<ProductoFamilia> {
  @override
  String get supabaseTable => 'producto_familias';

  @override
  Map<String, dynamic> toSupabaseMap(ProductoFamilia m) => m.toMap();

  @override
  FutureOr<void> build() {
    // Estado inicial vacío; no hace nada al construirse.
  }

  /// Guarda [familia] (INSERT o UPDATE) offline-first.
  ///
  /// Invalida [familiasProvider] en éxito para refrescar la lista.
  /// Propaga [OfflineWriteException] en caso de conflicto o sin red.
  Future<void> save(ProductoFamilia familia) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => performSave(ref, familia));
    if (!state.hasError) {
      ref.invalidate(familiasProvider);
    }
  }

  /// Elimina [familia] offline-first (soft-delete: activo = false).
  ///
  /// Invalida [familiasProvider] en éxito para refrescar la lista.
  Future<void> delete(ProductoFamilia familia) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => performDelete(ref, familia));
    if (!state.hasError) {
      ref.invalidate(familiasProvider);
    }
  }
}

/// Provider de escritura para [ProductoFamilia].
///
/// Scope: autoDispose (se libera cuando no hay widgets escuchando).
final familiaWriteProvider =
    AsyncNotifierProvider.autoDispose<FamiliaWriteNotifier, void>(
  FamiliaWriteNotifier.new,
);
