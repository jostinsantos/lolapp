// lib/servicio/pelisplus.dart
//
// Extractor de servidores de pelisplushd.la
// Solo encuentra embeds (NO resuelve HLS/m3u8).
// Compatible con MainFuentes / sources.dart

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class PelisPlusService {
  static const String _baseUrl = 'https://www.pelisplushd.la';
  static const String _tmdbApiKey = '439c478a771f35c05022f9feabcca01c';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration _timeout = Duration(seconds: 12);

  /// Scrape progresivo. Emite mapas listos para el modal / MainFuentes.
  /// Solo servidores embed (sin extracción HLS).
  static Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) return;

    try {
      final mediaType = isMovie ? 'movie' : 'tv';

      // 1. Títulos desde TMDB (es-MX, es-ES, en-US)
      final titles = await _getTmdbTitles(tmdbId, mediaType);
      if (titles.isEmpty) return;

      // 2. Buscar URL de la película/serie probando cada título
      final movieUrl = await _findMovieUrl(titles, tmdbId, mediaType);
      if (movieUrl == null || movieUrl.isEmpty) return;

      // 3. Si es serie, armar URL del capítulo
      var pageUrl = movieUrl;
      if (!isMovie) {
        pageUrl =
            '${movieUrl.replaceAll(RegExp(r'/+$'), '')}/temporada/$season/capitulo/$episode';
      }

      // 4. HTML de la página
      final html = await _fetchUrl(pageUrl);
      if (html == null || html.isEmpty) return;

      // 5. Extraer servidores (solo embeds, sin resolver)
      final raw = _extractServers(html);
      if (raw.isEmpty) return;

      // 6. Emitir en formato MainFuentes
      final seen = <String>{};
      for (final item in raw) {
        final url = item['serverUrl']?.toString() ?? '';
        if (url.isEmpty || seen.contains(url)) continue;
        seen.add(url);

        final langRaw = item['language']?.toString() ?? 'Latino';
        final idioma = _toCanonicalIdioma(langRaw);
        final name = item['serverName']?.toString() ?? 'Online';

        yield {
          'servidor_url': url,
          'servidor': name,
          'server': name,
          'idioma': idioma,
          'language': idioma,
          'type': 'embed',
          'url': url,
          'provider': 'PelisPlusHD',
          'quality': 'HD',
        };
      }
    } catch (_) {
      // Silencioso: el agregador maneja errores por fuente
    }
  }

  // ─────────────────────────────────────────────────────────
  // TMDB — títulos en es-MX, es-ES, en-US
  // ─────────────────────────────────────────────────────────

  static Future<List<String>> _getTmdbTitles(int tmdbId, String type) async {
    final languages = ['es-MX', 'es-ES', 'en-US'];
    final titles = <String>{};

    for (final lang in languages) {
      final url =
          'https://api.themoviedb.org/3/$type/$tmdbId?api_key=$_tmdbApiKey&language=$lang';
      final data = await _fetchJson(url);
      if (data == null) continue;

      final title = data['title']?.toString() ?? data['name']?.toString();
      if (title != null && title.trim().isNotEmpty) {
        titles.add(title.trim());
      }
    }

    // Fallback sin idioma
    if (titles.isEmpty) {
      final url =
          'https://api.themoviedb.org/3/$type/$tmdbId?api_key=$_tmdbApiKey';
      final data = await _fetchJson(url);
      if (data != null) {
        final title = data['title']?.toString() ?? data['name']?.toString();
        if (title != null && title.trim().isNotEmpty) {
          titles.add(title.trim());
        }
      }
    }

    // Variantes útiles para búsqueda
    final expanded = <String>{};
    for (final t in titles) {
      expanded.add(t);
      expanded.add(t.replaceAll(':', ''));
      expanded.add(t.replaceAll(RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑüÜ\s]'), ''));
      expanded.add(t.replaceAll(RegExp(r'\(\d{4}\)'), '').trim());
    }

    return expanded
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .take(12)
        .toList();
  }

  // ─────────────────────────────────────────────────────────
  // Búsqueda en pelisplushd.la
  // ─────────────────────────────────────────────────────────

  static Future<String?> _findMovieUrl(
    List<String> titles,
    int tmdbId,
    String mediaType,
  ) async {
    for (final searchTitle in titles) {
      if (searchTitle.isEmpty) continue;

      final searchUrl =
          '$_baseUrl/search?s=${Uri.encodeComponent(searchTitle)}';
      final html = await _fetchUrl(searchUrl);
      if (html == null || html.isEmpty) continue;

      final matches = _extractSearchResults(html, mediaType);
      for (final match in matches) {
        final foundTitle = match['title'] ?? '';
        final href = match['href'] ?? '';
        if (href.isEmpty) continue;

        // Coincidencia con el título de búsqueda o con cualquiera de la lista
        if (_titleMatch(searchTitle, foundTitle) ||
            titles.any((t) => _titleMatch(t, foundTitle))) {
          return href;
        }
      }
    }

    // Fallback por ID TMDB (si el sitio lo usa en la ruta)
    final directUrls = [
      '$_baseUrl/pelicula/$tmdbId',
      '$_baseUrl/serie/$tmdbId',
    ];
    for (final url in directUrls) {
      final html = await _fetchUrl(url);
      if (html != null && html.isNotEmpty && html.length > 500) {
        return url;
      }
    }

    return null;
  }

  static List<Map<String, String>> _extractSearchResults(
    String html,
    String mediaType,
  ) {
    final results = <Map<String, String>>[];
    final typePattern = mediaType == 'movie' ? '/pelicula/' : '/serie/';

    final linkRe = RegExp(
      r'<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    );

    for (final m in linkRe.allMatches(html)) {
      var href = m.group(1) ?? '';
      final content = m.group(2) ?? '';

      if (!href.contains(typePattern)) continue;

      String title = '';
      final pMatch = RegExp(
        r'<p[^>]*>([\s\S]*?)</p>',
        caseSensitive: false,
      ).firstMatch(content);
      if (pMatch != null) {
        title = _stripTags(pMatch.group(1) ?? '');
      } else {
        final dt = RegExp(
          r'data-title="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(m.group(0) ?? '');
        if (dt != null) {
          title = dt.group(1) ?? '';
        } else {
          title = _stripTags(content);
        }
      }

      title = title
          .replaceAll(RegExp(r'^VER\s+', caseSensitive: false), '')
          .replaceAll(
            RegExp(r'\s+Online\s+Gratis\s+HD$', caseSensitive: false),
            '',
          )
          .replaceAll(
            RegExp(r'\s+Online\s+Latino\s+HD$', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'\(\d{4}\)$'), '')
          .trim();

      if (title.isEmpty) continue;

      if (!href.startsWith('http')) {
        href = href.startsWith('/') ? '$_baseUrl$href' : '$_baseUrl/$href';
      }

      results.add({'href': href, 'title': title});
    }

    return results;
  }

  static bool _titleMatch(String query, String target) {
    final q = _normalizeTitle(query);
    final t = _normalizeTitle(target);
    if (q.isEmpty || t.isEmpty) return false;
    if (q == t) return true;

    final qWords =
        q.split(' ').where((w) => w.length > 2).toList();
    final tWords = t.split(' ');
    if (qWords.isEmpty) return q == t;

    var matchCount = 0;
    for (final w in qWords) {
      if (tWords.contains(w)) matchCount++;
    }
    return (matchCount / qWords.length) >= 0.8;
  }

  static String _normalizeTitle(String title) {
    if (title.isEmpty) return '';
    var s = title.toLowerCase();
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  // ─────────────────────────────────────────────────────────
  // Extracción de servidores (SOLO embeds, sin HLS)
  // ─────────────────────────────────────────────────────────

  static List<Map<String, String>> _extractServers(String html) {
    final results = <Map<String, String>>[];
    final seen = <String>{};

    // Método 1: <li data-url="..." data-name="...">
    final p1 = RegExp(
      r'<li[^>]*data-url="([^"]+)"[^>]*data-name="([^"]*)"[^>]*>',
      caseSensitive: false,
    );
    for (final m in p1.allMatches(html)) {
      final url = m.group(1) ?? '';
      final name = m.group(2) ?? 'Servidor';
      final lang = _detectLanguage(name, html);
      if (!_isLanguageSupported(lang)) continue;
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);
      results.add({
        'serverUrl': url,
        'serverName': name,
        'language': lang,
      });
    }

    // Método 2: <span url="...">
    if (results.isEmpty) {
      final p2 = RegExp(
        r'<span[^>]*url="([^"]+)"[^>]*>',
        caseSensitive: false,
      );
      for (final m in p2.allMatches(html)) {
        final url = m.group(1) ?? '';
        final lang = _detectLanguage('', html);
        if (!_isLanguageSupported(lang)) continue;
        if (url.isEmpty || seen.contains(url)) continue;
        seen.add(url);
        results.add({
          'serverUrl': url,
          'serverName': 'Servidor',
          'language': lang,
        });
      }
    }

    // Método 3: var options = { ... };
    if (results.isEmpty) {
      final p3 = RegExp(
        r'var\s+options\s*=\s*(\{[\s\S]*?\});',
        caseSensitive: false,
      );
      final m3 = p3.firstMatch(html);
      if (m3 != null) {
        final options = _parseJsObject(m3.group(1) ?? '');
        options.forEach((key, value) {
          if (!_isLanguageSupported(key)) return;
          if (value is List) {
            for (final item in value) {
              if (item is Map && item['url'] != null) {
                final url = item['url'].toString();
                if (url.isEmpty || seen.contains(url)) continue;
                seen.add(url);
                results.add({
                  'serverUrl': url,
                  'serverName': item['name']?.toString() ?? key,
                  'language': key,
                });
              }
            }
          }
        });
      }
    }

    return results;
  }

  static String _detectLanguage(String name, String html) {
    final text = '${name.toLowerCase()} ${html.toLowerCase()}';
    if (text.contains('latino') || RegExp(r'\blat\b').hasMatch(text)) {
      return 'Latino';
    }
    if (text.contains('castellano') ||
        text.contains('español') ||
        RegExp(r'\besp\b').hasMatch(text)) {
      return 'Castellano';
    }
    if (text.contains('subtitulado') || text.contains('sub')) {
      return 'Subtitulado';
    }
    return 'Latino';
  }

  static bool _isLanguageSupported(String lang) {
    final l = lang.toLowerCase();
    return l.contains('latino') ||
        l.contains('castellano') ||
        l.contains('español') ||
        l.contains('esp');
  }

  static String _toCanonicalIdioma(String lang) {
    final l = lang.toLowerCase();
    if (l.contains('castellano') || l.contains('es_es') || l.contains('español')) {
      return 'es_ES';
    }
    if (l.contains('sub') || l.contains('en_us') || l.contains('english')) {
      return 'en_US';
    }
    return 'es_MX';
  }

  // ─────────────────────────────────────────────────────────
  // Parseo JS simple (options)
  // ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _parseJsObject(String str) {
    var s = str.trim().replaceAll("'", '"');
    s = s.replaceAll(RegExp(r',\s*}'), '}');

    try {
      final data = jsonDecode(s);
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}

    final result = <String, dynamic>{};
    final pattern = RegExp(r'"([^"]+)"\s*:\s*(\[[^\]]*\]|[^{,]*)');
    for (final m in pattern.allMatches(s)) {
      final key = m.group(1) ?? '';
      var value = (m.group(2) ?? '').trim();
      if (key.isEmpty) continue;

      if (value.startsWith('[')) {
        final items = <Map<String, String>>[];
        final itemRe = RegExp(r'\{[^}]*\}');
        for (final im in itemRe.allMatches(value)) {
          final item = <String, String>{};
          final propRe = RegExp(r'"([^"]+)"\s*:\s*"([^"]*)"');
          for (final pm in propRe.allMatches(im.group(0) ?? '')) {
            item[pm.group(1) ?? ''] = pm.group(2) ?? '';
          }
          if (item.isNotEmpty) items.add(item);
        }
        result[key] = items;
      } else {
        result[key] = value.replaceAll('"', '');
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────
  // HTTP
  // ─────────────────────────────────────────────────────────

  static Future<String?> _fetchUrl(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': _userAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
              'Accept-Language': 'es-ES,es;q=0.9',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return null;
      return response.body;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchJson(String url) async {
    final body = await _fetchUrl(url);
    if (body == null) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  static String _stripTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}