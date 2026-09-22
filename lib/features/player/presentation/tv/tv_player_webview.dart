import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
  }

  /// Evita que el video robe toda la pantalla del sistema.
  /// Así la mira (Flutter) sigue visible encima del WebView.
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

  /// Click REAL (nativo) + fallback JS
  Future<void> _performClick() async {
    if (!_pageReady) return;

    setState(() => _clickFlash = true);
    _clickAnim.forward(from: 0).then((_) {
      if (mounted) setState(() => _clickFlash = false);
    });

    final x = _cursorX;
    final y = _cursorY;

    try {
      await _clickChannel.invokeMethod('injectClick', {
        'x': x,
        'y': y,
      });
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

  Future<void> _requestExit() async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExitConfirmDialog(
        onContinue: () => Navigator.of(ctx).pop(false),
        onExit: () => Navigator.of(ctx).pop(true),
      ),
    );

    _exitDialogOpen = false;
    if (!mounted) return;

    if (result == true) {
      Navigator.of(context).maybePop();
    } else {
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

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
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
    return Scaffold(
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

                // Mira SIEMPRE encima (también con video a pantalla completa “falsa”)
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
                                  .animate(CurvedAnimation(
                                parent: _clickAnim,
                                curve: Curves.easeOut,
                              )),
                              child: FadeTransition(
                                opacity: Tween<double>(begin: 0.9, end: 0)
                                    .animate(_clickAnim),
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
                                        color: const Color(0xFF3B82F6)
                                            .withValues(alpha: 0.7),
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
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 15),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
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
                              horizontal: 14, vertical: 8),
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
    );
  }
}

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
          colors: [
            Color(0xFFBFDBFE),
            Color(0xFF3B82F6),
            Color(0xFF1E3A8A),
          ],
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

class _ExitConfirmDialog extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onExit;

  const _ExitConfirmDialog({
    required this.onContinue,
    required this.onExit,
  });

  @override
  State<_ExitConfirmDialog> createState() => _ExitConfirmDialogState();
}

class _ExitConfirmDialogState extends State<_ExitConfirmDialog> {
  final FocusNode _continueFocus = FocusNode(debugLabel: 'exit_continue');
  final FocusNode _exitFocus = FocusNode(debugLabel: 'exit_exit');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _continueFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _continueFocus.dispose();
    _exitFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onContinueKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _exitFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      widget.onContinue();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      widget.onContinue();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onExitKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _continueFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      widget.onContinue();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.exit_to_app_rounded,
                color: Color(0xFF3B82F6), size: 40),
            const SizedBox(height: 16),
            const Text(
              '¿Salir del reproductor?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Se cerrará la página del servidor.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    focusNode: _continueFocus,
                    label: 'Continuar',
                    primary: true,
                    onKey: _onContinueKey,
                    onTap: widget.onContinue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DialogButton(
                    focusNode: _exitFocus,
                    label: 'Regresar',
                    primary: false,
                    onKey: _onExitKey,
                    onTap: widget.onExit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final bool primary;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback onTap;

  const _DialogButton({
    required this.focusNode,
    required this.label,
    required this.primary,
    required this.onKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKey,
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primary
                    ? (hasFocus
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF2563EB).withValues(alpha: 0.85))
                    : (hasFocus
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : (primary
                          ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                          : Colors.white24),
                  width: hasFocus ? 2.2 : 1.2,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: hasFocus ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}