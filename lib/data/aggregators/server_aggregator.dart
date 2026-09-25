// lib/servicio/servidores_aggregator.dart
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../extractors/providers/cuevana_extractor.dart';
import '../extractors/providers/unlimplay_extractor.dart';
import '../extractors/providers/cinecalidad_extractor.dart';
import '../extractors/providers/tioplus_extractor.dart';
import '../extractors/providers/embed69_extractor.dart';
import '../extractors/providers/poseidon_extractor.dart';
import '../extractors/providers/cinesrc_extractor.dart';
import '../extractors/providers/pelispedia_extractor.dart';
import '../extractors/providers/seriesmetro_extractor.dart';
import '../extractors/providers/smartpelis_extractor.dart';
import '../datasources/remote/sources/custom_api.dart';
typedef ServidorMap = Map<String, dynamic>;

class ServidoresConfig {
  final bool cuevana;
  final bool unlimplay;
  final bool cinecalidad;
  final bool tioplus;
  final bool embed69;
  final bool poseidon;
  final bool cinesrc;
  final bool pelispedia;
  final bool seriesmetro;
  final bool smartpelis;
  final bool customapi;
  final bool verificarServidores;

  const ServidoresConfig({
    this.cuevana = false,
    this.unlimplay = false,
    this.cinecalidad = false,
    this.tioplus = false,
    this.embed69 = false,
    this.poseidon = false,
    this.cinesrc = false,
    this.pelispedia = false,
    this.seriesmetro = false,
    this.smartpelis = false,
    this.customapi = false,
    this.verificarServidores = true,
  });

  static Future<ServidoresConfig> fromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return ServidoresConfig(
      cuevana: prefs.getBool('cuevana_enabled') ?? false,
      unlimplay: prefs.getBool('unlimplay_enabled') ?? false,
      cinecalidad: prefs.getBool('cinecalidad_enabled') ?? false,
      tioplus: prefs.getBool('tioplus_enabled') ?? false,
      embed69: prefs.getBool('embed69_enabled') ?? false,
      poseidon: prefs.getBool('poseidon_enabled') ?? false,
      cinesrc: prefs.getBool('cinesrc_enabled') ?? false,
      pelispedia: prefs.getBool('pelispedia_enabled') ?? false,
      seriesmetro: prefs.getBool('seriesmetro_enabled') ?? false,
      smartpelis: prefs.getBool('smartpelis_enabled') ?? false,
      customapi: prefs.getBool('custom_api_enabled') ?? false,
      verificarServidores: prefs.getBool('verificar_servidores') ?? true,
    );
  }

  bool get anyEnabled =>
      cuevana ||
      unlimplay ||
      cinecalidad ||
      tioplus ||
      embed69 ||
      poseidon ||
      cinesrc ||
      pelispedia ||
      seriesmetro ||
      smartpelis ||
      customapi;
}

class ServidorEvent {
  final String source;
  final ServidorMap? server;
  final String? error;
  final bool done;

  const ServidorEvent({
    required this.source,
    this.server,
    this.error,
    this.done = false,
  });
}

class ServidoresAggregator {
  ServidoresAggregator._();

  static Stream<ServidorEvent> scrapeStream({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
    ServidoresConfig? config,
  }) async* {
    if (tmdbId <= 0) throw Exception('tmdb_id inválido');

    final cfg = config ?? await ServidoresConfig.fromPrefs();
    if (!cfg.anyEnabled) return;

    final controllers = <String, StreamController<ServidorEvent>>{};
    final futures = <Future<void>>[];

    void startSource(
      String source,
      Stream<dynamic> Function() runner,
      ServidorMap Function(dynamic) toMap,
    ) {
      final ctrl = StreamController<ServidorEvent>();
      controllers[source] = ctrl;

      futures.add(() async {
        try {
          await for (final item in runner()) {
            if (!ctrl.isClosed) {
              ctrl.add(ServidorEvent(source: source, server: toMap(item)));
            }
          }
          if (!ctrl.isClosed) {
            ctrl.add(ServidorEvent(source: source, done: true));
          }
        } catch (e) {
          if (!ctrl.isClosed) {
            ctrl.add(ServidorEvent(
              source: source,
              error: e.toString(),
              done: true,
            ));
          }
        } finally {
          await ctrl.close();
        }
      }());
    }

    if (cfg.cuevana) {
      startSource(
        'cuevana',
        () => CuevanaService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as CuevanaServer).toModalMap(),
      );
    }
    if (cfg.unlimplay) {
      startSource(
        'unlimplay',
        () => UnlimplayService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as UnlimplayServer).toModalMap(),
      );
    }
    if (cfg.cinecalidad) {
      startSource(
        'cinecalidad',
        () => CinecalidadService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as CinecalidadServer).toModalMap(),
      );
    }
    if (cfg.tioplus) {
      startSource(
        'tioplus',
        () => TioplusService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as TioplusServer).toModalMap(),
      );
    }
    if (cfg.embed69) {
      startSource(
        'embed69',
        () => Embed69Service.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as Embed69Server).toModalMap(),
      );
    }
    if (cfg.poseidon) {
      startSource(
        'poseidon',
        () => PoseidonService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as PoseidonServer).toModalMap(),
      );
    }
    if (cfg.cinesrc) {
      startSource(
        'cinesrc',
        () => CineSrcService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as CineSrcServer).toModalMap(),
      );
    }
    if (cfg.pelispedia) {
      startSource(
        'pelispedia',
        () => PelispediaService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as PelispediaServer).toModalMap(),
      );
    }
    if (cfg.seriesmetro) {
      startSource(
        'seriesmetro',
        () => SeriesMetroService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as SeriesMetroServer).toModalMap(),
      );
    }
    if (cfg.smartpelis) {
      startSource(
        'smartpelis',
        () => SmartPelisService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) => (s as SmartPelisServer).toModalMap(),
      );
    }
    if (cfg.customapi) {
      startSource(
        'customapi',
        () => CustomApiService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        ),
        (s) {
          final map = (s as CustomApiServer).toModalMap();
          map['es_customapi'] = true;
          return map;
        },
      );
    }

    final active = controllers.values.toList();
    if (active.isEmpty) return;

    final pending = active.length;
    var finished = 0;
    final seenUrls = <String>{};

    await for (final event in _StreamGroup.merge(active.map((c) => c.stream))) {
      if (event.server != null) {
        final url = event.server!['servidor_url']?.toString() ?? '';
        if (url.isNotEmpty && seenUrls.contains(url)) continue;
        if (url.isNotEmpty) seenUrls.add(url);
      }
      yield event;
      if (event.done) {
        finished++;
        if (finished >= pending) break;
      }
    }

    await Future.wait(futures);
  }

  static Future<List<ServidorMap>> scrapeAll({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
    ServidoresConfig? config,
  }) async {
    final list = <ServidorMap>[];
    final seen = <String>{};

    await for (final event in scrapeStream(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
      config: config,
    )) {
      if (event.server == null) continue;
      final url = event.server!['servidor_url']?.toString() ?? '';
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);
      list.add(event.server!);
    }
    return list;
  }

  static Map<String, List<ServidorMap>> groupBySource(List<ServidorMap> all) {
    final map = <String, List<ServidorMap>>{
      'cuevana': [],
      'unlimplay': [],
      'cinecalidad': [],
      'tioplus': [],
      'embed69': [],
      'poseidon': [],
      'cinesrc': [],
      'pelispedia': [],
      'seriesmetro': [],
      'smartpelis': [],
      'customapi': [],
    };
    for (final s in all) {
      if (s['es_cuevana'] == true) {
        map['cuevana']!.add(s);
      } else if (s['es_unlimplay'] == true) {
        map['unlimplay']!.add(s);
      } else if (s['es_cinecalidad'] == true) {
        map['cinecalidad']!.add(s);
      } else if (s['es_tioplus'] == true) {
        map['tioplus']!.add(s);
      } else if (s['es_embed69'] == true) {
        map['embed69']!.add(s);
      } else if (s['es_poseidon'] == true) {
        map['poseidon']!.add(s);
      } else if (s['es_cinesrc'] == true) {
        map['cinesrc']!.add(s);
      } else if (s['es_pelispedia'] == true) {
        map['pelispedia']!.add(s);
      } else if (s['es_seriesmetro'] == true) {
        map['seriesmetro']!.add(s);
      } else if (s['es_smartpelis'] == true) {
        map['smartpelis']!.add(s);
      } else if (s['es_customapi'] == true) {
        map['customapi']!.add(s);
      }
    }
    return map;
  }
}

class _StreamGroup {
  static Stream<T> merge<T>(Iterable<Stream<T>> streams) {
    final controller = StreamController<T>();
    var active = 0;
    for (final stream in streams) {
      active++;
      stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          active--;
          if (active == 0) controller.close();
        },
        cancelOnError: false,
      );
    }
    if (active == 0) controller.close();
    return controller.stream;
  }
}