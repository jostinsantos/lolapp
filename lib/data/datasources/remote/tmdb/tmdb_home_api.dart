import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/tmdb_apis.dart';

/// Servicio de Home alimentado por la API de TMDB.
/// Aplica las preferencias de ConfigPage (SharedPreferences).
///
/// API key: a2d9bbed370d9f678e34006f8750a5a5
///
/// Idiomas de la app (español latino / castellano / inglés) controlan el
/// parámetro `language` de TMDB (títulos, sinopsis, etc.), NO filtran por
/// idioma original del contenido.
///
/// Regionalización: solo excluye contenido asiático / indio / ruso.
class TmdbHomeService {
  static const String _apiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5'; // unused fallback
  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  /// Mínimo de votos para considerar contenido "conocido".
  static const int _minVoteCountMovies = 80;
  static const int _minVoteCountTv = 40;

  /// Popularidad mínima (TMDB popularity score).
  static const double _minPopularity = 8.0;

  /// Items objetivo por sección (estilo Netflix / streaming).
  static const int _targetPerSection = 18;

  /// Páginas a pedir por endpoint.
  static const int _pagesToFetch = 3;

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
  };

  /// Idiomas originales a excluir cuando regionalización está activa
  /// (asiático, indio y ruso). El resto de idiomas se permiten.
  static const Set<String> _excludedRegionalLangs = {
    // Indio / subcontinente
    'hi', // hindi
    'te', // telugu
    'ta', // tamil
    'ml', // malayalam
    'kn', // kannada
    'bn', // bengali
    'mr', // marathi
    'pa', // punjabi
    'gu', // gujarati
    'ur', // urdu
    'ne', // nepali
    'si', // sinhala
    // Asiático este / sureste
    'zh', // chinese
    'cn', // chinese (legacy)
    'ja', // japanese
    'ko', // korean
    'th', // thai
    'vi', // vietnamese
    'id', // indonesian
    'ms', // malay
    'tl', // tagalog
    'fil',
    'my', // burmese
    'km', // khmer
    'lo', // lao
    // Ruso
    'ru',
  };

  final math.Random _rng = math.Random();

  // Cache simple de logos por (mediaType,id).
  final Map<String, String> _logoCache = {};

  // ── Preferencias ──────────────────────────────────────────────────────────

  Future<_HomePrefs> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    return _HomePrefs(
      tmdbEnrichment: p.getBool('tmdb_enrichment') ?? true,
      allowAdult: p.getBool('allow_adult_content') ?? false,
      showUnreleased: p.getBool('show_unreleased') ?? false,
      homeSessions: p.getBool('home_sessions') ?? true,
      homeFeaturedMovies: p.getBool('home_featured_movies') ?? true,
      homePopularMovies: p.getBool('home_popular_movies') ?? true,
      homePopularSeries: p.getBool('home_popular_series') ?? true,
      homeYearMovies: p.getBool('home_year_movies') ?? true,
      homeFeaturedSeries: p.getBool('home_featured_series') ?? true,
      homeYearSeries: p.getBool('home_year_series') ?? true,
      homeTrendingMovies: p.getBool('home_trending_movies') ?? true,
      homeTrendingSeries: p.getBool('home_trending_series') ?? true,
      homeLatest: p.getBool('home_latest') ?? true,
      regionalFilter: p.getBool('regional_peru') ?? false,
      spanishLatino: p.getBool('spanish_latino') ?? true,
      spanishCastellano: p.getBool('spanish_castellano') ?? false,
      english: p.getBool('english') ?? false,
      disableNonLatin: p.getBool('disable_non_latin_titles') ?? false,
    );
  }

  /// Idioma de la API TMDB según config de la app.
  /// Prioridad: latino > castellano > inglés > es-MX por defecto.
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
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Varias páginas para rellenar sliders.
  Future<List<Map<String, dynamic>>> _listResultsMultiPage(
    String path, {
    Map<String, String>? query,
    required String language,
    int pages = _pagesToFetch,
    int max = 40,
  }) async {
    final all = <Map<String, dynamic>>[];
    final seen = <int>{};

    for (var page = 1; page <= pages && all.length < max; page++) {
      final q = <String, String>{
        ...?query,
        'page': page.toString(),
      };
      final data = await _get(path, query: q, language: language);
      if (data == null) break;
      final results = data['results'];
      if (results is! List || results.isEmpty) break;

      for (final raw in results) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final id = m['id'] as int? ?? 0;
        if (id <= 0 || seen.contains(id)) continue;
        seen.add(id);
        all.add(m);
        if (all.length >= max) break;
      }

      final totalPages = data['total_pages'];
      if (totalPages is num && page >= totalPages.toInt()) break;
    }
    return all;
  }

  // ── Filtros ───────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> items,
    _HomePrefs prefs, {
    required bool isMovie,
  }) {
    final minVotes = isMovie ? _minVoteCountMovies : _minVoteCountTv;

    return items.where((item) {
      // 1) Debe tener póster
      final poster = item['poster_path']?.toString() ?? '';
      if (poster.isEmpty) return false;

      // 2) Contenido conocido
      final voteCount = (item['vote_count'] is num)
          ? (item['vote_count'] as num).toInt()
          : int.tryParse('${item['vote_count']}') ?? 0;
      final popularity = (item['popularity'] is num)
          ? (item['popularity'] as num).toDouble()
          : double.tryParse('${item['popularity']}') ?? 0.0;

      if (voteCount < minVotes && popularity < _minPopularity) return false;

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

      // 5) Regionalización: SOLO excluir asiático / indio / ruso.
      //    Todo el resto de idiomas (es, en, fr, de, it, pt, etc.) se permite.
      final origLang =
          (item['original_language'] ?? '').toString().toLowerCase();
      if (prefs.regionalFilter && _excludedRegionalLangs.contains(origLang)) {
        return false;
      }

      // 6) Títulos no latinos (opcional)
      if (prefs.disableNonLatin) {
        final title =
            (isMovie ? item['title'] : item['name'])?.toString() ?? '';
        if (title.isNotEmpty && !_isMostlyLatin(title)) return false;
      }

      return true;
    }).toList();
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

  // ── Query params ──────────────────────────────────────────────────────────

  Map<String, String> _baseDiscover(_HomePrefs prefs, {required bool isMovie}) {
    final q = <String, String>{
      'include_adult': prefs.allowAdult ? 'true' : 'false',
      'sort_by': 'popularity.desc',
      'vote_count.gte': isMovie ? '$_minVoteCountMovies' : '$_minVoteCountTv',
    };

    if (!prefs.showUnreleased) {
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (isMovie) {
        q['primary_release_date.lte'] = stamp;
      } else {
        q['first_air_date.lte'] = stamp;
      }
    }

    // NO se usa with_original_language: los toggles de idioma son solo
    // para el parámetro `language` de la API (metadatos localizados).

    // Excluir reality / talk / news / soap en Home (series)
    if (!isMovie && TmdbApis.tvWithoutGenres.isNotEmpty) {
      q['without_genres'] = TmdbApis.tvWithoutGenres;
    }
    return q;
  }

  // ── Logos ─────────────────────────────────────────────────────────────────

  /// Logo preferido: idioma de la app → null → en → cualquiera.
  Future<String> _fetchLogo({
    required int tmdbId,
    required bool isMovie,
    required String language,
  }) async {
    final cacheKey = '${isMovie ? 'm' : 't'}_$tmdbId';
    final cached = _logoCache[cacheKey];
    if (cached != null) return cached;

    final path = isMovie ? '/movie/$tmdbId/images' : '/tv/$tmdbId/images';
    final data = await _get(
      path,
      query: {'include_image_language': '$language,null,en,es-MX,es'},
      language: language,
    );
    if (data == null) {
      _logoCache[cacheKey] = '';
      return '';
    }

    final logos = (data['logos'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['logos'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    if (logos.isEmpty) {
      _logoCache[cacheKey] = '';
      return '';
    }

    final langCode = language.split('-').first; // es-MX → es
    Map<String, dynamic>? pick;

    for (final l in logos) {
      if ((l['iso_639_1']?.toString() ?? '') == langCode) {
        pick = l;
        break;
      }
    }
    pick ??= logos.cast<Map<String, dynamic>?>().firstWhere(
          (l) {
            final iso = l!['iso_639_1'];
            return iso == null || (iso is String && iso.isEmpty);
          },
          orElse: () => null,
        );
    if (pick == null) {
      for (final l in logos) {
        if ((l['iso_639_1']?.toString() ?? '') == 'en') {
          pick = l;
          break;
        }
      }
    }
    pick ??= logos.first;

    final file = pick['file_path']?.toString() ?? '';
    final url = file.isNotEmpty ? '$_imgBase/w500$file' : '';
    _logoCache[cacheKey] = url;
    return url;
  }

  /// Enriquece ítems con logos (paralelo, limitado).
  Future<List<Map<String, dynamic>>> _attachLogos(
    List<Map<String, dynamic>> items, {
    required String language,
    int maxToFetch = 24,
  }) async {
    final toFetch = items.take(maxToFetch).toList();
    final futures = toFetch.map((item) async {
      final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
      if (id <= 0) return item;
      final isMovie = (item['media_type']?.toString() ?? 'movie') == 'movie';
      final logo = await _fetchLogo(
        tmdbId: id,
        isMovie: isMovie,
        language: language,
      );
      if (logo.isEmpty) return item;
      return {...item, 'logo_path': logo};
    });

    final enriched = await Future.wait(futures);
    final byId = <int, Map<String, dynamic>>{};
    for (final e in enriched) {
      final id = e['tmdb_id'] as int? ?? 0;
      if (id > 0) byId[id] = e;
    }
    return items.map((item) {
      final id = item['tmdb_id'] as int? ?? 0;
      return byId[id] ?? item;
    }).toList();
  }

  // ── Mapeo ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> _mapItem(Map<String, dynamic> raw, {required bool isMovie}) {
    final id = raw['id'] as int? ?? 0;
    final title = isMovie
        ? (raw['title']?.toString() ?? raw['original_title']?.toString() ?? '')
        : (raw['name']?.toString() ?? raw['original_name']?.toString() ?? '');

    final posterPath = raw['poster_path']?.toString() ?? '';
    final backdropPath = raw['backdrop_path']?.toString() ?? '';

    final posterUrl = posterPath.isNotEmpty ? '$_imgBase/w500$posterPath' : '';
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

  // ── Backdrops sin idioma ──────────────────────────────────────────────────

  Future<String> pickRandomBackdropWithoutLanguage({
    required int tmdbId,
    required bool isMovie,
    String? fallbackPath,
  }) async {
    final path = isMovie ? '/movie/$tmdbId/images' : '/tv/$tmdbId/images';
    final data = await _get(
      path,
      query: {'include_image_language': 'null,es,en'},
      language: 'es-MX',
    );
    if (data == null) return _fullBackdrop(fallbackPath);

    final backdrops = (data['backdrops'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['backdrops'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    final noLang = backdrops.where((b) {
      final lang = b['iso_639_1'];
      return lang == null || (lang is String && lang.isEmpty);
    }).toList();

    final pool = noLang.isNotEmpty ? noLang : backdrops;
    if (pool.isEmpty) return _fullBackdrop(fallbackPath);

    final chosen = pool[_rng.nextInt(pool.length)];
    final file = chosen['file_path']?.toString();
    return _fullBackdrop(file ?? fallbackPath);
  }

  String _fullBackdrop(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$_imgBase/w1280$path';
  }

  // ── Home ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchHome() async {
    final prefs = await _loadPrefs();
    final language = await _apiLanguage(prefs);

    final futures = <String, Future<List<Map<String, dynamic>>>>{};

    if (prefs.homeFeaturedMovies) {
      futures['top_movies'] = _listResultsMultiPage(
        '/movie/top_rated',
        language: language,
        max: _targetPerSection + 10,
      );
    }
    if (prefs.homeFeaturedSeries) {
      futures['top_tv'] = _listResultsMultiPage(
        '/tv/top_rated',
        language: language,
        max: _targetPerSection + 10,
      );
    }
    if (prefs.homePopularMovies) {
      futures['popular_movies'] = _listResultsMultiPage(
        '/movie/popular',
        language: language,
        max: _targetPerSection + 10,
      );
    }
    if (prefs.homePopularSeries) {
      futures['popular_tv'] = _listResultsMultiPage(
        '/tv/popular',
        language: language,
        max: _targetPerSection + 10,
      );
    }
    if (prefs.homeTrendingMovies) {
      futures['trending_movies'] = _listResultsMultiPage(
        '/trending/movie/week',
        language: language,
        max: _targetPerSection + 10,
      );
    }
    if (prefs.homeTrendingSeries) {
      futures['trending_tv'] = _listResultsMultiPage(
        '/trending/tv/week',
        language: language,
        max: _targetPerSection + 10,
      );
    }
    if (prefs.homeLatest) {
      futures['now_playing'] = _listResultsMultiPage(
        '/movie/now_playing',
        language: language,
        max: _targetPerSection + 10,
      );
      futures['on_the_air'] = _listResultsMultiPage(
        '/tv/on_the_air',
        language: language,
        max: _targetPerSection + 10,
      );
      futures['recent_discover_movies'] = _listResultsMultiPage(
        '/discover/movie',
        query: {
          ..._baseDiscover(prefs, isMovie: true),
          'sort_by': 'primary_release_date.desc',
        },
        language: language,
        max: _targetPerSection + 10,
      );
    }

    final year = DateTime.now().year.toString();
    if (prefs.homeYearMovies) {
      futures['year_movies'] = _listResultsMultiPage(
        '/discover/movie',
        query: {
          ..._baseDiscover(prefs, isMovie: true),
          'primary_release_year': year,
          'sort_by': 'popularity.desc',
        },
        language: language,
        max: _targetPerSection + 10,
      );
    }
    if (prefs.homeYearSeries) {
      futures['year_tv'] = _listResultsMultiPage(
        '/discover/tv',
        query: {
          ..._baseDiscover(prefs, isMovie: false),
          'first_air_date_year': year,
          'sort_by': 'popularity.desc',
        },
        language: language,
        max: _targetPerSection + 10,
      );
    }

    final keys = futures.keys.toList();
    final results = await Future.wait(futures.values);
    final rawMap = <String, List<Map<String, dynamic>>>{};
    for (var i = 0; i < keys.length; i++) {
      rawMap[keys[i]] = results[i];
    }

    Future<Map<String, dynamic>?> section(
      String title,
      List<Map<String, dynamic>>? raw, {
      required bool isMovie,
      int minItems = 4,
      bool withLogos = true,
    }) async {
      if (raw == null || raw.isEmpty) return null;
      final filtered = _applyFilters(raw, prefs, isMovie: isMovie);
      if (filtered.length < minItems) return null;

      var mapped = filtered
          .take(_targetPerSection)
          .map((e) => _mapItem(e, isMovie: isMovie))
          .where((e) => (e['poster_path'] as String).isNotEmpty)
          .toList();
      if (mapped.length < minItems) return null;

      if (withLogos && prefs.tmdbEnrichment) {
        mapped = await _attachLogos(mapped, language: language);
      }

      return {'title': title, 'items': mapped};
    }

    final data = <String, dynamic>{};

    final topM = await section(
      'Destacadas - Películas',
      rawMap['top_movies'],
      isMovie: true,
    );
    if (topM != null) data['top_movies'] = topM;

    final topT = await section(
      'Destacadas - Series',
      rawMap['top_tv'],
      isMovie: false,
    );
    if (topT != null) data['top_tv'] = topT;

    final popM = await section(
      'Populares - Películas',
      rawMap['popular_movies'],
      isMovie: true,
    );
    if (popM != null) data['popular_movies'] = popM;

    final popT = await section(
      'Populares - Series',
      rawMap['popular_tv'],
      isMovie: false,
    );
    if (popT != null) data['popular_tv'] = popT;

    final trM = await section(
      'Tendencia - Películas',
      rawMap['trending_movies'],
      isMovie: true,
    );
    if (trM != null) data['trending_movies'] = trM;

    final trT = await section(
      'Tendencia - Series',
      rawMap['trending_tv'],
      isMovie: false,
    );
    if (trT != null) data['trending_tv'] = trT;

    if (prefs.homeLatest) {
      final latestRaw = <Map<String, dynamic>>[
        ...?rawMap['now_playing'],
        ...?rawMap['recent_discover_movies'],
      ];
      final seen = <int>{};
      final deduped = <Map<String, dynamic>>[];
      for (final m in latestRaw) {
        final id = m['id'] as int? ?? 0;
        if (id > 0 && !seen.contains(id)) {
          seen.add(id);
          deduped.add(m);
        }
      }
      final latest = await section(
        'Últimos estrenos - Películas',
        deduped,
        isMovie: true,
      );
      if (latest != null) data['recent_movies'] = latest;

      final recentTv = await section(
        'Últimos estrenos - Series',
        rawMap['on_the_air'],
        isMovie: false,
      );
      if (recentTv != null) data['recent_tv'] = recentTv;
    }

    final yM = await section(
      'Por año - Películas',
      rawMap['year_movies'],
      isMovie: true,
    );
    if (yM != null) data['year_movies'] = yM;

    final yT = await section(
      'Por año - Series',
      rawMap['year_tv'],
      isMovie: false,
    );
    if (yT != null) data['year_tv'] = yT;

    if (prefs.homeSessions) {
      data['continue_watching'] = {
        'title': 'Seguir viendo',
        'items': <Map<String, dynamic>>[],
      };
    }

    if (prefs.tmdbEnrichment) {
      final genreSliders = await _buildGenreSliders(prefs, language);
      if (genreSliders.isNotEmpty) {
        data['movie_genre_sliders'] = genreSliders;
      }
    }

    return {
      'success': true,
      'data': data,
    };
  }

  Future<List<Map<String, dynamic>>> _buildGenreSliders(
    _HomePrefs prefs,
    String language,
  ) async {
    const genres = [
      (28, 'Acción'),
      (35, 'Comedia'),
      (18, 'Drama'),
      (27, 'Terror'),
      (878, 'Ciencia ficción'),
      (53, 'Suspense'),
      (10749, 'Romance'),
    ];

    final out = <Map<String, dynamic>>[];
    await Future.wait(genres.map((g) async {
      final items = await _listResultsMultiPage(
        '/discover/movie',
        query: {
          ..._baseDiscover(prefs, isMovie: true),
          'with_genres': g.$1.toString(),
          'sort_by': 'popularity.desc',
        },
        language: language,
        max: _targetPerSection + 8,
      );
      final filtered = _applyFilters(items, prefs, isMovie: true);
      if (filtered.length < 4) return;

      var mapped = filtered
          .take(_targetPerSection)
          .map((e) => _mapItem(e, isMovie: true))
          .where((e) => (e['poster_path'] as String).isNotEmpty)
          .toList();
      if (mapped.length < 4) return;

      mapped = await _attachLogos(mapped, language: language, maxToFetch: 12);
      out.add({'name': g.$2, 'items': mapped});
    }));

    out.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return out;
  }
}

class _HomePrefs {
  final bool tmdbEnrichment;
  final bool allowAdult;
  final bool showUnreleased;
  final bool homeSessions;
  final bool homeFeaturedMovies;
  final bool homePopularMovies;
  final bool homePopularSeries;
  final bool homeYearMovies;
  final bool homeFeaturedSeries;
  final bool homeYearSeries;
  final bool homeTrendingMovies;
  final bool homeTrendingSeries;
  final bool homeLatest;
  /// Excluir solo asiático / indio / ruso.
  final bool regionalFilter;
  /// Idioma de metadatos de la API (no filtro de contenido).
  final bool spanishLatino;
  final bool spanishCastellano;
  final bool english;
  final bool disableNonLatin;

  const _HomePrefs({
    required this.tmdbEnrichment,
    required this.allowAdult,
    required this.showUnreleased,
    required this.homeSessions,
    required this.homeFeaturedMovies,
    required this.homePopularMovies,
    required this.homePopularSeries,
    required this.homeYearMovies,
    required this.homeFeaturedSeries,
    required this.homeYearSeries,
    required this.homeTrendingMovies,
    required this.homeTrendingSeries,
    required this.homeLatest,
    required this.regionalFilter,
    required this.spanishLatino,
    required this.spanishCastellano,
    required this.english,
    required this.disableNonLatin,
  });
}