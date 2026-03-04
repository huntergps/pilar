import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/brick_write_provider.dart';
import 'contactos_provider.dart';

// ---------------------------------------------------------------------------
// ContactoWriteNotifier
// ---------------------------------------------------------------------------

/// Notifier de escritura para [Contacto].
///
/// Usa [BrickWriteNotifier] para escribir vía Brick en native y vía Supabase
/// directo en web. Invalida [contactosProvider] al terminar con éxito.
///
/// ### Uso en pantallas
///
/// ```dart
/// // Guardar (INSERT o UPDATE)
/// await ref.read(contactoWriteProvider.notifier).save(contacto);
///
/// // Eliminar
/// await ref.read(contactoWriteProvider.notifier).delete(contacto);
///
/// // Observar estado de escritura
/// final writeState = ref.watch(contactoWriteProvider);
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
class ContactoWriteNotifier extends AutoDisposeAsyncNotifier<void>
    with BrickWriteNotifier<Contacto> {
  @override
  String get supabaseTable => 'contactos';

  @override
  Map<String, dynamic> toSupabaseMap(Contacto m) => m.toMap();

  @override
  FutureOr<void> build() {
    // Estado inicial vacío; no hace nada al construirse.
  }

  /// Guarda [contacto] (INSERT o UPDATE) offline-first.
  ///
  /// Invalida [contactosProvider] en éxito para refrescar la lista.
  /// Propaga [OfflineWriteException] en caso de conflicto o sin red.
  Future<void> save(Contacto contacto) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => performSave(ref, contacto));
    if (!state.hasError) {
      ref.invalidate(contactosProvider);
    }
  }

  /// Elimina [contacto] offline-first.
  ///
  /// Invalida [contactosProvider] en éxito para refrescar la lista.
  Future<void> delete(Contacto contacto) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => performDelete(ref, contacto));
    if (!state.hasError) {
      ref.invalidate(contactosProvider);
    }
  }
}

/// Provider de escritura para [Contacto].
///
/// Scope: autoDispose (se libera cuando no hay widgets escuchando).
final contactoWriteProvider =
    AsyncNotifierProvider.autoDispose<ContactoWriteNotifier, void>(
  ContactoWriteNotifier.new,
);
