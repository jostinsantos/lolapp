import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../player/presentation/widgets/mini_player_service.dart';
import '../models/tv_channel_models.dart';

const _kAccent = Color(0xFFE50914);

/// Player de canal en vivo — **móvil**
/// Incluye minimizar → mini-player inferior (misma barra que VOD).
class PlayerTvChanel extends StatefulWidget {
  final TvChannel channel;
  final List<TvCategory> categories;

  const PlayerTvChanel({
    super.key,
    required this.channel,
    this.categories = const [],
  });

  @override
  State<PlayerTvChanel> createState() => _PlayerTvChanelState();
}

class _PlayerTvChanelState extends State<PlayerTvChanel> {
  VideoPlayerController? _controller;
  late TvChannel _channel;
  bool _initialized = false;
  bool _hasError = false;
  String? _errorMsg;
  bool _showControls = true;
  bool _isPlaying = false;
  Timer? _hideTimer;

  List<TvChannel> get _flat {
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
    _init();
  }


  static const _uaVlc = 'VLC/3.0.16 LibVLC/3.0.16';
  static const _uaChrome =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  Map<String, String> _headersFor(String url, {required String ua}) {
    final u = url.toLowerCase();
    String origin = '';
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        origin = '${uri.scheme}://${uri.host}';
      }
    } catch (_) {}
    final h = <String, String>{
      'User-Agent': ua,
      'Accept': '*/*',
      'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
      'Connection': 'keep-alive',
    };
    if (origin.isNotEmpty) {
      h['Referer'] = '$origin/';
      h['Origin'] = origin;
    }
    if (u.contains('.m3u8') || u.contains('/hls/')) {
      h['Accept'] = 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*';
    }
    return h;
  }

  bool _looksHls(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u8') ||
        u.contains('/hls/') ||
        u.contains('format=m3u8') ||
        u.contains('type=m3u8');
  }

  Future<VideoPlayerController?> _tryOpen(
    String url, {
    required String ua,
    VideoFormat? formatHint,
  }) async {
    final uri = Uri.parse(url);
    final c = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: _headersFor(url, ua: ua),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      formatHint: formatHint,
    );
    try {
      await c.initialize().timeout(const Duration(seconds: 20));
      return c;
    } catch (e) {
      try {
        await c.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _init() async {
    setState(() {
      _initialized = false;
      _hasError = false;
      _errorMsg = null;
    });

    final url = _channel.url.trim();
    if (url.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMsg = 'URL vacía';
      });
      return;
    }

    // Liberar controller anterior
    final prev = _controller;
    _controller = null;
    if (prev != null) {
      try {
        prev.removeListener(_onTick);
        await prev.pause();
        await prev.dispose();
      } catch (_) {}
      // Esperar a que MediaCodec se libere (evita Decoder init failed)
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final isDash = url.toLowerCase().contains('.mpd') ||
        url.toLowerCase().contains('dash');
    // Kino LiveExoPlayer: UA okhttp/4.12.0 primero, sin formatHint
    final attempts = <({String ua, VideoFormat? hint, String label})>[
      (ua: 'okhttp/4.12.0', hint: null, label: 'kino-okhttp'),
      (ua: _uaVlc, hint: null, label: 'VLC'),
      (ua: _uaChrome, hint: null, label: 'Chrome'),
      (ua: 'Lavf/58.76.100', hint: null, label: 'FFmpeg'),
      if (_looksHls(url))
        (ua: 'okhttp/4.12.0', hint: VideoFormat.hls, label: 'okhttp+HLS'),
      if (_looksHls(url))
        (ua: _uaVlc, hint: VideoFormat.hls, label: 'VLC+HLS'),
      if (isDash)
        (ua: 'okhttp/4.12.0', hint: VideoFormat.dash, label: 'okhttp+DASH'),
    ];

    Object? lastError;
    for (final a in attempts) {
      if (!mounted) return;
      try {
        final c = await _tryOpen(url, ua: a.ua, formatHint: a.hint);
        if (c == null) continue;
        c.addListener(_onTick);
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
        debugPrint('[LivePlayer] attempt ${a.label} failed: $e');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    if (!mounted) return;
    final raw = lastError?.toString() ?? 'Error desconocido';
    String msg;
    if (raw.contains('403') || raw.contains('Forbidden')) {
      msg = 'Acceso denegado (403). Canal geo-bloqueado o con token.';
    } else if (raw.contains('404')) {
      msg = 'Stream no encontrado (404).';
    } else if (raw.contains('Timeout') || raw.contains('timeout')) {
      msg = 'Tiempo de espera agotado al abrir el stream.';
    } else if (raw.contains('MediaCodec') ||
        raw.contains('Decoder') ||
        raw.contains('CodecException')) {
      msg =
          'No se pudo decodificar este stream en el dispositivo.\nPrueba otro canal o reinicia la app.';
    } else if (raw.contains('SocketException') || raw.contains('Network')) {
      msg = 'Error de red. Comprueba la conexión.';
    } else {
      msg = raw.length > 180 ? '${raw.substring(0, 180)}…' : raw;
    }
    setState(() {
      _hasError = true;
      _errorMsg = msg;
    });
  }

  void _onTick() {
    if (!mounted || _controller == null) return;
    final p = _controller!.value.isPlaying;
    if (p != _isPlaying) setState(() => _isPlaying = p);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_isPlaying) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _showCtrls() {
    setState(() => _showControls = true);
    _scheduleHide();
  }

  void _toggle() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    _showCtrls();
  }

  Future<void> _minimize() async {
    final mini = MiniPlayerService.instance;
    await mini.loadPref();
    if (!mini.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mini-player desactivado en Configuración → Player'),
        ),
      );
      return;
    }
    final c = _controller;
    final url = _channel.url.trim();
    if (c == null || !c.value.isInitialized || url.isEmpty) return;

    final wasPlaying = c.value.isPlaying;
    try {
      c.removeListener(_onTick);
    } catch (_) {}
    // Handoff: no dispose aquí
    _controller = null;

    final ok = await mini.attachController(
      controller: c,
      url: url,
      title: _channel.name,
      idcontenido: _channel.id.hashCode,
      tipo: 'live',
      poster: _channel.logo ?? '',
      resumePlay: wasPlaying,
    );
    if (!mounted) return;
    if (ok) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Navigator.pop(context);
    } else {
      _controller = c;
      try {
        c.addListener(_onTick);
        if (wasPlaying) await c.play();
      } catch (_) {}
    }
  }

  Future<void> _exit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        title: const Text('Salir del canal',
            style: TextStyle(color: Colors.white)),
        content: const Text('¿Quieres salir de la reproducción?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salir', style: TextStyle(color: _kAccent))),
        ],
      ),
    );
    if (ok == true && mounted) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      WakelockPlus.disable();
      Navigator.pop(context);
    }
  }

  void _next(int delta) {
    final list = _flat;
    if (list.length < 2) return;
    final idx =
        list.indexWhere((c) => c.id == _channel.id || c.url == _channel.url);
    final next = ((idx < 0 ? 0 : idx) + delta) % list.length;
    final safe = next < 0 ? list.length - 1 : next;
    _switch(list[safe]);
  }

  Future<void> _switch(TvChannel ch) async {
    await _controller?.pause();
    await _controller?.dispose();
    _controller = null;
    setState(() {
      _channel = ch;
      _initialized = false;
      _hasError = false;
    });
    await _init();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () {
            if (_showControls) {
              setState(() => _showControls = false);
            } else {
              _showCtrls();
            }
          },
          child: Stack(
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorMsg ?? 'Error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: _kAccent),
                          onPressed: _init,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Center(
                    child: CircularProgressIndicator(color: _kAccent)),
              if (_showControls)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _exit,
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white),
                          ),
                          IconButton(
                            tooltip: 'Minimizar',
                            onPressed: _minimize,
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _next(-1),
                            icon: const Icon(Icons.skip_previous_rounded,
                                color: Colors.white70),
                          ),
                          IconButton(
                            onPressed: () => _next(1),
                            icon: const Icon(Icons.skip_next_rounded,
                                color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_showControls)
                Center(
                  child: IconButton(
                    iconSize: 64,
                    onPressed: _toggle,
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
