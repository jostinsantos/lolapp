// lib/fuentes/apis/home/pelisplus.dart
import '../base/base_home_scraper.dart';
class PelisPlusScraper {
  static const String base = 'https://www.pelisplushd.la';

  static const List<String> generos = [
    'accion', 'animacion', 'aventura', 'belica', 'ciencia-ficcion',
    'comedia', 'crimen', 'documental', 'dorama', 'drama', 'familia',
    'fantasia', 'foreign', 'guerra', 'historia', 'pelicula-de-la-television',
    'romance', 'suspense', 'terror', 'western', 'misterio'
  ];

  static const Map<String, String> subPorTipo = {
    'movie': 'peliculas',
    'pelicula': 'peliculas',
    'peliculas': 'peliculas',
    'tv': 'series',
    'serie': 'series',
    'series': 'series',
    'anime': 'animes',
    'animes': 'animes',
  };

  static List<String> tiposDisponibles() => ['movie', 'tv', 'anime', 'dorama'];

  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    String? sub,
    int page = 1,
  }) async {
    String path = '';

    if (genero == null || genero.isEmpty) {
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
          path = '/generos/dorama';
          break;
        default:
          return ScraperResult(
            ok: false,
            error: 'Parámetro requerido: tipo=(movie|tv|anime|dorama) o genero=...',
          );
      }
      if (page > 1) path += '?page=$page';
    } else {
      if (!generos.contains(genero)) {
        return ScraperResult(ok: false, error: 'Género no válido: $genero');
      }

      String subFinal = '';
      if (sub != null && sub.isNotEmpty) {
        if (!['peliculas', 'series', 'animes'].contains(sub)) {
          return ScraperResult(ok: false, error: 'sub debe ser peliculas|series|animes');
        }
        subFinal = sub;
      } else if (tipo != null && subPorTipo.containsKey(tipo)) {
        subFinal = subPorTipo[tipo]!;
      }

      if (subFinal.isNotEmpty) {
        path = '/generos/$genero/$subFinal';
      } else {
        path = '/generos/$genero';
      }
      path += '?page=$page';
    }

    final url = '$base$path';
    final html = await fetchHtml(url);
    if (html == null) {
      return ScraperResult(ok: false, error: 'No se pudo cargar la página', url: url);
    }

    final items = _parseItems(html);
    final pagination = _parsePagination(html, page);

    String section = '';
    final h2 = RegExp(r'<h2 class="card-title title_seo[^"]*">([^<]+)</h2>').firstMatch(html);
    if (h2 != null) section = _decode(h2.group(1)!);

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

  static List<ScraperItem> _parseItems(String html) {
    final items = <ScraperItem>[];
    final arts = RegExp(r'<a href="([^"]+)" class="Posters-link"[\s\S]*?</a>').allMatches(html);

    for (final art in arts) {
      final bloque = art.group(0)!;
      final href = art.group(1)!;

      String titulo = '';
      String tipo = '';
      String poster = '';
      double? rating;

      final url = href.startsWith('http') ? href : '$base$href';

      final t = RegExp(r'/(pelicula|serie|anime)/').firstMatch(href);
      if (t != null) {
        tipo = t.group(1) == 'serie' ? 'tv' : t.group(1)!;
      }

      final titleM = RegExp(r'<div class="listing-content">\s*<p>([^<]+)</p>').firstMatch(bloque);
      if (titleM != null) titulo = _decode(titleM.group(1)!.trim());

      final img = RegExp(r'<img[^>]+src="(/poster/[^"]+)"').firstMatch(bloque);
      if (img != null) {
        poster = img.group(1)!.startsWith('http') ? img.group(1)! : '$base${img.group(1)!}';
      }

      final rat = RegExp(r'<span>([\d.]+)/10</span>').firstMatch(bloque);
      if (rat != null) rating = double.tryParse(rat.group(1)!);

      if (titulo.isNotEmpty) {
        items.add(ScraperItem(
          titulo: titulo,
          tipo: tipo,
          url: url,
          poster: poster,
          rating: rating,
        ));
      }
    }
    return items;
  }

  static Map<String, dynamic> _parsePagination(String html, int page) {
    int totalPaginas = 1;
    final matches = RegExp(r'[?&]page=(\d+)').allMatches(html);
    for (final m in matches) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > totalPaginas) totalPaginas = n;
    }
    return {
      'current': page,
      'total': totalPaginas,
      'has_next': page < totalPaginas,
      'has_prev': page > 1,
    };
  }

  static String _decode(String s) =>
      s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#039;', "'");
}