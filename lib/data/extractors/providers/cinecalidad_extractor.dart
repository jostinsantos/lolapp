import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Servidores permitidos (mismo filtro que el PHP original).
const _kAllowedServers = ['Vimeos', 'Hlswish', 'voe', 'Videoapp'];

const _kTmdbApiKey = 'a2d9bbed370d9f678e34006f8750a5a5';
const _kTmdbBase = 'https://api.themoviedb.org/3';
const _kCinecalidadBase = 'https://www.cinecalidad.am';

/// Modelo de servidor listo para [ServidoresModal].
class CinecalidadServer {
  final String serverName;
  final String url;
  final String calidad;
  final String idioma;
  final String serverClean;

  const CinecalidadServer({
    required this.serverName,
    required this.url,
    this.calidad = 'HD',
    this.idioma = 'es_MX',
    this.serverClean = '',
  });

  Map<String, dynamic> toModalMap() {
    final display = serverClean.isNotEmpty
        ? 'Cinecalidad · $serverClean'
        : 'Cinecalidad · $serverName';
    return {
      'servidor_nombre': display,
      'servidor_url': url,
      'calidad': calidad,
      'idioma': idioma,
      'estado': 'activo',
      'es_cinecalidad': true,
    };
  }
}

class CinecalidadService {
  CinecalidadService._();

  /// Stream de servidores (mismo contrato que [UnlimplayService.scrape]).
  ///
  /// Emite cada link válido encontrado en la página de Cinecalidad.
  /// Si no hay resultados o falla, el stream termina sin emitir (o con error).
  static Stream<CinecalidadServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) {
      throw Exception('tmdb_id inválido');
    }

    final tmdbData = await _getTmdbData(tmdbId, isMovie ? 'movie' : 'tv');
    if (tmdbData.titles.isEmpty) {
      throw Exception('No se pudieron obtener datos de TMDb para el ID: $tmdbId');
    }

    final candidates = _generateCandidates(
      titles: tmdbData.titles,
      tmdbId: tmdbId,
      year: tmdbData.year,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );

    String? foundHtml;
    String? foundUrl;

    for (final url in candidates) {
      try {
        final html = await _fetchPage(url);
        if (html != null && _hasValidContent(html)) {
          foundHtml = html;
          foundUrl = url;
          break;
        }
      } catch (_) {
        // Continuar con el siguiente candidato
      }
    }

    if (foundHtml == null || foundUrl == null) {
      throw Exception('No se encontró ninguna URL válida en Cinecalidad');
    }

    final links = _extractCinecalidadLinks(foundHtml);
    for (final link in links) {
      yield CinecalidadServer(
        serverName: link.server,
        url: link.url,
        serverClean: link.serverClean,
        // Cinecalidad suele servir principalmente latino / castellano.
        // Se marca como latino por defecto para el clasificador del modal.
        idioma: 'es_MX',
        calidad: 'HD',
      );
    }
  }

  // ─── TMDB ───────────────────────────────────────────────────────────────

  static Future<_TmdbData> _getTmdbData(int tmdbId, String type) async {
    const languages = {
      'latino': 'es-MX',
      'castellano': 'es-ES',
      'ingles': 'en-US',
    };

    final data = _TmdbData(id: tmdbId);
    final client = http.Client();

    try {
      for (final entry in languages.entries) {
        final path = type == 'tv' ? '/tv/$tmdbId' : '/movie/$tmdbId';
        final uri = Uri.parse(
          '$_kTmdbBase$path?api_key=$_kTmdbApiKey&language=${entry.value}',
        );

        try {
          final response = await client
              .get(uri)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode != 200) continue;

          final movie = jsonDecode(response.body) as Map<String, dynamic>;
          if (movie['success'] == false) continue;

          final title = (movie['title'] ?? movie['name'] ?? '').toString();
          if (title.isNotEmpty) {
            data.titles[entry.key] = title;
          }

          if (data.year == null) {
            final release = movie['release_date']?.toString() ??
                movie['first_air_date']?.toString();
            if (release != null && release.length >= 4) {
              data.year = int.tryParse(release.substring(0, 4));
            }
          }
        } catch (_) {
          continue;
        }
      }
    } finally {
      client.close();
    }

    return data;
  }

  // ─── Candidatos de URL ──────────────────────────────────────────────────

  static List<String> _generateCandidates({
    required Map<String, String> titles,
    required int tmdbId,
    int? year,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) {
    final candidates = <String>[];

    if (!isMovie) {
      final base = '$_kCinecalidadBase/ver-el-episodio/';
      for (final title in titles.values) {
        final slug = _slugify(title);
        if (slug.isEmpty) continue;
        candidates.add('$base$slug-${season}x$episode/');
        candidates.add('$base$slug-${season}x$episode-$tmdbId/');
        if (year != null) {
          candidates.add('$base$slug-${season}x$episode-$year/');
        }
      }
    } else {
      final base = '$_kCinecalidadBase/ver-pelicula/';
      for (final title in titles.values) {
        final slug = _slugify(title);
        if (slug.isEmpty) continue;
        candidates.add('$base$slug/');
        candidates.add('$base$slug-$tmdbId/');
        if (year != null) {
          candidates.add('$base$slug-$year/');
        }
      }
    }

    return candidates.toSet().toList();
  }

  // ─── Fetch + extracción ─────────────────────────────────────────────────

  static Future<String?> _fetchPage(String url) async {
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
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (_) {}
    return null;
  }

  static bool _hasValidContent(String html) {
    return html.contains('panel_online') && html.contains('data-option');
  }

  static List<_ExtractedLink> _extractCinecalidadLinks(String html) {
    final result = <_ExtractedLink>[];

    // <div id="panel_online" ...> ... <ul class="linklist">...</ul>
    final panelRe = RegExp(
      r'<div id="panel_online".*?<ul class="linklist">(.*?)</ul>',
      caseSensitive: false,
      dotAll: true,
    );
    final panelMatch = panelRe.firstMatch(html);
    if (panelMatch == null) return result;

    final panelContent = panelMatch.group(1) ?? '';
    final liRe = RegExp(
      r'<li[^>]*data-option="([^"]+)"[^>]*>([^<]+)',
      caseSensitive: false,
    );

    for (final m in liRe.allMatches(panelContent)) {
      var serverName = (m.group(2) ?? '').trim();
      // Quitar posibles spans residuales
      serverName = serverName.replaceAll(RegExp(r'<span.*'), '').trim();

      if (!_kAllowedServers.contains(serverName)) continue;

      var realUrl = m.group(1) ?? '';
      if (realUrl.startsWith('/zopass/?zopass=')) {
        try {
          final uri = Uri.parse(
            realUrl.startsWith('http') ? realUrl : 'https://dummy$realUrl',
          );
          final zopass = uri.queryParameters['zopass'];
          if (zopass != null && zopass.isNotEmpty) {
            realUrl = utf8.decode(base64Decode(zopass));
          }
        } catch (_) {
          // Dejar la URL original si falla el decode
        }
      }

      if (realUrl.isEmpty) continue;

      result.add(_ExtractedLink(
        server: serverName,
        url: realUrl,
        serverClean: _extractServerName(realUrl),
      ));
    }

    return result;
  }

  static String _extractServerName(String url) {
    try {
      final host = Uri.parse(url).host;
      if (host.isEmpty) return 'desconocido';
      final parts = host.split('.');
      if (parts.length >= 3 &&
          (host.startsWith('www.') || host.startsWith('cdn.'))) {
        return parts[1];
      }
      return parts[0];
    } catch (_) {
      return 'desconocido';
    }
  }

  // ─── Slugify (port del PHP) ─────────────────────────────────────────────

  static String _slugify(String title) {
    const unwanted = {
      'Š': 'S', 'š': 's', 'Ž': 'Z', 'ž': 'z', 'À': 'A', 'Á': 'A', 'Â': 'A',
      'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'Æ': 'A', 'Ç': 'C', 'È': 'E', 'É': 'E',
      'Ê': 'E', 'Ë': 'E', 'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', 'Ñ': 'N',
      'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ø': 'O', 'Ù': 'U',
      'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ý': 'Y', 'Þ': 'B', 'ß': 'ss', 'à': 'a',
      'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'a', 'ç': 'c',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i',
      'ï': 'i', 'ð': 'o', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
      'ö': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ý': 'y', 'þ': 'b',
      'ÿ': 'y', 'Ŕ': 'R', 'ŕ': 'r',
    };

    var s = title;
    unwanted.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.toLowerCase();
    s = s.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
    s = s.replaceAll(RegExp(r'\s+'), '-');
    return s.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

// ─── Helpers internos ─────────────────────────────────────────────────────

class _TmdbData {
  final int id;
  int? year;
  final Map<String, String> titles = {};

  _TmdbData({required this.id});
}

class _ExtractedLink {
  final String server;
  final String url;
  final String serverClean;

  const _ExtractedLink({
    required this.server,
    required this.url,
    required this.serverClean,
  });
}