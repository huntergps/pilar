import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Compile-time defaults (injected via --dart-define)
// ---------------------------------------------------------------------------

/// Compile-time Supabase URL (empty string when not provided).
const _kCompiledUrl = String.fromEnvironment('SUPABASE_URL');

/// Compile-time Supabase anon key (empty string when not provided).
const _kCompiledAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// ---------------------------------------------------------------------------
// SupabaseConfig — typed credentials value object
// ---------------------------------------------------------------------------

/// Holds a validated pair of Supabase credentials.
class SupabaseConfig {
  final String url;
  final String anonKey;

  const SupabaseConfig({required this.url, required this.anonKey});

  bool get isValid =>
      url.startsWith('https://') && url.contains('.supabase') && anonKey.length > 20;
}

// ---------------------------------------------------------------------------
// SupabaseConfigService — reads/writes credentials with priority:
//   1. --dart-define at compile time (highest priority, cannot be overridden)
//   2. SharedPreferences (saved from setup screen at runtime)
// ---------------------------------------------------------------------------

abstract final class SupabaseConfigService {
  static const _keyUrl = 'supabase_url';
  static const _keyAnonKey = 'supabase_anon_key';

  /// Loads credentials. Returns null when none are configured.
  ///
  /// Priority: compile-time → SharedPreferences.
  static Future<SupabaseConfig?> load() async {
    // 1. Compiled-in values (flutter run --dart-define=...)
    if (_kCompiledUrl.isNotEmpty && _kCompiledAnonKey.isNotEmpty) {
      const config = SupabaseConfig(url: _kCompiledUrl, anonKey: _kCompiledAnonKey);
      if (config.isValid) return config;
    }

    // 2. Saved at runtime via setup screen
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyUrl) ?? '';
    final anonKey = prefs.getString(_keyAnonKey) ?? '';
    if (url.isEmpty || anonKey.isEmpty) return null;

    final config = SupabaseConfig(url: url, anonKey: anonKey);
    return config.isValid ? config : null;
  }

  /// Persists credentials to SharedPreferences.
  static Future<void> save(String url, String anonKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUrl, url.trim());
    await prefs.setString(_keyAnonKey, anonKey.trim());
  }

  /// Clears saved credentials from SharedPreferences.
  /// Has no effect when credentials are compiled in via --dart-define.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUrl);
    await prefs.remove(_keyAnonKey);
  }

  /// True when credentials were injected at compile time and cannot be
  /// changed at runtime (prevents showing the "clear" button in settings).
  static bool get isCompiledIn =>
      _kCompiledUrl.isNotEmpty && _kCompiledAnonKey.isNotEmpty;
}
