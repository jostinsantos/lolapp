// lib/fuentes/apis/home/base_scraper.dart
import 'package:http/http.dart' as http;

class ScraperItem {
  final String titulo;
  final String tipo;       // movie | tv | anime | dorama | episode
  final String url;
  final String poster;
  final double? rating;
  final int? year;
  final int? tmdbId;
  final String? sinopsis;
  final List<String> generos;

  ScraperItem({
    required this.titulo,
    required this.tipo,
    required this.url,
    required this.poster,
    this.rating,
    this.year,
    this.tmdbId,
    this.sinopsis,
    this.generos = const [],
  });

  Map<String, dynamic> toMap() => {
        'titulo': titulo,
        'tipo': tipo,
        'url': url,
        'poster': poster,
        'rating': rating,
        'year': year,
        'tmdb_id': tmdbId,
        'sinopsis': sinopsis,
        'generos': generos,
      };
}

class ScraperResult {
  final bool ok;
  final String? error;
  final String section;
  final String url;
  final int currentPage;
  final int totalPages;
  final bool hasNext;
  final List<ScraperItem> items;

  ScraperResult({
    required this.ok,
    this.error,
    this.section = '',
    this.url = '',
    this.currentPage = 1,
    this.totalPages = 1,
    this.hasNext = false,
    this.items = const [],
  });
}

Future<String?> fetchHtml(String url, {Duration timeout = const Duration(seconds: 25)}) async {
  try {
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
        'Accept-Language': 'es-MX,es;q=0.9',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    ).timeout(timeout);

    if (res.statusCode >= 200 && res.statusCode < 400) {
      return res.body;
    }
  } catch (_) {}
  return null;
}