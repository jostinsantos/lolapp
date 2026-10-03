// lib/servicio/hackstore.dart
//
// Extractor de servidores de video de hackstore.mx
// Compatible con MainFuentes (scrape → Map con servidor_url, idioma, etc.)

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class HackStoreService {
  static const String _baseUrl = 'https://hackstore.mx';
  static const String _tmdbApiKey = '439c478a771f35c05022f9feabcca01c';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration _timeout = Duration(seconds: 15);

  /// Scrape progresivo. Emite mapas listos para el modal / MainFuentes.
  static Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) return;

    try {
      final mediaType = isMovie ? 'movie' : 'tv';
      final postType = isMovie ? 'movies' : 'tvshows';

      // 1. Títulos + año desde TMDB
      final titlesInfo = await _getTmdbTitles(tmdbId, mediaType);
      if (titlesInfo == null || titlesInfo.titles.isEmpty) {
        return;
      }

      // 2. Slugs
      final slugs = _generateSlugs(titlesInfo.titles, titlesInfo.year);
      if (slugs.isEmpty) return;

      // 3. ID del contenido
      final contentId = await _findContentId(slugs, postType);
      if (contentId == null) return;

      // 4. Si es serie, ID del episodio
      String targetId = contentId;
      if (!isMovie) {
        final episodeId = await _findEpisodeId(contentId, season, episode);
        if (episodeId == null) return;
        targetId = episodeId;
      }

      // 5. Players
      final players = await _getPlayers(targetId);
      if (players.isEmpty) return;

      // 6. Formatear y emitir
      for (final server in _formatServers(players)) {
        yield server;
      }
    } catch (_) {
      // Silencioso: MainFuentes ya maneja errores por fuente
    }
  }

  // ─────────────────────────────────────────────────────────
  // TMDB
  // ─────────────────────────────────────────────────────────

  static Future<_TitlesInfo?> _getTmdbTitles(int tmdbId, String type) async {
    final languages = ['es-MX', 'es-ES', 'en-US'];
    final titles = <String, String>{};
    String year = '';

    for (final lang in languages) {
      final url =
          'https://api.themoviedb.org/3/$type/$tmdbId?api_key=$_tmdbApiKey&language=$lang';
      final data = await _fetchJson(url);
      if (data == null) continue;

      final title = data['title']?.toString() ?? data['name']?.toString();
      if (title != null && title.isNotEmpty) {
        titles[lang] = title;
      }

      if (year.isEmpty) {
        final date = data['release_date']?.toString() ??
            data['first_air_date']?.toString() ??
            '';
        if (date.length >= 4) year = date.substring(0, 4);
      }
    }

    // Fallback sin idioma
    if (titles.isEmpty) {
      final url =
          'https://api.themoviedb.org/3/$type/$tmdbId?api_key=$_tmdbApiKey';
      final data = await _fetchJson(url);
      if (data != null) {
        final title = data['title']?.toString() ?? data['name']?.toString();
        if (title != null && title.isNotEmpty) {
          titles['default'] = title;
        }
        if (year.isEmpty) {
          final date = data['release_date']?.toString() ??
              data['first_air_date']?.toString() ??
              '';
          if (date.length >= 4) year = date.substring(0, 4);
        }
      }
    }

    // Títulos alternativos + traducciones
    final altTitles = await _getAlternativeTitles(tmdbId, type);
    var altIndex = 0;
    for (final alt in altTitles) {
      if (!titles.values.contains(alt)) {
        titles['alt_$altIndex'] = alt;
        altIndex++;
      }
    }

    if (titles.isEmpty) return null;

    return _TitlesInfo(
      titles: titles.values.toSet().toList(),
      year: year,
    );
  }

  static Future<List<String>> _getAlternativeTitles(
    int tmdbId,
    String type,
  ) async {
    final result = <String>{};

    // alternative_titles
    final altUrl =
        'https://api.themoviedb.org/3/$type/$tmdbId/alternative_titles?api_key=$_tmdbApiKey';
    final altData = await _fetchJson(altUrl);
    if (altData != null && altData['titles'] is List) {
      for (final item in altData['titles'] as List) {
        if (item is Map && item['title'] != null) {
          final t = item['title'].toString().trim();
          if (t.isNotEmpty) result.add(t);
        }
      }
    }

    // translations
    final trUrl =
        'https://api.themoviedb.org/3/$type/$tmdbId/translations?api_key=$_tmdbApiKey';
    final trData = await _fetchJson(trUrl);
    if (trData != null && trData['translations'] is List) {
      for (final item in trData['translations'] as List) {
        if (item is Map && item['data'] is Map) {
          final data = item['data'] as Map;
          final t = (data['title'] ?? data['name'])?.toString().trim();
          if (t != null && t.isNotEmpty) result.add(t);
        }
      }
    }

    return result.toList();
  }

  // ─────────────────────────────────────────────────────────
  // Slugs
  // ─────────────────────────────────────────────────────────

  static List<String> _generateSlugs(List<String> titles, String year) {
    final slugs = <String>{};

    for (final title in titles) {
      if (title.trim().isEmpty) continue;
      final slug = _normalizeSlug(title);
      if (slug.isEmpty) continue;

      if (year.isNotEmpty) {
        slugs.add('$slug-$year');
      }
      slugs.add(slug);
    }

    return slugs.take(15).toList();
  }

  static String _normalizeSlug(String title) {
    if (title.isEmpty) return '';

    var s = title.toLowerCase();

    // Quitar acentos
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }

    // Solo a-z 0-9 y espacios
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(' ', '-');
    s = s.replaceAll(RegExp(r'-+'), '-');
    s = s.replaceAll(RegExp(r'^-+|-+$'), '');

    return s;
  }

  // ─────────────────────────────────────────────────────────
  // API HackStore
  // ─────────────────────────────────────────────────────────

  static Future<String?> _findContentId(
    List<String> slugs,
    String postType,
  ) async {
    for (final slug in slugs) {
      final endpoint =
          '$_baseUrl/wp-api/v1/single/$postType?slug=$slug&postType=$postType';
      final data = await _fetchJson(endpoint);
      if (data != null &&
          data['data'] is Map &&
          data['data']['_id'] != null) {
        return data['data']['_id'].toString();
      }
    }
    return null;
  }

  static Future<String?> _findEpisodeId(
    String seriesId,
    int season,
    int episode,
  ) async {
    final url =
        '$_baseUrl/wp-api/v1/single/episodes/list?_id=$seriesId&season=$season&page=1&postsPerPage=200';
    final data = await _fetchJson(url);

    if (data == null ||
        data['data'] is! Map ||
        data['data']['posts'] is! List) {
      return null;
    }

    final posts = data['data']['posts'] as List;
    for (final post in posts) {
      if (post is! Map) continue;
      final s = post['season_number'];
      final e = post['episode_number'];
      final id = post['_id'];

      final seasonNum = s is int ? s : int.tryParse(s?.toString() ?? '');
      final episodeNum = e is int ? e : int.tryParse(e?.toString() ?? '');

      if (seasonNum == season && episodeNum == episode && id != null) {
        return id.toString();
      }
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _getPlayers(String postId) async {
    final url = '$_baseUrl/wp-api/v1/player?postId=$postId';
    final data = await _fetchJson(url);

    if (data == null ||
        data['data'] is! Map ||
        data['data']['embeds'] is! List) {
      return [];
    }

    final embeds = data['data']['embeds'] as List;
    final result = <Map<String, dynamic>>[];

    for (final e in embeds.take(15)) {
      if (e is Map) {
        result.add(Map<String, dynamic>.from(e));
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────
  // Formato compatible con MainFuentes
  // ─────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _formatServers(
    List<Map<String, dynamic>> players,
  ) {
    final servers = <Map<String, dynamic>>[];

    for (final player in players) {
      final lang = (player['lang']?.toString() ?? 'latino').toLowerCase();

      // Filtrar idiomas no deseados (igual que PHP)
      if (lang.contains('sub') ||
          lang.contains('vose') ||
          lang.contains('eng') ||
          lang.contains('espana')) {
        continue;
      }

      var rawUrl = player['url']?.toString() ?? '';
      if (rawUrl.isEmpty || rawUrl.contains('la.movie')) continue;

      // Reemplazo voe.sx → eugenemakedraw.com
      rawUrl = rawUrl.replaceAll('voe.sx', 'eugenemakedraw.com');

      final serverName = player['server']?.toString() ?? 'Online';
      final serverId = player['server_id']?.toString() ?? '';

      // Idioma canónico
      String idioma = 'es_MX';
      if (lang.contains('castellano') || lang.contains('es_es')) {
        idioma = 'es_ES';
      } else if (lang.contains('en_us') || lang.contains('english')) {
        idioma = 'en_US';
      }

      servers.add({
        // Campos que espera MainFuentes / modal
        'servidor_url': rawUrl,
        'servidor': serverName,
        'server': serverName,
        'server_id': serverId,
        'idioma': idioma,
        'language': idioma,
        'type': player['type']?.toString() ?? 'embed',
        'url': rawUrl,
      });
    }

    return servers;
  }

  // ─────────────────────────────────────────────────────────
  // HTTP
  // ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _fetchJson(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': _userAgent,
              'Accept': 'application/json, text/plain, */*',
              'Accept-Language': 'es-ES,es;q=0.9',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }
}

class _TitlesInfo {
  final List<String> titles;
  final String year;

  const _TitlesInfo({required this.titles, required this.year});
}