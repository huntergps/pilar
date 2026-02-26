import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns true if [error] looks like a network connectivity issue.
bool isOfflineError(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('connection refused') ||
      msg.contains('failed host lookup') ||
      msg.contains('network is unreachable') ||
      msg.contains('no address associated') ||
      msg.contains('connection timed out') ||
      msg.contains('clientexception') ||
      msg.contains('connection reset') ||
      msg.contains('handshakeexception');
}

/// Tracks online/offline connectivity status.
///
/// Starts as `true` (online). On native platforms, probes DNS every 30 s
/// (or every 5 s while recovering offline). Providers can call
/// [reportOnline] / [reportOffline] to update the state proactively
/// without waiting for the next probe cycle.
///
/// Always returns `true` on web (no dart:io DNS access available).
class ConnectivityNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    if (kIsWeb) return true;
    _schedule(fast: false);
    ref.onDispose(() => _timer?.cancel());
    return true; // assume online initially
  }

  void reportOnline() {
    if (!state) {
      state = true;
      _schedule(fast: false); // slow probe once reconnected
    }
  }

  void reportOffline() {
    if (state) {
      state = false;
      _schedule(fast: true); // probe more aggressively while offline
    }
  }

  void _schedule({required bool fast}) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: fast ? 5 : 30),
      (_) => _probe(),
    );
  }

  Future<void> _probe() async {
    try {
      final result = await InternetAddress.lookup('supabase.co')
          .timeout(const Duration(seconds: 3));
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        reportOnline();
      }
    } catch (_) {
      reportOffline();
    }
  }
}

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);
