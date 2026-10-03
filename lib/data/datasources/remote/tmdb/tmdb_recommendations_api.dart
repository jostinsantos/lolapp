import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/constants/tmdb_apis.dart';

/// Servicio TMDB de recomendaciones (mismo estilo que TmdbContentService).
///
/// Orden de resultados:
/// 1) Películas de la misma colección (si aplica)
/// 2) Recommendations + similar, ordenados por popularidad
///
/// Idioma: es-MX → en-US → es-ES
class TmdbRecommendationsService {
  static const String _apiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5'; // unused fallback
  static const String _base = 'https://api.themoviedb.org/3';

  static const List<String> _langPriority = ['es-MX', 'en-US', 'es-ES'];

  Future<List<Map<String, dynamic>>> fetchRecommendations({
    required int tmdbId,
    required String mediaType,
    int? collectionId,
  }) async {
    final results = <Map<String, dynamic>>[];
    final seen = <int>{tmdbId};
    final mt = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';

    // 1) Colección (solo movie)
    if (mt == 'movie' && collectionId != null && collectionId > 0) {
      final parts = await _fetchCollectionParts(collectionId);
      for (final p in parts) {
        final id = (p['id'] as num?)?.toInt();
        if (id == null || seen.contains(id)) continue;
        seen.add(id);
        results.add({
          ...p,
          'media_type': 'movie',
          'source': 'collection',
          'title': p['title'] ?? p['name'] ?? '',
        });
      }
    }

    // 2) Recommendations + similar (populares primero)
    for (final endpoint in ['recommendations', 'similar']) {
      final list = await _fetchList('$_base/$mt/$tmdbId/$endpoint');
      list.sort((a, b) {
        final pa = (a['popularity'] as num?)?.toDouble() ?? 0;
        final pb = (b['popularity'] as num?)?.toDouble() ?? 0;
        return pb.compareTo(pa);
      });
      for (final item in list) {
        final id = (item['id'] as num?)?.toInt();
        if (id == null || seen.contains(id)) continue;
        seen.add(id);
        final itemMt =
            (item['media_type']?.toString() ?? mt).toLowerCase();
        results.add({
          ...item,
          'media_type': itemMt == 'tv' ? 'tv' : 'movie',
          'source': endpoint,
          'title': item['title'] ?? item['name'] ?? '',
        });
      }
    }

    return results;
  }

  /// Detalle enriquecido del ítem seleccionado: logo, géneros, IMDb, overview
  /// con fallback de idioma es-MX → en-US → es-ES.
  Future<Map<String, dynamic>?> fetchItemDetails({
    required int tmdbId,
    required String mediaType,
  }) async {
    final mt = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';

    Map<String, dynamic>? best;
    String? bestOverview;
    String? bestTitle;

    for (final lang in _langPriority) {
      try {
        final uri = Uri.parse(
          '$_base/$mt/$tmdbId'
          '?api_key=${await TmdbApis.getApiKey()}'
          '&language=$lang'
          '&append_to_response=external_ids,images'
          '&include_image_language=${lang.split('-').first},null',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);

        final overview = (data['overview']?.toString() ?? '').trim();
        final title =
            (data['title'] ?? data['name'] ?? '').toString().trim();

        if (best == null) {
          best = data;
          if (overview.isNotEmpty) bestOverview = overview;
          if (title.isNotEmpty) bestTitle = title;
        } else {
          if ((bestOverview == null || bestOverview.isEmpty) &&
              overview.isNotEmpty) {
            bestOverview = overview;
          }
          if ((bestTitle == null || bestTitle.isEmpty) && title.isNotEmpty) {
            bestTitle = title;
          }
          // Preferir géneros del primer idioma con datos
          if ((best['genres'] == null ||
                  (best['genres'] is List &&
                      (best['genres'] as List).isEmpty)) &&
              data['genres'] is List &&
              (data['genres'] as List).isNotEmpty) {
            best['genres'] = data['genres'];
          }
        }

        // Si ya tenemos overview en el idioma prioritario, podemos parar
        if (overview.isNotEmpty && best == data) {
          // seguimos un poco por si images/logo vienen mejor en otro lang
        }
      } catch (_) {}
    }

    if (best == null) return null;

    if (bestOverview != null && bestOverview.isNotEmpty) {
      best['overview'] = bestOverview;
    }
    if (bestTitle != null && bestTitle.isNotEmpty) {
      best['title'] = bestTitle;
      best['name'] = bestTitle;
    }

    // Logo: images.logos preferido language es → en → null
    final logoPath = _pickLogo(best);
    if (logoPath != null) {
      best['logo_path'] = logoPath;
    }

    // IMDb rating / id desde external_ids
    final ext = best['external_ids'];
    if (ext is Map) {
      final imdbId = ext['imdb_id']?.toString();
      if (imdbId != null && imdbId.isNotEmpty) {
        best['imdb_id'] = imdbId;
      }
    }

    return best;
  }

  String? _pickLogo(Map<String, dynamic> data) {
    final images = data['images'];
    if (images is! Map) return null;
    final logos = images['logos'];
    if (logos is! List || logos.isEmpty) return null;

    // Preferencia: es → en → sin idioma → cualquiera
    String? pick(String? lang) {
      for (final l in logos) {
        if (l is! Map) continue;
        final iso = l['iso_639_1']?.toString();
        final path = l['file_path']?.toString();
        if (path == null || path.isEmpty) continue;
        if (lang == null) {
          if (iso == null || iso.isEmpty) return path;
        } else if (iso == lang) {
          return path;
        }
      }
      return null;
    }

    return pick('es') ??
        pick('en') ??
        pick(null) ??
        (logos.first is Map
            ? (logos.first as Map)['file_path']?.toString()
            : null);
  }

  Future<List<Map<String, dynamic>>> _fetchCollectionParts(
    int collectionId,
  ) async {
    for (final lang in _langPriority) {
      try {
        final uri = Uri.parse(
          '$_base/collection/$collectionId?api_key=${await TmdbApis.getApiKey()}&language=$lang',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final parts = List<Map<String, dynamic>>.from(data['parts'] ?? []);
        if (parts.isEmpty) continue;
        parts.sort((a, b) {
          final da = a['release_date']?.toString() ?? '';
          final db = b['release_date']?.toString() ?? '';
          return da.compareTo(db);
        });
        return parts;
      } catch (_) {}
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _fetchList(String pathWithoutQuery) async {
    for (final lang in _langPriority) {
      try {
        final uri = Uri.parse(
          '$pathWithoutQuery?api_key=${await TmdbApis.getApiKey()}&language=$lang&page=1',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = List<Map<String, dynamic>>.from(data['results'] ?? []);
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    return const [];
  }
}