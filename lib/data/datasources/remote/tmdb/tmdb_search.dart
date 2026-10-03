import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/tmdb_apis.dart';

/// Servicio de búsqueda alimentado por la API de TMDB.
/// Respeta las preferencias de ConfigPage (SharedPreferences),
/// igual que TmdbHomeService.
///
/// Mejoras:
/// - Búsqueda multi-idioma (es-MX, es-ES, en-US) en paralelo
/// - Más sensible con queries cortas
/// - Encuentra títulos originales / japoneses / inglés / español
///
/// API key: a2d9bbed370d9f678e34006f8750a5a5
class TmdbSearchService {
  static const String _apiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5'; // unused fallback
  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  /// Mínimo de votos / popularidad para filtrar basura.
  static const int _minVoteCountMovies = 40;
  static const int _minVoteCountTv = 20;
  static const double _minPopularity = 3.0;

  /// Máximo de resultados a devolver.
  static const int _maxResults = 30;

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
  };

  /// Idiomas originales a excluir cuando regionalización está activa.
  static const Set<String> _excludedRegionalLangs = {
    'hi', 'te', 'ta', 'ml', 'kn', 'bn', 'mr', 'pa', 'gu', 'ur', 'ne', 'si',
    'zh', 'cn', 'ja', 'ko', 'th', 'vi', 'id', 'ms', 'tl', 'fil', 'my', 'km', 'lo',
    'ru',
  };

  // ── Preferencias ──────────────────────────────────────────────────────────

  Future<_SearchPrefs> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    return _SearchPrefs(
      allowAdult: p.getBool('allow_adult_content') ?? false,
      showUnreleased: p.getBool('show_unreleased') ?? false,
      regionalFilter: p.getBool('regional_peru') ?? false,
      spanishLatino: p.getBool('spanish_latino') ?? true,
      spanishCastellano: p.getBool('spanish_castellano') ?? false,
      english: p.getBool('english') ?? false,
      disableNonLatin: p.getBool('disable_non_latin_titles') ?? false,
    );
  }

  Future<String> _apiLanguage([dynamic _]) async {
    return TmdbApis.getLanguage();
  }

  // ── API helpers ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _get(
    String path, {
    Map<String, String>? query,
    required String language,
  }) async {
    final q = <String, String>{
      'api_key': await TmdbApis.getApiKey(),
      'language': language,
      ...?query,
    };
    final uri = Uri.parse('$_base$path').replace(queryParameters: q);
    try {
      final res =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Filtros ───────────────────────────────────────────────────────────────

  bool _passesFilters(
    Map<String, dynamic> item,
    _SearchPrefs prefs, {
    required bool isMovie,
    int? minVotesOverride,
    double? minPopularityOverride,
  }) {
    // 1) Debe tener póster
    final poster = item['poster_path']?.toString() ?? '';
    if (poster.isEmpty) return false;

    // 2) Contenido mínimamente conocido
    final minVotes = minVotesOverride ??
        (isMovie ? _minVoteCountMovies : _minVoteCountTv);
    final minPop = minPopularityOverride ?? _minPopularity;

    final voteCount = (item['vote_count'] is num)
        ? (item['vote_count'] as num).toInt()
        : int.tryParse('${item['vote_count']}') ?? 0;
    final popularity = (item['popularity'] is num)
        ? (item['popularity'] as num).toDouble()
        : double.tryParse('${item['popularity']}') ?? 0.0;

    if (voteCount < minVotes && popularity < minPop) return false;

    // 3) Adult
    if (item['adult'] == true && !prefs.allowAdult) return false;

    // 4) Unreleased
    if (!prefs.showUnreleased) {
      final dateStr =
          (isMovie ? item['release_date'] : item['first_air_date'])
                  ?.toString() ??
              '';
      if (dateStr.isNotEmpty) {
        final d = DateTime.tryParse(dateStr);
        if (d != null && d.isAfter(DateTime.now())) return false;
      }
    }

    // 5) Regionalización
    final origLang =
        (item['original_language'] ?? '').toString().toLowerCase();
    if (prefs.regionalFilter && _excludedRegionalLangs.contains(origLang)) {
      return false;
    }

    // 6) Títulos no latinos
    if (prefs.disableNonLatin) {
      final title =
          (isMovie ? item['title'] : item['name'])?.toString() ?? '';
      if (title.isNotEmpty && !_isMostlyLatin(title)) return false;
    }

    return true;
  }

  bool _isMostlyLatin(String text) {
    int nonLatin = 0;
    int letters = 0;
    for (final r in text.runes) {
      final isLatin = (r >= 0x0041 && r <= 0x005A) ||
          (r >= 0x0061 && r <= 0x007A) ||
          (r >= 0x00C0 && r <= 0x024F) ||
          (r >= 0x1E00 && r <= 0x1EFF);
      if (isLatin) {
        letters++;
      } else if (r > 0x007F) {
        if (r < 0x2000 || r > 0x206F) {
          nonLatin++;
          letters++;
        }
      }
    }
    if (letters == 0) return true;
    return nonLatin / letters < 0.35;
  }

  // ── Mapeo (mismo formato que TmdbHomeService) ─────────────────────────────

  Map<String, dynamic> _mapItem(
    Map<String, dynamic> raw, {
    required bool isMovie,
  }) {
    final id = raw['id'] as int? ?? 0;
    final title = isMovie
        ? (raw['title']?.toString() ?? raw['original_title']?.toString() ?? '')
        : (raw['name']?.toString() ?? raw['original_name']?.toString() ?? '');

    final posterPath = raw['poster_path']?.toString() ?? '';
    final backdropPath = raw['backdrop_path']?.toString() ?? '';

    final posterUrl =
        posterPath.isNotEmpty ? '$_imgBase/w500$posterPath' : '';
    final backdropUrl = backdropPath.isNotEmpty
        ? '$_imgBase/w1280$backdropPath'
        : posterUrl;

    final genreIds = (raw['genre_ids'] is List)
        ? List<int>.from(
            (raw['genre_ids'] as List).whereType<num>().map((e) => e.toInt()),
          )
        : <int>[];

    return {
      'idcontenido': id,
      'tmdb_id': id,
      'media_type': isMovie ? 'movie' : 'tv',
      'title': title,
      'series_title': isMovie ? null : title,
      'poster_path': posterUrl,
      'backdrop_path': backdropUrl,
      'logo_path': '',
      'overview': raw['overview']?.toString() ?? '',
      'vote_average': raw['vote_average'],
      'vote_count': raw['vote_count'],
      'release_date': isMovie ? raw['release_date'] : null,
      'first_air_date': isMovie ? null : raw['first_air_date'],
      'year': _yearFrom(isMovie ? raw['release_date'] : raw['first_air_date']),
      'genres': _genreNames(genreIds, isMovie: isMovie),
      'genre_ids': genreIds,
      'runtime': null,
      'adult': raw['adult'] == true,
      'original_language': raw['original_language'],
      'popularity': raw['popularity'],
    };
  }

  String _yearFrom(dynamic date) {
    final s = date?.toString() ?? '';
    return s.length >= 4 ? s.substring(0, 4) : '';
  }

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
    10770: 'Película de TV',
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
    10751: 'Familiar',
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

  String _genreNames(List<int> ids, {required bool isMovie}) {
    final map = isMovie ? _movieGenres : _tvGenres;
    return ids.map((id) => map[id]).whereType<String>().take(3).join(', ');
  }

  // ── Búsqueda principal ────────────────────────────────────────────────────

  /// Busca películas y series en TMDB.
  ///
  /// Devuelve el mismo formato que usa tu BuscarPage:
  /// ```dart
  /// {
  ///   'success': true,
  ///   'data': {
  ///     'items': [ ... ]
  ///   }
  /// }
  /// ```
  Future<Map<String, dynamic>> search(String query, {int limit = _maxResults}) async {
    final q = query.trim();
    if (q.isEmpty) {
      return {
        'success': true,
        'data': {'items': <Map<String, dynamic>>[]},
      };
    }

    final prefs = await _loadPrefs();
    final preferredLang = await _apiLanguage(prefs);

    // Idiomas en los que buscamos (títulos originales + ES + EN)
    final languagesToSearch = <String>{
      preferredLang,
      'es-MX',
      'es-ES',
      'en-US',
    }.toList();

    // Umbrales más permisivos con queries cortas (más sensibilidad)
    final isShortQuery = q.length <= 3;
    final minVotesMovies = isShortQuery ? 12 : _minVoteCountMovies;
    final minVotesTv = isShortQuery ? 6 : _minVoteCountTv;
    final minPop = isShortQuery ? 1.2 : _minPopularity;

    final rawItems = <Map<String, dynamic>>[];
    final seen = <String>{}; // "movie_123" / "tv_456"

    void addFromResults(List? results) {
      if (results == null) return;
      for (final raw in results) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);

        final mediaType = (m['media_type']?.toString() ?? '').toLowerCase();
        if (mediaType != 'movie' && mediaType != 'tv') continue;

        final isMovie = mediaType == 'movie';
        final id = m['id'] as int? ?? 0;
        if (id <= 0) continue;

        final key = '${mediaType}_$id';
        if (seen.contains(key)) continue;
        seen.add(key);

        if (!_passesFilters(
          m,
          prefs,
          isMovie: isMovie,
          minVotesOverride: isMovie ? minVotesMovies : minVotesTv,
          minPopularityOverride: minPop,
        )) continue;

        rawItems.add(m);
        if (rawItems.length >= limit * 2) break;
      }
    }

    // Búsquedas en paralelo
    final futures = languagesToSearch.map((lang) {
      return _get(
        '/search/multi',
        query: {
          'query': q,
          'include_adult': prefs.allowAdult ? 'true' : 'false',
          'page': '1',
        },
        language: lang,
      );
    });

    final results = await Future.wait(futures);

    for (final multi in results) {
      if (multi != null) {
        addFromResults(multi['results'] as List?);
      }
    }

    // Página 2 solo del idioma preferido si todavía faltan resultados
    if (rawItems.length < limit) {
      final multi2 = await _get(
        '/search/multi',
        query: {
          'query': q,
          'include_adult': prefs.allowAdult ? 'true' : 'false',
          'page': '2',
        },
        language: preferredLang,
      );
      if (multi2 != null) {
        addFromResults(multi2['results'] as List?);
      }
    }

    // Ordenar por popularidad
    rawItems.sort((a, b) {
      final pa = (a['popularity'] is num)
          ? (a['popularity'] as num).toDouble()
          : 0.0;
      final pb = (b['popularity'] is num)
          ? (b['popularity'] as num).toDouble()
          : 0.0;
      return pb.compareTo(pa);
    });

    final mapped = rawItems
        .take(limit)
        .map((e) {
          final isMovie =
              (e['media_type']?.toString() ?? 'movie').toLowerCase() == 'movie';
          return _mapItem(e, isMovie: isMovie);
        })
        .where((e) => (e['poster_path'] as String).isNotEmpty)
        .toList();

    return {
      'success': true,
      'data': {
        'items': mapped,
      },
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
  final bool disableNonLatin;

  const _SearchPrefs({
    required this.allowAdult,
    required this.showUnreleased,
    required this.regionalFilter,
    required this.spanishLatino,
    required this.spanishCastellano,
    required this.english,
    required this.disableNonLatin,
  });
}