// lib/fuentes/apis/home/detalle_cuevana.dart
import 'dart:convert';
import '../base/base_detail_scraper.dart';
import '../../models/scraper/detalle_model.dart';
class DetalleCuevana {
  static const _tmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const _base = 'https://wv3.cuevana3.eu';

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
        servicio: 'cuevana',
        titulo: titulo,
        tipo: tipo,
      );
    }

    final nextM = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (nextM == null) {
      return DetalleContenido(
        ok: false,
        error: 'No __NEXT_DATA__',
        servicio: 'cuevana',
        titulo: titulo,
        tipo: tipo,
      );
    }

    Map? next;
    try {
      next = jsonDecode(nextM.group(1)!);
    } catch (_) {
      return DetalleContenido(
        ok: false,
        error: 'JSON inválido',
        servicio: 'cuevana',
        titulo: titulo,
        tipo: tipo,
      );
    }

    final pp = next?['props']?['pageProps'] as Map? ?? {};
    final isMovie = url.contains('/ver-pelicula/');
    final endpoint = isMovie ? 'movie' : 'tv';

    String tituloFinal = titulo;
    String? anio, sinopsis, poster, backdrop, logo, imdbId;
    double? rating;
    int? tmdbId;
    final generos = <String>[];
    final servidores = <DetalleServidor>[];
    final temporadasMap = <int, List<DetalleCapitulo>>{};

    if (isMovie && pp['thisMovie'] is Map) {
      final m = pp['thisMovie'] as Map;
      tmdbId = int.tryParse(m['TMDbId']?.toString() ?? '');
      tituloFinal = m['titles']?['name']?.toString() ?? titulo;
      sinopsis = m['overview']?.toString();
      poster = m['images']?['poster']?.toString();
      backdrop = m['images']?['backdrop']?.toString();
      rating = (m['rate']?['average'] as num?)?.toDouble();
      anio = (m['releaseDate']?.toString() ?? '').length >= 4
          ? m['releaseDate'].toString().substring(0, 4)
          : null;

      for (final g in (m['genres'] as List? ?? [])) {
        if (g is Map && g['name'] != null) generos.add(g['name'].toString());
      }

      const langs = {
        'latino': 'Español Latino',
        'spanish': 'Español',
        'english': 'Subtitulado',
        'japanese': 'Japonés',
      };
      final videos = m['videos'] as Map? ?? {};
      langs.forEach((key, label) {
        for (final v in (videos[key] as List? ?? [])) {
          if (v is! Map) continue;
          servidores.add(
            DetalleServidor(
              nombre: v['cyberlocker']?.toString() ?? 'Servidor',
              url: v['result']?.toString() ?? '',
              idioma: label,
              calidad: v['quality']?.toString(),
            ),
          );
        }
      });
    }

    if (!isMovie && pp['thisSerie'] is Map) {
      final s = pp['thisSerie'] as Map;
      tmdbId = int.tryParse(s['TMDbId']?.toString() ?? '');
      tituloFinal = s['titles']?['name']?.toString() ?? titulo;
      sinopsis = s['overview']?.toString();
      poster = s['images']?['poster']?.toString();
      backdrop = s['images']?['backdrop']?.toString();
      rating = (s['rate']?['average'] as num?)?.toDouble();
      anio = (s['releaseDate']?.toString() ?? '').length >= 4
          ? s['releaseDate'].toString().substring(0, 4)
          : null;

      for (final g in (s['genres'] as List? ?? [])) {
        if (g is Map && g['name'] != null) generos.add(g['name'].toString());
      }

      for (final season in (s['seasons'] as List? ?? [])) {
        if (season is! Map) continue;
        final num = int.tryParse(season['number']?.toString() ?? '') ?? 0;
        for (final ep in (season['episodes'] as List? ?? [])) {
          if (ep is! Map) continue;
          final epNum = int.tryParse(ep['number']?.toString() ?? '') ?? 0;
          final slug = ep['slug']?['name']?.toString() ?? '';
          temporadasMap.putIfAbsent(num, () => []);
          temporadasMap[num]!.add(
            DetalleCapitulo(
              temporada: num,
              numero: epNum,
              titulo: ep['title']?.toString() ?? '',
              url: '$_base/episodio/$slug-temporada-$num-episodio-$epNum',
              imagen: ep['image']?.toString(),
              airDate: (ep['releaseDate']?.toString() ?? '').length >= 10
                  ? ep['releaseDate'].toString().substring(0, 10)
                  : null,
            ),
          );
        }
      }
    }

    // Logo + IMDb desde TMDB
    if (tmdbId != null) {
      final detail = await fetchHtml(
        'https://api.themoviedb.org/3/$endpoint/$tmdbId?api_key=$_tmdbKey&language=es-MX&append_to_response=images,external_ids',
      );
      if (detail != null) {
        final d = jsonDecode(detail);
        imdbId = d['external_ids']?['imdb_id'] ?? d['imdb_id'];
        if (d['overview'] != null && (sinopsis == null || sinopsis!.isEmpty))
          sinopsis = d['overview'];
        if (poster == null && d['poster_path'] != null) {
          poster = 'https://image.tmdb.org/t/p/w500${d['poster_path']}';
        }
        if (backdrop == null && d['backdrop_path'] != null) {
          backdrop = 'https://image.tmdb.org/t/p/original${d['backdrop_path']}';
        }
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
      servicio: 'cuevana',
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
}
