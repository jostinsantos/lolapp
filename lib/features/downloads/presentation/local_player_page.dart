import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LocalPlayerScreen extends StatefulWidget {
  final String playlistPath;
  final String title;

  const LocalPlayerScreen({
    super.key,
    required this.playlistPath,
    required this.title,
  });

  @override
  State<LocalPlayerScreen> createState() => _LocalPlayerScreenState();
}

class _LocalPlayerScreenState extends State<LocalPlayerScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  String? _errorMsg;
  bool _showControls = true;
  bool _isPlaying = false;
  bool _controlsLocked = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.playlistPath);
      if (!await file.exists()) {
        setState(() {
          _hasError = true;
          _errorMsg = 'Archivo no encontrado';
        });
        return;
      }

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      controller.addListener(_onPlayerUpdate);
      await controller.play();

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initialized = true;
        _isPlaying = true;
      });
      _scheduleHideControls();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMsg = e.toString();
      });
    }
  }

  void _onPlayerUpdate() {
    if (!mounted || _controller == null) return;
    final playing = _controller!.value.isPlaying;
    if (playing != _isPlaying) {
      setState(() => _isPlaying = playing);
    } else {
      setState(() {});
    }
  }

  void _togglePlay() {
    if (_controller == null || _controlsLocked) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    _scheduleHideControls();
  }

  void _seekRelative(int seconds) {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controlsLocked) {
      return;
    }
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    var target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    _controller!.seekTo(target);
    _scheduleHideControls();
  }

  void _seekTo(Duration position) {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controlsLocked) {
      return;
    }
    _controller!.seekTo(position);
    _scheduleHideControls();
  }

  void _toggleControls() {
    if (_controlsLocked) {
      // Bloqueado: solo mostrar el candado un momento para poder desbloquear
      setState(() => _showControls = true);
      _scheduleHideControls();
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  void _toggleLock() {
    setState(() {
      _controlsLocked = !_controlsLocked;
      _showControls = true;
    });
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    if (!_isPlaying) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
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
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Volver'),
                    ),
                  ],
                ),
              ),
            )
          : !_initialized
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : GestureDetector(
                  onTap: _toggleControls,
                  behavior: HitTestBehavior.opaque,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Video
                      Center(
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio == 0
                              ? 16 / 9
                              : _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      ),

                      // Controles (se ocultan con el timer, incluido el top bar)
                      if (_showControls) ...[
                        // ─── Top bar: solo si NO está bloqueado ────────
                        if (!_controlsLocked)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: EdgeInsets.only(
                                top: MediaQuery.paddingOf(context).top + 4,
                                left: 8,
                                right: 8,
                                bottom: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.75),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back,
                                        color: Colors.white),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                  Expanded(
                                    child: Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  // Candado → bloquear controles
                                  IconButton(
                                    tooltip: 'Bloquear controles',
                                    icon: const Icon(
                                      Icons.lock_open_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: _toggleLock,
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // ─── Centro (play / seek) ─────────────────────
                        if (!_controlsLocked)
                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _ControlButton(
                                  icon: Icons.replay_10_rounded,
                                  size: 48,
                                  onTap: () => _seekRelative(-10),
                                ),
                                const SizedBox(width: 36),
                                _ControlButton(
                                  icon: _isPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_filled_rounded,
                                  size: 72,
                                  onTap: _togglePlay,
                                ),
                                const SizedBox(width: 36),
                                _ControlButton(
                                  icon: Icons.forward_10_rounded,
                                  size: 48,
                                  onTap: () => _seekRelative(10),
                                ),
                              ],
                            ),
                          ),

                        // ─── Bottom bar (progreso) ────────────────────
                        if (!_controlsLocked)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                28,
                                16,
                                12 + MediaQuery.paddingOf(context).bottom,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.85),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: _buildProgressBar(),
                            ),
                          ),

                        // ─── Bloqueado: solo el candado para desbloquear
                        if (_controlsLocked)
                          Positioned(
                            bottom: 24 + MediaQuery.paddingOf(context).bottom,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: GestureDetector(
                                onTap: _toggleLock,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFE50914)
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.lock_rounded,
                                    color: Color(0xFFE50914),
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildProgressBar() {
    final c = _controller!;
    final duration = c.value.duration;
    final position = c.value.position;
    final maxMs =
        duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final valueMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3.5,
            activeTrackColor: const Color(0xFFE50914),
            inactiveTrackColor: Colors.white24,
            thumbColor: const Color(0xFFE50914),
            overlayColor: const Color(0xFFE50914).withValues(alpha: 0.25),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
              elevation: 2,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: valueMs,
            min: 0,
            max: maxMs,
            onChanged: (v) {
              _seekTo(Duration(milliseconds: v.round()));
            },
            onChangeStart: (_) {
              _hideTimer?.cancel();
            },
            onChangeEnd: (_) {
              _scheduleHideControls();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: size,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ),
    );
  }
}