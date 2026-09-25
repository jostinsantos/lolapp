import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tarjeta "Siguiente episodio" con la misma lógica visual que "Omitir intro":
/// - fade + scale al aparecer / desaparecer
/// - barra inferior de auto-hide (10 s)
/// - el contador se pausa si [controlsVisible] es true
/// - al llegar a 0 llama [onAutoHide] (el padre oculta sin marcar dismissed)
class NextEpisodePrompt extends StatefulWidget {
  final String? thumbnailUrl;
  final String titleLine;
  final String subtitleLine;
  final String countdownText;
  final bool isTv;
  final FocusNode focusNode;
  final VoidCallback onPlay;
  final VoidCallback onDismiss;
  /// Auto-ocultar tras el timeout (no es dismiss manual).
  final VoidCallback onAutoHide;
  /// Baja el foco a la barra de progreso sin cerrar el prompt.
  final VoidCallback? onNavigateDown;
  final Color accentColor;
  final String Function(String?, {String size}) optimizeTmdbUrl;

  /// true mientras el padre quiere mostrar la tarjeta.
  final bool visible;

  /// Controles del player abiertos → pausa el auto-hide (como Nuvio).
  final bool controlsVisible;

  /// Duración del auto-hide en ms (default 10 s, igual que Omitir intro).
  final int autoHideMs;

  const NextEpisodePrompt({
    super.key,
    this.thumbnailUrl,
    required this.titleLine,
    required this.subtitleLine,
    required this.countdownText,
    required this.isTv,
    required this.focusNode,
    required this.onPlay,
    required this.onDismiss,
    required this.onAutoHide,
    this.onNavigateDown,
    required this.accentColor,
    required this.optimizeTmdbUrl,
    required this.visible,
    required this.controlsVisible,
    this.autoHideMs = 15000,
  });

  @override
  State<NextEpisodePrompt> createState() => _NextEpisodePromptState();
}

class _NextEpisodePromptState extends State<NextEpisodePrompt> {
  Timer? _timer;
  double _progress = 1.0; // 1 = recién mostrado, 0 = se oculta
  DateTime? _startedAt;
  bool _autoHideFired = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _startOrResume();
    }
  }

  @override
  void didUpdateWidget(covariant NextEpisodePrompt oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Acaba de hacerse visible → reiniciar contador (p.ej. al abrir controles)
    if (widget.visible && !oldWidget.visible) {
      _autoHideFired = false;
      _progress = 1.0;
      _startOrResume();
      return;
    }

    // Dejó de ser visible → parar
    if (!widget.visible && oldWidget.visible) {
      _stop();
      return;
    }

    if (!widget.visible) return;

    // Controles abiertos → pausar
    if (widget.controlsVisible && !oldWidget.controlsVisible) {
      _pause();
    }
    // Controles cerrados → reanudar
    if (!widget.controlsVisible && oldWidget.controlsVisible) {
      _resume();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startOrResume() {
    _timer?.cancel();
    _startedAt = DateTime.now().subtract(
      Duration(
        milliseconds: ((1.0 - _progress) * widget.autoHideMs).round(),
      ),
    );
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !widget.visible) {
        _stop();
        return;
      }
      // Pausado mientras hay controles
      if (widget.controlsVisible) return;
      final started = _startedAt;
      if (started == null) return;

      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final left =
          (widget.autoHideMs - elapsed).clamp(0, widget.autoHideMs);
      final p = left / widget.autoHideMs;
      if ((p - _progress).abs() > 0.008 || p <= 0) {
        setState(() => _progress = p);
      }
      if (elapsed >= widget.autoHideMs) {
        _stop();
        if (!_autoHideFired) {
          _autoHideFired = true;
          widget.onAutoHide();
        }
      }
    });
  }

  void _pause() {
    if (_startedAt == null) return;
    final elapsed =
        DateTime.now().difference(_startedAt!).inMilliseconds;
    final left =
        (widget.autoHideMs - elapsed).clamp(0, widget.autoHideMs);
    _progress = left / widget.autoHideMs;
    _startedAt = null;
  }

  void _resume() {
    if (!widget.visible || _startedAt != null || _autoHideFired) return;
    _startOrResume();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
  }

  @override
  Widget build(BuildContext context) {
    // Siempre en el árbol para poder animar salida; IgnorePointer si oculto
    return AnimatedScale(
      scale: widget.visible ? 1.0 : 0.8,
      duration: Duration(milliseconds: widget.visible ? 300 : 200),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1.0 : 0.0,
        duration: Duration(milliseconds: widget.visible ? 300 : 200),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: Focus(
            focusNode: widget.focusNode,
            onKeyEvent: (node, event) {
              if (!widget.visible) return KeyEventResult.ignored;
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space) {
                  widget.onPlay();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.browserBack) {
                  widget.onDismiss();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (widget.onNavigateDown != null) {
                    widget.onNavigateDown!();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                    event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                    event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final hasFocus = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: widget.onPlay,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 200,
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.isTv
                                          ? 'Siguiente episodio'
                                          : 'Siguiente',
                                      style: TextStyle(
                                        color: hasFocus
                                            ? Colors.black54
                                            : Colors.white
                                                .withValues(alpha: 0.6),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.titleLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: hasFocus
                                            ? Colors.black
                                            : Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: hasFocus
                                      ? widget.accentColor
                                      : widget.accentColor
                                          .withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: hasFocus
                                      ? Colors.white
                                      : Colors.white,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Barra de auto-hide (igual que Omitir intro)
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(7),
                            bottomRight: Radius.circular(7),
                          ),
                          child: LinearProgressIndicator(
                            value: _progress.clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation(
                              hasFocus
                                  ? widget.accentColor
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
}