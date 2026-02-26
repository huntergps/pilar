import 'package:brick_gen/brick_gen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provides the [PilarRepository] singleton for offline-first data access.
///
/// Returns `null` on web (sqflite is not available on web) and before
/// [PilarRepository.configure] has been called in [main].
final repositoryProvider = Provider<PilarRepository?>((ref) {
  if (kIsWeb) return null;
  if (!PilarRepository.isInitialized) return null;
  return PilarRepository.instance;
});
