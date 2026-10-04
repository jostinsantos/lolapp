import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_constants.dart';

/// Cliente central de Supabase.
/// Se inicializa una sola vez con las credenciales fijas del desarrollador.
class AppSupabase {
  static SupabaseClient? _client;
  static bool _initialized = false;

  static SupabaseClient? get client => _client;
  static bool get isInitialized => _initialized && _client != null;

  /// Inicializa el cliente (llamar al arrancar la app).
  static Future<void> init() async {
    if (_initialized && _client != null) return;

    if (!isSupabaseConfigured) {
      _client = null;
      _initialized = false;
      return;
    }

    try {
      await Supabase.initialize(
        url: kSupabaseUrl.trim(),
        anonKey: kSupabaseAnonKey.trim(),
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _client = Supabase.instance.client;
      _initialized = true;
    } catch (_) {
      _client = null;
      _initialized = false;
    }
  }

  /// Usuario de Auth actual (cuenta)
  static User? get currentUser => _client?.auth.currentUser;

  /// true si hay sesión de cuenta activa
  static bool get isLoggedIn => currentUser != null;

  /// Cerrar sesión de la cuenta
  static Future<void> signOut() async {
    await _client?.auth.signOut();
  }
}
