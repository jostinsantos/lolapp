import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../servers/presentation/tv_servers_modal.dart';
import '../../../../data/datasources/remote/tmdb/tmdb_player_api.dart';

class TvPlayerWebViewPage extends StatefulWidget {
  final String url;
  final String title;
  final String? servidorNombre;
  final String? idioma;
  final int idcontenido;
  final int tmdbId;
  final int? temporada;
  final int? capitulo;
  final String tipo;

  const TvPlayerWebViewPage({
    super.key,
    required this.url,
    required this.title,
    this.servidorNombre,
    this.idioma,
    required this.idcontenido,
    required this.tmdbId,
    this.temporada,
    this.capitulo,
    required this.tipo,
  });

  @override
  State<TvPlayerWebViewPage> createState() => _TvPlayerWebViewPageState();
}

class _TvPlayerWebViewPageState extends State<TvPlayerWebViewPage>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  final FocusNode _focusNode = FocusNode(debugLabel: 'webview_cursor');

  static const _clickChannel = MethodChannel('tv_webview/click');

  double _cursorX = 0.5;
  double _cursorY = 0.5;
  Size _viewSize = Size.zero;

  bool _loading = true;
  double _progress = 0;
  String? _error;
  bool _pageReady = false;
  bool _autoPlayTried = false;

  static const double _step = 14.0;
  static const double _fastStep = 28.0;

  late final String _allowedHost;

  double _cursorOpacity = 1.0;
  Timer? _idleTimer;

  bool _showHint = true;
  Timer? _hintTimer;

  bool _clickFlash = false;
  late final AnimationController _clickAnim;

  bool _exitDialogOpen = false;

  List<dynamic> _temporadas = const [];
  Map<String, dynamic>? _siguiente;
  Map<String, int> _episodeProgress = {};
  int _selectedSeasonIndex = 0;
  bool _apiLoaded = false;
  bool _apiLoading = false;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    _allowedHost = (uri?.host ?? '').toLowerCase();

    _clickAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) setState(() => _progress = progress / 100.0);
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
                _pageReady = false;
                _autoPlayTried = false;
              });
            }
          },
          onPageFinished: (String url) async {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _pageReady = true;
            });
            await _injectFullscreenGuard();
            await _tryAutoPlay();
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _loading = false;
                _error = error.description;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (_isAllowedUrl(uri)) return NavigationDecision.navigate;
            return NavigationDecision.prevent;
          },
        ),
      );

    try {
      final platform = _controller.platform;
      if (platform is AndroidWebViewController) {
        platform.setMediaPlaybackRequiresUserGesture(false);
      }
    } catch (_) {}

    _controller.loadRequest(Uri.parse(widget.url));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    _hintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });

    _resetIdleTimer();
    _saveWebPlayerCache();
  }

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

  Future<void> _saveWebPlayerCache({int segundo = 0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final full = {
        'idcontenido': widget.idcontenido,
        'tmdbId': widget.tmdbId,
        'temporada': widget.temporada,
        'capitulo': widget.capitulo,
        'segundo': segundo,
        'titulo': widget.title,
        'tipo': widget.tipo,
        'videoUrl': widget.url,
        'servidorNombre': widget.servidorNombre,
        'idioma': widget.idioma,
        'webplayer': true,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_getCacheKey(), jsonEncode(full));

      final rapido = {
        'idcontenido': widget.idcontenido,
        'temporada': widget.temporada,
        'capitulo': widget.capitulo,
        'segundo': segundo,
        'webplayer': true,
      };
      await prefs.setString(_getCacheKeyRapido(), jsonEncode(rapido));
    } catch (_) {}
  }

  Future<void> _ensureApiData() async {
    if (_apiLoaded || _apiLoading) return;
    _apiLoading = true;
    try {
      final mediaType = widget.tipo.toLowerCase() == 'tv' ? 'tv' : 'movie';
      final service = TmdbPlayerService();
      final data = await service.fetchPlayer(
        tmdbId: widget.tmdbId,
        mediaType: mediaType,
        temporada: widget.temporada ?? 0,
        capitulo: widget.capitulo ?? 0,
      );
      if (!mounted) return;
      if (data['error'] == true) return;

      final temps = data['temporadas'] is List
          ? List<Map<String, dynamic>>.from(data['temporadas'])
          : <Map<String, dynamic>>[];

      int seasonIdx = 0;
      if (widget.temporada != null && temps.isNotEmpty) {
        final idx = temps.indexWhere((t) => t['numero'] == widget.temporada);
        if (idx >= 0) seasonIdx = idx;
      }

      final siguiente = data['siguiente'] is Map
          ? Map<String, dynamic>.from(data['siguiente'])
          : null;

      final progress = <String, int>{};
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final temp in temps) {
          final tNum = temp['numero'];
          final caps = temp['capitulos'] as List? ?? [];
          for (final cap in caps) {
            final cNum = cap['numero'];
            final key =
                'cachePlayerRapido_${widget.idcontenido}_T${tNum}_C$cNum';
            final raw = prefs.getString(key);
            if (raw != null) {
              try {
                final d = jsonDecode(raw);
                final sec = d['segundo'] as int?;
                if (sec != null && sec > 5) {
                  progress['T${tNum}_C$cNum'] = sec;
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _temporadas = temps;
          _siguiente = siguiente;
          _selectedSeasonIndex = seasonIdx;
          _episodeProgress = progress;
          _apiLoaded = true;
        });
      }
    } catch (_) {
    } finally {
      _apiLoading = false;
    }
  }

  String _optimizeTmdbUrl(String? url, {String size = 'w300'}) {
    if (url == null || url.isEmpty) return '';
    if (url.contains('image.tmdb.org/t/p/')) {
      return url.replaceFirstMapped(
        RegExp(r'/t/p/(original|w\d+|h\d+)/'),
        (m) => '/t/p/$size/',
      );
    }
    return url;
  }

  Future<void> _injectFullscreenGuard() async {
    await _controller.runJavaScript('''
      (function() {
        try {
          Element.prototype.requestFullscreen = function() {
            this.style.position = 'fixed';
            this.style.left = '0';
            this.style.top = '0';
            this.style.width = '100vw';
            this.style.height = '100vh';
            this.style.zIndex = '999998';
            this.style.objectFit = 'contain';
            this.style.background = '#000';
            return Promise.resolve();
          };
          Element.prototype.webkitRequestFullscreen = Element.prototype.requestFullscreen;
          Element.prototype.mozRequestFullScreen = Element.prototype.requestFullscreen;
          Element.prototype.msRequestFullscreen = Element.prototype.requestFullscreen;

          if (HTMLVideoElement && HTMLVideoElement.prototype) {
            HTMLVideoElement.prototype.webkitEnterFullscreen = function() {
              this.style.position = 'fixed';
              this.style.left = '0';
              this.style.top = '0';
              this.style.width = '100vw';
              this.style.height = '100vh';
              this.style.zIndex = '999998';
              this.style.objectFit = 'contain';
              this.style.background = '#000';
            };
          }
        } catch(e) {}
      })();
    ''');
  }

  Future<void> _tryAutoPlay() async {
    if (_autoPlayTried || !_pageReady) return;
    _autoPlayTried = true;

    await _controller.runJavaScript('''
      (function() {
        try {
          var videos = document.querySelectorAll('video');
          videos.forEach(function(v) {
            v.muted = false;
            v.setAttribute('playsinline', '');
            v.setAttribute('webkit-playsinline', '');
            var p = v.play();
            if (p && typeof p.catch === 'function') p.catch(function(){});
          });
        } catch(e) {}
        try {
          var selectors = [
            'button[aria-label*="play" i]',
            'button[title*="play" i]',
            '.vjs-big-play-button',
            '.ytp-large-play-button',
            '.play-button',
            '.btn-play'
          ];
          for (var s of selectors) {
            var els = document.querySelectorAll(s);
            for (var el of els) {
              var r = el.getBoundingClientRect();
              if (r.width > 20 && r.height > 20) {
                el.click();
                return;
              }
            }
          }
        } catch(e) {}
      })();
    ''');
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _hintTimer?.cancel();
    _clickAnim.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isAllowedUrl(Uri? uri) {
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return true;
    if (_allowedHost.isEmpty) return true;
    return host == _allowedHost || host.endsWith('.$_allowedHost');
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_cursorOpacity < 1.0) {
      setState(() => _cursorOpacity = 1.0);
    }
    _idleTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && !_exitDialogOpen) {
        setState(() => _cursorOpacity = 0.28);
      }
    });
  }

  void _moveCursor(double dx, double dy, {bool fast = false}) {
    if (_viewSize == Size.zero) return;
    final step = fast ? _fastStep : _step;
    setState(() {
      _cursorX = (_cursorX + dx * step).clamp(6.0, _viewSize.width - 6.0);
      _cursorY = (_cursorY + dy * step).clamp(6.0, _viewSize.height - 6.0);
    });
    _resetIdleTimer();
  }

  Future<void> _performClick() async {
    if (!_pageReady) return;

    setState(() => _clickFlash = true);
    _clickAnim.forward(from: 0).then((_) {
      if (mounted) setState(() => _clickFlash = false);
    });

    final x = _cursorX;
    final y = _cursorY;

    try {
      await _clickChannel.invokeMethod('injectClick', {'x': x, 'y': y});
    } catch (_) {
      await _jsClickFallback(x, y);
    }

    _resetIdleTimer();
  }

  Future<void> _jsClickFallback(double x, double y) async {
    final sx = x.toStringAsFixed(1);
    final sy = y.toStringAsFixed(1);
    await _controller.runJavaScript('''
      (function() {
        var el = document.elementFromPoint($sx, $sy);
        if (!el) return;
        var o = {
          bubbles: true, cancelable: true, view: window,
          clientX: $sx, clientY: $sy, button: 0
        };
        el.dispatchEvent(new MouseEvent('mousedown', o));
        el.dispatchEvent(new MouseEvent('mouseup', o));
        el.dispatchEvent(new MouseEvent('click', o));
        try { el.click(); } catch(e) {}
        try { if (typeof el.focus === 'function') el.focus(); } catch(e) {}
      })();
    ''');
  }

  Future<void> _scrollPage(double dy) async {
    if (!_pageReady) return;
    await _controller.scrollBy(0, dy.round());
  }

  // ─────────────────────────────────────────────
  // MODAL DE SALIDA — siempre al pulsar Atrás
  // ─────────────────────────────────────────────
  Future<void> _requestExit() async {
    if (_exitDialogOpen) return;
    if (!mounted) return;
    _exitDialogOpen = true;

    final isTv = widget.tipo.toLowerCase() == 'tv';

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) => _WebExitDialog(
        isTv: isTv,
        onContinue: () => Navigator.of(ctx).pop('continue'),
        onExit: () => Navigator.of(ctx).pop('exit'),
        onChangeChapter: () => Navigator.of(ctx).pop('chapter'),
        onChangeServer: () => Navigator.of(ctx).pop('server'),
      ),
    );

    _exitDialogOpen = false;
    if (!mounted) return;

    switch (result) {
      case 'exit':
        await _saveWebPlayerCache();
        if (mounted) {
          // canPop: false hace que maybePop() no haga nada → hay que forzar el pop
          Navigator.of(context).pop();
        }
        break;
      case 'chapter':
        await _openSeasonsEpisodesOverlay();
        break;
      case 'server':
        await _openServersOverlay();
        break;
      default:
        // 'continue' / null → solo cerrar el modal y seguir viendo
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
            _resetIdleTimer();
          }
        });
        break;
    }
  }

  Future<void> _openSeasonsEpisodesOverlay() async {
    if (!_apiLoaded) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => const Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              color: Color(0xFF3B82F6),
              strokeWidth: 3,
            ),
          ),
        ),
      );
      await _ensureApiData();
      if (mounted) Navigator.of(context).pop();
    }

    if (!mounted) return;
    if (_temporadas.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          _resetIdleTimer();
        }
      });
      return;
    }

    _exitDialogOpen = true;
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim, secondary) {
        return _WebSeasonsEpisodesOverlay(
          temporadas: _temporadas,
          selectedSeasonIndex: _selectedSeasonIndex,
          episodeProgress: _episodeProgress,
          currentTemporada: widget.temporada,
          currentCapitulo: widget.capitulo,
          siguiente: _siguiente,
          accentColor: const Color(0xFF3B82F6),
          optimizeTmdbUrl: _optimizeTmdbUrl,
          onClose: () {
            Navigator.of(ctx).pop();
          },
          onEpisodeSelected: ({required int temporada, required int capitulo}) {
            Navigator.of(ctx).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _openServersOverlay(temporada: temporada, capitulo: capitulo);
              }
            });
          },
          onNextEpisode: () {
            Navigator.of(ctx).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_siguiente != null) {
                final t = _siguiente!['temporada'] as int?;
                final c = _siguiente!['capitulo'] as int?;
                if (t != null && c != null) {
                  _openServersOverlay(temporada: t, capitulo: c);
                  return;
                }
              }
              _openServersOverlay();
            });
          },
          onChangeServer: () {
            Navigator.of(ctx).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openServersOverlay();
            });
          },
        );
      },
    );
    _exitDialogOpen = false;

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          _resetIdleTimer();
        }
      });
    }
  }

  Future<void> _openServersOverlay({int? temporada, int? capitulo}) async {
    _exitDialogOpen = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServidoresModalTv(
        idcontenido: widget.idcontenido,
        temporada: temporada ?? widget.temporada,
        capitulo: capitulo ?? widget.capitulo,
        tipo: widget.tipo,
        titulo: widget.title,
        fromPlayer: true,
        currentIdioma: widget.idioma,
        currentServidorUrl: null,
      ),
    );
    _exitDialogOpen = false;

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          _resetIdleTimer();
        }
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_exitDialogOpen) return KeyEventResult.ignored;

    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final fast = isRepeat;

    if (key == LogicalKeyboardKey.arrowUp) {
      _moveCursor(0, -1, fast: fast);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveCursor(0, 1, fast: fast);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveCursor(-1, 0, fast: fast);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveCursor(1, 0, fast: fast);
      return KeyEventResult.handled;
    }

    if (!isDown) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _performClick();
      return KeyEventResult.handled;
    }

    // Refuerzo por tecla (D-pad / remote que envía KeyEvent)
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      _requestExit();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.pageUp) {
      _scrollPage(-160);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _scrollPage(160);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // PopScope intercepta el Atrás del SISTEMA (Android TV)
    // para que NUNCA haga pop de la ruta sin mostrar el modal.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_exitDialogOpen) return;
        _requestExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewSize = Size(constraints.maxWidth, constraints.maxHeight);
              if (_cursorX == 0.5 && _cursorY == 0.5) {
                _cursorX = _viewSize.width / 2;
                _cursorY = _viewSize.height / 2;
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  WebViewWidget(controller: _controller),

                  Positioned(
                    left: _cursorX - 10,
                    top: _cursorY - 10,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _cursorOpacity,
                        duration: const Duration(milliseconds: 400),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_clickFlash)
                              ScaleTransition(
                                scale: Tween<double>(begin: 0.6, end: 1.8)
                                    .animate(
                                      CurvedAnimation(
                                        parent: _clickAnim,
                                        curve: Curves.easeOut,
                                      ),
                                    ),
                                child: FadeTransition(
                                  opacity: Tween<double>(
                                    begin: 0.9,
                                    end: 0,
                                  ).animate(_clickAnim),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF93C5FD),
                                        width: 2.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF3B82F6,
                                          ).withValues(alpha: 0.7),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            const _MetallicBlueCursor(),
                          ],
                        ),
                      ),
                    ),
                  ),

                  if (_loading)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        backgroundColor: Colors.white12,
                        color: const Color(0xFF3B82F6),
                        minHeight: 3,
                      ),
                    ),

                  if (_error != null)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () => _requestExit(),
                              child: const Text('Volver'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_showHint)
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _loading ? 0 : 0.85,
                          duration: const Duration(milliseconds: 500),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'D-pad · mover  ·  OK · click  ·  Back · salir',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CURSOR
// ═══════════════════════════════════════════════════════════
class _MetallicBlueCursor extends StatelessWidget {
  const _MetallicBlueCursor();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFBFDBFE), Color(0xFF3B82F6), Color(0xFF1E3A8A)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.55),
            blurRadius: 8,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1.4,
        ),
      ),
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// MODAL PRINCIPAL DE SALIDA (diseño limpio)
// ═══════════════════════════════════════════════════════════
class _WebExitDialog extends StatefulWidget {
  final bool isTv;
  final VoidCallback onContinue;
  final VoidCallback onExit;
  final VoidCallback onChangeChapter;
  final VoidCallback onChangeServer;

  const _WebExitDialog({
    required this.isTv,
    required this.onContinue,
    required this.onExit,
    required this.onChangeChapter,
    required this.onChangeServer,
  });

  @override
  State<_WebExitDialog> createState() => _WebExitDialogState();
}

class _WebExitDialogState extends State<_WebExitDialog> {
  late final List<FocusNode> _nodes;
  late final List<VoidCallback> _actions;
  late final List<String> _labels;
  late final List<bool> _isDestructive;

  @override
  void initState() {
    super.initState();
    final count = widget.isTv ? 4 : 3;
    _nodes = List.generate(count, (i) => FocusNode(debugLabel: 'web_exit_$i'));
    _actions = [
      widget.onContinue,
      widget.onExit,
      if (widget.isTv) widget.onChangeChapter,
      widget.onChangeServer,
    ];
    _labels = [
      'Reanudar',
      'Salir',
      if (widget.isTv) 'Cambiar capítulo',
      'Cambiar de servidor',
    ];
    _isDestructive = [false, true, if (widget.isTv) false, false];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      widget.onContinue();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _actions[index]();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final next = (index + 1).clamp(0, _nodes.length - 1);
      if (next != index) _nodes[next].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final prev = (index - 1).clamp(0, _nodes.length - 1);
      if (prev != index) _nodes[prev].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_nodes.length, (i) {
              return Padding(
                padding: EdgeInsets.only(bottom: i < _nodes.length - 1 ? 8 : 0),
                child: _WebExitOptionButton(
                  focusNode: _nodes[i],
                  label: _labels[i],
                  isDestructive: _isDestructive[i],
                  onKey: (e) => _onKey(i, e),
                  onTap: _actions[i],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _WebExitOptionButton extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final bool isDestructive;
  final KeyEventResult Function(KeyEvent) onKey;
  final VoidCallback onTap;

  const _WebExitOptionButton({
    required this.focusNode,
    required this.label,
    required this.isDestructive,
    required this.onKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (_, e) => onKey(e),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;

          Color bg;
          Color fg;
          Color border;

          if (hasFocus) {
            if (isDestructive) {
              bg = const Color(0xFFE50914);
              fg = Colors.white;
              border = Colors.white;
            } else {
              bg = Colors.white;
              fg = Colors.black;
              border = Colors.white;
            }
          } else {
            bg = Colors.white.withValues(alpha: 0.08);
            fg = Colors.white;
            border = Colors.transparent;
          }

          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: double.infinity,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border, width: 2),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: hasFocus ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// OVERLAY PANTALLA COMPLETA: TEMPORADAS + CAPÍTULOS
// ═══════════════════════════════════════════════════════════
class _WebSeasonsEpisodesOverlay extends StatefulWidget {
  final List<dynamic> temporadas;
  final int selectedSeasonIndex;
  final Map<String, int> episodeProgress;
  final int? currentTemporada;
  final int? currentCapitulo;
  final Map<String, dynamic>? siguiente;
  final Color accentColor;
  final String Function(String?, {String size}) optimizeTmdbUrl;
  final VoidCallback onClose;
  final void Function({required int temporada, required int capitulo})
  onEpisodeSelected;
  final VoidCallback onNextEpisode;
  final VoidCallback onChangeServer;

  const _WebSeasonsEpisodesOverlay({
    required this.temporadas,
    required this.selectedSeasonIndex,
    required this.episodeProgress,
    this.currentTemporada,
    this.currentCapitulo,
    this.siguiente,
    required this.accentColor,
    required this.optimizeTmdbUrl,
    required this.onClose,
    required this.onEpisodeSelected,
    required this.onNextEpisode,
    required this.onChangeServer,
  });

  @override
  State<_WebSeasonsEpisodesOverlay> createState() =>
      _WebSeasonsEpisodesOverlayState();
}

class _WebSeasonsEpisodesOverlayState
    extends State<_WebSeasonsEpisodesOverlay> {
  late int _seasonIndex;
  final List<FocusNode> _seasonNodes = [];
  final List<FocusNode> _episodeNodes = [];
  final FocusNode _nextNode = FocusNode(debugLabel: 'web_next_ep');
  final FocusNode _serverNode = FocusNode(debugLabel: 'web_change_server');

  final ScrollController _seasonScroll = ScrollController();
  final ScrollController _episodeScroll = ScrollController();
  final ScrollController _pageScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _seasonIndex = widget.selectedSeasonIndex.clamp(
      0,
      widget.temporadas.length - 1,
    );
    _rebuildSeasonNodes();
    _rebuildEpisodeNodes();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idx = _initialEpisodeIndex();
      if (_episodeNodes.isNotEmpty) {
        _episodeNodes[idx].requestFocus();
        _scrollEpisodeTo(idx);
      } else if (_seasonNodes.isNotEmpty) {
        _seasonNodes[_seasonIndex].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final n in _seasonNodes) {
      n.dispose();
    }
    for (final n in _episodeNodes) {
      n.dispose();
    }
    _nextNode.dispose();
    _serverNode.dispose();
    _seasonScroll.dispose();
    _episodeScroll.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  void _rebuildSeasonNodes() {
    for (final n in _seasonNodes) {
      n.dispose();
    }
    _seasonNodes
      ..clear()
      ..addAll(List.generate(widget.temporadas.length, (_) => FocusNode()));
  }

  void _rebuildEpisodeNodes() {
    for (final n in _episodeNodes) {
      n.dispose();
    }
    _episodeNodes.clear();
    final caps = _currentCaps;
    _episodeNodes.addAll(List.generate(caps.length, (_) => FocusNode()));
  }

  List get _currentCaps {
    if (widget.temporadas.isEmpty) return const [];
    return widget.temporadas[_seasonIndex]['capitulos'] as List? ?? [];
  }

  int _initialEpisodeIndex() {
    final caps = _currentCaps;
    if (caps.isEmpty) return 0;
    final seasonNum = widget.temporadas[_seasonIndex]['numero'];
    if (widget.currentTemporada != null &&
        seasonNum == widget.currentTemporada &&
        widget.currentCapitulo != null) {
      final idx = caps.indexWhere((c) => c['numero'] == widget.currentCapitulo);
      if (idx >= 0) return idx;
    }
    return 0;
  }

  void _scrollSeasonTo(int index) {
    if (!_seasonScroll.hasClients) return;
    const itemW = 130.0;
    final offset =
        (index * itemW) - (MediaQuery.sizeOf(context).width / 2) + (itemW / 2);
    _seasonScroll.animateTo(
      offset.clamp(0.0, _seasonScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _scrollEpisodeTo(int index) {
    if (!_episodeScroll.hasClients) return;
    const itemW = 170.0;
    final offset =
        (index * itemW) - (MediaQuery.sizeOf(context).width / 2) + (itemW / 2);
    _episodeScroll.animateTo(
      offset.clamp(0.0, _episodeScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _ensureBottomVisible() {
    if (!_pageScroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pageScroll.hasClients) return;
      _pageScroll.animateTo(
        _pageScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _selectSeason(int i) {
    if (i == _seasonIndex) return;
    setState(() {
      _seasonIndex = i;
      _rebuildEpisodeNodes();
    });
    _seasonNodes[i].requestFocus();
    _scrollSeasonTo(i);
  }

  bool _isBack(KeyEvent e) =>
      e.logicalKey == LogicalKeyboardKey.goBack ||
      e.logicalKey == LogicalKeyboardKey.escape ||
      e.logicalKey == LogicalKeyboardKey.browserBack;

  KeyEventResult _handleSeasonKey(int index, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isBack(e)) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      final next = (index + 1).clamp(0, _seasonNodes.length - 1);
      if (next != index) {
        setState(() {
          _seasonIndex = next;
          _rebuildEpisodeNodes();
        });
        _seasonNodes[next].requestFocus();
        _scrollSeasonTo(next);
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final prev = (index - 1).clamp(0, _seasonNodes.length - 1);
      if (prev != index) {
        setState(() {
          _seasonIndex = prev;
          _rebuildEpisodeNodes();
        });
        _seasonNodes[prev].requestFocus();
        _scrollSeasonTo(prev);
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_episodeNodes.isNotEmpty) {
        final idx = _initialEpisodeIndex().clamp(0, _episodeNodes.length - 1);
        _episodeNodes[idx].requestFocus();
        _scrollEpisodeTo(idx);
      } else {
        _nextNode.requestFocus();
        _ensureBottomVisible();
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.select ||
        e.logicalKey == LogicalKeyboardKey.enter) {
      _selectSeason(index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleEpisodeKey(int index, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isBack(e)) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      final next = (index + 1).clamp(0, _episodeNodes.length - 1);
      if (next != index) {
        _episodeNodes[next].requestFocus();
        _scrollEpisodeTo(next);
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final prev = (index - 1).clamp(0, _episodeNodes.length - 1);
      if (prev != index) {
        _episodeNodes[prev].requestFocus();
        _scrollEpisodeTo(prev);
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_seasonNodes.isNotEmpty) {
        _seasonNodes[_seasonIndex].requestFocus();
        _scrollSeasonTo(_seasonIndex);
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _nextNode.requestFocus();
      _ensureBottomVisible();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.select ||
        e.logicalKey == LogicalKeyboardKey.enter) {
      final caps = _currentCaps;
      if (index < caps.length) {
        final cap = caps[index];
        final num = cap['numero'] as int? ?? (index + 1);
        final seasonNum =
            widget.temporadas[_seasonIndex]['numero'] as int? ?? 1;
        widget.onEpisodeSelected(temporada: seasonNum, capitulo: num);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleNextKey(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isBack(e)) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_episodeNodes.isNotEmpty) {
        final idx = _initialEpisodeIndex().clamp(0, _episodeNodes.length - 1);
        _episodeNodes[idx].requestFocus();
        _scrollEpisodeTo(idx);
      } else if (_seasonNodes.isNotEmpty) {
        _seasonNodes[_seasonIndex].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _serverNode.requestFocus();
      _ensureBottomVisible();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.select ||
        e.logicalKey == LogicalKeyboardKey.enter) {
      widget.onNextEpisode();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleServerKey(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isBack(e)) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _nextNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.select ||
        e.logicalKey == LogicalKeyboardKey.enter) {
      widget.onChangeServer();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _nextLabel() {
    if (widget.siguiente != null) {
      final t = widget.siguiente!['temporada'];
      final c = widget.siguiente!['capitulo'];
      final name =
          (widget.siguiente!['titulo'] ??
                  widget.siguiente!['titulo_capitulo'] ??
                  '')
              .toString();
      final s = t != null ? 'S${t.toString().padLeft(2, '0')}' : '';
      final e = c != null ? 'E${c.toString().padLeft(2, '0')}' : '';
      if (name.isNotEmpty) return 'Siguiente: $s$e · $name';
      return 'Siguiente capítulo ($s$e)'.trim();
    }
    return 'Siguiente capítulo';
  }

  @override
  Widget build(BuildContext context) {
    final caps = _currentCaps;

    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                children: [
                  const Text(
                    'Cambiar capítulo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Back · cerrar',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _pageScroll,
                padding: const EdgeInsets.only(bottom: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView.builder(
                        controller: _seasonScroll,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: widget.temporadas.length,
                        itemBuilder: (ctx, i) {
                          final temp = widget.temporadas[i];
                          final isSelected = i == _seasonIndex;
                          return Focus(
                            focusNode: _seasonNodes[i],
                            onKeyEvent: (_, e) => _handleSeasonKey(i, e),
                            child: Builder(
                              builder: (context) {
                                final hasFocus = Focus.of(context).hasFocus;
                                return GestureDetector(
                                  onTap: () => _selectSeason(i),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 10),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.transparent
                                          : Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: hasFocus
                                            ? Colors.white
                                            : isSelected
                                            ? widget.accentColor
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      temp['nombre'] ??
                                          'Temporada ${temp['numero']}',
                                      style: TextStyle(
                                        color: isSelected
                                            ? widget.accentColor
                                            : Colors.white70,
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      height: 118,
                      child: ListView.builder(
                        controller: _episodeScroll,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: caps.length,
                        itemBuilder: (ctx, i) {
                          final cap = caps[i];
                          final num = cap['numero'];
                          final titulo = cap['titulo'] ?? 'Episodio $num';
                          final backdrop = widget.optimizeTmdbUrl(
                            cap['backdrop']?.toString(),
                            size: 'w300',
                          );
                          final seasonNum =
                              widget.temporadas[_seasonIndex]['numero'];
                          final isActual =
                              (widget.currentTemporada != null &&
                                  widget.currentCapitulo != null &&
                                  seasonNum == widget.currentTemporada &&
                                  num == widget.currentCapitulo) ||
                              cap['actual'] == true;
                          final progressKey = 'T${seasonNum}_C$num';
                          final progressSec =
                              widget.episodeProgress[progressKey];
                          final hasProgress =
                              progressSec != null && progressSec > 5;

                          return Focus(
                            focusNode: _episodeNodes.length > i
                                ? _episodeNodes[i]
                                : null,
                            onKeyEvent: (_, e) => _handleEpisodeKey(i, e),
                            child: Builder(
                              builder: (context) {
                                final hasFocus = Focus.of(context).hasFocus;
                                return GestureDetector(
                                  onTap: () {
                                    final n = num as int? ?? (i + 1);
                                    final s = seasonNum as int? ?? 1;
                                    widget.onEpisodeSelected(
                                      temporada: s,
                                      capitulo: n,
                                    );
                                  },
                                  child: Container(
                                    width: 158,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: hasFocus
                                            ? Colors.white
                                            : isActual
                                            ? widget.accentColor
                                            : Colors.transparent,
                                        width: 2,
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
                                              memCacheWidth: 320,
                                              fadeInDuration: const Duration(
                                                milliseconds: 150,
                                              ),
                                              placeholder: (_, __) =>
                                                  ColoredBox(
                                                    color: Colors.grey[900]!,
                                                  ),
                                              errorWidget: (_, __, ___) =>
                                                  ColoredBox(
                                                    color: Colors.grey[900]!,
                                                  ),
                                            )
                                          else
                                            ColoredBox(
                                              color: Colors.grey[900]!,
                                            ),
                                          const DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Color(0xD9000000),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (isActual)
                                            Positioned(
                                              top: 6,
                                              left: 6,
                                              child: Icon(
                                                Icons.play_circle_fill,
                                                color: widget.accentColor,
                                                size: 22,
                                              ),
                                            ),
                                          Positioned(
                                            bottom: 6,
                                            left: 8,
                                            right: 8,
                                            child: Text(
                                              '$num: $titulo',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          if (hasProgress)
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: LinearProgressIndicator(
                                                value: (progressSec! / 2700)
                                                    .clamp(0.0, 1.0),
                                                backgroundColor: Colors.white24,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                      widget.accentColor,
                                                    ),
                                                minHeight: 3,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 28),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Focus(
                        focusNode: _nextNode,
                        onFocusChange: (has) {
                          if (has) _ensureBottomVisible();
                        },
                        onKeyEvent: (_, e) => _handleNextKey(e),
                        child: Builder(
                          builder: (context) {
                            final hasFocus = Focus.of(context).hasFocus;
                            return GestureDetector(
                              onTap: widget.onNextEpisode,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                height: 52,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: hasFocus
                                      ? Colors.white
                                      : widget.accentColor.withValues(
                                          alpha: 0.22,
                                        ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: hasFocus
                                        ? Colors.white
                                        : widget.accentColor,
                                    width: 1.8,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.skip_next_rounded,
                                      size: 24,
                                      color: hasFocus
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _nextLabel(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: hasFocus
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
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

                    const SizedBox(height: 12),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Focus(
                        focusNode: _serverNode,
                        onFocusChange: (has) {
                          if (has) _ensureBottomVisible();
                        },
                        onKeyEvent: (_, e) => _handleServerKey(e),
                        child: Builder(
                          builder: (context) {
                            final hasFocus = Focus.of(context).hasFocus;
                            return GestureDetector(
                              onTap: widget.onChangeServer,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                height: 52,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: hasFocus
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: hasFocus
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 1.8,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.dns_rounded,
                                      size: 22,
                                      color: hasFocus
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Cambiar de servidor',
                                      style: TextStyle(
                                        color: hasFocus
                                            ? Colors.black
                                            : Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
