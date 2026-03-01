import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_offline_first_with_rest/offline_queue.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:supabase/supabase.dart';

import 'brick/brick.g.dart';
import 'brick/db/schema.g.dart';

/// Singleton repository for PILAR ERP offline-first data access.
///
/// Initialization sequence (in main.dart, native only):
/// ```dart
/// // 1. Create the offline HTTP client + queue
/// final (offlineClient, offlineQueue) =
///     OfflineFirstWithSupabaseRepository.clientQueue(
///       databaseFactory: databaseFactory,
///       ignorePaths: {'/auth/v1', '/storage/v1', '/functions/v1'},
///     );
///
/// // 2. Initialize Supabase WITH the offline-aware HTTP client
/// await Supabase.initialize(
///   url: config.url,
///   anonKey: config.anonKey,
///   httpClient: offlineClient,
/// );
///
/// // 3. Configure the repository
/// PilarRepository.configure(
///   supabaseClient: Supabase.instance.client,
///   offlineQueue: offlineQueue,
/// );
/// ```
class PilarRepository extends OfflineFirstWithSupabaseRepository {
  static PilarRepository? _instance;

  PilarRepository._({
    required super.supabaseProvider,
    required super.sqliteProvider,
    required super.migrations,
    required super.offlineRequestQueue,
    super.memoryCacheProvider,
  });

  static PilarRepository get instance {
    assert(_instance != null, 'Call PilarRepository.configure() first');
    return _instance!;
  }

  static bool get isInitialized => _instance != null;

  /// Configure and initialize the repository after Supabase.initialize().
  // ── Cola offline pública ─────────────────────────────────────────────────

  /// Devuelve todos los requests pendientes en la cola offline de Brick.
  ///
  /// Cada mapa incluye: `id`, `request_method`, `url`, `attempts`,
  /// `locked`, `created_at`, `updated_at`.
  Future<List<Map<String, dynamic>>> getOfflineQueueItems() {
    return offlineRequestQueue.client.requestManager.unprocessedRequests();
  }

  /// Elimina un request de la cola por su [id].
  ///
  /// Retorna `true` si fue encontrado y eliminado, `false` si no existía.
  Future<bool> deleteOfflineQueueItem(int id) {
    return offlineRequestQueue.client.requestManager
        .deleteUnprocessedRequest(id);
  }

  // ── Static configure ─────────────────────────────────────────────────────

  static void configure({
    required SupabaseClient supabaseClient,
    required RestOfflineRequestQueue offlineQueue,
  }) {
    _instance = PilarRepository._(
      supabaseProvider: SupabaseProvider(
        supabaseClient,
        modelDictionary: supabaseModelDictionary,
      ),
      sqliteProvider: SqliteProvider(
        'pilar_offline.sqlite',
        databaseFactory: databaseFactory,
        modelDictionary: sqliteModelDictionary,
      ),
      migrations: migrations,
      offlineRequestQueue: offlineQueue,
    );
  }
}
