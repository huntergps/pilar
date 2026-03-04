import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/administracion/screens/sync_log_screen.dart'
    show syncQueueItemsProvider;

/// Número de requests HTTP pendientes en la cola offline de Brick.
///
/// Retorna 0 en web (sin SQLite) o cuando el repositorio no está disponible
/// o mientras [syncQueueItemsProvider] está cargando / en error.
///
/// Usado por [PilarHeader] para mostrar el badge de sync en el TitleBar.
final pendingSyncCountProvider = Provider.autoDispose<int>((ref) {
  if (kIsWeb) return 0;
  return ref.watch(syncQueueItemsProvider).maybeWhen(
        data: (items) => items.length,
        orElse: () => 0,
      );
});
