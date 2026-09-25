// lib/fuentes/apis/home/detalle_tioplus.dart
import 'dart:convert';
import '../base/base_detail_scraper.dart';
import '../../models/scraper/detalle_model.dart';
class DetalleTioPlus {
  static const _tmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';

  static Future<DetalleContenido> fetch({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    final html = await fetchHtml(url);
    if (html == null) {
      return DetalleContenido(
        ok: false,
        error: 'No se pudo cargar',
        servicio: 'tioplus',
        titulo: titulo,
        tipo: tipo,
      );
    }

    String tituloFinal = titulo;
    String? anio, sinopsis, poster, backdrop, logo, imdbId, tituloOriginal;
    double? rating;
    int? tmdbId;
    final generos = <String>[];
    final servidores = <DetalleServidor>[];
    final temporadasMap = <int, List<DetalleCapitulo>>{};

    final isMovie = !url.contains('/serie/') && !url.contains('/anime/');
    final endpoint = isMovie ? 'movie' : 'tv';

    // Título + año
    final h1 = RegExp(r'<h1 class="slugh1">([^<]+)</h1>').firstMatch(html);
    if (h1 != null) {
      final t = h1.group(1)!.trim();
      final m = RegExp(r'^(.+?)\s*\((\d{4})\)$').firstMatch(t);
      if (m != null) {
        tituloFinal = m.group(1)!.trim();
        anio = m.group(2);
      } else {
        tituloFinal = t;
      }
    }

    // Título original
    final orig = RegExp(
      r'<b>Titulo Original:</b></span>\s*<h2>([^<]+)</h2>',
    ).firstMatch(html);
    if (orig != null) tituloOriginal = orig.group(1)!.trim();

    // Sinopsis
    final desc = RegExp(
      r'<div class="description">\s*<p>(.*?)</p>',
      dotAll: true,
    ).firstMatch(html);
    if (desc != null) sinopsis = _d(desc.group(1)!);

    // Backdrop
    final bg = RegExp(
      r'background-image:\s*url\("?(https://image\.tmdb\.org/t/p/w1280/[^"\)]+)"?\)',
      caseSensitive: false,
    ).firstMatch(html);
    if (bg != null) backdrop = bg.group(1);

    // Poster
    final og = RegExp(
      r'<meta property="og:image" content="([^"]+)"',
    ).firstMatch(html);
    if (og != null) poster = og.group(1);

    // Rating
    final rat = RegExp(r'<b>Rating:</b>\s*([\d.]+)').firstMatch(html);
    if (rat != null) rating = double.tryParse(rat.group(1)!);

    // Año fallback
    if (anio == null) {
      final y = RegExp(r'<b>Año:</b>\s*<a[^>]*>(\d{4})</a>').firstMatch(html);
      if (y != null) anio = y.group(1);
    }

    // Géneros
    final genBlock = RegExp(
      r'<span><b>Generos</b></span>(.*?)</div>',
      dotAll: true,
    ).firstMatch(html);
    if (genBlock != null) {
      for (final a in RegExp(
        r'<a[^>]*>([^<]+)</a>',
      ).allMatches(genBlock.group(1)!)) {
        generos.add(a.group(1)!.trim());
      }
    }

    // Servidores (tokens)
    final srv = RegExp(r'data-server="([^"]+)"').allMatches(html);
    final seen = <String>{};
    int i = 1;
    for (final m in srv) {
      final token = m.group(1)!;
      if (seen.contains(token)) continue;
      seen.add(token);
      servidores.add(
        DetalleServidor(nombre: 'Opción $i', url: token),
      ); // token base64
      i++;
    }

    // Temporadas + capítulos (seasonsJson)
    if (!isMovie) {
      final jsonM = RegExp(
        r'const seasonsJson = (\{.*?\});\s*</script>',
        dotAll: true,
      ).firstMatch(html);
      if (jsonM != null) {
        try {
          var jsonStr = jsonM.group(1)!;
          Map? seasons = jsonDecode(jsonStr);
          if (seasons == null) {
            jsonStr = jsonStr
                .replaceAll(r'\/', '/')
                .replaceAll('\n', '')
                .replaceAll('\r', '');
            seasons = jsonDecode(jsonStr);
          }
          if (seasons is Map) {
            seasons.forEach((key, eps) {
              final t = int.tryParse(key.toString()) ?? 0;
              if (eps is List) {
                for (final ep in eps) {
                  if (ep is! Map) continue;
                  final num =
                      int.tryParse(ep['episode']?.toString() ?? '') ?? 0;
                  final title = ep['title']?.toString() ?? '';
                  final img = ep['image'] != null
                      ? 'https://image.tmdb.org/t/p/w300${ep['image']}'
                      : null;
                  final epUrl =
                      '${url.replaceAll(RegExp(r'/$'), '')}/season/$t/episode/$num';
                  temporadasMap.putIfAbsent(t, () => []);
                  temporadasMap[t]!.add(
                    DetalleCapitulo(
                      temporada: t,
                      numero: num,
                      titulo: title,
                      url: epUrl,
                      imagen: img,
                    ),
                  );
                }
              }
            });
          }
        } catch (_) {}
      }
    }

    // TMDB
    Future<void> searchTmdb(String q) async {
      if (tmdbId != null) return;
      var api =
          'https://api.themoviedb.org/3/search/$endpoint?api_key=$_tmdbKey&query=${Uri.encodeComponent(q)}&language=es-MX';
      if (anio != null) api += '&year=$anio';
      final r = await fetchHtml(api);
      if (r != null) {
        final j = jsonDecode(r);
        if (j['results'] is List && (j['results'] as List).isNotEmpty) {
          tmdbId = j['results'][0]['id'];
        }
      }
    }

    await searchTmdb(tituloFinal);
    if (tmdbId == null && tituloOriginal != null)
      await searchTmdb(tituloOriginal!);

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
        imdbId = d['external_ids']?['imdb_id'] ?? d['imdb_id'];

        final logos = d['images']?['logos'] as List? ?? [];
        for (final l in logos) {
          if (l['iso_639_1'] == 'es') {
            logo = 'https://image.tmdb.org/t/p/w500${l['file_path']}';
            break;
          }
        }
        if (logo == null && logos.isNotEmpty)
          logo = 'https://image.tmdb.org/t/p/w500${logos[0]['file_path']}';
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
      servicio: 'tioplus',
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
