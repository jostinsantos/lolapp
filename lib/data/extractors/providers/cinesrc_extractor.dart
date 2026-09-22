// lib/extractors/providers/cinesrc_extractor.dart
//
// Extractor de CineSRC.
// Devuelve 3 servidores por petición:
//   1) CineSRC directo (embed.st)
//   2) VideoApp  (vía Modlyo)
//   3) VidSrc    (vía Modlyo)
//
// MainFuentes se encarga de deduplicar, verificar (HLS) y enriquecer.
// El idioma por defecto es latino (es_MX) para que no sea descartado
// por "unServidorPorIdioma" antes de tiempo.

import 'dart:async';

class CineSrcServer {
  final String lang;       // "latino", "castellano", "subtitulado", etc.
  final String name;       // "CineSRC", "VideoApp", "VidSrc"
  final String url;        // URL del embed
  final String idiomaCode; // es_MX / es_ES / en_US ...

  const CineSrcServer({
    required this.lang,
    required this.name,
    required this.url,
    required this.idiomaCode,
  });

  Map<String, dynamic> toModalMap() {
    return {
      'servidor_nombre': name,
      'servidor_url': url,
      'calidad': 'HD',
      'idioma': idiomaCode,
      'estado': 'activo',
      'es_cinesrc': true,
      'fuente_id': 'cinesrc',
      'fuente_label': 'CineSrc',
    };
  }
}

class CineSrcService {
  // ─────────────────────────────────────────────────────────
  // Constructores de URL
  // ─────────────────────────────────────────────────────────

  /// CineSRC directo (embed oficial).
  static String buildEmbedUrl({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) {
    final base = isMovie
        ? 'https://cinesrc.st/embed/movie/$tmdbId'
        : 'https://cinesrc.st/embed/tv/$tmdbId?s=$season&e=$episode';

    return '$base?color=%2300ff66&autoplay=true&autonext=true&back=close&prioritize=true';
  }

  /// VideoApp vía Modlyo.
  static String buildVideoAppUrl({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) {
    final target = isMovie
        ? 'https://videoapp.mov/e/movie/$tmdbId'
        : 'https://videoapp.mov/e/tv/$tmdbId/$season/$episode';

    return 'https://modlyo.com/embed.php?url=$target';
  }

  /// VidSrc vía Modlyo.
  static String buildVidSrcUrl({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) {
    final target = isMovie
        ? 'https://vidsrc.sh/embed/movie?tmdb=$tmdbId&ds_lang=es'
        : 'https://vidsrc.sh/embed/tv/$tmdbId/$season/$episode&ds_lang=es';

    return 'https://modlyo.com/embed.php?url=$target';
  }

  // ─────────────────────────────────────────────────────────
  // Scrape principal: emite LOS TRES servidores
  // ─────────────────────────────────────────────────────────

  /// Emite 3 servidores por petición:
  ///   - CineSRC  (embed.st)
  ///   - VideoApp (Modlyo)
  ///   - VidSrc   (Modlyo)
  ///
  /// MainFuentes se encarga del resto (dedup, verificación HLS, etc.).
  static Stream<CineSrcServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) return;

    // 1) CineSRC directo
    yield CineSrcServer(
      lang: 'latino',
      name: 'CineSRC',
      url: buildEmbedUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'es_MX',
    );

    // 2) VideoApp vía Modlyo
    yield CineSrcServer(
      lang: 'latino',
      name: 'VideoApp',
      url: buildVideoAppUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'es_MX',
    );

    // 3) VidSrc vía Modlyo
    yield CineSrcServer(
      lang: 'latino',
      name: 'VidSrc',
      url: buildVidSrcUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'es_MX',
    );
  }

  // ─────────────────────────────────────────────────────────
  // Scrapes individuales (por si los quieres usar sueltos)
  // ─────────────────────────────────────────────────────────

  /// Solo CineSRC directo.
  static Stream<CineSrcServer> scrapeCineSrc({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    yield CineSrcServer(
      lang: 'latino',
      name: 'CineSRC',
      url: buildEmbedUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'es_MX',
    );
  }

  /// Solo VideoApp vía Modlyo.
  static Stream<CineSrcServer> scrapeVideoApp({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    yield CineSrcServer(
      lang: 'latino',
      name: 'VideoApp',
      url: buildVideoAppUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'es_MX',
    );
  }

  /// Solo VidSrc vía Modlyo.
  static Stream<CineSrcServer> scrapeVidSrc({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    yield CineSrcServer(
      lang: 'latino',
      name: 'VidSrc',
      url: buildVidSrcUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'es_MX',
    );
  }
}