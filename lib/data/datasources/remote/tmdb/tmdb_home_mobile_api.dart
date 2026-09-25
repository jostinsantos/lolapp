import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/tmdb_apis.dart';

/// Servicio de Home (móvil) alimentado por TMDB.
/// Misma lógica de preferencias/filtros que TmdbHomeService (TV),
/// pero con estructura orientada a la UI móvil y un main_slider propio.
///
/// API key: a2d9bbed370d9f678e34006f8750a5a5
class TmdbHomeMobileService {
  static const String _apiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5'; // unused fallback
  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  static const int _minVoteCountMovies = 80;
  static const int _minVoteCountTv = 40;
  static const double _minPopularity = 8.0;
  static const int _targetPerSection = 18;
  static const int _pagesToFetch = 3;
  static const int _mainSliderSize = 8;

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
  };

  static const Set<String> _excludedRegionalLangs = {
    'hi', 'te', 'ta', 'ml', 'kn', 'bn', 'mr', 'pa', 'gu', 'ur', 'ne', 'si',
    'zh', 'cn', 'ja', 'ko', 'th', 'vi', 'id', 'ms', 'tl', 'fil', 'my', 'km', 'lo',
    'ru',
  };

  final math.Random _rng = math.Random();
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
      final poster = item['poster_path']?.toString() ?? '';
      if (poster.isEmpty) return false;

      final voteCount = (item['vote_count'] is num)
          ? (item['vote_count'] as num).toInt()
          : int.tryParse('${item['vote_count']}') ?? 0;
      final popularity = (item['popularity'] is num)
          ? (item['popularity'] as num).toDouble()
          : double.tryParse('${item['popularity']}') ?? 0.0;

      if (voteCount < minVotes && popularity < _minPopularity) return false;

      if (item['adult'] == true && !prefs.allowAdult) return false;

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

      final origLang =
          (item['original_language'] ?? '').toString().toLowerCase();
      if (prefs.regionalFilter && _excludedRegionalLangs.contains(origLang)) {
        return false;
      }

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
    if (!isMovie && TmdbApis.tvWithoutGenres.isNotEmpty) {
      q['without_genres'] = TmdbApis.tvWithoutGenres;
    }
    return q;
  }

  // ── Logos ─────────────────────────────────────────────────────────────────

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

    final langCode = language.split('-').first;
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
      'type': isMovie ? 'movie' : 'tv', // compat con _HeroSlide móvil
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

  // ── Main slider (hero) ────────────────────────────────────────────────────

  /// Construye el slider principal del home móvil.
  /// Prioridad:
  /// 1. Trending semana (películas + series)
  /// 2. Popular
  /// 3. Solo ítems con backdrop
  /// 4. Enriquecidos con logo
  /// 5. Mezcla equilibrada movie/tv y sin duplicados
  Future<List<Map<String, dynamic>>> _buildMainSlider(
    _HomePrefs prefs,
    String language,
    Map<String, List<Map<String, dynamic>>> rawMap,
  ) async {
    final pool = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addRaw(List<Map<String, dynamic>>? list, {required bool isMovie}) {
      if (list == null) return;
      for (final raw in list) {
        final id = raw['id'] as int? ?? 0;
        if (id <= 0) continue;
        final key = '${isMovie ? 'm' : 't'}_$id';
        if (seen.contains(key)) continue;

        // Requiere backdrop para que el hero se vea bien
        final backdrop = raw['backdrop_path']?.toString() ?? '';
        if (backdrop.isEmpty) continue;

        if (!_applyFilters([raw], prefs, isMovie: isMovie).isNotEmpty) continue;

        seen.add(key);
        pool.add({...raw, '_isMovie': isMovie});
      }
    }

    // Orden de prioridad de fuentes
    addRaw(rawMap['trending_movies'], isMovie: true);
    addRaw(rawMap['trending_tv'], isMovie: false);
    addRaw(rawMap['popular_movies'], isMovie: true);
    addRaw(rawMap['popular_tv'], isMovie: false);
    addRaw(rawMap['now_playing'], isMovie: true);
    addRaw(rawMap['top_movies'], isMovie: true);
    addRaw(rawMap['top_tv'], isMovie: false);

    if (pool.isEmpty) return [];

    // Ordenar por popularidad
    pool.sort((a, b) {
      final pa = (a['popularity'] is num)
          ? (a['popularity'] as num).toDouble()
          : 0.0;
      final pb = (b['popularity'] is num)
          ? (b['popularity'] as num).toDouble()
          : 0.0;
      return pb.compareTo(pa);
    });

    // Equilibrar: intentar ~50/50 movie/tv
    final movies = pool.where((e) => e['_isMovie'] == true).toList();
    final tvs = pool.where((e) => e['_isMovie'] == false).toList();

    final selected = <Map<String, dynamic>>[];
    var mi = 0, ti = 0;
    while (selected.length < _mainSliderSize &&
        (mi < movies.length || ti < tvs.length)) {
      if (mi < movies.length &&
          (selected.length.isEven || ti >= tvs.length)) {
        selected.add(movies[mi++]);
      } else if (ti < tvs.length) {
        selected.add(tvs[ti++]);
      } else if (mi < movies.length) {
        selected.add(movies[mi++]);
      }
    }

    // Mapear + logos (importante para el hero)
    var mapped = selected.map((e) {
      final isMovie = e['_isMovie'] == true;
      return _mapItem(e, isMovie: isMovie);
    }).toList();

    if (prefs.tmdbEnrichment) {
      mapped = await _attachLogos(
        mapped,
        language: language,
        maxToFetch: _mainSliderSize,
      );
    }

    // Preferir los que ya tienen logo; si faltan, se quedan igual
    mapped.sort((a, b) {
      final la = (a['logo_path']?.toString() ?? '').isNotEmpty ? 1 : 0;
      final lb = (b['logo_path']?.toString() ?? '').isNotEmpty ? 1 : 0;
      return lb.compareTo(la);
    });

    return mapped.take(_mainSliderSize).toList();
  }

  // ── Home ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchHome() async {
    final prefs = await _loadPrefs();
    final language = await _apiLanguage(prefs);

    final futures = <String, Future<List<Map<String, dynamic>>>>{};

    // Siempre pedimos datos útiles para el main_slider
    futures['trending_movies'] = _listResultsMultiPage(
      '/trending/movie/week',
      language: language,
      max: 30,
    );
    futures['trending_tv'] = _listResultsMultiPage(
      '/trending/tv/week',
      language: language,
      max: 30,
    );
    futures['popular_movies'] = _listResultsMultiPage(
      '/movie/popular',
      language: language,
      max: _targetPerSection + 12,
    );
    futures['popular_tv'] = _listResultsMultiPage(
      '/tv/popular',
      language: language,
      max: _targetPerSection + 12,
    );
    futures['top_movies'] = _listResultsMultiPage(
      '/movie/top_rated',
      language: language,
      max: _targetPerSection + 10,
    );
    futures['top_tv'] = _listResultsMultiPage(
      '/tv/top_rated',
      language: language,
      max: _targetPerSection + 10,
    );

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
      bool withLogos = false,
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
        mapped = await _attachLogos(mapped, language: language, maxToFetch: 12);
      }

      return {'title': title, 'items': mapped};
    }

    final data = <String, dynamic>{};

    // ── Main slider (hero móvil) ──────────────────────────────────────────
    final mainSlider = await _buildMainSlider(prefs, language, rawMap);
    if (mainSlider.isNotEmpty) {
      data['main_slider'] = mainSlider;
    }

    // ── Secciones normales ────────────────────────────────────────────────
    if (prefs.homeFeaturedMovies) {
      final topM = await section(
        'Mejores Valoradas - Películas',
        rawMap['top_movies'],
        isMovie: true,
      );
      if (topM != null) data['top_movies'] = topM;
    }
    if (prefs.homeFeaturedSeries) {
      final topT = await section(
        'Mejores Valoradas - Series',
        rawMap['top_tv'],
        isMovie: false,
      );
      if (topT != null) data['top_tv'] = topT;
    }

    if (prefs.homePopularMovies) {
      final popM = await section(
        'Populares - Películas',
        rawMap['popular_movies'],
        isMovie: true,
      );
      if (popM != null) data['popular_movies'] = popM;
    }
    if (prefs.homePopularSeries) {
      final popT = await section(
        'Populares - Series',
        rawMap['popular_tv'],
        isMovie: false,
      );
      if (popT != null) data['popular_tv'] = popT;
    }

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
        'Agregados Recientemente - Películas',
        deduped,
        isMovie: true,
      );
      if (latest != null) data['recent_movies'] = latest;

      final recentTv = await section(
        'Agregados Recientemente - Series',
        rawMap['on_the_air'],
        isMovie: false,
      );
      if (recentTv != null) data['recent_tv'] = recentTv;
    }

    // year opcional (por si lo usas después)
    if (prefs.homeYearMovies) {
      final yM = await section(
        'Por año - Películas',
        rawMap['year_movies'],
        isMovie: true,
      );
      if (yM != null) data['year_movies'] = yM;
    }
    if (prefs.homeYearSeries) {
      final yT = await section(
        'Por año - Series',
        rawMap['year_tv'],
        isMovie: false,
      );
      if (yT != null) data['year_tv'] = yT;
    }

    // Géneros (móvil ya los usa)
    if (prefs.tmdbEnrichment) {
      final genreSliders = await _buildGenreSliders(prefs, language);
      if (genreSliders.isNotEmpty) {
        data['movie_genre_sliders'] = genreSliders;
      }
    }

    // continue_watching vacío (el historial lo carga la página desde prefs)
    if (prefs.homeSessions) {
      data['continue_watching'] = {
        'title': 'Continuar Viendo',
        'items': <Map<String, dynamic>>[],
      };
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

      // En móvil los logos de género no son críticos; opcional
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
  final bool regionalFilter;
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