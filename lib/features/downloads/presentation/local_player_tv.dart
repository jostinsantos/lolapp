import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Episodio local de una serie (para botón "Siguiente capítulo").
class LocalSeriesEpisode {
  final String videoPath;
  final String title;
  final String? folderPath;
  final int? tmdbId;
  final String? tipo;
  final int? temporada;
  final int? capitulo;

  const LocalSeriesEpisode({
    required this.videoPath,
    required this.title,
    this.folderPath,
    this.tmdbId,
    this.tipo,
    this.temporada,
    this.capitulo,
  });
}

class LocalPlayerTvScreen extends StatefulWidget {
  final String playlistPath;
  final String title;
  final String? folderPath;
  final int? tmdbId;
  final String? tipo;
  final int? temporada;
  final int? capitulo;

  /// Episodios locales de la misma serie (ordenados). Solo se usa para
  /// mostrar "Siguiente capítulo" si existe el siguiente descargado.
  final List<LocalSeriesEpisode>? seriesEpisodes;

  const LocalPlayerTvScreen({
    super.key,
    required this.playlistPath,
    required this.title,
    this.folderPath,
    this.tmdbId,
    this.tipo,
    this.temporada,
    this.capitulo,
    this.seriesEpisodes,
  });

  @override
  State<LocalPlayerTvScreen> createState() => _LocalPlayerTvScreenState();
}

class _LocalPlayerTvScreenState extends State<LocalPlayerTvScreen> {
  static const _kAccent = Color(0xFFE50914);

  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  String? _errorMsg;
  bool _showControls = true;
  bool _isPlaying = false;
  Timer? _hideTimer;

  final FocusNode _rootFocus = FocusNode(debugLabel: 'local_player_tv_root');
  final FocusNode _playFocus = FocusNode(debugLabel: 'lp_play');
  final FocusNode _rewindFocus = FocusNode(debugLabel: 'lp_rew');
  final FocusNode _forwardFocus = FocusNode(debugLabel: 'lp_fwd');
  final FocusNode _nextFocus = FocusNode(debugLabel: 'lp_next');
  final FocusNode _exitContinueFocus = FocusNode(debugLabel: 'exit_continue');
  final FocusNode _exitCloseFocus = FocusNode(debugLabel: 'exit_close');
  final FocusNode _seekBarFocus = FocusNode(debugLabel: 'lp_seek');

  bool _exitModalVisible = false;
  Timer? _saveTimer;
  bool _isExiting = false;

  // Subtítulos locales (.srt / .vtt junto al vídeo)
  final List<_LpCue> _cues = [];
  String _currentSub = '';
  bool _subsEnabled = true;

  String get _historyKey {
    if (widget.tmdbId != null) {
      if ((widget.tipo == 'tv' || widget.tipo == 'series') &&
          widget.temporada != null &&
          widget.capitulo != null) {
        return 'local_tv_history_${widget.tmdbId}_T${widget.temporada}_C${widget.capitulo}';
      }
      return 'local_tv_history_${widget.tmdbId}';
    }
    return 'local_tv_history_${widget.playlistPath.hashCode}';
  }

  /// Siguiente episodio descargado (misma serie), o null si no hay.
  LocalSeriesEpisode? get _nextEpisode {
    final list = widget.seriesEpisodes;
    if (list == null || list.isEmpty) return null;
    if (widget.temporada == null || widget.capitulo == null) return null;

    final curS = widget.temporada!;
    final curE = widget.capitulo!;

    // Ordenar por temporada / capítulo
    final sorted = List<LocalSeriesEpisode>.from(list)
      ..sort((a, b) {
        final sa = a.temporada ?? 0;
        final sb = b.temporada ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        return (a.capitulo ?? 0).compareTo(b.capitulo ?? 0);
      });

    for (final ep in sorted) {
      final s = ep.temporada ?? 0;
      final e = ep.capitulo ?? 0;
      if (s > curS || (s == curS && e > curE)) {
        // No devolver el mismo archivo
        if (ep.videoPath != widget.playlistPath) return ep;
      }
    }
    return null;
  }

  bool get _hasNextEpisode => _nextEpisode != null;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _initPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rootFocus.requestFocus();
    });
  }

  Future<void> _initPlayer() async {
    try {
      final path = widget.playlistPath;
      final file = File(path);
      if (!await file.exists()) {
        setState(() {
          _hasError = true;
          _errorMsg = 'Archivo no encontrado:\n$path';
        });
        return;
      }

      final lower = path.toLowerCase();
      late VideoPlayerController controller;

      if (lower.endsWith('.m3u8')) {
        controller = VideoPlayerController.networkUrl(
          Uri.file(path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
        );
      } else {
        controller = VideoPlayerController.file(file);
      }

      await controller.initialize();
      controller.addListener(_onPlayerUpdate);

      final prefs = await SharedPreferences.getInstance();
      final savedMs = prefs.getInt(_historyKey) ?? 0;
      if (savedMs > 3000 &&
          controller.value.duration.inMilliseconds > savedMs + 5000) {
        await controller.seekTo(Duration(milliseconds: savedMs));
      }

      await controller.play();

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initialized = true;
        _isPlaying = true;
      });
      _loadLocalSubtitles();
      _focusPlayButton();
      _scheduleHideControls();
      _startSaveLoop();
    } catch (e) {
      if (widget.playlistPath.toLowerCase().endsWith('.m3u8')) {
        try {
          final controller =
              VideoPlayerController.file(File(widget.playlistPath));
          await controller.initialize();
          controller.addListener(_onPlayerUpdate);
          await controller.play();
          if (!mounted) return;
          setState(() {
            _controller = controller;
            _initialized = true;
            _isPlaying = true;
          });
          _focusPlayButton();
          _scheduleHideControls();
          _startSaveLoop();
          return;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMsg = '$e';
        });
      }
    }
  }

  void _focusPlayButton() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showControls && !_exitModalVisible) {
        _playFocus.requestFocus();
      }
    });
  }

  void _startSaveLoop() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });
  }

  Future<void> _saveProgress() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final ms = c.value.position.inMilliseconds;
    if (ms < 2000) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_historyKey, ms);
    } catch (_) {}
  }

  void _onPlayerUpdate() {
    if (!mounted || _controller == null) return;
    final playing = _controller!.value.isPlaying;
    final pos = _controller!.value.position;
    String sub = '';
    if (_subsEnabled && _cues.isNotEmpty) {
      for (final c in _cues) {
        if (pos >= c.start && pos <= c.end) {
          sub = c.text;
          break;
        }
      }
    }
    if (playing != _isPlaying || sub != _currentSub) {
      setState(() {
        _isPlaying = playing;
        _currentSub = sub;
      });
    }
  }

  Future<void> _loadLocalSubtitles() async {
    try {
      final videoPath = widget.playlistPath;
      final dir = File(videoPath).parent;
      if (!await dir.exists()) return;
      final base = videoPath.replaceAll(RegExp(r'\.[^.]+$'), '');
      final candidates = <File>[
        File('$base.srt'),
        File('$base.vtt'),
        File('${base}_es.srt'),
        File('${base}.es.srt'),
      ];
      // También cualquier .srt/.vtt en la carpeta
      try {
        await for (final e in dir.list()) {
          if (e is File) {
            final n = e.path.toLowerCase();
            if (n.endsWith('.srt') || n.endsWith('.vtt')) {
              candidates.add(e);
            }
          }
        }
      } catch (_) {}

      for (final f in candidates) {
        if (!await f.exists()) continue;
        final content = await f.readAsString();
        final parsed = f.path.toLowerCase().endsWith('.vtt')
            ? _parseVtt(content)
            : _parseSrt(content);
        if (parsed.isNotEmpty) {
          if (mounted) {
            setState(() {
              _cues
                ..clear()
                ..addAll(parsed);
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('[LocalPlayerTv] subs: $e');
    }
  }

  List<_LpCue> _parseSrt(String content) {
    final cues = <_LpCue>[];
    final blocks = content.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;
      final timeLine = lines.firstWhere(
        (l) => l.contains('-->'),
        orElse: () => '',
      );
      if (timeLine.isEmpty) continue;
      final parts = timeLine.split('-->');
      if (parts.length < 2) continue;
      final start = _parseTs(parts[0].trim());
      final end = _parseTs(parts[1].trim().split(' ').first);
      final textLines = lines.skipWhile((l) => !l.contains('-->')).skip(1);
      final text = textLines.join('\n').trim();
      if (text.isNotEmpty && end > start) {
        cues.add(_LpCue(start: start, end: end, text: text));
      }
    }
    return cues;
  }

  List<_LpCue> _parseVtt(String content) {
    final cues = <_LpCue>[];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('-->')) continue;
      final parts = lines[i].split('-->');
      if (parts.length < 2) continue;
      final start = _parseTs(parts[0].trim());
      final end = _parseTs(parts[1].trim().split(' ').first);
      final buf = <String>[];
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].trim().isEmpty || lines[j].contains('-->')) break;
        buf.add(lines[j]);
      }
      final text = buf.join('\n').trim();
      if (text.isNotEmpty && end > start) {
        cues.add(_LpCue(start: start, end: end, text: text));
      }
    }
    return cues;
  }

  Duration _parseTs(String raw) {
    // 00:01:02,500 or 00:01:02.500 or 01:02.500
    final s = raw.replaceAll(',', '.');
    final parts = s.split(':');
    try {
      if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final secParts = parts[2].split('.');
        final sec = int.parse(secParts[0]);
        final ms = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return Duration(hours: h, minutes: m, seconds: sec, milliseconds: ms);
      }
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final secParts = parts[1].split('.');
        final sec = int.parse(secParts[0]);
        final ms = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return Duration(minutes: m, seconds: sec, milliseconds: ms);
      }
    } catch (_) {}
    return Duration.zero;
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    _showControlsTemporarily();
  }

  void _seekRelative(int seconds) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    var target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    c.seekTo(target);
    _showControlsTemporarily();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_exitModalVisible) {
        setState(() => _showControls = false);
        _rootFocus.requestFocus();
      }
    });
  }

  void _showControlsTemporarily() {
    final wasHidden = !_showControls;
    setState(() => _showControls = true);
    if (wasHidden) {
      _focusPlayButton();
    }
    _scheduleHideControls();
  }

  void _handleBack() {
    if (_isExiting) return;
    if (_exitModalVisible) return;
    if (_showControls) {
      setState(() => _showControls = false);
      _rootFocus.requestFocus();
      return;
    }
    setState(() {
      _exitModalVisible = true;
      _showControls = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _exitContinueFocus.requestFocus();
    });
  }

  void _closeExitModal() {
    if (_isExiting) return;
    setState(() => _exitModalVisible = false);
    _rootFocus.requestFocus();
    _scheduleHideControls();
  }

  Future<void> _exitPlayer() async {
    if (_isExiting) return;
    _isExiting = true;
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    await _saveProgress();
    try {
      await _controller?.pause();
    } catch (_) {}
    if (!mounted) return;
    // Pop forzado: evita que quede la ruta y se reabra el player de series.
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  Future<void> _playNextEpisode() async {
    final next = _nextEpisode;
    if (next == null || _isExiting) return;
    _isExiting = true;
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    await _saveProgress();
    try {
      await _controller?.pause();
    } catch (_) {}
    if (!mounted) return;

    final episodes = widget.seriesEpisodes;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LocalPlayerTvScreen(
          playlistPath: next.videoPath,
          title: next.title,
          folderPath: next.folderPath,
          tmdbId: next.tmdbId ?? widget.tmdbId,
          tipo: next.tipo ?? widget.tipo,
          temporada: next.temporada,
          capitulo: next.capitulo,
          seriesEpisodes: episodes,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _saveProgress();
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    _rootFocus.dispose();
    _playFocus.dispose();
    _rewindFocus.dispose();
    _forwardFocus.dispose();
    _nextFocus.dispose();
    _exitContinueFocus.dispose();
    _seekBarFocus.dispose();
    _exitCloseFocus.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isExiting) return KeyEventResult.handled;
    final key = event.logicalKey;

    if (_exitModalVisible) {
      if (key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.browserBack) {
        _closeExitModal();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      _handleBack();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (!_showControls) {
        _showControlsTemporarily();
        return KeyEventResult.handled;
      }
      _togglePlay();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      if (!_showControls) {
        _showControlsTemporarily();
      }
      _seekRelative(-10);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      if (!_showControls) {
        _showControlsTemporarily();
      }
      _seekRelative(10);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_showControls) {
        // Subir → barra de progreso
        _seekBarFocus.requestFocus();
        return KeyEventResult.handled;
      }
      _showControlsTemporarily();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_showControls) {
        if (_seekBarFocus.hasFocus) {
          _playFocus.requestFocus();
        } else {
          setState(() => _showControls = false);
          _rootFocus.requestFocus();
        }
      } else {
        _showControlsTemporarily();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _isExiting) return;
        _handleBack();
      },
      child: Focus(
        focusNode: _rootFocus,
        onKeyEvent: _onRootKey,
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_hasError)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _errorMsg ?? 'Error al reproducir',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      Focus(
                        autofocus: true,
                        onKeyEvent: (n, e) {
                          if (e is KeyDownEvent &&
                              (e.logicalKey == LogicalKeyboardKey.select ||
                                  e.logicalKey == LogicalKeyboardKey.enter ||
                                  e.logicalKey == LogicalKeyboardKey.goBack ||
                                  e.logicalKey == LogicalKeyboardKey.escape)) {
                            _exitPlayer();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(builder: (ctx) {
                          final has = Focus.of(ctx).hasFocus;
                          return TextButton(
                            onPressed: _exitPlayer,
                            style: TextButton.styleFrom(
                              foregroundColor: has ? _kAccent : Colors.white,
                              side: BorderSide(
                                  color: has ? _kAccent : Colors.white38),
                            ),
                            child: const Text('Volver'),
                          );
                        }),
                      ),
                    ],
                  ),
                )
              else if (!_initialized)
                const Center(
                  child: CircularProgressIndicator(color: _kAccent),
                )
              else
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio == 0
                        ? 16 / 9
                        : _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              // Subtítulos locales
              if (_initialized &&
                  _subsEnabled &&
                  _currentSub.isNotEmpty &&
                  !_exitModalVisible)
                Positioned(
                  left: 48,
                  right: 48,
                  bottom: _showControls ? 120 : 48,
                  child: IgnorePointer(
                    child: Text(
                      _currentSub,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.3,
                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 8,
                            offset: Offset(1, 1),
                          ),
                        ],
                        backgroundColor: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              if (_initialized && _showControls && !_exitModalVisible)
                _buildControls(),
              if (_exitModalVisible) _buildExitModal(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final c = _controller!;
    final pos = c.value.position;
    final dur = c.value.duration;
    final maxMs = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final valueMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final hasNext = _hasNextEpisode;

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.75),
            ],
            stops: const [0, 0.25, 0.55, 1],
          ),
        ),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  Focus(
                    focusNode: _seekBarFocus,
                    onKeyEvent: (n, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.arrowLeft ||
                          key == LogicalKeyboardKey.mediaRewind) {
                        _seekRelative(-10);
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowRight ||
                          key == LogicalKeyboardKey.mediaFastForward) {
                        _seekRelative(10);
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _playFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.select ||
                          key == LogicalKeyboardKey.enter) {
                        _togglePlay();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(builder: (ctx) {
                      final seekFocused = Focus.of(ctx).hasFocus;
                      // Thumb más pequeño con foco para mejor escala en TV
                      final thumbR = seekFocused ? 5.0 : 8.0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: seekFocused
                                ? Colors.white
                                : Colors.transparent,
                            width: seekFocused ? 1.5 : 0,
                          ),
                        ),
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _kAccent,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: _kAccent,
                            overlayColor:
                                _kAccent.withValues(alpha: 0.25),
                            trackHeight: seekFocused ? 3 : 4,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: thumbR,
                            ),
                          ),
                          child: Slider(
                            value: valueMs,
                            min: 0,
                            max: maxMs,
                            onChanged: (v) {
                              c.seekTo(
                                  Duration(milliseconds: v.round()));
                              _showControlsTemporarily();
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(pos),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          _formatDuration(dur),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _tvIconButton(
                    focusNode: _rewindFocus,
                    icon: Icons.replay_10_rounded,
                    onPressed: () => _seekRelative(-10),
                    onLeft: null,
                    onRight: () => _playFocus.requestFocus(),
                  ),
                  const SizedBox(width: 28),
                  _tvIconButton(
                    focusNode: _playFocus,
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 42,
                    onPressed: _togglePlay,
                    onLeft: () => _rewindFocus.requestFocus(),
                    onRight: () {
                      if (hasNext) {
                        _nextFocus.requestFocus();
                      } else {
                        _forwardFocus.requestFocus();
                      }
                    },
                  ),
                  if (hasNext) ...[
                    const SizedBox(width: 20),
                    _tvNextButton(),
                    const SizedBox(width: 20),
                  ] else
                    const SizedBox(width: 28),
                  _tvIconButton(
                    focusNode: _forwardFocus,
                    icon: Icons.forward_10_rounded,
                    onPressed: () => _seekRelative(10),
                    onLeft: () {
                      if (hasNext) {
                        _nextFocus.requestFocus();
                      } else {
                        _playFocus.requestFocus();
                      }
                    },
                    onRight: null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tvNextButton() {
    return Focus(
      focusNode: _nextFocus,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _playNextEpisode();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          _playFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _forwardFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape) {
          _handleBack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final has = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: _playNextEpisode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: has
                  ? _kAccent.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: has ? _kAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: has ? 28 : 24,
                ),
                const SizedBox(width: 6),
                Text(
                  'Siguiente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: has ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _tvIconButton({
    required FocusNode focusNode,
    required IconData icon,
    required VoidCallback onPressed,
    double size = 34,
    VoidCallback? onLeft,
    VoidCallback? onRight,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onPressed();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (onLeft != null) {
            onLeft();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          if (onRight != null) {
            onRight();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape) {
          _handleBack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final has = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: has
                  ? _kAccent.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: has ? _kAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: size),
          ),
        );
      }),
    );
  }

  Widget _buildExitModal() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            width: 420,
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '¿Salir de la reproducción?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Se guardará el progreso actual.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _modalBtn(
                        focusNode: _exitContinueFocus,
                        label: 'Continuar',
                        primary: false,
                        onPressed: _closeExitModal,
                        onRight: () => _exitCloseFocus.requestFocus(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _modalBtn(
                        focusNode: _exitCloseFocus,
                        label: 'Salir',
                        primary: true,
                        onPressed: _exitPlayer,
                        onLeft: () => _exitContinueFocus.requestFocus(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modalBtn({
    required FocusNode focusNode,
    required String label,
    required bool primary,
    required VoidCallback onPressed,
    VoidCallback? onLeft,
    VoidCallback? onRight,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onPressed();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft && onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight && onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape) {
          _closeExitModal();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final has = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: primary
                  ? (has ? _kAccent : _kAccent.withValues(alpha: 0.75))
                  : (has
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: has ? _kAccent : Colors.transparent,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: has ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _LpCue {
  final Duration start;
  final Duration end;
  final String text;
  const _LpCue({
    required this.start,
    required this.end,
    required this.text,
  });
}
