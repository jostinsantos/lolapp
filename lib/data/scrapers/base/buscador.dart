// lib/fuentes/apis/home/buscador.dart
// Solo parsers de búsqueda por sitio. La API pública search() está en registry.dart
import 'dart:convert';
import 'base_home_scraper.dart';
class BuscadorItem {
  final String sitio;
  final String titulo;
  final String tipo; // movie | tv | anime
  final String url;
  final String imagen;
  final int? anio;
  final double? rating;
  final int? tmdbId;

  BuscadorItem({
    required this.sitio,
    required this.titulo,
    required this.tipo,
    required this.url,
    required this.imagen,
    this.anio,
    this.rating,
    this.tmdbId,
  });
}

class BuscadorResult {
  final bool ok;
  final String? error;
  final String query;
  final String tipo;
  final int total;
  final Map<String, List<BuscadorItem>> resultados; // sitio → items

  BuscadorResult({
    required this.ok,
    this.error,
    this.query = '',
    this.tipo = 'todas',
    this.total = 0,
    this.resultados = const {},
  });
}

class BuscadorScraper {
  // ────────────────────────────────────────────────
  // SeriesKao
  // ────────────────────────────────────────────────
  static Future<List<BuscadorItem>> searchSeriesKao(String q) async {
    final html = await fetchHtml(
      'https://serieskao.top/search?s=${Uri.encodeComponent(q)}',
    );
    if (html == null) return [];

    final items = <BuscadorItem>[];
    final arts = RegExp(
      r'<article class="card">([\s\S]*?)</article>',
    ).allMatches(html);

    for (final art in arts) {
      final block = art.group(1)!;
      String titulo = '';
      String tipo = '';
      String url = '';
      String imagen = '';
      int? anio;
      double? rating;

      final aM = RegExp(
        r'<a href="([^"]+)" class="card__link">',
      ).firstMatch(block);
      if (aM != null) {
        final href = aM.group(1)!;
        url = href.startsWith('http') ? href : 'https://serieskao.top$href';
        final t = RegExp(r'/(pelicula|serie|anime)/').firstMatch(href);
        if (t != null) tipo = t.group(1) == 'serie' ? 'tv' : t.group(1)!;
      }

      final img = RegExp(r'<img src="([^"]+)"').firstMatch(block);
      if (img != null) imagen = img.group(1)!;

      final titleM = RegExp(
        r'<h[12] class="card__title">([^<]+)</h[12]>',
      ).firstMatch(block);
      if (titleM != null) titulo = _norm(titleM.group(1)!);

      final rat = RegExp(
        r'card__rating">.*?</svg>\s*([\d.]+)',
        dotAll: true,
      ).firstMatch(block);
      if (rat != null) rating = double.tryParse(rat.group(1)!);

      final y = RegExp(r'card__badge--year">(\d{4})<').firstMatch(block);
      if (y != null) anio = int.tryParse(y.group(1)!);

      if (titulo.isNotEmpty) {
        items.add(
          BuscadorItem(
            sitio: 'serieskao',
            titulo: titulo,
            tipo: tipo,
            url: url,
            imagen: imagen,
            anio: anio,
            rating: rating,
          ),
        );
      }
    }
    return items;
  }

  // ────────────────────────────────────────────────
  // Cuevana
  // ────────────────────────────────────────────────
  static Future<List<BuscadorItem>> searchCuevana(String q) async {
    final html = await fetchHtml(
      'https://wv3.cuevana3.eu/search?q=${Uri.encodeComponent(q)}',
    );
    if (html == null) return [];

    final m = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);
    if (m == null) return [];

    Map<String, dynamic>? next;
    try {
      next = jsonDecode(m.group(1)!) as Map<String, dynamic>;
    } catch (_) {
      return [];
    }

    final movies = next['props']?['pageProps']?['movies'] as List? ?? [];
    final items = <BuscadorItem>[];

    for (final mv in movies) {
      if (mv is! Map) continue;
      final slug = mv['url']?['slug']?.toString() ?? '';
      final esTv = slug.startsWith('series/');
      final tmdbId = mv['TMDbId'];

      items.add(
        BuscadorItem(
          sitio: 'cuevana',
          titulo: _norm(mv['titles']?['name']?.toString() ?? ''),
          tipo: esTv ? 'tv' : 'movie',
          url:
              'https://wv3.cuevana3.eu/${esTv ? 'ver-serie' : 'ver-pelicula'}/${mv['slug']?['name'] ?? ''}',
          imagen: mv['images']?['poster']?.toString() ?? '',
          rating: (mv['rate']?['average'] as num?)?.toDouble(),
          tmdbId: tmdbId is num ? tmdbId.toInt() : int.tryParse('$tmdbId'),
        ),
      );
    }
    return items;
  }

  // ────────────────────────────────────────────────
  // TioPlus
  // ────────────────────────────────────────────────
  static Future<List<BuscadorItem>> searchTioPlus(String q) async {
    final html = await fetchHtml(
      'https://tioplus.app/search/${Uri.encodeComponent(q)}',
    );
    if (html == null) return [];

    final items = <BuscadorItem>[];
    final arts = RegExp(
      r"<article class='item[^']*'>([\s\S]*?)</article>",
    ).allMatches(html);

    for (final art in arts) {
      final block = art.group(1)!;
      String titulo = '';
      String tipo = '';
      String url = '';
      String imagen = '';
      int? anio;

      final aM = RegExp(
        r'''<a class='itemA' href="([^"]+)"''',
      ).firstMatch(block);
      if (aM != null) {
        url = aM.group(1)!;
        final t = RegExp(r'/(pelicula|serie|anime)/').firstMatch(url);
        if (t != null) tipo = t.group(1) == 'serie' ? 'tv' : t.group(1)!;
      }

      final h2 = RegExp(r'<h2>([^<]+)</h2>').firstMatch(block);
      if (h2 != null) {
        final raw = _norm(h2.group(1)!);
        final y = RegExp(r'^(.+?)\s*\((\d{4})\)\s*$').firstMatch(raw);
        if (y != null) {
          titulo = y.group(1)!.trim();
          anio = int.tryParse(y.group(2)!);
        } else {
          titulo = raw;
        }
      }

      final src = RegExp(r"data-src='([^']+)'").firstMatch(block);
      if (src != null) imagen = src.group(1)!;

      final span = RegExp(
        r'<span class="typeItem[^"]*">([^<]+)</span>',
      ).firstMatch(block);
      if (span != null) {
        final t = span.group(1)!.toLowerCase();
        if (t.contains('anime')) {
          tipo = 'anime';
        } else if (t.contains('serie')) {
          tipo = 'tv';
        } else if (t.contains('pel')) {
          tipo = 'movie';
        }
      }

      if (titulo.isNotEmpty) {
        items.add(
          BuscadorItem(
            sitio: 'tioplus',
            titulo: titulo,
            tipo: tipo,
            url: url,
            imagen: imagen,
            anio: anio,
          ),
        );
      }
    }
    return items;
  }

  // ────────────────────────────────────────────────
  // CineHax
  // ────────────────────────────────────────────────
  static Future<List<BuscadorItem>> searchCineHax(String q) async {
    final html = await fetchHtml(
      'https://cinehax.com/buscar/?q=${Uri.encodeComponent(q)}',
    );
    if (html == null) return [];

    final items = <BuscadorItem>[];
    final arts = RegExp(
      r'<a href="(/ver/\?tipo=(pelicula|serie)[^"]+)">([\s\S]*?)</a>',
    ).allMatches(html);

    for (final art in arts) {
      final href = art.group(1)!;
      final tipoRaw = art.group(2)!;
      final bloque = art.group(3)!;

      final tipo = tipoRaw == 'serie' ? 'tv' : 'movie';
      final url = 'https://cinehax.com$href';
      int? tmdbId;
      final idM = RegExp(r'id=(\d+)').firstMatch(href);
      if (idM != null) tmdbId = int.tryParse(idM.group(1)!);

      String imagen = '';
      final imgM = RegExp(
        r'''https://image\.tmdb\.org/t/p/[^"']+''',
      ).firstMatch(bloque);
      if (imgM != null) imagen = imgM.group(0)!;
      String titulo = '';
      final h3 = RegExp(r'<h3[^>]*>([^<]+)</h3>').firstMatch(bloque);
      if (h3 != null) {
        titulo = _norm(h3.group(1)!);
      } else {
        final alt = RegExp(r'alt="([^"]+)"').firstMatch(bloque);
        if (alt != null) titulo = _norm(alt.group(1)!);
      }

      double? rating;
      final rat = RegExp(r'text-yellow-500">([\d.]+)<').firstMatch(bloque);
      if (rat != null) rating = double.tryParse(rat.group(1)!);

      if (titulo.isNotEmpty) {
        items.add(
          BuscadorItem(
            sitio: 'cinehax',
            titulo: titulo,
            tipo: tipo,
            url: url,
            imagen: imagen,
            rating: rating,
            tmdbId: tmdbId,
          ),
        );
      }
    }
    return items;
  }

  // ────────────────────────────────────────────────
  // PelisPlus
  // ────────────────────────────────────────────────
  static Future<List<BuscadorItem>> searchPelisPlus(String q) async {
    final html = await fetchHtml(
      'https://www.pelisplushd.la/search?s=${Uri.encodeComponent(q)}',
    );
    if (html == null) return [];

    final items = <BuscadorItem>[];
    final arts = RegExp(
      r'<a href="([^"]+)" class="Posters-link"[\s\S]*?</a>',
    ).allMatches(html);

    for (final art in arts) {
      final href = art.group(1)!;
      final bloque = art.group(0)!;

      final url = href.startsWith('http')
          ? href
          : 'https://www.pelisplushd.la$href';
      String tipo = '';
      final t = RegExp(r'/(pelicula|serie|anime)/').firstMatch(href);
      if (t != null) tipo = t.group(1) == 'serie' ? 'tv' : t.group(1)!;

      final badge = RegExp(
        r'<div class="(movies|series|animes) centrado">\s*([^<]+)\s*</div>',
      ).firstMatch(bloque);
      if (badge != null) {
        final txt = badge.group(2)!.toLowerCase();
        if (txt.contains('anime')) {
          tipo = 'anime';
        } else if (txt.contains('serie')) {
          tipo = 'tv';
        } else if (txt.contains('pel')) {
          tipo = 'movie';
        }
      }

      String titulo = '';
      final p = RegExp(r'<p>([^<]+)</p>').firstMatch(bloque);
      if (p != null) titulo = _norm(p.group(1)!);

      String imagen = '';
      final img = RegExp(r'<img[^>]+src="(/poster/[^"]+)"').firstMatch(bloque);
      if (img != null) imagen = 'https://www.pelisplushd.la${img.group(1)!}';

      double? rating;
      final rat = RegExp(r'<span>([\d.]+)/10</span>').firstMatch(bloque);
      if (rat != null) rating = double.tryParse(rat.group(1)!);

      if (titulo.isNotEmpty) {
        items.add(
          BuscadorItem(
            sitio: 'pelisplus',
            titulo: titulo,
            tipo: tipo,
            url: url,
            imagen: imagen,
            rating: rating,
          ),
        );
      }
    }
    return items;
  }

  // ────────────────────────────────────────────────
  // AnimeJK (jkanime.net)
  // ────────────────────────────────────────────────
  static Future<List<BuscadorItem>> searchAnimeJk(String q) async {
    final encoded = Uri.encodeComponent(q.trim());
    final html = await fetchHtml('https://jkanime.net/buscar/$encoded');
    if (html == null) return [];

    final items = <BuscadorItem>[];
    // div.anime__item blocks
    final arts = RegExp(
      r'<div class="anime__item"[^>]*>([\s\S]*?)</div>\s*</div>\s*</div>',
    ).allMatches(html);

    // Fallback más amplio si el patrón estricto no encuentra nada
    final Iterable<RegExpMatch> matches = arts.isEmpty
        ? RegExp(
            r'class="anime__item"[^>]*>([\s\S]*?)(?=class="anime__item"|class="page_|$)',
          ).allMatches(html)
        : arts;

    for (final art in matches) {
      final block = art.group(1) ?? art.group(0)!;

      String titulo = '';
      String url = '';
      String imagen = '';
      String tipo = 'anime';

      // Título + link: <h5><a href="...">Title</a></h5>
      final linkM = RegExp(
        r'<h5[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>',
      ).firstMatch(block);
      if (linkM != null) {
        url = linkM.group(1)!;
        titulo = _norm(linkM.group(2)!);
      } else {
        final aM = RegExp(
          r'<a[^>]+href="(https?://jkanime\.net/[^"]+|/[a-z0-9\-]+/?)"[^>]*>([^<]+)</a>',
        ).firstMatch(block);
        if (aM != null) {
          url = aM.group(1)!;
          titulo = _norm(aM.group(2)!);
        }
      }

      if (url.isNotEmpty && !url.startsWith('http')) {
        url = url.startsWith('/')
            ? 'https://jkanime.net$url'
            : 'https://jkanime.net/$url';
      }

      // Imagen: data-setbg o style background
      final bgM = RegExp(r'data-setbg="([^"]+)"').firstMatch(block);
      if (bgM != null) {
        imagen = bgM.group(1)!;
      } else {
        final styleM = RegExp(
          r'''url\(["']?([^"')]+)["']?\)''',
        ).firstMatch(block);
        if (styleM != null) imagen = styleM.group(1)!;
      }

      // Tipo desde lis o texto
      final typeM = RegExp(
        r'<li[^>]*>\s*(Anime|Pel[ií]cula|OVA|ONA|Especial)[^<]*</li>',
        caseSensitive: false,
      ).firstMatch(block);
      if (typeM != null) {
        final t = typeM.group(1)!.toLowerCase();
        if (t.contains('pel')) {
          tipo = 'movie';
        } else if (t.contains('ova')) {
          tipo = 'ova';
        } else if (t.contains('ona')) {
          tipo = 'ona';
        } else if (t.contains('esp')) {
          tipo = 'especial';
        } else {
          tipo = 'anime';
        }
      }

      if (titulo.isNotEmpty && url.isNotEmpty) {
        items.add(
          BuscadorItem(
            sitio: 'animejk',
            titulo: titulo,
            tipo: tipo,
            url: url,
            imagen: imagen,
          ),
        );
      }
    }
    return items;
  }

  static String _norm(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}