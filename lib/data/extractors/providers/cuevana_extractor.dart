// lib/servicio/cuevana.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Scraper nativo de Cuevana (wv3.cuevana3.eu).
/// No usa APIs propias ni player.php: todo se hace en Dart.
class CuevanaService {
  CuevanaService._();

  static const _kTmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const _kTmdbBase = 'https://api.themoviedb.org/3';
  static const _kBase = 'https://wv3.cuevana3.eu';

  static const _kUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Servidores permitidos (mismo filtro que tu PHP).
  static const _kAllowed = [
    'streamwish',
    'vidhide',
    'filelions',
    'vidhidepro',
    'streamwish.to',
    'vidhidepro.com',
    'filelions.com',
    'filelions.to',
    ' ',
  ];

  /// Mapeo de dominios del player (antes en player.php).
  static const _kDomainMap = <String, String>{
    'streamwish.to': 'hgplaycdn.com',
    'vidhidepro.com': 'callistanise.com',
    'filelions.to': 'callistanise.com',
  };

  /// Emite servidores listos para [ServidoresModal].
  static Stream<CuevanaServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) {
      throw Exception('tmdb_id inválido');
    }

    final tmdb = await _getTmdbInfo(tmdbId, isMovie ? 'movie' : 'tv');
    if (tmdb.latino.isEmpty && tmdb.ingles.isEmpty && tmdb.castellano.isEmpty) {
      throw Exception('No se obtuvo info de TMDB');
    }

    final List<_VideoGroup> groups;

    if (isMovie) {
      groups = await _scrapeMovie(tmdb);
    } else {
      groups = await _scrapeEpisode(tmdb, season, episode);
    }

    if (groups.isEmpty) {
      throw Exception('No se encontraron servidores en Cuevana');
    }

    final seen = <String>{};

    for (final group in groups) {
      for (final video in group.videos) {
        if (!_isAllowedServer(video.cyberlocker)) continue;

        // Resolver URL real del cyberlocker (lógica de player.php)
        final resolved = await _resolvePlayer(video.url);
        if (resolved == null || resolved.isEmpty) continue;
        if (seen.contains(resolved)) continue;
        seen.add(resolved);

        yield CuevanaServer(
          cyberlocker: video.cyberlocker,
          url: resolved,
          quality: video.quality,
          idiomaCode: _languageToCode(group.language),
          tmdbId: tmdbId,
          season: isMovie ? 0 : season,
          episode: isMovie ? 0 : episode,
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
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

    int? year;
    final dateStr = mediaType == 'movie'
        ? (es?['release_date'] ?? en?['release_date'])?.toString()
        : (es?['first_air_date'] ?? en?['first_air_date'])?.toString();
    if (dateStr != null && dateStr.length >= 4) {
      year = int.tryParse(dateStr.substring(0, 4));
    }

    return _TmdbInfo(
      id: tmdbId,
      latino: (es?['title'] ?? es?['name'] ?? '').toString(),
      castellano: (eses?['title'] ?? eses?['name'] ?? '').toString(),
      ingles: (en?['title'] ?? en?['name'] ?? '').toString(),
      year: year,
    );
  }

  // ─── Movie ──────────────────────────────────────────────────────────────

  static Future<List<_VideoGroup>> _scrapeMovie(_TmdbInfo tmdb) async {
    final candidates = _buildCandidates(isMovie: true, tmdb: tmdb);
    final found = await _findWorkingUrl(candidates, movie: true);
    if (found == null) return [];

    final pageProps = _extractNextData(found.html);
    if (pageProps == null) return [];

    final thisMovie = pageProps['thisMovie'];
    if (thisMovie is! Map) return [];

    final videosData = thisMovie['videos'];
    if (videosData is! Map) return [];

    return _getVideoGroupsFromData(Map<String, dynamic>.from(videosData));
  }

  // ─── Episode ────────────────────────────────────────────────────────────

  static Future<List<_VideoGroup>> _scrapeEpisode(
    _TmdbInfo tmdb,
    int season,
    int episode,
  ) async {
    final nombres = <String>[
      if (tmdb.latino.trim().isNotEmpty) tmdb.latino,
      if (tmdb.castellano.trim().isNotEmpty) tmdb.castellano,
      if (tmdb.ingles.trim().isNotEmpty) tmdb.ingles,
    ];

    final candidates = <String>[];
    for (final nombre in nombres) {
      final slug = _slugify(nombre);
      if (slug.isEmpty) continue;
      candidates.add(
        '$_kBase/episodio/$slug-temporada-$season-episodio-$episode',
      );
      candidates.add(
        '$_kBase/episodio/$slug-${tmdb.id}-temporada-$season-episodio-$episode',
      );
    }

    String? episodeUrl;
    String? html;

    for (final tryUrl in candidates) {
      final body = await _fetch(tryUrl);
      if (body == null) continue;
      if (body.contains('__NEXT_DATA__') && body.contains('"episode"')) {
        episodeUrl = tryUrl;
        html = body;
        break;
      }
    }

    if (html == null || episodeUrl == null) return [];

    final pageProps = _extractNextData(html);
    if (pageProps == null) return [];

    final ep = pageProps['episode'];
    if (ep is! Map) return [];

    final videosData = ep['videos'];
    if (videosData is! Map) return [];

    return _getVideoGroupsFromData(Map<String, dynamic>.from(videosData));
  }

  // ─── Candidates / find page ─────────────────────────────────────────────

  static List<String> _buildCandidates({
    required bool isMovie,
    required _TmdbInfo tmdb,
  }) {
    final prefix = isMovie ? '$_kBase/ver-pelicula/' : '$_kBase/ver-serie/';
    final titles = [tmdb.latino, tmdb.castellano, tmdb.ingles];
    final out = <String>[];

    for (final title in titles) {
      if (title.trim().isEmpty) continue;
      final slug = _slugify(title);
      if (slug.isEmpty) continue;
      out.add('$prefix$slug');
      out.add('$prefix$slug-${tmdb.id}');
      if (tmdb.year != null) {
        out.add('$prefix$slug-${tmdb.year}');
      }
    }
    return out.toSet().toList();
  }

  static Future<_FoundPage?> _findWorkingUrl(
    List<String> candidates, {
    required bool movie,
  }) async {
    final needle = movie ? '"thisMovie"' : '"thisSerie"';
    for (final url in candidates) {
      final html = await _fetch(url);
      if (html == null) continue;
      if (html.contains('__NEXT_DATA__') && html.contains(needle)) {
        return _FoundPage(url: url, html: html);
      }
    }
    return null;
  }

  // ─── Parse __NEXT_DATA__ ────────────────────────────────────────────────

  static Map<String, dynamic>? _extractNextData(String html) {
    final re = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    );
    final m = re.firstMatch(html);
    if (m == null) return null;
    try {
      final data = jsonDecode(m.group(1)!);
      if (data is! Map) return null;
      final props = data['props'];
      if (props is! Map) return null;
      final pageProps = props['pageProps'];
      if (pageProps is! Map) return null;
      return Map<String, dynamic>.from(pageProps);
    } catch (_) {
      return null;
    }
  }

  static List<_VideoGroup> _getVideoGroupsFromData(Map<String, dynamic> videos) {
    const langMap = {
      'latino': 'Español Latino',
      'spanish': 'Español Castellano',
      'english': 'Inglés',
      'japanese': 'Japonés',
    };

    final groups = <_VideoGroup>[];

    for (final entry in langMap.entries) {
      final listRaw = videos[entry.key];
      if (listRaw is! List || listRaw.isEmpty) continue;

      final videosList = <_RawVideo>[];
      for (final v in listRaw) {
        if (v is! Map) continue;
        final cyber = (v['cyberlocker'] ?? '').toString();
        final url = (v['result'] ?? '').toString();
        final quality = (v['quality'] ?? 'HD').toString();
        if (url.isEmpty) continue;
        videosList.add(
          _RawVideo(cyberlocker: cyber, url: url, quality: quality),
        );
      }
      if (videosList.isNotEmpty) {
        groups.add(_VideoGroup(language: entry.value, videos: videosList));
      }
    }
    return groups;
  }

  // ─── Player resolve (antes player.php) ──────────────────────────────────

  /// Descarga la página del cyberlocker y extrae `var url = '...'`.
  static Future<String?> _resolvePlayer(String sourceUrl) async {
    if (sourceUrl.isEmpty) return null;

    final html = await _fetch(sourceUrl);
    if (html == null) return null;

    String? videoUrl;

    final m1 = RegExp(r"var url = '([^']+)'").firstMatch(html);
    if (m1 != null) videoUrl = m1.group(1);

    if (videoUrl == null) {
      final m2 = RegExp(r'var url = "([^"]+)"').firstMatch(html);
      if (m2 != null) videoUrl = m2.group(1);
    }

    // Fallbacks comunes en embeds
    if (videoUrl == null) {
      final m3 = RegExp(
        r'''(?:file|src|source)\s*[:=]\s*["'](https?://[^"']+\.m3u8[^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (m3 != null) videoUrl = m3.group(1);
    }

    if (videoUrl == null || videoUrl.isEmpty) return null;

    return _mapDomain(videoUrl);
  }

  static String _mapDomain(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      for (final entry in _kDomainMap.entries) {
        if (host.contains(entry.key)) {
          final newHost = host.replaceFirst(entry.key, entry.value);
          return uri.replace(host: newHost).toString();
        }
      }
    } catch (_) {}
    return url;
  }

  static bool _isAllowedServer(String name) {
    final n = name.toLowerCase();
    for (final a in _kAllowed) {
      if (n.contains(a.toLowerCase())) return true;
    }
    return false;
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
            },
          )
          .timeout(const Duration(seconds: 18));
      if (r.statusCode == 200 && r.body.isNotEmpty) return r.body;
    } catch (_) {}
    return null;
  }

  static String _slugify(String title) {
    var s = title.trim().toLowerCase();
    // Quitar acentos básicos
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
    if (lang.contains('castellano') || lang.contains('españa')) {
      return 'es_ES';
    }
    if (lang.contains('inglés') ||
        lang.contains('ingles') ||
        lang.contains('english') ||
        lang.contains('sub')) {
      return 'en_US';
    }
    if (lang.contains('japon')) return 'ja_JA';
    return 'es_MX';
  }
}

// ─── Modelos ──────────────────────────────────────────────────────────────

class CuevanaServer {
  final String cyberlocker;
  final String url;
  final String quality;
  final String idiomaCode;
  final int tmdbId;
  final int season;
  final int episode;

  const CuevanaServer({
    required this.cyberlocker,
    required this.url,
    this.quality = 'HD',
    this.idiomaCode = 'es_MX',
    required this.tmdbId,
    this.season = 0,
    this.episode = 0,
  });

  Map<String, dynamic> toModalMap() {
    final name = cyberlocker.isEmpty
        ? 'Servidor'
        : '${cyberlocker[0].toUpperCase()}${cyberlocker.substring(1)}';
    return {
      'servidor_nombre': 'Cuevana · $name',
      'servidor_url': url,
      'calidad': quality,
      'idioma': idiomaCode,
      'estado': 'activo',
      'es_cuevana': true,
      'tmdb_id': tmdbId,
      'season': season,
      'episode': episode,
    };
  }
}

class _TmdbInfo {
  final int id;
  final String latino;
  final String castellano;
  final String ingles;
  final int? year;

  const _TmdbInfo({
    required this.id,
    required this.latino,
    required this.castellano,
    required this.ingles,
    this.year,
  });
}

class _FoundPage {
  final String url;
  final String html;
  const _FoundPage({required this.url, required this.html});
}

class _RawVideo {
  final String cyberlocker;
  final String url;
  final String quality;
  const _RawVideo({
    required this.cyberlocker,
    required this.url,
    required this.quality,
  });
}

class _VideoGroup {
  final String language;
  final List<_RawVideo> videos;
  const _VideoGroup({required this.language, required this.videos});
}