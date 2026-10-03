// lib/fuentes/apis/home/serieskao.dart
import '../base/base_home_scraper.dart';
class SeriesKaoScraper {
  static const String base = 'https://serieskao.top';

  static const List<String> generos = [
    'accion', 'animacion', 'aventura', 'belica', 'ciencia-ficcion',
    'comedia', 'crimen', 'documental', 'drama', 'fantasia',
    'familia', 'guerra', 'historia', 'romance', 'suspense',
    'terror', 'western', 'misterio'
  ];

  static List<String> tiposDisponibles() => ['movie', 'tv', 'anime', 'dorama'];

  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    String path = '';

    if (genero != null && genero.isNotEmpty) {
      if (!generos.contains(genero)) {
        return ScraperResult(ok: false, error: 'Género no válido: $genero');
      }
      path = '/generos/$genero';
    } else {
      switch (tipo) {
        case 'movie':
        case 'pelicula':
          path = populares ? '/peliculas/populares' : '/peliculas';
          break;
        case 'tv':
        case 'serie':
        case 'series':
          path = populares ? '/series/populares' : '/series';
          break;
        case 'anime':
        case 'animes':
          path = populares ? '/animes/populares' : '/animes';
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
    }

    // Construir URL con paginación correcta.
    // El sitio acepta ?page=N incluso si la URL ya tiene query.
    var url = '$base$path';
    if (page > 1) {
      url += (url.contains('?') ? '&' : '?') + 'page=$page';
    }

    final html = await fetchHtml(url);
    if (html == null) {
      return ScraperResult(
        ok: false,
        error: 'No se pudo cargar la página',
        url: url,
      );
    }

    final items = _parseItems(html);
    final pagination = _parsePagination(html);

    String section = '';
    final h1 = RegExp(r'<h1 class="section__title">([^<]+)</h1>').firstMatch(html);
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

  static List<ScraperItem> _parseItems(String html) {
    final items = <ScraperItem>[];
    final arts = RegExp(r'<article class="card">(.*?)</article>', dotAll: true)
        .allMatches(html);

    for (final art in arts) {
      final block = art.group(1)!;
      String titulo = '';
      String tipo = '';
      String url = '';
      String poster = '';
      double? rating;
      int? year;

      final urlM =
          RegExp(r'<a href="([^"]+)" class="card__link">').firstMatch(block);
      if (urlM != null) {
        final href = urlM.group(1)!;
        url = href.startsWith('http') ? href : '$base$href';
        final t = RegExp(r'/(pelicula|serie|anime)/').firstMatch(href);
        if (t != null) tipo = t.group(1)!;
      }

      final img = RegExp(r'<img src="([^"]+)"').firstMatch(block);
      if (img != null) poster = img.group(1)!;

      final titleM =
          RegExp(r'<h[12] class="card__title">([^<]+)</h[12]>').firstMatch(block);
      if (titleM != null) titulo = _decode(titleM.group(1)!.trim());

      final rat = RegExp(r'card__rating">.*?</svg>\s*([\d.]+)', dotAll: true)
          .firstMatch(block);
      if (rat != null) rating = double.tryParse(rat.group(1)!);

      final y = RegExp(r'card__badge--year">(\d{4})<').firstMatch(block);
      if (y != null) year = int.tryParse(y.group(1)!);

      if (titulo.isNotEmpty) {
        items.add(ScraperItem(
          titulo: titulo,
          tipo: tipo,
          url: url,
          poster: poster,
          rating: rating,
          year: year,
        ));
      }
    }
    return items;
  }

  /// Parsea la paginación. El sitio usa:
  ///   <span class="pagination__info">Página 3 de 659</span>
  /// y también enlaces con `?page=N`.
  ///
  /// Es tolerante a problemas de encoding (PÃ¡gina) y a la ausencia de tilde.
  static Map<String, dynamic> _parsePagination(String html) {
    int current = 1;
    int total = 1;

    // Formato principal: "Página X de Y" dentro de .pagination__info
    // Se acepta cualquier letra entre "P" y "gina" para sobrevivir a encoding roto.
    final info = RegExp(
      r'pagination__info[^>]*>\s*P[^0-9]{0,4}gina\s+(\d+)\s+de\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(html);

    if (info != null) {
      current = int.parse(info.group(1)!);
      total = int.parse(info.group(2)!);
    } else {
      // Fallback 1: botón activo de la paginación
      final active =
          RegExp(r'pagination__btn--active[^>]*>\s*(\d+)\s*<').firstMatch(html);
      if (active != null) current = int.parse(active.group(1)!);

      // Fallback 2: mayor número de ?page=N en los enlaces
      final nums = RegExp(r'[?&]page=(\d+)')
          .allMatches(html)
          .map((m) => int.tryParse(m.group(1)!) ?? 0)
          .where((n) => n > 0)
          .toList();
      if (nums.isNotEmpty) {
        total = nums.reduce((a, b) => a > b ? a : b);
      }

      // Fallback 3: si existe un enlace "Siguiente", forzamos has_next
      final hasNextLink = RegExp(
        r'aria-label="Siguiente"[^>]*href="[^"]+"',
      ).hasMatch(html);
      if (hasNextLink && total <= current) {
        total = current + 1;
      }
    }

    return {
      'current': current,
      'total': total,
      'has_next': current < total,
      'has_prev': current > 1,
    };
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}