// lib/fuentes/apis/home/tioplus.dart
import '../base/base_home_scraper.dart';
class TioPlusScraper {
  static const String base = 'https://tioplus.app';

  static List<String> tiposDisponibles() => ['movie', 'tv', 'anime', 'dorama'];

  static Future<ScraperResult> fetch({
    required String tipo,
    String? genero,
    String? year,
    int page = 1,
  }) async {
    String basePath;
    switch (tipo) {
      case 'movie':
      case 'pelicula':
      case 'peliculas':
        basePath = '/peliculas';
        break;
      case 'tv':
      case 'serie':
      case 'series':
        basePath = '/series';
        break;
      case 'anime':
      case 'animes':
        basePath = '/animes';
        break;
      case 'dorama':
      case 'doramas':
        basePath = '/doramas';
        break;
      default:
        return ScraperResult(ok: false, error: 'tipo debe ser movie|tv|anime|dorama');
    }

    String path;
    if ((genero != null && genero.isNotEmpty) || (year != null && year.isNotEmpty)) {
      final yearSeg = year?.isNotEmpty == true ? year! : 'null';
      final genSeg = genero?.isNotEmpty == true ? genero! : 'null';
      path = '$basePath/filter/$yearSeg/$genSeg/$page';
    } else {
      path = basePath;
      if (page > 1) path += '/$page';
    }

    final url = '$base$path';
    final html = await fetchHtml(url);
    if (html == null) {
      return ScraperResult(ok: false, error: 'No se pudo cargar la página', url: url);
    }

    final items = _parseItems(html);
    final pagination = _parsePagination(html, page);

    String section = '';
    final h1 = RegExp(r'<div class="options-filters">\s*<h1>([^<]+)</h1>').firstMatch(html);
    if (h1 != null) section = _decode(h1.group(1)!);

    return ScraperResult(
      ok: true,
      section: section,
      url: url,
      currentPage: pagination['current'] as int,
      totalPages: pagination['total'] as int,
      hasNext: pagination['has_next'] as bool,
      items: items,
    );
  }

  static Future<Map<String, dynamic>> fetchFiltros(String tipo) async {
    String path;
    switch (tipo) {
      case 'movie':
      case 'pelicula':
      case 'peliculas':
        path = '/peliculas';
        break;
      case 'tv':
      case 'serie':
      case 'series':
        path = '/series';
        break;
      case 'anime':
      case 'animes':
        path = '/animes';
        break;
      case 'dorama':
      case 'doramas':
        path = '/doramas';
        break;
      default:
        return {'ok': false, 'error': 'filtros debe ser movie|tv|anime|dorama'};
    }

    final html = await fetchHtml('$base$path');
    if (html == null) return {'ok': false, 'error': 'No se pudo cargar filtros'};

    final generos = <Map<String, String>>[];
    final years = <int>[];

    final catSelect = RegExp(r'<select name="categoria"[\s\S]*?</select>').firstMatch(html);
    if (catSelect != null) {
      final opts = RegExp(r'<option value="([^"]+)"[^>]*>\s*([^<]+)</option>').allMatches(catSelect.group(0)!);
      for (final o in opts) {
        if (o.group(1) == 'null') continue;
        generos.add({
          'slug': o.group(1)!,
          'nombre': _decode(o.group(2)!.trim()),
        });
      }
    }

    final yearSelect = RegExp(r'<select name="year"[\s\S]*?</select>').firstMatch(html);
    if (yearSelect != null) {
      final opts = RegExp(r'<option value="([^"]+)"[^>]*>\s*([^<]+)</option>').allMatches(yearSelect.group(0)!);
      for (final o in opts) {
        if (o.group(1) == 'null') continue;
        final y = int.tryParse(o.group(1)!);
        if (y != null) years.add(y);
      }
    }

    return {
      'ok': true,
      'tipo': tipo,
      'generos': generos,
      'years': years,
    };
  }

  static List<ScraperItem> _parseItems(String html) {
    final items = <ScraperItem>[];
    final arts = RegExp(r"<article class='item[^']*'>([\s\S]*?)</article>").allMatches(html);

    for (final art in arts) {
      final block = art.group(1)!;
      String titulo = '';
      int? anio;
      String tipo = '';
      String url = '';
      String poster = '';

      final aM = RegExp(r'''<a class='itemA' href="([^"]+)"''').firstMatch(block);
      if (aM != null) {
        url = aM.group(1)!;
        final t = RegExp(r'/(pelicula|serie|anime)/').firstMatch(url);
        if (t != null) {
          tipo = t.group(1) == 'serie' ? 'tv' : t.group(1)!;
        }
      }

      final h2 = RegExp(r'<h2>([^<]+)</h2>').firstMatch(block);
      if (h2 != null) {
        final raw = _decode(h2.group(1)!.trim());
        final m = RegExp(r'^(.+?)\s*\((\d{4})\)\s*$').firstMatch(raw);
        if (m != null) {
          titulo = m.group(1)!.trim();
          anio = int.tryParse(m.group(2)!);
        } else {
          titulo = raw;
        }
      }

      final src = RegExp(r"data-src='([^']+)'").firstMatch(block);
      if (src != null) poster = src.group(1)!;

      final span = RegExp(r'<span class="typeItem[^"]*">([^<]+)</span>').firstMatch(block);
      if (span != null) {
        final decl = span.group(1)!.toLowerCase().trim();
        if (decl.contains('anime')) tipo = 'anime';
        else if (decl.contains('serie')) tipo = 'tv';
        else if (decl.contains('pel')) tipo = 'movie';
      }

      if (titulo.isNotEmpty) {
        items.add(ScraperItem(
          titulo: titulo,
          tipo: tipo,
          url: url,
          poster: poster,
          year: anio,
        ));
      }
    }
    return items;
  }

  static Map<String, dynamic> _parsePagination(String html, int page) {
    int total = 0;
    final m = RegExp(
      r'Showing\s*<span[^>]*>\d+</span>\s*to\s*<span[^>]*>\d+</span>\s*of\s*<span[^>]*>(\d+)</span>',
    ).firstMatch(html);
    if (m != null) total = int.tryParse(m.group(1)!) ?? 0;

    const porPagina = 24;
    final totalPaginas = total > 0 ? (total / porPagina).ceil() : 1;

    return {
      'current': page,
      'total': totalPaginas,
      'results': total,
      'has_next': page < totalPaginas,
      'has_prev': page > 1,
    };
  }

  static String _decode(String s) =>
      s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#039;', "'");
}