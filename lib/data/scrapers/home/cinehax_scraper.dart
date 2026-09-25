// lib/fuentes/apis/home/cinehax.dart
class CineHax {
  static String url({
    required int tmdbId,
    String tipo = 'pelicula', // pelicula | serie | tv
    int? season,
    int? episode,
  }) {
    if (tmdbId <= 0) return '';

    const base = 'https://cinehax.com/ver/';

    if (tipo == 'serie' || tipo == 'tv') {
      final s = (season ?? 1).clamp(1, 999);
      final e = (episode ?? 1).clamp(1, 999);
      return '$base?tipo=serie&id=$tmdbId&season=$s&episode=$e';
    }

    return '$base?tipo=pelicula&id=$tmdbId';
  }
}