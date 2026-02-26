import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Compile-time overrides (injected via --dart-define o --dart-define-from-file)
// ---------------------------------------------------------------------------

/// Compile-time Supabase URL override (vacío cuando no se provee).
const _kCompiledUrl = String.fromEnvironment('SUPABASE_URL');

/// Compile-time Supabase anon key override (vacío cuando no se provee).
const _kCompiledAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// ---------------------------------------------------------------------------
// Defaults hardcodeados para esta instancia de PILAR
// Prioridad: --dart-define > SharedPreferences (override manual) > estos defaults
// ---------------------------------------------------------------------------

const _kDefaultUrl = 'https://bsqhqmmxnfyufozhyszj.supabase.co';
const _kDefaultAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzcWhxbW14bmZ5dWZvemh5c3pqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE3Mzg4OTgsImV4cCI6MjA4NzMxNDg5OH0'
    '.S9LFa2p38L8loqgm5-m6Is4sJ84IvxDqiqlcGs-r68o';

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

  /// Loads credentials. Nunca retorna null — usa los defaults hardcodeados
  /// si no hay override por --dart-define ni por SharedPreferences.
  ///
  /// Prioridad: --dart-define > SharedPreferences > defaults hardcodeados.
  static Future<SupabaseConfig> load() async {
    // 1. Compile-time override (--dart-define o --dart-define-from-file)
    if (_kCompiledUrl.isNotEmpty && _kCompiledAnonKey.isNotEmpty) {
      const config = SupabaseConfig(url: _kCompiledUrl, anonKey: _kCompiledAnonKey);
      if (config.isValid) return config;
    }

    // 2. Override manual guardado desde la pantalla de setup
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyUrl) ?? '';
    final anonKey = prefs.getString(_keyAnonKey) ?? '';
    if (url.isNotEmpty && anonKey.isNotEmpty) {
      final config = SupabaseConfig(url: url, anonKey: anonKey);
      if (config.isValid) return config;
    }

    // 3. Defaults de esta instancia PILAR (siempre válidos)
    return const SupabaseConfig(url: _kDefaultUrl, anonKey: _kDefaultAnonKey);
  }

  /// URL efectiva (útil para pre-llenar la pantalla de setup).
  static Future<String> effectiveUrl() async => (await load()).url;

  /// Anon key efectiva (útil para pre-llenar la pantalla de setup).
  static Future<String> effectiveAnonKey() async => (await load()).anonKey;

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
