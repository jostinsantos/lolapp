import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/tmdb_apis.dart';

class TmdbContentService {
  static const String _apiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5'; // unused fallback
  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  static const List<String> _omdbKeys = ['5b0e8a3e', '1289a38c', 'eb1327da'];

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

  Future<String> _apiLanguage() async {
    return TmdbApis.getLanguage();
  }

  Future<({bool showSpecials, bool showUnreleasedEps})> _episodePrefs() async {
    final p = await SharedPreferences.getInstance();
    return (
      showSpecials: p.getBool('show_season_specials') ?? false,
      showUnreleasedEps: p.getBool('show_unreleased_episodes') ?? false,
    );
  }

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
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 16));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _img(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$_imgBase/$size$path';
  }

  Future<Map<String, dynamic>?> _fetchOmdb(String imdbId) async {
    if (imdbId.isEmpty) return null;
    for (final key in _omdbKeys) {
      try {
        final uri = Uri.parse('https://www.omdbapi.com/?i=$imdbId&apikey=$key');
        final res = await http.get(uri).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic> && data['Response'] == 'True') {
          return data;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String> _fetchLogo({
    required int tmdbId,
    required bool isMovie,
    required String language,
  }) async {
    final path = isMovie ? '/movie/$tmdbId/images' : '/tv/$tmdbId/images';
    final data = await _get(
      path,
      query: {'include_image_language': '$language,null,en,es-MX,es'},
      language: language,
    );
    if (data == null) return '';

    final logos = (data['logos'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['logos'] as List).whereType<Map>().map(
              (e) => Map<String, dynamic>.from(e),
            ),
          )
        : <Map<String, dynamic>>[];

    if (logos.isEmpty) return '';

    final langCode = language.split('-').first;
    Map<String, dynamic>? pick;

    for (final l in logos) {
      if ((l['iso_639_1']?.toString() ?? '') == langCode) {
        pick = l;
        break;
      }
    }
    pick ??= logos.cast<Map<String, dynamic>?>().firstWhere((l) {
      final iso = l!['iso_639_1'];
      return iso == null || (iso is String && iso.isEmpty);
    }, orElse: () => null);
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
    return file.isNotEmpty ? _img(file, size: 'w500') : '';
  }

  Future<Map<String, dynamic>> fetchContent({
    required int tmdbId,
    required String mediaType,
  }) async {
    final isMovie = mediaType.toLowerCase() != 'tv';
    final language = await _apiLanguage();

    final detailPath = isMovie ? '/movie/$tmdbId' : '/tv/$tmdbId';
    final append = isMovie
        ? 'credits,videos,similar,external_ids,images'
        : 'credits,videos,similar,external_ids,images,content_ratings';

    final detail = await _get(
      detailPath,
      query: {'append_to_response': append},
      language: language,
    );

    if (detail == null) {
      return {'success': false, 'error': 'No se encontró el contenido en TMDB'};
    }

    final external = detail['external_ids'] is Map
        ? Map<String, dynamic>.from(detail['external_ids'] as Map)
        : <String, dynamic>{};
    final imdbId = (external['imdb_id'] ?? detail['imdb_id'] ?? '').toString();

    final omdbFuture = imdbId.isNotEmpty
        ? _fetchOmdb(imdbId)
        : Future.value(null);
    final logoFuture = _fetchLogo(
      tmdbId: tmdbId,
      isMovie: isMovie,
      language: language,
    );

    Future<List<Map<String, dynamic>>> seasonsFuture;
    if (isMovie) {
      seasonsFuture = Future.value(<Map<String, dynamic>>[]);
    } else {
      seasonsFuture = _fetchAllSeasons(
        tmdbId: tmdbId,
        language: language,
        seasonsMeta: detail['seasons'] is List
            ? List<Map<String, dynamic>>.from(
                (detail['seasons'] as List).whereType<Map>().map(
                  (e) => Map<String, dynamic>.from(e),
                ),
              )
            : [],
      );
    }

    final results = await Future.wait([omdbFuture, logoFuture, seasonsFuture]);

    final omdb = results[0] as Map<String, dynamic>?;
    final logoUrl = results[1] as String;
    final seasons = results[2] as List<Map<String, dynamic>>;

    final title = isMovie
        ? (detail['title']?.toString() ??
              detail['original_title']?.toString() ??
              '')
        : (detail['name']?.toString() ??
              detail['original_name']?.toString() ??
              '');

    String? director;
    final credits = detail['credits'] is Map
        ? Map<String, dynamic>.from(detail['credits'] as Map)
        : null;
    if (isMovie && credits != null) {
      final crew = credits['crew'] is List ? credits['crew'] as List : [];
      for (final c in crew) {
        if (c is Map && c['job']?.toString() == 'Director') {
          director = c['name']?.toString();
          break;
        }
      }
    } else if (!isMovie) {
      final creators = detail['created_by'] is List
          ? detail['created_by'] as List
          : [];
      if (creators.isNotEmpty && creators.first is Map) {
        director = (creators.first as Map)['name']?.toString();
      }
    }

    final castRaw = (credits?['cast'] is List) ? credits!['cast'] as List : [];
    final cast = castRaw.whereType<Map>().take(16).map((c) {
      final m = Map<String, dynamic>.from(c);
      return {
        'id': m['id'],
        'name': m['name']?.toString() ?? '',
        'character': m['character']?.toString() ?? '',
        'profile_path': m['profile_path']?.toString() ?? '',
        'order': m['order'],
      };
    }).toList();

    final videosRaw = detail['videos'] is Map
        ? Map<String, dynamic>.from(detail['videos'] as Map)
        : <String, dynamic>{};
    final videoResults = (videosRaw['results'] is List)
        ? List<Map<String, dynamic>>.from(
            (videosRaw['results'] as List).whereType<Map>().map(
              (e) => Map<String, dynamic>.from(e),
            ),
          )
        : <Map<String, dynamic>>[];

    final videosEs = <Map<String, dynamic>>[];
    final videosEn = <Map<String, dynamic>>[];
    for (final v in videoResults) {
      if ((v['site']?.toString() ?? '') != 'YouTube') continue;
      final type = (v['type']?.toString() ?? '').toLowerCase();
      if (type != 'trailer' && type != 'teaser' && type != 'clip') continue;
      final item = {
        'key': v['key']?.toString() ?? '',
        'name': v['name']?.toString() ?? 'Trailer',
        'type': v['type']?.toString() ?? '',
        'official': v['official'] == true,
      };
      final lang = (v['iso_639_1']?.toString() ?? '').toLowerCase();
      if (lang == 'es') {
        videosEs.add(item);
      } else if (lang == 'en') {
        videosEn.add(item);
      }
    }
    if (videosEs.isEmpty && videosEn.isNotEmpty) {
      videosEs.addAll(videosEn.take(4));
    }

    final similarRaw = detail['similar'] is Map
        ? Map<String, dynamic>.from(detail['similar'] as Map)
        : <String, dynamic>{};
    final similarResults = (similarRaw['results'] is List)
        ? List<Map<String, dynamic>>.from(
            (similarRaw['results'] as List).whereType<Map>().map(
              (e) => Map<String, dynamic>.from(e),
            ),
          )
        : <Map<String, dynamic>>[];

    final similar = similarResults
        .where((s) => (s['poster_path']?.toString() ?? '').isNotEmpty)
        .take(14)
        .map((s) {
          final sid = s['id'] as int? ?? 0;
          final sTitle = isMovie
              ? (s['title']?.toString() ?? '')
              : (s['name']?.toString() ?? '');
          return {
            'id': sid,
            'idcontenido': sid,
            'tmdb_id': sid,
            'media_type': isMovie ? 'movie' : 'tv',
            'title': sTitle,
            'poster_path': _img(s['poster_path']?.toString(), size: 'w342'),
            'backdrop_path': _img(s['backdrop_path']?.toString(), size: 'w780'),
            'vote_average': s['vote_average'],
            'release_date': isMovie ? s['release_date'] : null,
            'first_air_date': isMovie ? null : s['first_air_date'],
          };
        })
        .toList();

    final genresList = <dynamic>[];
    if (detail['genres'] is List) {
      for (final g in detail['genres'] as List) {
        if (g is Map && g['name'] != null) {
          genresList.add({'id': g['id'], 'name': g['name'].toString()});
        }
      }
    } else if (detail['genre_ids'] is List) {
      final map = isMovie ? _movieGenres : _tvGenres;
      for (final id in (detail['genre_ids'] as List).whereType<num>()) {
        final name = map[id.toInt()];
        if (name != null) genresList.add({'id': id.toInt(), 'name': name});
      }
    }

    dynamic runtime = detail['runtime'];
    List? episodeRunTime;
    if (!isMovie) {
      episodeRunTime = detail['episode_run_time'] is List
          ? detail['episode_run_time'] as List
          : null;
      if ((runtime == null || runtime == 0) &&
          episodeRunTime != null &&
          episodeRunTime.isNotEmpty) {
        runtime = episodeRunTime.first;
      }
    }

    double imdbRating = 0;
    List ratings = [];
    if (omdb != null) {
      imdbRating = double.tryParse(omdb['imdbRating']?.toString() ?? '') ?? 0;
      if (omdb['Ratings'] is List) {
        ratings = omdb['Ratings'] as List;
      }
    }

    final data = <String, dynamic>{
      'idcontenido': tmdbId,
      'tmdb_id': tmdbId,
      'type': isMovie ? 'movie' : 'tv',
      'media_type': isMovie ? 'movie' : 'tv',
      'title': title,
      'original_title': isMovie
          ? detail['original_title']
          : detail['original_name'],
      'overview': detail['overview']?.toString() ?? '',
      'poster_path': _img(detail['poster_path']?.toString(), size: 'w500'),
      'backdrop_path': _img(detail['backdrop_path']?.toString(), size: 'w1280'),
      'logo_path': logoUrl,
      'vote_average': detail['vote_average'],
      'vote_count': detail['vote_count'],
      'popularity': detail['popularity'],
      'adult': detail['adult'] == true,
      'original_language': detail['original_language'],
      'release_date': isMovie ? detail['release_date'] : null,
      'first_air_date': isMovie ? null : detail['first_air_date'],
      'runtime': runtime,
      'episode_run_time': episodeRunTime,
      'status': detail['status'],
      'tagline': detail['tagline']?.toString() ?? '',
      'director': director,
      'genres': genresList,
      'imdb_id': imdbId,
      'external_ids': external,
      'imdb_rating': imdbRating > 0 ? imdbRating : null,
      'vote_imdb': imdbRating > 0 ? imdbRating : null,
      'imdb_data': omdb != null
          ? {
              'imdbID': omdb['imdbID'],
              'imdbRating': omdb['imdbRating'],
              'Metascore': omdb['Metascore'],
              'Ratings': ratings,
              'Rated': omdb['Rated'],
              'Runtime': omdb['Runtime'],
              'Genre': omdb['Genre'],
              'Director': omdb['Director'],
              'Actors': omdb['Actors'],
              'Plot': omdb['Plot'],
              'Awards': omdb['Awards'],
            }
          : null,
      'cast': cast,
      'videos': {'es': videosEs, 'en': videosEn},
      'similar': similar,
      'seasons': seasons,
      'number_of_seasons': isMovie ? null : seasons.length,
      'number_of_episodes': isMovie
          ? null
          : seasons.fold<int>(
              0,
              (sum, s) => sum + ((s['episode_count'] as int?) ?? 0),
            ),
    };

    return {'success': true, 'data': data};
  }

  Future<List<Map<String, dynamic>>> _fetchAllSeasons({
    required int tmdbId,
    required String language,
    required List<Map<String, dynamic>> seasonsMeta,
  }) async {
    final prefs = await _episodePrefs();
    final now = DateTime.now();

    // 1) Filtrar números de temporada (sin T0 si especiales desactivadas)
    final seasonNumbers =
        seasonsMeta
            .map((s) => s['season_number'] as int? ?? -1)
            .where((n) {
              if (n < 0) return false;
              // Especiales / temporada 0
              if (n == 0 && !prefs.showSpecials) return false;
              return true;
            })
            .toSet()
            .toList()
          ..sort();

    if (seasonNumbers.isEmpty) return [];

    final futures = seasonNumbers.map((n) async {
      final data = await _get('/tv/$tmdbId/season/$n', language: language);
      if (data == null) return null;

      final epsRaw = data['episodes'] is List
          ? List<Map<String, dynamic>>.from(
              (data['episodes'] as List).whereType<Map>().map(
                (e) => Map<String, dynamic>.from(e),
              ),
            )
          : <Map<String, dynamic>>[];

      final episodes = <Map<String, dynamic>>[];
      for (final ep in epsRaw) {
        // Filtrar capítulos sin estrenar si está desactivado
        if (!prefs.showUnreleasedEps) {
          final air = ep['air_date']?.toString() ?? '';
          if (air.isNotEmpty) {
            final d = DateTime.tryParse(air);
            if (d != null && d.isAfter(now)) continue;
          }
        }
        episodes.add({
          'id': ep['id'],
          'episode_number': ep['episode_number'],
          'name':
              ep['name']?.toString() ??
              'Episodio ${ep['episode_number'] ?? ''}',
          'overview': ep['overview']?.toString() ?? '',
          'still_path': ep['still_path']?.toString() ?? '',
          'air_date': ep['air_date']?.toString() ?? '',
          'vote_average': ep['vote_average'],
          'vote_count': ep['vote_count'],
          'runtime': ep['runtime'],
          'season_number': ep['season_number'] ?? n,
          'crew': (ep['crew'] is List)
              ? (ep['crew'] as List)
                    .whereType<Map>()
                    .map(
                      (c) => {
                        'name': c['name']?.toString() ?? '',
                        'job': c['job']?.toString() ?? '',
                        'department': c['department']?.toString() ?? '',
                      },
                    )
                    .where((c) => (c['name'] as String).isNotEmpty)
                    .toList()
              : <Map<String, String>>[],
          'guest_stars': (ep['guest_stars'] is List)
              ? (ep['guest_stars'] as List)
                    .whereType<Map>()
                    .map(
                      (g) => {
                        'name': g['name']?.toString() ?? '',
                        'character': g['character']?.toString() ?? '',
                        'profile_path': g['profile_path']?.toString() ?? '',
                      },
                    )
                    .where((g) => (g['name'] as String).isNotEmpty)
                    .take(8)
                    .toList()
              : <Map<String, String>>[],
        });
      }

      // 2) No devolver temporadas sin capítulos (cualquier N, no solo T0)
      if (episodes.isEmpty) return null;

      return {
        'id': data['id'],
        'season_number': data['season_number'] ?? n,
        'name': data['name']?.toString() ?? 'Temporada $n',
        'overview': data['overview']?.toString() ?? '',
        'poster_path': data['poster_path']?.toString() ?? '',
        'air_date': data['air_date']?.toString() ?? '',
        'episode_count': episodes.length,
        'episodes': episodes,
      };
    });

    final results = await Future.wait(futures);

    // 3) Solo temporadas válidas con al menos 1 episodio
    final seasons = results.whereType<Map<String, dynamic>>().toList()
      ..sort(
        (a, b) =>
            (a['season_number'] as int).compareTo(b['season_number'] as int),
      );

    return seasons;
  }
}
