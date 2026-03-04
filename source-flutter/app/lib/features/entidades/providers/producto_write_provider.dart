import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/brick_write_provider.dart';
import 'productos_provider.dart';

// ---------------------------------------------------------------------------
// ProductoWriteNotifier
// ---------------------------------------------------------------------------

/// Notifier de escritura para [Producto].
///
/// Usa [BrickWriteNotifier] para escribir vía Brick en native y vía Supabase
/// directo en web. Invalida [productosProvider] al terminar con éxito.
///
/// ### Uso en pantallas
///
/// ```dart
/// // Guardar (INSERT o UPDATE)
/// await ref.read(productoWriteProvider.notifier).save(producto);
///
/// // Eliminar
/// await ref.read(productoWriteProvider.notifier).delete(producto);
///
/// // Observar estado de escritura
/// final writeState = ref.watch(productoWriteProvider);
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
class ProductoWriteNotifier extends AutoDisposeAsyncNotifier<void>
    with BrickWriteNotifier<Producto> {
  @override
  String get supabaseTable => 'productos';

  @override
  Map<String, dynamic> toSupabaseMap(Producto m) => m.toMap();

  @override
  FutureOr<void> build() {
    // Estado inicial vacío; no hace nada al construirse.
  }

  /// Guarda [producto] (INSERT o UPDATE) offline-first.
  ///
  /// Invalida [productosProvider] en éxito para refrescar la lista.
  /// Propaga [OfflineWriteException] en caso de conflicto o sin red.
  Future<void> save(Producto producto) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => performSave(ref, producto));
    if (!state.hasError) {
      ref.invalidate(productosProvider);
    }
  }

  /// Elimina [producto] offline-first.
  ///
  /// Invalida [productosProvider] en éxito para refrescar la lista.
  Future<void> delete(Producto producto) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => performDelete(ref, producto));
    if (!state.hasError) {
      ref.invalidate(productosProvider);
    }
  }
}

/// Provider de escritura para [Producto].
///
/// Scope: autoDispose (se libera cuando no hay widgets escuchando).
final productoWriteProvider =
    AsyncNotifierProvider.autoDispose<ProductoWriteNotifier, void>(
  ProductoWriteNotifier.new,
);
