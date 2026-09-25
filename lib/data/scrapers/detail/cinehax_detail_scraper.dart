// lib/fuentes/apis/home/detalle_cinehax.dart
import 'dart:convert';
import '../base/base_detail_scraper.dart';
import '../../models/scraper/detalle_model.dart';
class DetalleCineHax {
  static const _tmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';

  static Future<DetalleContenido> fetch({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    final uri = Uri.tryParse(url);
    final query = uri?.queryParameters ?? {};
    final tipoKao = query['tipo'] ?? 'pelicula';
    final tmdbIdStr = query['id'] ?? '';
    final season = int.tryParse(query['season'] ?? '') ?? 0;
    final isMovie = tipoKao == 'pelicula';
    final endpoint = isMovie ? 'movie' : 'tv';
    final tmdbId = int.tryParse(tmdbIdStr);

    if (tmdbId == null || tmdbId <= 0) {
      return DetalleContenido(ok: false, error: 'TMDB ID inválido', servicio: 'cinehax', titulo: titulo, tipo: tipo);
    }

    // HTML para servidores
    final html = await fetchHtml(url);
    final servidores = <DetalleServidor>[];
    if (html != null) {
      final seen = <String>{};
      int i = 1;
      for (final m in RegExp(r'data-url="(https?://[^"]+)"').allMatches(html)) {
        final u = m.group(1)!;
        if (seen.contains(u) || u.contains('youtube')) continue;
        seen.add(u);
        servidores.add(DetalleServidor(nombre: 'Opción $i', url: u));
        i++;
      }
      for (final m in RegExp(r'<iframe[^>]+src="(https?://[^"]+)"').allMatches(html)) {
        final u = m.group(1)!;
        if (seen.contains(u) || u.contains('youtube')) continue;
        seen.add(u);
        servidores.add(DetalleServidor(nombre: 'Opción $i', url: u));
        i++;
      }
    }

    // TMDB detalles
    String tituloFinal = titulo;
    String? anio, sinopsis, poster, backdrop, logo, imdbId;
    double? rating;
    final generos = <String>[];
    final temporadasMap = <int, List<DetalleCapitulo>>{};

    final detail = await fetchHtml(
      'https://api.themoviedb.org/3/$endpoint/$tmdbId?api_key=$_tmdbKey&language=es-MX&append_to_response=images,external_ids,credits',
    );

    if (detail != null) {
      final d = jsonDecode(detail);
      tituloFinal = d['title'] ?? d['name'] ?? titulo;
      anio = ((d['release_date'] ?? d['first_air_date'] ?? '') as String).length >= 4
          ? (d['release_date'] ?? d['first_air_date']).toString().substring(0, 4)
          : null;
      sinopsis = d['overview'];
      rating = (d['vote_average'] as num?)?.toDouble();
      imdbId = d['external_ids']?['imdb_id'] ?? d['imdb_id'];
      if (d['poster_path'] != null) poster = 'https://image.tmdb.org/t/p/w500${d['poster_path']}';
      if (d['backdrop_path'] != null) backdrop = 'https://image.tmdb.org/t/p/original${d['backdrop_path']}';

      for (final g in (d['genres'] as List? ?? [])) {
        if (g is Map && g['name'] != null) generos.add(g['name'].toString());
      }

      final logos = d['images']?['logos'] as List? ?? [];
      for (final l in logos) {
        if (l['iso_639_1'] == 'es') {
          logo = 'https://image.tmdb.org/t/p/w500${l['file_path']}';
          break;
        }
      }
      if (logo == null && logos.isNotEmpty) logo = 'https://image.tmdb.org/t/p/w500${logos[0]['file_path']}';

      // Temporadas
      if (!isMovie && d['seasons'] is List) {
        for (final s in d['seasons']) {
          if (s is! Map) continue;
final num = int.tryParse(s['season_number']?.toString() ?? '') ?? 0;
          if (num == 0 && (d['seasons'] as List).length > 1) continue;
          temporadasMap[num] = [];
        }

        // Cargar episodios de la temporada actual (o la primera)
        final seasonActual = season > 0 ? season : (temporadasMap.keys.isNotEmpty ? temporadasMap.keys.first : 1);
        final eps = await _getEpisodios(tmdbId, seasonActual, tipoKao);
        temporadasMap[seasonActual] = eps;
      }
    }

    final temporadas = temporadasMap.entries
        .map((e) => DetalleTemporada(
              numero: e.key,
              nombre: 'Temporada ${e.key}',
              episodios: e.value,
            ))
        .toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));

    return DetalleContenido(
      ok: true,
      servicio: 'cinehax',
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

  static Future<List<DetalleCapitulo>> _getEpisodios(int tmdbId, int season, String tipoKao) async {
    final api = await fetchHtml(
      'https://api.themoviedb.org/3/tv/$tmdbId/season/$season?api_key=$_tmdbKey&language=es-MX',
    );
    if (api == null) return [];
    final sData = jsonDecode(api);
    final caps = <DetalleCapitulo>[];
    for (final ep in (sData['episodes'] as List? ?? [])) {
      if (ep is! Map) continue;
final num = int.tryParse(ep['episode_number']?.toString() ?? '') ?? 0;
      caps.add(DetalleCapitulo(
        temporada: season,
        numero: num,
        titulo: ep['name']?.toString() ?? 'Episodio $num',
        url: 'https://cinehax.com/ver/?tipo=$tipoKao&id=$tmdbId&season=$season&episode=$num',
        imagen: ep['still_path'] != null ? 'https://image.tmdb.org/t/p/w300${ep['still_path']}' : null,
        airDate: ep['air_date']?.toString(),
       rating: double.tryParse(ep['vote_average']?.toString() ?? ''),
duracion: int.tryParse(ep['runtime']?.toString() ?? ''),
      ));
    }
    return caps;
  }
}