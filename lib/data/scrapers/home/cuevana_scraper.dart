// lib/fuentes/apis/home/cuevana.dart
import 'dart:convert';
import '../base/base_home_scraper.dart';
class CuevanaScraper {
  static const String base = 'https://wv3.cuevana3.eu';

  static const List<String> generos = [
    'accion', 'aventura', 'animacion', 'ciencia-ficcion', 'crimen',
    'drama', 'familia', 'fantasia', 'misterio', 'romance', 'suspense', 'terror'
  ];

  static List<String> tiposDisponibles() => ['movie', 'tv', 'tendencias', 'episodios'];

  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    int page = 1,
  }) async {
    String path = '';
    String mode = 'movies';

    if (genero != null && genero.isNotEmpty) {
      if (!generos.contains(genero)) {
        return ScraperResult(ok: false, error: 'Género no válido: $genero');
      }
      path = '/genero/$genero';
      mode = 'movies';
    } else {
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
        case 'tendencias':
        case 'series-populares':
        case 'tv-tendencias':
          path = '/series/tendencias/dia';
          break;
        case 'episodios':
        case 'capitulos':
          path = '/episodios';
          mode = 'episodes';
          break;
        default:
          return ScraperResult(
            ok: false,
            error: 'Parámetro requerido: tipo=(movie|tv|tendencias|episodios) o genero=...',
          );
      }
    }

    // Cuevana usa /page/N en la ruta (NO ?page=N).
    // ?page=N es ignorado y siempre devuelve la página 1 → bucle infinito.
    var url = '$base$path';
    if (page > 1) {
      url = '$base$path/page/$page';
    }

    final html = await fetchHtml(url);
    if (html == null) {
      return ScraperResult(ok: false, error: 'No se pudo cargar la página', url: url);
    }

    final nextData = _getNextData(html);
    if (nextData == null) {
      return ScraperResult(ok: false, error: 'No se encontró __NEXT_DATA__', url: url);
    }

    final pp = nextData['props']?['pageProps'] as Map<String, dynamic>? ?? {};

    int total = 1;
    int current = page; // el sitio a veces no expone page en pageProps

    void _readInt(dynamic v, void Function(int) set) {
      if (v is num) {
        set(v.toInt());
      } else if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) set(parsed);
      }
    }

    _readInt(pp['pages'], (v) => total = v);
    _readInt(pp['totalPages'], (v) => total = v);
    _readInt(pp['total_pages'], (v) => total = v);

    // En /genero/... sí viene "page"; en /peliculas y /series a menudo no.
    _readInt(pp['page'], (v) => current = v);
    _readInt(pp['currentPage'], (v) => current = v);
    _readInt(pp['current_page'], (v) => current = v);

    final items = <ScraperItem>[];

    if (mode == 'episodes' && pp['episodes'] is List) {
      for (final ep in (pp['episodes'] as List)) {
        if (ep is! Map) continue;
        final slug = ep['slug']?['name']?.toString() ?? '';
        final s = ep['slug']?['season']?.toString() ?? '';
        final e = ep['slug']?['episode']?.toString() ?? '';
        items.add(ScraperItem(
          titulo: ep['title']?.toString() ?? '',
          tipo: 'episode',
          url: '$base/episodio/$slug-temporada-$s-episodio-$e',
          poster: ep['image']?.toString() ?? '',
          tmdbId: (ep['TMDbId'] as num?)?.toInt(),
          year: int.tryParse((ep['releaseDate']?.toString() ?? '').substring(0, 4)),
        ));
      }
    } else if (pp['movies'] is List) {
      for (final m in (pp['movies'] as List)) {
        if (m is! Map) continue;
        final tmdbId = m['TMDbId'];
        final slug = m['slug']?['name']?.toString() ?? '';
        bool esTv = false;
        if (m['url']?['slug'] != null &&
            m['url']['slug'].toString().startsWith('series/')) {
          esTv = true;
        }

        final generosList = <String>[];
        if (m['genres'] is List) {
          for (final g in m['genres']) {
            if (g is Map && g['name'] != null) {
              generosList.add(g['name'].toString());
            }
          }
        }

        items.add(ScraperItem(
          titulo: m['titles']?['name']?.toString() ?? '',
          tipo: esTv ? 'tv' : 'movie',
          url: '$base/${esTv ? 'ver-serie' : 'ver-pelicula'}/$slug',
          poster: m['images']?['poster']?.toString() ?? '',
          rating: (m['rate']?['average'] as num?)?.toDouble(),
          year: int.tryParse((m['releaseDate']?.toString() ?? '').substring(0, 4)),
          tmdbId: tmdbId is num ? tmdbId.toInt() : int.tryParse('$tmdbId'),
          sinopsis: m['overview']?.toString(),
          generos: generosList,
        ));
      }
    }

    // Lista vacía = no hay más páginas, aunque pages diga otra cosa.
    final hasNext = items.isNotEmpty && current < total;

    return ScraperResult(
      ok: true,
      section: path,
      url: url,
      currentPage: current,
      totalPages: total,
      hasNext: hasNext,
      items: items,
    );
  }

  static Map<String, dynamic>? _getNextData(String html) {
    final m = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true)
        .firstMatch(html);
    if (m == null) return null;
    try {
      return jsonDecode(m.group(1)!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}