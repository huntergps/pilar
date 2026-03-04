import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/connectivity_service.dart';

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

  /// Cuando es `true`, el próximo [build] usará [OfflineFirstGetPolicy.awaitRemote]
  /// en lugar de leer solo desde caché local.
  ///
  /// Se activa en [_onRealtimeChange] y se consume (reset a `false`) al inicio
  /// de cada [build]. Esto garantiza que un cambio Realtime fuerza exactamente
  /// un re-fetch remoto, y las siguientes lecturas vuelven a ser locales.
  bool _needsRemoteRefresh = false;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    // Consume el flag antes de arrancar la carga (evita que un segundo rebuild
    // consecutivo vuelva a ir al servidor innecesariamente).
    final awaitRemote = _needsRemoteRefresh;
    _needsRemoteRefresh = false;

    _subscribeRealtime();
    ref.onDispose(_unsubscribe);

    return fetchData(awaitRemote: awaitRemote);
  }

  /// Consulta que devuelve los datos. Sobreescribir para añadir filtros,
  /// joins o lógica offline-first con Brick.
  ///
  /// [awaitRemote]: cuando es `true`, fuerza una lectura desde Supabase en
  /// lugar del caché local. Útil tras un cambio Realtime para garantizar que
  /// los datos reflejan el estado del servidor.
  ///
  /// La implementación base hace un SELECT sin filtros. Si la subclase usa
  /// Brick repository, debe respetar el flag [awaitRemote].
  Future<List<Map<String, dynamic>>> fetchData({bool awaitRemote = false}) async {
    final data = await Supabase.instance.client
        .from(supabaseTable)
        .select();
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Fuerza una recarga invalidando el provider.
  void refresh() => ref.invalidateSelf();

  /// Llamado por la suscripción Realtime cuando hay un cambio en [supabaseTable].
  ///
  /// Activa el flag [_needsRemoteRefresh] para que el próximo [build] lea desde
  /// el servidor, garantizando que el caché Brick refleja el cambio remoto.
  void _onRealtimeChange(PostgresChangePayload payload) {
    _needsRemoteRefresh = true;
    ref.invalidateSelf();
  }

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
          callback: _onRealtimeChange,
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

/// Excepción específica para intentos de lectura offline sin caché local.
///
/// Se lanza cuando [brickItemProvider] detecta un error de red. Proporciona
/// un mensaje legible que los widgets pueden mostrar al usuario.
class OfflineItemException implements Exception {
  const OfflineItemException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _isNetworkError(Object e) {
  final msg = e.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('connection refused') ||
      msg.contains('network') ||
      msg.contains('timeout') ||
      msg.contains('failed host lookup') ||
      msg.contains('clientexception') ||
      msg.contains('handshakeexception');
}

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
///
/// ### Comportamiento offline
///
/// Intenta siempre leer desde Supabase (fuente de verdad). Si hay un error de
/// red, actualiza [connectivityProvider] a offline y lanza [OfflineItemException]
/// con un mensaje legible. Cuando el servidor responde con éxito, reporta online.
///
// brickItemProvider usa Supabase directamente porque es un provider GENÉRICO
// (tabla como String). Brick requiere tipo T en tiempo de compilación: get<Contacto>().
// Para modelos específicos, usa los providers tipados (contactosProvider, productosProvider).
// TODO: Cuando un módulo necesite detalle offline de un modelo concreto,
// crear un provider tipado: brickContactoByIdProvider, brickProductoByIdProvider, etc.
final brickItemProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, (String, String)>(
  (ref, args) async {
    final (table, id) = args;

    // 1. Intentar siempre desde Supabase (fuente de verdad).
    try {
      final data = await Supabase.instance.client
          .from(table)
          .select()
          .eq('id', id)
          .maybeSingle();
      // Éxito: reportar online para que el banner desaparezca si estaba visible.
      ref.read(connectivityProvider.notifier).reportOnline();
      return data;
    } catch (e) {
      // 2. Si es error de red, reportar offline y lanzar excepción descriptiva.
      if (_isNetworkError(e)) {
        ref.read(connectivityProvider.notifier).reportOffline();
        // 3. No hay caché genérica disponible sin tipo T — informar al usuario.
        throw OfflineItemException(
          'Sin conexión: no se puede cargar "$table/$id" offline.\n'
          'Los cambios locales se sincronizarán cuando recuperes la red.',
        );
      }
      rethrow;
    }
  },
);
