// lib/fuentes/apis/home/detalle_serieskao.dart
import 'dart:convert';
import '../base/base_detail_scraper.dart';
import '../../models/scraper/detalle_model.dart';
class DetalleSeriesKao {
  static const _tmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';

  static Future<DetalleContenido> fetch({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    print('DetalleSeriesKao.fetch llamado');
    print('URL: $url');

    final html = await fetchHtml(url);

    if (html == null) {
      return DetalleContenido(
        ok: false,
        error: 'No se pudo descargar HTML de SeriesKao\n$url',
        servicio: 'serieskao',
        titulo: titulo,
        tipo: tipo,
      );
    }

    print('HTML OK → ${html.length} caracteres');

    String tituloFinal = titulo;
    String? anio, sinopsis, poster, backdrop, logo, imdbId;
    double? rating;
    int? tmdbId;
    final generos = <String>[];
    final servidores = <DetalleServidor>[];
    final temporadasMap = <int, List<DetalleCapitulo>>{};

    final isMovie = !url.contains('/serie/') && !url.contains('/anime/');
    final endpoint = isMovie ? 'movie' : 'tv';

    // Título
    final h1 = RegExp(
      r'<h1 class="detail-hero__title">([^<]+)</h1>',
    ).firstMatch(html);
    if (h1 != null) tituloFinal = _d(h1.group(1)!);

    // Año
    final y1 = RegExp(r'\((\d{4})\)').firstMatch(html);
    if (y1 != null) anio = y1.group(1);
    final y2 = RegExp(r'"datePublished":(\d{4}|"\d{4}")').firstMatch(html);
    if (y2 != null) anio = y2.group(1)!.replaceAll('"', '');

    // Sinopsis
    final desc = RegExp(r'"description":"([^"]+)"').firstMatch(html);
    if (desc != null) sinopsis = _d(desc.group(1)!);

    // Rating
    final rat = RegExp(r'"ratingValue":"([\d.]+)"').firstMatch(html);
    if (rat != null) rating = double.tryParse(rat.group(1)!);

    // Géneros
    final genM = RegExp(r'"genre":\[([^\]]+)\]').firstMatch(html);
    if (genM != null) {
      for (final g in genM.group(1)!.split(',')) {
        final c = g.replaceAll('"', '').trim();
        if (c.isNotEmpty) generos.add(c);
      }
    }

    // IMDb
    final imdbM =
        RegExp(r'data-url="/vidurl/(tt\d+)/').firstMatch(html) ??
        RegExp(r'"(tt\d{7,})"').firstMatch(html);
    if (imdbM != null) imdbId = imdbM.group(1);

    // Capítulos
    if (!isMovie) {
      final blocks = RegExp(
        r'<div class="episodes-list\s*"?[^>]*id="season-(\d+)"[^>]*>(.*?)</div>',
        dotAll: true,
      ).allMatches(html);

      for (final b in blocks) {
        final tNum = int.tryParse(b.group(1)!) ?? 0;
        final content = b.group(2)!;
        final eps = RegExp(
          r'<a href="([^"]+)" class="episode-item">\s*<span class="episode-item__number">(\d+)</span>\s*<span class="episode-item__title">([^<]+)</span>',
          dotAll: true,
        ).allMatches(content);

        for (final ep in eps) {
          final href = ep.group(1)!;
          final num = int.tryParse(ep.group(2)!) ?? 0;
          final title = _d(ep.group(3)!);
          final full = href.startsWith('http')
              ? href
              : 'https://serieskao.top$href';
          temporadasMap.putIfAbsent(tNum, () => []);
          temporadasMap[tNum]!.add(
            DetalleCapitulo(
              temporada: tNum,
              numero: num,
              titulo: title,
              url: full,
            ),
          );
        }
      }
    }

    // Servidores película
    final srv = RegExp(r'data-url="(https?://[^"]+)"').allMatches(html);
    final seen = <String>{};
    int i = 1;
    for (final m in srv) {
      final u = m.group(1)!;
      if (seen.contains(u) || u.contains('youtube')) continue;
      seen.add(u);
      servidores.add(DetalleServidor(nombre: 'Opción $i', url: u));
      i++;
    }

    // TMDB
    if (imdbId != null) {
      final find = await fetchHtml(
        'https://api.themoviedb.org/3/find/$imdbId?api_key=$_tmdbKey&external_source=imdb_id&language=es-MX',
      );
      if (find != null) {
        final j = jsonDecode(find);
        final results = isMovie ? j['movie_results'] : j['tv_results'];
        if (results is List && results.isNotEmpty) tmdbId = results[0]['id'];
      }
    }

    if (tmdbId == null && tituloFinal.isNotEmpty) {
      var api =
          'https://api.themoviedb.org/3/search/$endpoint?api_key=$_tmdbKey&query=${Uri.encodeComponent(tituloFinal)}&language=es-MX';
      if (anio != null) api += '&year=$anio';
      final search = await fetchHtml(api);
      if (search != null) {
        final j = jsonDecode(search);
        if (j['results'] is List && (j['results'] as List).isNotEmpty) {
          tmdbId = j['results'][0]['id'];
        }
      }
    }

    if (tmdbId != null) {
      final detail = await fetchHtml(
        'https://api.themoviedb.org/3/$endpoint/$tmdbId?api_key=$_tmdbKey&language=es-MX&append_to_response=images,external_ids',
      );
      if (detail != null) {
        final d = jsonDecode(detail);
        if (d['poster_path'] != null)
          poster = 'https://image.tmdb.org/t/p/w500${d['poster_path']}';
        if (d['backdrop_path'] != null)
          backdrop = 'https://image.tmdb.org/t/p/original${d['backdrop_path']}';
        if (d['overview'] != null && (sinopsis == null || sinopsis!.isEmpty))
          sinopsis = d['overview'];
        if (d['vote_average'] != null)
          rating = (d['vote_average'] as num).toDouble();
        if (d['external_ids']?['imdb_id'] != null)
          imdbId = d['external_ids']['imdb_id'];

        final logos = d['images']?['logos'] as List? ?? [];
        for (final l in logos) {
          if (l['iso_639_1'] == 'es') {
            logo = 'https://image.tmdb.org/t/p/w500${l['file_path']}';
            break;
          }
        }
        if (logo == null && logos.isNotEmpty) {
          logo = 'https://image.tmdb.org/t/p/w500${logos[0]['file_path']}';
        }
      }
    }

    final temporadas =
        temporadasMap.entries
            .map(
              (e) => DetalleTemporada(
                numero: e.key,
                nombre: 'Temporada ${e.key}',
                episodios: e.value
                  ..sort((a, b) => a.numero.compareTo(b.numero)),
              ),
            )
            .toList()
          ..sort((a, b) => a.numero.compareTo(b.numero));

    return DetalleContenido(
      ok: true,
      servicio: 'serieskao',
      titulo: tituloFinal,
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

  static String _d(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
