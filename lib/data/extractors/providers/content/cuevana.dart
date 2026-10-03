import 'dart:convert';
import 'package:http/http.dart' as http;

class CuevanaService {
  static const String _tmdbApiKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const String _baseUrl = 'https://wv3.cuevana3.eu';
  static const String _playerApi =
      'https://www.modlyo.com/scraper/cuevana/player.php?url=';

  static const List<String> _allowedServers = [
    'streamwish',
    'vidhide',
    'filelions',
    'vidhidepro',
    'streamwish.to',
    'vidhidepro.com',
    'filelions.com',
    'filelions.to',
  ];

  // ────────────────────────────────────────────────
  // API PÚBLICA
  // ────────────────────────────────────────────────

  /// Película
  static Future<Map<String, dynamic>> getMovie(int tmdbId) async {
    return fetch(type: 'movie', id: tmdbId);
  }

  /// Capítulo
  static Future<Map<String, dynamic>> getCapitulo({
    int? tmdbId,
    int? temporada,
    int? capitulo,
    String? url,
  }) async {
    return fetch(
      type: 'capitulo',
      id: tmdbId,
      temporada: temporada,
      capitulo: capitulo,
      url: url,
    );
  }

  /// Temporada completa
  static Future<Map<String, dynamic>> getTemporada({
    required int tmdbId,
    required int temporada,
  }) async {
    return fetch(type: 'temporada', id: tmdbId, temporada: temporada);
  }

  /// Método genérico (igual que la API PHP)
  static Future<Map<String, dynamic>> fetch({
    required String type,
    int? id,
    int? temporada,
    int? capitulo,
    String? url,
  }) async {
    type = type.toLowerCase();

    try {
      if (type == 'movie') {
        if (id == null || id <= 0) {
          return {'success': false, 'error': 'Falta id de TMDB'};
        }
        return await _scrapeMovie(id);
      }

      if (type == 'capitulo') {
        return await _scrapeCapitulo(
          tmdbId: id,
          temporada: temporada,
          capitulo: capitulo,
          url: url,
        );
      }

      if (type == 'temporada') {
        if (id == null || id <= 0 || temporada == null || temporada <= 0) {
          return {'success': false, 'error': 'Falta id y temporada'};
        }
        return await _scrapeTemporada(id, temporada);
      }

      return {
        'success': false,
        'error': 'type inválido. Usa: movie | capitulo | temporada',
      };
    } catch (e) {
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ────────────────────────────────────────────────
  // IMPLEMENTACIÓN
  // ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _scrapeMovie(int tmdbId) async {
    final tmdb = await _getTmdbInfo(tmdbId, 'movie');
    if (tmdb['latino'].toString().isEmpty &&
        tmdb['ingles'].toString().isEmpty) {
      return {'success': false, 'error': 'No se obtuvo info de TMDB'};
    }

    final candidates = _buildCandidates('movie', tmdb);
    final found = await _findWorkingUrl(candidates);

    if (found == null) {
      return {
        'success': false,
        'error': 'No se encontró la película en Cuevana',
        'tried': candidates,
      };
    }

    final pageProps = _extractNextData(found!['html']!);
    if (pageProps == null || pageProps['thisMovie'] == null) {
      return {
        'success': false,
        'error': 'Datos inválidos',
        'url': found['url'],
      };
    }

    var videoGroups = _getVideoGroupsFromData(
      pageProps['thisMovie']['videos'] ?? {},
    );
    videoGroups = await _resolvePlayers(videoGroups);

    return {
      'success': true,
      'type': 'movie',
      'scraped_url': found['url'],
      'tmdb_id': tmdbId,
      'video_groups': videoGroups,
    };
  }

  static Future<Map<String, dynamic>> _scrapeCapitulo({
    int? tmdbId,
    int? temporada,
    int? capitulo,
    String? url,
  }) async {
    String? episodeUrl = url;

    if (episodeUrl == null || episodeUrl.isEmpty) {
      if (tmdbId == null ||
          tmdbId <= 0 ||
          temporada == null ||
          temporada <= 0 ||
          capitulo == null ||
          capitulo <= 0) {
        return {
          'success': false,
          'error': 'Para capitulo usa url= o id+temporada+capitulo',
        };
      }

      final tmdb = await _getTmdbInfo(tmdbId, 'tv');
      final nombres = [
        tmdb['latino'],
        tmdb['castellano'],
        tmdb['ingles'],
      ].where((n) => n.toString().trim().isNotEmpty).toList();

      final candidates = <String>[];
      for (final nombre in nombres) {
        final slug = _slugify(nombre.toString());
        candidates.add(
          '$_baseUrl/episodio/$slug-temporada-$temporada-episodio-$capitulo',
        );
        candidates.add(
          '$_baseUrl/episodio/$slug-$tmdbId-temporada-$temporada-episodio-$capitulo',
        );
      }

      for (final tryUrl in candidates) {
        final html = await _fetch(tryUrl);
        if (html != null &&
            html.contains('__NEXT_DATA__') &&
            html.contains('"episode"')) {
          episodeUrl = tryUrl;
          break;
        }
      }

      if (episodeUrl == null || episodeUrl.isEmpty) {
        return {
          'success': false,
          'error': 'No se encontró el capítulo',
          'tried': candidates,
        };
      }
    }

    var videoGroups = await _scrapeEpisodeVideos(episodeUrl);
    if (videoGroups == null) {
      return {
        'success': false,
        'error': 'Error al scrapear el capítulo',
        'url': episodeUrl,
      };
    }

    videoGroups = await _resolvePlayers(videoGroups);

    return {
      'success': true,
      'type': 'capitulo',
      'scraped_url': episodeUrl,
      'tmdb_id': tmdbId,
      'video_groups': videoGroups,
    };
  }

  static Future<Map<String, dynamic>> _scrapeTemporada(
    int tmdbId,
    int temporada,
  ) async {
    final tmdb = await _getTmdbInfo(tmdbId, 'tv');
    if (tmdb['latino'].toString().isEmpty &&
        tmdb['ingles'].toString().isEmpty) {
      return {'success': false, 'error': 'No se obtuvo info de TMDB'};
    }

    final candidates = _buildCandidates('series', tmdb);
    final found = await _findWorkingUrl(candidates);

    if (found == null) {
      return {
        'success': false,
        'error': 'No se encontró la serie en Cuevana',
        'tried': candidates,
      };
    }

    final pageProps = _extractNextData(found!['html']!);
    if (pageProps == null || pageProps['thisSerie'] == null) {
      return {
        'success': false,
        'error': 'Datos de serie inválidos',
        'url': found['url'],
      };
    }

    final serieData = pageProps['thisSerie'];
    final episodesResult = <Map<String, dynamic>>[];

    final seasons = serieData['seasons'] as List? ?? [];
    for (final season in seasons) {
      if ((season['number'] as int? ?? 0) != temporada) continue;

      final episodes = season['episodes'] as List? ?? [];
      for (final ep in episodes) {
        final slug = ep['slug'] as Map? ?? {};
        final name = slug['name']?.toString() ?? '';
        final s = slug['season']?.toString() ?? '';
        final e = slug['episode']?.toString() ?? '';

        if (name.isEmpty || s.isEmpty || e.isEmpty) continue;

        final epUrl = '$_baseUrl/episodio/$name-temporada-$s-episodio-$e';

        var videoGroups = await _scrapeEpisodeVideos(epUrl);
        if (videoGroups != null) {
          videoGroups = await _resolvePlayers(videoGroups);
        }

        episodesResult.add({
          'episode_number': (ep['number'] ?? 0).toString(),
          'title': ep['title'] ?? 'Sin título',
          'scraped_url': epUrl,
          'video_groups': videoGroups ?? [],
        });
      }
    }

    return {
      'success': true,
      'type': 'temporada',
      'scraped_url': found['url'],
      'tmdb_id': tmdbId,
      'temporada': temporada,
      'total': episodesResult.length,
      'episodes': episodesResult,
    };
  }

  // ────────────────────────────────────────────────
  // HELPERS
  // ────────────────────────────────────────────────

  static Future<String?> _fetch(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 18));

      if (response.statusCode == 200) return response.body;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _fetchJson(String url) async {
    final body = await _fetch(url);
    if (body == null) return {};
    try {
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : {};
    } catch (_) {
      return {};
    }
  }

  static String _slugify(String title) {
    var t = title.toLowerCase().trim();
    t = t
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'[\s-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return t;
  }

  static Future<Map<String, dynamic>> _getTmdbInfo(
    int tmdbId,
    String mediaType,
  ) async {
    final endpoint = mediaType == 'movie'
        ? 'https://api.themoviedb.org/3/movie/$tmdbId'
        : 'https://api.themoviedb.org/3/tv/$tmdbId';

    final es = await _fetchJson(
      '$endpoint?api_key=$_tmdbApiKey&language=es-MX',
    );
    final eses = await _fetchJson(
      '$endpoint?api_key=$_tmdbApiKey&language=es-ES',
    );
    final en = await _fetchJson(
      '$endpoint?api_key=$_tmdbApiKey&language=en-US',
    );

    int? year;
    if (mediaType == 'movie' && es['release_date'] != null) {
      year = int.tryParse(es['release_date'].toString().substring(0, 4));
    } else if (mediaType == 'tv' && es['first_air_date'] != null) {
      year = int.tryParse(es['first_air_date'].toString().substring(0, 4));
    }

    return {
      'id': tmdbId,
      'latino': es['title'] ?? es['name'] ?? '',
      'castellano': eses['title'] ?? eses['name'] ?? '',
      'ingles': en['title'] ?? en['name'] ?? '',
      'year': year,
    };
  }

  static List<String> _buildCandidates(String type, Map tmdb) {
    final prefix = type == 'movie'
        ? '$_baseUrl/ver-pelicula/'
        : '$_baseUrl/ver-serie/';
    final candidates = <String>[];
    final titles = [tmdb['latino'], tmdb['castellano'], tmdb['ingles']];

    for (final title in titles) {
      if (title == null || title.toString().trim().isEmpty) continue;
      final slug = _slugify(title.toString());
      candidates.add('$prefix$slug');
      if (tmdb['id'] != null) candidates.add('$prefix$slug-${tmdb['id']}');
      if (tmdb['year'] != null) candidates.add('$prefix$slug-${tmdb['year']}');
    }
    return candidates.toSet().toList();
  }

  static Future<Map<String, String>?> _findWorkingUrl(
    List<String> candidates,
  ) async {
    for (final url in candidates) {
      final html = await _fetch(url);
      if (html == null) continue;
      if (html.contains('__NEXT_DATA__') &&
          (html.contains('"thisMovie"') || html.contains('"thisSerie"'))) {
        return {'url': url, 'html': html};
      }
    }
    return null;
  }

  static Map<String, dynamic>? _extractNextData(String html) {
    final match = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) return null;
    try {
      final data = jsonDecode(match.group(1)!);
      return data['props']?['pageProps'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  static bool _isAllowedServer(String name) {
    final lower = name.toLowerCase();
    return _allowedServers.any((a) => lower.contains(a.toLowerCase()));
  }

  static List<Map<String, dynamic>> _getVideoGroupsFromData(
    dynamic videosData,
  ) {
    if (videosData is! Map) return [];

    final videoGroups = <Map<String, dynamic>>[];
    const langMap = {
      'latino': 'Español Latino',
      'spanish': 'Español Castellano',
      'english': 'Inglés',
      'japanese': 'Japonés',
    };

    for (final entry in langMap.entries) {
      final list = videosData[entry.key];
      if (list is! List || list.isEmpty) continue;

      final videos = <Map<String, dynamic>>[];
      for (final v in list) {
        if (v is! Map) continue;
        videos.add({
          'cyberlocker': v['cyberlocker']?.toString() ?? '',
          'url': v['result']?.toString() ?? '',
          'quality': v['quality']?.toString() ?? 'HD',
        });
      }
      if (videos.isNotEmpty) {
        videoGroups.add({'language': entry.value, 'videos': videos});
      }
    }
    return videoGroups;
  }

  static Future<List<Map<String, dynamic>>?> _scrapeEpisodeVideos(
    String url,
  ) async {
    final html = await _fetch(url);
    if (html == null) return null;

    final pageProps = _extractNextData(html);
    if (pageProps == null || pageProps['episode'] == null) return null;

    return _getVideoGroupsFromData(pageProps['episode']['videos'] ?? {});
  }

  static Future<List<Map<String, dynamic>>> _resolvePlayers(
    List<Map<String, dynamic>> videoGroups,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final group in videoGroups) {
      final resolved = <Map<String, dynamic>>[];
      final videos = group['videos'] as List? ?? [];

      for (final v in videos) {
        final cyber = (v['cyberlocker'] ?? '').toString().toLowerCase();
        if (!_isAllowedServer(cyber)) continue;

        final playerUrl = '$_playerApi${Uri.encodeComponent(v['url'] ?? '')}';
        final playerData = await _fetchJson(playerUrl);

        if (playerData['success'] == true && playerData['embed_url'] != null) {
          resolved.add({
            'cyberlocker': v['cyberlocker'],
            'quality': v['quality'] ?? 'HD',
            'original_url': playerData['original_url'] ?? v['url'],
            'mapped_url': playerData['mapped_url'] ?? '',
            'embed_url': playerData['embed_url'],
          });
        }
      }

      if (resolved.isNotEmpty) {
        result.add({'language': group['language'], 'videos': resolved});
      }
    }
    return result;
  }
}
