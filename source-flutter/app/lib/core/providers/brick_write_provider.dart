import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/connectivity_service.dart';

// ---------------------------------------------------------------------------
// OfflineWriteException
// ---------------------------------------------------------------------------

/// Excepción lanzada por [BrickWriteNotifier] cuando la escritura falla.
///
/// - [isConflict] = `true` → conflicto de versión (bloqueo optimista).
/// - [isConflict] = `false` → error de red (sin conectividad).
class OfflineWriteException implements Exception {
  const OfflineWriteException(this.message, {this.isConflict = false});

  /// Descripción legible del error.
  final String message;

  /// `true` si el error es por version mismatch (bloqueo optimista).
  /// `false` si es un error de red / timeout.
  final bool isConflict;

  @override
  String toString() =>
      'OfflineWriteException($message, isConflict: $isConflict)';
}

// ---------------------------------------------------------------------------
// HasVersion mixin
// ---------------------------------------------------------------------------

/// Mixin para modelos Brick que exponen su campo `version` de bloqueo optimista.
///
/// Los modelos que declaren `final int version` pueden usar este mixin para
/// que [BrickWriteNotifier] sea capaz de leer la versión actual del registro.
///
/// Ejemplo de uso en un modelo:
/// ```dart
/// class Contacto extends OfflineFirstWithSupabaseModel with HasVersion {
///   @override
///   final int version;
///   // ...
/// }
/// ```
mixin HasVersion {
  /// Versión actual del registro (empieza en 1, se incrementa en la BD).
  int get version;
}

// ---------------------------------------------------------------------------
// BrickWriteNotifier<T>
// ---------------------------------------------------------------------------

/// Clase base para [AsyncNotifier]s que escriben modelos offline-first.
///
/// ### Estrategia por plataforma
///
/// | Plataforma | Escritura |
/// |------------|-----------|
/// | **Native** (iOS/Android/Desktop) | `PilarRepository.upsert/delete` → SQLite local + cola de sincronización a Supabase. Tolerante a desconexión. |
/// | **Web** | Upsert/DELETE directo a Supabase usando [supabaseTable] y [toSupabaseMap]. Sin SQLite. |
///
/// ### Bloqueo optimista
///
/// Si la BD rechaza el cambio por conflicto de versión (HTTP 409, error
/// PostgreSQL `P0001` o `23505`), lanza [OfflineWriteException] con
/// `isConflict: true`.
///
/// ### Conectividad
///
/// - Éxito → `connectivityProvider.notifier.reportOnline()`.
/// - Error de red → `connectivityProvider.notifier.reportOffline()`.
///
/// ### Cómo extender
///
/// 1. Implementa [supabaseTable] con el nombre de la tabla Supabase.
/// 2. Implementa [toSupabaseMap] para serializar el modelo a JSON (solo usado
///    en web; en native Brick maneja la serialización).
/// 3. Llama [performSave] y [performDelete] desde tu notifier.
///
/// ```dart
/// @riverpod
/// class ContactoWrite extends _$ContactoWrite
///     with BrickWriteNotifier<Contacto> {
///   @override
///   String get supabaseTable => 'contactos';
///
///   @override
///   Map<String, dynamic> toSupabaseMap(Contacto m) => m.toMap();
///
///   @override
///   FutureOr<void> build() {}
///
///   Future<void> save(Contacto contacto) async {
///     state = const AsyncLoading();
///     state = await AsyncValue.guard(() => performSave(ref, contacto));
///     if (!state.hasError) ref.invalidate(contactosProvider);
///   }
/// }
/// ```
mixin BrickWriteNotifier<T extends OfflineFirstWithSupabaseModel> {
  // ── Contrato para el branch web ─────────────────────────────────────────

  /// Nombre de la tabla en Supabase.
  ///
  /// Requerido para el branch web (Supabase directo). En native, Brick
  /// gestiona el nombre de tabla internamente a través del adaptador generado.
  String get supabaseTable;

  /// Serializa [model] a un `Map<String, dynamic>` compatible con Supabase.
  ///
  /// Solo se usa en el branch web. En native Brick usa su propio adaptador.
  ///
  /// Implementación típica:
  /// ```dart
  /// @override
  /// Map<String, dynamic> toSupabaseMap(Contacto m) => m.toMap();
  /// ```
  Map<String, dynamic> toSupabaseMap(T model);

  // ── Upsert ──────────────────────────────────────────────────────────────

  /// Guarda [model] (INSERT o UPDATE) usando la estrategia adecuada.
  ///
  /// Lanza [OfflineWriteException] si:
  /// - El servidor devuelve un conflicto de versión (`isConflict: true`).
  /// - No hay red (`isConflict: false`).
  Future<void> performSave(Ref ref, T model) async {
    try {
      if (!kIsWeb && PilarRepository.isInitialized) {
        // ── Native: Brick gestiona SQLite + cola offline ─────────────────
        await PilarRepository.instance.upsert<T>(model);
      } else {
        // ── Web: upsert directo a Supabase (sin SQLite en web) ──────────
        await Supabase.instance.client
            .from(supabaseTable)
            .upsert(toSupabaseMap(model));
      }
      ref.read(connectivityProvider.notifier).reportOnline();
    } catch (e) {
      if (_isConflictError(e)) {
        throw const OfflineWriteException(
          'Conflicto de versión: otro proceso modificó el registro. '
          'Recarga los datos e intenta de nuevo.',
          isConflict: true,
        );
      }
      if (isOfflineError(e)) {
        ref.read(connectivityProvider.notifier).reportOffline();
        throw const OfflineWriteException(
          'Sin conexión al guardar. El cambio se enviará cuando vuelva la red.',
          isConflict: false,
        );
      }
      rethrow;
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  /// Elimina [model] usando la estrategia adecuada según plataforma.
  ///
  /// Lanza [OfflineWriteException] si hay error de red.
  Future<void> performDelete(Ref ref, T model) async {
    try {
      if (!kIsWeb && PilarRepository.isInitialized) {
        // ── Native: Brick gestiona SQLite + cola offline ─────────────────
        await PilarRepository.instance.delete<T>(model);
      } else {
        // ── Web: DELETE directo a Supabase ───────────────────────────────
        // Todos los modelos Brick usan `id` como clave única.
        final id = toSupabaseMap(model)['id'] as String?;
        if (id == null || id.isEmpty) {
          throw const OfflineWriteException(
            'No se puede eliminar: el modelo no tiene id.',
          );
        }
        await Supabase.instance.client
            .from(supabaseTable)
            .delete()
            .eq('id', id);
      }
      ref.read(connectivityProvider.notifier).reportOnline();
    } catch (e) {
      if (e is OfflineWriteException) rethrow;
      if (isOfflineError(e)) {
        ref.read(connectivityProvider.notifier).reportOffline();
        throw const OfflineWriteException(
          'Sin conexión al eliminar. Intenta de nuevo cuando vuelva la red.',
          isConflict: false,
        );
      }
      rethrow;
    }
  }

  // ── Helpers privados ─────────────────────────────────────────────────────

  /// Detecta errores de conflicto de versión / bloqueo optimista.
  ///
  /// Recibe el [Object] de excepción directamente para poder inspeccionar el
  /// tipo antes de recurrir a `toString()`.
  ///
  /// Orden de evaluación:
  /// 1. [PostgrestException] — tipo específico de supabase_flutter. Compara
  ///    el código PostgreSQL directamente sin depender de su representación
  ///    como cadena.
  ///    - `P0001` = `RAISE EXCEPTION` de nuestro trigger `check_version_conflict`.
  ///    - `23505` = `unique_violation` (conflicto de constraint único en BD).
  /// 2. Fallback genérico sobre `toString()` para cualquier otro tipo de error
  ///    (p. ej. respuestas HTTP crudas desde proxies o pruebas unitarias).
  ///    Se evita el término `'conflict'` como patrón genérico para reducir
  ///    falsos positivos ("connection conflict", "merge conflict", etc.).
  bool _isConflictError(Object error) {
    if (error is PostgrestException) {
      if (error.code == 'P0001' || error.code == '23505') return true;
      final msg = error.message.toLowerCase();
      return msg.contains('version_conflict') ||
          msg.contains('version mismatch') ||
          msg.contains('conflict');
    }
    // Fallback genérico: HTTP 409 o identificadores de error conocidos en string.
    final msg = error.toString().toLowerCase();
    return msg.contains('409') ||
        msg.contains('version_conflict') ||
        msg.contains('version mismatch') ||
        msg.contains('p0001') ||
        msg.contains('23505');
  }
}
