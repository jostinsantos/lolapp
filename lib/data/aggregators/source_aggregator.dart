// lib/servicio/main_fuentes.dart
//
// Agregador central de todas las fuentes de video.
// Emite un JSON unificado que consume ServidoresModal.
// Soporta: verificación vía ExtractorHlsService, caché de reutilización,
// modos manual / auto-primera / auto-idioma, y "último enlace elegido".
//
// Incluye fuente personalizada ILIMITADA (customapi):
// URLs tipo https://modlyo.com/lolfuentes/api.php?idcodigo=XXXXX

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../extractors/providers/cuevana_extractor.dart';
import '../extractors/providers/unlimplay_extractor.dart';
import '../extractors/providers/cinecalidad_extractor.dart';
import '../extractors/providers/tioplus_extractor.dart';
import '../extractors/providers/embed69_extractor.dart';
import '../extractors/providers/poseidon_extractor.dart';
import '../extractors/providers/fuegocine_extractor.dart';
import '../extractors/providers/pelispedia_extractor.dart';
import '../extractors/providers/seriesmetro_extractor.dart';
import '../extractors/providers/smartpelis_extractor.dart';
import '../extractors/providers/cinesrc_extractor.dart';
import '../datasources/remote/sources/custom_api.dart';
import '../extractors/hls/hls_extractor.dart';

// ─────────────────────────────────────────────────────────────
// Enums de configuración (alineados con FuentesSection)
// ─────────────────────────────────────────────────────────────

enum FuenteSeleccion {
  manual,
  autoPrimera,
  autoIdioma,
}

extension FuenteSeleccionX on FuenteSeleccion {
  String get label {
    switch (this) {
      case FuenteSeleccion.manual:
        return 'Manual';
      case FuenteSeleccion.autoPrimera:
        return 'Auto · primera opción';
      case FuenteSeleccion.autoIdioma:
        return 'Auto · idioma favorito';
    }
  }

  String get description {
    switch (this) {
      case FuenteSeleccion.manual:
        return 'Muestra todas las fuentes en pestañas para elegir';
      case FuenteSeleccion.autoPrimera:
        return 'Abre el primer servidor verificado sin mostrar lista';
      case FuenteSeleccion.autoIdioma:
        return 'Filtra por idioma favorito y muestra solo esos';
    }
  }
}

enum FuenteId {
  todos,
  embed69,
  poseidon,
  cuevana,
  unlimplay,
  cinecalidad,
  tioplus,
  fuegocine,
  pelispedia,
  seriesmetro,
  smartpelis,
  cinesrc,
  customapi, // APIs del usuario (códigos PHP ilimitados)
}

extension FuenteIdX on FuenteId {
  String get label {
    switch (this) {
      case FuenteId.todos:
        return 'Todos';
      case FuenteId.embed69:
        return 'Embed69';
      case FuenteId.poseidon:
        return 'Poseidon';
      case FuenteId.cuevana:
        return 'Cuevana';
      case FuenteId.unlimplay:
        return 'Unlimplay';
      case FuenteId.cinecalidad:
        return 'Cinecalidad';
      case FuenteId.tioplus:
        return 'TioPlus';
      case FuenteId.fuegocine:
        return 'FuegoCine';
      case FuenteId.pelispedia:
        return 'Pelispedia';
      case FuenteId.seriesmetro:
        return 'SeriesMetro';
      case FuenteId.smartpelis:
        return 'SmartPelis';
      case FuenteId.cinesrc:
        return 'CineSrc';
      case FuenteId.customapi:
        return 'Mis APIs';
    }
  }

  String get flagKey {
    switch (this) {
      case FuenteId.todos:
        return '';
      case FuenteId.embed69:
        return 'es_embed69';
      case FuenteId.poseidon:
        return 'es_poseidon';
      case FuenteId.cuevana:
        return 'es_cuevana';
      case FuenteId.unlimplay:
        return 'es_unlimplay';
      case FuenteId.cinecalidad:
        return 'es_cinecalidad';
      case FuenteId.tioplus:
        return 'es_tioplus';
      case FuenteId.fuegocine:
        return 'es_fuegocine';
      case FuenteId.pelispedia:
        return 'es_pelispedia';
      case FuenteId.seriesmetro:
        return 'es_seriesmetro';
      case FuenteId.smartpelis:
        return 'es_smartpelis';
      case FuenteId.cinesrc:
        return 'es_cinesrc';
      case FuenteId.customapi:
        return 'es_customapi';
    }
  }

  Color get badgeColor {
    switch (this) {
      case FuenteId.todos:
        return const Color(0xFFE50914);
      case FuenteId.embed69:
        return const Color(0xFF3B82F6);
      case FuenteId.poseidon:
        return const Color(0xFF8B5CF6);
      case FuenteId.cuevana:
        return const Color(0xFF22C55E);
      case FuenteId.unlimplay:
        return const Color(0xFFF59E0B);
      case FuenteId.cinecalidad:
        return const Color(0xFFEC4899);
      case FuenteId.tioplus:
        return const Color(0xFF06B6D4);
      case FuenteId.fuegocine:
        return const Color(0xFFFF6B00);
      case FuenteId.pelispedia:
        return const Color(0xFF14B8A6);
      case FuenteId.seriesmetro:
        return const Color(0xFF6366F1);
      case FuenteId.smartpelis:
        return const Color(0xFFF97316);
      case FuenteId.cinesrc:
        return const Color(0xFFEF4444);
      case FuenteId.customapi:
        return const Color(0xFF60A5FA);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Configuración leída de SharedPreferences
// ─────────────────────────────────────────────────────────────

class FuentesConfig {
  final bool cuevanaEnabled;
  final bool unlimplayEnabled;
  final bool cinecalidadEnabled;
  final bool tioplusEnabled;
  final bool embed69Enabled;
  final bool poseidonEnabled;
  final bool fuegocineEnabled;
  final bool pelispediaEnabled;
  final bool seriesmetroEnabled;
  final bool smartpelisEnabled;
  final bool cinesrcEnabled;
  final bool customApiEnabled;

  final bool verificarServidores;
  final bool unServidorPorIdioma;
  final bool mostrarServidoresEnPlayer;
  final bool idiomaPredEnabled;
  final String idiomaPredCode;
  final FuenteSeleccion seleccionFuente;
  final bool reutilizarUltimoEnlace;
  final int capitulosPrecarga;

  const FuentesConfig({
    required this.cuevanaEnabled,
    required this.unlimplayEnabled,
    required this.cinecalidadEnabled,
    required this.tioplusEnabled,
    required this.embed69Enabled,
    required this.poseidonEnabled,
    required this.fuegocineEnabled,
    required this.pelispediaEnabled,
    required this.seriesmetroEnabled,
    required this.smartpelisEnabled,
    required this.cinesrcEnabled,
    required this.customApiEnabled,
    required this.verificarServidores,
    required this.unServidorPorIdioma,
    required this.mostrarServidoresEnPlayer,
    required this.idiomaPredEnabled,
    required this.idiomaPredCode,
    required this.seleccionFuente,
    required this.reutilizarUltimoEnlace,
    this.capitulosPrecarga = 2,
  });

  static Future<FuentesConfig> load() async {
    final prefs = await SharedPreferences.getInstance();

    FuenteSeleccion sel = FuenteSeleccion.manual;
    final selRaw = prefs.getString('seleccion_fuente') ?? 'manual';
    for (final v in FuenteSeleccion.values) {
      if (v.name == selRaw) {
        sel = v;
        break;
      }
    }

    return FuentesConfig(
      cuevanaEnabled: prefs.getBool('cuevana_enabled') ?? false,
      unlimplayEnabled: prefs.getBool('unlimplay_enabled') ?? false,
      cinecalidadEnabled: prefs.getBool('cinecalidad_enabled') ?? false,
      tioplusEnabled: prefs.getBool('tioplus_enabled') ?? false,
      embed69Enabled: prefs.getBool('embed69_enabled') ?? false,
      poseidonEnabled: prefs.getBool('poseidon_enabled') ?? false,
      fuegocineEnabled: prefs.getBool('fuegocine_enabled') ?? false,
      pelispediaEnabled: prefs.getBool('pelispedia_enabled') ?? false,
      seriesmetroEnabled: prefs.getBool('seriesmetro_enabled') ?? false,
      smartpelisEnabled: prefs.getBool('smartpelis_enabled') ?? false,
      cinesrcEnabled: prefs.getBool('cinesrc_enabled') ?? false,
      customApiEnabled: prefs.getBool('custom_api_enabled') ?? false,
      verificarServidores: prefs.getBool('verificar_servidores') ?? true,
      unServidorPorIdioma: prefs.getBool('un_servidor_por_idioma') ?? true,
      mostrarServidoresEnPlayer:
          prefs.getBool('mostrar_servidores_player') ?? true,
      idiomaPredEnabled:
          prefs.getBool('idioma_predeterminado_enabled') ?? false,
      idiomaPredCode: prefs.getString('idioma_predeterminado') ?? 'es_MX',
      seleccionFuente: sel,
      reutilizarUltimoEnlace:
          prefs.getBool('reutilizar_ultimo_enlace') ?? false,
      capitulosPrecarga:
          (prefs.getInt('capitulos_precarga') ?? 2).clamp(0, 10),
    );
  }

  List<FuenteId> get fuentesActivas {
    final list = <FuenteId>[];
    if (embed69Enabled) list.add(FuenteId.embed69);
    if (poseidonEnabled) list.add(FuenteId.poseidon);
    if (cuevanaEnabled) list.add(FuenteId.cuevana);
    if (unlimplayEnabled) list.add(FuenteId.unlimplay);
    if (cinecalidadEnabled) list.add(FuenteId.cinecalidad);
    if (tioplusEnabled) list.add(FuenteId.tioplus);
    if (fuegocineEnabled) list.add(FuenteId.fuegocine);
    if (pelispediaEnabled) list.add(FuenteId.pelispedia);
    if (seriesmetroEnabled) list.add(FuenteId.seriesmetro);
    if (smartpelisEnabled) list.add(FuenteId.smartpelis);
    if (cinesrcEnabled) list.add(FuenteId.cinesrc);
    if (customApiEnabled) list.add(FuenteId.customapi);
    return list;
  }
}

// ─────────────────────────────────────────────────────────────
// Evento / resultado unificado
// ─────────────────────────────────────────────────────────────

class FuenteEvent {
  final FuenteId fuente;
  final Map<String, dynamic>? servidor;
  final bool isDone;
  final bool isVerified;
  final String? error;
  final String? resolvedM3u8;

  const FuenteEvent({
    required this.fuente,
    this.servidor,
    this.isDone = false,
    this.isVerified = false,
    this.error,
    this.resolvedM3u8,
  });
}

class FuentesResult {
  final Map<FuenteId, List<Map<String, dynamic>>> porFuente;
  final List<Map<String, dynamic>> todos;
  final Map<String, List<Map<String, dynamic>>> porIdioma;

  FuentesResult({
    required this.porFuente,
    required this.todos,
    required this.porIdioma,
  });

  Map<String, dynamic> toJson() => {
        'porFuente': porFuente.map(
          (k, v) => MapEntry(k.name, v),
        ),
        'todos': todos,
        'porIdioma': porIdioma,
      };
}

// ─────────────────────────────────────────────────────────────
// Caché de reutilización (servidores + último enlace elegido)
// ─────────────────────────────────────────────────────────────

class FuentesCache {
  static const Duration defaultTtl = Duration(hours: 12);
  static const _kLastLinkPrefix = 'ultimo_enlace_';
  static const _kServersPrefix = 'serv_cache_';
  static const _kTtlPrefsKey = 'servidores_cache_ttl_hours';

  static Future<Duration> ttl() async {
    try {
      final p = await SharedPreferences.getInstance();
      final h = p.getInt(_kTtlPrefsKey);
      if (h != null && h > 0) return Duration(hours: h);
    } catch (_) {}
    return defaultTtl;
  }

  static Future<int?> serversCacheAgeMs({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _serversKey(
        tmdbId: tmdbId,
        tipo: tipo,
        season: season,
        episode: episode,
      );
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = map['ts'] as int?;
      if (ts == null) return null;
      return DateTime.now().millisecondsSinceEpoch - ts;
    } catch (_) {
      return null;
    }
  }

  static String _serversKey({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) =>
      '$_kServersPrefix${tmdbId}_${tipo}_${season}_$episode';

  static String _lastLinkKey({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) =>
      '$_kLastLinkPrefix${tmdbId}_${tipo}_${season}_$episode';

  static Future<void> saveServers({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
    required List<Map<String, dynamic>> servidores,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _serversKey(
        tmdbId: tmdbId,
        tipo: tipo,
        season: season,
        episode: episode,
      );
      final payload = {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'servidores': servidores,
      };
      await prefs.setString(key, jsonEncode(payload));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>?> loadServers({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _serversKey(
        tmdbId: tmdbId,
        tipo: tipo,
        season: season,
        episode: episode,
      );
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = map['ts'] as int?;
      if (ts == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      final maxAge = (await ttl()).inMilliseconds;
      if (age > maxAge) {
        await prefs.remove(key);
        return null;
      }
      return List<Map<String, dynamic>>.from(map['servidores'] ?? []);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLastLink({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
    required Map<String, dynamic> servidor,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _lastLinkKey(
        tmdbId: tmdbId,
        tipo: tipo,
        season: season,
        episode: episode,
      );
      final payload = {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'servidor': servidor,
      };
      await prefs.setString(key, jsonEncode(payload));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> loadLastLink({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _lastLinkKey(
        tmdbId: tmdbId,
        tipo: tipo,
        season: season,
        episode: episode,
      );
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = map['ts'] as int?;
      if (ts == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      final maxAge = (await ttl()).inMilliseconds;
      if (age > maxAge) {
        await prefs.remove(key);
        return null;
      }
      final s = map['servidor'];
      if (s is Map) return Map<String, dynamic>.from(s);
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearFor({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_serversKey(
        tmdbId: tmdbId,
        tipo: tipo,
        season: season,
        episode: episode,
      ));
      await prefs.remove(_lastLinkKey(
        tmdbId: tmdbId,
        tipo: tipo,
        season: season,
        episode: episode,
      ));
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────
// Cola de verificación (1 WebView a la vez) + caché en memoria
// ─────────────────────────────────────────────────────────────

class _VerifyGate {
  static int _inflight = 0;
  static const int _maxConcurrent = 1;
  static final List<Completer<void>> _waiters = [];
  static final Map<String, String> _memCache = {};

  static Future<void> acquire() async {
    if (_inflight < _maxConcurrent) {
      _inflight++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
    _inflight++;
  }

  static void release() {
    _inflight = (_inflight - 1).clamp(0, _maxConcurrent);
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      if (!next.isCompleted) next.complete();
    }
  }

  static String? cached(String url) => _memCache[url];

  static void putCache(String url, String? m3u8) {
    _memCache[url] = m3u8 ?? '';
    if (_memCache.length > 200) {
      final keys = _memCache.keys.take(50).toList();
      for (final k in keys) {
        _memCache.remove(k);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// SERVICIO PRINCIPAL
// ─────────────────────────────────────────────────────────────

class MainFuentes {
  FuentesConfig? _config;

  FuentesConfig get config {
    if (_config == null) {
      throw StateError('Llama a loadConfig() antes de usar MainFuentes');
    }
    return _config!;
  }

  Future<FuentesConfig> loadConfig() async {
    _config = await FuentesConfig.load();
    return _config!;
  }

  Stream<Map<String, dynamic>> _scrapeFuente({
    required FuenteId fuente,
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) async* {
    if (tmdbId <= 0) return;

    switch (fuente) {
      case FuenteId.todos:
        break;
      case FuenteId.cuevana:
        await for (final s in CuevanaService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;
      case FuenteId.unlimplay:
        await for (final s in UnlimplayService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;
      case FuenteId.cinecalidad:
        await for (final s in CinecalidadService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          final map = s.toModalMap();
          map['idioma'] = 'es_MX';
          yield map;
        }
        break;
      case FuenteId.tioplus:
        await for (final s in TioplusService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          final map = s.toModalMap();
          map['idioma'] ??= 'es_MX';
          yield map;
        }
        break;
      case FuenteId.embed69:
        await for (final s in Embed69Service.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;
      case FuenteId.poseidon:
        await for (final s in PoseidonService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;
      case FuenteId.fuegocine:
        await for (final map in FuegoCineService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield map;
        }
        break;
      case FuenteId.pelispedia:
        await for (final s in PelispediaService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;
      case FuenteId.seriesmetro:
        await for (final s in SeriesMetroService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;
      case FuenteId.smartpelis:
        await for (final s in SmartPelisService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;
      case FuenteId.cinesrc:
        await for (final s in CineSrcService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;
      case FuenteId.customapi:
        await for (final s in CustomApiService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          final map = s.toModalMap();
          map['es_customapi'] = true;
          // Conservar label real de cada código (título del panel PHP)
          if ((map['fuente_label']?.toString() ?? '').isEmpty) {
            map['fuente_label'] = 'Mis APIs';
          }
          yield map;
        }
        break;
    }
  }

  static String normalizeIdioma(String? raw) {
    if (raw == null || raw.isEmpty) return 'es_MX';
    final l = raw.toLowerCase().trim();
    if (l.contains('castellano') ||
        l.contains('es_es') ||
        l.contains('es-es') ||
        l == 'esp') {
      return 'es_ES';
    }
    if (l.contains('sub') ||
        l.contains('en_us') ||
        l.contains('en-us') ||
        l.startsWith('en') ||
        l.contains('inglés') ||
        l.contains('ingles') ||
        l.contains('english')) {
      return 'en_US';
    }
    if (l.contains('japon')) return 'ja_JA';
    return 'es_MX';
  }

  static String idiomaLabel(String code) {
    switch (code) {
      case 'es_ES':
        return 'Castellano';
      case 'en_US':
        return 'Subtitulado';
      case 'ja_JA':
        return 'Japonés';
      default:
        return 'Latino';
    }
  }

  static const Duration _kVerifyTimeout = Duration(seconds: 5);
  static const int _kMaxVerifyPerFuente = 4;

  static Future<String?> verificarConExtractor(
    BuildContext context,
    String url, {
    Duration timeout = _kVerifyTimeout,
  }) async {
    if (url.isEmpty) return null;

    final cached = _VerifyGate.cached(url);
    if (cached != null) {
      return cached.isEmpty ? null : cached;
    }

    await _VerifyGate.acquire();
    try {
      if (!context.mounted) return null;
      final m3u8 = await ExtractorHlsService.buscarFuente(
        context,
        url,
        timeout: timeout,
      );
      _VerifyGate.putCache(url, m3u8);
      return (m3u8 == null || m3u8.isEmpty) ? null : m3u8;
    } catch (_) {
      _VerifyGate.putCache(url, null);
      return null;
    } finally {
      _VerifyGate.release();
    }
  }

  Stream<FuenteEvent> fetchProgressive({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
    int maxPorFuente = 16,
    BuildContext? context,
    bool? forzarVerificar,
  }) {
    final controller = StreamController<FuenteEvent>();
    final cfg = config;
    final activas = cfg.fuentesActivas;
    final verificar = forzarVerificar ?? cfg.verificarServidores;
    final unPorIdioma = cfg.unServidorPorIdioma;

    if (tmdbId <= 0) {
      controller.addError(Exception('tmdb_id inválido: $tmdbId'));
      controller.close();
      return controller.stream;
    }

    if (activas.isEmpty) {
      controller.addError(
        Exception(
            'No hay fuentes activas. Actívalas en Configuración → Fuentes.'),
      );
      controller.close();
      return controller.stream;
    }

    var pendientes = activas.length;
    final seenUrls = <String>{};

    Future<void> markDone(FuenteId fuente, {String? error}) async {
      if (!controller.isClosed) {
        controller.add(FuenteEvent(
          fuente: fuente,
          isDone: true,
          error: error,
        ));
      }
      pendientes--;
      if (pendientes <= 0 && !controller.isClosed) {
        await controller.close();
      }
    }

    for (final fuente in activas) {
      () async {
        final idiomasDeEstaFuente = <String>{};
        var count = 0;
        var verifiedAttempts = 0;

        try {
          await for (final raw in _scrapeFuente(
            fuente: fuente,
            tmdbId: tmdbId,
            isMovie: isMovie,
            season: season,
            episode: episode,
          )) {
            if (controller.isClosed) break;
            // customapi puede traer muchos servidores de varios códigos
            final max = fuente == FuenteId.customapi ? 64 : maxPorFuente;
            if (count >= max) break;

            final map = Map<String, dynamic>.from(raw);
            final url = map['servidor_url']?.toString() ?? '';
            if (url.isEmpty) continue;

            if (seenUrls.contains(url)) continue;
            seenUrls.add(url);

            map['idioma'] = normalizeIdioma(map['idioma']?.toString());
            map[fuente.flagKey] = true;
            map['fuente_id'] = map['fuente_id']?.toString().isNotEmpty == true
                ? map['fuente_id']
                : fuente.name;
            map['fuente_label'] =
                map['fuente_label']?.toString().isNotEmpty == true
                    ? map['fuente_label']
                    : fuente.label;
            map['tmdb_id'] = tmdbId;
            map['season'] = isMovie ? 0 : season;
            map['episode'] = isMovie ? 0 : episode;

            if (unPorIdioma) {
              final idioma = map['idioma'] as String;
              if (idiomasDeEstaFuente.contains(idioma)) continue;
              idiomasDeEstaFuente.add(idioma);
            }

            if (verificar &&
                context != null &&
                context.mounted &&
                verifiedAttempts < _kMaxVerifyPerFuente) {
              verifiedAttempts++;
              final m3u8 = await verificarConExtractor(context, url);
              if (m3u8 != null && m3u8.isNotEmpty) {
                map['resolved_m3u8'] = m3u8;
                map['verificado'] = true;
                count++;
                if (!controller.isClosed) {
                  controller.add(FuenteEvent(
                    fuente: fuente,
                    servidor: map,
                    isVerified: true,
                    resolvedM3u8: m3u8,
                  ));
                }
              } else {
                map['verificado'] = false;
                count++;
                if (!controller.isClosed) {
                  controller.add(FuenteEvent(
                    fuente: fuente,
                    servidor: map,
                    isVerified: false,
                  ));
                }
              }
            } else {
              map['verificado'] = false;
              count++;
              if (!controller.isClosed) {
                controller.add(FuenteEvent(
                  fuente: fuente,
                  servidor: map,
                  isVerified: false,
                ));
              }
            }
          }
          await markDone(fuente);
        } catch (e) {
          await markDone(
            fuente,
            error: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
          );
        }
      }();
    }

    return controller.stream;
  }

  Future<FuentesResult> fetchAll({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
    int maxPorFuente = 16,
    BuildContext? context,
    bool? forzarVerificar,
  }) async {
    final porFuente = <FuenteId, List<Map<String, dynamic>>>{};
    final todos = <Map<String, dynamic>>[];
    final porIdioma = <String, List<Map<String, dynamic>>>{};
    final seen = <String>{};

    await for (final event in fetchProgressive(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
      maxPorFuente: maxPorFuente,
      context: context,
      forzarVerificar: forzarVerificar,
    )) {
      if (event.servidor == null) continue;
      final map = event.servidor!;
      final url = map['servidor_url']?.toString() ?? '';
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);

      porFuente.putIfAbsent(event.fuente, () => []).add(map);
      todos.add(map);

      final idioma = normalizeIdioma(map['idioma']?.toString());
      porIdioma.putIfAbsent(idioma, () => []).add(map);
    }

    return FuentesResult(
      porFuente: porFuente,
      todos: todos,
      porIdioma: porIdioma,
    );
  }

  Future<Map<String, dynamic>?> tryReuseLastLink({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
    BuildContext? context,
  }) async {
    if (!config.reutilizarUltimoEnlace) return null;

    final last = await FuentesCache.loadLastLink(
      tmdbId: tmdbId,
      tipo: tipo,
      season: season,
      episode: episode,
    );
    if (last == null) return null;

    final url = last['servidor_url']?.toString() ?? '';
    if (url.isEmpty) return null;

    if (config.verificarServidores && context != null && context.mounted) {
      final m3u8 = await verificarConExtractor(context, url);
      if (m3u8 == null || m3u8.isEmpty) {
        last['verificado'] = false;
        return last;
      }
      last['resolved_m3u8'] = m3u8;
      last['verificado'] = true;
    }
    return last;
  }

  Future<List<Map<String, dynamic>>?> tryLoadCachedServers({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) {
    return FuentesCache.loadServers(
      tmdbId: tmdbId,
      tipo: tipo,
      season: season,
      episode: episode,
    );
  }
}