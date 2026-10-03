import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const _kTmdbApiKey = 'a2d9bbed370d9f678e34006f8750a5a5';
const _kTmdbBase = 'https://api.themoviedb.org/3';
const _kTioplusBase = 'https://tioplus.app';

/// Host originales → host de reemplazo (mismo filtro que el PHP).
const _kHostMap = <String, String>{
  'vidhideplus.com': 'callistanise.com',
};

const _kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// Modelo de servidor listo para [ServidoresModal].
class TioplusServer {
  final String serverName;
  final String url;
  final String calidad;
  final String idioma;

  const TioplusServer({
    required this.serverName,
    required this.url,
    this.calidad = 'HD',
    this.idioma = 'es_MX',
  });

  Map<String, dynamic> toModalMap() {
    return {
      'servidor_nombre': 'TioPlus · $serverName',
      'servidor_url': url,
      'calidad': calidad,
      'idioma': idioma,
      'estado': 'activo',
      'es_tioplus': true,
    };
  }
}

class TioplusService {
  TioplusService._();

  /// Stream de servidores (mismo contrato que [CinecalidadService.scrape] /
  /// [UnlimplayService.scrape]).
  static Stream<TioplusServer> scrape({
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
      throw Exception(
        'No se pudieron obtener datos de TMDb para el ID: $tmdbId',
      );
    }

    // 1) Candidatos por slug construido
    final candidates = _generateCandidates(
      titles: tmdbData.titles,
      year: tmdbData.year,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );

    String? foundHtml;
    String? foundUrl;
    String? foundKind;

    for (final c in candidates) {
      try {
        final html = await _fetchPage(c.url);
        if (html != null && _hasServers(html)) {
          foundHtml = html;
          foundUrl = c.url;
          foundKind = c.kind;
          break;
        }
      } catch (_) {}
    }

    // 2) Fallback: búsqueda en /api/search
    if (foundHtml == null) {
      final fromSearch = await _searchTioplus(
        titles: tmdbData.titles,
        year: tmdbData.year,
        isMovie: isMovie,
        season: season,
        episode: episode,
      );
      for (final c in fromSearch) {
        try {
          final html = await _fetchPage(c.url);
          if (html != null && _hasServers(html)) {
            foundHtml = html;
            foundUrl = c.url;
            foundKind = c.kind;
            break;
          }
        } catch (_) {}
      }
    }

    // 3) TV: si serie falló, forzar anime con mismos slugs
    if (foundHtml == null && !isMovie) {
      for (final title in tmdbData.titles.values) {
        final slug = _slugify(title);
        if (slug.isEmpty) continue;
        final animeUrl =
            '$_kTioplusBase/anime/$slug/season/$season/episode/$episode';
        try {
          final html = await _fetchPage(animeUrl);
          if (html != null && _hasServers(html)) {
            foundHtml = html;
            foundUrl = animeUrl;
            foundKind = 'anime';
            break;
          }
        } catch (_) {}
      }
    }

    if (foundHtml == null || foundUrl == null) {
      throw Exception('No se encontró ninguna URL válida en TioPlus');
    }

    final links = await _resolveEmbeds(foundHtml, referer: foundUrl);
    for (final link in links) {
      yield TioplusServer(
        serverName: link.name,
        url: link.embedUrl,
        idioma: _guessIdioma(link.name, foundKind),
        calidad: 'HD',
      );
    }
  }

  // ─── TMDB (igual patrón que Cinecalidad) ────────────────────────────────

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
          final response =
              await client.get(uri).timeout(const Duration(seconds: 10));
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

  static List<_Candidate> _generateCandidates({
    required Map<String, String> titles,
    int? year,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) {
    final slugs = <String>{};

    for (final title in titles.values) {
      final s = _slugify(title);
      if (s.isEmpty) continue;
      slugs.add(s);

      // sin artículo inicial (el/la/los/las/the)
      final noArt = title.replaceFirst(
        RegExp(r'^(el|la|los|las|the|a|an)\s+', caseSensitive: false),
        '',
      );
      if (noArt != title) {
        final s2 = _slugify(noArt);
        if (s2.isNotEmpty) slugs.add(s2);
      }

      if (year != null) {
        slugs.add('$s-$year');
      }
    }

    final candidates = <_Candidate>[];

    if (isMovie) {
      for (final slug in slugs) {
        candidates.add(_Candidate(
          kind: 'pelicula',
          slug: slug,
          url: '$_kTioplusBase/pelicula/$slug',
        ));
      }
    } else {
      // serie primero, luego anime
      for (final kind in ['serie', 'anime']) {
        for (final slug in slugs) {
          candidates.add(_Candidate(
            kind: kind,
            slug: slug,
            url: '$_kTioplusBase/$kind/$slug/season/$season/episode/$episode',
          ));
        }
      }
    }

    return candidates;
  }

  // ─── Búsqueda TioPlus (fallback) ────────────────────────────────────────

  static Future<List<_Candidate>> _searchTioplus({
    required Map<String, String> titles,
    int? year,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async {
    final queries = <String>{...titles.values};
    if (year != null) {
      for (final t in titles.values) {
        queries.add('$t $year');
      }
    }

    final found = <String, _Candidate>{};

    for (final q in queries) {
      final html = await _fetchPage(
        '$_kTioplusBase/api/search/${Uri.encodeComponent(q)}',
      );
      if (html == null || html.contains('No hay resultados')) continue;

      final re = RegExp(
        r'''href=["'](https?://tioplus\.app/(pelicula|serie|anime)/([^"'/?#]+))["']''',
        caseSensitive: false,
      );

      for (final m in re.allMatches(html)) {
        final kind = (m.group(2) ?? '').toLowerCase();
        final slug = m.group(3) ?? '';
        if (slug.isEmpty) continue;

        if (isMovie && kind != 'pelicula') continue;
        if (!isMovie && kind != 'serie' && kind != 'anime') continue;

        var url = m.group(1)!;
        if (kind != 'pelicula') {
          url = '$url/season/$season/episode/$episode';
        }

        final key = '$kind|$slug';
        found.putIfAbsent(
          key,
          () => _Candidate(kind: kind, slug: slug, url: url),
        );
      }

      if (found.isNotEmpty) break;
    }

    final list = found.values.toList();
    list.sort((a, b) {
      const order = {'pelicula': 0, 'serie': 1, 'anime': 2};
      return (order[a.kind] ?? 9).compareTo(order[b.kind] ?? 9);
    });
    return list;
  }

  // ─── Fetch ──────────────────────────────────────────────────────────────

  static Future<String?> _fetchPage(
    String url, {
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final headers = <String, String>{
        'User-Agent': _kUserAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'es-MX,es-ES,es;q=0.9,en;q=0.8',
        ...?extraHeaders,
      };

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 400) {
        return response.body;
      }
    } catch (_) {}
    return null;
  }

  static bool _hasServers(String html) {
    return html.contains('data-server=') && html.contains('subselect');
  }

  // ─── Extracción data-server → /player/ → embed ──────────────────────────

  static Future<List<_EmbedLink>> _resolveEmbeds(
    String html, {
    required String referer,
  }) async {
    final result = <_EmbedLink>[];

    // <li data-server="..." ...> <span>Nombre</span>
    final re = RegExp(
      r'''<li[^>]*data-server=["']([^"']+)["'][^>]*>.*?<span>([^<]+)</span>''',
      caseSensitive: false,
      dotAll: true,
    );

    for (final m in re.allMatches(html)) {
      final dataServer = (m.group(1) ?? '').trim();
      final name =
          _decodeHtml((m.group(2) ?? '').trim());
      if (dataServer.isEmpty || name.isEmpty) continue;

      // Igual que el JS: /player/ + btoa(data-server)
      final playerPath = base64Encode(utf8.encode(dataServer));
      final playerUrl = '$_kTioplusBase/player/$playerPath';

      final playerHtml = await _fetchPage(
        playerUrl,
        extraHeaders: {
          'Referer': referer,
          'Accept': 'text/html',
        },
      );
      if (playerHtml == null) continue;

      var embed = _extractRedirect(playerHtml);
      if (embed == null || embed.isEmpty) continue;

      embed = _applyHostMap(embed);

      result.add(_EmbedLink(name: name, embedUrl: embed));
    }

    return result;
  }

  static String? _extractRedirect(String playerHtml) {
    final re1 = RegExp(
      r'''window\.location\.href\s*=\s*['"]([^'"]+)['"]''',
    );
    final m1 = re1.firstMatch(playerHtml);
    if (m1 != null) return m1.group(1);

    final re2 = RegExp(
      r'''location\.href\s*=\s*['"]([^'"]+)['"]''',
    );
    final m2 = re2.firstMatch(playerHtml);
    return m2?.group(1);
  }

  static String _applyHostMap(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      final mapped = _kHostMap[host];
      if (mapped == null) return url;

      return uri.replace(host: mapped).toString();
    } catch (_) {
      return url;
    }
  }

  static String _guessIdioma(String serverName, String? kind) {
    final n = serverName.toLowerCase();
    if (n.contains('castellano') || n.contains('español') && n.contains('es')) {
      return 'es_ES';
    }
    if (n.contains('latino') || n.contains('lat')) {
      return 'es_MX';
    }
    if (n.contains('sub') || n.contains('english') || n.contains('inglés')) {
      return 'en_US';
    }
    // TioPlus en español latino por defecto
    return 'es_MX';
  }

  // ─── Slugify (mismo mapa que Cinecalidad) ───────────────────────────────

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

  static String _decodeHtml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }
}

// ─── Helpers internos ─────────────────────────────────────────────────────

class _TmdbData {
  final int id;
  int? year;
  final Map<String, String> titles = {};

  _TmdbData({required this.id});
}

class _Candidate {
  final String kind;
  final String slug;
  final String url;

  const _Candidate({
    required this.kind,
    required this.slug,
    required this.url,
  });
}

class _EmbedLink {
  final String name;
  final String embedUrl;

  const _EmbedLink({
    required this.name,
    required this.embedUrl,
  });
}