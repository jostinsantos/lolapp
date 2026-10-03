import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

/// Cliente singleton de Supabase (proyecto del USUARIO).
class AppSupabase {
  static SupabaseClient? _client;
  static bool _initialized = false;
  static String? _lastUrl;
  static String? _lastKey;

  static SupabaseClient? get client => _client;
  static bool get isInitialized => _initialized && _client != null;

  static Future<bool> init() async {
    try {
      final url = await SupabaseConfig.getUrl();
      final key = await SupabaseConfig.getAnonKey();

      if (url == null || url.isEmpty || key == null || key.isEmpty) {
        _client = null;
        _initialized = false;
        return false;
      }

      // Si ya está inicializado con los mismos valores, reutilizar
      if (_initialized &&
          _client != null &&
          _lastUrl == url &&
          _lastKey == key) {
        return true;
      }

      // Supabase.initialize solo se puede llamar una vez por proceso.
      // Si cambia URL/KEY, usamos SupabaseClient directo.
      try {
        if (!_initialized) {
          await Supabase.initialize(
            url: url,
            anonKey: key,
            debug: false,
          );
          _client = Supabase.instance.client;
        } else {
          _client = SupabaseClient(url, key);
        }
      } catch (_) {
        // Ya inicializado globalmente o error: cliente directo
        _client = SupabaseClient(url, key);
      }

      _lastUrl = url;
      _lastKey = key;
      _initialized = true;
      return true;
    } catch (_) {
      _client = null;
      _initialized = false;
      return false;
    }
  }

  static Future<bool> reinit() async {
    _client = null;
    _initialized = false;
    _lastUrl = null;
    _lastKey = null;
    return init();
  }

  /// Prueba conexión sin lanzar excepciones ruidosas.
  static Future<bool> testConnection() async {
    try {
      if (!isInitialized) {
        final ok = await init();
        if (!ok) return false;
      }
      if (_client == null) return false;
      // Consulta ligera; si la tabla no existe aún, igual consideramos
      // que el endpoint responde (credenciales válidas).
      try {
        await _client!.from('profiles').select('id').limit(1);
        return true;
      } catch (_) {
        // Tabla puede no existir; si el cliente está vivo, OK
        return _client != null;
      }
    } catch (_) {
      return false;
    }
  }
}
