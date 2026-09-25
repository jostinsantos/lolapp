import 'dart:async';

class CineSrcServer {
  final String lang;
  final String name;
  final String url;
  final String idiomaCode;

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

  static String buildVsEmbedUrl({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) {
    if (isMovie) {
      return 'https://vsembed.ru/embed/movie?tmdb=$tmdbId&ds_lang=es?auto=1';
    }
    return 'https://vsembed.ru/embed/tv?tmdb=$tmdbId&season=$season&episode=$episode&color=e600e6&ds_lang=es?auto=1';
  }

  static String buildZxcPrimeUrl({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) {
    if (isMovie) {
      return 'https://player.zxcprime.xyz/player/movie/$tmdbId?autoplay=true&server=0&back=false&dubLang=esla';
    }
    return 'https://player.zxcprime.xyz/player/tv/$tmdbId/$season/$episode?autoplay=true&server=0&back=false&dubLang=esla';
  }

  static String buildVimeusUrl({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) {
    const viewKey = 'KUDU-EYQ76rbZwNu7hun16C4HX0K6qy77hZw4CaveiI';
    if (isMovie) {
      return 'https://vimeus.com/e/movie?tmdb=$tmdbId&view_key=$viewKey&title=+&theme=minimal';
    }
    return 'https://vimeus.com/e/serie?tmdb=$tmdbId&se=$season&ep=$episode&view_key=$viewKey&title=+&theme=minimal';
  }

  static Stream<CineSrcServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) return;

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

    yield CineSrcServer(
      lang: 'ingles',
      name: 'VsEmbed',
      url: buildVsEmbedUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'en_US',
    );

    yield CineSrcServer(
      lang: 'ingles',
      name: 'ZxcPrime',
      url: buildZxcPrimeUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'en_US',
    );

    yield CineSrcServer(
      lang: 'latino',
      name: 'Vimeus',
      url: buildVimeusUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'es_MX',
    );
  }

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

  static Stream<CineSrcServer> scrapeVsEmbed({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    yield CineSrcServer(
      lang: 'ingles',
      name: 'VsEmbed',
      url: buildVsEmbedUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'en_US',
    );
  }

  static Stream<CineSrcServer> scrapeZxcPrime({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    yield CineSrcServer(
      lang: 'ingles',
      name: 'ZxcPrime',
      url: buildZxcPrimeUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'en_US',
    );
  }

  static Stream<CineSrcServer> scrapeVimeus({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    yield CineSrcServer(
      lang: 'latino',
      name: 'Vimeus',
      url: buildVimeusUrl(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ),
      idiomaCode: 'es_MX',
    );
  }
}