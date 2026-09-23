// lib/servicio/tmdb/tmdb_search_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/tmdb_apis.dart';

/// Búsqueda multi (movie + tv) 100% TMDB.
class TmdbSearchService {
  static const String _apiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5'; // unused fallback
  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  static const Map<String, String> _headers = {'Accept': 'application/json'};

  static const Map<int, String> _movieGenres = {
    28: 'Acción',
    12: 'Aventura',
    16: 'Animación',
    35: 'Comedia',
    80: 'Crimen',
    99: 'Documental',
    18: 'Drama',
    10751: 'Familiar',
    14: 'Fantasía',
    36: 'Historia',
    27: 'Terror',
    10402: 'Música',
    9648: 'Misterio',
    10749: 'Romance',
    878: 'Ciencia ficción',
    53: 'Suspense',
    10752: 'Bélica',
    37: 'Western',
  };

  static const Map<int, String> _tvGenres = {
    10759: 'Acción y Aventura',
    16: 'Animación',
    35: 'Comedia',
    80: 'Crimen',
    99: 'Documental',
    18: 'Drama',
    10751: 'Familia',
    10762: 'Kids',
    9648: 'Misterio',
    10763: 'News',
    10764: 'Reality',
    10765: 'Sci-Fi & Fantasy',
    10766: 'Soap',
    10767: 'Talk',
    10768: 'War & Politics',
    37: 'Western',
  };

  Future<_SearchPrefs> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    return _SearchPrefs(
      allowAdult: p.getBool('allow_adult') ?? false,
      showUnreleased: p.getBool('show_unreleased') ?? false,
      regionalFilter: p.getBool('regional_filter') ?? true,
      spanishLatino: p.getBool('spanish_latino') ?? true,
      spanishCastellano: p.getBool('spanish_castellano') ?? false,
      english: p.getBool('english') ?? false,
    );
  }

  Future<String> _apiLanguage([dynamic _]) async {
    return TmdbApis.getLanguage();
  }

  Future<Map<String, dynamic>?> _get(
    String path, {
    required Map<String, String> query,
  }) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: {
      'api_key': await TmdbApis.getApiKey(),
      ...query,
    });
    try {
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 16));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
      return null;
    }
  }

  String? _img(String? path, {String size = 'w342'}) {
    if (path == null || path.isEmpty || path == 'null') return null;
    if (path.startsWith('http')) return path;
    return '$_imgBase/$size$path';
  }

  bool _passes(Map<String, dynamic> item, _SearchPrefs prefs) {
    final mt = item['media_type']?.toString() ?? '';
    if (mt != 'movie' && mt != 'tv') return false;
    final poster = item['poster_path']?.toString() ?? '';
    if (poster.isEmpty) return false;
    if (!prefs.allowAdult && item['adult'] == true) return false;
    if (!prefs.showUnreleased) {
      final date = (mt == 'movie'
              ? item['release_date']
              : item['first_air_date'])
          ?.toString() ??
          '';
      if (date.isNotEmpty) {
        final d = DateTime.tryParse(date);
        if (d != null && d.isAfter(DateTime.now())) return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _mapItem(Map<String, dynamic> item) {
    final mt = item['media_type']?.toString() ?? 'movie';
    final id = item['id'] as int? ?? 0;
    final title = mt == 'movie'
        ? (item['title'] ?? item['original_title'] ?? '')
        : (item['name'] ?? item['original_name'] ?? '');
    final date = (mt == 'movie'
            ? item['release_date']
            : item['first_air_date'])
        ?.toString() ??
        '';
    final year = date.length >= 4 ? date.substring(0, 4) : '';
    final genreIds = (item['genre_ids'] is List)
        ? List<int>.from(
            (item['genre_ids'] as List).whereType<num>().map((e) => e.toInt()))
        : <int>[];
    final gMap = mt == 'movie' ? _movieGenres : _tvGenres;
    final genres =
        genreIds.map((id) => gMap[id]).whereType<String>().toList();

    return {
      'idcontenido': id,
      'tmdb_id': id,
      'media_type': mt,
      'type': mt,
      'title': title.toString(),
      'poster_path': _img(item['poster_path']?.toString()),
      'backdrop_path': _img(item['backdrop_path']?.toString(), size: 'w780'),
      'vote_average': item['vote_average'],
      'release_date': date,
      'first_air_date': date,
      'year': year,
      'genres': genres,
      'overview': item['overview']?.toString() ?? '',
    };
  }

  /// Busca en /search/multi. Devuelve shape compatible con BuscarPage.
  Future<Map<String, dynamic>> search(String query, {int limit = 40}) async {
    final q = query.trim();
    if (q.isEmpty) {
      return {
        'success': true,
        'data': {'items': <Map<String, dynamic>>[]},
      };
    }

    final prefs = await _loadPrefs();
    final language = await _apiLanguage(prefs);
    final seen = <int>{};
    final out = <Map<String, dynamic>>[];

    for (var page = 1; page <= 2 && out.length < limit; page++) {
      final data = await _get('/search/multi', query: {
        'query': q,
        'language': language,
        'page': '$page',
        'include_adult': prefs.allowAdult ? 'true' : 'false',
      });
      if (data == null) break;
      final results = data['results'];
      if (results is! List) break;

      for (final r in results) {
        if (r is! Map) continue;
        final item = Map<String, dynamic>.from(r);
        if (!_passes(item, prefs)) continue;
        final id = item['id'] as int? ?? 0;
        if (id <= 0 || seen.contains(id)) continue;
        seen.add(id);
        out.add(_mapItem(item));
        if (out.length >= limit) break;
      }
    }

    return {
      'success': true,
      'data': {'items': out},
    };
  }
}

class _SearchPrefs {
  final bool allowAdult;
  final bool showUnreleased;
  final bool regionalFilter;
  final bool spanishLatino;
  final bool spanishCastellano;
  final bool english;

  const _SearchPrefs({
    required this.allowAdult,
    required this.showUnreleased,
    required this.regionalFilter,
    required this.spanishLatino,
    required this.spanishCastellano,
    required this.english,
  });
}