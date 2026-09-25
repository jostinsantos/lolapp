// lib/mobil/servicios/fuentes/apis/contenido/base_scraper.dart
import 'package:http/http.dart' as http;
import 'dart:io';

class ScraperItem {
  final String titulo;
  final String tipo;
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
  print('→ fetchHtml INICIO: $url');

  try {
    final client = HttpClient();
    client.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
    client.connectionTimeout = timeout;
    client.badCertificateCallback = (cert, host, port) => true; // por si hay SSL raro

    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    request.headers.set(HttpHeaders.acceptLanguageHeader, 'es-ES,es;q=0.9,en;q=0.8');
    request.followRedirects = true;
    request.maxRedirects = 5;

    final response = await request.close().timeout(timeout);
    print('← status: ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 400) {
      print('✗ HTTP ${response.statusCode}');
      client.close();
      return null;
    }

    final body = await response.transform(const SystemEncoding().decoder).join();
    print('← body length: ${body.length}');
    client.close();

    if (body.isEmpty) {
      print('✗ body vacío');
      return null;
    }

    return body;
  } catch (e, st) {
    print('✗ fetchHtml ERROR: $e');
    print(st);
    return null;
  }
}