import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../data/aggregators/source_aggregator.dart'; // Ajusta el import según tu estructura real

/// Preferencias de audio/subtítulo/selección (las 3 nuevas opciones)
class ServerLoaderPrefs {
  /// "latino" | "castellano" | "subtitulado"
  final String idiomaAudioPredeterminado;

  /// Código de idioma de subtítulo preferido (ej. "es", "es_MX", "en")
  final String subtituloPredeterminado;

  /// "auto" | "manual"
  final String seleccionarServidores;

  const ServerLoaderPrefs({
    this.idiomaAudioPredeterminado = 'latino',
    this.subtituloPredeterminado = 'es',
    this.seleccionarServidores = 'auto',
  });

  static Future<ServerLoaderPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return ServerLoaderPrefs(
      idiomaAudioPredeterminado:
          p.getString('idioma_audio_predeterminado') ?? 'latino',
      subtituloPredeterminado:
          p.getString('subtitulo_predeterminado') ?? 'es',
      seleccionarServidores:
          p.getString('seleccionar_servidores') ?? 'auto',
    );
  }

  static Future<void> save({
    String? idiomaAudioPredeterminado,
    String? subtituloPredeterminado,
    String? seleccionarServidores,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (idiomaAudioPredeterminado != null) {
      await p.setString(
        'idioma_audio_predeterminado',
        idiomaAudioPredeterminado,
      );
    }
    if (subtituloPredeterminado != null) {
      await p.setString('subtitulo_predeterminado', subtituloPredeterminado);
    }
    if (seleccionarServidores != null) {
      await p.setString('seleccionar_servidores', seleccionarServidores);
    }
  }

  String get preferredIdiomaCode {
    switch (idiomaAudioPredeterminado.toLowerCase()) {
      case 'castellano':
        return 'es_ES';
      case 'subtitulado':
        return 'en_US';
      case 'latino':
      default:
        return 'es_MX';
    }
  }

  List<String> get idiomaFallbackOrder {
    switch (idiomaAudioPredeterminado.toLowerCase()) {
      case 'castellano':
        return ['es_ES', 'es_MX', 'en_US'];
      case 'subtitulado':
        return ['en_US', 'es_MX', 'es_ES'];
      case 'latino':
      default:
        return ['es_MX', 'es_ES', 'en_US'];
    }
  }
}

class PlayableSource {
  final String url;
  final Map<String, String> headers;
  final String quality;
  final String serverName;
  final String idioma;
  final Map<String, dynamic> rawServer;

  const PlayableSource({
    required this.url,
    this.headers = const {},
    this.quality = 'Auto',
    this.serverName = 'Server',
    this.idioma = 'es_MX',
    this.rawServer = const {},
  });
}

enum CacheType { optimal, validServers, all }

/// First-win: no espera todas las fuentes. Idioma preferido → primer m3u8 válido.
class ServerLoader {
  ServerLoader({MainFuentes? mainFuentes})
      : _main = mainFuentes ?? MainFuentes();

  final MainFuentes _main;
  ServerLoaderPrefs? _prefs;
  FuentesConfig? _fuentesConfig;

  static const Duration _cacheATtl = Duration(minutes: 60);
  static const String _kCacheAPrefix = 'srv_opt_';
  static const String _kCacheBPrefix = 'srv_valid_';

  final Set<String> _invalidUrls = {};

  Future<void> _ensureLoaded() async {
    _prefs ??= await ServerLoaderPrefs.load();
    if (_fuentesConfig == null) {
      await _main.loadConfig();
      _fuentesConfig = _main.config;
    }
  }

  String _cacheKey({
    required int contentId,
    required int season,
    required int episode,
    required String idioma,
  }) =>
      '${contentId}_${season}_${episode}_$idioma';

  Future<List<Map<String, dynamic>>> getServers({
    required int contentId,
    required bool isMovie,
    int season = 0,
    int episode = 0,
    String? idioma,
    BuildContext? context,
    bool forceRefresh = false,
  }) async {
    await _ensureLoaded();
    final preferred = idioma ?? _prefs!.preferredIdiomaCode;
    final key = _cacheKey(
      contentId: contentId,
      season: isMovie ? 0 : season,
      episode: isMovie ? 0 : episode,
      idioma: preferred,
    );

    if (!forceRefresh) {
      final cached = await _loadCacheB(key);
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final cachedMain = await _main.tryLoadCachedServers(
      tmdbId: contentId,
      tipo: isMovie ? 'movie' : 'tv',
      season: season,
      episode: episode,
    );
    if (cachedMain != null && cachedMain.isNotEmpty && !forceRefresh) {
      final filtered = _filterByIdioma(cachedMain, preferred);
      if (filtered.isNotEmpty) {
        await _saveCacheB(key, filtered);
        return filtered;
      }
    }

    final result = await _main.fetchAll(
      tmdbId: contentId,
      isMovie: isMovie,
      season: season,
      episode: episode,
      context: context,
      forzarVerificar: false,
    );

    final filtered = _filterByIdioma(result.todos, preferred);
    if (filtered.isNotEmpty) {
      await _saveCacheB(key, filtered);
      await FuentesCache.saveServers(
        tmdbId: contentId,
        tipo: isMovie ? 'movie' : 'tv',
        season: season,
        episode: episode,
        servidores: result.todos,
      );
    }
    return filtered;
  }

  /// Primera fuente válida del idioma configurado → m3u8 y PARA (no espera el resto).
  Future<PlayableSource?> resolvePlayable({
    required int contentId,
    required bool isMovie,
    int season = 0,
    int episode = 0,
    String? idioma,
    BuildContext? context,
    bool forceRefresh = false,
  }) async {
    await _ensureLoaded();
    final preferred = idioma ?? _prefs!.preferredIdiomaCode;
    final order = _prefs!.idiomaFallbackOrder;
    final s = isMovie ? 0 : season;
    final e = isMovie ? 0 : episode;
    final key = _cacheKey(
      contentId: contentId,
      season: s,
      episode: e,
      idioma: preferred,
    );

    if (!forceRefresh) {
      final opt = await _loadCacheA(key);
      if (opt != null && opt.url.isNotEmpty) {
        debugPrint('[ServerLoader] Hit Caché A → ${opt.serverName}');
        return opt;
      }
    }

    if (!forceRefresh) {
      final fromLists = await _resolveFromCachedLists(
        contentId: contentId,
        isMovie: isMovie,
        season: s,
        episode: e,
        preferred: preferred,
        order: order,
        context: context,
        cacheKey: key,
      );
      if (fromLists != null) return fromLists;
    }

    return _resolveProgressiveFirstWin(
      contentId: contentId,
      isMovie: isMovie,
      season: s,
      episode: e,
      preferred: preferred,
      order: order,
      context: context,
      cacheKey: key,
    );
  }

  void markServerAsInvalid(Map<String, dynamic> server) {
    final url = server['servidor_url']?.toString() ??
        server['resolved_m3u8']?.toString() ??
        '';
    if (url.isNotEmpty) _invalidUrls.add(url);
  }

  bool _isInvalid(Map<String, dynamic> server) {
    final url = server['servidor_url']?.toString() ??
        server['resolved_m3u8']?.toString() ??
        '';
    return url.isNotEmpty && _invalidUrls.contains(url);
  }

  Future<void> preloadNext({
    required int contentId,
    required int season,
    required int nextEpisode,
    BuildContext? context,
  }) async {
    try {
      await _ensureLoaded();
      if (_fuentesConfig!.capitulosPrecarga <= 0) return;

      final preferred = _prefs!.preferredIdiomaCode;
      final key = _cacheKey(
        contentId: contentId,
        season: season,
        episode: nextEpisode,
        idioma: preferred,
      );

      final existing = await _loadCacheA(key);
      if (existing != null) return;

      final playable = await resolvePlayable(
        contentId: contentId,
        isMovie: false,
        season: season,
        episode: nextEpisode,
        idioma: preferred,
        context: context,
        forceRefresh: false,
      );

      if (playable != null) {
        debugPrint(
          '[ServerLoader] Precarga OK: S$season E$nextEpisode → ${playable.serverName}',
        );
      }
    } catch (e) {
      debugPrint('[ServerLoader] Precarga fallida (ignorada): $e');
    }
  }

  Future<void> clearCache(CacheType type) async {
    final p = await SharedPreferences.getInstance();
    final keys = p.getKeys();
    for (final k in keys) {
      if (type == CacheType.all || type == CacheType.optimal) {
        if (k.startsWith(_kCacheAPrefix)) await p.remove(k);
      }
      if (type == CacheType.all || type == CacheType.validServers) {
        if (k.startsWith(_kCacheBPrefix)) await p.remove(k);
      }
    }
  }

  Future<bool> get isAutoMode async {
    await _ensureLoaded();
    return _prefs!.seleccionarServidores == 'auto';
  }

  ServerLoaderPrefs get prefs =>
      _prefs ?? const ServerLoaderPrefs();

  Future<PlayableSource?> _resolveFromCachedLists({
    required int contentId,
    required bool isMovie,
    required int season,
    required int episode,
    required String preferred,
    required List<String> order,
    required String cacheKey,
    BuildContext? context,
  }) async {
    final collected = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addAll(List<Map<String, dynamic>>? list) {
      if (list == null) return;
      for (final s in list) {
        final url = s['servidor_url']?.toString() ??
            s['resolved_m3u8']?.toString() ??
            '';
        if (url.isEmpty || seen.contains(url) || _isInvalid(s)) continue;
        seen.add(url);
        collected.add(s);
      }
    }

    addAll(await _loadCacheB(cacheKey));
    addAll(await _main.tryLoadCachedServers(
      tmdbId: contentId,
      tipo: isMovie ? 'movie' : 'tv',
      season: season,
      episode: episode,
    ));

    if (_fuentesConfig?.reutilizarUltimoEnlace == true) {
      try {
        final last = await _main.tryReuseLastLink(
          tmdbId: contentId,
          tipo: isMovie ? 'movie' : 'tv',
          season: season,
          episode: episode,
          context: context,
        );
        if (last != null) addAll([last]);
      } catch (_) {}
    }

    if (collected.isEmpty) return null;

    for (final code in order) {
      for (final srv in collected) {
        final idioma = MainFuentes.normalizeIdioma(srv['idioma']?.toString());
        if (idioma != code) continue;
        final playable = await tryResolveServer(srv, context: context);
        if (playable != null) {
          await _persistWin(
            cacheKey: cacheKey,
            contentId: contentId,
            isMovie: isMovie,
            season: season,
            episode: episode,
            playable: playable,
            server: srv,
            allKnown: collected,
          );
          debugPrint(
            '[ServerLoader] Caché lista → ${playable.serverName} ($idioma)',
          );
          return playable;
        }
        markServerAsInvalid(srv);
      }
    }
    return null;
  }

  Future<PlayableSource?> _resolveProgressiveFirstWin({
    required int contentId,
    required bool isMovie,
    required int season,
    required int episode,
    required String preferred,
    required List<String> order,
    required String cacheKey,
    BuildContext? context,
  }) async {
    final completer = Completer<PlayableSource?>();
    final collected = <Map<String, dynamic>>[];
    final seen = <String>{};
    final pendingFallback = <Map<String, dynamic>>[];
    StreamSubscription<FuenteEvent>? sub;
    var resolved = false;
    // Serializa intentos para no abrir N extractores a la vez
    Future<void> chain = Future.value();

    void finish(PlayableSource? src) {
      if (resolved) return;
      resolved = true;
      sub?.cancel();
      if (!completer.isCompleted) completer.complete(src);
    }

    Future<void> tryServer(Map<String, dynamic> srv) async {
      if (resolved) return;
      final playable = await tryResolveServer(srv, context: context);
      if (playable != null && !resolved) {
        await _persistWin(
          cacheKey: cacheKey,
          contentId: contentId,
          isMovie: isMovie,
          season: season,
          episode: episode,
          playable: playable,
          server: srv,
          allKnown: collected,
        );
        debugPrint(
          '[ServerLoader] First-win → ${playable.serverName} (${playable.idioma})',
        );
        finish(playable);
      } else {
        markServerAsInvalid(srv);
      }
    }

    sub = _main
        .fetchProgressive(
      tmdbId: contentId,
      isMovie: isMovie,
      season: isMovie ? 1 : (season <= 0 ? 1 : season),
      episode: isMovie ? 1 : (episode <= 0 ? 1 : episode),
      context: context,
      forzarVerificar: false,
    )
        .listen(
      (event) {
        if (resolved) return;
        if (event.servidor == null) return;

        final map = Map<String, dynamic>.from(event.servidor!);
        if (event.resolvedM3u8 != null && event.resolvedM3u8!.isNotEmpty) {
          map['resolved_m3u8'] = event.resolvedM3u8;
          map['verificado'] = true;
        }

        final url = map['servidor_url']?.toString() ??
            map['resolved_m3u8']?.toString() ??
            '';
        if (url.isEmpty || seen.contains(url) || _isInvalid(map)) return;
        seen.add(url);
        collected.add(map);

        final idioma = MainFuentes.normalizeIdioma(map['idioma']?.toString());

        if (idioma == preferred) {
          chain = chain.then((_) async {
            if (!resolved) await tryServer(map);
          });
        } else if (order.contains(idioma)) {
          pendingFallback.add(map);
        }
      },
      onError: (e) {
        debugPrint('[ServerLoader] stream error: $e');
      },
      onDone: () {
        chain = chain.then((_) async {
          if (resolved) return;
          for (final code in order) {
            if (code == preferred) continue;
            for (final srv in pendingFallback) {
              if (resolved) return;
              final idioma =
                  MainFuentes.normalizeIdioma(srv['idioma']?.toString());
              if (idioma != code) continue;
              await tryServer(srv);
            }
          }
          if (!resolved) {
            for (final srv in collected) {
              if (resolved) return;
              await tryServer(srv);
            }
          }
          finish(null);
        });
      },
      cancelOnError: false,
    );

    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        sub?.cancel();
        return null;
      },
    );
  }

  Future<void> _persistWin({
    required String cacheKey,
    required int contentId,
    required bool isMovie,
    required int season,
    required int episode,
    required PlayableSource playable,
    required Map<String, dynamic> server,
    required List<Map<String, dynamic>> allKnown,
  }) async {
    try {
      await _saveCacheA(cacheKey, playable);
      if (allKnown.isNotEmpty) {
        await _saveCacheB(cacheKey, allKnown);
        await FuentesCache.saveServers(
          tmdbId: contentId,
          tipo: isMovie ? 'movie' : 'tv',
          season: season,
          episode: episode,
          servidores: allKnown,
        );
      }
      await FuentesCache.saveLastLink(
        tmdbId: contentId,
        tipo: isMovie ? 'movie' : 'tv',
        season: season,
        episode: episode,
        servidor: server,
      );
    } catch (_) {}
  }

  List<Map<String, dynamic>> _filterByIdioma(
    List<Map<String, dynamic>> all,
    String preferred,
  ) {
    final order = _prefs?.idiomaFallbackOrder ?? ['es_MX', 'es_ES', 'en_US'];
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final code in order) {
      for (final s in all) {
        if (_isInvalid(s)) continue;
        final idioma = MainFuentes.normalizeIdioma(s['idioma']?.toString());
        final url = s['servidor_url']?.toString() ??
            s['resolved_m3u8']?.toString() ??
            '';
        if (idioma == code && url.isNotEmpty && !seen.contains(url)) {
          seen.add(url);
          result.add(s);
        }
      }
      if (result.isNotEmpty && code == preferred) break;
    }

    if (result.isEmpty) {
      for (final s in all) {
        if (_isInvalid(s)) continue;
        final url = s['servidor_url']?.toString() ??
            s['resolved_m3u8']?.toString() ??
            '';
        if (url.isNotEmpty && !seen.contains(url)) {
          seen.add(url);
          result.add(s);
        }
      }
    }
    return result;
  }

  Future<PlayableSource?> tryResolveServer(
    Map<String, dynamic> srv, {
    BuildContext? context,
  }) async {
    if (_isInvalid(srv)) return null;

    final already = srv['resolved_m3u8']?.toString();
    if (already != null && already.isNotEmpty) {
      return PlayableSource(
        url: already,
        headers: _extractHeaders(srv),
        quality: srv['quality']?.toString() ??
            srv['calidad']?.toString() ??
            'Auto',
        serverName: srv['fuente_label']?.toString() ??
            srv['servidor_nombre']?.toString() ??
            srv['server']?.toString() ??
            'Server',
        idioma: MainFuentes.normalizeIdioma(srv['idioma']?.toString()),
        rawServer: srv,
      );
    }

    final url = srv['servidor_url']?.toString() ?? '';
    if (url.isEmpty) return null;

    final lower = url.toLowerCase();
    final esDirecto = srv['type']?.toString() == 'direct' ||
        srv['provider']?.toString() == 'netmirror' ||
        lower.contains('.mp4') ||
        lower.contains('.m3u8') ||
        lower.contains('hakunaymatata.com') ||
        (lower.contains('/bt/') && lower.contains('.mp4'));

    if (esDirecto) {
      return PlayableSource(
        url: url,
        headers: _extractHeaders(srv),
        quality: srv['quality']?.toString() ??
            srv['calidad']?.toString() ??
            'Auto',
        serverName: srv['fuente_label']?.toString() ??
            srv['servidor_nombre']?.toString() ??
            'Server',
        idioma: MainFuentes.normalizeIdioma(srv['idioma']?.toString()),
        rawServer: srv,
      );
    }

    if (context != null && context.mounted) {
      try {
        final m3u8 = await MainFuentes.verificarConExtractor(
          context,
          url,
          timeout: const Duration(seconds: 8),
        );
        if (m3u8 != null && m3u8.isNotEmpty) {
          srv['resolved_m3u8'] = m3u8;
          srv['verificado'] = true;
          return PlayableSource(
            url: m3u8,
            headers: _extractHeaders(srv),
            quality: srv['quality']?.toString() ??
                srv['calidad']?.toString() ??
                'Auto',
            serverName: srv['fuente_label']?.toString() ??
                srv['servidor_nombre']?.toString() ??
                'Server',
            idioma: MainFuentes.normalizeIdioma(srv['idioma']?.toString()),
            rawServer: srv,
          );
        }
      } catch (_) {}
    }

    return null;
  }

  Map<String, String> _extractHeaders(Map<String, dynamic> srv) {
    final h = <String, String>{};
    final raw = srv['headers'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k != null && v != null) h['$k'] = '$v';
      });
    }
    h.putIfAbsent(
      'User-Agent',
      () =>
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    );
    return h;
  }

  Future<void> _saveCacheA(String key, PlayableSource src) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        '$_kCacheAPrefix$key',
        jsonEncode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'url': src.url,
          'headers': src.headers,
          'quality': src.quality,
          'serverName': src.serverName,
          'idioma': src.idioma,
          'raw': src.rawServer,
        }),
      );
    } catch (_) {}
  }

  Future<PlayableSource?> _loadCacheA(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_kCacheAPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = map['ts'] as int?;
      if (ts == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _cacheATtl.inMilliseconds) {
        await p.remove('$_kCacheAPrefix$key');
        return null;
      }
      final headers = <String, String>{};
      final h = map['headers'];
      if (h is Map) {
        h.forEach((k, v) => headers['$k'] = '$v');
      }
      final url = map['url']?.toString() ?? '';
      if (url.isEmpty) return null;
      return PlayableSource(
        url: url,
        headers: headers,
        quality: map['quality']?.toString() ?? 'Auto',
        serverName: map['serverName']?.toString() ?? 'Server',
        idioma: map['idioma']?.toString() ?? 'es_MX',
        rawServer: map['raw'] is Map
            ? Map<String, dynamic>.from(map['raw'] as Map)
            : {},
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCacheB(
    String key,
    List<Map<String, dynamic>> servers,
  ) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        '$_kCacheBPrefix$key',
        jsonEncode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'servidores': servers,
        }),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> _loadCacheB(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_kCacheBPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = map['ts'] as int?;
      if (ts == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      final ttl = await FuentesCache.ttl();
      if (age > ttl.inMilliseconds) {
        await p.remove('$_kCacheBPrefix$key');
        return null;
      }
      return List<Map<String, dynamic>>.from(map['servidores'] ?? []);
    } catch (_) {
      return null;
    }
  }
}