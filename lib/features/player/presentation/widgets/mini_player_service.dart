import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const kMiniPlayerEnabledKey = 'mini_player_enabled';

/// Mini-player global.
/// Preferible **adjuntar** el VideoPlayerController del player (handoff)
/// para no abrir un segundo decoder (evita MediaCodec Decoder init failed).
class MiniPlayerService extends ChangeNotifier {
  MiniPlayerService._();
  static final MiniPlayerService instance = MiniPlayerService._();

  VideoPlayerController? _controller;
  bool _enabled = true;
  bool _active = false;
  bool _initializing = false;
  bool _ownedByHandoff = false;

  String title = '';
  String poster = '';
  String videoUrl = '';
  Map<String, String>? headers;
  int idcontenido = 0;
  int? temporada;
  int? capitulo;
  String tipo = 'movie';
  int? tmdbId;
  String? idioma;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;

  int _lastSaveSec = -1;
  int _lastNotifyMs = 0;

  bool get enabled => _enabled;
  bool get isActive => _active && _controller != null;
  bool get isInitializing => _initializing;
  VideoPlayerController? get controller => _controller;

  int get _resolvedId {
    final id = tmdbId ?? idcontenido;
    return id > 0 ? id : idcontenido;
  }

  String get _mediaType {
    final t = tipo.toLowerCase();
    if (t == 'tv' || t == 'live') return t == 'live' ? 'live' : 'tv';
    return 'movie';
  }

  String _cacheKey() {
    if (_mediaType == 'tv' && temporada != null && capitulo != null) {
      return 'cachePlayer_${_resolvedId}_T${temporada}_C$capitulo';
    }
    return 'cachePlayer_$_resolvedId';
  }

  String _cacheKeyRapido() {
    if (_mediaType == 'tv' && temporada != null && capitulo != null) {
      return 'cachePlayerRapido_${_resolvedId}_T${temporada}_C$capitulo';
    }
    return 'cachePlayerRapido_$_resolvedId';
  }

  Future<void> loadPref() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool(kMiniPlayerEnabledKey) ?? true;
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(kMiniPlayerEnabledKey, v);
    if (!v && _active) await stop();
    notifyListeners();
  }

  /// Guarda progreso en las mismas claves que el player normal.
  Future<void> saveProgress({bool force = false}) async {
    if (!_active || idcontenido == 0 && _resolvedId == 0) return;
    // No guardar live channels en historial VOD
    if (_mediaType == 'live') return;

    final sec = position.inSeconds;
    if (!force && sec == _lastSaveSec) return;
    // Throttle: cada 5 s salvo force
    if (!force && _lastSaveSec >= 0 && (sec - _lastSaveSec).abs() < 5) return;
    _lastSaveSec = sec;

    try {
      final prefs = await SharedPreferences.getInstance();
      final full = {
        'idcontenido': _resolvedId,
        'temporada': temporada,
        'capitulo': capitulo,
        'segundo': sec,
        'titulo': title,
        'tipo': _mediaType == 'tv' ? 'tv' : 'movie',
        'videoUrl': videoUrl,
        'backdrop': poster,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_cacheKey(), jsonEncode(full));
      final rapido = {
        'idcontenido': _resolvedId,
        'temporada': temporada,
        'capitulo': capitulo,
        'segundo': sec,
      };
      await prefs.setString(_cacheKeyRapido(), jsonEncode(rapido));
    } catch (e) {
      debugPrint('[MiniPlayer] saveProgress: $e');
    }
  }

  Future<bool> attachController({
    required VideoPlayerController controller,
    required String url,
    required String title,
    required int idcontenido,
    required String tipo,
    String poster = '',
    Map<String, String>? headers,
    int? temporada,
    int? capitulo,
    int? tmdbId,
    String? idioma,
    bool resumePlay = true,
  }) async {
    if (!_enabled) return false;
    if (!controller.value.isInitialized) return false;

    await stop(notify: false);

    this.title = title;
    this.poster = poster;
    videoUrl = url;
    this.headers = headers;
    this.idcontenido = idcontenido;
    this.temporada = temporada;
    this.capitulo = capitulo;
    this.tipo = tipo;
    this.tmdbId = tmdbId;
    this.idioma = idioma;

    _controller = controller;
    _ownedByHandoff = true;
    _active = true;
    _initializing = false;
    _lastSaveSec = -1;

    try {
      controller.removeListener(_onTick);
    } catch (_) {}
    controller.addListener(_onTick);

    position = controller.value.position;
    duration = controller.value.duration;

    if (resumePlay) {
      try {
        await controller.play();
      } catch (e) {
        debugPrint('[MiniPlayer] play after attach: $e');
      }
    }
    isPlaying = controller.value.isPlaying;
    await saveProgress(force: true);
    notifyListeners();
    return true;
  }

  Future<bool> minimizeFromUrl({
    required String url,
    required String title,
    required int idcontenido,
    required String tipo,
    String poster = '',
    Map<String, String>? headers,
    int? temporada,
    int? capitulo,
    int? tmdbId,
    String? idioma,
    Duration startAt = Duration.zero,
    bool autoPlay = true,
  }) async {
    if (!_enabled) return false;
    if (url.trim().isEmpty) return false;

    await stop(notify: false);

    this.title = title;
    this.poster = poster;
    videoUrl = url;
    this.headers = headers;
    this.idcontenido = idcontenido;
    this.temporada = temporada;
    this.capitulo = capitulo;
    this.tipo = tipo;
    this.tmdbId = tmdbId;
    this.idioma = idioma;
    position = startAt;

    _initializing = true;
    _active = true;
    _ownedByHandoff = false;
    _lastSaveSec = -1;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 350));

    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: headers ?? const {},
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize();
      if (startAt > Duration.zero) {
        await c.seekTo(startAt);
      }
      c.addListener(_onTick);
      if (autoPlay) await c.play();
      _controller = c;
      duration = c.value.duration;
      position = c.value.position;
      isPlaying = c.value.isPlaying;
      _initializing = false;
      await saveProgress(force: true);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[MiniPlayer] init error: $e');
      _initializing = false;
      _active = false;
      _controller = null;
      notifyListeners();
      return false;
    }
  }

  Future<bool> minimize({
    required String url,
    required String title,
    required int idcontenido,
    required String tipo,
    String poster = '',
    Map<String, String>? headers,
    int? temporada,
    int? capitulo,
    int? tmdbId,
    String? idioma,
    Duration startAt = Duration.zero,
    bool autoPlay = true,
  }) {
    return minimizeFromUrl(
      url: url,
      title: title,
      idcontenido: idcontenido,
      tipo: tipo,
      poster: poster,
      headers: headers,
      temporada: temporada,
      capitulo: capitulo,
      tmdbId: tmdbId,
      idioma: idioma,
      startAt: startAt,
      autoPlay: autoPlay,
    );
  }

  void _onTick() {
    final c = _controller;
    if (c == null) return;
    try {
      position = c.value.position;
      duration = c.value.duration;
      final playing = c.value.isPlaying;
      if (playing != isPlaying) isPlaying = playing;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastNotifyMs > 400) {
        _lastNotifyMs = now;
        notifyListeners();
      }

      // Guardar historial cada ~5 s de reproducción
      if (playing) {
        saveProgress();
      }
    } catch (_) {}
  }

  Future<void> togglePlay() async {
    final c = _controller;
    if (c == null) return;
    try {
      if (c.value.isPlaying) {
        await c.pause();
        await saveProgress(force: true);
      } else {
        await c.play();
      }
      isPlaying = c.value.isPlaying;
      notifyListeners();
    } catch (e) {
      debugPrint('[MiniPlayer] togglePlay: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _controller?.pause();
    } catch (_) {}
    isPlaying = false;
    await saveProgress(force: true);
    notifyListeners();
  }

  Future<void> play() async {
    try {
      await _controller?.play();
      isPlaying = true;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> stop({bool notify = true}) async {
    await saveProgress(force: true);
    final c = _controller;
    _controller = null;
    _active = false;
    _initializing = false;
    isPlaying = false;
    if (c != null) {
      try {
        c.removeListener(_onTick);
        await c.pause();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
    _ownedByHandoff = false;
    if (notify) notifyListeners();
  }

  Map<String, dynamic> expandArgs() => {
        'videoUrl': videoUrl,
        'titulo': title,
        'idcontenido': idcontenido,
        'tipo': tipo,
        'temporada': temporada,
        'capitulo': capitulo,
        'tmdbId': tmdbId,
        'idioma': idioma,
        'headers': headers,
        'poster': poster,
        'startAt': position.inSeconds,
      };
}
