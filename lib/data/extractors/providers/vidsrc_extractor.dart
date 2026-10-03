// lib/servicio/vidsrc.dart
//
// VidSrc.me — solo encuentra embeds (como HackStore).
// NO resuelve HLS aquí: lo hace ExtractorHlsService en MainFuentes.

import 'dart:async';

import 'package:http/http.dart' as http;

class VidSrcService {
  static String _baseDom = 'https://vidsrc.me';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
  static const Duration _timeout = Duration(seconds: 18);

  static Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) return;

    try {
      final embedUrls = _buildEmbedCandidates(tmdbId, isMovie, season, episode);
      final seen = <String>{};

      for (final embedUrl in embedUrls) {
        final html = await _fetch(embedUrl);
        if (html == null || html.isEmpty) continue;

        _updateBaseDomFromHtml(html);

        final servers = _parseServers(html);
        for (var i = 0; i < servers.length; i++) {
          final s = servers[i];
          final hash = s['hash'] ?? '';
          final name = s['name'] ?? 'Server ${i + 1}';
          if (hash.isEmpty) continue;

          final rcpUrl = '$_baseDom/rcp/$hash';
          if (!seen.contains(rcpUrl)) {
            seen.add(rcpUrl);
            yield _map(
              url: rcpUrl,
              name: name.isNotEmpty ? name : 'VidSrc ${i + 1}',
            );
          }

          final prorcp = await _resolveProrcpFromRcp(rcpUrl);
          if (prorcp != null && prorcp.isNotEmpty && !seen.contains(prorcp)) {
            seen.add(prorcp);
            yield _map(
              url: prorcp,
              name: name.isNotEmpty ? '$name · Pro' : 'VidSrc Pro ${i + 1}',
            );
          }
        }

        for (final iframe in _parseIframes(html)) {
          if (seen.contains(iframe)) continue;
          seen.add(iframe);
          yield _map(url: iframe, name: 'VidSrc Embed');
        }

        if (seen.isEmpty) {
          seen.add(embedUrl);
          yield _map(url: embedUrl, name: 'VidSrc');
        }

        if (seen.isNotEmpty) break;
      }
    } catch (_) {}
  }

  static Map<String, dynamic> _map({
    required String url,
    required String name,
  }) {
    return {
      'servidor_url': url,
      'url': url,
      'servidor': name,
      'servidor_nombre': name,
      'server': 'VidSrc',
      'idioma': 'en_US',
      'language': 'en_US',
      'type': 'embed',
      'headers': {
        'User-Agent': _ua,
        'Referer': 'https://vidsrc.me/',
        'Origin': 'https://vidsrc.me',
      },
      'provider': 'vidsrc',
    };
  }

  static List<String> _buildEmbedCandidates(
    int tmdbId,
    bool isMovie,
    int season,
    int episode,
  ) {
    if (isMovie) {
      return [
        'https://vidsrc.me/embed/movie/$tmdbId',
        'https://vidsrc.me/embed/$tmdbId',
        'https://vidsrc.to/embed/movie/$tmdbId',
        'https://vidsrc.xyz/embed/movie/$tmdbId',
      ];
    }
    return [
      'https://vidsrc.me/embed/tv/$tmdbId/$season-$episode',
      'https://vidsrc.me/embed/$tmdbId/$season-$episode',
      'https://vidsrc.to/embed/tv/$tmdbId/$season-$episode',
      'https://vidsrc.xyz/embed/tv/$tmdbId/$season-$episode',
    ];
  }

  static void _updateBaseDomFromHtml(String html) {
    // Solo comillas dobles en el patrón (evita romper r'...')
    final m = RegExp(
      r'<iframe[^>]+src="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (m == null) {
      final m2 = RegExp(
        r"<iframe[^>]+src='([^']+)'",
        caseSensitive: false,
      ).firstMatch(html);
      if (m2 == null) return;
      _applyBaseDom(m2.group(1) ?? '');
      return;
    }
    _applyBaseDom(m.group(1) ?? '');
  }

  static void _applyBaseDom(String src) {
    if (src.isEmpty) return;
    if (src.startsWith('//')) src = 'https:$src';
    try {
      final u = Uri.parse(src);
      if (u.hasScheme && u.host.isNotEmpty) {
        _baseDom = '${u.scheme}://${u.host}';
      }
    } catch (_) {}
  }

  static List<Map<String, String>> _parseServers(String html) {
    final out = <Map<String, String>>[];
    final seen = <String>{};

    // data-hash="..." 
    final re1 = RegExp(
      r'data-hash="([^"]+)"[^>]*>([^<]*)',
      caseSensitive: false,
    );
    for (final m in re1.allMatches(html)) {
      final hash = m.group(1)?.trim() ?? '';
      if (hash.isEmpty || seen.contains(hash)) continue;
      seen.add(hash);
      final name = m.group(2)?.trim() ?? '';
      out.add({'hash': hash, 'name': name.isEmpty ? 'Server' : name});
    }

    if (out.isEmpty) {
      // data-hash='...'
      final re1b = RegExp(
        r"data-hash='([^']+)'[^>]*>([^<]*)",
        caseSensitive: false,
      );
      for (final m in re1b.allMatches(html)) {
        final hash = m.group(1)?.trim() ?? '';
        if (hash.isEmpty || seen.contains(hash)) continue;
        seen.add(hash);
        final name = m.group(2)?.trim() ?? '';
        out.add({'hash': hash, 'name': name.isEmpty ? 'Server' : name});
      }
    }

    if (out.isEmpty) {
      // Solo el hash, sin nombre
      final re2 = RegExp(r'data-hash="([^"]+)"', caseSensitive: false);
      for (final m in re2.allMatches(html)) {
        final hash = m.group(1)?.trim() ?? '';
        if (hash.isEmpty || seen.contains(hash)) continue;
        seen.add(hash);
        out.add({'hash': hash, 'name': 'Server'});
      }
    }

    if (out.isEmpty) {
      final re2b = RegExp(r"data-hash='([^']+)'", caseSensitive: false);
      for (final m in re2b.allMatches(html)) {
        final hash = m.group(1)?.trim() ?? '';
        if (hash.isEmpty || seen.contains(hash)) continue;
        seen.add(hash);
        out.add({'hash': hash, 'name': 'Server'});
      }
    }

    return out;
  }

  static List<String> _parseIframes(String html) {
    final out = <String>[];

    final reDq = RegExp(
      r'<iframe[^>]+src="([^"]+)"',
      caseSensitive: false,
    );
    for (final m in reDq.allMatches(html)) {
      final src = _normalizeSrc(m.group(1)?.trim() ?? '');
      if (src != null) out.add(src);
    }

    final reSq = RegExp(
      r"<iframe[^>]+src='([^']+)'",
      caseSensitive: false,
    );
    for (final m in reSq.allMatches(html)) {
      final src = _normalizeSrc(m.group(1)?.trim() ?? '');
      if (src != null) out.add(src);
    }

    return out;
  }

  static String? _normalizeSrc(String src) {
    if (src.isEmpty) return null;
    if (src.startsWith('//')) src = 'https:$src';
    if (src.startsWith('/')) src = '$_baseDom$src';
    if (src.startsWith('http')) return src;
    return null;
  }

  static Future<String?> _resolveProrcpFromRcp(String rcpUrl) async {
    try {
      final html = await _fetch(
        rcpUrl,
        extraHeaders: {'Referer': 'https://vidsrc.me/'},
      );
      if (html == null) return null;

      // src: '...'  o  src: "..."
      String path = '';
      final m1 = RegExp(r"src:\s*'([^']+)'").firstMatch(html);
      if (m1 != null) {
        path = m1.group(1)?.trim() ?? '';
      } else {
        final m2 = RegExp(r'src:\s*"([^"]+)"').firstMatch(html);
        path = m2?.group(1)?.trim() ?? '';
      }

      if (path.isEmpty) {
        final m3 = RegExp(
          r'<iframe[^>]+src="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(html);
        path = m3?.group(1)?.trim() ?? '';
      }
      if (path.isEmpty) {
        final m4 = RegExp(
          r"<iframe[^>]+src='([^']+)'",
          caseSensitive: false,
        ).firstMatch(html);
        path = m4?.group(1)?.trim() ?? '';
      }

      if (path.isEmpty) return null;
      if (path.startsWith('//')) return 'https:$path';
      if (path.startsWith('http')) return path;
      if (path.startsWith('/')) return '$_baseDom$path';
      return '$_baseDom/$path';
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fetch(
    String url, {
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final res = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': _ua,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9,es;q=0.8',
              'Referer': 'https://vidsrc.me/',
              ...?extraHeaders,
            },
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 400) return null;
      return res.body;
    } catch (_) {
      return null;
    }
  }
}