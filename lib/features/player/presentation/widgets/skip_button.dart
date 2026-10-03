import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Datos de un segmento (intro / outro / recap) normalizados a segundos.
class SkipSegment {
  final double startSec;
  final double endSec;

  const SkipSegment({required this.startSec, required this.endSec});

  bool contains(double posSec) => posSec >= startSec && posSec <= endSec;
}

/// Resultado de las APIs de skip (introdb + skipdb).
class SkipSegmentsData {
  final SkipSegment? intro;
  final SkipSegment? outro;
  final SkipSegment? recap;
  final String source; // 'introdb' | 'skipdb' | 'none'

  const SkipSegmentsData({
    this.intro,
    this.outro,
    this.recap,
    this.source = 'none',
  });

  bool get hasIntro => intro != null;
  bool get hasOutro => outro != null;
}

/// Carga intro/outro/recap con fallback:
/// 1) api.introdb.app
/// 2) api.skipdb.tv
/// Si ninguna responde, [source] queda en 'none' (el caller usa el 95 % para outro).
class SkipSegmentsLoader {
  static Future<SkipSegmentsData> load({
    required String imdbId,
    int? season,
    int? episode,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final id = imdbId.trim();
    if (id.isEmpty) return const SkipSegmentsData();

    // ── 1) Primary: introdb ──────────────────────────────────────────────
    try {
      final data = await _fetchIntroDb(
        imdbId: id,
        season: season,
        episode: episode,
        timeout: timeout,
      );
      if (data != null && (data.hasIntro || data.hasOutro)) {
        return data;
      }
    } catch (e) {
      debugPrint('SkipSegmentsLoader introdb error: $e');
    }

    // ── 2) Secondary: skipdb ─────────────────────────────────────────────
    try {
      final data = await _fetchSkipDb(
        imdbId: id,
        season: season,
        episode: episode,
        timeout: timeout,
      );
      if (data != null && (data.hasIntro || data.hasOutro)) {
        return data;
      }
    } catch (e) {
      debugPrint('SkipSegmentsLoader skipdb error: $e');
    }

    return const SkipSegmentsData();
  }

  static Future<SkipSegmentsData?> _fetchIntroDb({
    required String imdbId,
    int? season,
    int? episode,
    required Duration timeout,
  }) async {
    final params = <String, String>{'imdb_id': imdbId};
    if (season != null) params['season'] = season.toString();
    if (episode != null) params['episode'] = episode.toString();

    final uri = Uri.https('api.introdb.app', '/segments', params);
    final res = await http.get(uri).timeout(timeout);
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    if (data is! Map) return null;

    SkipSegment? intro, outro, recap;

    final introMap = data['intro'];
    if (introMap is Map) {
      final start = _toSec(introMap['start_sec'] ?? introMap['start_ms']);
      final end = _toSec(introMap['end_sec'] ?? introMap['end_ms']);
      if (start != null && end != null && end > start) {
        intro = SkipSegment(startSec: start, endSec: end);
      }
    }

    final outroMap = data['outro'];
    if (outroMap is Map) {
      final start = _toSec(outroMap['start_sec'] ?? outroMap['start_ms']);
      final end = _toSec(outroMap['end_sec'] ?? outroMap['end_ms']);
      if (start != null) {
        outro = SkipSegment(
          startSec: start,
          endSec: end ?? (start + 120), // fallback si no hay end
        );
      }
    }

    final recapMap = data['recap'];
    if (recapMap is Map) {
      final start = _toSec(recapMap['start_sec'] ?? recapMap['start_ms']);
      final end = _toSec(recapMap['end_sec'] ?? recapMap['end_ms']);
      if (start != null && end != null && end > start) {
        recap = SkipSegment(startSec: start, endSec: end);
      }
    }

    return SkipSegmentsData(
      intro: intro,
      outro: outro,
      recap: recap,
      source: 'introdb',
    );
  }

  static Future<SkipSegmentsData?> _fetchSkipDb({
    required String imdbId,
    int? season,
    int? episode,
    required Duration timeout,
  }) async {
    final params = <String, String>{'imdb_id': imdbId};
    if (season != null) params['season'] = season.toString();
    if (episode != null) params['episode'] = episode.toString();

    final uri = Uri.https('api.skipdb.tv', '/api/segments', params);
    final res = await http.get(uri).timeout(timeout);
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    if (data is! Map) return null;

    final segments = data['segments'];
    if (segments is! Map) return null;

    SkipSegment? intro, outro, recap;

    final introMap = segments['intro'];
    if (introMap is Map) {
      final start = _msToSec(introMap['start_ms']);
      final end = _msToSec(introMap['end_ms']);
      if (start != null && end != null && end > start) {
        intro = SkipSegment(startSec: start, endSec: end);
      }
    }

    final outroMap = segments['outro'];
    if (outroMap is Map) {
      final start = _msToSec(outroMap['start_ms']);
      final end = _msToSec(outroMap['end_ms']);
      if (start != null) {
        outro = SkipSegment(
          startSec: start,
          endSec: end ?? (start + 120),
        );
      }
    }

    final recapMap = segments['recap'];
    if (recapMap is Map) {
      final start = _msToSec(recapMap['start_ms']);
      final end = _msToSec(recapMap['end_ms']);
      if (start != null && end != null && end > start) {
        recap = SkipSegment(startSec: start, endSec: end);
      }
    }

    return SkipSegmentsData(
      intro: intro,
      outro: outro,
      recap: recap,
      source: 'skipdb',
    );
  }

  /// Interpreta un valor que puede venir en segundos o milisegundos.
  static double? _toSec(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final d = v.toDouble();
      // Heurística: valores > 10000 suelen ser ms
      if (d > 10000) return d / 1000.0;
      return d;
    }
    if (v is String) {
      final cleaned = v.trim();
      if (cleaned.contains(':')) {
        // Formato hh:mm:ss o mm:ss
        final parts = cleaned.split(':');
        try {
          if (parts.length == 3) {
            return int.parse(parts[0]) * 3600.0 +
                int.parse(parts[1]) * 60.0 +
                double.parse(parts[2]);
          }
          if (parts.length == 2) {
            return int.parse(parts[0]) * 60.0 + double.parse(parts[1]);
          }
        } catch (_) {}
      }
      final n = double.tryParse(cleaned);
      if (n != null) {
        if (n > 10000) return n / 1000.0;
        return n;
      }
    }
    return null;
  }

  static double? _msToSec(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble() / 1000.0;
    if (v is String) {
      final n = double.tryParse(v.trim());
      if (n != null) return n / 1000.0;
    }
    return null;
  }
}

/// Widget unificado de "Omitir intro" + prompt de siguiente episodio (outro).
///
/// - Carga segmentos con fallback introdb → skipdb.
/// - Si no hay intro, no muestra el botón de omitir intro.
/// - Si no hay outro de ninguna API, usa [nextThresholdPct] (por defecto 0.95)
///   para mostrar el prompt de siguiente.
/// - Cuando el botón está visible, mantiene/recupera el foco aunque se
///   abran o cierren los controles del player.
class OmitirBoton extends StatefulWidget {
  final String? imdbId;
  final int? season;
  final int? episode;

  /// Posición actual del vídeo (se actualiza desde el player).
  final Duration currentPosition;
  final Duration totalDuration;

  /// Fracción de duración a partir de la cual se considera "outro"
  /// cuando ninguna API devolvió datos de outro (por defecto 0.95).
  final double nextThresholdPct;

  /// true = serie (usa "Siguiente episodio"), false = película.
  final bool isTv;

  final bool showControls;
  final bool showToolbarOnly;
  final bool showSeasonsAndEpisodes;

  /// Si true, no se muestra nada (p.ej. cuando está activo BecauseYouWatched).
  final bool hideAll;

  // ── Intro ──────────────────────────────────────────────────────────────
  final FocusNode skipIntroFocusNode;
  /// El player hace el seek. Recibe el endSec del intro (o null).
  final ValueChanged<double?> onSkipIntro;

  // ── Next episode / outro ───────────────────────────────────────────────
  final FocusNode nextPromptFocusNode;
  final String? nextThumbnailUrl;
  final String nextTitleLine;
  final VoidCallback onPlayNext;
  final VoidCallback onDismissNext;
  final VoidCallback? onNavigateDownFromNext;

  /// Callback cuando el player debe mostrar/ocultar el prompt de next
  /// (para sincronizar estado interno del player si lo necesita).
  final ValueChanged<bool>? onNextPromptVisibilityChanged;

  /// Callback cuando el player debe saber si el skip-intro está visible.
  final ValueChanged<bool>? onSkipIntroVisibilityChanged;

  final Color accentColor;
  final String Function(String?, {String size}) optimizeTmdbUrl;

  /// true si hay siguiente episodio o recomendación disponible.
  final bool hasNextContent;

  const OmitirBoton({
    super.key,
    this.imdbId,
    this.season,
    this.episode,
    required this.currentPosition,
    required this.totalDuration,
    this.nextThresholdPct = 0.95,
    required this.isTv,
    required this.showControls,
    required this.showToolbarOnly,
    this.showSeasonsAndEpisodes = false,
    this.hideAll = false,
    required this.skipIntroFocusNode,
    required this.onSkipIntro,
    required this.nextPromptFocusNode,
    this.nextThumbnailUrl,
    required this.nextTitleLine,
    required this.onPlayNext,
    required this.onDismissNext,
    this.onNavigateDownFromNext,
    this.onNextPromptVisibilityChanged,
    this.onSkipIntroVisibilityChanged,
    required this.accentColor,
    required this.optimizeTmdbUrl,
    this.hasNextContent = true,
  });

  @override
  State<OmitirBoton> createState() => OmitirBotonState();
}

class OmitirBotonState extends State<OmitirBoton> {
  SkipSegmentsData _segments = const SkipSegmentsData();
  bool _loading = false;
  bool _showSkipIntro = false;
  bool _showNextPrompt = false;
  bool _dismissedNext = false;

  String? _lastImdb;
  int? _lastSeason;
  int? _lastEpisode;

  /// End del intro en segundos (para que el player haga seek).
  double? get introEndSec => _segments.intro?.endSec;

  bool get isSkipIntroVisible => _showSkipIntro;
  bool get isNextPromptVisible => _showNextPrompt;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant OmitirBoton oldWidget) {
    super.didUpdateWidget(oldWidget);

    final imdbChanged = widget.imdbId != _lastImdb ||
        widget.season != _lastSeason ||
        widget.episode != _lastEpisode;
    if (imdbChanged) {
      _dismissedNext = false;
      _maybeLoad();
    }

    _updateVisibility();
  }

  Future<void> _maybeLoad() async {
    final imdb = (widget.imdbId ?? '').trim();
    if (imdb.isEmpty) {
      _segments = const SkipSegmentsData();
      _lastImdb = null;
      return;
    }
    if (_loading) return;
    if (imdb == _lastImdb &&
        widget.season == _lastSeason &&
        widget.episode == _lastEpisode &&
        _segments.source != 'none') {
      return;
    }

    _loading = true;
    _lastImdb = imdb;
    _lastSeason = widget.season;
    _lastEpisode = widget.episode;

    final data = await SkipSegmentsLoader.load(
      imdbId: imdb,
      season: widget.season,
      episode: widget.episode,
    );

    if (!mounted) return;
    setState(() {
      _segments = data;
      _loading = false;
    });
    _updateVisibility();
  }

  /// Decide si mostrar omitir-intro y/o next-prompt según la posición.
  void _updateVisibility() {
    if (widget.hideAll || widget.totalDuration.inSeconds <= 0) {
      _setSkipIntro(false);
      _setNextPrompt(false);
      return;
    }

    final pos = widget.currentPosition.inMilliseconds / 1000.0;
    final remaining = widget.totalDuration - widget.currentPosition;

    // ── Intro ────────────────────────────────────────────────────────────
    bool introVisible = false;
    if (_segments.hasIntro) {
      introVisible = _segments.intro!.contains(pos);
    }
    // Si no hay datos de intro de ninguna API → no mostrar botón.
    _setSkipIntro(introVisible);

    // ── Outro / next ─────────────────────────────────────────────────────
    if (_dismissedNext || !widget.hasNextContent) {
      _setNextPrompt(false);
      return;
    }

    bool nextVisible = false;
    if (_segments.hasOutro) {
      nextVisible = pos >= _segments.outro!.startSec &&
          remaining > const Duration(seconds: 2);
    } else {
      // Fallback 95 % (o el umbral configurado)
      final progress = widget.currentPosition.inMilliseconds /
          widget.totalDuration.inMilliseconds;
      nextVisible = progress >= widget.nextThresholdPct &&
          remaining > const Duration(seconds: 2);
    }

    // No mostrar next mientras el skip-intro esté activo
    if (introVisible) nextVisible = false;

    _setNextPrompt(nextVisible);
  }

  void _setSkipIntro(bool v) {
    if (v == _showSkipIntro) return;
    setState(() => _showSkipIntro = v);
    widget.onSkipIntroVisibilityChanged?.call(v);
    if (v) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showSkipIntro) {
          widget.skipIntroFocusNode.requestFocus();
        }
      });
    }
  }

  void _setNextPrompt(bool v) {
    if (v == _showNextPrompt) return;
    setState(() => _showNextPrompt = v);
    widget.onNextPromptVisibilityChanged?.call(v);
    if (v) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showNextPrompt) {
          widget.nextPromptFocusNode.requestFocus();
        }
      });
    }
  }

  double get _bottomOffset {
    if (widget.showControls || widget.showToolbarOnly) {
      return widget.showSeasonsAndEpisodes ? 280.0 : 150.0;
    }
    return 48.0;
  }

  double get _nextBottomOffset {
    if (widget.showControls || widget.showToolbarOnly) {
      return widget.showSeasonsAndEpisodes ? 290.0 : 160.0;
    }
    return 56.0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hideAll) return const SizedBox.shrink();

    return Stack(
      children: [
        if (_showSkipIntro)
          Positioned(
            right: 28,
            bottom: _bottomOffset,
            child: _SkipIntroButton(
              focusNode: widget.skipIntroFocusNode,
              onSkip: () {
                final end = _segments.intro?.endSec;
                widget.onSkipIntro(end);
                setState(() => _showSkipIntro = false);
                widget.onSkipIntroVisibilityChanged?.call(false);
              },
              onNavigateDown: () {
                widget.onNavigateDownFromNext?.call();
              },
            ),
          ),
        if (_showNextPrompt && widget.hasNextContent)
          Positioned(
            right: 28,
            bottom: _nextBottomOffset,
            child: _NextEpisodePromptInner(
              thumbnailUrl: widget.nextThumbnailUrl,
              titleLine: widget.nextTitleLine,
              isTv: widget.isTv,
              focusNode: widget.nextPromptFocusNode,
              onPlay: widget.onPlayNext,
              onDismiss: () {
                setState(() {
                  _showNextPrompt = false;
                  _dismissedNext = true;
                });
                widget.onNextPromptVisibilityChanged?.call(false);
                widget.onDismissNext();
              },
              onNavigateDown: widget.onNavigateDownFromNext,
              accentColor: widget.accentColor,
              optimizeTmdbUrl: widget.optimizeTmdbUrl,
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón "Omitir intro"
// ─────────────────────────────────────────────────────────────────────────────

class _SkipIntroButton extends StatelessWidget {
  final FocusNode focusNode;
  final VoidCallback onSkip;
  final VoidCallback? onNavigateDown;

  const _SkipIntroButton({
    required this.focusNode,
    required this.onSkip,
    this.onNavigateDown,
  });

  bool _isBackKey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            onSkip();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            onNavigateDown?.call();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            // Mantener foco en el botón; no dejar que se escape
            return KeyEventResult.handled;
          }
          if (_isBackKey(event)) {
            // Dejar que el player maneje el back (cerrar controles / salir)
            return KeyEventResult.ignored;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onSkip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                    color: hasFocus ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Omitir intro',
                    style: TextStyle(
                      color: hasFocus ? Colors.black : Colors.white,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prompt de siguiente episodio (mismo diseño que NextEpisodePrompt original)
// ─────────────────────────────────────────────────────────────────────────────

class _NextEpisodePromptInner extends StatelessWidget {
  final String? thumbnailUrl;
  final String titleLine;
  final bool isTv;
  final FocusNode focusNode;
  final VoidCallback onPlay;
  final VoidCallback onDismiss;
  final VoidCallback? onNavigateDown;
  final Color accentColor;
  final String Function(String?, {String size}) optimizeTmdbUrl;

  const _NextEpisodePromptInner({
    this.thumbnailUrl,
    required this.titleLine,
    required this.isTv,
    required this.focusNode,
    required this.onPlay,
    required this.onDismiss,
    this.onNavigateDown,
    required this.accentColor,
    required this.optimizeTmdbUrl,
  });

  bool _isBackKey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            onPlay();
            return KeyEventResult.handled;
          }
          if (_isBackKey(event)) {
            onDismiss();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            onNavigateDown?.call();
            return KeyEventResult.handled;
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
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(maxWidth: 280),
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xE6121212),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.2),
                width: hasFocus ? 1.8 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onPlay,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isTv ? 'Siguiente episodio' : 'Siguiente',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              titleLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
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
                              ? Colors.white
                              : accentColor.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: hasFocus ? Colors.black : Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}