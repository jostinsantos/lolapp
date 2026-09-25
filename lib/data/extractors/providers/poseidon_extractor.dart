// lib/servicio/poseidon.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Scraper nativo de PoseidonHD2 (www.poseidonhd2.co).
/// Misma lógica que CuevanaService: TMDB → slug → página → __NEXT_DATA__ → player.php → URL real.
class PoseidonService {
  PoseidonService._();

  static const _kTmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const _kTmdbBase = 'https://api.themoviedb.org/3';
  static const _kBase = 'https://www.poseidonhd2.co';

  static const _kUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Dominios a reemplazar en la URL final resuelta.
  static const _kDomainMap = <String, String>{
    'streamwish.to': 'hgplaycdn.com',
    'vidhidepro.com': 'callistanise.com',
    'filelions.to': 'callistanise.com',
    'voe.sx': 'eugenemakedraw.com',
    'doodstream.com': 'playmogo.com',
  };

  /// Emite servidores listos (mismo formato que CuevanaServer).
  static Stream<PoseidonServer> scrape({
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
      throw Exception('No se encontraron servidores en PoseidonHD2');
    }

    final seen = <String>{};

    for (final group in groups) {
      for (final video in group.videos) {
        // Resolver player.php → URL real del cyberlocker
        final resolved = await _resolvePlayer(video.url);
        if (resolved == null || resolved.isEmpty) continue;

        final finalUrl = _replaceDomain(resolved);
        if (seen.contains(finalUrl)) continue;
        seen.add(finalUrl);

        yield PoseidonServer(
          cyberlocker: video.cyberlocker,
          url: finalUrl,
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
    final candidates = _buildMovieCandidates(tmdb);
    final found = await _findWorkingUrl(candidates, isMovie: true);
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
    final candidates = _buildEpisodeCandidates(tmdb, season, episode);
    final found = await _findWorkingUrl(candidates, isMovie: false);
    if (found == null) return [];

    final pageProps = _extractNextData(found.html);
    if (pageProps == null) return [];

    // En episodios la clave suele ser "episode"
    final ep = pageProps['episode'] ?? pageProps['thisEpisode'];
    if (ep is! Map) return [];

    final videosData = ep['videos'];
    if (videosData is! Map) return [];

    return _getVideoGroupsFromData(Map<String, dynamic>.from(videosData));
  }

  // ─── Construcción de URLs (la parte clave de Poseidon) ──────────────────

  /// Película: /pelicula/{tmdbId}/{slug}
  static List<String> _buildMovieCandidates(_TmdbInfo tmdb) {
    final titles = [tmdb.latino, tmdb.castellano, tmdb.ingles];
    final out = <String>{};

    for (final title in titles) {
      if (title.trim().isEmpty) continue;
      final slug = _slugify(title);
      if (slug.isEmpty) continue;

      // Formato principal que usa el sitio
      out.add('$_kBase/pelicula/${tmdb.id}/$slug');

      // Variantes por si el slug cambia un poco
      if (tmdb.year != null) {
        out.add('$_kBase/pelicula/${tmdb.id}/$slug-${tmdb.year}');
      }
    }
    return out.toList();
  }

  /// Serie: /serie/{tmdbId}/{slug}/temporada/{s}/episodio/{e}
  static List<String> _buildEpisodeCandidates(
    _TmdbInfo tmdb,
    int season,
    int episode,
  ) {
    final titles = [tmdb.latino, tmdb.castellano, tmdb.ingles];
    final out = <String>{};

    for (final title in titles) {
      if (title.trim().isEmpty) continue;
      final slug = _slugify(title);
      if (slug.isEmpty) continue;

      out.add(
        '$_kBase/serie/${tmdb.id}/$slug/temporada/$season/episodio/$episode',
      );
    }
    return out.toList();
  }

  static Future<_FoundPage?> _findWorkingUrl(
    List<String> candidates, {
    required bool isMovie,
  }) async {
    final needle = isMovie ? '"thisMovie"' : '"episode"';
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
    // Mapeo de claves que usa Poseidon (idéntico a Cuevana)
    const langMap = {
      'latino': 'Español Latino',
      'spanish': 'Español Castellano',
      'english': 'Inglés / Subtitulado',
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

  // ─── Resolver player.php (igual que el PHP) ─────────────────────────────

  static Future<String?> _resolvePlayer(String sourceUrl) async {
    if (sourceUrl.isEmpty) return null;

    final html = await _fetch(sourceUrl);
    if (html == null) return null;

    String? videoUrl;

    // Patrón principal: var url = 'https://...'
    final m1 = RegExp(r"var\s+url\s*=\s*'([^']+)'").firstMatch(html);
    if (m1 != null) videoUrl = m1.group(1);

    if (videoUrl == null) {
      final m2 = RegExp(r'var\s+url\s*=\s*"([^"]+)"').firstMatch(html);
      if (m2 != null) videoUrl = m2.group(1);
    }

    // Fallback: window.location.href
    if (videoUrl == null) {
      final m3 = RegExp(
        r"window\.location\.href\s*=\s*'([^']+)'",
      ).firstMatch(html);
      if (m3 != null) videoUrl = m3.group(1);
    }

    // Fallback m3u8
    if (videoUrl == null) {
      final m4 = RegExp(
        r'''(?:file|src|source)\s*[:=]\s*["'](https?://[^"']+\.m3u8[^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (m4 != null) videoUrl = m4.group(1);
    }

    if (videoUrl == null || videoUrl.isEmpty) return null;
    return videoUrl;
  }

  /// Reemplaza dominios conocidos en la URL resuelta.
  static String _replaceDomain(String url) {
    var out = url;
    _kDomainMap.forEach((from, to) {
      out = out.replaceAll(from, to);
    });
    return out;
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
          .timeout(const Duration(seconds: 18));
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

class PoseidonServer {
  final String cyberlocker;
  final String url;
  final String quality;
  final String idiomaCode;
  final int tmdbId;
  final int season;
  final int episode;

  const PoseidonServer({
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
      'servidor_nombre': 'Poseidon · $name',
      'servidor_url': url,
      'calidad': quality,
      'idioma': idiomaCode,
      'estado': 'activo',
      'es_poseidon': true,
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