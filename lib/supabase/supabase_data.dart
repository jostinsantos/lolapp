import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'supabase_config.dart';
import 'supabase_auth.dart';

/// Servicio unificado para Guardados, Historial y Likes.
/// 
/// - Si es invitado o no hay perfil → solo cache local.
/// - Si hay cuenta + perfil → sincroniza con Supabase.
class SupabaseData {
  static SupabaseClient? get _c => AppSupabase.client;

  // ─────────────────────────────────────────────────────────────
  //  GUARDADOS (biblioteca)
  // ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getGuardados() async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      return _getLocalList('local_guardados');
    }

    try {
      final res = await _c!
          .from('guardados')
          .select('id, tmdb_id, poster, tipo, created_at')
          .eq('profile_id', profileId)
          .order('created_at', ascending: false);

      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await _saveLocalList('local_guardados', list);
      return list;
    } catch (_) {
      return _getLocalList('local_guardados');
    }
  }

  static Future<bool> addGuardado({
    required int tmdbId,
    String? poster,
    required String tipo, // 'movie' | 'tv'
  }) async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    final item = {
      'tmdb_id': tmdbId,
      'poster': poster,
      'tipo': tipo,
      'created_at': DateTime.now().toIso8601String(),
    };

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      final list = await _getLocalList('local_guardados');
      list.removeWhere((e) => e['tmdb_id'] == tmdbId && e['tipo'] == tipo);
      list.insert(0, item);
      await _saveLocalList('local_guardados', list);
      return true;
    }

    try {
      await _c!.from('guardados').upsert({
        'profile_id': profileId,
        'tmdb_id': tmdbId,
        'poster': poster,
        'tipo': tipo,
      }, onConflict: 'profile_id,tmdb_id,tipo');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> removeGuardado({
    required int tmdbId,
    required String tipo,
  }) async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      final list = await _getLocalList('local_guardados');
      list.removeWhere((e) => e['tmdb_id'] == tmdbId && e['tipo'] == tipo);
      await _saveLocalList('local_guardados', list);
      return true;
    }

    try {
      await _c!
          .from('guardados')
          .delete()
          .eq('profile_id', profileId)
          .eq('tmdb_id', tmdbId)
          .eq('tipo', tipo);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isGuardado({
    required int tmdbId,
    required String tipo,
  }) async {
    final list = await getGuardados();
    return list.any((e) => e['tmdb_id'] == tmdbId && e['tipo'] == tipo);
  }

  // ─────────────────────────────────────────────────────────────
  //  HISTORIAL (con progreso + temporada/capítulo)
  // ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getHistorial() async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      return _getLocalList('local_historial');
    }

    try {
      final res = await _c!
          .from('historial')
          .select('id, tmdb_id, poster, tipo, progress_seconds, season, episode, titulo, backdrop, duration_seconds, created_at, updated_at')
          .eq('profile_id', profileId)
          .order('updated_at', ascending: false);

      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await _saveLocalList('local_historial', list);
      return list;
    } catch (_) {
      return _getLocalList('local_historial');
    }
  }

  /// Guarda o actualiza el historial.
  /// [progressSeconds] = segundo exacto donde se quedó.
  /// [season] y [episode] solo para series.
  /// [titulo], [backdrop], [durationSeconds] opcionales para biblioteca.
  static Future<bool> saveHistorial({
    required int tmdbId,
    String? poster,
    required String tipo,
    required int progressSeconds,
    int? season,
    int? episode,
    String? titulo,
    String? backdrop,
    int? durationSeconds,
  }) async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    // PostgreSQL UNIQUE trata NULL como distinto → películas no harían upsert.
    // Usamos 0 como sentinela para movie (y TV sin s/e).
    final tipoNorm =
        (tipo.contains('tv') || tipo.contains('serie')) ? 'tv' : 'movie';
    final seasonVal = tipoNorm == 'tv' ? (season ?? 0) : 0;
    final episodeVal = tipoNorm == 'tv' ? (episode ?? 0) : 0;

    final item = {
      'tmdb_id': tmdbId,
      'poster': poster,
      'tipo': tipoNorm,
      'progress_seconds': progressSeconds,
      'season': seasonVal,
      'episode': episodeVal,
      if (titulo != null && titulo.isNotEmpty) 'titulo': titulo,
      if (backdrop != null && backdrop.isNotEmpty) 'backdrop': backdrop,
      if (durationSeconds != null && durationSeconds > 0)
        'duration_seconds': durationSeconds,
      'updated_at': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    };

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      final list = await _getLocalList('local_historial');
      list.removeWhere((e) {
        final sameId = e['tmdb_id'] == tmdbId && e['tipo'] == tipoNorm;
        if (!sameId) return false;
        final s = e['season'] ?? e['temporada'] ?? 0;
        final ep = e['episode'] ?? e['capitulo'] ?? 0;
        return s == seasonVal && ep == episodeVal;
      });
      list.insert(0, item);
      // Mantener solo los últimos 100
      if (list.length > 100) list.removeRange(100, list.length);
      await _saveLocalList('local_historial', list);
      return true;
    }

    try {
      final payload = <String, dynamic>{
        'profile_id': profileId,
        'tmdb_id': tmdbId,
        'poster': poster,
        'tipo': tipoNorm,
        'progress_seconds': progressSeconds,
        'season': seasonVal,
        'episode': episodeVal,
      };
      if (titulo != null && titulo.isNotEmpty) payload['titulo'] = titulo;
      if (backdrop != null && backdrop.isNotEmpty) payload['backdrop'] = backdrop;
      if (durationSeconds != null && durationSeconds > 0) {
        payload['duration_seconds'] = durationSeconds;
      }
      await _c!.from('historial').upsert(
        payload,
        onConflict: 'profile_id,tmdb_id,tipo,season,episode',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> removeHistorial({
    required int tmdbId,
    required String tipo,
    int? season,
    int? episode,
  }) async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    final tipoNorm =
        (tipo.contains('tv') || tipo.contains('serie')) ? 'tv' : 'movie';
    final seasonVal = tipoNorm == 'tv' ? (season ?? 0) : 0;
    final episodeVal = tipoNorm == 'tv' ? (episode ?? 0) : 0;

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      final list = await _getLocalList('local_historial');
      list.removeWhere((e) {
        final sameId = e['tmdb_id'] == tmdbId &&
            (e['tipo'] == tipoNorm || e['tipo'] == tipo);
        if (!sameId) return false;
        final s = e['season'] ?? e['temporada'] ?? 0;
        final ep = e['episode'] ?? e['capitulo'] ?? 0;
        return s == seasonVal && ep == episodeVal;
      });
      await _saveLocalList('local_historial', list);
      return true;
    }

    try {
      await _c!
          .from('historial')
          .delete()
          .eq('profile_id', profileId)
          .eq('tmdb_id', tmdbId)
          .eq('tipo', tipoNorm)
          .eq('season', seasonVal)
          .eq('episode', episodeVal);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  LIKES
  // ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getLikes() async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      return _getLocalList('local_likes');
    }

    try {
      final res = await _c!
          .from('likes')
          .select('id, tmdb_id, poster, tipo, created_at')
          .eq('profile_id', profileId)
          .order('created_at', ascending: false);

      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await _saveLocalList('local_likes', list);
      return list;
    } catch (_) {
      return _getLocalList('local_likes');
    }
  }

  static Future<bool> addLike({
    required int tmdbId,
    String? poster,
    required String tipo,
  }) async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    final item = {
      'tmdb_id': tmdbId,
      'poster': poster,
      'tipo': tipo,
      'created_at': DateTime.now().toIso8601String(),
    };

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      final list = await _getLocalList('local_likes');
      list.removeWhere((e) => e['tmdb_id'] == tmdbId && e['tipo'] == tipo);
      list.insert(0, item);
      await _saveLocalList('local_likes', list);
      return true;
    }

    try {
      await _c!.from('likes').upsert({
        'profile_id': profileId,
        'tmdb_id': tmdbId,
        'poster': poster,
        'tipo': tipo,
      }, onConflict: 'profile_id,tmdb_id,tipo');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> removeLike({
    required int tmdbId,
    required String tipo,
  }) async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    final isGuest = await SupabaseConfig.isGuest();

    if (isGuest || profileId == null || !SupabaseAuth.isLoggedIn) {
      final list = await _getLocalList('local_likes');
      list.removeWhere((e) => e['tmdb_id'] == tmdbId && e['tipo'] == tipo);
      await _saveLocalList('local_likes', list);
      return true;
    }

    try {
      await _c!
          .from('likes')
          .delete()
          .eq('profile_id', profileId)
          .eq('tmdb_id', tmdbId)
          .eq('tipo', tipo);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isLiked({
    required int tmdbId,
    required String tipo,
  }) async {
    final list = await getLikes();
    return list.any((e) => e['tmdb_id'] == tmdbId && e['tipo'] == tipo);
  }

  // ─────────────────────────────────────────────────────────────
  //  Helpers de cache local
  // ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _getLocalList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveLocalList(
    String key,
    List<Map<String, dynamic>> list,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(list));
  }
}
