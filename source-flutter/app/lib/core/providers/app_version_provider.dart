import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Lee los metadatos de la aplicación (nombre, versión, build number) en caliente.
///
/// Se inicializa una sola vez al arrancar la app.
/// Uso en widgets:
/// ```dart
/// final info = ref.watch(appVersionProvider).valueOrNull;
/// Text('v${info?.version ?? '...'}');
/// ```
final appVersionProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});
