import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'cast_manager.dart';

/// Pantalla dedicada de transmisión Cast.
/// Muestra el contenido que se está reproduciendo en la TV, tiempo transcurrido,
/// controles play/pause/seek y botones Omitir intro / Omitir outro.
class CastScreen extends StatefulWidget {
  final String title;
  final String? backdropUrl;
  final Color accentColor;

  const CastScreen({
    super.key,
    required this.title,
    this.backdropUrl,
    this.accentColor = const Color(0xFFFF6B00),
  });

  @override
  State<CastScreen> createState() => _CastScreenState();
}

class _CastScreenState extends State<CastScreen> {
  static const Color netflixRed = Color(0xFFE50914);

  final _mgr = CastManager();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = true;
  bool _connected = true;

  bool _showSkipIntro = false;
  bool _showSkipOutro = false;
  bool _skipIntroDismissed = false;
  bool _skipOutroDismissed = false;

  StreamSubscription? _posSub;
  StreamSubscription? _playSub;
  StreamSubscription? _connSub;
  Timer? _uiTicker;

  @override
  void initState() {
    super.initState();
    // Siempre vertical: nunca horizontal en la pantalla de Cast
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _position = _mgr.position;
    _duration = _mgr.duration;
    _isPlaying = _mgr.isPlaying;
    _connected = _mgr.isConnected;

    _posSub = _mgr.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
        _updateSkipVisibility();
      });
    });

    _playSub = _mgr.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
    });

    _connSub = _mgr.connectedStream.listen((c) {
      if (!mounted) return;
      setState(() => _connected = c);
      if (!c) {
        // Sesión perdida → salir sin volver al player
        Future.microtask(() {
          if (mounted) _exitWithoutPlayer();
        });
      }
    });

    // Ticker local por si positionStream no llega con frecuencia
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_mgr.isConnected) return;
      setState(() {
        _position = _mgr.position;
        _duration = _mgr.duration;
        _isPlaying = _mgr.isPlaying;
        _updateSkipVisibility();
      });
    });
  }

  void _updateSkipVisibility() {
    final posSec = _position.inMilliseconds / 1000.0;

    // Intro
    if (_mgr.introStartSec != null &&
        _mgr.introEndSec != null &&
        !_skipIntroDismissed) {
      final inIntro = posSec >= _mgr.introStartSec! &&
          posSec <= _mgr.introEndSec!;
      _showSkipIntro = inIntro;
      if (!inIntro) _skipIntroDismissed = false;
    } else {
      _showSkipIntro = false;
    }

    // Outro
    if (_mgr.outroStartSec != null &&
        _mgr.outroEndSec != null &&
        !_skipOutroDismissed) {
      final inOutro = posSec >= _mgr.outroStartSec! &&
          posSec <= _mgr.outroEndSec!;
      _showSkipOutro = inOutro;
      if (!inOutro) _skipOutroDismissed = false;
    } else {
      _showSkipOutro = false;
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playSub?.cancel();
    _connSub?.cancel();
    _uiTicker?.cancel();
    // No restauramos landscape aquí: el home/móvil ya fija portrait.
    // Si el usuario vuelve al player, el player pondrá landscape en su initState.
    super.dispose();
  }

  /// Sale de CastScreen.
  /// Si se abrió con pushReplacement (recomendado), un solo pop vuelve al home
  /// y no al player → no se ve la doble reproducción.
  void _exitWithoutPlayer() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onBack() async {
    // Solo cerramos la UI de Cast; la sesión Cast sigue viva en CastManager.
    // No volvemos al player → evita ver el video local + el de la TV.
    _exitWithoutPlayer();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _confirmDisconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Detener transmisión?',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'Se desconectará del Chromecast / TV.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Detener',
                style: TextStyle(color: netflixRed)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _mgr.disconnect();
      if (mounted) _exitWithoutPlayer();
    }
  }

  Future<void> _onSkipIntro() async {
    await _mgr.skipIntro();
    setState(() {
      _showSkipIntro = false;
      _skipIntroDismissed = true;
    });
  }

  Future<void> _onSkipOutro() async {
    await _mgr.skipOutro();
    setState(() {
      _showSkipOutro = false;
      _skipOutroDismissed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.title.isNotEmpty ? widget.title : _mgr.currentTitle;
    final backdrop = (widget.backdropUrl != null &&
            widget.backdropUrl!.isNotEmpty)
        ? widget.backdropUrl!
        : _mgr.backdropUrl;

    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _onBack,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transmitiendo a TV',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title.isNotEmpty ? title : 'Video',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _connected
                          ? widget.accentColor.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _connected
                            ? widget.accentColor.withValues(alpha: 0.5)
                            : Colors.redAccent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _connected
                              ? Icons.cast_connected_rounded
                              : Icons.cast_rounded,
                          color: _connected
                              ? widget.accentColor
                              : Colors.redAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _connected ? 'Conectado' : 'Desconectado',
                          style: TextStyle(
                            color: _connected
                                ? widget.accentColor
                                : Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),

            // ── Artwork / backdrop ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (backdrop.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: backdrop,
                          fit: BoxFit.cover,
                          memCacheWidth: 800,
                          placeholder: (_, __) =>
                              ColoredBox(color: Colors.grey[900]!),
                          errorWidget: (_, __, ___) =>
                              ColoredBox(color: Colors.grey[900]!),
                        )
                      else
                        ColoredBox(color: Colors.grey[900]!),
                      // Overlay oscuro + icono TV
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.45),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Icon(
                            Icons.tv_rounded,
                            color: widget.accentColor,
                            size: 32,
                          ),
                        ),
                      ),
                      // Badge "En TV"
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.accentColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'EN TV',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Tiempo ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  Text(
                    _fmt(_position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _duration > Duration.zero
                        ? _fmt(_duration)
                        : '--:--',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // ── Progress bar ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3.5,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: widget.accentColor,
                  inactiveTrackColor:
                      Colors.white.withValues(alpha: 0.18),
                  thumbColor: widget.accentColor,
                  overlayColor:
                      widget.accentColor.withValues(alpha: 0.25),
                ),
                child: Slider(
                  value: progress,
                  onChanged: (v) {
                    if (_duration <= Duration.zero) return;
                    final target = Duration(
                      milliseconds:
                          (v * _duration.inMilliseconds).round(),
                    );
                    setState(() => _position = target);
                    _mgr.seek(target);
                  },
                ),
              ),
            ),

            // ── Skip intro / outro ────────────────────────────────────
            if (_showSkipIntro || _showSkipOutro)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_showSkipIntro)
                      _SkipChip(
                        label: 'Omitir intro',
                        icon: Icons.fast_forward_rounded,
                        accent: widget.accentColor,
                        onTap: _onSkipIntro,
                      ),
                    if (_showSkipIntro && _showSkipOutro)
                      const SizedBox(width: 10),
                    if (_showSkipOutro)
                      _SkipChip(
                        label: 'Omitir outro',
                        icon: Icons.skip_next_rounded,
                        accent: widget.accentColor,
                        onTap: _onSkipOutro,
                      ),
                  ],
                ),
              ),

            const Spacer(flex: 1),

            // ── Controles centrales ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundCtrl(
                    icon: Icons.replay_10_rounded,
                    size: 28,
                    onTap: () => _mgr.seekRelative(-10),
                  ),
                  _RoundCtrl(
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 40,
                    filled: true,
                    accent: widget.accentColor,
                    onTap: () => _mgr.togglePlay(),
                  ),
                  _RoundCtrl(
                    icon: Icons.forward_10_rounded,
                    size: 28,
                    onTap: () => _mgr.seekRelative(10),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Botón desconectar ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _confirmDisconnect,
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: const Text(
                    'Detener y desconectar',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.7),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
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

// ── Widgets auxiliares ────────────────────────────────────────────────────

class _RoundCtrl extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool filled;
  final Color? accent;

  const _RoundCtrl({
    required this.icon,
    required this.size,
    required this.onTap,
    this.filled = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? const Color(0xFFFF6B00);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: size + 28,
          height: size + 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? color.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.08),
            border: filled
                ? Border.all(color: color.withValues(alpha: 0.5))
                : null,
          ),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

class _SkipChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _SkipChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}