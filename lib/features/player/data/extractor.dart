import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../presentation/tv/tv_player_page.dart';
// ============================================================
//  RESOLVERS NATIVOS (portados de fuegocine)
// ============================================================

class StreamResult {
  final String url;
  final String quality;
  final Map<String, String> headers;
  final String serverName;
  final bool verified;

  StreamResult({
    required this.url,
    this.quality = 'HD',
    this.headers = const {},
    this.serverName = 'Server',
    this.verified = true,
  });
}

class NativeResolvers {
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // Regex reutilizables (sin problemas de comillas en Dart)
  static final RegExp _reM3u8Any = RegExp(
    r'https?://[^\s"\x27]+\.m3u8[^\s"\x27]*',
    caseSensitive: false,
  );
  static final RegExp _reM3u8Quoted = RegExp(
    '["\'](https?://[^"\']+?\\.m3u8[^"\']*?)["\']',
    caseSensitive: false,
  );
  static final RegExp _reFile = RegExp(
    'file\\s*:\\s*["\']([^"\']+)["\']',
    caseSensitive: false,
  );
  static final RegExp _reFileM3u8 = RegExp(
    'file\\s*:\\s*["\']([^"\']+\\.m3u8[^"\']*)["\']',
    caseSensitive: false,
  );
  static final RegExp _reSourcesFile = RegExp(
    'sources\\s*:\\s*\\[\\s*\\{\\s*file\\s*:\\s*["\']([^"\']+)["\']',
    caseSensitive: false,
  );
  static final RegExp _reLocationHref = RegExp(
    "window\\.location\\.href\\s*=\\s*['\"]([^'\"]+)['\"]",
    caseSensitive: false,
  );
  static final RegExp _rePassMd5 = RegExp(
    r'\$\.get\(['
    "'"
    r'](/pass_md5/[\w-]+)/([\w-]+)['
    "'"
    r']',
    caseSensitive: false,
  );
  static final RegExp _rePacker = RegExp(
    r"eval\(function\(p,a,c,k,e,[a-z]\)\{[\s\S]*?\}\s*\('([\s\S]+?)',\s*(\d+),\s*(\d+),\s*'([\s\S]+?)'\.split\('\|'\)",
  );
  static final RegExp _rePackerVidHide = RegExp(
    r"eval\(function\(p,a,c,k,e,[rd]\)[\s\S]*?\.split\('\|'\)[^\)]*\)\)",
  );
  static final RegExp _rePackerVidHideInner = RegExp(
    r"eval\(function\(p,a,c,k,e,[rd]\)\{.*?\}\s*\('([\s\S]*?)',\s*(\d+),\s*(\d+),\s*'([\s\S]*?)'\.split\('\|'\)",
  );

  // ---------- DETECCIÓN DE HOST ----------
  static String detectServer(String url) {
    final s = url.toLowerCase();
    if (_isMirror(s, _voeMirrors)) return 'voe';
    if (_isMirror(s, _streamwishMirrors) || s.contains('filelions')) {
      return 'streamwish';
    }
    if (_isMirror(s, _filemoonMirrors)) return 'filemoon';
    if (_isMirror(s, _vidhideMirrors)) return 'vidhide';
    if (_isMirror(s, _doodMirrors)) return 'doodstream';
    if (_isMirror(s, _goodstreamMirrors)) return 'goodstream';
    if (s.contains('vimeos') || s.contains('vms.sh')) return 'vimeos';
    if (_isMirror(s, _luluMirrors)) return 'lulustream';
    if (_isMirror(s, _dropcdnMirrors)) return 'dropcdn';
    if (s.contains('pixeldrain')) return 'pixeldrain';
    if (s.contains('buzzheavier') || s.contains('bzh.sh')) return 'buzzheavier';
    if (s.contains('ok.ru') || s.contains('okru')) return 'okru';
    if (s.contains('vidsrc') || s.contains('moviesapi')) return 'vidsrc';
    return 'unknown';
  }

  static bool _isMirror(String url, List<String> mirrors) {
    return mirrors.any((m) => url.contains(m));
  }

  static const _voeMirrors = [
    'voe.sx',
    'voe-sx',
    'voex.sx',
    'marissashare',
    'cloudwindow',
    'marissasharecareer',
  ];
  static const _streamwishMirrors = [
    'hlswish',
    'streamwish',
    'hglink',
    'hglamioz',
    'hglink.to',
    'audinifer',
    'embedwish',
    'awish',
    'dwish',
    'strwish',
    'filelions',
    'wishembed',
    'wishfast',
    'hanerix',
  ];
  static const _filemoonMirrors = [
    'filemoon',
    'moonalu',
    'moonembed',
    'bysedikamoum',
    'r66nv9ed',
    '398fitus',
    'filemoon.sx',
    'filemoon.to',
    'filemoon.lat',
    'filemoon.live',
    'filemoon.online',
    'filemoon.me',
    'fmoon.top',
  ];
  static const _vidhideMirrors = [
    'vidhide',
    'minochinos',
    'vadisov',
    'vaiditv',
    'amusemre',
    'callistanise',
    'vhaudm',
    'mdfury',
    'dintezuvio',
    'acek-cdn',
    'vedonm',
    'vidhidepro',
    'vidhidevip',
    'masukestin',
    'vidoza',
    'supervideo',
  ];
  static const _doodMirrors = [
    'dood.li',
    'dood.la',
    'ds2video.com',
    'ds2play.com',
    'dood.yt',
    'dood.ws',
    'dood.so',
    'dood.to',
    'dood.pm',
    'dood.watch',
    'dood.sh',
    'dood.cx',
    'dood.wf',
    'dood.re',
    'dood.one',
    'dood.tech',
    'dood.work',
    'doods.pro',
    'dooood.com',
    'doodstream.com',
    'doodstream.co',
    'd000d.com',
    'd0000d.com',
    'd0o0d.com',
    'do0od.com',
    'dooodster.com',
    'vidply.com',
    'do7go.com',
    'all3do.com',
    'doply.net',
    'dsvplay.com',
  ];
  static const _goodstreamMirrors = ['goodstream', 'gs.one'];
  static const _luluMirrors = [
    'lulustream',
    'luluvdo',
    'luluvids',
    'pondy',
    'lulupuv',
  ];
  static const _dropcdnMirrors = [
    'dropcdn.io',
    'dropload.io',
    'dropcdn',
    'dropload',
    'dr0pstream',
  ];

  // ---------- ENTRADA PRINCIPAL ----------
  static Future<StreamResult?> resolve(
    String url, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final server = detectServer(url);
    try {
      switch (server) {
        case 'voe':
          return await _resolveVoe(url).timeout(timeout);
        case 'doodstream':
          return await _resolveDoodstream(url).timeout(timeout);
        case 'streamwish':
          return await _resolveStreamWish(url).timeout(timeout);
        case 'vidhide':
          return await _resolveVidHide(url).timeout(timeout);
        case 'goodstream':
          return await _resolveGoodstream(url).timeout(timeout);
        case 'lulustream':
          return await _resolveLuluStream(url).timeout(timeout);
        case 'pixeldrain':
          return await _resolvePixeldrain(url).timeout(timeout);
        case 'buzzheavier':
          return await _resolveBuzzheavier(url).timeout(timeout);
        case 'dropcdn':
          return await _resolveDropcdn(url).timeout(timeout);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ---------- VOE ----------
  static Future<StreamResult?> _resolveVoe(String url) async {
    final res = await http.get(Uri.parse(url), headers: {'User-Agent': _ua});
    if (res.statusCode != 200) return null;
    final html = res.body;

    if (html.contains('window.location.href') && html.length < 2000) {
      final m = _reLocationHref.firstMatch(html);
      if (m != null) return _resolveVoe(m.group(1)!);
    }

    final jsonMatch = RegExp(
      r'<script type="application/json">([\s\S]*?)</script>',
    ).firstMatch(html);
    if (jsonMatch != null) {
      try {
        var encText = jsonMatch.group(1)!.trim();
        if (encText.startsWith('[')) {
          final list = jsonDecode(encText);
          if (list is List && list.isNotEmpty) {
            encText = list[0].toString();
          }
        }

        var decoded = encText.replaceAllMapped(RegExp(r'[a-zA-Z]'), (m) {
          final c = m.group(0)!;
          final code = c.codeUnitAt(0);
          final limit = c.toUpperCase() == c ? 90 : 122;
          final shifted = code + 13;
          return String.fromCharCode(limit >= shifted ? shifted : shifted - 26);
        });

        for (final n in ['@\$', '^^', '~@', '%?', '*~', '!!', '#&']) {
          decoded = decoded.replaceAll(n, '');
        }

        final b64_1 = utf8.decode(base64Decode(_padB64(decoded)));
        final shifted = String.fromCharCodes(b64_1.codeUnits.map((c) => c - 3));
        final reversed = shifted.split('').reversed.join();
        final decrypted = utf8.decode(base64Decode(_padB64(reversed)));
        final data = jsonDecode(decrypted);

        if (data is Map && data['source'] != null) {
          return StreamResult(
            url: data['source'].toString(),
            quality: '1080p',
            serverName: 'VOE',
            headers: {'User-Agent': _ua, 'Referer': url},
          );
        }
      } catch (_) {}
    }

    final m3u8 = _reM3u8Quoted.firstMatch(html);
    if (m3u8 != null) {
      return StreamResult(
        url: m3u8.group(1)!,
        quality: '1080p',
        serverName: 'VOE',
        headers: {'User-Agent': _ua, 'Referer': url},
      );
    }
    return null;
  }

  // ---------- DOODSTREAM ----------
  static Future<StreamResult?> _resolveDoodstream(String url) async {
    var embedUrl = url;
    if (!embedUrl.contains('/e/')) {
      embedUrl = embedUrl.replaceAll(RegExp(r'/(d|f)/'), '/e/');
    }

    final res = await http.get(
      Uri.parse(embedUrl),
      headers: {'User-Agent': _ua, 'Referer': 'https://lamovie.cc/'},
    );
    if (res.statusCode != 200) return null;

    final match = _rePassMd5.firstMatch(res.body);
    if (match == null) return null;

    final passPath = match.group(1)!;
    final token = match.group(2)!;
    final domain = Uri.parse(embedUrl).origin;
    final passUrl = '$domain$passPath';

    final passRes = await http.get(
      Uri.parse(passUrl),
      headers: {'User-Agent': _ua, 'Referer': embedUrl},
    );
    if (passRes.statusCode != 200) return null;

    final videoBase = passRes.body.trim();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = List.generate(
      10,
      (_) => chars[DateTime.now().microsecondsSinceEpoch % chars.length],
    ).join();
    final expiry = DateTime.now().millisecondsSinceEpoch;
    final finalUrl = '$videoBase$rnd?token=$token&expiry=$expiry';

    return StreamResult(
      url: finalUrl,
      quality: '720p',
      serverName: 'DoodStream',
      headers: {'User-Agent': _ua, 'Referer': '$domain/'},
    );
  }

  // ---------- STREAMWISH ----------
  static Future<StreamResult?> _resolveStreamWish(String url) async {
    final rawId = url.split('/').last.replaceAll(RegExp(r'\.html$'), '');
    final mirrors = [
      'https://hanerix.com/e/$rawId',
      'https://embedwish.com/e/$rawId',
      'https://hglink.to/e/$rawId',
      url,
      'https://streamwish.to/e/$rawId',
      'https://awish.pro/e/$rawId',
      'https://strwish.com/e/$rawId',
      'https://wishfast.top/e/$rawId',
    ];

    for (final mirror in mirrors) {
      try {
        final mirrorOrigin = Uri.parse(mirror).origin;
        final resp = await http
            .get(
              Uri.parse(mirror),
              headers: {'Referer': mirror, 'User-Agent': _ua},
            )
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode != 200) continue;
        final html = resp.body;

        String? m3u8Url;

        final hashMatch = RegExp(
          r'[0-9a-f]{32}',
          caseSensitive: false,
        ).firstMatch(html);
        if (hashMatch != null) {
          final hash = hashMatch.group(0)!;
          final dlUrl =
              '$mirrorOrigin/dl?op=view&file_code=$rawId&hash=$hash&embed=1&referer=&adb=1&hls4=1';
          final dlResp = await http
              .get(
                Uri.parse(dlUrl),
                headers: {
                  'User-Agent': _ua,
                  'Referer': mirror,
                  'X-Requested-With': 'XMLHttpRequest',
                },
              )
              .timeout(const Duration(seconds: 4));
          if (dlResp.statusCode == 200) {
            final m = _reM3u8Any.firstMatch(dlResp.body);
            if (m != null) m3u8Url = m.group(0);
          }
        }

        if (m3u8Url == null) {
          final packed = _rePacker.firstMatch(html);
          if (packed != null) {
            final unpacked = _unpackEval(
              packed.group(1)!,
              int.parse(packed.group(2)!),
              packed.group(4)!.split('|'),
            );
            final m = _reM3u8Any.firstMatch(unpacked);
            if (m != null) m3u8Url = m.group(0);
          }
        }

        if (m3u8Url == null) {
          final fileMatch = _reFile.firstMatch(html);
          if (fileMatch != null) m3u8Url = fileMatch.group(1);
        }

        if (m3u8Url != null) {
          m3u8Url = m3u8Url.replaceAll('\\', '');
          if (m3u8Url.startsWith('/')) m3u8Url = '$mirrorOrigin$m3u8Url';
          return StreamResult(
            url: m3u8Url,
            quality: 'Auto',
            serverName: 'StreamWish',
            headers: {
              'Referer': mirror,
              'Origin': mirrorOrigin,
              'User-Agent': _ua,
            },
          );
        }
      } catch (_) {}
    }
    return null;
  }

  // ---------- VIDHIDE ----------
  static Future<StreamResult?> _resolveVidHide(String url) async {
    final domain = Uri.parse(url).host;
    final res = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': _ua, 'Referer': 'https://$domain/'},
    );
    if (res.statusCode != 200) return null;
    final html = res.body;

    String? finalUrl;
    String quality = '1080p';

    final packedMatch = _rePackerVidHide.firstMatch(html);
    if (packedMatch != null) {
      final unpacked = _unpackVidHide(packedMatch.group(0)!);
      if (unpacked != null) {
        final hls = RegExp(r'"hls[24]"\s*:\s*"([^"]+)"').firstMatch(unpacked);
        if (hls != null) finalUrl = hls.group(1);
        final label =
            RegExp(
              r'\{label\s*:\s*"([^"]+)"',
              caseSensitive: false,
            ).firstMatch(unpacked) ??
            RegExp(
              r'name\s*:\s*"([^"]+)"',
              caseSensitive: false,
            ).firstMatch(unpacked);
        if (label != null) {
          quality = label.group(1)!.toLowerCase().contains('p')
              ? label.group(1)!
              : '${label.group(1)}p';
        }
      }
    }

    if (finalUrl == null) {
      final raw =
          RegExp(r'"hls[24]"\s*:\s*"([^"]+)"').firstMatch(html) ??
          _reFile.firstMatch(html) ??
          RegExp(
            '["\'](https?://[^"\']+?/stream/[^"\']+?\\.m3u8[^"\']*?)["\']',
            caseSensitive: false,
          ).firstMatch(html);
      if (raw != null) finalUrl = raw.group(1);
    }

    if (finalUrl == null) return null;
    if (!finalUrl.startsWith('http')) {
      finalUrl = '${Uri.parse(url).origin}$finalUrl';
    }
    if (!finalUrl.contains('referer=')) {
      finalUrl += '${finalUrl.contains('?') ? '&' : '?'}referer=embed69.org';
    }

    return StreamResult(
      url: finalUrl,
      quality: quality,
      serverName: 'VidHide',
      headers: {
        'User-Agent': _ua,
        'Referer': url.split('?').first,
        'Origin': Uri.parse(url).origin,
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
  }

  // ---------- GOODSTREAM ----------
  static Future<StreamResult?> _resolveGoodstream(String url) async {
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://goodstream.one/',
        'Accept-Language': 'es-MX,es;q=0.9',
      },
    );
    if (res.statusCode != 200) return null;
    final match = RegExp(r'file:\s*"([^"]+)"').firstMatch(res.body);
    if (match == null) return null;
    return StreamResult(
      url: match.group(1)!,
      quality: '1080p',
      serverName: 'GoodStream',
      headers: {
        'Referer': url,
        'Origin': 'https://goodstream.one',
        'User-Agent': _ua,
      },
    );
  }

  // ---------- LULUSTREAM ----------
  static Future<StreamResult?> _resolveLuluStream(String url) async {
    final origin = Uri.parse(url).origin;
    final res = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': _ua, 'Referer': url},
    );
    if (res.statusCode != 200) return null;
    final html = res.body;
    String? m3u8Url;

    final sources = _reSourcesFile.firstMatch(html);
    if (sources != null) m3u8Url = sources.group(1);

    if (m3u8Url == null) {
      final packed = _rePacker.firstMatch(html);
      if (packed != null) {
        final unpacked = _unpackEval(
          packed.group(1)!,
          int.parse(packed.group(2)!),
          packed.group(4)!.split('|'),
        );
        final m = _reM3u8Any.firstMatch(unpacked);
        if (m != null) m3u8Url = m.group(0);
      }
    }

    if (m3u8Url == null) {
      final fileMatch = _reFileM3u8.firstMatch(html);
      if (fileMatch != null) m3u8Url = fileMatch.group(1);
    }

    if (m3u8Url == null) return null;
    m3u8Url = m3u8Url.replaceAll('\\', '');
    if (m3u8Url.startsWith('/')) m3u8Url = '$origin$m3u8Url';

    return StreamResult(
      url: m3u8Url,
      quality: 'HD',
      serverName: 'LuluStream',
      headers: {'Referer': url, 'Origin': origin, 'User-Agent': _ua},
    );
  }

  // ---------- PIXELDRAIN ----------
  static Future<StreamResult?> _resolvePixeldrain(String url) async {
    final idMatch = RegExp(
      r'/(u|l|api/file)/([a-zA-Z0-9]+)',
      caseSensitive: false,
    ).firstMatch(url);
    if (idMatch == null) return null;
    final fileId = idMatch.group(2)!;
    final directUrl = 'https://pixeldrain.com/api/file/$fileId?download=1';
    return StreamResult(
      url: directUrl,
      quality: 'HD',
      serverName: 'Pixeldrain',
      headers: {'User-Agent': _ua, 'Referer': 'https://pixeldrain.com/'},
    );
  }

  // ---------- BUZZHEAVIER ----------
  static Future<StreamResult?> _resolveBuzzheavier(String url) async {
    final cleanUrl = url.split('|').first.replaceAll(RegExp(r'/$'), '');
    final domain = Uri.parse(cleanUrl).host;
    final downloadUrl = '$cleanUrl/download';

    try {
      final head = await http
          .head(
            Uri.parse(downloadUrl),
            headers: {
              'User-Agent': _ua,
              'Referer': cleanUrl,
              'hx-current-url': cleanUrl,
              'hx-request': 'true',
              'Accept': '*/*',
            },
          )
          .timeout(const Duration(seconds: 6));

      final hx = head.headers['hx-redirect'];
      if (hx != null && hx.isNotEmpty) {
        var finalUrl = hx;
        if (hx.startsWith('/dl/')) finalUrl = 'https://$domain$hx';
        return StreamResult(
          url: '$finalUrl#.mp4',
          quality: 'HD',
          serverName: 'Buzzheavier',
          headers: {'User-Agent': _ua, 'Referer': cleanUrl},
        );
      }
    } catch (_) {}

    final id = cleanUrl.split('/').last;
    return StreamResult(
      url: 'https://buzzheavier.com/v/$id/video.mp4#.mp4',
      quality: 'HD',
      serverName: 'Buzzheavier',
      headers: {'User-Agent': _ua, 'Referer': cleanUrl},
    );
  }

  // ---------- DROPCDN ----------
  static Future<StreamResult?> _resolveDropcdn(String url) async {
    final normalized = url
        .replaceAll('/d/', '/')
        .replaceAll('/e/', '/')
        .replaceAll('/embed-', '/');
    final idMatch =
        RegExp(r'/([a-zA-Z0-9]+)$').firstMatch(normalized) ??
        RegExp(r'/([a-zA-Z0-9]+)_o/').firstMatch(normalized);
    final fileCode = idMatch?.group(1) ?? normalized.split('/').last;
    final embedUrl = 'https://dr0pstream.com/e/$fileCode';

    final res = await http.get(
      Uri.parse(embedUrl),
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://dr0pstream.com/',
        'Origin': 'https://dr0pstream.com',
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
    if (res.statusCode != 200) return null;

    final m3u8Matches = _reM3u8Any
        .allMatches(res.body)
        .map((m) => m.group(0)!)
        .toList();
    if (m3u8Matches.isEmpty) return null;

    var m3u8Url = m3u8Matches.firstWhere(
      (u) => u.contains('master.m3u8') && u.contains('?t='),
      orElse: () => m3u8Matches.firstWhere(
        (u) => u.contains('master.m3u8'),
        orElse: () => m3u8Matches.first,
      ),
    );
    m3u8Url = m3u8Url.replaceAll('\\/', '/');

    return StreamResult(
      url: m3u8Url,
      quality: 'HD',
      serverName: 'DropCDN',
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://dr0pstream.com/',
        'Origin': 'https://dr0pstream.com',
      },
    );
  }

  // ---------- HELPERS ----------
  static String _padB64(String s) {
    final pad = (4 - s.length % 4) % 4;
    return s + ('=' * pad);
  }

  static String _unpackEval(String payload, int radix, List<String> symtab) {
    const chars =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    int unbase(String str) {
      var result = 0;
      for (var i = 0; i < str.length; i++) {
        final pos = chars.indexOf(str[i]);
        if (pos == -1) return -1;
        result = result * radix + pos;
      }
      return result;
    }

    return payload.replaceAllMapped(RegExp(r'\b([0-9a-zA-Z]+)\b'), (m) {
      final idx = unbase(m.group(1)!);
      if (idx < 0 || idx >= symtab.length) return m.group(0)!;
      final val = symtab[idx];
      return val.isNotEmpty ? val : m.group(0)!;
    });
  }

  static String? _unpackVidHide(String script) {
    try {
      final match = _rePackerVidHideInner.firstMatch(script);
      if (match == null) return null;
      final p = match.group(1)!;
      final a = int.parse(match.group(2)!);
      final k = match.group(4)!.split('|');
      const chars = '0123456789abcdefghijklmnopqrstuvwxyz';

      String decode(int l, int s) {
        var res = '';
        var n = l;
        while (n > 0) {
          res = chars[n % s] + res;
          n = n ~/ s;
        }
        return res.isEmpty ? '0' : res;
      }

      return p.replaceAllMapped(RegExp(r'\b\w+\b'), (m) {
        final s = int.tryParse(m.group(0)!, radix: 36) ?? -1;
        if (s >= 0 && s < k.length && k[s].isNotEmpty) return k[s];
        return decode(s, a);
      });
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
//  EXTRACTOR PAGE
// ============================================================

class ExtractorPage extends StatefulWidget {
  final int idcontenido;
  final int? tmdbId;
  final int? temporada;
  final int? capitulo;
  final String servidorUrl;
  final String servidorNombre;
  final String tipo;
  final String titulo;
  final int? idServidor;
  final String? idioma;

  const ExtractorPage({
    super.key,
    required this.idcontenido,
    this.tmdbId,
    this.temporada,
    this.capitulo,
    required this.servidorUrl,
    required this.servidorNombre,
    required this.tipo,
    required this.titulo,
    this.idServidor,
    this.idioma,
  });

  @override
  State<ExtractorPage> createState() => _ExtractorPageState();
}

class _ExtractorPageState extends State<ExtractorPage>
    with WidgetsBindingObserver {
  static const String _kHostCacheKey = 'extractor_host_methods';
  static const String _kMethodWebview = 'webview_media_detector';
  static const String _kMethodNative = 'native_resolver';

  late final String initialUrl;
  late final String _hostKey;
  late WebViewController _webViewController;
  final Set<String> detectedUrls = {};
  bool isSearching = true;
  bool showWebView = false;
  String? selectedM3u8Url;
  Timer? _searchTimer;
  bool _isNavigating = false;
  bool _detectionStopped = false;
  bool _hostKnown = false;
  String? _cachedMethod;
  bool _nativeTried = false;

  int get _resolvedTmdbId => widget.tmdbId ?? widget.idcontenido;

  @override
  void initState() {
    super.initState();
    initialUrl = widget.servidorUrl;
    _hostKey = _extractHost(initialUrl);
    WidgetsBinding.instance.addObserver(this);
    _lockToLandscape();
    _loadHostCache().then((_) {
      _initWebView();
      if (_cachedMethod == _kMethodNative) {
        _tryNativeResolver(early: true);
      }
    });
  }

  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      var host = uri.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      return host;
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadHostCache() async {
    if (_hostKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kHostCacheKey);
      if (raw == null || raw.isEmpty) return;
      final map = Map<String, dynamic>.from(jsonDecode(raw));
      final entry = map[_hostKey];
      if (entry is Map) {
        _cachedMethod = entry['method']?.toString();
        _hostKnown = _cachedMethod != null && _cachedMethod!.isNotEmpty;
      }
    } catch (_) {}
  }

  Future<void> _saveHostMethod(String method) async {
    if (_hostKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kHostCacheKey);
      final map = raw != null && raw.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(raw))
          : <String, dynamic>{};
      map[_hostKey] = {
        'method': method,
        'servidor': widget.servidorNombre,
        'ts': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_kHostCacheKey, jsonEncode(map));
      _cachedMethod = method;
      _hostKnown = true;
    } catch (_) {}
  }

  Future<void> _tryNativeResolver({bool early = false}) async {
    if (_nativeTried || _isNavigating || _detectionStopped) return;
    _nativeTried = true;

    final result = await NativeResolvers.resolve(initialUrl);
    if (result != null && result.url.isNotEmpty && mounted && !_isNavigating) {
      selectedM3u8Url = result.url;
      await _saveHostMethod(_kMethodNative);
      _tryNavigateToPlayer();
    }
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      )
      ..addJavaScriptChannel(
        'MediaDetector',
        onMessageReceived: (JavaScriptMessage message) {
          if (_detectionStopped || _isNavigating) return;
          final url = message.message.trim();
          if (url.isNotEmpty && _isMediaUrl(url)) {
            _addDetectedUrl(url);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() {});
          },
          onPageFinished: (_) {
            if (_detectionStopped || _isNavigating) return;
            _injectPowerfulMediaDetector();
            _startPeriodicSearch();
          },
          onNavigationRequest: (request) {
            if (_detectionStopped || _isNavigating) {
              return NavigationDecision.prevent;
            }
            final uri = Uri.parse(request.url);
            final baseUri = Uri.parse(initialUrl);
            if (uri.host == baseUri.host || uri.host.isEmpty) {
              if (_isMediaUrl(request.url)) {
                _addDetectedUrl(request.url);
              }
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));

    if (mounted) setState(() {});
  }

  bool _isMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.ts') ||
        lower.contains('.m4s') ||
        lower.contains('master.m3u8') ||
        lower.contains('playlist.m3u8') ||
        lower.contains('index.m3u8');
  }

  String _toAbsoluteUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.isAbsolute) return url;
      return Uri.parse(initialUrl).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  void _addDetectedUrl(String url) {
    if (_isNavigating || _detectionStopped) return;

    final absoluteUrl = _toAbsoluteUrl(url);
    if (detectedUrls.add(absoluteUrl)) {
      if (absoluteUrl.contains('.m3u8') ||
          (selectedM3u8Url == null && absoluteUrl.contains('.mp4'))) {
        selectedM3u8Url = absoluteUrl;
        _saveHostMethod(_kMethodWebview);
        _tryNavigateToPlayer();
      }
    }
  }

  void _stopDetectionJs() {
    try {
      _webViewController.runJavaScript('''
        (function() {
          if (window.__mdCleanup) {
            try { window.__mdCleanup(); } catch(e) {}
          }
          document.querySelectorAll('video').forEach(v => { try { v.pause(); } catch(e) {} });
        })();
      ''');
    } catch (_) {}
  }

  void _tryNavigateToPlayer() {
    if (selectedM3u8Url != null && mounted && !_isNavigating) {
      _isNavigating = true;
      _detectionStopped = true;
      _searchTimer?.cancel();
      _stopDetectionJs();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            videoUrl: selectedM3u8Url!,
            idcontenido: widget.idcontenido,
            tmdbId: _resolvedTmdbId,
            temporada: widget.temporada,
            capitulo: widget.capitulo,
            tipo: widget.tipo,
            titulo: widget.titulo,
            idioma: widget.idioma,
          ),
        ),
      );
    }
  }

  void _lockToLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _unlockOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _injectPowerfulMediaDetector() {
    final aggressive = _hostKnown && _cachedMethod == _kMethodWebview;
    final intervalMs = aggressive ? 1800 : 3500;

    _webViewController.runJavaScript('''
      (function() {
        if (window.__mdCleanup) {
          try { window.__mdCleanup(); } catch(e) {}
        }

        let stopped = false;
        const urls = new Set();

        const sendUrl = (url) => {
          if (stopped || !url) return;
          try {
            const absUrl = new URL(url, location.href).href;
            if ((absUrl.includes('.m3u8') || absUrl.includes('.mp4') ||
                 absUrl.includes('.ts') || absUrl.includes('.m4s')) && !urls.has(absUrl)) {
              urls.add(absUrl);
              if (window.MediaDetector && window.MediaDetector.postMessage) {
                window.MediaDetector.postMessage(absUrl);
              }
            }
          } catch(e) {}
        };

        if (!window.__mdOrigFetch) window.__mdOrigFetch = window.fetch;
        if (!window.__mdOrigXhrOpen) window.__mdOrigXhrOpen = XMLHttpRequest.prototype.open;

        window.fetch = function(...args) {
          if (!stopped) {
            const input = args[0];
            const url = typeof input === 'string' ? input : (input?.url || '');
            if (url) sendUrl(url);
          }
          return window.__mdOrigFetch.apply(this, args);
        };

        try {
          XMLHttpRequest.prototype.open = function(method, url) {
            if (!stopped && url) sendUrl(url);
            window.__mdOrigXhrOpen.apply(this, arguments);
          };
        } catch(e) {}

        try {
          if (window.Hls && Hls.isSupported() && !window.__mdHlsWrapped) {
            window.__mdHlsWrapped = true;
            const OriginalHls = window.Hls;
            window.Hls = function(config) {
              const hls = new OriginalHls(config);
              hls.on(Hls.Events.MANIFEST_PARSED, (event, data) => {
                if (stopped) return;
                data.levels?.forEach(level => {
                  [level.url, ...(level.url || [])].flat().forEach(u => sendUrl(u));
                });
              });
              hls.on(Hls.Events.LEVEL_LOADED, (event, data) => {
                if (stopped) return;
                data.details?.fragments?.forEach(f => sendUrl(f.url));
              });
              return hls;
            };
          }
        } catch(e) {}

        const combinedCheck = () => {
          if (stopped) return;
          try {
            performance.getEntriesByType('resource').forEach(entry => {
              const url = entry.name;
              const type = entry.initiatorType;
              const ct = entry.contentType || '';
              if (
                ct.startsWith('video/') || ct.startsWith('audio/') ||
                ['video','audio','xmlhttprequest','other'].includes(type) ||
                url.includes('.m3u8') || url.includes('.mp4') ||
                url.includes('.ts') || url.includes('.m4s')
              ) {
                sendUrl(url);
              }
            });
          } catch(e) {}

          try {
            document.querySelectorAll('video, source, [src], [href], iframe').forEach(el => {
              const src = el.src || el.href || el.getAttribute('src') || el.getAttribute('href') || '';
              if (src) sendUrl(src);
            });
          } catch(e) {}
        };
        combinedCheck();
        const mdInterval = setInterval(combinedCheck, $intervalMs);

        try {
          if (window.jwplayer) {
            const playlist = window.jwplayer().getPlaylist?.() || [];
            playlist.forEach(item => {
              if (item.file) sendUrl(item.file);
              if (item.sources) item.sources.forEach(s => s.file && sendUrl(s.file));
            });
          }
        } catch(e) {}

        try {
          if (window.videojs) {
            window.videojs.getAllPlayers?.().forEach(p => {
              const src = p.tech?.()?.currentSource_?.src;
              if (src) sendUrl(src);
            });
          }
        } catch(e) {}

        try {
          if (window._mutationObserver) {
            window._mutationObserver.disconnect();
          }
          window._mutationObserver = new MutationObserver(() => {
            if (stopped) return;
            document.querySelectorAll('video, source').forEach(el => {
              if (el.src) sendUrl(el.src);
            });
          });
          window._mutationObserver.observe(document.body, { childList: true, subtree: true });
        } catch(e) {}

        window.__mdCleanup = function() {
          stopped = true;
          try { clearInterval(mdInterval); } catch(e) {}
          try {
            if (window._mutationObserver) {
              window._mutationObserver.disconnect();
              window._mutationObserver = null;
            }
          } catch(e) {}
          try { window.fetch = window.__mdOrigFetch; } catch(e) {}
          try { XMLHttpRequest.prototype.open = window.__mdOrigXhrOpen; } catch(e) {}
        };
      })();
    ''');
  }

  void _startPeriodicSearch() {
    _searchTimer?.cancel();
    final timeoutSec = _hostKnown ? 7 : 12;
    _searchTimer = Timer(Duration(seconds: timeoutSec), () {
      if (mounted &&
          selectedM3u8Url == null &&
          !_isNavigating &&
          !_detectionStopped) {
        _tryNativeResolver().then((_) {
          if (mounted &&
              selectedM3u8Url == null &&
              !_isNavigating &&
              !_detectionStopped) {
            setState(() {
              isSearching = false;
              showWebView = true;
            });
          }
        });
      }
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _lockToLandscape();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchTimer?.cancel();
    _detectionStopped = true;

    if (!_isNavigating) {
      _unlockOrientation();
    }

    _stopDetectionJs();
    try {
      _webViewController.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}

    super.dispose();
  }

  Widget _buildBackButton() {
    final topPad = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topPad + 12,
      left: 16,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.black.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                _unlockOrientation();
                Navigator.pop(context);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (showWebView) WebViewWidget(controller: _webViewController),
          if (isSearching && !_isNavigating)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 6,
                  ),
                  if (_hostKnown) ...[
                    const SizedBox(height: 16),
                    Text(
                      _cachedMethod == _kMethodNative
                          ? 'Host conocido · resolver nativo'
                          : 'Host conocido · extracción rápida',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (showWebView && !_isNavigating) _buildBackButton(),
          if (selectedM3u8Url != null && !_isNavigating)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 90,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '¡Stream encontrado!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${widget.titulo}${widget.temporada != null && widget.capitulo != null ? ' - T${widget.temporada?.toString().padLeft(2, '0')}C${widget.capitulo?.toString().padLeft(2, '0')}' : ''}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton.icon(
                      onPressed: _tryNavigateToPlayer,
                      icon: const Icon(Icons.play_arrow, size: 30),
                      label: const Text(
                        'Reproducir',
                        style: TextStyle(fontSize: 20),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
