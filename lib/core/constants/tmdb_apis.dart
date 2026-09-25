import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// APIs TMDB de la app + API propia del usuario.
///
/// - Las claves integradas se eligen al azar en cada llamada (reparto de carga).
/// - Si el usuario activa "API propia" y guarda su key, se usa solo esa.
/// - Idioma de la API: es-MX | es-ES | en-US (global).
class TmdbApis {
  TmdbApis._();

  /// Claves integradas de la app (añade o quita aquí).
  static const List<String> builtInKeys = [
    'a2d9bbed370d9f678e34006f8750a5a5',
    '439c478a771f35c05022f9feabcca01c',
    '1865f43a0549ca50d341dd9ab8b29f49',


  ];

  static const String _kUseCustom = 'tmdb_use_custom_api';
  static const String _kCustomKey = 'tmdb_custom_api_key';
  static const String _kLanguage = 'tmdb_api_language';

  /// Géneros TV a excluir en Home y Descubrir (reality, talk, news, soap).
  static const List<int> excludedTvGenreIds = [
    10764, // Reality
    10767, // Talk
    10763, // News
    10766, // Soap
  ];

  static const List<int> excludedMovieGenreIds = <int>[];

  static final _rng = Random();

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final useCustom = prefs.getBool(_kUseCustom) ?? false;
    if (useCustom) {
      final custom = prefs.getString(_kCustomKey)?.trim() ?? '';
      if (custom.isNotEmpty) return custom;
    }
    final keys = builtInKeys.where((k) => k.trim().isNotEmpty).toList();
    if (keys.isEmpty) return '';
    if (keys.length == 1) return keys.first;
    return keys[_rng.nextInt(keys.length)];
  }

  static Future<bool> getUseCustomApi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kUseCustom) ?? false;
  }

  static Future<void> setUseCustomApi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseCustom, value);
  }

  static Future<String?> getCustomApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCustomKey);
  }

  static Future<void> setCustomApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomKey, key.trim());
  }

  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLanguage) ?? 'es-MX';
    switch (code) {
      case 'es-ES':
      case 'en-US':
      case 'es-MX':
        return code;
      default:
        return 'es-MX';
    }
  }

  static Future<void> setLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguage, code);
  }

  static String get tvWithoutGenres => excludedTvGenreIds.join(',');

  static String get movieWithoutGenres =>
      excludedMovieGenreIds.isEmpty ? '' : excludedMovieGenreIds.join(',');
}
