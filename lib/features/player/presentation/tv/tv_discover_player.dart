// lib/tv/player/player_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../servers/presentation/tv_servers_modal_fuentes.dart'; // ServidoresModalFuentesTv
import '../../../servers/presentation/tv_server_preloader.dart';
import 'tv_quality_selector.dart';
import '../../../content/presentation/content_info.dart';
import '../../../content/presentation/cast_modal.dart';
import '../../../content/presentation/seasons_episodes.dart';
import '../widgets/next_episode_prompt.dart';
import '../widgets/screensaver_overlay.dart';
import '../widgets/because_you_watched_overlay.dart';
import '../../../../data/datasources/remote/tmdb/tmdb_player_api.dart';
import '../widgets/watch_later_button.dart'; // solo GuardadosBus.bump / cache si lo usas en save
import '../widgets/watch_later_button.dart';
enum _VideoFitMode {
  original,
  ratio16_9,
  ratio21_9,
  ratio16_10,
  ratio4_3,
}

class PlayerScreen extends StatefulWidget {
  final String videoUrl;
  final int idcontenido;
  final int? tmdbId;
  final int? temporada;
  final int? capitulo;
  final String tipo;
  final String titulo;
  final String? servidorUrl;
  final String? servidorNombre;
  final String? idioma;
  final int? idServidor;
  final String? fuentesServidor;
  final String? fuente; // fuente forzada para el modal nuevo

  const PlayerScreen({
    super.key,
    required this.videoUrl,
    required this.idcontenido,
    this.tmdbId,
    this.temporada,
    this.capitulo,
    required this.tipo,
    required this.titulo,
    this.servidorUrl,
    this.servidorNombre,
    this.idioma,
    this.idServidor,
    this.fuentesServidor,
    this.fuente,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Color accentOrange = Color(0xFFFF6B00);
  static const Color netflixRed = Color(0xFFE50914);

  late VideoPlayerController _controller;
  bool _isLoading = true;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String _errorMessage = '';
  bool _showControls = false;
  bool _isBuffering = false;
  Timer? _hideControlsTimer;
  bool _isDragging = false;
  bool _isDisposing = false;
  bool _controllerReady = false;
  bool _isModalOpen = false;
  bool _showToolbarOnly = false;
  Timer? _hideToolbarOnlyTimer;

  FocusNode? _lastFocusedActionNode;
  bool _controlsWereShowingBeforeModal = false;

  Timer? _seekHoldTimer;
  int _seekHoldDirection = 0;
  int _seekHoldTicks = 0;

  static const String _prefNextThresholdPctKey = 'player_next_threshold_pct';

  Map<String, dynamic>? _apiData;
  String? _backdropUrl;
  String? _logoUrl;
  String _tituloContenido = '';
  String? _tituloCapitulo;
  String? _capituloFmt;
  String _idioma = 'ES';
  String? _servidorUrl;
  String? _servidorNombre;
  List<dynamic> _temporadas = const [];
  List<dynamic> _recomendaciones = const [];
  int _selectedSeasonIndex = 0;
  Map<String, dynamic>? _siguiente;

  String _currentTime = '';
  String _horaFinEstimada = '';
  Timer? _clockTimer;
  Timer? _cacheTimer;
  Timer? _screensaverTimer;
  bool _showScreensaver = false;

  final FocusNode _videoFocusNode = FocusNode();
  final FocusNode _seekBarFocusNode = FocusNode();
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _restartFocusNode = FocusNode();
  final FocusNode _nextFocusNode = FocusNode();
  final FocusNode _serversFocusNode = FocusNode();
  final FocusNode _qualityFocusNode = FocusNode();
  final FocusNode _infoFocusNode = FocusNode();
  final FocusNode _fitFocusNode = FocusNode();
  final FocusNode _nextPromptFocusNode = FocusNode();
  final FocusNode _errorServersFocusNode = FocusNode();
  final FocusNode _errorBackFocusNode = FocusNode();
  final FocusNode _exitContinueFocusNode = FocusNode();
  final FocusNode _exitConfirmFocusNode = FocusNode();
  final FocusNode _byProducirSiguienteFocusNode = FocusNode();
  final FocusNode _byContinuarCreditosFocusNode = FocusNode();
  bool _showBecauseYouWatched = false;
  bool _hasShownBecauseYouWatched = false;
  late final List<FocusNode> _actionNodes;

  String _currentQualityLabel = 'Auto';
  String? _currentQualityUrl;
  final List<FocusNode> _seasonFocusNodes = [];
  final List<FocusNode> _episodeFocusNodes = [];
  final List<FocusNode> _recoFocusNodes = [];

  final ScrollController _seasonScrollController = ScrollController();
  final ScrollController _episodeScrollController = ScrollController();
  final ScrollController _recoScrollController = ScrollController();

  int _currentRow = 0;
  int _currentCol = 0;

  _VideoFitMode _fitMode = _VideoFitMode.original;
  String? _fitToastLabel;
  Timer? _fitToastTimer;

  double? get _forcedAspectRatio {
    switch (_fitMode) {
      case _VideoFitMode.original:
        return null;
      case _VideoFitMode.ratio16_9:
        return 16 / 9;
      case _VideoFitMode.ratio21_9:
        return 21 / 9;
      case _VideoFitMode.ratio16_10:
        return 16 / 10;
      case _VideoFitMode.ratio4_3:
        return 4 / 3;
    }
  }

  String get _fitModeLabel {
    switch (_fitMode) {
      case _VideoFitMode.original:
        return 'Original';
      case _VideoFitMode.ratio16_9:
        return '16:9';
      case _VideoFitMode.ratio21_9:
        return '21:9';
      case _VideoFitMode.ratio16_10:
        return '16:10';
      case _VideoFitMode.ratio4_3:
        return '4:3';
    }
  }

  IconData get _fitModeIcon {
    switch (_fitMode) {
      case _VideoFitMode.original:
        return Icons.fit_screen_rounded;
      case _VideoFitMode.ratio16_9:
        return Icons.crop_16_9_rounded;
      case _VideoFitMode.ratio21_9:
        return Icons.crop_landscape_rounded;
      case _VideoFitMode.ratio16_10:
        return Icons.crop_5_4_rounded;
      case _VideoFitMode.ratio4_3:
        return Icons.crop_portrait_rounded;
    }
  }

  String get _resolvedFuente {
    final f = (widget.fuente ?? widget.fuentesServidor)?.trim() ?? '';
    return f;
  }

  void _cycleFitMode() {
    setState(() {
      final values = _VideoFitMode.values;
      final next = (_fitMode.index + 1) % values.length;
      _fitMode = values[next];
      _fitToastLabel = _fitModeLabel;
    });
    _fitToastTimer?.cancel();
    _fitToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_isDisposing) {
        setState(() => _fitToastLabel = null);
      }
    });
    _scheduleHideControls();
    _resetScreensaverTimer();
  }

  void _recalcularHoraFin() {
    if (_totalDuration.inSeconds <= 0) {
      _horaFinEstimada = '';
      return;
    }
    final restante = _totalDuration - _currentPosition;
    if (restante <= Duration.zero) {
      _horaFinEstimada = '';
      return;
    }
    final fin = DateTime.now().add(restante);
    _horaFinEstimada =
        '${fin.hour.toString().padLeft(2, '0')}:${fin.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildVideoSurface() {
    if (!_controllerReady || !_controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    final vw = _controller.value.size.width;
    final vh = _controller.value.size.height;
    if (vw <= 0 || vh <= 0) {
      return const ColoredBox(color: Colors.black);
    }

    final forced = _forcedAspectRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        if (maxW <= 0 || maxH <= 0) {
          return const ColoredBox(color: Colors.black);
        }

        if (forced == null) {
          final videoAspect = vw / vh;
          late final double w;
          late final double h;
          if (maxW / maxH > videoAspect) {
            h = maxH;
            w = h * videoAspect;
          } else {
            w = maxW;
            h = w / videoAspect;
          }
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: SizedBox(
                width: w,
                height: h,
                child: VideoPlayer(_controller),
              ),
            ),
          );
        }

        late final double frameW;
        late final double frameH;
        if (maxW / maxH > forced) {
          frameH = maxH;
          frameW = frameH * forced;
        } else {
          frameW = maxW;
          frameH = frameW / forced;
        }

        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: SizedBox(
              width: frameW,
              height: frameH,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: vw,
                  height: vh,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _showSeasonsAndEpisodes => _currentRow >= 3;

  List<FocusNode> get _visibleActionNodes {
    final list = <FocusNode>[_playPauseFocusNode, _restartFocusNode];
    if (widget.tipo == 'tv' ||
        (_showEndPrompt && _recomendaciones.isNotEmpty)) {
      list.add(_nextFocusNode);
    }
    list.addAll([
      _serversFocusNode,
      _qualityFocusNode,
      _fitFocusNode,
      _infoFocusNode,
    ]);
    return list;
  }

  bool get _showNextButton =>
      widget.tipo == 'tv' || (_showEndPrompt && _recomendaciones.isNotEmpty);

  int _lastPositionUpdateMs = 0;
  static const int _positionThrottleMs = 250;

  bool _showEndPrompt = false;
  bool _hasHandledEnd = false;
  bool _showNextEpisodeCard = false;
  bool _nextPromptUserDismissed = false; // <-- FALTA ESTO
  double? _introStartSec;
  double? _introEndSec;
  double? _outroStartSec;
  double? _outroEndSec;
  bool _showSkipIntro = false;
  final FocusNode _skipIntroFocusNode = FocusNode();

  double _nextThresholdPct = 0.95;

  Map<String, int> _episodeProgress = {};
  Map<String, int> _recoProgress = {};

  String _getCacheKey() {
    if (widget.tipo == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'cachePlayer_${widget.idcontenido}_T${widget.temporada}_C${widget.capitulo}';
    }
    return 'cachePlayer_${widget.idcontenido}';
  }

  String _getCacheKeyRapido() {
    if (widget.tipo == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'cachePlayerRapido_${widget.idcontenido}_T${widget.temporada}_C${widget.capitulo}';
    }
    return 'cachePlayerRapido_${widget.idcontenido}';
  }

  String _optimizeTmdbUrl(String? url, {String size = 'w500'}) {
    if (url == null || url.isEmpty) return '';
    if (url.contains('image.tmdb.org/t/p/')) {
      return url.replaceFirstMapped(
        RegExp(r'/t/p/(original|w\d+|h\d+)/'),
        (m) => '/t/p/$size/',
      );
    }
    return url;
  }

  @override
  void initState() {
    super.initState();
    _actionNodes = [
      _playPauseFocusNode,
      _restartFocusNode,
      _nextFocusNode,
      _serversFocusNode,
      _qualityFocusNode,
      _fitFocusNode,
      _infoFocusNode,
    ];
    if (widget.idioma != null && widget.idioma!.isNotEmpty) {
      _idioma = widget.idioma!.toUpperCase();
    }
    _servidorUrl = widget.servidorUrl;
    _servidorNombre = widget.servidorNombre;
    _forceLandscape();
    _keepScreenOn();
    _startClock();
    _preloadServidores();
    _loadApiData().then((_) {
      _initializePlayer();
    });
    _loadNextThresholdPref();
    FocusManager.instance.addListener(_onGlobalFocusChanged);
    _startCacheTimer();
    _resetScreensaverTimer();
  }

  void _preloadServidores() {
    try {
      ServidoresPreloader.preload(
        idcontenido: widget.idcontenido,
        tipo: widget.tipo,
        temporada: widget.temporada,
        capitulo: widget.capitulo,
      );
    } catch (_) {}
  }

  void _startClock() {
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isDisposing) _updateClock();
    });
  }

  void _updateClock() {
    final now = DateTime.now();
    final formatted =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (formatted != _currentTime) {
      setState(() => _currentTime = formatted);
    }
  }

  void _startCacheTimer() {
    _cacheTimer?.cancel();
    _cacheTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isDisposing && _controllerReady) {
        _saveCache();
      }
    });
  }

  void _resetScreensaverTimer() {
    _screensaverTimer?.cancel();
    if (_showScreensaver && mounted && !_isDisposing) {
      setState(() => _showScreensaver = false);
    }
    _screensaverTimer = Timer(const Duration(minutes: 1), () {
      if (!mounted || _isDisposing || _isDragging) return;
      if (!_isPlaying) {
        setState(() => _showScreensaver = true);
      }
    });
  }

  Future<void> _saveCache() async {
    if (!_controllerReady || !_controller.value.isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    final pos = _controller.value.position.inSeconds;

    String? backdrop;
    if (_apiData != null) {
      final b = _apiData!['backdrop'] ?? _apiData!['backdrop_path'];
      if (b is String && b.isNotEmpty) {
        backdrop = _optimizeTmdbUrl(b, size: 'w780');
      }
    }
    backdrop ??= _backdropUrl;

    final full = {
      'idcontenido': widget.idcontenido,
      'temporada': widget.temporada,
      'capitulo': widget.capitulo,
      'segundo': pos,
      'titulo': _tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo,
      'tipo': widget.tipo,
      'videoUrl': widget.videoUrl,
      'poster': backdrop ?? '',
      'backdrop': backdrop ?? '',
      'timestamp': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_getCacheKey(), jsonEncode(full));

    final rapido = {
      'idcontenido': widget.idcontenido,
      'temporada': widget.temporada,
      'capitulo': widget.capitulo,
      'segundo': pos,
    };
    await prefs.setString(_getCacheKeyRapido(), jsonEncode(rapido));
  }

  Future<int?> _getSavedPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_getCacheKeyRapido());
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      return data['segundo'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadEpisodeProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, int>{};
      for (final temp in _temporadas) {
        final tNum = temp['numero'];
        final caps = temp['capitulos'] as List? ?? [];
        for (final cap in caps) {
          final cNum = cap['numero'];
          final key =
              'cachePlayerRapido_${widget.idcontenido}_T${tNum}_C$cNum';
          final raw = prefs.getString(key);
          if (raw != null) {
            try {
              final data = jsonDecode(raw);
              final sec = data['segundo'] as int?;
              if (sec != null && sec > 5) {
                map['T${tNum}_C$cNum'] = sec;
              }
            } catch (_) {}
          }
        }
      }
      if (mounted && !_isDisposing) {
        setState(() => _episodeProgress = map);
      }
    } catch (e) {
      debugPrint('Error cargando progreso capítulos: $e');
    }
  }

  Future<void> _loadRecoProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, int>{};
      for (final rec in _recomendaciones) {
        final id = rec['idcontenido'];
        if (id == null) continue;
        final key = 'cachePlayerRapido_$id';
        final raw = prefs.getString(key);
        if (raw != null) {
          try {
            final data = jsonDecode(raw);
            final sec = data['segundo'] as int?;
            if (sec != null && sec > 5) {
              map['id_$id'] = sec;
            }
          } catch (_) {}
        }
      }
      if (mounted && !_isDisposing) {
        setState(() => _recoProgress = map);
      }
    } catch (_) {}
  }

  int _getFocusEpisodeIndex() {
    if (_temporadas.isEmpty) return 0;
    final caps = _temporadas[_selectedSeasonIndex]['capitulos'] as List? ?? [];
    if (caps.isEmpty) return 0;
    final seasonNum = _temporadas[_selectedSeasonIndex]['numero'];
    if (widget.temporada != null &&
        seasonNum == widget.temporada &&
        widget.capitulo != null) {
      final idx = caps.indexWhere((c) => c['numero'] == widget.capitulo);
      if (idx >= 0) return idx;
    }
    return 0;
  }

  Future<void> _loadApiData() async {
    try {
      final int tmdbId = widget.tmdbId ?? widget.idcontenido;
      final String mediaType =
          widget.tipo.toLowerCase() == 'tv' ? 'tv' : 'movie';

      final service = TmdbPlayerService();
      final data = await service.fetchPlayer(
        tmdbId: tmdbId,
        mediaType: mediaType,
        temporada: widget.temporada ?? 0,
        capitulo: widget.capitulo ?? 0,
      );

      if (!mounted || _isDisposing) return;
      if (data['error'] == true) return;

      setState(() {
        _apiData = data;
        _logoUrl = data['logo']?.toString();
        _backdropUrl = data['backdrop']?.toString();
        _tituloContenido =
            data['titulo_contenido']?.toString() ?? widget.titulo;
        _tituloCapitulo = data['titulo_capitulo']?.toString();
        _capituloFmt = data['capitulo']?.toString();

        _temporadas = data['temporadas'] is List
            ? List<Map<String, dynamic>>.from(data['temporadas'])
            : [];

        _siguiente = data['siguiente'] is Map
            ? Map<String, dynamic>.from(data['siguiente'])
            : null;

        final recoApi =
            data['recomendaciones'] is List ? data['recomendaciones'] as List : [];

        if (recoApi.isNotEmpty) {
          _recomendaciones = recoApi.map((e) {
            final item = Map<String, dynamic>.from(e as Map);
            return <String, dynamic>{
              'idcontenido':
                  item['idcontenido'] ?? item['tmdb_id'] ?? item['idtmdb'],
              'titulo': item['titulo'] ?? item['title'] ?? '',
              'poster': item['poster']?.toString() ?? '',
              'backdrop': item['backdrop']?.toString() ?? '',
              'logo': item['logo']?.toString(),
              'tipo': item['tipo'] ?? item['media_type'] ?? 'movie',
            };
          }).toList();
          _rebuildRecoFocusNodes();
        }

        if (widget.temporada != null && _temporadas.isNotEmpty) {
          final idx =
              _temporadas.indexWhere((t) => t['numero'] == widget.temporada);
          if (idx >= 0) _selectedSeasonIndex = idx;
        }

        _rebuildSeasonFocusNodes();
        _rebuildEpisodeFocusNodes();
      });

      _loadIntroSkip();
      _loadEpisodeProgress();
      if (_recomendaciones.isNotEmpty) _loadRecoProgress();
    } catch (e, st) {
      debugPrint('Error cargando TMDB Player: $e\n$st');
    }
  }

  Future<void> _loadIntroSkip() async {
    try {
      final imdb = (_apiData?['imdb_id'] ?? '').toString().trim();
      if (imdb.isEmpty) return;

      final season = widget.temporada ?? _apiData?['temporada'];
      final episode = widget.capitulo ?? _apiData?['numero_capitulo'];

      final params = <String, String>{'imdb_id': imdb};
      if (season != null) params['season'] = season.toString();
      if (episode != null) params['episode'] = episode.toString();

      final uri = Uri.https('api.introdb.app', '/segments', params);
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || !mounted || _isDisposing) return;

      final data = jsonDecode(res.body);
      final intro = data['intro'];
      final outro = data['outro'];

      double? introStart, introEnd, outroStart, outroEnd;

      if (intro is Map) {
        final start = intro['start_sec'];
        final end = intro['end_sec'];
        if (start != null && end != null) {
          introStart = (start as num).toDouble();
          introEnd = (end as num).toDouble();
        }
      }
      if (outro is Map) {
        final start = outro['start_sec'];
        final end = outro['end_sec'];
        if (start != null) outroStart = (start as num).toDouble();
        if (end != null) outroEnd = (end as num).toDouble();
      }

      if (mounted && !_isDisposing) {
        setState(() {
          _introStartSec = introStart;
          _introEndSec = introEnd;
          _outroStartSec = outroStart;
          _outroEndSec = outroEnd;
        });
      }
    } catch (e) {
      debugPrint('Error intro skip: $e');
    }
  }

  Future<void> _loadNextThresholdPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getDouble(_prefNextThresholdPctKey);
      if (cached != null && cached > 0 && cached < 1) {
        if (mounted && !_isDisposing) {
          setState(() => _nextThresholdPct = cached);
        } else {
          _nextThresholdPct = cached;
        }
      }
    } catch (_) {}
  }

  void _updateSkipIntroVisibility() {
    if (_introStartSec == null || _introEndSec == null) {
      if (_showSkipIntro) _showSkipIntro = false;
      return;
    }
    final pos = _currentPosition.inMilliseconds / 1000.0;
    final visible = pos >= _introStartSec! && pos <= _introEndSec!;
    if (visible != _showSkipIntro) {
      _showSkipIntro = visible;
      if (visible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposing && _showSkipIntro) {
            _skipIntroFocusNode.requestFocus();
          }
        });
      } else if (_skipIntroFocusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposing) {
            if (_showControls) {
              _seekBarFocusNode.requestFocus();
            } else {
              _videoFocusNode.requestFocus();
            }
          }
        });
      }
    }
  }

  void _skipIntro() {
    if (_introEndSec == null || !_controllerReady) return;
    final target = Duration(milliseconds: (_introEndSec! * 1000).round());
    _controller.seekTo(target);
    setState(() => _showSkipIntro = false);
    _scheduleHideControls();
  }

  void _startSeekHold(int direction) {
    _stopSeekHold();
    _seekHoldDirection = direction;
    _seekHoldTicks = 0;
    _seekStep(direction);
    _seekHoldTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _isDisposing || !_controllerReady) {
        _stopSeekHold();
        return;
      }
      _seekHoldTicks++;
      int seconds;
      if (_seekHoldTicks >= 20) {
        seconds = 30;
      } else if (_seekHoldTicks >= 10) {
        seconds = 15;
      } else if (_seekHoldTicks >= 4) {
        seconds = 5;
      } else {
        seconds = 2;
      }
      final delta = Duration(seconds: seconds * _seekHoldDirection);
      var newPos = _currentPosition + delta;
      if (newPos < Duration.zero) newPos = Duration.zero;
      if (newPos > _totalDuration) newPos = _totalDuration;
      _controller.seekTo(newPos);
      _resetScreensaverTimer();
    });
  }

  void _seekStep(int direction) {
    final delta = Duration(seconds: 10 * direction);
    var newPos = _currentPosition + delta;
    if (newPos < Duration.zero) newPos = Duration.zero;
    if (newPos > _totalDuration) newPos = _totalDuration;
    _controller.seekTo(newPos);
    _scheduleHideControls();
    _resetScreensaverTimer();
  }

  void _stopSeekHold() {
    _seekHoldTimer?.cancel();
    _seekHoldTimer = null;
    _seekHoldDirection = 0;
    _seekHoldTicks = 0;
  }

  void _rebuildSeasonFocusNodes() {
    for (final n in _seasonFocusNodes) {
      n.dispose();
    }
    _seasonFocusNodes
      ..clear()
      ..addAll(List.generate(_temporadas.length, (_) => FocusNode()));
  }

  void _rebuildEpisodeFocusNodes() {
    for (final n in _episodeFocusNodes) {
      n.dispose();
    }
    _episodeFocusNodes.clear();
    if (_temporadas.isNotEmpty) {
      final caps =
          _temporadas[_selectedSeasonIndex]['capitulos'] as List? ?? [];
      _episodeFocusNodes.addAll(List.generate(caps.length, (_) => FocusNode()));
    }
  }

  void _rebuildRecoFocusNodes() {
    for (final n in _recoFocusNodes) {
      n.dispose();
    }
    _recoFocusNodes
      ..clear()
      ..addAll(List.generate(_recomendaciones.length, (_) => FocusNode()));
  }

  void _forceLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _keepScreenOn() => WakelockPlus.enable();

  Future<void> _initializePlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      await _controller.initialize();

      if (!mounted || _isDisposing) {
        await _controller.dispose();
        return;
      }

      _controller.addListener(_videoListener);
      _controllerReady = true;

      final saved = await _getSavedPosition();
      if (saved != null && saved > 5) {
        await _controller.seekTo(Duration(seconds: saved));
      }

      if (!mounted || _isDisposing) return;
      setState(() {
        _isLoading = false;
        _totalDuration = _controller.value.duration;
        _errorMessage = '';
        _recalcularHoraFin();
      });
      _controller.play();
      setState(() => _isPlaying = true);
      _resetScreensaverTimer();
    } catch (e) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposing) {
          _errorServersFocusNode.requestFocus();
        }
      });
    }
  }

  bool _isNextTriggerReached() {
    if (_totalDuration.inSeconds <= 0) return false;
    if (_outroStartSec != null) {
      final pos = _currentPosition.inMilliseconds / 1000.0;
      return pos >= _outroStartSec!;
    }
    final progress =
        _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
    return progress >= _nextThresholdPct;
  }

  void _videoListener() {
    if (!mounted || _isDisposing) return;

    final value = _controller.value;
    final nowMs = value.position.inMilliseconds;
    final shouldUpdatePosition = _isDragging ||
        (nowMs - _lastPositionUpdateMs).abs() >= _positionThrottleMs;

    final newPlaying = value.isPlaying;
    final newBuffering = value.isBuffering;
    final newDuration = value.duration;
    final pos = value.position;
    final dur = value.duration;
    bool needsSetState = false;

   if (shouldUpdatePosition) {
  _currentPosition = value.position;
  _lastPositionUpdateMs = nowMs;
  final prevSkip = _showSkipIntro;
  _updateSkipIntroVisibility();
  if (prevSkip != _showSkipIntro) needsSetState = true;
  needsSetState = true;

  if (_totalDuration.inSeconds > 30) {
    final remaining = _totalDuration - _currentPosition;
    final nextTrigger =
        _isNextTriggerReached() && remaining > const Duration(seconds: 2);

    final shouldShowCard = nextTrigger &&
        (_siguiente != null || _recomendaciones.isNotEmpty) &&
        !_nextPromptUserDismissed &&
        !_showBecauseYouWatched;

    if (shouldShowCard != _showNextEpisodeCard) {
      _showNextEpisodeCard = shouldShowCard;
      needsSetState = true;
      if (shouldShowCard) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposing && _showNextEpisodeCard) {
            _nextPromptFocusNode.requestFocus();
          }
        });
      } else if (_nextPromptFocusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposing) {
            if (_showControls) {
              _seekBarFocusNode.requestFocus();
            } else {
              _videoFocusNode.requestFocus();
            }
          }
        });
      }
    }

    if (widget.tipo == 'movie' &&
        !_hasShownBecauseYouWatched &&
        nextTrigger &&
        remaining > const Duration(seconds: 2) &&
        _recomendaciones.isNotEmpty) {
      _hasShownBecauseYouWatched = true;
      _showBecauseYouWatched = true;
      _showNextEpisodeCard = false;
      needsSetState = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposing && _showBecauseYouWatched) {
          _byProducirSiguienteFocusNode.requestFocus();
        }
      });
    }

    final nearEnd = nextTrigger;
    if (nearEnd != _showEndPrompt) {
      _showEndPrompt = nearEnd;
      needsSetState = true;
    }

    if (!_hasHandledEnd &&
        _currentPosition >= _totalDuration - const Duration(seconds: 1)) {
      _hasHandledEnd = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposing) _handleVideoEnded();
      });
    }
  }
}

    if (newPlaying != _isPlaying) {
      _isPlaying = newPlaying;
      needsSetState = true;
      if (newPlaying) _resetScreensaverTimer();
    }
    if (newBuffering != _isBuffering) {
      _isBuffering = newBuffering;
      needsSetState = true;
    }
    if (newDuration != _totalDuration) {
      _totalDuration = newDuration;
      needsSetState = true;
    }

    if (needsSetState) setState(() {});
    if (dur.inSeconds > 10 && pos.inSeconds >= dur.inSeconds - 3) {
      _saveCache();
    }
  }

  bool _isControlFocused() {
    return _actionNodes.any((n) => n.hasFocus) ||
        _seekBarFocusNode.hasFocus ||
        _skipIntroFocusNode.hasFocus ||
        _nextPromptFocusNode.hasFocus ||
        _byProducirSiguienteFocusNode.hasFocus ||
        _byContinuarCreditosFocusNode.hasFocus ||
        _seasonFocusNodes.any((n) => n.hasFocus) ||
        _episodeFocusNodes.any((n) => n.hasFocus) ||
        _recoFocusNodes.any((n) => n.hasFocus);
  }

  bool _hasPermanentFocusSession() {
    return _showSkipIntro ||
        _showNextEpisodeCard ||
        _showSeasonsAndEpisodes ||
        _seasonFocusNodes.any((n) => n.hasFocus) ||
        _episodeFocusNodes.any((n) => n.hasFocus) ||
        _recoFocusNodes.any((n) => n.hasFocus) ||
        _skipIntroFocusNode.hasFocus ||
        _nextPromptFocusNode.hasFocus;
  }

  // ========== CAMBIO PRINCIPAL: YA NO SE OCULTAN AUTOMÁTICAMENTE ==========
  void _onGlobalFocusChanged() {
    if (!mounted || _isDisposing) return;
    // Ya no llamamos a _scheduleHideControls()
    _resetScreensaverTimer();
  }

  void _scheduleHideControls() {
    // Desactivado completamente: los controles NO se ocultan solos
    _hideControlsTimer?.cancel();
  }

  void _scheduleHideToolbarOnly() {
    // Desactivado también
    _hideToolbarOnlyTimer?.cancel();
  }
  // ========================================================================

  void _showControlsOverlayNow() {
    setState(() {
      _showControls = true;
      _showToolbarOnly = false;
      _currentRow = 1;
      _showScreensaver = false;
      _recalcularHoraFin();
    });
    _hideToolbarOnlyTimer?.cancel();
    _seekBarFocusNode.requestFocus();
    _scheduleHideControls();
    _resetScreensaverTimer();
  }

  void _showToolbarOnlyNow() {
    if (!_showToolbarOnly) {
      setState(() {
        _showToolbarOnly = true;
        _currentRow = 2;
      });
    }
    final nodes = _visibleActionNodes;
    final target = _lastFocusedActionNode != null &&
            nodes.contains(_lastFocusedActionNode)
        ? _lastFocusedActionNode!
        : (nodes.isNotEmpty ? nodes.first : _playPauseFocusNode);
    target.requestFocus();
    _scheduleHideToolbarOnly();
    _resetScreensaverTimer();
  }

  void _handleBackPressed() {
    if (_showScreensaver) {
      setState(() => _showScreensaver = false);
      _resetScreensaverTimer();
      return;
    }
    if (_showToolbarOnly) {
      _hideToolbarOnlyTimer?.cancel();
      setState(() {
        _showToolbarOnly = false;
        _currentRow = 0;
      });
      _videoFocusNode.requestFocus();
      return;
    }
    if (_showControls) {
      if (_currentRow >= 3) {
        setState(() => _currentRow = 2);
        _playPauseFocusNode.requestFocus();
      } else {
        _hideControlsTimer?.cancel();
        setState(() {
          _showControls = false;
          _currentRow = 0;
        });
        _videoFocusNode.requestFocus();
      }
    } else {
      _showExitConfirmation();
    }
  }

  bool _isBackKey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack;
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    _scheduleHideControls();
    _resetScreensaverTimer();
  }

  void _restart() {
    _controller.seekTo(Duration.zero);
    _controller.play();
    _scheduleHideControls();
    _resetScreensaverTimer();
  }

  /// Modal de servidores: usa **ServidoresModalFuentesTv**
  Future<void> _openServersModal({
    int? idcontenido,
    int? temporada,
    int? capitulo,
    String? titulo,
    String? tipo,
    String? backdropUrl,
    String? logoUrl,
    bool clearCurrentServer = false,
  }) async {
    _hideControlsTimer?.cancel();
    await _saveCache();

    final wasPlaying = _isPlaying;
    if (_isPlaying) _controller.pause();

    final targetId = idcontenido ?? widget.idcontenido;
    final isSameContent = targetId == widget.idcontenido &&
        (temporada == null || temporada == widget.temporada) &&
        (capitulo == null || capitulo == widget.capitulo);
    final isNext = !isSameContent;

    final modalTitulo = (titulo != null && titulo.isNotEmpty)
        ? titulo
        : (_tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo);

    final fuente = _resolvedFuente;
    if (fuente.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay fuente para buscar servidores'),
            backgroundColor: Color(0xFF1C1C1E),
          ),
        );
      }
      if (mounted && !_isDisposing && wasPlaying) {
        _controller.play();
        _scheduleHideControls();
      }
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => ServidoresModalFuentesTv(
        tmdbId: targetId,
        idcontenido: targetId,
        tipo: tipo ?? widget.tipo,
        temporada: isSameContent ? (temporada ?? widget.temporada) : temporada,
        capitulo: isSameContent ? (capitulo ?? widget.capitulo) : capitulo,
        fuente: fuente,
        titulo: modalTitulo,
        fromPlayer: true,
        esSiguienteCapitulo: isNext && (tipo ?? widget.tipo) == 'tv',
        backdropUrl: backdropUrl ?? (isSameContent ? _backdropUrl : null),
        logoUrl: logoUrl ?? (isSameContent ? _logoUrl : null),
        currentServidorUrl:
            (isSameContent && !clearCurrentServer) ? _servidorUrl : null,
      ),
    );

    if (mounted && !_isDisposing && wasPlaying) {
      _controller.play();
      _scheduleHideControls();
    }
  }

  void _openInfoModal() {
    _hideControlsTimer?.cancel();
    _lastFocusedActionNode = _infoFocusNode;
    _controlsWereShowingBeforeModal = _showControls;
    ModalInformacion.show(
      context: context,
      apiData: _apiData,
      tituloContenido: _tituloContenido,
      tituloCapitulo: _tituloCapitulo,
      capituloFmt: _capituloFmt,
      tipo: widget.tipo,
      accentColor: accentOrange,
      optimizeTmdbUrl: _optimizeTmdbUrl,
    ).then((_) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _showControls = true;
        _currentRow = 2;
        _recalcularHoraFin();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposing) return;
        _infoFocusNode.requestFocus();
        _scheduleHideControls();
      });
    });
  }

  void _openActoresModal() {
    _hideControlsTimer?.cancel();
    final currentFocused = _visibleActionNodes
        .cast<FocusNode?>()
        .firstWhere((n) => n != null && n.hasFocus, orElse: () => null);
    _lastFocusedActionNode = currentFocused ?? _lastFocusedActionNode;
    _controlsWereShowingBeforeModal = _showControls;
    final imdb = (_apiData?['imdb_id'] ?? '').toString();
    final tmdbId = _apiData?['idtmdb'] as int? ??
        _apiData?['tmdb_id'] as int? ??
        widget.idcontenido;
    ModalActores.show(
      context: context,
      imdbId: imdb.isNotEmpty ? imdb : null,
      tmdbId: tmdbId,
      tipo: widget.tipo,
      accentColor: accentOrange,
    ).then((_) {
      if (!mounted || _isDisposing) return;
      if (_controlsWereShowingBeforeModal) {
        setState(() {
          _showControls = true;
          _currentRow = 2;
          _recalcularHoraFin();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isDisposing) return;
          (_lastFocusedActionNode ?? _playPauseFocusNode).requestFocus();
          _scheduleHideControls();
        });
      } else {
        _scheduleHideControls();
        _videoFocusNode.requestFocus();
      }
    });
  }

  Future<void> _openQualitySelector() async {
    _hideControlsTimer?.cancel();

    final selected = await HlsQualitySelectorModal.show(
      context,
      masterUrl: widget.videoUrl,
      currentQualityUrl: _currentQualityUrl,
      currentQualityLabel: _currentQualityLabel,
      accentColor: accentOrange,
    );

    if (selected == null || !mounted || _isDisposing) {
      if (mounted && !_isDisposing) {
        setState(() {
          _showControls = true;
          _currentRow = 2;
          _recalcularHoraFin();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isDisposing) return;
          final nodes = _visibleActionNodes;
          final qi = nodes.indexOf(_qualityFocusNode);
          _currentCol = qi >= 0 ? qi : 0;
          if (qi >= 0) {
            _qualityFocusNode.requestFocus();
          } else if (nodes.isNotEmpty) {
            nodes[0].requestFocus();
          }
          _scheduleHideControls();
        });
      }
      return;
    }

    final currentUrl = _currentQualityUrl ?? widget.videoUrl;
    if (selected.url == currentUrl) {
      setState(() {
        _showControls = true;
        _currentRow = 2;
        _recalcularHoraFin();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposing) return;
        final nodes = _visibleActionNodes;
        final qi = nodes.indexOf(_qualityFocusNode);
        _currentCol = qi >= 0 ? qi : 0;
        if (qi >= 0) {
          _qualityFocusNode.requestFocus();
        } else if (nodes.isNotEmpty) {
          nodes[0].requestFocus();
        }
        _scheduleHideControls();
      });
      return;
    }

    final savedPos =
        _controllerReady ? _controller.value.position : Duration.zero;

    await _saveCache();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _currentQualityLabel = selected.label;
      _currentQualityUrl = selected.isAuto ? null : selected.url;
      _hasHandledEnd = false;
      _showEndPrompt = false;
      _showNextEpisodeCard = false;
    });

    try {
      if (_controllerReady) {
        _controller.removeListener(_videoListener);
        try {
          await _controller.pause();
        } catch (_) {}
      }
      await _controller.dispose();
    } catch (_) {}
    _controllerReady = false;

    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(selected.url));
      await _controller.initialize();

      if (!mounted || _isDisposing) {
        await _controller.dispose();
        return;
      }

      _controller.addListener(_videoListener);
      _controllerReady = true;

      if (savedPos > const Duration(seconds: 2)) {
        await _controller.seekTo(savedPos);
      }

      if (!mounted || _isDisposing) return;

      setState(() {
        _isLoading = false;
        _totalDuration = _controller.value.duration;
        _currentPosition = savedPos;
        _showControls = true;
        _currentRow = 2;
        _recalcularHoraFin();
      });

      await _controller.play();
      setState(() => _isPlaying = true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposing) return;
        final nodes = _visibleActionNodes;
        final qi = nodes.indexOf(_qualityFocusNode);
        if (qi >= 0) {
          _currentCol = qi;
          _qualityFocusNode.requestFocus();
        } else if (nodes.isNotEmpty) {
          _currentCol = 0;
          nodes[0].requestFocus();
        }
        _scheduleHideControls();
      });
    } catch (e) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cambiar calidad: $e';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposing) {
          _errorServersFocusNode.requestFocus();
        }
      });
    }
  }

  void _goNextEpisode() {
    if (widget.tipo == 'tv') {
      if (_siguiente == null) return;
      _openServersModal(
        temporada: _siguiente!['temporada'],
        capitulo: _siguiente!['capitulo'],
      );
    } else {
      if (_recomendaciones.isEmpty) return;
      final next = _recomendaciones.first;
      _openServersModal(
        idcontenido: next['idcontenido'] as int?,
        titulo: (next['titulo'] ?? next['title'] ?? '').toString(),
        tipo: (next['tipo'] ?? 'movie').toString(),
        backdropUrl: (next['backdrop'] ?? next['poster'])?.toString(),
        logoUrl: next['logo']?.toString(),
        clearCurrentServer: true,
      );
    }
  }

  void _handleVideoEnded() {
    if (!mounted || _isDisposing) return;
    _goNextEpisode();
  }

  Future<void> _showExitConfirmation() async {
    final wasPlaying = _isPlaying;
    if (_isPlaying) _controller.pause();

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlg) {
            Widget actionBtn({
              required FocusNode node,
              required String label,
              required bool isExit,
              required VoidCallback onTap,
              bool autofocus = false,
            }) {
              return Focus(
                focusNode: node,
                autofocus: autofocus,
                onFocusChange: (_) => setDlg(() {}),
                onKeyEvent: (n, e) {
                  if (e is! KeyDownEvent) return KeyEventResult.ignored;
                  if (e.logicalKey == LogicalKeyboardKey.arrowRight &&
                      !isExit) {
                    _exitConfirmFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.arrowLeft && isExit) {
                    _exitContinueFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.select ||
                      e.logicalKey == LogicalKeyboardKey.enter) {
                    onTap();
                    return KeyEventResult.handled;
                  }
                  if (_isBackKey(e)) {
                    Navigator.pop(context, false);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (ctx) {
                    final hasFocus = Focus.of(ctx).hasFocus;
                    return GestureDetector(
                      onTap: onTap,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: hasFocus
                              ? netflixRed
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasFocus ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: hasFocus ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.exit_to_app_rounded,
                      color: Colors.redAccent, size: 26),
                  SizedBox(width: 10),
                  Text(
                    '¿Salir del reproductor?',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
              content: Text(
                'Se guardará el progreso actual.',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              actions: [
                actionBtn(
                  node: _exitContinueFocusNode,
                  label: 'Continuar',
                  isExit: false,
                  autofocus: true,
                  onTap: () => Navigator.pop(context, false),
                ),
                actionBtn(
                  node: _exitConfirmFocusNode,
                  label: 'Salir',
                  isExit: true,
                  onTap: () => Navigator.pop(context, true),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm == true) {
      await _saveCache();
      _goBackToContent();
    } else if (mounted && !_isDisposing && wasPlaying) {
      _controller.play();
      _scheduleHideControls();
    }
  }

  void _goBackToContent() {
    _restoreOrientation();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  String _idiomaFlagUrl() {
    final c = _idioma.toLowerCase().trim();
    if (c.contains('lat') || c == 'es' || c.contains('mx')) {
      return 'https://embed69.org/static/lang/LAT.png';
    }
    if (c.contains('esp') || c.contains('castellano') || c.contains('es_es')) {
      return 'https://embed69.org/static/lang/ESP.png';
    }
    return 'https://embed69.org/static/lang/SUB.png';
  }

  String _idiomaLabel() {
    final c = _idioma.toLowerCase().trim();
    if (c.contains('lat') || c == 'es' || c.contains('mx')) return 'Latino';
    if (c.contains('esp') || c.contains('castellano')) return 'Castellano';
    return 'Subtitulado';
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
    }
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  String? _episodeCodeLabel() {
    if (_capituloFmt != null && _capituloFmt!.isNotEmpty) return _capituloFmt;
    if (widget.temporada != null && widget.capitulo != null) {
      return 'S${widget.temporada.toString().padLeft(2, '0')}E${widget.capitulo.toString().padLeft(2, '0')}';
    }
    return null;
  }

  String _nextPromptTitle() {
    if (widget.tipo == 'tv' && _siguiente != null) {
      final t = _siguiente!['temporada'];
      final c = _siguiente!['capitulo'];
      final name =
          _siguiente!['titulo'] ?? _siguiente!['titulo_capitulo'] ?? '';
      final s = t != null ? 'S${t.toString().padLeft(2, '0')}' : '';
      final e = c != null ? 'E${c.toString().padLeft(2, '0')}' : '';
      if (name.toString().isNotEmpty) return '$s$e · $name';
      return '$s $e'.trim();
    }
    if (_recomendaciones.isNotEmpty) {
      return (_recomendaciones.first['titulo'] ?? '').toString();
    }
    return 'Siguiente';
  }

  String? _nextPromptThumb() {
    if (widget.tipo == 'tv' && _siguiente != null) {
      return (_siguiente!['backdrop'] ?? _siguiente!['poster'])?.toString();
    }
    if (_recomendaciones.isNotEmpty) {
      final r = _recomendaciones.first;
      return (r['backdrop'] ?? r['poster'])?.toString();
    }
    return _backdropUrl;
  }

  void _moveFocusDown() {
    if (_nextPromptFocusNode.hasFocus) {
      setState(() {
        _showControls = true;
        _currentRow = 1;
        _recalcularHoraFin();
      });
      _seekBarFocusNode.requestFocus();
      _scheduleHideControls();
      return;
    }

    if (_currentRow == 0) {
      _showControlsOverlayNow();
    } else if (_currentRow == 1) {
      setState(() => _currentRow = 2);
      _currentCol = 0;
      final nodes = _visibleActionNodes;
      if (nodes.isNotEmpty) {
        nodes[0].requestFocus();
      } else {
        _playPauseFocusNode.requestFocus();
      }
    } else if (_currentRow == 2) {
      if (widget.tipo == 'tv' && _temporadas.isNotEmpty) {
        setState(() => _currentRow = 3);
        if (_seasonFocusNodes.isNotEmpty) {
          _seasonFocusNodes[_selectedSeasonIndex].requestFocus();
          _scrollToFocus(_seasonScrollController, _selectedSeasonIndex, 120);
        }
      }
    } else if (_currentRow == 3) {
      setState(() => _currentRow = 4);
      if (_episodeFocusNodes.isNotEmpty) {
        final idx = _getFocusEpisodeIndex();
        _episodeFocusNodes[idx].requestFocus();
        _scrollToFocus(_episodeScrollController, idx, 170);
      }
    }
  }

  void _moveFocusUp() {
    if (_currentRow == 2) {
      setState(() {
        _showControls = true;
        _showToolbarOnly = false;
        _currentRow = 1;
        _recalcularHoraFin();
      });
      _hideToolbarOnlyTimer?.cancel();
      _seekBarFocusNode.requestFocus();
      _scheduleHideControls();
      return;
    }
    if (_currentRow == 4) {
      setState(() => _currentRow = 3);
      if (_seasonFocusNodes.isNotEmpty) {
        _seasonFocusNodes[_selectedSeasonIndex].requestFocus();
        _scrollToFocus(_seasonScrollController, _selectedSeasonIndex, 120);
      }
    } else if (_currentRow == 3) {
      setState(() {
        _currentRow = 2;
        _currentCol = 0;
      });
      _playPauseFocusNode.requestFocus();
    } else if (_currentRow == 1) {
      setState(() {
        _showControls = false;
        _currentRow = 0;
      });
      _videoFocusNode.requestFocus();
    }
  }

  void _moveFocusRight() {
    if (_currentRow == 2 || _actionNodes.any((n) => n.hasFocus)) {
      _currentRow = 2;
      final nodes = _visibleActionNodes;
      if (nodes.isEmpty) return;
      var idx = nodes.indexWhere((n) => n.hasFocus);
      if (idx < 0) idx = _currentCol.clamp(0, nodes.length - 1);
      final next = (idx + 1).clamp(0, nodes.length - 1);
      if (next != idx || !nodes[next].hasFocus) {
        _currentCol = next;
        nodes[next].requestFocus();
        _lastFocusedActionNode = nodes[next];
      }
    } else if (_currentRow == 3 && _seasonFocusNodes.isNotEmpty) {
      final next =
          (_selectedSeasonIndex + 1).clamp(0, _seasonFocusNodes.length - 1);
      setState(() {
        _selectedSeasonIndex = next;
        _rebuildEpisodeFocusNodes();
      });
      _seasonFocusNodes[next].requestFocus();
      _scrollToFocus(_seasonScrollController, next, 120);
    } else if (_currentRow == 4 &&
        widget.tipo == 'tv' &&
        _episodeFocusNodes.isNotEmpty) {
      final idx = _episodeFocusNodes.indexWhere((n) => n.hasFocus);
      final next = (idx + 1).clamp(0, _episodeFocusNodes.length - 1);
      _episodeFocusNodes[next].requestFocus();
      _scrollToFocus(_episodeScrollController, next, 170);
    }
  }

  void _moveFocusLeft() {
    if (!_showControls && !_showToolbarOnly) {
      _showToolbarOnlyNow();
      return;
    }
    if (_currentRow == 2 || _actionNodes.any((n) => n.hasFocus)) {
      _currentRow = 2;
      final nodes = _visibleActionNodes;
      if (nodes.isEmpty) return;
      var idx = nodes.indexWhere((n) => n.hasFocus);
      if (idx < 0) idx = _currentCol.clamp(0, nodes.length - 1);
      final prev = (idx - 1).clamp(0, nodes.length - 1);
      if (prev != idx || !nodes[prev].hasFocus) {
        _currentCol = prev;
        nodes[prev].requestFocus();
        _lastFocusedActionNode = nodes[prev];
      }
    } else if (_currentRow == 3 && _seasonFocusNodes.isNotEmpty) {
      final prev =
          (_selectedSeasonIndex - 1).clamp(0, _seasonFocusNodes.length - 1);
      setState(() {
        _selectedSeasonIndex = prev;
        _rebuildEpisodeFocusNodes();
      });
      _seasonFocusNodes[prev].requestFocus();
      _scrollToFocus(_seasonScrollController, prev, 120);
    } else if (_currentRow == 4 &&
        widget.tipo == 'tv' &&
        _episodeFocusNodes.isNotEmpty) {
      final idx = _episodeFocusNodes.indexWhere((n) => n.hasFocus);
      final prev = (idx - 1).clamp(0, _episodeFocusNodes.length - 1);
      _episodeFocusNodes[prev].requestFocus();
      _scrollToFocus(_episodeScrollController, prev, 170);
    }
  }

  void _scrollToFocus(
    ScrollController controller,
    int index,
    double itemWidth,
  ) {
    if (!controller.hasClients) return;
    final offset = (index * itemWidth) -
        (MediaQuery.sizeOf(context).width / 2) +
        (itemWidth / 2);
    controller.animateTo(
      offset.clamp(0.0, controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _isDisposing = true;
    _hideControlsTimer?.cancel();
    _hideToolbarOnlyTimer?.cancel();
    _clockTimer?.cancel();
    _cacheTimer?.cancel();
    _screensaverTimer?.cancel();
    _fitToastTimer?.cancel();
    _seekHoldTimer?.cancel();
    FocusManager.instance.removeListener(_onGlobalFocusChanged);

    try {
      if (_controllerReady) {
        _controller.removeListener(_videoListener);
        try {
          _controller.pause();
        } catch (_) {}
      }
      _controller.dispose();
    } catch (_) {}

    WakelockPlus.disable();
    _restoreOrientation();

    _skipIntroFocusNode.dispose();
    _nextPromptFocusNode.dispose();
    _errorServersFocusNode.dispose();
    _errorBackFocusNode.dispose();
    _exitContinueFocusNode.dispose();
    _exitConfirmFocusNode.dispose();
    _byProducirSiguienteFocusNode.dispose();
    _byContinuarCreditosFocusNode.dispose();
    _videoFocusNode.dispose();
    _seekBarFocusNode.dispose();
    for (final n in _actionNodes) {
      n.dispose();
    }
    for (final n in _seasonFocusNodes) {
      n.dispose();
    }
    for (final n in _episodeFocusNodes) {
      n.dispose();
    }
    for (final n in _recoFocusNodes) {
      n.dispose();
    }
    _seasonScrollController.dispose();
    _episodeScrollController.dispose();
    _recoScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _videoFocusNode,
          autofocus: _errorMessage.isEmpty,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (_errorMessage.isNotEmpty) {
                if (_isBackKey(event)) {
                  _goBackToContent();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _errorBackFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _errorServersFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  _openServersModal();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }
              if (_isBackKey(event)) {
                _handleBackPressed();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                if (_showScreensaver) {
                  setState(() => _showScreensaver = false);
                }
                _moveFocusDown();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                if (!_showControls && !_showToolbarOnly) {
                  if (_showScreensaver) {
                    setState(() => _showScreensaver = false);
                  }
                  _openActoresModal();
                  return KeyEventResult.handled;
                }
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                if (!_showControls && !_showToolbarOnly) {
                  if (_showScreensaver) {
                    setState(() => _showScreensaver = false);
                  }
                  _showToolbarOnlyNow();
                  return KeyEventResult.handled;
                }
              }
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                if (_showScreensaver) {
                  setState(() => _showScreensaver = false);
                  _resetScreensaverTimer();
                  return KeyEventResult.handled;
                }
                if (_showControls) {
                  _togglePlay();
                } else {
                  _showControlsOverlayNow();
                }
                return KeyEventResult.handled;
              }
              if (_showScreensaver) {
                setState(() => _showScreensaver = false);
                _resetScreensaverTimer();
              }
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Colors.black,
                child: Center(
                  child: _isLoading
                      ? _buildLoadingScreen()
                      : _errorMessage.isNotEmpty
                          ? _buildErrorScreen()
                          : _buildVideoSurface(),
                ),
              ),

              if (_fitToastLabel != null)
                Positioned(
                  top: 72,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        _fitToastLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),

              if (!_isLoading &&
                  _errorMessage.isEmpty &&
                  _showSkipIntro &&
                  !_showBecauseYouWatched)
                Positioned(
                  right: 28,
                  bottom: (_showControls || _showToolbarOnly)
                      ? (_showSeasonsAndEpisodes ? 280.0 : 150.0)
                      : 48.0,
                  child: Focus(
                    focusNode: _skipIntroFocusNode,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          _skipIntro();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          setState(() {
                            _showControls = true;
                            _currentRow = 1;
                            _recalcularHoraFin();
                          });
                          _seekBarFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (_isBackKey(event)) {
                          _handleBackPressed();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final hasFocus = Focus.of(context).hasFocus;
                        return GestureDetector(
                          onTap: _skipIntro,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: hasFocus
                                  ? Colors.white
                                  : Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: hasFocus
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.55),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fast_forward_rounded,
                                  size: 20,
                                  color:
                                      hasFocus ? Colors.black : Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Omitir intro',
                                  style: TextStyle(
                                    color:
                                        hasFocus ? Colors.black : Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              if (!_isLoading &&
                  _errorMessage.isEmpty &&
                  _showNextEpisodeCard &&
                  (_siguiente != null || _recomendaciones.isNotEmpty) &&
                  !_showBecauseYouWatched)
                Positioned(
                  right: 28,
                  bottom: (_showControls || _showToolbarOnly)
                      ? (_showSeasonsAndEpisodes ? 290.0 : 160.0)
                      : 56.0,
                 child: NextEpisodePrompt(
  thumbnailUrl: _nextPromptThumb(),
  titleLine: _nextPromptTitle(),
  subtitleLine: '',
  countdownText: '',
  isTv: widget.tipo == 'tv',
  focusNode: _nextPromptFocusNode,
  visible: _showNextEpisodeCard,
  controlsVisible: _showControls || _showToolbarOnly,
  autoHideMs: 10000,
  onPlay: _goNextEpisode,
  onDismiss: () {
    setState(() {
      _showNextEpisodeCard = false;
      _nextPromptUserDismissed = true;
    });
    _videoFocusNode.requestFocus();
  },
  onAutoHide: () {
    setState(() => _showNextEpisodeCard = false);
    _videoFocusNode.requestFocus();
  },
  onNavigateDown: () {
    setState(() {
      _showControls = true;
      _currentRow = 1;
      _recalcularHoraFin();
    });
    _seekBarFocusNode.requestFocus();
    _scheduleHideControls();
  },
  accentColor: accentOrange,
  optimizeTmdbUrl: _optimizeTmdbUrl,
),
                ),

              if (!_isLoading &&
                  _errorMessage.isEmpty &&
                  _showBecauseYouWatched &&
                  widget.tipo == 'movie' &&
                  _recomendaciones.isNotEmpty)
                BecauseYouWatchedOverlay(
                  videoController: _controller,
                  currentTitle: _tituloContenido.isNotEmpty
                      ? _tituloContenido
                      : widget.titulo,
                  nextIdContenido:
                      _recomendaciones.first['idcontenido'] as int,
                  nextTitulo:
                      (_recomendaciones.first['titulo'] ?? '').toString(),
                  nextPoster: _recomendaciones.first['poster']?.toString(),
                  nextBackdrop:
                      _recomendaciones.first['backdrop']?.toString(),
                  nextLogo: _recomendaciones.first['logo']?.toString(),
                  nextTipo:
                      (_recomendaciones.first['tipo'] ?? 'movie').toString(),
                  accentColor: accentOrange,
                  optimizeTmdbUrl: _optimizeTmdbUrl,
                  producirSiguienteFocusNode: _byProducirSiguienteFocusNode,
                  continuarCreditosFocusNode: _byContinuarCreditosFocusNode,
                  isBackKey: _isBackKey,
                  onContinuarCreditos: () {
                    setState(() => _showBecauseYouWatched = false);
                    _showControlsOverlayNow();
                  },
                  onProducirSiguiente: () {
                    setState(() => _showBecauseYouWatched = false);
                    final next = _recomendaciones.first;
                    _openServersModal(
                      idcontenido: next['idcontenido'] as int?,
                      titulo:
                          (next['titulo'] ?? next['title'] ?? '').toString(),
                      tipo: (next['tipo'] ?? 'movie').toString(),
                      backdropUrl:
                          (next['backdrop'] ?? next['poster'])?.toString(),
                      logoUrl: next['logo']?.toString(),
                      clearCurrentServer: true,
                    );
                  },
                ),

              if (!_isLoading &&
                  _errorMessage.isEmpty &&
                  _showControls &&
                  !_showBecauseYouWatched)
                _buildControlsOverlay(),

              if (!_isLoading &&
                  _errorMessage.isEmpty &&
                  !_showControls &&
                  _showToolbarOnly &&
                  !_showBecauseYouWatched)
                _buildToolbarOnlyOverlay(),

              if (_showScreensaver &&
                  !_isLoading &&
                  _errorMessage.isEmpty &&
                  !_showBecauseYouWatched)
                ScreensaverOverlay(
                  backdropUrl: _backdropUrl,
                  logoUrl: _logoUrl,
                  title: _tituloContenido.isNotEmpty
                      ? _tituloContenido
                      : widget.titulo,
                  episodeLabel: widget.tipo == 'tv'
                      ? (_capituloFmt ??
                          (widget.temporada != null && widget.capitulo != null
                              ? 'S${widget.temporada.toString().padLeft(2, '0')}E${widget.capitulo.toString().padLeft(2, '0')}'
                              : null))
                      : null,
                  optimizeTmdbUrl: _optimizeTmdbUrl,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_backdropUrl != null && _backdropUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: _backdropUrl!,
            fit: BoxFit.cover,
            memCacheWidth: 960,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, __) => const ColoredBox(color: Colors.black),
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        const Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: accentOrange,
              strokeWidth: 3.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorScreen() {
    Widget errorBtn({
      required FocusNode node,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      required bool primary,
      required FocusNode other,
      bool autofocus = false,
    }) {
      return Focus(
        focusNode: node,
        autofocus: autofocus,
        onFocusChange: (_) {
          if (mounted && !_isDisposing) setState(() {});
        },
        onKeyEvent: (n, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowRight ||
              e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            other.requestFocus();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.select ||
              e.logicalKey == LogicalKeyboardKey.enter) {
            onTap();
            return KeyEventResult.handled;
          }
          if (_isBackKey(e)) {
            _goBackToContent();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) {
            final hasFocus = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: hasFocus
                      ? (primary ? accentOrange : netflixRed)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasFocus ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 20,
                        color: hasFocus ? Colors.white : Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: hasFocus ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: netflixRed, size: 64),
          const SizedBox(height: 16),
          const Text(
            'No se pudo cargar el video',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              errorBtn(
                node: _errorServersFocusNode,
                icon: Icons.dns_rounded,
                label: 'Cambiar servidor',
                onTap: () => _openServersModal(),
                primary: true,
                other: _errorBackFocusNode,
                autofocus: true,
              ),
              const SizedBox(width: 16),
              errorBtn(
                node: _errorBackFocusNode,
                icon: Icons.arrow_back_rounded,
                label: 'Volver',
                onTap: () async {
                  await _saveCache();
                  _goBackToContent();
                },
                primary: false,
                other: _errorServersFocusNode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarOnlyOverlay() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
          ),
        ),
        child: SafeArea(top: false, child: _buildActionButtonsRow()),
      ),
    );
  }

  Widget _buildActionButtonsRow() {
    return Row(
      children: [
        _buildPlayPauseBtn(),
        const SizedBox(width: 10),
        _buildActionBtn(
          _restartFocusNode,
          Icons.replay_rounded,
          'Reiniciar',
          _restart,
          iconOnly: true,
        ),
        const SizedBox(width: 10),
        if (_showNextButton)
          _buildActionBtn(
            _nextFocusNode,
            Icons.skip_next_rounded,
            widget.tipo == 'tv' ? 'Siguiente episodio' : 'Ver siguiente',
            _goNextEpisode,
            highlight: true,
            iconOnly: true,
          ),
        const Spacer(),
        _buildActionBtn(
          _serversFocusNode,
          Icons.dns_rounded,
          'Servidores',
          () => _openServersModal(),
        ),
        const SizedBox(width: 10),
        QualityActionButton(
          focusNode: _qualityFocusNode,
          currentLabel: _currentQualityLabel,
          onTap: _openQualitySelector,
          accentColor: accentOrange,
          onArrowLeft: _moveFocusLeft,
          onArrowRight: _moveFocusRight,
          onArrowUp: _moveFocusUp,
          onArrowDown: _moveFocusDown,
          isBackKey: _isBackKey,
          onBack: _handleBackPressed,
        ),
        const SizedBox(width: 10),
        _buildActionBtn(
          _fitFocusNode,
          _fitModeIcon,
          _fitModeLabel,
          _cycleFitMode,
        ),
        const SizedBox(width: 10),
        _buildActionBtn(
          _infoFocusNode,
          Icons.info_outline_rounded,
          'Info',
          _openInfoModal,
        ),
      ],
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.15, 0.45, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (_logoUrl != null && _logoUrl!.isNotEmpty) ...[
                          CachedNetworkImage(
                            imageUrl: _logoUrl!,
                            height: 36,
                            fit: BoxFit.contain,
                            memCacheHeight: 72,
                            memCacheWidth: 200,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.tipo == 'movie') ...[
                                if (_logoUrl == null || _logoUrl!.isEmpty)
                                  Text(
                                    '$_tituloContenido${_apiData?['fecha_salida'] != null ? ' (${_apiData!['fecha_salida'].toString().substring(0, 4)})' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ] else ...[
                                if (_logoUrl == null || _logoUrl!.isEmpty)
                                  Text(
                                    _episodeCodeLabel() ?? _tituloContenido,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                else
                                  Text(
                                    _episodeCodeLabel() ?? _tituloContenido,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (_tituloCapitulo != null &&
                                    _tituloCapitulo!.isNotEmpty)
                                  Text(
                                    _tituloCapitulo!,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: _idiomaFlagUrl(),
                      width: 26,
                      height: 26,
                      fit: BoxFit.cover,
                      memCacheWidth: 52,
                      errorWidget: (_, __, ___) => Text(
                        _idiomaLabel(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _currentTime,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_horaFinEstimada.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Termina $_horaFinEstimada',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            Focus(
              focusNode: _seekBarFocusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (_isBackKey(event)) {
                    _handleBackPressed();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _moveFocusDown();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    if (_showSkipIntro) {
                      _skipIntroFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (_showNextEpisodeCard &&
                        (_siguiente != null || _recomendaciones.isNotEmpty)) {
                      _nextPromptFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    _moveFocusUp();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _startSeekHold(-1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _startSeekHold(1);
                    return KeyEventResult.handled;
                  }
                }
                if (event is KeyUpEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                      event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _stopSeekHold();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(_currentPosition),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3.5,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius:
                                _seekBarFocusNode.hasFocus ? 9 : 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: accentOrange,
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.25),
                          thumbColor: _seekBarFocusNode.hasFocus
                              ? Colors.white
                              : accentOrange,
                          overlayColor:
                              accentOrange.withValues(alpha: 0.25),
                        ),
                        child: Slider(
                          value: _totalDuration.inSeconds > 0
                              ? _currentPosition.inSeconds
                                  .clamp(0, _totalDuration.inSeconds)
                                  .toDouble()
                              : 0.0,
                          max: _totalDuration.inSeconds > 0
                              ? _totalDuration.inSeconds.toDouble()
                              : 1.0,
                          onChanged: (v) =>
                              _controller.seekTo(Duration(seconds: v.toInt())),
                          onChangeStart: (_) {
                            _hideControlsTimer?.cancel();
                            setState(() => _isDragging = true);
                          },
                          onChangeEnd: (_) {
                            setState(() {
                              _isDragging = false;
                              _recalcularHoraFin();
                            });
                            _scheduleHideControls();
                          },
                        ),
                      ),
                    ),
                    Text(
                      '-${_formatDuration(_totalDuration - _currentPosition)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildActionButtonsRow(),
            ),
            if (_showSeasonsAndEpisodes &&
                widget.tipo == 'tv' &&
                _temporadas.isNotEmpty) ...[
              const SizedBox(height: 14),
              CapitulosTemporadas(
                temporadas: _temporadas,
                selectedSeasonIndex: _selectedSeasonIndex,
                seasonFocusNodes: _seasonFocusNodes,
                episodeFocusNodes: _episodeFocusNodes,
                seasonScrollController: _seasonScrollController,
                episodeScrollController: _episodeScrollController,
                episodeProgress: _episodeProgress,
                currentTemporada: widget.temporada,
                currentCapitulo: widget.capitulo,
                accentColor: accentOrange,
                optimizeTmdbUrl: _optimizeTmdbUrl,
                onSeasonSelected: (i) {
                  setState(() {
                    _selectedSeasonIndex = i;
                    _rebuildEpisodeFocusNodes();
                  });
                },
                onEpisodeSelected: ({required temporada, required capitulo}) {
                  _openServersModal(
                    idcontenido: widget.idcontenido,
                    temporada: temporada,
                    capitulo: capitulo,
                  );
                },
                onArrowUp: _moveFocusUp,
                onArrowDown: _moveFocusDown,
                onArrowLeft: _moveFocusLeft,
                onArrowRight: _moveFocusRight,
                isBackKey: _isBackKey,
                onBack: _handleBackPressed,
                getFocusEpisodeIndex: _getFocusEpisodeIndex,
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayPauseBtn() {
    return Focus(
      focusNode: _playPauseFocusNode,
      onFocusChange: (has) {
        if (has) {
          _currentRow = 2;
          _lastFocusedActionNode = _playPauseFocusNode;
        }
        setState(() {});
      },
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent) {
          if (_isBackKey(e)) {
            _handleBackPressed();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.select ||
              e.logicalKey == LogicalKeyboardKey.enter) {
            if (!_isBuffering) _togglePlay();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            _currentRow = 2;
            _moveFocusRight();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _currentRow = 2;
            _moveFocusLeft();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
            _moveFocusUp();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
            _moveFocusDown();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          final label =
              _isBuffering ? 'Cargando' : (_isPlaying ? 'Pausa' : 'Play');
          final icon = _isBuffering
              ? null
              : (_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded);

          return GestureDetector(
            onTap: _isBuffering ? null : _togglePlay,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isBuffering)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: hasFocus ? Colors.black : Colors.white,
                      ),
                    )
                  else
                    Icon(icon,
                        size: 18,
                        color: hasFocus ? Colors.black : Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: hasFocus ? Colors.black : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionBtn(
    FocusNode node,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool highlight = false,
    bool iconOnly = false,
  }) {
    return Focus(
      focusNode: node,
      onFocusChange: (has) {
        if (has) {
          _currentRow = 2;
          _lastFocusedActionNode = node;
        }
        setState(() {});
      },
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent) {
          if (_isBackKey(e)) {
            _handleBackPressed();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.select ||
              e.logicalKey == LogicalKeyboardKey.enter) {
            onTap();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            _currentRow = 2;
            _moveFocusRight();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _currentRow = 2;
            _moveFocusLeft();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
            _moveFocusUp();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
            _moveFocusDown();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: iconOnly ? 12 : 14,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: hasFocus
                    ? Colors.white
                    : highlight
                        ? accentOrange.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : (highlight ? accentOrange : Colors.transparent),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 18,
                      color: hasFocus ? Colors.black : Colors.white),
                  if (!iconOnly) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: hasFocus ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}