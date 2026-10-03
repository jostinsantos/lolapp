import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../content/presentation/content_page.dart';
import 'servidores_modal.dart';
import '../../../player/presentation/subtitles/subtitle_widget.dart';
import 'hls_quality_widget.dart';
import '../../../player/presentation/subtitles/subtitle_selector.dart'; // ← NUEVO
import '../../../../data/datasources/remote/tmdb/tmdb_player_api.dart';
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

enum _VideoFitMode { contain, cover, fill, fitWidth, fitHeight }

class PlayerScreen extends StatefulWidget {
  final String videoUrl;
  final int idcontenido;
  final int? temporada;
  final int? capitulo;
  final String tipo;
  final String titulo;
  final int? tmdbId;
  final String? idioma;
  final Map<String, String>? headers;
  final String? fuente;

  const PlayerScreen({
    super.key,
    required this.videoUrl,
    required this.idcontenido,
    this.temporada,
    this.capitulo,
    required this.tipo,
    required this.titulo,
    this.tmdbId,
    this.idioma,
    this.headers,
    this.fuente,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Color accentOrange = Color(0xFFFF6B00);
  static const Color netflixRed = Color(0xFFE50914);

  final TmdbPlayerService _tmdbPlayer = TmdbPlayerService();
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );

  late VideoPlayerController _controller;
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _subtitlesEnabled = true;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String _errorMessage = '';
  bool _showControls = true;
  bool _isBuffering = false;
  Timer? _hideControlsTimer;
  bool _isDragging = false;
  bool _isDisposing = false;
  bool _controllerReady = false;

  List<_SubtitleCue> _subtitleCues = const [];
  String _currentSubtitleText = '';

  // OpenSubtitles state
  String? _selectedSubtitleId;
  String _selectedSubtitleLabel = 'Subs';
  double _subtitleOffsetSec = 0.0;
  double _subtitleFontSize = 18.0;
  bool _subtitleBold = true;
  double _subtitleVerticalOffset = 0.0;

  static const String _prefSubIdKey = 'player_sub_id_';
  static const String _prefSubUrlKey = 'player_sub_url_';
  static const String _prefSubLangKey = 'player_sub_lang_';
  static const String _prefSubOffsetKey = 'subtitulo_offset_sec';
  static const String _prefSubFontKey = 'subtitulo_font_size';
  static const String _prefSubBoldKey = 'subtitulos_negrita';
  static const String _prefSubVertKey = 'subtitulo_vertical_offset';

  Map<String, dynamic>? _apiData;
  String? _backdropUrl;
  String? _logoUrl;
  String _tituloContenido = '';
  String? _tituloCapitulo;
  String? _capituloFmt;
  List<dynamic> _temporadas = const [];
  List<dynamic> _recomendaciones = const [];
  int _selectedSeasonIndex = 0;
  Map<String, dynamic>? _siguiente;
  String _idioma = 'ES';

  String _currentQualityLabel = 'Auto';
  String? _currentQualityUrl;

  int _lastPositionUpdateMs = 0;
  static const int _positionThrottleMs = 250;

  bool _showEndPrompt = false;
  bool _hasHandledEnd = false;
  bool _showBottomPanel = false;
  bool _showNextButton = false;

  double? _introStartSec;
  double? _introEndSec;
  bool _showSkipIntro = false;

  // ─── Video Fit ──────────────────────────────────────────────────────────
  _VideoFitMode _fitMode = _VideoFitMode.contain;

  BoxFit get _currentBoxFit {
    switch (_fitMode) {
      case _VideoFitMode.contain:
        return BoxFit.contain;
      case _VideoFitMode.cover:
        return BoxFit.cover;
      case _VideoFitMode.fill:
        return BoxFit.fill;
      case _VideoFitMode.fitWidth:
        return BoxFit.fitWidth;
      case _VideoFitMode.fitHeight:
        return BoxFit.fitHeight;
    }
  }

  String get _fitModeLabel {
    switch (_fitMode) {
      case _VideoFitMode.contain:
        return 'Original';
      case _VideoFitMode.cover:
        return 'Expandir';
      case _VideoFitMode.fill:
        return 'Estirar';
      case _VideoFitMode.fitWidth:
        return 'Ancho';
      case _VideoFitMode.fitHeight:
        return 'Alto';
    }
  }

  IconData get _fitModeIcon {
    switch (_fitMode) {
      case _VideoFitMode.contain:
        return Icons.fit_screen_rounded;
      case _VideoFitMode.cover:
        return Icons.aspect_ratio_rounded;
      case _VideoFitMode.fill:
        return Icons.open_in_full_rounded;
      case _VideoFitMode.fitWidth:
        return Icons.swap_horiz_rounded;
      case _VideoFitMode.fitHeight:
        return Icons.swap_vert_rounded;
    }
  }

  void _cycleFitMode() {
    setState(() {
      final values = _VideoFitMode.values;
      _fitMode = values[(_fitMode.index + 1) % values.length];
    });
    _scheduleHideControls();
  }

  int get _resolvedId {
    final id = widget.tmdbId ?? widget.idcontenido;
    return id > 0 ? id : 0;
  }

  String get _mediaType {
    final t = widget.tipo.toLowerCase();
    return t == 'tv' ? 'tv' : 'movie';
  }

  bool get _hasBottomContent =>
      _mediaType == 'tv' && _temporadas.isNotEmpty;

  List<dynamic> _filterTemporadas(List<dynamic> raw) {
    final now = DateTime.now();
    final out = <dynamic>[];
    for (final t in raw) {
      if (t is! Map) continue;
      final num = t['numero'];
      final n = num is int ? num : int.tryParse('$num') ?? -1;
      if (n <= 0) continue;
      final capsRaw = t['capitulos'] is List ? List<dynamic>.from(t['capitulos'] as List) : <dynamic>[];
      final caps = <dynamic>[];
      for (final c in capsRaw) {
        if (c is! Map) continue;
        final air = (c['air_date'] ?? c['fecha'] ?? c['fecha_estreno'] ?? '').toString();
        if (air.isNotEmpty) {
          final d = DateTime.tryParse(air);
          if (d != null && d.isAfter(now)) continue;
        }
        caps.add(c);
      }
      if (caps.isEmpty) continue;
      final copy = Map<String, dynamic>.from(t);
      copy['capitulos'] = caps;
      out.add(copy);
    }
    return out;
  }

  String _optimizeTmdbUrl(String? url, {String size = 'w500'}) {
    if (url == null || url.isEmpty) return '';
    if (url.contains('image.tmdb.org/t/p/')) {
      return url.replaceFirstMapped(
        RegExp(r'/t/p/(original|w\d+|h\d+)/'),
        (m) => '/t/p/$size/',
      );
    }
    if (url.startsWith('/')) {
      return 'https://image.tmdb.org/t/p/$size$url';
    }
    return url;
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

  @override
  void initState() {
    super.initState();
    if (widget.idioma != null && widget.idioma!.isNotEmpty) {
      _idioma = widget.idioma!.toUpperCase();
    }
    _setupSystemUi();
    _keepScreenOn();
    _loadApiData().then((_) {
      _initializePlayer();
      _loadSubtitles();
    });
    _loadRecommendationsFromGuardados();
    _loadSubtitlePrefs();
  }

  void _setupSystemUi() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreSystemUi() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _keepScreenOn() => WakelockPlus.enable();

  // ─── CACHÉ ──────────────────────────────────────────────────────────────
  String _getCacheKey() {
    if (_mediaType == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'cachePlayer_${_resolvedId}_T${widget.temporada}_C${widget.capitulo}';
    }
    return 'cachePlayer_$_resolvedId';
  }

  String _getCacheKeyRapido() {
    if (_mediaType == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'cachePlayerRapido_${_resolvedId}_T${widget.temporada}_C${widget.capitulo}';
    }
    return 'cachePlayerRapido_$_resolvedId';
  }

  Future<void> _saveCache() async {
    if (!_controllerReady || !_controller.value.isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    final pos = _controller.value.position.inSeconds;

    String? backdrop = _backdropUrl;
    if (_apiData != null) {
      final b = _apiData!['backdrop'] ?? _apiData!['backdrop_path'];
      if (b is String && b.isNotEmpty) backdrop = b;
    }

    final full = {
      'idcontenido': _resolvedId,
      'temporada': widget.temporada,
      'capitulo': widget.capitulo,
      'segundo': pos,
      'titulo': _tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo,
      'tipo': _mediaType,
      'videoUrl': widget.videoUrl,
      'backdrop': backdrop ?? '',
      'timestamp': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_getCacheKey(), jsonEncode(full));

    final rapido = {
      'idcontenido': _resolvedId,
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

  // ─── Cargar datos desde TMDB ────────────────────────────────────────────
  Future<void> _loadApiData() async {
    try {
      final data = await _tmdbPlayer.fetchPlayer(
        tmdbId: _resolvedId,
        mediaType: _mediaType,
        temporada: widget.temporada ?? 0,
        capitulo: widget.capitulo ?? 0,
      );

      if (data['error'] == true) {
        debugPrint('TmdbPlayerService error: ${data['mensaje']}');
        return;
      }

      if (!mounted || _isDisposing) return;

      setState(() {
        _apiData = data;
        _backdropUrl = _optimizeTmdbUrl(
          data['backdrop']?.toString(),
          size: 'w780',
        );
        _logoUrl = _optimizeTmdbUrl(data['logo']?.toString(), size: 'w500');
        _tituloContenido =
            data['titulo_contenido']?.toString() ?? widget.titulo;
        _tituloCapitulo = data['titulo_capitulo']?.toString();
        _capituloFmt = data['capitulo']?.toString();
        _temporadas = _filterTemporadas(
          data['temporadas'] is List
              ? List<dynamic>.from(data['temporadas'] as List)
              : const [],
        );
        _siguiente = data['siguiente'] is Map
            ? Map<String, dynamic>.from(data['siguiente'] as Map)
            : null;

        if (data['recomendaciones'] is List) {
          _recomendaciones = List<dynamic>.from(
            data['recomendaciones'] as List,
          );
        }

        if (widget.temporada != null && _temporadas.isNotEmpty) {
          final idx = _temporadas.indexWhere(
            (t) => (t is Map && t['numero'] == widget.temporada),
          );
          if (idx >= 0) _selectedSeasonIndex = idx;
        }
      });
      _loadIntroSkip();
    } catch (e) {
      debugPrint('Error API player TMDB: $e');
    }
  }

  Future<void> _loadIntroSkip() async {
    try {
      final imdb = (_apiData?['imdb_id'] ?? '').toString().trim();
      if (imdb.isEmpty) return;

      final season = widget.temporada ?? _apiData?['temporada'];
      final episode = widget.capitulo ?? _apiData?['numero_capitulo'];

      final params = <String, String>{'imdb_id': imdb, 'segment_type': 'intro'};
      if (season != null) params['season'] = season.toString();
      if (episode != null) params['episode'] = episode.toString();

      final uri = Uri.https('api.introdb.app', '/segments', params);
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || !mounted || _isDisposing) return;

      final data = jsonDecode(res.body);
      final intro = data['intro'];
      if (intro is Map) {
        final start = intro['start_sec'];
        final end = intro['end_sec'];
        if (start != null && end != null && mounted && !_isDisposing) {
          setState(() {
            _introStartSec = (start as num).toDouble();
            _introEndSec = (end as num).toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint('Error intro skip: $e');
    }
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
    }
  }

  void _skipIntro() {
    if (_introEndSec == null || !_controllerReady) return;
    final target = Duration(milliseconds: (_introEndSec! * 1000).round());
    _controller.seekTo(target);
    setState(() => _showSkipIntro = false);
    _scheduleHideControls();
  }

  void _seekBy(int seconds) {
    if (!_controllerReady) return;
    var newPos = _currentPosition + Duration(seconds: seconds);
    if (newPos < Duration.zero) newPos = Duration.zero;
    if (newPos > _totalDuration) newPos = _totalDuration;
    _controller.seekTo(newPos);
    _scheduleHideControls();
  }

  Future<void> _loadRecommendationsFromGuardados() async {
    if (_recomendaciones.isNotEmpty) return;
    try {
      final items = await GuardadosCache.getAll();
      final filtered = items
          .where((e) => e['idcontenido'] != _resolvedId)
          .take(8)
          .toList();

      final adapted = filtered.map((e) {
        return <String, dynamic>{
          'idcontenido': e['idcontenido'],
          'tmdb_id': e['idcontenido'],
          'titulo': e['title'] ?? '',
          'poster': _optimizeTmdbUrl(
            (e['poster_path'] ?? e['backdrop_path'] ?? '').toString(),
            size: 'w342',
          ),
          'backdrop': _optimizeTmdbUrl(
            (e['backdrop_path'] ?? e['poster_path'] ?? '').toString(),
            size: 'w500',
          ),
          'tipo': e['type'] ?? e['media_type'] ?? 'movie',
        };
      }).toList();

      if (mounted && !_isDisposing && _recomendaciones.isEmpty) {
        setState(() => _recomendaciones = adapted);
      }
    } catch (e) {
      debugPrint('Error cargando guardados: $e');
    }
  }

  Map<String, String> _playerHeaders() {
    final url = widget.videoUrl.toLowerCase();
    final isNet =
        url.contains('hakunaymatata.com') ||
        url.contains('net27.cc') ||
        url.contains('/bt/');

    if (isNet) {
      return {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': 'https://net27.cc/',
        'Origin': 'https://net27.cc',
        'Accept': '*/*',
        'Range': 'bytes=0-',
      };
    }

    final h = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': '*/*',
      if (widget.headers != null) ...widget.headers!,
    };
    return h;
  }

  Future<void> _initializePlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: _playerHeaders(),
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
      });
      _controller.play();
      setState(() => _isPlaying = true);
      _scheduleHideControls();
    } catch (e) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar el video: $e';
      });
    }
  }

  // ─── Subtítulos originales (fallback) ───────────────────────────────────
  Future<void> _loadSubtitles() async {
    try {
      final fromApi = _apiData?['subtitulo']?.toString();
      final url = (fromApi != null && fromApi.isNotEmpty)
          ? fromApi
          : 'https://modlyo.com/subtitulo/contenido/$_resolvedId/es_MX.vtt';

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

  // ─── Actualizar subtítulo con OFFSET ────────────────────────────────────
  void _updateCurrentSubtitle() {
    if (!_subtitlesEnabled || _subtitleCues.isEmpty) {
      if (_currentSubtitleText.isNotEmpty) _currentSubtitleText = '';
      return;
    }

    final adjustedPos =
        _currentPosition +
        Duration(milliseconds: (_subtitleOffsetSec * 1000).round());

    String newText = '';
    for (final cue in _subtitleCues) {
      if (adjustedPos >= cue.start && adjustedPos <= cue.end) {
        newText = cue.text;
        break;
      }
      if (adjustedPos < cue.start) break;
    }
    if (newText != _currentSubtitleText) {
      _currentSubtitleText = newText;
    }
  }

  // ─── Cargar subtítulo desde OpenSubtitles ───────────────────────────────
  Future<void> _loadSelectedSubtitle(Map<String, dynamic> sub) async {
    final url = sub['url']?.toString();
    final id = sub['id']?.toString() ?? '';
    final lang = (sub['lang'] ?? '').toString().toLowerCase();
    final fileName = sub['subtitleFileName']?.toString() ?? 'sub.srt';

    if (url == null || url.isEmpty) return;

    try {
      final finalId = id.isNotEmpty ? id : url.hashCode.toString();
      final cacheKey = 'os_sub_${_resolvedId}_$finalId';
      final content = await SubtitleUtils.downloadAndCache(
        url: url,
        cacheKey: cacheKey,
        fileName: fileName,
      );

      final cues = _parseVtt(content);

      if (mounted && !_isDisposing) {
        setState(() {
          _subtitleCues = cues;
          _subtitlesEnabled = true;
          _selectedSubtitleId = finalId;
          _selectedSubtitleLabel = lang.isNotEmpty
              ? lang.toUpperCase()
              : 'Subs';
          _currentSubtitleText = '';
        });
        await _saveActiveSubtitle(id: finalId, url: url, lang: lang);
      }
    } catch (e) {
      debugPrint('Error cargando subtítulo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No se pudo cargar el subtítulo'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  Future<void> _loadSubtitlePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final offset = prefs.getDouble(_prefSubOffsetKey) ?? 0.0;
      final font = prefs.getDouble(_prefSubFontKey) ?? 18.0;
      final bold = prefs.getBool(_prefSubBoldKey) ?? true;
      final vert = prefs.getDouble(_prefSubVertKey) ?? 0.0;
      final savedId = prefs.getString('$_prefSubIdKey$_resolvedId');
      final savedUrl = prefs.getString('$_prefSubUrlKey$_resolvedId');
      final savedLang = prefs.getString('$_prefSubLangKey$_resolvedId');
      if (!mounted || _isDisposing) return;
      setState(() {
        _subtitleOffsetSec = offset.clamp(-30.0, 30.0);
        _subtitleFontSize = font.clamp(12.0, 36.0);
        _subtitleBold = bold;
        _subtitleVerticalOffset = vert.clamp(-40.0, 160.0);
        _selectedSubtitleId = savedId;
        if (savedLang != null && savedLang.isNotEmpty) {
          _selectedSubtitleLabel = savedLang.toUpperCase();
        }
      });
      if (savedUrl != null && savedUrl.isNotEmpty) {
        await _loadSelectedSubtitle({
          'url': savedUrl,
          'id': savedId ?? '',
          'lang': savedLang ?? '',
          'subtitleFileName': 'cached.vtt',
        });
      }
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
      await prefs.setString('$_prefSubIdKey$_resolvedId', id);
      await prefs.setString('$_prefSubUrlKey$_resolvedId', url);
      if (lang != null && lang.isNotEmpty) {
        await prefs.setString('$_prefSubLangKey$_resolvedId', lang);
      }
    } catch (_) {}
  }

  Future<void> _clearActiveSubtitleCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefSubIdKey$_resolvedId');
      await prefs.remove('$_prefSubUrlKey$_resolvedId');
    } catch (_) {}
  }

  Future<void> _openSubtitlesModal() async {
    _hideControlsTimer?.cancel();

    final imdb = (_apiData?['imdb_id'] ?? '').toString().trim();

    final cuesForModal = _subtitleCues.map((c) {
      return {'start': c.start, 'end': c.end, 'text': c.text};
    }).toList();

    await OpenSubtitlesModal.show(
      context: context,
      imdbId: imdb.isEmpty ? null : imdb,
      mediaType: _mediaType,
      season: widget.temporada ?? _apiData?['temporada'],
      episode: widget.capitulo ?? _apiData?['numero_capitulo'],
      currentSubtitleId: _selectedSubtitleId,
      subtitleOffsetSec: _subtitleOffsetSec,
      subtitleFontSize: _subtitleFontSize,
      subtitleBold: _subtitleBold,
      subtitleVerticalOffset: _subtitleVerticalOffset,
      cues: cuesForModal,
      currentPosition: _currentPosition,
      positionListenable: _positionNotifier, // ← esto
    
      onOffsetChanged: (v) {
        setState(() => _subtitleOffsetSec = v);
        _saveSubtitleStylePrefs();
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
      onSubtitleSelected: _loadSelectedSubtitle,
      onDisable: () {
        setState(() {
          _subtitlesEnabled = false;
          _subtitleCues = const [];
          _currentSubtitleText = '';
          _selectedSubtitleId = null;
          _selectedSubtitleLabel = 'Subs';
        });
        _clearActiveSubtitleCache();
      },
    );

    if (mounted) _scheduleHideControls();
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

    bool needsSetState = false;

    if (shouldUpdatePosition) {
      _currentPosition = value.position;
      _positionNotifier.value = value.position;
      _currentPosition = value.position;
      _lastPositionUpdateMs = nowMs;
      _updateCurrentSubtitle();
      final prevSkip = _showSkipIntro;
      _updateSkipIntroVisibility();
      if (prevSkip != _showSkipIntro) needsSetState = true;
      needsSetState = true;

      if (_totalDuration.inSeconds > 30) {
        final remaining = _totalDuration - _currentPosition;
        final progress =
            _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;

        final nearEnd =
            progress >= 0.90 ||
            (remaining <= const Duration(minutes: 3) &&
                remaining > const Duration(seconds: 2));

        if (nearEnd != _showNextButton) {
          _showNextButton = nearEnd;
          needsSetState = true;
        }

        if (nearEnd != _showEndPrompt) {
          _showEndPrompt = nearEnd;
          needsSetState = true;
        }

        if (progress >= 0.98) {
          _saveCache();
        }

        if (!_hasHandledEnd &&
            _currentPosition >= _totalDuration - const Duration(seconds: 1)) {
          _hasHandledEnd = true;
          _saveCache();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isDisposing) _handleVideoEnded();
          });
        }
      }
    }

    if (newPlaying != _isPlaying) {
      _isPlaying = newPlaying;
      needsSetState = true;
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
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_showControls || _isDragging || _showBottomPanel) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isDisposing) {
        setState(() {
          _showControls = false;
          _showBottomPanel = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) _showBottomPanel = false;
    });
    if (_showControls) _scheduleHideControls();
  }

  void _togglePlay() {
    if (!_controllerReady) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    _scheduleHideControls();
  }

  void _restart() {
    if (!_controllerReady) return;
    _controller.seekTo(Duration.zero);
    _controller.play();
    _scheduleHideControls();
  }

  Future<void> _openServersModal({
    int? idcontenido,
    int? temporada,
    int? capitulo,
    String? tipo,
    bool isNext = false,
  }) async {
    _hideControlsTimer?.cancel();
    await _saveCache();

    final wasPlaying = _isPlaying;
    if (_isPlaying) _controller.pause();

    final id = idcontenido ?? _resolvedId;
    final media = tipo ?? _mediaType;

    await showDialog(
      context: context,
      builder: (_) => ServidoresModal(
        idcontenido: id,
        tmdbId: id,
        temporada: temporada ?? widget.temporada,
        capitulo: capitulo ?? widget.capitulo,
        tipo: media,
        titulo: _tituloContenido.isNotEmpty ? _tituloContenido : widget.titulo,
        fuente: widget.fuente ?? '',
        fromPlayer: true,
        esSiguienteCapitulo: isNext,
        backdropUrl: _backdropUrl,
        logoUrl: _logoUrl,
      ),
    );

    if (mounted && !_isDisposing && wasPlaying) {
      _controller.play();
      _scheduleHideControls();
    }
  }

  void _openInfoModal() {
    _hideControlsTimer?.cancel();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _logoUrl != null && _logoUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _logoUrl!,
                              height: 42,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              memCacheHeight: 84,
                              errorWidget: (_, __, ___) => Text(
                                _tituloContenido,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Text(
                              _tituloContenido,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_capituloFmt != null || _tituloCapitulo != null) ...[
                        Text(
                          [
                            if (_capituloFmt != null) _capituloFmt,
                            if (_tituloCapitulo != null) _tituloCapitulo,
                          ].whereType<String>().join(' · '),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_apiData?['calificacion'] != null) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_apiData!['calificacion']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_apiData?['fecha_salida'] != null) ...[
                              const SizedBox(width: 12),
                              Text(
                                _apiData!['fecha_salida'].toString().length >= 4
                                    ? _apiData!['fecha_salida']
                                          .toString()
                                          .substring(0, 4)
                                    : '',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        _apiData?['overview']?.toString() ?? 'Sin descripción',
                        style: TextStyle(
                          color: Colors.grey[300],
                          height: 1.45,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _scheduleHideControls());
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
      if (mounted && !_isDisposing) _scheduleHideControls();
      return;
    }

    final currentUrl = _currentQualityUrl ?? widget.videoUrl;
    if (selected.url == currentUrl) {
      _scheduleHideControls();
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
      _showNextButton = false;
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
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(selected.url),
        httpHeaders: _playerHeaders(),
      );
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
      });

      await _controller.play();
      setState(() => _isPlaying = true);
      _scheduleHideControls();
    } catch (e) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cambiar calidad: $e';
      });
    }
  }

  void _goNextEpisode() {
    if (_mediaType != 'tv' || _siguiente == null) return;
    _openServersModal(
      temporada: _siguiente!['temporada'] as int?,
      capitulo: _siguiente!['capitulo'] as int?,
      isNext: true,
    );
  }

  void _handleVideoEnded() {
    if (!mounted || _isDisposing) return;
    setState(() {
      _showNextButton = true;
      _showControls = true;
    });
  }

  Future<void> _showExitConfirmation() async {
    final wasPlaying = _isPlaying;
    if (_isPlaying) _controller.pause();
    await _saveCache();

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Salir del reproductor?',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'Se guardará el progreso actual.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir', style: TextStyle(color: netflixRed)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _restoreSystemUi();
      WakelockPlus.disable();
      Navigator.pop(context);
    } else if (mounted && wasPlaying) {
      _controller.play();
      _scheduleHideControls();
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _isDisposing = true;
    _hideControlsTimer?.cancel();
    _positionNotifier.dispose();

    _saveCache();
    if (_controllerReady) {
      _controller.removeListener(_videoListener);
      _controller.dispose();
    }
    _restoreSystemUi();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isLoading)
              _buildLoadingScreen()
            else if (_errorMessage.isNotEmpty)
              _buildErrorScreen()
            else
              SizedBox.expand(
                child: FittedBox(
                  fit: _currentBoxFit,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
            if (_isBuffering && !_isLoading && _errorMessage.isEmpty)
              const Center(
                child: CircularProgressIndicator(
                  color: accentOrange,
                  strokeWidth: 3,
                ),
              ),
            if (!_isLoading && _errorMessage.isEmpty && _subtitlesEnabled)
              SubtitleWidget(
                text: _currentSubtitleText,
                isActive: _currentSubtitleText.isNotEmpty,
                bottomPadding: _showControls
                    ? (_showBottomPanel ? 220.0 : 120.0)
                    : 36.0,
                fontSize: _subtitleFontSize,
                textColor: Colors.white,
                strokeColor: Colors.black,
                strokeWidth: 2.0,
                fontWeight: _subtitleBold ? FontWeight.w700 : FontWeight.w500,
                maxWidth: 640,
                verticalOffset: _subtitleVerticalOffset,
              ),
            if (!_isLoading && _errorMessage.isEmpty && _showSkipIntro)
              Positioned(
                right: 16,
                bottom: _showControls
                    ? (_showBottomPanel ? 200.0 : 110.0)
                    : 40.0,
                child: GestureDetector(
                  onTap: _skipIntro,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white54),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fast_forward_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Omitir intro',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_isLoading &&
                _errorMessage.isEmpty &&
                _showNextButton &&
                _mediaType == 'tv' &&
                _siguiente != null)
              Positioned(
                right: 16,
                bottom: _showControls
                    ? (_showBottomPanel ? 200.0 : 110.0)
                    : 40.0,
                child: GestureDetector(
                  onTap: _goNextEpisode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: accentOrange,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: accentOrange.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _mediaType == 'tv'
                              ? 'Siguiente episodio'
                              : 'Siguiente',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_isLoading && _errorMessage.isEmpty && _showControls)
              _buildControlsOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_backdropUrl != null)
          CachedNetworkImage(
            imageUrl: _backdropUrl!,
            fit: BoxFit.cover,
            memCacheWidth: 800,
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        const Center(
          child: SizedBox(
            width: 44,
            height: 44,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: netflixRed, size: 56),
          const SizedBox(height: 14),
          const Text(
            'No se pudo cargar el video',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = '';
                  });
                  _initializePlayer();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: netflixRed,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Reintentar'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _openServersModal(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Cambiar servidor'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.75),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.92),
          ],
          stops: const [0.0, 0.18, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _showExitConfirmation,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (_logoUrl != null && _logoUrl!.isNotEmpty) ...[
                          CachedNetworkImage(
                            imageUrl: _logoUrl!,
                            height: 28,
                            fit: BoxFit.contain,
                            memCacheHeight: 56,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_capituloFmt != null)
                                Text(
                                  '$_capituloFmt${_tituloCapitulo != null ? ' · $_tituloCapitulo' : ''}',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                _tituloContenido,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: _idiomaFlagUrl(),
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      memCacheWidth: 48,
                      errorWidget: (_, __, ___) => Text(
                        _idioma,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _centerBtn(
                  icon: Icons.replay_10_rounded,
                  size: 40,
                  onTap: () => _seekBy(-10),
                ),
                const SizedBox(width: 28),
                _centerBtn(
                  icon: _isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 56,
                  onTap: _togglePlay,
                  filled: true,
                ),
                const SizedBox(width: 28),
                _centerBtn(
                  icon: Icons.forward_10_rounded,
                  size: 40,
                  onTap: () => _seekBy(10),
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        activeTrackColor: accentOrange,
                        inactiveTrackColor: Colors.white.withValues(
                          alpha: 0.25,
                        ),
                        thumbColor: accentOrange,
                        overlayColor: accentOrange.withValues(alpha: 0.25),
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
                        onChanged: (v) {
                          setState(() {
                            _currentPosition = Duration(seconds: v.toInt());
                          });
                          _controller.seekTo(Duration(seconds: v.toInt()));
                        },
                        onChangeStart: (_) {
                          _hideControlsTimer?.cancel();
                          setState(() => _isDragging = true);
                        },
                        onChangeEnd: (_) {
                          setState(() => _isDragging = false);
                          _scheduleHideControls();
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(_totalDuration - _currentPosition),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionIcon(Icons.replay_rounded, 'Reiniciar', _restart),
                  if (_mediaType == 'tv' && _siguiente != null)
                    _actionIcon(
                      Icons.skip_next_rounded,
                      'Siguiente',
                      _goNextEpisode,
                    ),
                  // ── BOTÓN SUBTÍTULOS (abre el modal) ────────────────
                  _actionIcon(
                    _subtitlesEnabled
                        ? Icons.closed_caption_rounded
                        : Icons.closed_caption_disabled_rounded,
                    _selectedSubtitleLabel,
                    _openSubtitlesModal,
                  ),
                  _actionIcon(
                    Icons.dns_rounded,
                    'Servidores',
                    () => _openServersModal(),
                  ),
                  _actionIcon(
                    Icons.high_quality_rounded,
                    _currentQualityLabel,
                    _openQualitySelector,
                  ),
                  _actionIcon(_fitModeIcon, _fitModeLabel, _cycleFitMode),
                  _actionIcon(
                    Icons.info_outline_rounded,
                    'Info',
                    _openInfoModal,
                  ),
                  if (_hasBottomContent)
                    _actionIcon(
                      _showBottomPanel
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      _showBottomPanel ? 'Ocultar' : 'Más',
                      () {
                        setState(() => _showBottomPanel = !_showBottomPanel);
                        if (_showBottomPanel) {
                          _hideControlsTimer?.cancel();
                        } else {
                          _scheduleHideControls();
                        }
                      },
                    ),
                ],
              ),
            ),
            if (_showBottomPanel && _hasBottomContent) ...[
              const SizedBox(height: 10),
              if (_mediaType == 'tv' && _temporadas.isNotEmpty) ...[
                SizedBox(
                  height: 34,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _temporadas.length,
                    itemBuilder: (ctx, i) {
                      final temp = _temporadas[i] as Map;
                      final isSelected = i == _selectedSeasonIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedSeasonIndex = i),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accentOrange.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? accentOrange
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            temp['nombre']?.toString() ??
                                'Temporada ${temp['numero']}',
                            style: TextStyle(
                              color: isSelected ? accentOrange : Colors.white70,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(height: 90, child: _buildEpisodesList()),
              ] else if (_recomendaciones.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ver a continuación',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 90, child: _buildRecommendationsList()),
              ],
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _centerBtn({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size + 12,
        height: size + 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  Widget _actionIcon(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodesList() {
    if (_temporadas.isEmpty) return const SizedBox.shrink();
    final season = _temporadas[_selectedSeasonIndex];
    if (season is! Map) return const SizedBox.shrink();
    final caps = season['capitulos'] as List? ?? [];
    final seasonNum = season['numero'];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: caps.length,
      itemBuilder: (ctx, i) {
        final cap = caps[i];
        if (cap is! Map) return const SizedBox.shrink();
        final isActual = cap['actual'] == true;
        final num = cap['numero'];
        final titulo = cap['titulo'] ?? 'Episodio $num';
        final backdrop = _optimizeTmdbUrl(
          cap['backdrop']?.toString(),
          size: 'w300',
        );

        return GestureDetector(
          onTap: () => _openServersModal(
            idcontenido: _resolvedId,
            temporada: seasonNum is int
                ? seasonNum
                : int.tryParse('$seasonNum'),
            capitulo: num is int ? num : int.tryParse('$num'),
          ),
          child: Container(
            width: 140,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActual ? accentOrange : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: backdrop,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) =>
                          ColoredBox(color: Colors.grey[900]!),
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: Colors.grey[900]!),
                    )
                  else
                    ColoredBox(color: Colors.grey[900]!),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xD9000000)],
                      ),
                    ),
                  ),
                  if (isActual)
                    const Positioned(
                      top: 4,
                      left: 4,
                      child: Icon(
                        Icons.play_circle_fill,
                        color: accentOrange,
                        size: 18,
                      ),
                    ),
                  Positioned(
                    bottom: 5,
                    left: 6,
                    right: 6,
                    child: Text(
                      '$num · $titulo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendationsList() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _recomendaciones.length,
      itemBuilder: (ctx, i) {
        final rec = _recomendaciones[i];
        if (rec is! Map) return const SizedBox.shrink();
        final poster = _optimizeTmdbUrl(
          (rec['backdrop'] ?? rec['poster'])?.toString(),
          size: 'w300',
        );
        final titulo = rec['titulo'] ?? '';
        final id = rec['tmdb_id'] ?? rec['idcontenido'];
        final tipo = rec['tipo']?.toString() ?? 'movie';

        return GestureDetector(
          onTap: () => _openServersModal(
            idcontenido: id is int ? id : int.tryParse('$id'),
            tipo: tipo,
          ),
          child: Container(
            width: 150,
            margin: const EdgeInsets.only(right: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) =>
                          ColoredBox(color: Colors.grey[900]!),
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: Colors.grey[900]!),
                    )
                  else
                    ColoredBox(color: Colors.grey[900]!),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xE6000000)],
                        ),
                      ),
                      child: Text(
                        titulo.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}