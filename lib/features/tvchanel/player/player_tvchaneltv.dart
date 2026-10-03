import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/tv_channel_models.dart';

const _kAccent = Color(0xFFE50914);

/// Player de canal en vivo (TV)
/// - Reloj en controles
/// - Flecha ARRIBA / Select centro → lista de canales por categoría
/// - CH+/CH- (page up/down) → canal siguiente/anterior
/// - Atrás → modal confirmar salir
class PlayerTvChanelTv extends StatefulWidget {
  final TvChannel channel;
  /// Lista completa para zapping y guía
  final List<TvCategory> categories;

  const PlayerTvChanelTv({
    super.key,
    required this.channel,
    this.categories = const [],
  });

  @override
  State<PlayerTvChanelTv> createState() => _PlayerTvChanelTvState();
}

class _PlayerTvChanelTvState extends State<PlayerTvChanelTv> {
  VideoPlayerController? _controller;
  late TvChannel _channel;
  bool _initialized = false;
  bool _hasError = false;
  String? _errorMsg;
  bool _showControls = true;
  bool _isPlaying = false;
  bool _showGuide = false;
  Timer? _hideTimer;
  Timer? _clockTimer;
  String _clock = '';
  final FocusNode _rootFocus = FocusNode(debugLabel: 'live_player_tv');

  List<TvChannel> get _flatChannels {
    final list = <TvChannel>[];
    for (final c in widget.categories) {
      list.addAll(c.channels);
    }
    if (list.isEmpty) list.add(_channel);
    return list;
  }

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _updateClock());
    _initPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rootFocus.requestFocus();
    });
  }

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    if (mounted) setState(() => _clock = '$h:$m');
  }



  Future<void> _initPlayer() async {
    setState(() {
      _initialized = false;
      _hasError = false;
      _errorMsg = null;
    });

    final url = _channel.url.trim();
    if (url.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMsg = 'URL del canal vacía';
      });
      return;
    }

    // Liberar decoder anterior por completo (evita NO_MEMORY en OMX.qcom)
    final prev = _controller;
    _controller = null;
    if (prev != null) {
      try {
        prev.removeListener(_onUpdate);
      } catch (_) {}
      try {
        await prev.pause();
      } catch (_) {}
      try {
        await prev.dispose();
      } catch (_) {}
      // Samsung/QCOM necesita más tiempo para liberar el codec HW
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }

    String origin = '';
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        origin = '${uri.scheme}://${uri.host}';
      }
    } catch (_) {}

    final isHls = url.toLowerCase().contains('.m3u8') ||
        url.toLowerCase().contains('/hls/') ||
        url.toLowerCase().contains('format=m3u8');

    // Pocas tentativas: cada fallo deja el codec en NO_MEMORY si se reintenta muy rápido
    final attempts = <({Map<String, String> headers, VideoFormat? hint})>[
      (
        headers: {
          'User-Agent': 'okhttp/4.12.0',
          'Accept': '*/*',
          'Connection': 'keep-alive',
        },
        hint: null,
      ),
      (
        headers: {
          'User-Agent': 'okhttp/4.12.0',
          'Accept': '*/*',
          if (origin.isNotEmpty) 'Referer': '$origin/',
          if (origin.isNotEmpty) 'Origin': origin,
        },
        hint: isHls ? VideoFormat.hls : null,
      ),
      (
        headers: {
          'User-Agent': 'VLC/3.0.16 LibVLC/3.0.16',
          'Accept': '*/*',
          if (origin.isNotEmpty) 'Referer': '$origin/',
        },
        hint: null,
      ),
    ];

    Object? lastError;
    for (var i = 0; i < attempts.length; i++) {
      if (!mounted) return;
      final a = attempts[i];
      VideoPlayerController? c;
      try {
        c = VideoPlayerController.networkUrl(
          Uri.parse(url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
          httpHeaders: a.headers,
          formatHint: a.hint,
        );
        await c.initialize().timeout(const Duration(seconds: 20));
        c.addListener(_onUpdate);
        await c.play();
        if (!mounted) {
          await c.dispose();
          return;
        }
        setState(() {
          _controller = c;
          _initialized = true;
          _isPlaying = true;
          _hasError = false;
          _errorMsg = null;
        });
        _scheduleHide();
        return;
      } catch (e) {
        lastError = e;
        try {
          await c?.dispose();
        } catch (_) {}
        // Tras NO_MEMORY / MediaCodec: esperar más antes del siguiente intento
        final waitMs = e.toString().contains('NO_MEMORY') ||
                e.toString().contains('MediaCodec') ||
                e.toString().contains('Decoder')
            ? 1500
            : 600;
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
    }

    if (!mounted) return;
    final raw = lastError?.toString() ?? 'Error';
    String msg;
    if (raw.contains('403') || raw.contains('Forbidden')) {
      msg =
          'Acceso denegado (403).\nCanal geo-bloqueado o con token.';
    } else if (raw.contains('NO_MEMORY') ||
        raw.contains('MediaCodec') ||
        raw.contains('Decoder')) {
      msg =
          'El decodificador del dispositivo está ocupado o sin memoria.\n'
          'Cierra otras apps de vídeo y reintenta, o cambia de canal.';
    } else if (raw.contains('404')) {
      msg = 'Stream no encontrado (404).';
    } else if (raw.contains('SocketException') || raw.contains('Network')) {
      msg = 'Error de red. Comprueba la conexión.';
    } else {
      msg = raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
    }
    setState(() {
      _hasError = true;
      _errorMsg = msg;
    });
  }

  void _onUpdate() {
    if (!mounted || _controller == null) return;
    final playing = _controller!.value.isPlaying;
    if (playing != _isPlaying) setState(() => _isPlaying = playing);
  }

  Future<void> _switchChannel(TvChannel ch) async {
    if (ch.id == _channel.id && ch.url == _channel.url) return;
    await _controller?.pause();
    await _controller?.dispose();
    _controller = null;
    setState(() {
      _channel = ch;
      _showGuide = false;
      _showControls = true;
    });
    await _initPlayer();
    _rootFocus.requestFocus();
  }

  void _nextChannel(int delta) {
    final list = _flatChannels;
    if (list.length < 2) return;
    final idx = list.indexWhere((c) => c.id == _channel.id || c.url == _channel.url);
    final next = ((idx < 0 ? 0 : idx) + delta) % list.length;
    final safe = next < 0 ? list.length - 1 : next;
    _switchChannel(list[safe]);
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    _showControlsTemporarily();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_isPlaying || _showGuide) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_showGuide) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    _scheduleHide();
  }

  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => const _TvExitConfirmDialog(),
    );
    return ok == true;
  }

  /// Cierra de verdad el player tras confirmar.
  Future<void> _doExit() async {
    final yes = await _confirmExit();
    if (!yes || !mounted) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _rootFocus.requestFocus();
        });
      }
      return;
    }
    // Parar y liberar codec antes de salir
    try {
      await _controller?.pause();
    } catch (_) {}
    try {
      _controller?.removeListener(_onUpdate);
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    try {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await WakelockPlus.disable();
    } catch (_) {}
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    // Algunos mandos Android TV envían keyId numérico para CH+/CH-
    final keyId = k.keyId;

    if (_showGuide) {
      if (k == LogicalKeyboardKey.goBack ||
          k == LogicalKeyboardKey.escape) {
        setState(() => _showGuide = false);
        _scheduleHide();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      _doExit();
      return KeyEventResult.handled;
    }

    // Guía de canales
    if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.contextMenu) {
      setState(() {
        _showGuide = true;
        _showControls = true;
      });
      _hideTimer?.cancel();
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.space) {
      if (!_showControls) {
        _showControlsTemporarily();
      } else {
        _togglePlay();
      }
      return KeyEventResult.handled;
    }

    // CH+ / canal siguiente
    // channelUp, pageUp, mediaTrackNext, keyId 0x1000000A6 (KEYCODE_CHANNEL_UP=166)
    final isChUp = k == LogicalKeyboardKey.pageUp ||
        k == LogicalKeyboardKey.channelUp ||
        k == LogicalKeyboardKey.mediaTrackNext ||
        keyId == 0x1000000A6 || // KEYCODE_CHANNEL_UP
        keyId == 166;
    // CH-
    final isChDown = k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.channelDown ||
        k == LogicalKeyboardKey.mediaTrackPrevious ||
        keyId == 0x1000000A7 || // KEYCODE_CHANNEL_DOWN
        keyId == 167;

    if (isChUp || k == LogicalKeyboardKey.arrowRight) {
      _nextChannel(1);
      return KeyEventResult.handled;
    }
    if (isChDown || k == LogicalKeyboardKey.arrowLeft) {
      _nextChannel(-1);
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.arrowDown) {
      _showControlsTemporarily();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _clockTimer?.cancel();
    _controller?.removeListener(_onUpdate);
    _controller?.dispose();
    _rootFocus.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_showGuide) {
          setState(() => _showGuide = false);
          return;
        }
        await _doExit();
      },
      child: Focus(
        focusNode: _rootFocus,
        onKeyEvent: _onKey,
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_initialized && _controller != null && !_hasError)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio == 0
                        ? 16 / 9
                        : _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else if (_hasError)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _errorMsg ?? 'No se pudo reproducir',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '← → cambiar canal  ·  ↑ guía  ·  Atrás salir',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Center(child: CircularProgressIndicator(color: _kAccent)),

              // Controles
              if (_showControls && !_showGuide)
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _togglePlay,
                          icon: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_channel.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              if (_channel.group != null)
                                Text(_channel.group!,
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 12)),
                            ],
                          ),
                        ),
                        // Reloj
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_clock,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Lista de canales',
                          onPressed: () => setState(() {
                            _showGuide = true;
                            _showControls = true;
                          }),
                          icon: const Icon(Icons.list_rounded, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ),
                ),

              // Guía de canales
              if (_showGuide) _ChannelGuide(
                categories: widget.categories.isNotEmpty
                    ? widget.categories
                    : [TvCategory(name: 'Actual', channels: [_channel])],
                current: _channel,
                onSelect: _switchChannel,
                onClose: () {
                  setState(() => _showGuide = false);
                  _scheduleHide();
                  _rootFocus.requestFocus();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelGuide extends StatefulWidget {
  final List<TvCategory> categories;
  final TvChannel current;
  final ValueChanged<TvChannel> onSelect;
  final VoidCallback onClose;

  const _ChannelGuide({
    required this.categories,
    required this.current,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<_ChannelGuide> createState() => _ChannelGuideState();
}

class _ChannelGuideState extends State<_ChannelGuide> {
  int _catIndex = 0;
  late List<FocusNode> _catNodes;
  late List<List<FocusNode>> _chNodes;
  final _catScroll = ScrollController();
  final _chScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Encontrar categoría del canal actual
    for (var i = 0; i < widget.categories.length; i++) {
      if (widget.categories[i].channels.any(
          (c) => c.id == widget.current.id || c.url == widget.current.url)) {
        _catIndex = i;
        break;
      }
    }
    _catNodes = List.generate(
      widget.categories.length,
      (i) => FocusNode(debugLabel: 'guide_cat_$i'),
    );
    _chNodes = widget.categories
        .map((c) => List.generate(
              c.channels.length,
              (i) => FocusNode(debugLabel: 'guide_ch_${c.name}_$i'),
            ))
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chNodes.isNotEmpty && _chNodes[_catIndex].isNotEmpty) {
        // foco en canal actual
        final chs = widget.categories[_catIndex].channels;
        var idx = chs.indexWhere(
            (c) => c.id == widget.current.id || c.url == widget.current.url);
        if (idx < 0) idx = 0;
        if (idx < _chNodes[_catIndex].length) {
          _chNodes[_catIndex][idx].requestFocus();
        }
      } else if (_catNodes.isNotEmpty) {
        _catNodes[_catIndex].requestFocus();
      }
    });
  }

  void _ensureVisible(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _catScroll.dispose();
    _chScroll.dispose();
    for (final n in _catNodes) {
      n.dispose();
    }
    for (final row in _chNodes) {
      for (final n in row) {
        n.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Canales',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('↑↓ categorías  ·  ←→ canales  ·  OK ver  ·  Atrás cerrar',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12)),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Tabs categorías
              SizedBox(
                height: 42,
                child: ListView.separated(
                  controller: _catScroll,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final cat = widget.categories[i];
                    final selected = i == _catIndex;
                    return Focus(
                      focusNode: _catNodes[i],
                      onKeyEvent: (n, e) {
                        if (e is! KeyDownEvent) return KeyEventResult.ignored;
                        final k = e.logicalKey;
                        if (k == LogicalKeyboardKey.arrowRight &&
                            i < _catNodes.length - 1) {
                          setState(() => _catIndex = i + 1);
                          _catNodes[i + 1].requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (k == LogicalKeyboardKey.arrowLeft && i > 0) {
                          setState(() => _catIndex = i - 1);
                          _catNodes[i - 1].requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (k == LogicalKeyboardKey.arrowDown &&
                            _chNodes[i].isNotEmpty) {
                          setState(() => _catIndex = i);
                          _chNodes[i].first.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (k == LogicalKeyboardKey.select ||
                            k == LogicalKeyboardKey.enter) {
                          setState(() => _catIndex = i);
                          return KeyEventResult.handled;
                        }
                        if (k == LogicalKeyboardKey.goBack ||
                            k == LogicalKeyboardKey.escape) {
                          widget.onClose();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      onFocusChange: (has) {
                        if (has) {
                          setState(() => _catIndex = i);
                          _ensureVisible(_catNodes[i]);
                        }
                      },
                      child: Builder(builder: (ctx) {
                        final f = Focus.of(ctx).hasFocus;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _catIndex = i);
                            _catNodes[i].requestFocus();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected || f
                                  ? _kAccent
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: f ? Colors.white : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              '${cat.name} (${cat.channels.length})',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              // Lista canales de categoría
              Expanded(
                child: Builder(builder: (_) {
                  if (_catIndex >= widget.categories.length) {
                    return const SizedBox.shrink();
                  }
                  final cat = widget.categories[_catIndex];
                  final nodes = _chNodes[_catIndex];
                  return ListView.builder(
                    controller: _chScroll,
                    itemCount: cat.channels.length,
                    itemBuilder: (_, i) {
                      final ch = cat.channels[i];
                      final isCurrent = ch.id == widget.current.id ||
                          ch.url == widget.current.url;
                      final node = i < nodes.length ? nodes[i] : FocusNode();
                      return Focus(
                        focusNode: node,
                        onFocusChange: (has) {
                          if (has) _ensureVisible(node);
                        },
                        onKeyEvent: (n, e) {
                          if (e is! KeyDownEvent) return KeyEventResult.ignored;
                          final k = e.logicalKey;
                          if (k == LogicalKeyboardKey.arrowDown &&
                              i < nodes.length - 1) {
                            nodes[i + 1].requestFocus();
                            _ensureVisible(nodes[i + 1]);
                            return KeyEventResult.handled;
                          }
                          if (k == LogicalKeyboardKey.arrowUp) {
                            if (i > 0) {
                              nodes[i - 1].requestFocus();
                              _ensureVisible(nodes[i - 1]);
                            } else {
                              _catNodes[_catIndex].requestFocus();
                            }
                            return KeyEventResult.handled;
                          }
                          if (k == LogicalKeyboardKey.select ||
                              k == LogicalKeyboardKey.enter) {
                            widget.onSelect(ch);
                            return KeyEventResult.handled;
                          }
                          if (k == LogicalKeyboardKey.goBack ||
                              k == LogicalKeyboardKey.escape) {
                            widget.onClose();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(builder: (ctx) {
                          final f = Focus.of(ctx).hasFocus;
                          return GestureDetector(
                            onTap: () => widget.onSelect(ch),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: f
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : (isCurrent
                                        ? _kAccent.withValues(alpha: 0.2)
                                        : Colors.transparent),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: f
                                      ? Colors.white
                                      : (isCurrent
                                          ? _kAccent
                                          : Colors.transparent),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (isCurrent)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Icon(Icons.play_arrow,
                                          color: _kAccent, size: 18),
                                    ),
                                  Expanded(
                                    child: Text(
                                      ch.name,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: f || isCurrent
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo de salida con foco D-pad (borde rojo en el seleccionado).
class _TvExitConfirmDialog extends StatefulWidget {
  const _TvExitConfirmDialog();

  @override
  State<_TvExitConfirmDialog> createState() => _TvExitConfirmDialogState();
}

class _TvExitConfirmDialogState extends State<_TvExitConfirmDialog> {
  final _cancelFocus = FocusNode(debugLabel: 'exit_cancel');
  final _exitFocus = FocusNode(debugLabel: 'exit_ok');
  int _selected = 0; // 0 cancel, 1 exit

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cancelFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _cancelFocus.dispose();
    _exitFocus.dispose();
    super.dispose();
  }

  void _select(int i) {
    setState(() => _selected = i);
    if (i == 0) {
      _cancelFocus.requestFocus();
    } else {
      _exitFocus.requestFocus();
    }
  }

  KeyEventResult _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      _select(_selected == 0 ? 1 : 0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.space) {
      Navigator.pop(context, _selected == 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      Navigator.pop(context, false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) => _onKey(e),
      child: AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Salir del canal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          '¿Quieres salir de la reproducción?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          Focus(
            focusNode: _cancelFocus,
            onFocusChange: (h) {
              if (h) setState(() => _selected = 0);
            },
            onKeyEvent: (_, e) => _onKey(e),
            child: GestureDetector(
              onTap: () => Navigator.pop(context, false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _selected == 0
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selected == 0 ? _kAccent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        _selected == 0 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          Focus(
            focusNode: _exitFocus,
            onFocusChange: (h) {
              if (h) setState(() => _selected = 1);
            },
            onKeyEvent: (_, e) => _onKey(e),
            child: GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _kAccent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selected == 1 ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: const Text(
                  'Salir',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
