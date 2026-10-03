import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/content.dart';

/// Catálogo por defecto: The Movie Database.
class TmdbService {
  /// Placeholder; el addon debe traer apiKey en config.
  static const defaultKey = '';
  TmdbService({this.apiKey = ''});

  final String apiKey;
  static const _base = 'https://api.themoviedb.org/3';
  static const _img = 'https://image.tmdb.org/t/p';

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'User-Agent': 'NuvioLight/1.0',
      };

  Future<List<CatalogRow>> getHomeRows({String language = 'es-MX'}) async {
    final rows = <CatalogRow>[];

    final popularMovies = await _fetchList(
      '$_base/movie/popular?api_key=$apiKey&language=$language&page=1',
      ContentType.movie,
    );
    rows.add(CatalogRow(
      id: 'tmdb-popular-movies',
      title: 'Películas populares',
      items: popularMovies,
      addonId: 'tmdb',
    ));

    final topRated = await _fetchList(
      '$_base/movie/top_rated?api_key=$apiKey&language=$language&page=1',
      ContentType.movie,
    );
    rows.add(CatalogRow(
      id: 'tmdb-top-movies',
      title: 'Mejor valoradas',
      items: topRated,
      addonId: 'tmdb',
    ));

    final popularTv = await _fetchList(
      '$_base/tv/popular?api_key=$apiKey&language=$language&page=1',
      ContentType.series,
    );
    rows.add(CatalogRow(
      id: 'tmdb-popular-tv',
      title: 'Series populares',
      items: popularTv,
      addonId: 'tmdb',
    ));

    final topTv = await _fetchList(
      '$_base/tv/top_rated?api_key=$apiKey&language=$language&page=1',
      ContentType.series,
    );
    rows.add(CatalogRow(
      id: 'tmdb-top-tv',
      title: 'Series mejor valoradas',
      items: topTv,
      addonId: 'tmdb',
    ));

    final trending = await _fetchList(
      '$_base/trending/all/week?api_key=$apiKey&language=$language',
      null,
    );
    rows.add(CatalogRow(
      id: 'tmdb-trending',
      title: 'Tendencias de la semana',
      items: trending,
      addonId: 'tmdb',
    ));

    return rows;
  }

  /// Filas por género (para categorías / géneros).
  Future<List<CatalogRow>> getGenreRows({
    required bool movies,
    String language = 'es-MX',
  }) async {
    final path = movies ? 'movie' : 'tv';
    final type = movies ? ContentType.movie : ContentType.series;
    final genresUrl =
        '$_base/genre/$path/list?api_key=$apiKey&language=$language';
    try {
      final res = await http.get(Uri.parse(genresUrl), headers: _headers);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final genres = (data['genres'] as List? ?? []).take(8).toList();
      final rows = <CatalogRow>[];
      for (final g in genres) {
        final id = g['id'];
        final name = g['name'] as String? ?? 'Género';
        final items = await _fetchList(
          '$_base/discover/$path?api_key=$apiKey&language=$language&with_genres=$id&sort_by=popularity.desc&page=1',
          type,
        );
        if (items.isNotEmpty) {
          rows.add(CatalogRow(
            id: 'tmdb-genre-$path-$id',
            title: name,
            items: items,
            addonId: 'tmdb',
          ));
        }
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  Future<List<ContentItem>> search(String query, {String language = 'es-MX'}) async {
    if (query.trim().isEmpty) return [];
    final url =
        '$_base/search/multi?api_key=$apiKey&language=$language&query=${Uri.encodeComponent(query)}&page=1';
    final res = await http.get(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = data['results'] as List? ?? [];
    return results
        .map((e) => _mapItem(e as Map<String, dynamic>))
        .whereType<ContentItem>()
        .toList();
  }

  Future<ContentItem?> getDetails(String type, String tmdbId,
      {String language = 'es-MX'}) async {
    final path = type == 'tv' || type == 'series' ? 'tv' : 'movie';
    final append = path == 'tv'
        ? 'external_ids,credits,videos,images,similar,recommendations,content_ratings'
        : 'external_ids,credits,videos,images,similar,recommendations,release_dates';
    final url =
        '$_base/$path/$tmdbId?api_key=$apiKey&language=$language&append_to_response=$append&include_image_language=en,null';
    final res = await http.get(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final item = _mapItem(
      data,
      forceType: path == 'tv' ? ContentType.series : ContentType.movie,
    );
    if (item == null) return null;

    final genres = <String>[];
    if (data['genres'] is List) {
      for (final g in data['genres'] as List) {
        if (g is Map && g['name'] != null) genres.add(g['name'].toString());
      }
    }

    final extra = Map<String, dynamic>.from(item.extra);
    extra['tmdbId'] = tmdbId;
    extra['mediaType'] = path;
    extra['enrichedTmdb'] = true;
    if (data['number_of_seasons'] != null) {
      extra['numberOfSeasons'] = data['number_of_seasons'];
    }
    if (data['number_of_episodes'] != null) {
      extra['numberOfEpisodes'] = data['number_of_episodes'];
    }
    if (data['status'] != null) extra['status'] = data['status'];
    if (data['runtime'] != null) extra['runtime'] = data['runtime'];
    if (data['episode_run_time'] is List &&
        (data['episode_run_time'] as List).isNotEmpty) {
      extra['runtime'] = (data['episode_run_time'] as List).first;
    }
    if (data['original_language'] != null) {
      extra['originalLanguage'] =
          data['original_language'].toString().toUpperCase();
    }
    if (data['production_countries'] is List) {
      final countries = <String>[];
      for (final c in data['production_countries'] as List) {
        if (c is Map && c['name'] != null) countries.add(c['name'].toString());
        else if (c is String) countries.add(c);
      }
      if (countries.isNotEmpty) extra['countries'] = countries;
    }
    if (data['external_ids'] is Map) {
      final ext = data['external_ids'] as Map;
      extra['imdbId'] = ext['imdb_id'];
      if (ext['tvdb_id'] != null) extra['tvdbId'] = ext['tvdb_id'];
    }
    // Logo
    if (data['images'] is Map) {
      final logos = (data['images'] as Map)['logos'];
      if (logos is List && logos.isNotEmpty) {
        Map? best;
        for (final l in logos) {
          if (l is! Map) continue;
          final lang = l['iso_639_1']?.toString();
          if (lang == 'en' || lang == null || lang == 'null') {
            best = l;
            break;
          }
          best ??= l;
        }
        final pathLogo = best?['file_path']?.toString();
        if (pathLogo != null && pathLogo.isNotEmpty) {
          extra['logo'] = pathLogo.startsWith('http')
              ? pathLogo
              : '$_img/w500$pathLogo';
          extra['logo_path'] = extra['logo'];
        }
      }
    }
    // Collection
    if (data['belongs_to_collection'] is Map) {
      final col = Map<String, dynamic>.from(data['belongs_to_collection'] as Map);
      if (col['poster_path'] != null) {
        col['poster'] = '$_img/w300${col['poster_path']}';
      }
      extra['collection'] = col;
    }
    // Cast
    if (data['credits'] is Map) {
      final cast = (data['credits'] as Map)['cast'];
      if (cast is List) {
        extra['cast'] = cast.take(20).map((c) {
          if (c is! Map) return <String, dynamic>{};
          final m = Map<String, dynamic>.from(c);
          final pp = m['profile_path']?.toString();
          if (pp != null && pp.isNotEmpty && !pp.startsWith('http')) {
            m['profile_path'] = '$_img/w185$pp';
            m['photo'] = m['profile_path'];
          }
          return m;
        }).toList();
      }
    }
    // Videos
    if (data['videos'] is Map) {
      final results = (data['videos'] as Map)['results'];
      if (results is List) {
        extra['videos'] = results
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
      }
    }
    // Similar
    if (data['similar'] is Map) {
      final results = (data['similar'] as Map)['results'];
      if (results is List) {
        extra['similar'] = results
            .whereType<Map>()
            .map((v) {
              final m = Map<String, dynamic>.from(v);
              final pp = m['poster_path']?.toString();
              if (pp != null && pp.isNotEmpty) {
                m['poster'] = pp.startsWith('http') ? pp : '$_img/w342$pp';
              }
              return m;
            })
            .toList();
      }
    }
    // Temporadas (sin specials / season 0)
    if (path == 'tv' && data['seasons'] is List) {
      final seasons = <Map<String, dynamic>>[];
      for (final s in data['seasons'] as List) {
        if (s is! Map) continue;
        final sn = s['season_number'] as int? ?? 0;
        if (sn < 1) continue;
        seasons.add({
          'seasonNumber': sn,
          'name': s['name'] ?? 'Temporada $sn',
          'episodeCount': s['episode_count'] ?? 0,
          'poster': s['poster_path'] != null
              ? '$_img/w300${s['poster_path']}'
              : null,
          'overview': s['overview'],
          'airDate': s['air_date'],
        });
      }
      extra['seasons'] = seasons;
    }

    return ContentItem(
      id: item.id,
      title: item.title,
      originalTitle: item.originalTitle,
      type: item.type,
      poster: item.poster,
      backdrop: item.backdrop,
      overview: item.overview,
      year: item.year,
      rating: item.rating,
      genres: genres,
      addonId: item.addonId,
      extra: extra,
    );
  }

  /// Episodios de una temporada.
  Future<List<EpisodeInfo>> getSeasonEpisodes(
    String tmdbId,
    int seasonNumber, {
    String language = 'es-MX',
  }) async {
    final url =
        '$_base/tv/$tmdbId/season/$seasonNumber?api_key=$apiKey&language=$language';
    try {
      final res = await http.get(Uri.parse(url), headers: _headers);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final eps = data['episodes'] as List? ?? [];
      final now = DateTime.now();
      final out = <EpisodeInfo>[];
      for (final e in eps) {
        final m = e as Map<String, dynamic>;
        final air = m['air_date']?.toString();
        if (air != null && air.length >= 10) {
          final d = DateTime.tryParse(air);
          // No mostrar capítulos que aún no se estrenan
          if (d != null && d.isAfter(now)) continue;
        }
        final epNum = m['episode_number'] as int? ?? 0;
        if (epNum < 1) continue;
        final still = m['still_path'] as String?;
        out.add(EpisodeInfo(
          seasonNumber: seasonNumber,
          episodeNumber: epNum,
          name: (m['name'] as String?) ?? 'Episodio',
          overview: m['overview'] as String?,
          still: still != null ? '$_img/w300$still' : null,
          airDate: air,
          rating: (m['vote_average'] as num?)?.toDouble(),
          runtime: m['runtime'] as int?,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<ContentItem>> _fetchList(
      String url, ContentType? forceType) async {
    try {
      final res = await http.get(Uri.parse(url), headers: _headers);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];
      return results
          .map((e) => _mapItem(e as Map<String, dynamic>, forceType: forceType))
          .whereType<ContentItem>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  ContentItem? _mapItem(Map<String, dynamic> e, {ContentType? forceType}) {
    final mediaType = e['media_type'] as String?;
    ContentType type;
    if (forceType != null) {
      type = forceType;
    } else if (mediaType == 'tv') {
      type = ContentType.series;
    } else if (mediaType == 'movie') {
      type = ContentType.movie;
    } else if (e.containsKey('title') && !e.containsKey('name')) {
      type = ContentType.movie;
    } else if (e.containsKey('name') && !e.containsKey('title')) {
      type = ContentType.series;
    } else if (e.containsKey('title')) {
      type = ContentType.movie;
    } else if (e.containsKey('name')) {
      type = ContentType.series;
    } else {
      return null;
    }

    final idNum = e['id'];
    if (idNum == null) return null;
    final prefix = type == ContentType.series ? 'tmdb:series' : 'tmdb:movie';
    final title = (e['title'] ?? e['name'] ?? '') as String;
    if (title.isEmpty) return null;

    final date = (e['release_date'] ?? e['first_air_date'] ?? '') as String;
    final year = date.length >= 4 ? date.substring(0, 4) : null;

    final posterPath = e['poster_path'] as String?;
    final backdropPath = e['backdrop_path'] as String?;

    return ContentItem(
      id: '$prefix:$idNum',
      title: title,
      originalTitle: (e['original_title'] ?? e['original_name']) as String?,
      type: type,
      poster: posterPath != null ? '$_img/w500$posterPath' : null,
      backdrop: backdropPath != null ? '$_img/w1280$backdropPath' : null,
      overview: e['overview'] as String?,
      year: year,
      rating: (e['vote_average'] as num?)?.toDouble(),
      genres: const [],
      addonId: 'tmdb',
      extra: {
        'tmdbId': idNum,
        'mediaType': type == ContentType.series ? 'tv' : 'movie',
      },
    );
  }


  /// Descubrir por categoría + género (UI de Catálogos).
  /// category: movie | tv | anime | dorama
  Future<List<ContentItem>> discover({
    required String category,
    int? genreId,
    int page = 1,
    String language = 'es-MX',
  }) async {
    String path = 'movie';
    final extra = <String, String>{};

    switch (category) {
      case 'tv':
        path = 'tv';
        break;
      case 'anime':
        path = 'tv';
        extra['with_keywords'] = '210024'; // anime keyword approx; also use with_origin_country
        extra['with_origin_country'] = 'JP';
        break;
      case 'dorama':
        path = 'tv';
        extra['with_origin_country'] = 'KR';
        break;
      case 'movie':
      default:
        path = 'movie';
    }

    final qp = StringBuffer(
      '$_base/discover/$path?api_key=$apiKey&language=$language&sort_by=popularity.desc&page=$page',
    );
    if (genreId != null) qp.write('&with_genres=$genreId');
    extra.forEach((k, v) => qp.write('&$k=$v'));

    final res = await http.get(Uri.parse(qp.toString()), headers: _headers);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = data['results'] as List? ?? [];
    final type = path == 'tv' ? ContentType.series : ContentType.movie;
    return results
        .map((e) => _mapItem(e as Map<String, dynamic>, forceType: type))
        .whereType<ContentItem>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> listGenres({
    required bool movies,
    String language = 'es-MX',
  }) async {
    final path = movies ? 'movie' : 'tv';
    final url = '$_base/genre/$path/list?api_key=$apiKey&language=$language';
    final res = await http.get(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(
      (data['genres'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  /// Extrae tipo, tmdbId y opcionalmente season/episode.
  /// Formatos:
  ///   tmdb:movie:123
  ///   tmdb:series:123
  ///   tmdb:series:123:1:5  (S1E5)
  static ParsedTmdbId? parseId(String contentId) {
    final parts = contentId.split(':');
    if (parts.length >= 3 && parts[0] == 'tmdb') {
      final type = parts[1] == 'series' ? 'tv' : 'movie';
      final id = parts[2];
      int? season;
      int? episode;
      if (parts.length >= 5) {
        season = int.tryParse(parts[3]);
        episode = int.tryParse(parts[4]);
      }
      return ParsedTmdbId(type: type, id: id, season: season, episode: episode);
    }
    if (parts.length == 2 && int.tryParse(parts[1]) != null) {
      return ParsedTmdbId(type: parts[0], id: parts[1]);
    }
    return null;
  }
}

class ParsedTmdbId {
  final String type; // movie | tv
  final String id;
  final int? season;
  final int? episode;

  const ParsedTmdbId({
    required this.type,
    required this.id,
    this.season,
    this.episode,
  });
}
