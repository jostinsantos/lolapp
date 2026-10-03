// lib/fuentes/apis/home/detalle_model.dart
class DetalleServidor {
  final String nombre;
  final String url;
  final String? idioma;
  final String? calidad;

  DetalleServidor({
    required this.nombre,
    required this.url,
    this.idioma,
    this.calidad,
  });
}

class DetalleCapitulo {
  final int temporada;
  final int numero;
  final String titulo;
  final String url;
  final String? imagen;
  final String? airDate;
  final double? rating;
  final int? duracion;

  DetalleCapitulo({
    required this.temporada,
    required this.numero,
    required this.titulo,
    required this.url,
    this.imagen,
    this.airDate,
    this.rating,
    this.duracion,
  });
}

class DetalleTemporada {
  final int numero;
  final String nombre;
  final List<DetalleCapitulo> episodios;

  DetalleTemporada({
    required this.numero,
    required this.nombre,
    required this.episodios,
  });
}

class DetalleContenido {
  final bool ok;
  final String? error;
  final String servicio;
  final String titulo;
  final String tipo; // movie | tv | anime
  final String? anio;
  final String? sinopsis;
  final String? poster;
  final String? backdrop;
  final String? logo;
  final double? rating;
  final int? tmdbId;
  final String? imdbId;
  final List<String> generos;
  final List<DetalleServidor> servidores;
  final List<DetalleTemporada> temporadas;

  /// Datos extra del sitio (opcionales). No afecta a Cuevana ni al resto.
  /// Ej: status, studios, related, trailer, likes, slug, anime_id...
  final Map<String, dynamic>? extra;

  DetalleContenido({
    required this.ok,
    this.error,
    required this.servicio,
    required this.titulo,
    required this.tipo,
    this.anio,
    this.sinopsis,
    this.poster,
    this.backdrop,
    this.logo,
    this.rating,
    this.tmdbId,
    this.imdbId,
    this.generos = const [],
    this.servidores = const [],
    this.temporadas = const [],
    this.extra,
  });
}