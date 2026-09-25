import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Scraper nativo de SeriesMetro (www3.seriesmetro.net).
/// Replica el PHP: TMDB → candidatos slug → página con #aa-options →
/// iframes ?trembed=N → servidor final dentro del embed.
class SeriesMetroService {
  SeriesMetroService._();

  static const _kTmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const _kTmdbBase = 'https://api.themoviedb.org/3';
  static const _kBase = 'https://www3.seriesmetro.net';

  static const _kUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36';

  /// Emite servidores listos para [ServidoresModal] / MainFuentes.
  static Stream<SeriesMetroServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) {
      throw Exception('tmdb_id inválido');
    }

    final tmdb = await _getTmdbInfo(tmdbId, isMovie ? 'movie' : 'tv');
    if (tmdb.titles.isEmpty) {
      throw Exception('No se obtuvo info de TMDB');
    }

    final candidates = _buildCandidates(
      titles: tmdb.titles,
      year: tmdb.year,
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );

    final found = await _findWorkingUrl(candidates);
    if (found == null) {
      throw Exception('No se encontró la página en SeriesMetro');
    }

    final rawServers = await _scrapePelispedia(found.html);
    if (rawServers.isEmpty) {
      throw Exception('No se encontraron servidores en SeriesMetro');
    }

    final seen = <String>{};

    for (final raw in rawServers) {
      final url = raw.serverUrl.trim();
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);

      yield SeriesMetroServer(
        option: raw.option,
        language: raw.language,
        url: url,
        tmdbId: tmdbId,
        season: isMovie ? 0 : season,
        episode: isMovie ? 0 : episode,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  // ─── TMDB ───────────────────────────────────────────────────────────────

  static Future<_TmdbInfo> _getTmdbInfo(int tmdbId, String mediaType) async {
    final endpoint = mediaType == 'movie' ? 'movie' : 'tv';

    Future<Map<String, dynamic>?> fetchLang(String lang) async {
      try {
        final r = await http
            .get(
              Uri.parse(
                '$_kTmdbBase/$endpoint/$tmdbId?api_key=$_kTmdbKey&language=$lang',
              ),
              headers: {'Accept': 'application/json', 'User-Agent': _kUa},
            )
            .timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        final data = jsonDecode(r.body);
        if (data is! Map<String, dynamic>) return null;
        if (data['success'] == false) return null;
        return data;
      } catch (_) {
        return null;
      }
    }

    final es = await fetchLang('es-MX');
    final eses = await fetchLang('es-ES');
    final en = await fetchLang('en-US');

    final titles = <String>{};

    void addTitle(Map<String, dynamic>? data) {
      if (data == null) return;
      if (mediaType == 'movie') {
        final t = (data['title'] ?? '').toString().trim();
        final ot = (data['original_title'] ?? '').toString().trim();
        if (t.isNotEmpty) titles.add(t);
        if (ot.isNotEmpty) titles.add(ot);
      } else {
        final n = (data['name'] ?? '').toString().trim();
        final on = (data['original_name'] ?? '').toString().trim();
        if (n.isNotEmpty) titles.add(n);
        if (on.isNotEmpty) titles.add(on);
      }
    }

    addTitle(es);
    addTitle(eses);
    addTitle(en);

    int? year;
    final dateStr = mediaType == 'movie'
        ? (es?['release_date'] ?? en?['release_date'])?.toString()
        : (es?['first_air_date'] ?? en?['first_air_date'])?.toString();
    if (dateStr != null && dateStr.length >= 4) {
      year = int.tryParse(dateStr.substring(0, 4));
    }

    return _TmdbInfo(
      id: tmdbId,
      titles: titles.toList(),
      year: year,
    );
  }

  // ─── Candidates ─────────────────────────────────────────────────────────

  static List<String> _buildCandidates({
    required List<String> titles,
    required int? year,
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    final out = <String>{};

    for (final title in titles) {
      final slug = _slugify(title);
      if (slug.isEmpty) continue;

      if (isMovie) {
        out.add('$_kBase/pelicula/$slug/');
        out.add('$_kBase/pelicula/$slug-$tmdbId/');
        if (year != null) {
          out.add('$_kBase/pelicula/$slug-$year/');
        }
      } else {
        final baseSlug = '$slug-temporada-$season-capitulo-$episode';
        out.add('$_kBase/capitulo/$baseSlug/');
        out.add('$_kBase/capitulo/$baseSlug-$tmdbId/');
        if (year != null) {
          out.add('$_kBase/capitulo/$baseSlug-$year/');
        }
      }
    }

    return out.toList();
  }

  static Future<_FoundPage?> _findWorkingUrl(List<String> candidates) async {
    for (final url in candidates) {
      final html = await _fetch(url);
      if (html == null) continue;
      if (_isValidPage(html)) {
        return _FoundPage(url: url, html: html);
      }
    }
    return null;
  }

  static bool _isValidPage(String html) {
    return html.contains('id="aa-options"') ||
        html.contains("id='aa-options'") ||
        html.contains('aa-options');
  }

  // ─── Scrape (HTML real seriesmetro.net) ───────────────────────────────────
  //
  // <aside id="aa-options">
  //   <div id="options-0" class="video aa-tb hdd on">
  //     <iframe src="...?trembed=0&trid=..." data-src="...?trembed=0&trid=...">
  //   </div>
  // </aside>
  // <a href="#options-0">OPCIÓN <span>1</span> <span class="server">-Latino</span></a>
  //
  // Embed:
  //   <iframe src="https://fastream.to/embed-xxx.html">

  static Future<List<_RawServer>> _scrapePelispedia(String html) async {
    final result = <_RawServer>[];

    // 1) Botones: href="#options-N" → option + language
    final buttonInfo = <String, _ButtonInfo>{};
    final btnRe = RegExp(
      r'''<a[^>]*href=["']#([^"']+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );
    for (final m in btnRe.allMatches(html)) {
      final id = m.group(1)!;
      final inner = m.group(2) ?? '';

      int? option;
      final numM = RegExp(
        r'''<span(?![^>]*class=["'][^"']*server)[^>]*>\s*(\d+)\s*</span>''',
        caseSensitive: false,
      ).firstMatch(inner);
      if (numM != null) {
        option = int.tryParse(numM.group(1)!);
      }

      var language = 'Desconocido';
      final langM = RegExp(
        r'''<span[^>]*class=["'][^"']*server[^"']*["'][^>]*>\s*-?\s*([^<]+?)\s*</span>''',
        caseSensitive: false,
      ).firstMatch(inner);
      if (langM != null) {
        language = langM.group(1)!.trim().replaceFirst(RegExp(r'^-\s*'), '');
        if (language.toUpperCase() == 'VOSE') {
          language = 'Subtitulado';
        }
      }

      buttonInfo[id] = _ButtonInfo(option: option, language: language);
    }

    // 2) Bloques video: id="options-N" class="...video..."
    final blockRe = RegExp(
      r'''<div[^>]*\bid=["'](options?-\d+|video-\d+|opt-\d+)["'][^>]*>'''
      r'''([\s\S]*?)'''
      r'''</div>''',
      caseSensitive: false,
    );

    final seenIds = <String>{};
    for (final m in blockRe.allMatches(html)) {
      final id = m.group(1)!.trim();
      final block = m.group(2) ?? '';
      if (id.isEmpty || seenIds.contains(id)) continue;
      // Solo bloques de video / options-N
      final isOptions = id.startsWith('options') || id.startsWith('option');
      final hasIframe = block.toLowerCase().contains('iframe');
      if (!isOptions && !hasIframe) continue;
      seenIds.add(id);

      final iframeSrc = _extractIframeSrc(block);
      if (iframeSrc == null || iframeSrc.isEmpty) continue;

      final serverUrl = await _resolveEmbed(iframeSrc);
      if (serverUrl == null || serverUrl.isEmpty) continue;

      final info = buttonInfo[id];
      result.add(_RawServer(
        option: info?.option ?? _optionFromId(id),
        language: info?.language ?? 'Desconocido',
        serverUrl: serverUrl,
      ));
    }

    // 3) Fallback: todos los iframes dentro de aa-options
    if (result.isEmpty) {
      final aaMatch = RegExp(
        r'''id=["']aa-options["'][^>]*>([\s\S]*?)</aside>''',
        caseSensitive: false,
      ).firstMatch(html);
      final section = aaMatch?.group(1) ?? html;

      final iframeRe = RegExp(
        r'''<iframe[^>]*(?:data-src|src)=["']([^"']+)["']''',
        caseSensitive: false,
      );

      var opt = 1;
      final seenSrc = <String>{};
      for (final m in iframeRe.allMatches(section)) {
        var src = _decodeHtmlEntities(m.group(1)!).trim();
        if (src.isEmpty || seenSrc.contains(src)) continue;
        seenSrc.add(src);

        final serverUrl = await _resolveEmbed(src);
        if (serverUrl == null || serverUrl.isEmpty) continue;

        String language = 'Desconocido';
        final info = buttonInfo['options-${opt - 1}'] ??
            buttonInfo['option-$opt'];
        if (info != null) language = info.language;

        result.add(_RawServer(
          option: info?.option ?? opt,
          language: language,
          serverUrl: serverUrl,
        ));
        opt++;
      }
    }

    return result;
  }

  /// Descarga embed (?trembed=...) y extrae iframe final (fastream, etc.).
  static Future<String?> _resolveEmbed(String embedUrl) async {
    var url = embedUrl.trim();
    if (url.isEmpty) return null;

    if (url.startsWith('/')) {
      url = '$_kBase$url';
    } else if (url.startsWith('?')) {
      url = '$_kBase/$url';
    }

    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isNotEmpty && !host.contains('seriesmetro')) {
      return url;
    }

    final embedHtml = await _fetch(url);
    if (embedHtml == null) return null;

    final inner = _extractIframeSrc(embedHtml);
    if (inner != null && inner.isNotEmpty) {
      final host2 = Uri.tryParse(inner)?.host.toLowerCase() ?? '';
      if (host2.contains('seriesmetro')) {
        final deeper = await _fetch(inner);
        if (deeper != null) {
          final finalUrl = _extractIframeSrc(deeper);
          if (finalUrl != null && finalUrl.isNotEmpty) return finalUrl;
        }
      }
      return inner;
    }

    final m3u8 = RegExp(
      r'''(?:file|src|source)\s*[:=]\s*["'](https?://[^"']+\.m3u8[^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(embedHtml);
    if (m3u8 != null) return m3u8.group(1);

    final mp4 = RegExp(
      r'''(?:file|src|source)\s*[:=]\s*["'](https?://[^"']+\.mp4[^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(embedHtml);
    if (mp4 != null) return mp4.group(1);

    return null;
  }

  static String? _extractIframeSrc(String html) {
    final dataSrc = RegExp(
      r'''<iframe[^>]*\bdata-src=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (dataSrc != null) {
      final u = _decodeHtmlEntities(dataSrc.group(1)!).trim();
      if (u.isNotEmpty) return u;
    }

    final src = RegExp(
      r'''<iframe[^>]*\bsrc=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (src != null) {
      final u = _decodeHtmlEntities(src.group(1)!).trim();
      if (u.isNotEmpty) return u;
    }

    return null;
  }

  static int? _optionFromId(String id) {
    final m = RegExp(r'(\d+)$').firstMatch(id);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null) return null;
    // options-0 → Opción 1 en la UI
    if (id.startsWith('options-') || id.startsWith('option-')) {
      return n + 1;
    }
    return n;
  }

  static String _decodeHtmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&#038;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  // ─── HTTP / slug ────────────────────────────────────────────────────────

  static Future<String?> _fetch(String url) async {
    try {
      final r = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': _kUa,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
              'Referer': '$_kBase/',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200 && r.body.isNotEmpty) return r.body;
    } catch (_) {}
    return null;
  }

  static String _slugify(String title) {
    var s = title.trim().toLowerCase();
    const map = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n', 'ç': 'c',
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
    s = s.replaceAll(RegExp(r'[\s-]+'), '-');
    return s.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String _languageToCode(String language) {
    final lang = language.toLowerCase();
    if (lang.contains('castellano') ||
        lang.contains('españa') ||
        lang.contains('spain')) {
      return 'es_ES';
    }
    if (lang.contains('inglés') ||
        lang.contains('ingles') ||
        lang.contains('english') ||
        lang.contains('sub') ||
        lang.contains('vose')) {
      return 'en_US';
    }
    if (lang.contains('japon')) return 'ja_JA';
    return 'es_MX';
  }
}

// ─── Modelos ──────────────────────────────────────────────────────────────

class SeriesMetroServer {
  final int? option;
  final String language;
  final String url;
  final int tmdbId;
  final int season;
  final int episode;

  const SeriesMetroServer({
    this.option,
    required this.language,
    required this.url,
    required this.tmdbId,
    this.season = 0,
    this.episode = 0,
  });

  Map<String, dynamic> toModalMap() {
    final name = option != null ? 'Opción $option' : 'Servidor';
    return {
      'servidor_nombre': 'SeriesMetro · $name',
      'servidor_url': url,
      'calidad': 'HD',
      'idioma': SeriesMetroService._languageToCode(language),
      'estado': 'activo',
      'es_seriesmetro': true,
      'tmdb_id': tmdbId,
      'season': season,
      'episode': episode,
    };
  }
}

class _TmdbInfo {
  final int id;
  final List<String> titles;
  final int? year;

  const _TmdbInfo({
    required this.id,
    required this.titles,
    this.year,
  });
}

class _FoundPage {
  final String url;
  final String html;
  const _FoundPage({required this.url, required this.html});
}

class _RawServer {
  final int? option;
  final String language;
  final String serverUrl;

  const _RawServer({
    this.option,
    required this.language,
    required this.serverUrl,
  });
}

class _ButtonInfo {
  final int? option;
  final String language;

  const _ButtonInfo({this.option, required this.language});
}