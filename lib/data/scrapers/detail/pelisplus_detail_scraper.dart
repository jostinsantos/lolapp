import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../models/scraper/detalle_model.dart';
class DetallePelisPlus {
  static const _tmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const _base = 'https://www.pelisplushd.la';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static Future<String?> _fetch(String url) async {
    try {
      final res = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': _ua,
              'Accept-Language': 'es-MX,es;q=0.9,en;q=0.8',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Referer': _base,
            },
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      return res.body;
    } catch (_) {
      return null;
    }
  }

  static String _d(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Future<DetalleContenido> fetch({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    var pageUrl = url.trim();
    if (pageUrl.isEmpty) {
      return DetalleContenido(
        ok: false,
        error: 'URL vacía (PelisPlus)',
        servicio: 'pelisplus',
        titulo: titulo,
        tipo: tipo,
      );
    }
    if (!pageUrl.startsWith('http')) {
      pageUrl = pageUrl.startsWith('/') ? '$_base$pageUrl' : '$_base/$pageUrl';
    }

    final html = await _fetch(pageUrl);
    if (html == null || html.isEmpty) {
      return DetalleContenido(
        ok: false,
        error: 'No se pudo cargar la página de PelisPlus\n$pageUrl',
        servicio: 'pelisplus',
        titulo: titulo,
        tipo: tipo,
      );
    }

    final isMovie = !pageUrl.contains('/serie/') &&
        !pageUrl.contains('/anime/') &&
        !RegExp(r'/temporada/\d+/capitulo/\d+').hasMatch(pageUrl);

    final endpoint = isMovie ? 'movie' : 'tv';

    String tituloFinal = titulo;
    String? anio;
    String? sinopsis;
    String? poster;
    String? backdrop;
    String? logo;
    String? imdbId;
    double? rating;
    int? tmdbId;
    final generos = <String>[];
    final servidores = <DetalleServidor>[];
    final temporadasMap = <int, List<DetalleCapitulo>>{};

    final h1 = RegExp(r'<h1[^>]*>\s*([^<]+?)\s*</h1>').firstMatch(html);
    if (h1 != null) tituloFinal = _d(h1.group(1)!);

    final y1 = RegExp(
      r'<title>[^:]*:\s*[^(]+\((\d{4})\)',
      caseSensitive: false,
    ).firstMatch(html);
    if (y1 != null) {
      anio = y1.group(1);
    } else {
      final y2 =
          RegExp(r'Fecha de estreno:</span>\s*(\d{4})').firstMatch(html);
      if (y2 != null) anio = y2.group(1);
    }

    final sin = RegExp(
      r'<b>Sinopsis:</b>\s*</p>\s*<div class="text-large">(.*?)</div>',
      dotAll: true,
    ).firstMatch(html);
    if (sin != null) {
      sinopsis = _d(sin.group(1)!);
    } else {
      final meta = RegExp(
        r'<meta name="description" content="[^:]*:\s*([^"]+)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (meta != null) sinopsis = _d(meta.group(1)!);
    }

    final pos = RegExp(r'src="(/poster/[^"]+)"').firstMatch(html);
    if (pos != null) poster = '$_base${pos.group(1)!}';

    final rat = RegExp(
      r'text-info text-semibold ion-md-star">\s*([\d.]+)/10',
    ).firstMatch(html);
    if (rat != null) rating = double.tryParse(rat.group(1)!);

    for (final g in RegExp(
      r'href="/generos/[^"]+"[^>]*>([^<]+)</a>',
    ).allMatches(html)) {
      final name = _d(g.group(1)!);
      if (name.isNotEmpty && !generos.contains(name)) generos.add(name);
    }

    final seenSrv = <String>{};
    var i = 1;
    for (final m in RegExp(
      r'data-url="(https?://[^"]+)"\s+data-name="([^"]+)"',
    ).allMatches(html)) {
      final u = m.group(1)!;
      if (seenSrv.contains(u)) continue;
      seenSrv.add(u);
      servidores.add(DetalleServidor(
        nombre: 'Opción $i',
        url: u,
        idioma: m.group(2),
      ));
      i++;
    }

    if (!isMovie) {
      final blocks = RegExp(
        r'<div[^>]+id="pills-vertical-(\d+)"[^>]*>(.*?)</div>',
        dotAll: true,
      ).allMatches(html);

      for (final b in blocks) {
        final tNum = int.tryParse(b.group(1)!) ?? 0;
        if (tNum <= 0) continue;
        final content = b.group(2)!;
        final links =
            RegExp(r'<a\s+href="([^"]+)"[^>]*>([^<]+)</a>').allMatches(content);
        for (final a in links) {
          final href = a.group(1)!;
          final title = _d(a.group(2)!);
          final m2 =
              RegExp(r'/temporada/(\d+)/capitulo/(\d+)').firstMatch(href);
          if (m2 == null) continue;
          final full = href.startsWith('http') ? href : '$_base$href';
          temporadasMap.putIfAbsent(tNum, () => []);
          temporadasMap[tNum]!.add(DetalleCapitulo(
            temporada: int.parse(m2.group(1)!),
            numero: int.parse(m2.group(2)!),
            titulo: title,
            url: full,
          ));
        }
      }
    }

    if (tituloFinal.isNotEmpty) {
      final q = Uri.encodeComponent(tituloFinal);
      var api =
          'https://api.themoviedb.org/3/search/$endpoint?api_key=$_tmdbKey&query=$q&language=es-MX';
      if (anio != null && anio!.isNotEmpty) api += '&year=$anio';

      var searchBody = await _fetch(api);
      if (searchBody != null) {
        try {
          final j = jsonDecode(searchBody);
          if (j['results'] is List && (j['results'] as List).isNotEmpty) {
            tmdbId = (j['results'][0]['id'] as num?)?.toInt();
          }
        } catch (_) {}
      }

      if (tmdbId == null) {
        api =
            'https://api.themoviedb.org/3/search/$endpoint?api_key=$_tmdbKey&query=$q&language=es-MX';
        searchBody = await _fetch(api);
        if (searchBody != null) {
          try {
            final j = jsonDecode(searchBody);
            if (j['results'] is List && (j['results'] as List).isNotEmpty) {
              tmdbId = (j['results'][0]['id'] as num?)?.toInt();
            }
          } catch (_) {}
        }
      }
    }

    if (tmdbId != null) {
      final detailBody = await _fetch(
        'https://api.themoviedb.org/3/$endpoint/$tmdbId?api_key=$_tmdbKey&language=es-MX&append_to_response=images,external_ids',
      );
      if (detailBody != null) {
        try {
          final d = jsonDecode(detailBody);
          if (d['poster_path'] != null) {
            poster = 'https://image.tmdb.org/t/p/w500${d['poster_path']}';
          }
          if (d['backdrop_path'] != null) {
            backdrop =
                'https://image.tmdb.org/t/p/original${d['backdrop_path']}';
          }
          final overview = d['overview']?.toString();
          if (overview != null &&
              overview.isNotEmpty &&
              (sinopsis == null || sinopsis!.isEmpty)) {
            sinopsis = overview;
          }
          if (d['vote_average'] != null) {
            rating = (d['vote_average'] as num).toDouble();
          }
          imdbId = d['external_ids']?['imdb_id']?.toString() ??
              d['imdb_id']?.toString();

          final logos = d['images']?['logos'] as List? ?? [];
          for (final l in logos) {
            if (l is Map && l['iso_639_1'] == 'es') {
              logo = 'https://image.tmdb.org/t/p/w500${l['file_path']}';
              break;
            }
          }
          if (logo == null) {
            for (final l in logos) {
              if (l is Map &&
                  (l['iso_639_1'] == 'en' || l['iso_639_1'] == null)) {
                logo = 'https://image.tmdb.org/t/p/w500${l['file_path']}';
                break;
              }
            }
          }
          if (logo == null && logos.isNotEmpty && logos[0] is Map) {
            logo =
                'https://image.tmdb.org/t/p/w500${logos[0]['file_path']}';
          }

          if (d['title'] != null || d['name'] != null) {
            tituloFinal = (d['title'] ?? d['name']).toString();
          }
          final date =
              (d['release_date'] ?? d['first_air_date'])?.toString() ?? '';
          if (date.length >= 4) anio = date.substring(0, 4);
        } catch (_) {}
      }

      if (!isMovie && temporadasMap.isNotEmpty) {
        final firstSeason = temporadasMap.keys.reduce((a, b) => a < b ? a : b);
        final seasonBody = await _fetch(
          'https://api.themoviedb.org/3/tv/$tmdbId/season/$firstSeason?api_key=$_tmdbKey&language=es-MX',
        );
        if (seasonBody != null) {
          try {
            final sData = jsonDecode(seasonBody);
            final epMap = <int, Map>{};
            for (final ep in (sData['episodes'] as List? ?? [])) {
              if (ep is Map) {
                final n = (ep['episode_number'] as num?)?.toInt();
                if (n != null) epMap[n] = ep;
              }
            }
            final list = temporadasMap[firstSeason]!;
            for (var idx = 0; idx < list.length; idx++) {
              final cap = list[idx];
              final ep = epMap[cap.numero];
              if (ep == null) continue;
              final still = ep['still_path']?.toString();
              list[idx] = DetalleCapitulo(
                temporada: cap.temporada,
                numero: cap.numero,
                titulo: (ep['name']?.toString().isNotEmpty == true)
                    ? ep['name'].toString()
                    : cap.titulo,
                url: cap.url,
                imagen: (still != null && still.isNotEmpty)
                    ? 'https://image.tmdb.org/t/p/w300$still'
                    : cap.imagen,
                airDate: ep['air_date']?.toString() ?? cap.airDate,
              );
            }
          } catch (_) {}
        }
      }
    }

    final temporadas = temporadasMap.entries
        .map((e) => DetalleTemporada(
              numero: e.key,
              nombre: 'Temporada ${e.key}',
              episodios: e.value
                ..sort((a, b) => a.numero.compareTo(b.numero)),
            ))
        .toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));

    return DetalleContenido(
      ok: true,
      servicio: 'pelisplus',
      titulo: tituloFinal.isNotEmpty ? tituloFinal : titulo,
      tipo: isMovie ? 'movie' : 'tv',
      anio: anio,
      sinopsis: sinopsis,
      poster: poster,
      backdrop: backdrop,
      logo: logo,
      rating: rating,
      tmdbId: tmdbId,
      imdbId: imdbId,
      generos: generos,
      servidores: servidores,
      temporadas: temporadas,
    );
  }
}