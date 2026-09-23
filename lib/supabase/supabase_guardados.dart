import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'supabase_config.dart';

/// CRUD de elementos guardados en la tabla `guardados` de Supabase.
class SupabaseGuardados {
  static SupabaseClient? get _c => AppSupabase.client;

  static String? _resolvePoster(Map<String, dynamic> item) {
    // Acepta poster, poster_path, posterUrl
    final raw = item['poster']?.toString() ??
        item['poster_path']?.toString() ??
        item['posterUrl']?.toString() ??
        '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    // Ruta relativa de TMDB
    return 'https://image.tmdb.org/t/p/w500$raw';
  }

  static String _resolveTitulo(Map<String, dynamic> item) {
    return item['titulo']?.toString() ??
        item['title']?.toString() ??
        item['name']?.toString() ??
        item['titulo_contenido']?.toString() ??
        '';
  }

  static String _resolveTipo(Map<String, dynamic> item) {
    return item['tipo']?.toString() ??
        item['type']?.toString() ??
        item['mediaType']?.toString() ??
        item['media_type']?.toString() ??
        'movie';
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final userId = await SupabaseConfig.getCurrentUserId();
    if (userId == null || userId.isEmpty) return [];

    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return [];

    try {
      final res = await _c!
          .from('guardados')
          .select('id, user_id, idcontenido, poster, titulo, tipo, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (res as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        // Compatibilidad con UI que espera poster_path / title
        m['poster_path'] = m['poster'];
        m['title'] = m['titulo'];
        m['type'] = m['tipo'];
        m['media_type'] = m['tipo'];
        return m;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<bool> isSaved(int idcontenido) async {
    final userId = await SupabaseConfig.getCurrentUserId();
    if (userId == null || userId.isEmpty) return false;

    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return false;

    try {
      final res = await _c!
          .from('guardados')
          .select('id')
          .eq('user_id', userId)
          .eq('idcontenido', idcontenido)
          .maybeSingle();
      return res != null;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> save(Map<String, dynamic> item) async {
    final userId = await SupabaseConfig.getCurrentUserId();
    if (userId == null || userId.isEmpty) return false;

    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return false;

    final idcontenido = item['idcontenido'] ?? item['tmdb_id'] ?? item['idtmdb'];
    if (idcontenido == null) return false;

    final idInt = idcontenido is int
        ? idcontenido
        : int.tryParse(idcontenido.toString()) ?? 0;
    if (idInt == 0) return false;

    final poster = _resolvePoster(item);
    final titulo = _resolveTitulo(item);
    final tipo = _resolveTipo(item);

    try {
      await _c!.from('guardados').upsert({
        'user_id': userId,
        'idcontenido': idInt,
        'poster': poster,
        'titulo': titulo,
        'tipo': tipo,
      }, onConflict: 'user_id,idcontenido');
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> remove(int idcontenido) async {
    final userId = await SupabaseConfig.getCurrentUserId();
    if (userId == null || userId.isEmpty) return false;

    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return false;

    try {
      await _c!
          .from('guardados')
          .delete()
          .eq('user_id', userId)
          .eq('idcontenido', idcontenido);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> toggle(Map<String, dynamic> item) async {
    final id = item['idcontenido'] ?? item['tmdb_id'] ?? item['idtmdb'];
    if (id == null) return false;
    final idInt = id is int ? id : int.tryParse(id.toString()) ?? 0;
    if (idInt == 0) return false;

    final already = await isSaved(idInt);
    if (already) {
      await remove(idInt);
      return false;
    } else {
      await save(item);
      return true;
    }
  }

  static Future<bool> clearAll() async {
    final userId = await SupabaseConfig.getCurrentUserId();
    if (userId == null || userId.isEmpty) return false;

    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return false;

    try {
      await _c!.from('guardados').delete().eq('user_id', userId);
      return true;
    } catch (e) {
      return false;
    }
  }
}
