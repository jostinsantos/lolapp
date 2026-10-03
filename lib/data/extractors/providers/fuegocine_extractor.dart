import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class FuegoCineService {
  static const String _apiUrl = 'https://www.modlyo.com/api/servidores.php';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  static Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) async* {
    try {
      final uri = Uri.parse(_apiUrl).replace(queryParameters: {
        'tmdbId': tmdbId.toString(),
        'type': isMovie ? 'movie' : 'tv',
        if (!isMovie) 'season': season.toString(),
        if (!isMovie) 'episode': episode.toString(),
      });

      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] != true) return;

      final streams = data['streams'];
      if (streams is! List || streams.isEmpty) return;

      for (final s in streams) {
        if (s is! Map) continue;
        final url = s['servidor_url']?.toString() ?? '';
        if (url.isEmpty) continue;

        yield {
          'servidor_url': url,
          'servidor_nombre': s['servidor_nombre']?.toString() ?? 'Modlyo',
          'calidad': s['calidad']?.toString() ?? 'HD',
          'idioma': _normalizeIdioma(s['idioma']?.toString()),
          'es_fuegocine': true,
        };
      }
    } catch (_) {}
  }

  static String _normalizeIdioma(String? lang) {
    if (lang == null || lang.isEmpty) return 'es_MX';
    final l = lang.toLowerCase().trim();
    if (l.contains('es_es') || l.contains('es-es') || l.contains('esp') || l.contains('castellano')) {
      return 'es_ES';
    }
    if (l.contains('sub') || l.startsWith('en')) {
      return 'en';
    }
    return 'es_MX';
  }
}