import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../content/presentation/tv_content_page.dart';
import '../../../servers/presentation/tv_servers_modal.dart';
import '../../../servers/presentation/tv_server_preloader.dart';
import 'tv_subtitle_widget.dart';
import '../subtitles/tv_subtitle_selector.dart';
import 'tv_quality_selector.dart';
import '../../../content/presentation/content_info.dart';
import '../../../content/presentation/cast_modal.dart';
import '../../../content/presentation/seasons_episodes.dart';
import '../widgets/watch_later_button.dart';
import '../widgets/next_episode_prompt.dart';
import '../widgets/screensaver_overlay.dart';
import '../../../../data/datasources/remote/tmdb/tmdb_player_api.dart';
import 'tv_player_controller.dart';
import '../widgets/because_you_watched_overlay.dart';
class _SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  const _SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

enum _VideoFitMode { original, ratio16_9, ratio21_9, ratio16_10, ratio4_3 }


/// Track del seek bar: gris + segmentos verdes (intro/outro) + naranja (progreso).
/// El thumb del Slider queda siempre alineado con el final del naranja.
class _SegmentedVideoTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  final double? introStart;
  final double? introEnd;
  final double? outroStart;
  final double? outroEnd;
  final double? recapStart;
  final double? recapEnd;
  final double nextThreshold;
  final Color activeColor;
  final Color inactiveColor;
  final Color segmentColor;

  const _SegmentedVideoTrackShape({
    this.introStart,
    this.introEnd,
    this.outroStart,
    this.outroEnd,
    this.recapStart,
    this.recapEnd,
    this.nextThreshold = 0.95,
    required this.activeColor,
    required this.inactiveColor,
    required this.segmentColor,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4.0;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final cy = trackRect.center.dy;
    final left = trackRect.left;
    final right = trackRect.right;
    final width = trackRect.width;
    if (width <= 0) return;

    final r = Radius.circular(trackHeight / 2);
    final canvas = context.canvas;

    void drawSeg(double a, double b, Color color) {
      final x1 = left + (a.clamp(0.0, 1.0) * width);
      final x2 = left + (b.clamp(0.0, 1.0) * width);
      if (x2 <= x1) return;
      canvas.drawRRect(
        RRect.fromLTRBR(x1, cy - trackHeight / 2, x2, cy + trackHeight / 2, r),
        Paint()..color = color,
      );
    }

    // 1) Fondo inactivo completo
    drawSeg(0.0, 1.0, inactiveColor);

    // 2) Zonas verdes (intro / recap / outro / umbral)
    if (introStart != null && introEnd != null) {
      drawSeg(introStart!, introEnd!, segmentColor);
    }
    if (recapStart != null && recapEnd != null) {
      drawSeg(recapStart!, recapEnd!, segmentColor.withValues(alpha: 0.85));
    }
    if (outroStart != null) {
      final oEnd = outroEnd ?? 1.0;
      drawSeg(outroStart!, oEnd, segmentColor);
    } else if (nextThreshold > 0 && nextThreshold < 1) {
      drawSeg(nextThreshold, 1.0, segmentColor);
    }

    // 3) Progreso activo (naranja) hasta el thumb — siempre alineado
    final activeEnd = ((thumbCenter.dx - left) / width).clamp(0.0, 1.0);
    drawSeg(0.0, activeEnd, activeColor);
  }
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

  const PlayerScreen({
    super.key,
    this.videoUrl = '',
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
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Color accentOrange = Color(0xFFFF6B00);
  static const Color netflixRed = Color(0xFFE50914);

  final ServerLoader _serverLoader = ServerLoader();
  String _activeUrl = '';
  Map<String, String> _activeHeaders = {};
  List<Map<String, dynamic>> _fallbackServers = [];
  int _fallbackIndex = 0;
  bool _isResolving = false;
  bool _allServersFailed = false;
  bool _preloadTriggered = false;
  /// true cuando ya se precargó el siguiente (botón naranja).
  bool _nextPreloaded = false;
  /// Usuario cerró el prompt de siguiente manualmente.
  bool _nextPromptUserDismissed = false;
  bool _nextPromptAutoHidden = false;
  Timer? _nextPromptHideTimer;

  late VideoPlayerController _controller;
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _subtitlesEnabled = true;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String _errorMessage = '';
  bool _showControls = false;
  bool _isBuffering = false;
  Timer? _hideControlsTimer;
  bool _isDragging = false;
  bool _isDisposing = false;
  /// true cuando se reemplaza el player (siguiente ep / otro contenido).
  /// Evita que dispose() apague wakelock/orientación del player nuevo.
  bool _isReplacingPlayer = false;
  bool _controllerReady = false;

  bool _showToolbarOnly = false;
  Timer? _hideToolbarOnlyTimer;

  FocusNode? _lastFocusedActionNode;
  bool _controlsWereShowingBeforeModal = false;

  List<_SubtitleCue> _subtitleCues = const [];
  String _currentSubtitleText = '';

  double _subtitleOffsetSec = 0.0;
  double _subtitleFontSize = 22.0;
  bool _subtitleBold = false;
  double _subtitleVerticalOffset = 0.0;
  String? _currentSubtitleId;
  String? _currentSubtitleUrl;
  String? _currentSubtitleLang;

  Timer? _seekHoldTimer;
  int _seekHoldDirection = 0;
  int _seekHoldTicks = 0;

  static const String _prefSubIdKey = 'player_sub_id_';
  static const String _prefSubUrlKey = 'player_sub_url_';
  static const String _prefSubLangKey = 'player_sub_lang_';
  static const String _prefSubOffsetKey = 'subtitulo_offset_sec';
  static const String _prefSubFontKey = 'subtitulo_font_size';
  static const String _prefSubBoldKey = 'subtitulos_negrita';
  static const String _prefSubVertKey = 'subtitulo_vertical_offset';
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

  final FocusScopeNode _playerScopeNode =
      FocusScopeNode(debugLabel: 'player_scope');
  final FocusNode _videoFocusNode = FocusNode(debugLabel: 'player_video');
  final FocusNode _seekBarFocusNode = FocusNode();
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _restartFocusNode = FocusNode();
  final FocusNode _nextFocusNode = FocusNode();
  final FocusNode _subsFocusNode = FocusNode();
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
    // Aspecto objetivo: forzado por el usuario o el nativo del vídeo.
    final targetAspect = forced ?? (vw / vh);

    // Fire TV / Firestick: siempre mapear la textura a un SizedBox con
    // FittedBox.fill. Evita el recuadro + pantalla verde (SurfaceView)
    // que aparece cuando el VideoPlayer no llena el área de layout.
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          if (maxW <= 0 || maxH <= 0) {
            return const ColoredBox(color: Colors.black);
          }

          late final double frameW;
          late final double frameH;
          if (maxW / maxH > targetAspect) {
            frameH = maxH;
            frameW = frameH * targetAspect;
          } else {
            frameW = maxW;
            frameH = frameW / targetAspect;
          }

          return Center(
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
          );
        },
      ),
    );
  }

  bool get _showSeasonsAndEpisodes => _currentRow >= 3;

  bool get _hasRealNext {
    if (widget.tipo == 'tv') {
      return _siguiente != null &&
          (_siguiente!['temporada'] != null ||
              _siguiente!['capitulo'] != null ||
              _siguiente!['numero'] != null);
    }
    return _recomendaciones.isNotEmpty;
  }

  List<FocusNode> get _visibleActionNodes {
    final list = <FocusNode>[_playPauseFocusNode, _restartFocusNode];
    if (_showNextButton) {
      list.add(_nextFocusNode);
    }
    list.addAll([
      _subsFocusNode,
      _serversFocusNode,
      _qualityFocusNode,
      _fitFocusNode,
      _infoFocusNode,
    ]);
    return list;
  }

  bool get _showNextButton => _hasRealNext;

  int _lastPositionUpdateMs = 0;
  static const int _positionThrottleMs = 250;

  bool _showEndPrompt = false;
  bool _hasHandledEnd = false;
  bool _showNextEpisodeCard = false;

  double? _introStartSec;
  double? _introEndSec;
  double? _outroStartSec;
  double? _outroEndSec;
  double? _recapStartSec;
  double? _recapEndSec;
  bool _showSkipIntro = false;
  /// Usuario descartó el skip (atrás) en este intervalo.
  bool _skipIntroDismissed = false;
  /// Auto-ocultado por timeout; no reaparece hasta abrir controles.
  bool _skipIntroAutoHidden = false;
  Timer? _skipIntroHideTimer;
  /// 0.0 → 1.0 progreso de la barra de auto-hide (1 = recién mostrado).
  double _skipIntroHideProgress = 1.0;
  DateTime? _skipIntroHideStartedAt;
  static const int _skipIntroAutoHideMs = 10000;
  final FocusNode _skipIntroFocusNode = FocusNode();

  double _nextThresholdPct = 0.95;

  int _seekRepeatCount = 0;
  DateTime? _lastSeekKeyAt;

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
      _subsFocusNode,
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
      _loadSubtitles();
    });
    _loadSubtitlePrefs();
    _loadNextThresholdPref();
    _loadRecommendationsFromGuardados();
    FocusManager.instance.addListener(_onGlobalFocusChanged);
    _startCacheTimer();
    _resetScreensaverTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimPlayerFocus());
  }

  void _claimPlayerFocus() {
    if (!mounted || _isDisposing) return;
    try {
      _playerScopeNode.requestFocus();
    } catch (_) {}
    if (_errorMessage.isNotEmpty) {
      _errorServersFocusNode.requestFocus();
      return;
    }
    if (_showBecauseYouWatched) {
      _byProducirSiguienteFocusNode.requestFocus();
      return;
    }
    if (_showSkipIntro) {
      _skipIntroFocusNode.requestFocus();
      return;
    }
    if (_showControls) {
      _seekBarFocusNode.requestFocus();
      return;
    }
    if (_showToolbarOnly) {
      final nodes = _visibleActionNodes;
      if (nodes.isNotEmpty) {
        nodes.first.requestFocus();
        return;
      }
    }
    _videoFocusNode.requestFocus();
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

    GuardadosBus.bump();
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
          final key = 'cachePlayerRapido_${widget.idcontenido}_T${tNum}_C$cNum';
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
      final String mediaType = widget.tipo.toLowerCase() == 'tv'
          ? 'tv'
          : 'movie';

      final service = TmdbPlayerService();
      final data = await service.fetchPlayer(
        tmdbId: tmdbId,
        mediaType: mediaType,
        temporada: widget.temporada ?? 0,
        capitulo: widget.capitulo ?? 0,
      );

      if (!mounted || _isDisposing) return;

      if (data['error'] == true) {
        debugPrint('TMDB Player error: ${data['mensaje']}');
        return;
      }

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

        final recoApi = data['recomendaciones'] is List
            ? data['recomendaciones'] as List
            : [];

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
        }

        if (widget.temporada != null && _temporadas.isNotEmpty) {
          final idx = _temporadas.indexWhere(
            (t) => t['numero'] == widget.temporada,
          );
          if (idx >= 0) _selectedSeasonIndex = idx;
        }

        _rebuildSeasonFocusNodes();
        _rebuildEpisodeFocusNodes();
      });

      debugPrint('✅ Logo: $_logoUrl');
      debugPrint('✅ Título: $_tituloContenido');
      debugPrint('✅ Backdrop: $_backdropUrl');

      // Quitar de recomendaciones los ya vistos ≥50% (historial cache)
      if (_recomendaciones.isNotEmpty) {
        await _filterOutCompletedRecommendations();
      }

      _loadIntroSkip();
      _loadEpisodeProgress();
      if (_recomendaciones.isNotEmpty) _loadRecoProgress();
    } catch (e, st) {
      debugPrint('Error cargando TMDB Player: $e');
      debugPrint(st.toString());
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
      final recap = data['recap'];

      double? introStart, introEnd, outroStart, outroEnd, recapStart, recapEnd;

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
      if (recap is Map) {
        final start = recap['start_sec'];
        final end = recap['end_sec'];
        if (start != null) recapStart = (start as num).toDouble();
        if (end != null) recapEnd = (end as num).toDouble();
      }

      if (mounted && !_isDisposing) {
        setState(() {
          _introStartSec = introStart;
          _introEndSec = introEnd;
          _outroStartSec = outroStart;
          _outroEndSec = outroEnd;
          _recapStartSec = recapStart;
          _recapEndSec = recapEnd;
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

  void _releaseOverlayFocusToSafe() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposing) return;
      if (_showControls) {
        _seekBarFocusNode.requestFocus();
      } else if (_showToolbarOnly) {
        final nodes = _visibleActionNodes;
        if (nodes.isNotEmpty) {
          nodes.first.requestFocus();
        } else {
          _videoFocusNode.requestFocus();
        }
      } else {
        _videoFocusNode.requestFocus();
      }
    });
  }

  bool get _skipIntroActuallyVisible {
    if (_introStartSec == null || _introEndSec == null) return false;
    if (_showBecauseYouWatched) return false;
    final pos = _currentPosition.inMilliseconds / 1000.0;
    final inInterval = pos >= _introStartSec! && pos <= _introEndSec!;
    if (!inInterval) return false;
    // Nuvio: si dismissed, solo visible con controles abiertos
    if (_skipIntroDismissed && !(_showControls || _showToolbarOnly)) {
      return false;
    }
    // Auto-hidden: no mostrar mientras controles ocultos
    if (_skipIntroAutoHidden && !(_showControls || _showToolbarOnly)) {
      return false;
    }
    return true;
  }

  void _updateSkipIntroVisibility() {
    final shouldShow = _skipIntroActuallyVisible;
    if (shouldShow == _showSkipIntro) {
      // Pausar / reanudar contador según controles
      if (shouldShow) {
        if (_showControls || _showToolbarOnly) {
          _pauseSkipIntroHideTimer();
        } else {
          _resumeSkipIntroHideTimer();
        }
      }
      return;
    }

    final hadFocus = _skipIntroFocusNode.hasFocus;
    _showSkipIntro = shouldShow;

    if (shouldShow) {
      _skipIntroAutoHidden = false;
      _startSkipIntroHideTimer();
      // Solo robar foco si no hay controles / overlays prioritarios
      if (!(_showControls || _showToolbarOnly) &&
          !_showNextEpisodeCard &&
          !_showBecauseYouWatched) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposing && _showSkipIntro) {
            _skipIntroFocusNode.requestFocus();
          }
        });
      }
    } else {
      _stopSkipIntroHideTimer();
      if (hadFocus) _releaseOverlayFocusToSafe();
      // Al salir del intervalo, reset dismiss para el próximo
      final pos = _currentPosition.inMilliseconds / 1000.0;
      if (_introStartSec == null ||
          _introEndSec == null ||
          pos < _introStartSec! ||
          pos > _introEndSec!) {
        _skipIntroDismissed = false;
        _skipIntroAutoHidden = false;
      }
    }
  }

  void _startSkipIntroHideTimer() {
    _stopSkipIntroHideTimer();
    _skipIntroHideProgress = 1.0;
    _skipIntroHideStartedAt = DateTime.now();
    // Tick cada 50ms para la barra inferior del botón
    _skipIntroHideTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _isDisposing || !_showSkipIntro) {
        _stopSkipIntroHideTimer();
        return;
      }
      // Pausado mientras hay controles (como Nuvio)
      if (_showControls || _showToolbarOnly) return;
      final started = _skipIntroHideStartedAt;
      if (started == null) return;
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final left = (_skipIntroAutoHideMs - elapsed).clamp(0, _skipIntroAutoHideMs);
      final p = left / _skipIntroAutoHideMs;
      if ((p - _skipIntroHideProgress).abs() > 0.01 || p <= 0) {
        setState(() => _skipIntroHideProgress = p);
      }
      if (elapsed >= _skipIntroAutoHideMs) {
        _stopSkipIntroHideTimer();
        final hadFocus = _skipIntroFocusNode.hasFocus;
        setState(() {
          _skipIntroAutoHidden = true;
          _showSkipIntro = false;
          _skipIntroHideProgress = 0;
        });
        if (hadFocus) _releaseOverlayFocusToSafe();
      }
    });
  }

  void _pauseSkipIntroHideTimer() {
    // Congela el tiempo restante recalculando startedAt al reanudar
    if (_skipIntroHideStartedAt == null) return;
    final elapsed = DateTime.now().difference(_skipIntroHideStartedAt!).inMilliseconds;
    final left = (_skipIntroAutoHideMs - elapsed).clamp(0, _skipIntroAutoHideMs);
    _skipIntroHideProgress = left / _skipIntroAutoHideMs;
    // Marcar pausa: startedAt = null hasta resume
    _skipIntroHideStartedAt = null;
  }

  void _resumeSkipIntroHideTimer() {
    if (!_showSkipIntro || _skipIntroAutoHidden) return;
    if (_skipIntroHideStartedAt != null) return; // ya corriendo
    // Reanudar desde el progreso actual
    final leftMs = (_skipIntroHideProgress * _skipIntroAutoHideMs).round();
    _skipIntroHideStartedAt =
        DateTime.now().subtract(Duration(milliseconds: _skipIntroAutoHideMs - leftMs));
    if (_skipIntroHideTimer == null || !_skipIntroHideTimer!.isActive) {
      _startSkipIntroHideTimerFromPaused();
    }
  }

  void _startSkipIntroHideTimerFromPaused() {
    _skipIntroHideTimer?.cancel();
    _skipIntroHideTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _isDisposing || !_showSkipIntro) {
        _stopSkipIntroHideTimer();
        return;
      }
      if (_showControls || _showToolbarOnly) return;
      final started = _skipIntroHideStartedAt;
      if (started == null) return;
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final left = (_skipIntroAutoHideMs - elapsed).clamp(0, _skipIntroAutoHideMs);
      final p = left / _skipIntroAutoHideMs;
      if ((p - _skipIntroHideProgress).abs() > 0.01 || p <= 0) {
        setState(() => _skipIntroHideProgress = p);
      }
      if (elapsed >= _skipIntroAutoHideMs) {
        _stopSkipIntroHideTimer();
        final hadFocus = _skipIntroFocusNode.hasFocus;
        setState(() {
          _skipIntroAutoHidden = true;
          _showSkipIntro = false;
          _skipIntroHideProgress = 0;
        });
        if (hadFocus) _releaseOverlayFocusToSafe();
      }
    });
  }

  void _stopSkipIntroHideTimer() {
    _skipIntroHideTimer?.cancel();
    _skipIntroHideTimer = null;
    _skipIntroHideStartedAt = null;
  }

  void _dismissSkipIntro() {
    _stopSkipIntroHideTimer();
    final hadFocus = _skipIntroFocusNode.hasFocus;
    setState(() {
      _skipIntroDismissed = true;
      _showSkipIntro = false;
    });
    if (hadFocus) _releaseOverlayFocusToSafe();
  }

  void _skipIntro() {
    if (_introEndSec == null || !_controllerReady) return;
    final target = Duration(milliseconds: (_introEndSec! * 1000).round());
    _controller.seekTo(target);
    _stopSkipIntroHideTimer();
    setState(() {
      _showSkipIntro = false;
      _skipIntroDismissed = true;
      _skipIntroAutoHidden = false;
    });
    _releaseOverlayFocusToSafe();
    _scheduleHideControls();
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

  Future<void> _loadRecommendationsFromGuardados() async {
    if (_recomendaciones.isNotEmpty) return;
    try {
      final items = await GuardadosCache.getAll();
      final filtered = items
          .where((e) => e['idcontenido'] != widget.idcontenido)
          .take(12)
          .toList();

      final adapted = filtered.map((e) {
        final poster = _optimizeTmdbUrl(
          (e['poster_path'] ?? e['backdrop_path'] ?? '').toString(),
          size: 'w342',
        );
        final backdrop = _optimizeTmdbUrl(
          (e['backdrop_path'] ?? e['poster_path'] ?? '').toString(),
          size: 'w500',
        );
        return <String, dynamic>{
          'idcontenido': e['idcontenido'],
          'titulo': e['title'] ?? '',
          'poster': poster,
          'backdrop': backdrop,
          'tipo': e['media_type'] ?? e['type'] ?? 'movie',
        };
      }).toList();

      if (mounted && !_isDisposing) {
        _recomendaciones = adapted;
        await _filterOutCompletedRecommendations();
        if (mounted && !_isDisposing) {
          _rebuildRecoFocusNodes();
          _loadRecoProgress();
        }
      }
    } catch (e) {
      debugPrint('Error cargando guardados: $e');
    }
  }

  /// Revisa el historial en SharedPreferences de cada recomendación.
  /// Si el progreso es ≥ 50% del total (o estimado), se descarta.
  /// Afecta: "Ver a continuación", siguiente película, BecauseYouWatched, etc.
  Future<void> _filterOutCompletedRecommendations({
    double threshold = 0.50,
    int estimatedDurationSec = 5400,
  }) async {
    if (_recomendaciones.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final kept = <dynamic>[];

      for (final rec in _recomendaciones) {
        final idRaw = rec['idcontenido'] ?? rec['tmdb_id'] ?? rec['idtmdb'];
        final idInt = idRaw is int ? idRaw : int.tryParse('$idRaw') ?? 0;
        if (idInt <= 0) {
          kept.add(rec);
          continue;
        }

        // No recomendar el contenido que se está reproduciendo
        if (idInt == widget.idcontenido ||
            idInt == (widget.tmdbId ?? widget.idcontenido)) {
          continue;
        }

        int? segundo;
        int? duracion;
        String bestTs = '';

        for (final key in allKeys) {
          final isMatch = key == 'cachePlayer_$idInt' ||
              key == 'cachePlayerRapido_$idInt' ||
              key.startsWith('cachePlayer_${idInt}_') ||
              key.startsWith('cachePlayerRapido_${idInt}_');
          if (!isMatch) continue;

          final raw = prefs.getString(key);
          if (raw == null || raw.isEmpty) continue;
          try {
            final data = Map<String, dynamic>.from(jsonDecode(raw));
            final s = (data['segundo'] as num?)?.toInt();
            if (s == null || s < 5) continue;
            final d = (data['duracion'] as num?)?.toInt() ??
                (data['duration'] as num?)?.toInt();
            final ts = data['timestamp']?.toString() ?? '';
            final newer = segundo == null ||
                (ts.isNotEmpty && ts.compareTo(bestTs) > 0) ||
                (ts.isEmpty && s > (segundo ?? 0));
            if (newer) {
              segundo = s;
              duracion = d ?? duracion;
              bestTs = ts;
            }
          } catch (_) {}
        }

        if (segundo != null && segundo > 0) {
          final total =
              (duracion != null && duracion > 0) ? duracion : estimatedDurationSec;
          final ratio = segundo / total;
          if (ratio >= threshold) {
            // Ya visto ≥50% → no incluir en "después" / siguiente / BYW
            continue;
          }
        }

        kept.add(rec);
      }

      if (!mounted || _isDisposing) return;
      setState(() {
        _recomendaciones = kept;
      });
      _rebuildRecoFocusNodes();
    } catch (e) {
      debugPrint('Error filtrando recomendaciones terminadas: $e');
    }
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

  void _keepScreenOn() {
    try {
      WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _initializePlayer() async {
    if (_isResolving) return;
    _isResolving = true;
    _allServersFailed = false;

    try {
      String? url = widget.videoUrl.trim().isNotEmpty
          ? widget.videoUrl.trim()
          : null;
      Map<String, String> headers = {};

      if (url == null || url.isEmpty) {
        final playable = await _serverLoader.resolvePlayable(
          contentId: widget.tmdbId ?? widget.idcontenido,
          isMovie: widget.tipo.toLowerCase() != 'tv',
          season: widget.temporada ?? 0,
          episode: widget.capitulo ?? 0,
          context: mounted ? context : null,
        );
        if (playable != null && playable.url.isNotEmpty) {
          url = playable.url;
          headers = Map<String, String>.from(playable.headers);
          if (playable.idioma.isNotEmpty) {
            _idioma = playable.idioma.toUpperCase();
          }
        }
      }

      try {
        final servers = await _serverLoader.getServers(
          contentId: widget.tmdbId ?? widget.idcontenido,
          isMovie: widget.tipo.toLowerCase() != 'tv',
          season: widget.temporada ?? 0,
          episode: widget.capitulo ?? 0,
          context: mounted ? context : null,
        );
        _fallbackServers = servers;
        _fallbackIndex = 0;
        if (url != null) {
          final idxS = servers.indexWhere((s) {
            final u =
                s['resolved_m3u8']?.toString() ??
                s['servidor_url']?.toString() ??
                '';
            return u == url;
          });
          if (idxS >= 0) _fallbackIndex = idxS;
        }
      } catch (_) {}

      if (url == null || url.isEmpty) {
        if (!mounted || _isDisposing) return;
        setState(() {
          _isLoading = false;
          _allServersFailed = true;
          _errorMessage =
              'No se encontró ningún servidor disponible para este contenido.';
        });
        return;
      }

      await _startControllerWithUrl(url, headers);
    } catch (e) {
      debugPrint('Error resolve/init TV: $e');
      await _tryNextServer(reason: e.toString());
    } finally {
      _isResolving = false;
    }
  }

  Future<void> _startControllerWithUrl(
    String url,
    Map<String, String> headers,
  ) async {
    if (_controllerReady) {
      try {
        _controller.removeListener(_videoListener);
        await _controller.dispose();
      } catch (_) {}
      _controllerReady = false;
    }
    if (!mounted || _isDisposing) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _allServersFailed = false;
    });

    try {
      _activeUrl = url;
      _activeHeaders = headers;
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: headers.isEmpty
            ? {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              }
            : headers,
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
        _isPlaying = true;
      });
      await _controller.play();
      _keepScreenOn();
      _resetScreensaverTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) => _claimPlayerFocus());
    } catch (e) {
      debugPrint('Error al reproducir URL TV: $e');
      if (_fallbackIndex < _fallbackServers.length) {
        _serverLoader.markServerAsInvalid(_fallbackServers[_fallbackIndex]);
      }
      await _tryNextServer(reason: e.toString());
    }
  }

  Future<void> _tryNextServer({String? reason}) async {
    if (!mounted || _isDisposing) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    _fallbackIndex++;
    while (_fallbackIndex < _fallbackServers.length) {
      final srv = _fallbackServers[_fallbackIndex];
      try {
        final playable = await _serverLoader.tryResolveServer(
          srv,
          context: mounted ? context : null,
        );
        if (playable != null &&
            playable.url.isNotEmpty &&
            playable.url != _activeUrl) {
          await _startControllerWithUrl(playable.url, playable.headers);
          return;
        }
      } catch (_) {}
      _serverLoader.markServerAsInvalid(srv);
      _fallbackIndex++;
    }
    if (!mounted || _isDisposing) return;
    setState(() {
      _isLoading = false;
      _allServersFailed = true;
      _errorMessage = reason != null && reason.isNotEmpty
          ? 'Ningún servidor funcionó.\n$reason'
          : 'Ningún servidor disponible para este contenido.';
    });
  }

  Future<void> _loadSubtitles() async {
    try {
      final url =
          'https://modlyo.com/subtitulo/contenido/${widget.idcontenido}/es_MX.vtt';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final cues = _parseVtt(utf8.decode(response.bodyBytes));
        if (mounted && !_isDisposing) setState(() => _subtitleCues = cues);
      }
    } catch (_) {}
  }

  List<_SubtitleCue> _parseVtt(String content) {
    final cues = <_SubtitleCue>[];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final timeRegex = RegExp(
      r'(\d{2}:)?(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*(\d{2}:)?(\d{2}):(\d{2})[.,](\d{3})',
    );
    int i = 0;
    while (i < lines.length) {
      final match = timeRegex.firstMatch(lines[i].trim());
      if (match != null) {
        final start = _durationFromMatch(match, 1);
        final end = _durationFromMatch(match, 5);
        i++;
        final buffer = StringBuffer();
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(_stripVttTags(lines[i].trim()));
          i++;
        }
        cues.add(_SubtitleCue(start: start, end: end, text: buffer.toString()));
      }
      i++;
    }
    return cues;
  }

  Duration _durationFromMatch(RegExpMatch match, int startGroup) {
    final hoursStr = match.group(startGroup);
    final hours = hoursStr != null
        ? int.parse(hoursStr.replaceAll(':', ''))
        : 0;
    final minutes = int.parse(match.group(startGroup + 1)!);
    final seconds = int.parse(match.group(startGroup + 2)!);
    final millis = int.parse(match.group(startGroup + 3)!);
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  String _stripVttTags(String text) => text.replaceAll(RegExp(r'<[^>]*>'), '');

  void _updateCurrentSubtitle() {
    if (!_subtitlesEnabled || _subtitleCues.isEmpty) {
      if (_currentSubtitleText.isNotEmpty) {
        _currentSubtitleText = '';
      }
      return;
    }
    final effectivePos =
        _currentPosition +
        Duration(milliseconds: (_subtitleOffsetSec * 1000).round());
    String newText = '';
    for (final cue in _subtitleCues) {
      if (effectivePos >= cue.start && effectivePos <= cue.end) {
        newText = cue.text;
        break;
      }
      if (effectivePos < cue.start) break;
    }
    if (newText != _currentSubtitleText) {
      _currentSubtitleText = newText;
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
    final shouldUpdatePosition =
        _isDragging ||
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
      _updateCurrentSubtitle();
      final prevSkip = _showSkipIntro;
      _updateSkipIntroVisibility();
      if (prevSkip != _showSkipIntro) needsSetState = true;
      needsSetState = true;

      if (_totalDuration.inSeconds > 30) {
        final remaining = _totalDuration - _currentPosition;

        final nextTrigger =
            _isNextTriggerReached() && remaining > const Duration(seconds: 2);

        // Solo mostrar tarjeta si hay siguiente real y el usuario no la descartó
        final shouldShowCard = nextTrigger &&
            _hasRealNext &&
            !_nextPromptUserDismissed &&
            !_showBecauseYouWatched &&
            !(_nextPromptAutoHidden && !(_showControls || _showToolbarOnly));

        if (shouldShowCard != _showNextEpisodeCard) {
          _showNextEpisodeCard = shouldShowCard;
          needsSetState = true;
          if (shouldShowCard) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isDisposing && _showNextEpisodeCard) {
                _nextPromptFocusNode.requestFocus();
              }
            });
          } else {
            _nextPromptHideTimer?.cancel();
            if (_nextPromptFocusNode.hasFocus) {
              _releaseOverlayFocusToSafe();
            }
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
          _nextPromptHideTimer?.cancel();
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

        if (!_preloadTriggered && dur.inSeconds > 30) {
          final frac = pos.inMilliseconds / dur.inMilliseconds;
          if (frac >= 0.90) {
            _preloadTriggered = true;
            _silentPreloadNext();
          }
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
      if (newPlaying) {
        _resetScreensaverTimer();
      }
    }
    if (newBuffering != _isBuffering) {
      _isBuffering = newBuffering;
      needsSetState = true;
    }
    if (newDuration != _totalDuration) {
      _totalDuration = newDuration;
      needsSetState = true;
    }

    if (needsSetState) {
      setState(() {});
    }
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

  void _onGlobalFocusChanged() {
    if (!mounted || _isDisposing || _isReplacingPlayer) return;
    _scheduleHideControls();
    _resetScreensaverTimer();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_showControls || _isDragging) return;
    if (_isControlFocused()) return;
    if (_hasPermanentFocusSession()) return;
    _hideControlsTimer?.cancel();
  }

  void _showControlsOverlayNow() {
    setState(() {
      _showControls = true;
      _showToolbarOnly = false;
      _currentRow = 1;
      _showScreensaver = false;
      _recalcularHoraFin();
    });
    _pauseSkipIntroHideTimer();
    // Si estaba auto-oculto o dismissed, con controles puede volver a mostrarse
    if (_introStartSec != null && _introEndSec != null) {
      final pos = _currentPosition.inMilliseconds / 1000.0;
      final inInterval = pos >= _introStartSec! && pos <= _introEndSec!;
      if (inInterval && !_showSkipIntro) {
        setState(() {
          _showSkipIntro = true;
          _skipIntroHideProgress = _skipIntroHideProgress > 0
              ? _skipIntroHideProgress
              : 1.0;
        });
      }
    }
    _hideToolbarOnlyTimer?.cancel();
    _seekBarFocusNode.requestFocus();
    _scheduleHideControls();
    _resetScreensaverTimer();
    _maybeReshowNextPromptOnControls();
  }

  /// El auto-hide lo gestiona NextEpisodePrompt (barra 10s). Aquí solo re-mostrar.
  void _scheduleNextPromptAutoHide() {
    // no-op: el widget tiene el timer interno
  }

  /// Al mostrar controles (o toolbar), si estamos en zona de outro y hay siguiente, re-mostrar.
  void _maybeReshowNextPromptOnControls() {
    if (!_hasRealNext || _showBecauseYouWatched) return;
    // Solo bloquea si el usuario lo cerró a propósito (atrás / dismiss)
    if (_nextPromptUserDismissed) return;
    if (!_isNextTriggerReached()) return;
    final remaining = _totalDuration - _currentPosition;
    if (remaining <= const Duration(seconds: 2)) return;
    // Al abrir controles: limpia autoHidden y re-muestra
    setState(() {
      _nextPromptAutoHidden = false;
      _showNextEpisodeCard = true;
    });
  }

  void _showToolbarOnlyNow() {
    if (!_showToolbarOnly) {
      setState(() {
        _showToolbarOnly = true;
        _currentRow = 2;
      });
    }
    final nodes = _visibleActionNodes;
    final target =
        _lastFocusedActionNode != null && nodes.contains(_lastFocusedActionNode)
        ? _lastFocusedActionNode!
        : (nodes.isNotEmpty ? nodes.first : _playPauseFocusNode);
    target.requestFocus();
    _scheduleHideToolbarOnly();
    _resetScreensaverTimer();
    _maybeReshowNextPromptOnControls();
  }

  void _scheduleHideToolbarOnly() {
    _hideToolbarOnlyTimer?.cancel();
    if (!_showToolbarOnly) return;
    _hideToolbarOnlyTimer?.cancel();
  }

  void _handleBackPressed() {
    if (_isReplacingPlayer) return;
    if (_showScreensaver) {
      setState(() => _showScreensaver = false);
      _resetScreensaverTimer();
      return;
    }
    // Nuvio: BACK con skip visible y sin controles → descartar skip
    if (_showSkipIntro && !(_showControls || _showToolbarOnly)) {
      _dismissSkipIntro();
      return;
    }
    if (_showBecauseYouWatched) {
      setState(() {
        _showBecauseYouWatched = false;
        _showNextEpisodeCard = false;
      });
      _videoFocusNode.requestFocus();
      _scheduleHideControls();
      return;
    }
    if (_showNextEpisodeCard) {
      _nextPromptHideTimer?.cancel();
      setState(() {
        _showNextEpisodeCard = false;
        _nextPromptUserDismissed = true;
      });
      _videoFocusNode.requestFocus();
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
        _resumeSkipIntroHideTimer();
        _updateSkipIntroVisibility();
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

  void _toggleSubtitles() {
    setState(() => _subtitlesEnabled = !_subtitlesEnabled);
    _scheduleHideControls();
  }

  Future<void> _loadSubtitlePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final offset = prefs.getDouble(_prefSubOffsetKey) ?? 0.0;
      final font = prefs.getDouble(_prefSubFontKey) ?? 22.0;
      final bold = prefs.getBool(_prefSubBoldKey) ?? false;
      final vert = prefs.getDouble(_prefSubVertKey) ?? 0.0;
      if (!mounted || _isDisposing) return;
      setState(() {
        _subtitleOffsetSec = offset.clamp(-30.0, 30.0);
        _subtitleFontSize = font.clamp(12.0, 36.0);
        _subtitleBold = bold;
        _subtitleVerticalOffset = vert.clamp(-40.0, 160.0);
        _subtitlesEnabled = true;
      });
    } catch (e) {
      debugPrint('Error cargando prefs subtítulos: $e');
    }
  }

  Future<void> _saveSubtitleStylePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefSubOffsetKey, _subtitleOffsetSec);
      await prefs.setDouble(_prefSubFontKey, _subtitleFontSize);
      await prefs.setBool(_prefSubBoldKey, _subtitleBold);
      await prefs.setDouble(_prefSubVertKey, _subtitleVerticalOffset);
    } catch (_) {}
  }

  Future<void> _saveActiveSubtitle({
    required String id,
    required String url,
    String? lang,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefSubIdKey${widget.idcontenido}', id);
      await prefs.setString('$_prefSubUrlKey${widget.idcontenido}', url);
      if (lang != null && lang.isNotEmpty) {
        await prefs.setString('$_prefSubLangKey${widget.idcontenido}', lang);
      }
    } catch (_) {}
  }

  Future<void> _clearActiveSubtitleCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefSubIdKey${widget.idcontenido}');
      await prefs.remove('$_prefSubUrlKey${widget.idcontenido}');
    } catch (_) {}
  }

  Future<void> _applySubtitleFromUrl({
    required String url,
    required String id,
    String? lang,
    bool enable = true,
  }) async {
    try {
      final cacheKey = 'opensub_vtt_${widget.idcontenido}_$id';
      final content = await SubtitleUtils.downloadAndCache(
        url: url,
        cacheKey: cacheKey,
        fileName: '$id.vtt',
      );
      final cues = _parseVtt(content);
      if (!mounted || _isDisposing) return;
      setState(() {
        _subtitleCues = cues;
        _currentSubtitleId = id;
        _currentSubtitleUrl = url;
        if (lang != null) _currentSubtitleLang = lang;
        _subtitlesEnabled = enable;
        _currentSubtitleText = '';
      });
      _updateCurrentSubtitle();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error aplicando subtítulo: $e');
    }
  }

  List<Map<String, dynamic>> get _cuesAsMaps {
    return _subtitleCues
        .map((c) => {'start': c.start, 'end': c.end, 'text': c.text})
        .toList();
  }

  void _openSubtitlesModal() {
    _hideControlsTimer?.cancel();
    final imdb = (_apiData?['imdb_id'] ?? '').toString().trim();
    final mediaType = widget.tipo.toLowerCase() == 'tv' ? 'tv' : 'movie';
    OpenSubtitlesModalTv.restorePlayerFocus = () {
      if (!mounted || _isDisposing) return;
      setState(() {
        _showControls = true;
        _currentRow = 2;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposing) return;
        _subsFocusNode.requestFocus();
        _scheduleHideControls();
      });
    };
    OpenSubtitlesModalTv.show(
      context: context,
      imdbId: imdb.isNotEmpty ? imdb : null,
      mediaType: mediaType,
      season: widget.temporada,
      episode: widget.capitulo,
      currentSubtitleId: _currentSubtitleId,
      subtitleOffsetSec: _subtitleOffsetSec,
      subtitleFontSize: _subtitleFontSize,
      subtitleBold: _subtitleBold,
      subtitleVerticalOffset: _subtitleVerticalOffset,
      cues: _cuesAsMaps,
      currentPosition: _currentPosition,
      onOffsetChanged: (v) {
        setState(() => _subtitleOffsetSec = v);
        _saveSubtitleStylePrefs();
        _updateCurrentSubtitle();
        if (mounted) setState(() {});
      },
      onFontSizeChanged: (v) {
        setState(() => _subtitleFontSize = v);
        _saveSubtitleStylePrefs();
      },
      onBoldChanged: (v) {
        setState(() => _subtitleBold = v);
        _saveSubtitleStylePrefs();
      },
      onVerticalOffsetChanged: (v) {
        setState(() => _subtitleVerticalOffset = v);
        _saveSubtitleStylePrefs();
      },
      onSubtitleSelected: (sub) async {
        final id = sub['id']?.toString() ?? '';
        final url =
            (sub['url'] ??
                    sub['subtitleUrl'] ??
                    sub['src'] ??
                    sub['link'] ??
                    '')
                .toString();
        final lang = (sub['lang'] ?? '').toString().toLowerCase();
        if (url.isEmpty) {
          debugPrint('Subtítulo sin URL: $sub');
          return;
        }
        final finalId = id.isNotEmpty ? id : url.hashCode.toString();
        await _applySubtitleFromUrl(
          url: url,
          id: finalId,
          lang: lang.isNotEmpty ? lang : null,
          enable: true,
        );
        await _saveActiveSubtitle(id: finalId, url: url, lang: lang);
      },
      onDisable: () {
        setState(() {
          _subtitlesEnabled = false;
          _currentSubtitleText = '';
          _currentSubtitleId = null;
          _currentSubtitleUrl = null;
        });
        _clearActiveSubtitleCache();
      },
    ).then((_) {
      if (!mounted || _isDisposing) return;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted || _isDisposing) return;
        final primary = FocusManager.instance.primaryFocus;
        final syncOpen =
            primary != null &&
            primary.debugLabel != null &&
            primary.debugLabel!.startsWith('sync_');
        if (syncOpen) return;

        setState(() {
          _showControls = true;
          _currentRow = 2;
        });
        _subsFocusNode.requestFocus();
        _scheduleHideControls();
      });
    });
  }

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
    if (_isPlaying) {
      _controller.pause();
    }

    final targetId = idcontenido ?? widget.idcontenido;
    final isSameContent =
        targetId == widget.idcontenido &&
        (temporada == null || temporada == widget.temporada) &&
        (capitulo == null || capitulo == widget.capitulo);
    final isNext = !isSameContent;

    String modalTitulo;
    if (titulo != null && titulo.isNotEmpty) {
      modalTitulo = titulo;
    } else if (isSameContent) {
      modalTitulo = _tituloContenido.isNotEmpty
          ? _tituloContenido
          : widget.titulo;
    } else {
      modalTitulo = _tituloContenido.isNotEmpty
          ? _tituloContenido
          : widget.titulo;
    }

    await showDialog(
      context: context,
      builder: (_) => ServidoresModalTv(
        idcontenido: targetId,
        temporada: isSameContent ? (temporada ?? widget.temporada) : temporada,
        capitulo: isSameContent ? (capitulo ?? widget.capitulo) : capitulo,
        tipo: tipo ?? widget.tipo,
        titulo: modalTitulo,
        fromPlayer: true,
        currentIdioma: isSameContent ? _idioma : null,
        currentServidorUrl: (isSameContent && !clearCurrentServer)
            ? _servidorUrl
            : null,
        currentServidorNombre: (isSameContent && !clearCurrentServer)
            ? _servidorNombre
            : null,
        esSiguienteCapitulo: isNext && (tipo ?? widget.tipo) == 'tv',
        backdropUrl: backdropUrl ?? (isSameContent ? _backdropUrl : null),
        logoUrl: logoUrl ?? (isSameContent ? _logoUrl : null),
        tmdbId: targetId,
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
    final currentFocused = _visibleActionNodes.cast<FocusNode?>().firstWhere(
      (n) => n != null && n.hasFocus,
      orElse: () => null,
    );
    _lastFocusedActionNode = currentFocused ?? _lastFocusedActionNode;
    _controlsWereShowingBeforeModal = _showControls;
    final imdb = (_apiData?['imdb_id'] ?? '').toString();
    final tmdbId =
        _apiData?['idtmdb'] as int? ??
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

    final savedPos = _controllerReady
        ? _controller.value.position
        : Duration.zero;

    await _saveCache();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _currentQualityLabel = selected.label;
      _currentQualityUrl = selected.isAuto ? null : selected.url;
      _hasHandledEnd = false;
      _showEndPrompt = false;
      _showNextEpisodeCard = false;
      _nextPromptUserDismissed = false;
      _nextPreloaded = false;
      _preloadTriggered = false;
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
      _keepScreenOn();
      _resetScreensaverTimer();

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

  void _silentPreloadNext() {
    try {
      if (!_hasRealNext) return;
      if (widget.tipo == 'tv') {
        int season = widget.temporada ?? 1;
        int episode = (widget.capitulo ?? 0) + 1;
        if (_siguiente != null) {
          season = (_siguiente!['temporada'] as num?)?.toInt() ?? season;
          episode = (_siguiente!['capitulo'] as num?)?.toInt() ?? episode;
        }
        _serverLoader.preloadNext(
          contentId: widget.tmdbId ?? widget.idcontenido,
          season: season,
          nextEpisode: episode,
          context: mounted ? context : null,
        );
      } else if (_recomendaciones.isNotEmpty) {
        final next = _recomendaciones.first;
        final id = next['idcontenido'] ?? next['tmdb_id'];
        final idInt = id is int ? id : int.tryParse('$id') ?? 0;
        if (idInt > 0) {
          _serverLoader.preloadNext(
            contentId: idInt,
            season: 0,
            nextEpisode: 0,
            context: mounted ? context : null,
          );
        }
      }
      if (mounted && !_isDisposing) {
        setState(() => _nextPreloaded = true);
      } else {
        _nextPreloaded = true;
      }
    } catch (_) {}
  }

  Future<void> _killController() async {
    try {
      if (_controllerReady) {
        try {
          _controller.removeListener(_videoListener);
        } catch (_) {}
        try {
          await _controller.pause();
        } catch (_) {}
        try {
          await _controller.dispose();
        } catch (_) {}
        _controllerReady = false;
      }
    } catch (_) {}
  }

  void _cancelPlayerTimers() {
    _hideControlsTimer?.cancel();
    _hideToolbarOnlyTimer?.cancel();
    _clockTimer?.cancel();
    _cacheTimer?.cancel();
    _screensaverTimer?.cancel();
    _fitToastTimer?.cancel();
    _seekHoldTimer?.cancel();
    _nextPromptHideTimer?.cancel();
    _skipIntroHideTimer?.cancel();
  }

  Future<void> _navigateToPlayer({
    required int idcontenido,
    int? tmdbId,
    int? temporada,
    int? capitulo,
    required String tipo,
    required String titulo,
  }) async {
    if (!mounted || _isReplacingPlayer) return;
    _isReplacingPlayer = true;

    try {
      await _saveCache();
    } catch (_) {}

    _cancelPlayerTimers();
    try {
      FocusManager.instance.removeListener(_onGlobalFocusChanged);
    } catch (_) {}
    await _killController();

    if (!mounted) return;

    final route = MaterialPageRoute(
      settings: RouteSettings(
        name:
            'player_$idcontenido'
            '_${temporada ?? 0}_${capitulo ?? 0}'
            '_${DateTime.now().microsecondsSinceEpoch}',
      ),
      builder: (_) => PlayerScreen(
        key: ValueKey(
          'player_$idcontenido'
          '_${temporada ?? 0}_${capitulo ?? 0}'
          '_${DateTime.now().microsecondsSinceEpoch}',
        ),
        videoUrl: '',
        idcontenido: idcontenido,
        tmdbId: tmdbId ?? idcontenido,
        temporada: temporada,
        capitulo: capitulo,
        tipo: tipo,
        titulo: titulo,
      ),
    );

    Navigator.of(context).pushReplacement(route);
  }

  void _goNextEpisode() {
    if (!_hasRealNext) return;
    if (widget.tipo == 'tv') {
      if (_siguiente == null) return;
      final s = (_siguiente!['temporada'] as num?)?.toInt();
      final c = (_siguiente!['capitulo'] as num?)?.toInt();
      final titulo = (_siguiente!['titulo'] ?? _tituloContenido).toString();
      _navigateToPlayer(
        idcontenido: widget.idcontenido,
        tmdbId: widget.tmdbId ?? widget.idcontenido,
        temporada: s,
        capitulo: c,
        tipo: 'tv',
        titulo: titulo.isNotEmpty ? titulo : widget.titulo,
      );
    } else {
      if (_recomendaciones.isEmpty) return;
      final next = _recomendaciones.first;
      final id = next['idcontenido'] ?? next['tmdb_id'];
      final idInt = id is int ? id : int.tryParse('$id') ?? 0;
      if (idInt <= 0) return;
      _navigateToPlayer(
        idcontenido: idInt,
        tmdbId: idInt,
        tipo: (next['tipo'] ?? 'movie').toString(),
        titulo: (next['titulo'] ?? next['title'] ?? widget.titulo).toString(),
      );
    }
  }

  void _handleVideoEnded() {
    if (!mounted || _isDisposing) return;
    if (_showBecauseYouWatched) return;
    if (!_hasRealNext) return;
    _goNextEpisode();
  }

  Future<void> _showExitConfirmation() async {
    final wasPlaying = _isPlaying;
    if (_isPlaying) {
      _controller.pause();
    }

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
                  Icon(
                    Icons.exit_to_app_rounded,
                    color: Colors.redAccent,
                    size: 26,
                  ),
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

  Future<void> _goBackToContent() async {
    if (_isReplacingPlayer) return;
    _isReplacingPlayer = false;
    try {
      await _saveCache();
    } catch (_) {}
    _cancelPlayerTimers();
    await _killController();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    _restoreOrientation();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  String _idiomaFlagUrl() {
    final c = _idioma.toLowerCase().trim();
    if (c == 'es_mx' ||
        c == 'es-mx' ||
        c == 'es_la' ||
        c == 'es-la' ||
        c == 'lat' ||
        c == 'es' ||
        c.contains('latino')) {
      return 'https://embed69.org/static/lang/LAT.png';
    }
    if (c == 'es_es' ||
        c == 'es-es' ||
        c == 'esp' ||
        c.contains('castellano')) {
      return 'https://embed69.org/static/lang/ESP.png';
    }
    return 'https://embed69.org/static/lang/SUB.png';
  }

  String _idiomaLabel() {
    final c = _idioma.toLowerCase().trim();
    if (c == 'es_mx' ||
        c == 'es-mx' ||
        c == 'es_la' ||
        c == 'es-la' ||
        c == 'lat' ||
        c == 'es' ||
        c.contains('latino')) {
      return 'Latino';
    }
    if (c == 'es_es' ||
        c == 'es-es' ||
        c == 'esp' ||
        c.contains('castellano')) {
      return 'Castellano';
    }
    return 'Subtitulado';
  }

  double? _fracOfDuration(double? sec) {
    if (sec == null || _totalDuration.inMilliseconds <= 0) return null;
    return (sec * 1000 / _totalDuration.inMilliseconds).clamp(0.0, 1.0);
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
      if (name.toString().isNotEmpty) {
        return '$s$e · $name';
      }
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
      } else if (widget.tipo == 'movie' && _recomendaciones.isNotEmpty) {
        setState(() => _currentRow = 4);
        if (_recoFocusNodes.isNotEmpty) {
          _recoFocusNodes[0].requestFocus();
          _scrollToFocus(_recoScrollController, 0, 200);
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
      if (widget.tipo == 'tv') {
        setState(() => _currentRow = 3);
        if (_seasonFocusNodes.isNotEmpty) {
          _seasonFocusNodes[_selectedSeasonIndex].requestFocus();
          _scrollToFocus(_seasonScrollController, _selectedSeasonIndex, 120);
        }
      } else {
        setState(() {
          _currentRow = 2;
          _currentCol = 0;
        });
        _playPauseFocusNode.requestFocus();
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
      final next = (_selectedSeasonIndex + 1).clamp(
        0,
        _seasonFocusNodes.length - 1,
      );
      setState(() {
        _selectedSeasonIndex = next;
        _rebuildEpisodeFocusNodes();
      });
      _seasonFocusNodes[next].requestFocus();
      _scrollToFocus(_seasonScrollController, next, 120);
    } else if (_currentRow == 4) {
      if (widget.tipo == 'tv' && _episodeFocusNodes.isNotEmpty) {
        final idx = _episodeFocusNodes.indexWhere((n) => n.hasFocus);
        final next = (idx + 1).clamp(0, _episodeFocusNodes.length - 1);
        _episodeFocusNodes[next].requestFocus();
        _scrollToFocus(_episodeScrollController, next, 170);
      } else if (_recoFocusNodes.isNotEmpty) {
        final idx = _recoFocusNodes.indexWhere((n) => n.hasFocus);
        final next = (idx + 1).clamp(0, _recoFocusNodes.length - 1);
        _recoFocusNodes[next].requestFocus();
        _scrollToFocus(_recoScrollController, next, 200);
      }
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
      final prev = (_selectedSeasonIndex - 1).clamp(
        0,
        _seasonFocusNodes.length - 1,
      );
      setState(() {
        _selectedSeasonIndex = prev;
        _rebuildEpisodeFocusNodes();
      });
      _seasonFocusNodes[prev].requestFocus();
      _scrollToFocus(_seasonScrollController, prev, 120);
    } else if (_currentRow == 4) {
      if (widget.tipo == 'tv' && _episodeFocusNodes.isNotEmpty) {
        final idx = _episodeFocusNodes.indexWhere((n) => n.hasFocus);
        final prev = (idx - 1).clamp(0, _episodeFocusNodes.length - 1);
        _episodeFocusNodes[prev].requestFocus();
        _scrollToFocus(_episodeScrollController, prev, 170);
      } else if (_recoFocusNodes.isNotEmpty) {
        final idx = _recoFocusNodes.indexWhere((n) => n.hasFocus);
        final prev = (idx - 1).clamp(0, _recoFocusNodes.length - 1);
        _recoFocusNodes[prev].requestFocus();
        _scrollToFocus(_recoScrollController, prev, 200);
      }
    }
  }

  void _scrollToFocus(
    ScrollController controller,
    int index,
    double itemWidth,
  ) {
    if (!controller.hasClients) return;
    final offset =
        (index * itemWidth) -
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
    _nextPromptHideTimer?.cancel();
    _skipIntroHideTimer?.cancel();
    FocusManager.instance.removeListener(_onGlobalFocusChanged);

    // Si ya se liberó el controller en _navigateToPlayer, no volver a dispose.
    try {
      if (_controllerReady) {
        _controller.removeListener(_videoListener);
        try {
          _controller.pause();
        } catch (_) {}
        try {
          _controller.dispose();
        } catch (_) {}
        _controllerReady = false;
      }
    } catch (_) {}

    // CRÍTICO (Android TV): si estamos reemplazando el player, NO apagar
    // wakelock ni restaurar orientación. El dispose del player viejo corre
    // DESPUÉS del initState del nuevo y mataría el wakelock del nuevo.
    if (!_isReplacingPlayer) {
      try {
        WakelockPlus.disable();
      } catch (_) {}
      try {
        _restoreOrientation();
      } catch (_) {}
    }

    _skipIntroFocusNode.dispose();
    _nextPromptFocusNode.dispose();
    _errorServersFocusNode.dispose();
    _errorBackFocusNode.dispose();
    _exitContinueFocusNode.dispose();
    _exitConfirmFocusNode.dispose();
    _byProducirSiguienteFocusNode.dispose();
    _byContinuarCreditosFocusNode.dispose();
    _playerScopeNode.dispose();
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
    return FocusScope(
      node: _playerScopeNode,
      autofocus: true,
      child: PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _videoFocusNode,
          autofocus: true,
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
                    child: AnimatedOpacity(
                      opacity: 1,
                      duration: const Duration(milliseconds: 150),
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
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (!_isLoading &&
                  _errorMessage.isEmpty &&
                  _subtitlesEnabled &&
                  !_showBecauseYouWatched)
                SubtitleWidget(
                  text: _currentSubtitleText,
                  isActive: _currentSubtitleText.isNotEmpty,
                  bottomPadding: (_showControls || _showToolbarOnly)
                      ? (_showSeasonsAndEpisodes ? 300.0 : 160.0)
                      : 40.0,
                  fontSize: _subtitleFontSize,
                  textColor: Colors.white,
                  strokeColor: Colors.black,
                  strokeWidth: 2.5,
                  fontWeight: _subtitleBold ? FontWeight.w800 : FontWeight.w600,
                  maxWidth: 780,
                  verticalOffset: _subtitleVerticalOffset,
                ),

              if (!_isLoading &&
                  _errorMessage.isEmpty &&
                  !_showBecauseYouWatched)
                Positioned(
                  right: 28,
                  bottom: (_showControls || _showToolbarOnly)
                      ? (_showSeasonsAndEpisodes ? 280.0 : 150.0)
                      : 48.0,
                  child: _buildSkipIntroButton(),
                ),

              if (!_isLoading &&
                  _errorMessage.isEmpty &&
                  _hasRealNext &&
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
                    autoHideMs: 15000,
                    onPlay: _goNextEpisode,
                    onDismiss: () {
                      final hadFocus = _nextPromptFocusNode.hasFocus;
                      setState(() {
                        _showNextEpisodeCard = false;
                        _nextPromptUserDismissed = true;
                        _nextPromptAutoHidden = false;
                      });
                      if (hadFocus) _releaseOverlayFocusToSafe();
                    },
                    onAutoHide: () {
                      final hadFocus = _nextPromptFocusNode.hasFocus;
                      setState(() {
                        _showNextEpisodeCard = false;
                        _nextPromptAutoHidden = true;
                      });
                      if (hadFocus) _releaseOverlayFocusToSafe();
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
                  nextIdContenido: _recomendaciones.first['idcontenido'] as int,
                  nextTitulo: (_recomendaciones.first['titulo'] ?? '')
                      .toString(),
                  nextPoster: _recomendaciones.first['poster']?.toString(),
                  nextBackdrop: _recomendaciones.first['backdrop']?.toString(),
                  nextLogo: _recomendaciones.first['logo']?.toString(),
                  nextTipo: (_recomendaciones.first['tipo'] ?? 'movie')
                      .toString(),
                  accentColor: accentOrange,
                  optimizeTmdbUrl: _optimizeTmdbUrl,
                  producirSiguienteFocusNode: _byProducirSiguienteFocusNode,
                  continuarCreditosFocusNode: _byContinuarCreditosFocusNode,
                  isBackKey: _isBackKey,
                  onContinuarCreditos: () {
                    setState(() {
                      _showBecauseYouWatched = false;
                      _showNextEpisodeCard = false;
                    });
                    _showControlsOverlayNow();
                  },
                  onProducirSiguiente: () {
                    setState(() => _showBecauseYouWatched = false);
                    _goNextEpisode();
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
    ),
    );
  }

  Widget _buildSkipIntroButton() {
    // AnimatedVisibility estilo Nuvio: fade + scale
    return AnimatedScale(
      scale: _showSkipIntro ? 1.0 : 0.8,
      duration: Duration(milliseconds: _showSkipIntro ? 300 : 200),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showSkipIntro ? 1.0 : 0.0,
        duration: Duration(milliseconds: _showSkipIntro ? 300 : 200),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !_showSkipIntro,
          child: Focus(
            focusNode: _skipIntroFocusNode,
            onKeyEvent: (node, event) {
              if (!_showSkipIntro) return KeyEventResult.ignored;
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
                if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                    _showNextEpisodeCard) {
                  _nextPromptFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (_isBackKey(event)) {
                  _dismissSkipIntro();
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
                    width: 168,
                    decoration: BoxDecoration(
                      color: hasFocus
                          ? Colors.white
                          : const Color(0xD91E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasFocus
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                        width: hasFocus ? 2 : 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fast_forward_rounded,
                                size: 20,
                                color: hasFocus ? Colors.black : Colors.white,
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
                        // Barra de auto-hide (10s) estilo Nuvio
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(7),
                            bottomRight: Radius.circular(7),
                          ),
                          child: LinearProgressIndicator(
                            value: _skipIntroHideProgress.clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation(
                              hasFocus
                                  ? accentOrange
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
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
                    Icon(
                      icon,
                      size: 20,
                      color: hasFocus ? Colors.white : Colors.white70,
                    ),
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
            highlight: _nextPreloaded,
            iconOnly: true,
          ),
        const Spacer(),
        _buildActionBtn(
          _subsFocusNode,
          _subtitlesEnabled
              ? Icons.closed_caption_rounded
              : Icons.closed_caption_disabled_rounded,
          'Subtítulos',
          _openSubtitlesModal,
          iconOnly: true,
        ),
        const SizedBox(width: 10),
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
                    SizedBox(
                      width: 52,
                      child: Text(
                        _formatDuration(_currentPosition),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          trackShape: _SegmentedVideoTrackShape(
                            introStart: _fracOfDuration(_introStartSec),
                            introEnd: _fracOfDuration(_introEndSec),
                            outroStart: _fracOfDuration(_outroStartSec),
                            outroEnd: _fracOfDuration(_outroEndSec),
                            recapStart: _fracOfDuration(_recapStartSec),
                            recapEnd: _fracOfDuration(_recapEndSec),
                            nextThreshold: _nextThresholdPct,
                            activeColor: accentOrange,
                            inactiveColor:
                                Colors.white.withValues(alpha: 0.22),
                            segmentColor: const Color(0xFF2ECC71),
                          ),
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius:
                                _seekBarFocusNode.hasFocus ? 8 : 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: accentOrange,
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.22),
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
                          onChanged: (v) => _controller
                              .seekTo(Duration(seconds: v.toInt())),
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
                    SizedBox(
                      width: 58,
                      child: Text(
                        '-${_formatDuration(_totalDuration - _currentPosition)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
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

            if (_showSeasonsAndEpisodes) ...[
              const SizedBox(height: 14),
              if (widget.tipo == 'tv' && _temporadas.isNotEmpty)
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
                    _navigateToPlayer(
                      idcontenido: widget.idcontenido,
                      tmdbId: widget.tmdbId ?? widget.idcontenido,
                      temporada: temporada,
                      capitulo: capitulo,
                      tipo: 'tv',
                      titulo: _tituloContenido.isNotEmpty
                          ? _tituloContenido
                          : widget.titulo,
                    );
                  },
                  onArrowUp: _moveFocusUp,
                  onArrowDown: _moveFocusDown,
                  onArrowLeft: _moveFocusLeft,
                  onArrowRight: _moveFocusRight,
                  isBackKey: _isBackKey,
                  onBack: _handleBackPressed,
                  getFocusEpisodeIndex: _getFocusEpisodeIndex,
                )
              else if (_recomendaciones.isNotEmpty)
                VerDespuesList(
                  items: _recomendaciones,
                  focusNodes: _recoFocusNodes,
                  scrollController: _recoScrollController,
                  progressMap: _recoProgress,
                  accentColor: accentOrange,
                  optimizeTmdbUrl: _optimizeTmdbUrl,
                  onSelect: (id) {
                    final idInt = id is int ? id : int.tryParse('$id') ?? 0;
                    if (idInt <= 0) return;
                    final rec = _recomendaciones.cast<dynamic>().firstWhere(
                      (e) => e['idcontenido'] == idInt,
                      orElse: () => <String, dynamic>{},
                    );
                    _navigateToPlayer(
                      idcontenido: idInt,
                      tmdbId: idInt,
                      tipo: (rec['tipo'] ?? 'movie').toString(),
                      titulo: (rec['titulo'] ?? rec['title'] ?? widget.titulo)
                          .toString(),
                    );
                  },
                  onArrowUp: _moveFocusUp,
                  onArrowLeft: _moveFocusLeft,
                  onArrowRight: _moveFocusRight,
                  isBackKey: _isBackKey,
                  onBack: _handleBackPressed,
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
          setState(() {});
        } else {
          setState(() {});
        }
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
          final label = _isBuffering
              ? 'Cargando'
              : (_isPlaying ? 'Pausa' : 'Play');
          final icon = _isBuffering
              ? null
              : (_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded);

          return GestureDetector(
            onTap: _isBuffering ? null : _togglePlay,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                    Icon(
                      icon,
                      size: 18,
                      color: hasFocus ? Colors.black : Colors.white,
                    ),
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
          setState(() {});
        } else {
          setState(() {});
        }
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
                  Icon(
                    icon,
                    size: 18,
                    color: hasFocus ? Colors.black : Colors.white,
                  ),
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