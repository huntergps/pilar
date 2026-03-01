import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// BrickDataNotifier — lista offline-first con Realtime integrado
// ---------------------------------------------------------------------------

/// Clase base para [AsyncNotifier]s que gestionan listas de datos con:
/// - Carga inicial desde Supabase (con soporte futuro Brick offline-first).
/// - Suscripción automática a cambios vía Supabase Realtime.
/// - Método [refresh] para invalidación manual.
///
/// ### Cómo usarlo
///
/// 1. Extiende [BrickDataNotifier] e implementa [supabaseTable] y [fetchData]:
///
/// ```dart
/// class ContactosBrickNotifier extends BrickDataNotifier {
///   @override
///   String get supabaseTable => 'contactos';
///
///   @override
///   Future<List<Map<String, dynamic>>> fetchData() async {
///     final data = await Supabase.instance.client
///         .from(supabaseTable)
///         .select()
///         .eq('activo', true)
///         .order('razon_social');
///     return List<Map<String, dynamic>>.from(data);
///   }
/// }
/// ```
///
/// 2. Declara el provider:
///
/// ```dart
/// final contactosProvider = AsyncNotifierProvider.autoDispose<
///     ContactosBrickNotifier, List<Map<String, dynamic>>>(
///   ContactosBrickNotifier.new,
/// );
/// ```
///
/// 3. Úsalo en un widget:
///
/// ```dart
/// final contactos = ref.watch(contactosProvider);
/// contactos.when(
///   data: (list) => ...,
///   loading: () => const ProgressRing(),
///   error: (e, _) => Text('$e'),
/// );
/// ```
///
/// ### Realtime automático
///
/// El notifier suscribe automáticamente a INSERT/UPDATE/DELETE en [supabaseTable]
/// e invalida el provider cuando hay cambios. No es necesario llamar nada extra.
///
/// ### Upgrade a Brick offline-first
///
/// Cuando exista el modelo Brick para T, sobreescribe [fetchData] para usar
/// el repository en plataformas no-web y mantener el fallback a Supabase en web:
///
/// ```dart
/// @override
/// Future<List<Map<String, dynamic>>> fetchData() async {
///   final repo = ref.read(repositoryProvider);
///   if (repo != null) {
///     final models = await repo.get<Contacto>(query: Query(...));
///     return models.map((m) => m.toJson()).toList();
///   }
///   // web fallback
///   return super.fetchData();
/// }
/// ```
abstract class BrickDataNotifier
    extends AutoDisposeAsyncNotifier<List<Map<String, dynamic>>> {
  /// Nombre de la tabla Supabase. Usado para la suscripción Realtime.
  String get supabaseTable;

  RealtimeChannel? _channel;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    _subscribeRealtime();
    ref.onDispose(_unsubscribe);
    return fetchData();
  }

  /// Consulta que devuelve los datos. Sobreescribir para añadir filtros,
  /// joins o lógica offline-first con Brick.
  ///
  /// La implementación base hace un SELECT sin filtros.
  Future<List<Map<String, dynamic>>> fetchData() async {
    final data = await Supabase.instance.client
        .from(supabaseTable)
        .select();
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Fuerza una recarga invalidando el provider.
  void refresh() => ref.invalidateSelf();

  void _subscribeRealtime() {
    // Canal único por instancia para evitar suscripciones duplicadas.
    final channelName =
        'brick:$supabaseTable:${identityHashCode(this)}';
    _channel = Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: supabaseTable,
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
  }

  void _unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }
}

// ---------------------------------------------------------------------------
// brickItemProvider — ítem único por (tabla, id)
// ---------------------------------------------------------------------------

/// Provider familia para obtener un único registro por [id] desde Supabase.
///
/// Parámetros: tupla `(String tabla, String id)`.
///
/// ### Uso
/// ```dart
/// // En un widget:
/// final contactoAsync = ref.watch(
///   brickItemProvider(('contactos', contactoId)),
/// );
///
/// contactoAsync.when(
///   data: (data) => data == null
///       ? const Text('No encontrado')
///       : ContactoForm(data: data),
///   loading: () => const ProgressRing(),
///   error: (e, _) => Text('$e'),
/// );
/// ```
///
/// ### Invalidar después de guardar
/// ```dart
/// await Supabase.instance.client.from('contactos').update(data).eq('id', id);
/// ref.invalidate(brickItemProvider(('contactos', id)));
/// ```
final brickItemProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, (String, String)>(
  (ref, args) async {
    final (table, id) = args;
    final data = await Supabase.instance.client
        .from(table)
        .select()
        .eq('id', id)
        .maybeSingle();
    return data;
  },
);
