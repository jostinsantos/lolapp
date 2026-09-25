import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/datasources/remote/tmdb/tmdb_content.dart';

class BecauseYouWatchedOverlay extends StatefulWidget {
  final VideoPlayerController videoController;
  final String currentTitle;
  final int nextIdContenido;
  final String nextTitulo;
  final String? nextPoster;
  final String? nextBackdrop;
  final String? nextLogo;
  final String nextTipo;
  final Color accentColor;
  final String Function(String? url, {String size}) optimizeTmdbUrl;
  final FocusNode producirSiguienteFocusNode;
  final FocusNode continuarCreditosFocusNode;
  final bool Function(KeyEvent event) isBackKey;
  final VoidCallback onProducirSiguiente;
  final VoidCallback onContinuarCreditos;

  const BecauseYouWatchedOverlay({
    super.key,
    required this.videoController,
    required this.currentTitle,
    required this.nextIdContenido,
    required this.nextTitulo,
    this.nextPoster,
    this.nextBackdrop,
    this.nextLogo,
    required this.nextTipo,
    required this.accentColor,
    required this.optimizeTmdbUrl,
    required this.producirSiguienteFocusNode,
    required this.continuarCreditosFocusNode,
    required this.isBackKey,
    required this.onProducirSiguiente,
    required this.onContinuarCreditos,
  });

  @override
  State<BecauseYouWatchedOverlay> createState() =>
      _BecauseYouWatchedOverlayState();
}

class _BecauseYouWatchedOverlayState extends State<BecauseYouWatchedOverlay> {
  final TmdbContentService _service = TmdbContentService();
  static const int _countdownSec = 15;

  String? _titulo;
  String? _poster;
  String? _backdrop;
  String? _logo;
  String? _overview;
  String? _generos;
  String? _anio;
  String? _duracion;
  double? _imdbRating;

  int _remaining = _countdownSec;
  Timer? _timer;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _titulo = widget.nextTitulo;
    _poster = widget.nextPoster;
    _backdrop = widget.nextBackdrop;
    _logo = widget.nextLogo;
    _cargarDetalle();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.producirSiguienteFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _remaining = _countdownSec;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _cancelled) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        widget.onProducirSiguiente();
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _cancelCountdown() {
    _cancelled = true;
    _timer?.cancel();
    if (mounted) setState(() {});
  }

  Future<void> _cargarDetalle() async {
    try {
      final res = await _service.fetchContent(
        tmdbId: widget.nextIdContenido,
        mediaType: widget.nextTipo,
      );
      if (!mounted) return;
      if (res['success'] == true && res['data'] is Map) {
        final d = Map<String, dynamic>.from(res['data'] as Map);

        String? generos;
        if (d['genres'] is List) {
          generos = (d['genres'] as List)
              .whereType<Map>()
              .map((g) => g['name']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .take(2)
              .join(' • ');
        }

        String? anio;
        final fecha = (d['release_date'] ?? d['first_air_date'])?.toString();
        if (fecha != null && fecha.length >= 4) anio = fecha.substring(0, 4);

        String? duracion;
        final runtime = d['runtime'];
        if (runtime is num && runtime > 0) {
          final h = runtime ~/ 60;
          final m = runtime.toInt() % 60;
          duracion =
              h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
        }

        final imdb = d['imdb_rating'] is num
            ? (d['imdb_rating'] as num).toDouble()
            : (d['vote_average'] is num
                ? (d['vote_average'] as num).toDouble()
                : null);

        setState(() {
          final t = d['title']?.toString();
          if (t != null && t.isNotEmpty) _titulo = t;
          final p = d['poster_path']?.toString();
          if (p != null && p.isNotEmpty) _poster = p;
          final b = d['backdrop_path']?.toString();
          if (b != null && b.isNotEmpty) _backdrop = b;
          final l = d['logo_path']?.toString();
          if (l != null && l.isNotEmpty) _logo = l;
          _overview = d['overview']?.toString();
          _generos = (generos != null && generos.isNotEmpty) ? generos : null;
          _anio = anio;
          _duracion = duracion;
          _imdbRating = (imdb != null && imdb > 0) ? imdb : null;
        });
      }
    } catch (_) {}
  }

  Widget _buildBoton({
    required FocusNode node,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool primary,
    required FocusNode otherNode,
  }) {
    return Focus(
      focusNode: node,
      onFocusChange: (_) {
        if (mounted) setState(() {});
      },
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowRight ||
            e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          otherNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        // Atrás = cancelar countdown y seguir créditos (permite salir del overlay)
        if (widget.isBackKey(e)) {
          _cancelCountdown();
          widget.onContinuarCreditos();
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
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                color: hasFocus
                    ? Colors.white
                    : (primary
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: hasFocus ? Colors.black : Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: hasFocus ? Colors.black : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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

  @override
  Widget build(BuildContext context) {
    final backdropUrl = widget.optimizeTmdbUrl(_backdrop, size: 'w1280');

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: backdropUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: backdropUrl,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 250),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                )
              : const SizedBox.shrink(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black.withValues(alpha: 0.92),
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.8),
              ],
              stops: const [0.0, 0.35, 1.0],
            ),
          ),
        ),
        // Mini-player solo si el controller sigue vivo
        if (widget.videoController.value.isInitialized)
          Positioned(
            top: 20,
            right: 24,
            child: _MiniPlayer(controller: widget.videoController),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 48, 40),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ya que viste "${widget.currentTitle}"',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_logo != null && _logo!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: widget.optimizeTmdbUrl(_logo, size: 'w500'),
                        height: 70,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        errorWidget: (_, __, ___) => _tituloFallback(),
                      )
                    else
                      _tituloFallback(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_generos != null)
                          Text(_generos!, style: _metaStyle()),
                        if (_anio != null) ...[
                          _dot(),
                          Text(_anio!, style: _metaStyle()),
                        ],
                        if (_duracion != null) ...[
                          _dot(),
                          Text(_duracion!, style: _metaStyle()),
                        ],
                        if (_imdbRating != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'IMDb ${_imdbRating!.toStringAsFixed(1)}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_overview != null && _overview!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        _overview!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildBoton(
                          node: widget.producirSiguienteFocusNode,
                          icon: Icons.play_arrow_rounded,
                          label: _cancelled
                              ? 'Producir siguiente'
                              : 'Producir siguiente ($_remaining)',
                          onTap: () {
                            _cancelCountdown();
                            widget.onProducirSiguiente();
                          },
                          primary: true,
                          otherNode: widget.continuarCreditosFocusNode,
                        ),
                        const SizedBox(width: 14),
                        _buildBoton(
                          node: widget.continuarCreditosFocusNode,
                          icon: Icons.subtitles_outlined,
                          label: 'Seguir viendo créditos',
                          onTap: () {
                            _cancelCountdown();
                            widget.onContinuarCreditos();
                          },
                          primary: false,
                          otherNode: widget.producirSiguienteFocusNode,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tituloFallback() {
    return Text(
      _titulo ?? widget.nextTitulo,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 34,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.3,
      ),
    );
  }

  TextStyle _metaStyle() => TextStyle(
        color: Colors.white.withValues(alpha: 0.85),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      );

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('•',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
      );
}

class _MiniPlayer extends StatelessWidget {
  final VideoPlayerController controller;

  const _MiniPlayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final vw = controller.value.size.width;
    final vh = controller.value.size.height;
    final aspect = (vw > 0 && vh > 0) ? vw / vh : 16 / 9;

    return Container(
      width: 230,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: aspect,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: vw > 0 ? vw : 1280,
            height: vh > 0 ? vh : 720,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}