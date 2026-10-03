// lib/servicio/tmdb/tmdb_discover_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/tmdb_apis.dart';

/// Descubrir por tipo + género + orden (TMDB /discover).
///
/// sortBy: popularity | year | title | rating
class TmdbDiscoverService {
  static const String _apiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5'; // unused fallback
  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  static const Map<String, String> _headers = {'Accept': 'application/json'};

  /// Géneros película (nombre UI → id TMDB). null = Recientes (sin filtro).
  static const Map<String, int?> movieGenreIds = {
    'Recientes': null,
    'Acción': 28,
    'Aventura': 12,
    'Animación': 16,
    'Comedia': 35,
    'Crimen': 80,
    'Documental': 99,
    'Drama': 18,
    'Familia': 10751,
    'Fantasía': 14,
    'Historia': 36,
    'Terror': 27,
    'Música': 10402,
    'Misterio': 9648,
    'Romance': 10749,
    'Ciencia ficción': 878,
    'Suspense': 53,
    'Bélica': 10752,
    'Western': 37,
  };

  /// Géneros serie (nombre UI → id TMDB).
  static const Map<String, int?> tvGenreIds = {
    'Recientes': null,
    'Acción y Aventura': 10759,
    'Animación': 16,
    'Comedia': 35,
    'Crimen': 80,
    'Documental': 99,
    'Drama': 18,
    'Familia': 10751,
    'Kids': 10762,
    'Misterio': 9648,
    'News': 10763,
    'Reality': 10764,
    'Sci-Fi & Fantasy': 10765,
    'Soap': 10766,
    'Talk': 10767,
    'War & Politics': 10768,
    'Western': 37,
    'Terror': 27, // algunos contenidos TV
    'Suspense': 9648,
  };

  static List<String> movieGenreLabels() => movieGenreIds.keys.toList();
  static List<String> tvGenreLabels() => tvGenreIds.keys.toList();

  Future<_DiscPrefs> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    return _DiscPrefs(
      allowAdult: p.getBool('allow_adult') ?? false,
      showUnreleased: p.getBool('show_unreleased') ?? false,
      spanishLatino: p.getBool('spanish_latino') ?? true,
      spanishCastellano: p.getBool('spanish_castellano') ?? false,
      english: p.getBool('english') ?? false,
    );
  }

  Future<String> _apiLanguage([dynamic _]) async {
    return TmdbApis.getLanguage();
  }

  /// sort_by de TMDB según tipo y criterio.
  String _sortBy(String mediaType, String sortBy) {
    final isMovie = mediaType != 'tv';
    switch (sortBy) {
      case 'year':
        return isMovie ? 'primary_release_date.desc' : 'first_air_date.desc';
      case 'title':
        return isMovie ? 'original_title.asc' : 'original_name.asc';
      case 'rating':
        return 'vote_average.desc';
      case 'popularity':
      default:
        return 'popularity.desc';
    }
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

  Map<String, dynamic> _mapItem(Map<String, dynamic> item, String mediaType) {
    final id = item['id'] as int? ?? 0;
    final title = mediaType == 'movie'
        ? (item['title'] ?? item['original_title'] ?? '')
        : (item['name'] ?? item['original_name'] ?? '');
    final date = (mediaType == 'movie'
            ? item['release_date']
            : item['first_air_date'])
        ?.toString() ??
        '';
    final year = date.length >= 4 ? date.substring(0, 4) : '';

    return {
      'idcontenido': id,
      'tmdb_id': id,
      'media_type': mediaType,
      'type': mediaType,
      'title': title.toString(),
      'poster_path': _img(item['poster_path']?.toString()),
      'backdrop_path': _img(item['backdrop_path']?.toString(), size: 'w780'),
      'vote_average': item['vote_average'],
      'release_date': date,
      'first_air_date': date,
      'year': year,
      'overview': item['overview']?.toString() ?? '',
      'popularity': item['popularity'],
    };
  }

  /// Descubre contenido.
  ///
  /// [mediaType]: `movie` | `tv`
  /// [genero]: etiqueta UI (ej. "Acción", "Recientes")
  /// [sortBy]: popularity | year | title | rating
  /// [page]: página TMDB (1-based)
  Future<Map<String, dynamic>> discover({
    required String mediaType,
    required String genero,
    String sortBy = 'popularity',
    int page = 1,
  }) async {
    final isTv = mediaType.toLowerCase() == 'tv';
    final tipo = isTv ? 'tv' : 'movie';
    final prefs = await _loadPrefs();
    final language = await _apiLanguage(prefs);

    final genreMap = isTv ? tvGenreIds : movieGenreIds;
    final genreId = genreMap[genero]; // null = Recientes

    final query = <String, String>{
      'language': language,
      'page': '$page',
      'sort_by': _sortBy(tipo, sortBy),
      'include_adult': prefs.allowAdult ? 'true' : 'false',
      'vote_count.gte': sortBy == 'rating' ? '50' : '10',
    };

    if (genreId != null) {
      query['with_genres'] = '$genreId';
    }

    // Excluir reality / talk / news / soap en Descubrir (no en búsqueda)
    if (isTv && TmdbApis.tvWithoutGenres.isNotEmpty) {
      query['without_genres'] = TmdbApis.tvWithoutGenres;
    }

    // Recientes: priorizar fecha reciente
    if (genero.toLowerCase() == 'recientes' && sortBy == 'popularity') {
      query['sort_by'] =
          isTv ? 'first_air_date.desc' : 'primary_release_date.desc';
      if (!prefs.showUnreleased) {
        final today = DateTime.now();
        final d =
            '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        if (isTv) {
          query['first_air_date.lte'] = d;
        } else {
          query['primary_release_date.lte'] = d;
        }
      }
    } else if (!prefs.showUnreleased) {
      final today = DateTime.now();
      final d =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      if (isTv) {
        query['first_air_date.lte'] = d;
      } else {
        query['primary_release_date.lte'] = d;
      }
    }

    final path = isTv ? '/discover/tv' : '/discover/movie';
    final data = await _get(path, query: query);

    if (data == null) {
      return {
        'success': false,
        'error': 'Error de red o TMDB',
        'data': <Map<String, dynamic>>[],
        'page': page,
        'has_next': false,
      };
    }

    final results = data['results'];
    final items = <Map<String, dynamic>>[];
    if (results is List) {
      for (final r in results) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        if ((m['poster_path']?.toString() ?? '').isEmpty) continue;
        if (!prefs.allowAdult && m['adult'] == true) continue;
        items.add(_mapItem(m, tipo));
      }
    }

    final totalPages = data['total_pages'] as int? ?? page;
    final hasNext = page < totalPages && page < 500;

    return {
      'success': true,
      'data': items,
      'page': page,
      'has_next': hasNext,
      'total_pages': totalPages,
    };
  }
}

class _DiscPrefs {
  final bool allowAdult;
  final bool showUnreleased;
  final bool spanishLatino;
  final bool spanishCastellano;
  final bool english;

  const _DiscPrefs({
    required this.allowAdult,
    required this.showUnreleased,
    required this.spanishLatino,
    required this.spanishCastellano,
    required this.english,
  });
}