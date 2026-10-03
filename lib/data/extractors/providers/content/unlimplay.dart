import 'dart:convert';
import 'package:http/http.dart' as http;

class UnlimplayServer {
  final String lang; // latino | espanol | subtitulado
  final String name; // streamwish, vidhide 2, ...
  final String url;
  final String idiomaCode; // es_MX, es_ES, en_US

  const UnlimplayServer({
    required this.lang,
    required this.name,
    required this.url,
    required this.idiomaCode,
  });

  Map<String, dynamic> toModalMap() {
    final display = name
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    return {
      'servidor_nombre': 'Unlimplay · $display',
      'servidor_url': url,
      'calidad': 'HD',
      'idioma': idiomaCode,
      'estado': 'activo',
      'es_unlimplay': true,
    };
  }
}

class UnlimplayService {
  static const _allowed = ['streamwish', 'vidhide', 'filelions'];
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Solo reescribe hglink.to y streamwish.to → vibuxer.com
  static String _rewriteHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    final host = uri.host.toLowerCase();
    String? newHost;

   if (host == 'hglink.to' || host == 'streamwish.to') {
  newHost = 'vibuxer.com';
} else if (host == 'filelions.to' || host == 'minochinos.com') {
  newHost = 'callistanise.com';
}

    if (newHost == null) return url;
    return uri.replace(host: newHost).toString();
  }

  /// Scrape + emite servidores de a uno (carga progresiva en el modal).
  static Stream<UnlimplayServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    final embedUrl = isMovie
        ? 'https://unlimplay.com/f/embed/movie/$tmdbId'
        : 'https://unlimplay.com/f/embed/tv/$tmdbId/$season/$episode';

    final response = await http
        .get(
          Uri.parse(embedUrl),
          headers: {
            'User-Agent': _ua,
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'es-ES,es;q=0.9',
          },
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode != 200 || response.body.isEmpty) {
      throw Exception('No se pudo obtener la página Unlimplay');
    }

    final html = response.body;
    final sources = <Map<String, dynamic>>[];

    final embedsMatch = RegExp(
      r'const\s+EMBEDS\s*=\s*(\{.*?\});',
      dotAll: true,
    ).firstMatch(html);
    if (embedsMatch != null) {
      final decoded = _tryJson(embedsMatch.group(1)!);
      if (decoded != null) sources.add(decoded);
    }

    final finalMatch = RegExp(
      r'finalizePlayer\s*\(\s*(\{.*?\})\s*\)\s*;',
      dotAll: true,
    ).firstMatch(html);
    if (finalMatch != null) {
      final decoded = _tryJson(finalMatch.group(1)!);
      if (decoded != null) sources.add(decoded);
    }

    if (sources.isEmpty) {
      throw Exception('No se encontró EMBEDS ni finalizePlayer');
    }

    final merged = <String, Map<String, String>>{};

    for (final block in sources) {
      block.forEach((lang, servers) {
        if (servers is! Map) return;
        final langKey = lang.toString();
        merged.putIfAbsent(langKey, () => {});

        servers.forEach((name, embedUrl) {
          final url = embedUrl?.toString().trim() ?? '';
          if (url.isEmpty) return;

          final nameKey = name.toString();
          final bucket = merged[langKey]!;

          if (bucket[nameKey] == url) return;
          if (bucket.values.contains(url)) return;

          if (!bucket.containsKey(nameKey)) {
            bucket[nameKey] = url;
            return;
          }

          var n = 2;
          while (bucket.containsKey('$nameKey $n')) {
            n++;
          }
          bucket['$nameKey $n'] = url;
        });
      });
    }

    const langOrder = ['latino', 'español', 'espanol', 'subtitulado'];
    final langKeys = <String>[
      ...langOrder.where(merged.containsKey),
      ...merged.keys.where((k) => !langOrder.contains(k.toLowerCase())),
    ];

    for (final lang in langKeys) {
      final servers = merged[lang]!;
      for (final entry in servers.entries) {
        final base = entry.key.toLowerCase().trim();
        final ok = _allowed.any((p) => base.startsWith(p));
        if (!ok) continue;

        yield UnlimplayServer(
          lang: lang,
          name: entry.key,
          url: _rewriteHost(entry.value),
          idiomaCode: _langToCode(lang),
        );

        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
  }

  static Map<String, dynamic>? _tryJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static String _langToCode(String lang) {
    final l = lang.toLowerCase().trim();
    if (l == 'latino' || l == 'lat' || l == 'mx') return 'es_MX';
    if (l == 'español' || l == 'espanol' || l == 'castellano' || l == 'es') {
      return 'es_ES';
    }
    if (l.contains('sub') || l == 'english' || l == 'en') return 'en_US';
    return 'es_MX';
  }
}
