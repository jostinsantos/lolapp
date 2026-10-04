import 'supabase_data.dart';
import 'supabase_config.dart';

/// Compatibilidad con el código existente que usa GuardadosService.
/// Internamente usa SupabaseData (central).
class GuardadosService {
  /// Lista los guardados del perfil actual (o cache si invitado).
  static Future<List<Map<String, dynamic>>> getAll() async {
    final list = await SupabaseData.getGuardados();
    // Mapear a formato antiguo (idcontenido)
    return list.map((e) {
      return {
        'idcontenido': e['tmdb_id'],
        'poster': e['poster'],
        'tipo': e['tipo'] ?? 'movie',
        'titulo': e['titulo'],
        'timestamp': e['created_at'],
        ...e,
      };
    }).toList();
  }

  static Future<bool> isSaved(int idcontenido) async {
    // Probar movie y tv
    final asMovie = await SupabaseData.isGuardado(tmdbId: idcontenido, tipo: 'movie');
    if (asMovie) return true;
    return SupabaseData.isGuardado(tmdbId: idcontenido, tipo: 'tv');
  }

  /// Toggle. Devuelve true si quedó guardado.
  static Future<bool> toggle(Map<String, dynamic> item) async {
    final id = item['idcontenido'] ?? item['tmdb_id'] ?? item['id'];
    if (id == null) return false;
    final tmdbId = id is int ? id : int.tryParse(id.toString()) ?? 0;
    if (tmdbId == 0) return false;

    final tipo = (item['tipo'] ?? item['type'] ?? item['mediaType'] ?? 'movie')
        .toString()
        .toLowerCase();
    final tipoNorm = tipo.contains('tv') || tipo.contains('serie') ? 'tv' : 'movie';
    final poster = item['poster']?.toString();

    final already = await SupabaseData.isGuardado(tmdbId: tmdbId, tipo: tipoNorm);
    if (already) {
      await SupabaseData.removeGuardado(tmdbId: tmdbId, tipo: tipoNorm);
      return false;
    } else {
      await SupabaseData.addGuardado(tmdbId: tmdbId, poster: poster, tipo: tipoNorm);
      return true;
    }
  }

  static Future<void> remove(int idcontenido) async {
    await SupabaseData.removeGuardado(tmdbId: idcontenido, tipo: 'movie');
    await SupabaseData.removeGuardado(tmdbId: idcontenido, tipo: 'tv');
  }

  static Future<void> clearAll() async {
    final list = await getAll();
    for (final e in list) {
      final id = e['idcontenido'] ?? e['tmdb_id'];
      if (id != null) {
        final tmdbId = id is int ? id : int.tryParse(id.toString()) ?? 0;
        if (tmdbId > 0) {
          await remove(tmdbId);
        }
      }
    }
  }
}
