import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WebView móvil — estilo sobrio como TV.
/// Siempre horizontal. Un solo botón atrás (blur) que se desvanece.
class WebPlayerView extends StatefulWidget {
  final int idcontenido;
  final int? tmdbId;
  final int? temporada;
  final int? capitulo;
  final String servidorUrl;
  final String servidorNombre;
  final String tipo;
  final String titulo;
  final String? idioma;
  final String? backdropUrl;
  final String? posterUrl;
  final VoidCallback? onChangeServer;

  const WebPlayerView({
    super.key,
    required this.idcontenido,
    this.tmdbId,
    this.temporada,
    this.capitulo,
    required this.servidorUrl,
    required this.servidorNombre,
    required this.tipo,
    required this.titulo,
    this.idioma,
    this.backdropUrl,
    this.posterUrl,
    this.onChangeServer,
  });

  @override
  State<WebPlayerView> createState() => _WebPlayerViewState();
}

class _WebPlayerViewState extends State<WebPlayerView>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  late final String _allowedHost;

  bool _loading = true;
  double _progress = 0;
  String? _error;
  bool _pageReady = false;
  bool _autoPlayTried = false;
  bool _exitDialogOpen = false;

  /// Opacidad del botón atrás (1 → ~0.15 con el tiempo).
  double _backOpacity = 1.0;
  Timer? _fadeTimer;
  static const _fadeStep = Duration(milliseconds: 120);
  static const _fadeInterval = Duration(milliseconds: 80);
  static const _minOpacity = 0.12;

  int get _resolvedTmdbId =>
      (widget.tmdbId != null && widget.tmdbId! > 0)
          ? widget.tmdbId!
          : widget.idcontenido;

  @override
  void initState() {
    super.initState();

    final uri = Uri.tryParse(widget.servidorUrl);
    _allowedHost = (uri?.host ?? '').toLowerCase();

    // Siempre horizontal (como TV)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100.0);
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
                _pageReady = false;
                _autoPlayTried = false;
              });
            }
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _pageReady = true;
            });
            await _injectFullscreenGuard();
            await _tryAutoPlay();
          },
          onWebResourceError: (err) {
            if (err.isForMainFrame == true && mounted) {
              setState(() {
                _loading = false;
                _error = err.description;
              });
            }
          },
          onNavigationRequest: (req) {
            final u = Uri.tryParse(req.url);
            if (u == null) return NavigationDecision.prevent;
            if (_isAllowedUrl(u)) return NavigationDecision.navigate;
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

    final url = widget.servidorUrl.trim();
    if (url.isEmpty) {
      _loading = false;
      _error = 'URL de servidor vacía';
    } else {
      _controller.loadRequest(Uri.parse(url));
    }

    unawaited(_saveWebPlayerCache());
    _startBackFade();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── Botón atrás: visible → más transparente con el tiempo ────────────
  void _startBackFade() {
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(_fadeInterval, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = (_backOpacity - 0.035).clamp(_minOpacity, 1.0);
      if (next == _backOpacity) {
        t.cancel();
        return;
      }
      setState(() => _backOpacity = next);
    });
  }

  void _wakeBackButton() {
    setState(() => _backOpacity = 1.0);
    _startBackFade();
  }

  // ─── Host permitido ─────────────────────────────────────────────────────
  bool _isAllowedUrl(Uri? uri) {
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return true;
    if (_allowedHost.isEmpty) return true;
    return host == _allowedHost || host.endsWith('.$_allowedHost');
  }

  // ─── Caché ──────────────────────────────────────────────────────────────
  String _getCacheKey() {
    if (widget.tipo.toLowerCase() == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'cachePlayer_${widget.idcontenido}_T${widget.temporada}_C${widget.capitulo}';
    }
    return 'cachePlayer_${widget.idcontenido}';
  }

  String _getCacheKeyRapido() {
    if (widget.tipo.toLowerCase() == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'cachePlayerRapido_${widget.idcontenido}_T${widget.temporada}_C${widget.capitulo}';
    }
    return 'cachePlayerRapido_${widget.idcontenido}';
  }

  Future<void> _saveWebPlayerCache({int segundo = 0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _getCacheKey(),
        jsonEncode({
          'idcontenido': widget.idcontenido,
          'tmdbId': _resolvedTmdbId,
          'temporada': widget.temporada,
          'capitulo': widget.capitulo,
          'segundo': segundo,
          'titulo': widget.titulo,
          'tipo': widget.tipo,
          'videoUrl': widget.servidorUrl,
          'servidorNombre': widget.servidorNombre,
          'idioma': widget.idioma,
          'webplayer': true,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
      await prefs.setString(
        _getCacheKeyRapido(),
        jsonEncode({
          'idcontenido': widget.idcontenido,
          'temporada': widget.temporada,
          'capitulo': widget.capitulo,
          'segundo': segundo,
          'webplayer': true,
        }),
      );
    } catch (_) {}
  }

  // ─── JS helpers (como TV) ───────────────────────────────────────────────
  Future<void> _injectFullscreenGuard() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          try {
            Element.prototype.requestFullscreen = function() {
              this.style.position = 'fixed';
              this.style.left = '0'; this.style.top = '0';
              this.style.width = '100vw'; this.style.height = '100vh';
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
                this.style.left = '0'; this.style.top = '0';
                this.style.width = '100vw'; this.style.height = '100vh';
                this.style.zIndex = '999998';
                this.style.objectFit = 'contain';
                this.style.background = '#000';
              };
            }
          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _tryAutoPlay() async {
    if (_autoPlayTried || !_pageReady) return;
    _autoPlayTried = true;
    try {
      await _controller.runJavaScript('''
        (function() {
          try {
            document.querySelectorAll('video').forEach(function(v) {
              v.muted = false;
              v.setAttribute('playsinline', '');
              v.setAttribute('webkit-playsinline', '');
              var p = v.play();
              if (p && p.catch) p.catch(function(){});
            });
          } catch(e) {}
          try {
            var sels = [
              'button[aria-label*="play" i]',
              'button[title*="play" i]',
              '.vjs-big-play-button',
              '.ytp-large-play-button',
              '.play-button', '.btn-play'
            ];
            for (var s of sels) {
              var els = document.querySelectorAll(s);
              for (var el of els) {
                var r = el.getBoundingClientRect();
                if (r.width > 20 && r.height > 20) { el.click(); return; }
              }
            }
          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }

  // ─── Menú salida (sobrio, como TV) ──────────────────────────────────────
  Future<void> _requestExit() async {
    if (_exitDialogOpen) return;
    if (!mounted) return;
    _wakeBackButton();
    _exitDialogOpen = true;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => _ExitSheet(
        title: widget.titulo,
        servidor: widget.servidorNombre,
        onContinue: () => Navigator.of(ctx).pop('continue'),
        onExit: () => Navigator.of(ctx).pop('exit'),
        onChangeServer: () => Navigator.of(ctx).pop('server'),
      ),
    );

    _exitDialogOpen = false;
    if (!mounted) return;

    switch (result) {
      case 'exit':
        await _saveWebPlayerCache();
        if (mounted) Navigator.of(context).pop();
        break;
      case 'server':
        if (widget.onChangeServer != null) {
          widget.onChangeServer!();
        } else {
          await _saveWebPlayerCache();
          if (mounted) Navigator.of(context).pop('change_server');
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_exitDialogOpen) return;
        _requestExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // WebView / error
            if (_error == null)
              WebViewWidget(controller: _controller)
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 48,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _error = null;
                            _loading = true;
                          });
                          _controller.loadRequest(
                            Uri.parse(widget.servidorUrl),
                          );
                        },
                        child: const Text(
                          'Reintentar',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Progreso fino (casi invisible)
            if (_loading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.transparent,
                  color: Colors.white.withValues(alpha: 0.35),
                  minHeight: 2,
                ),
              ),

            // Único control: botón atrás blur que se desvanece
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              left: 12,
              child: GestureDetector(
                onTap: () {
                  _wakeBackButton();
                  _requestExit();
                },
                child: AnimatedOpacity(
                  opacity: _backOpacity,
                  duration: _fadeStep,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Menú salida — monocromo, estilo TV
// ═══════════════════════════════════════════════════════════════════════════

class _ExitSheet extends StatelessWidget {
  final String title;
  final String servidor;
  final VoidCallback onContinue;
  final VoidCallback onExit;
  final VoidCallback onChangeServer;

  const _ExitSheet({
    required this.title,
    required this.servidor,
    required this.onContinue,
    required this.onExit,
    required this.onChangeServer,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0E0E10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title.isNotEmpty ? title : 'Reproductor',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (servidor.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                servidor,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 22),
            _row('Seguir viendo', Icons.play_arrow_rounded, onContinue),
            const SizedBox(height: 8),
            _row('Cambiar servidor', Icons.dns_outlined, onChangeServer),
            const SizedBox(height: 8),
            _row('Salir', Icons.close_rounded, onExit, dim: true),
          ],
        ),
      ),
    );
  }

  Widget _row(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool dim = false,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: dim ? 0.04 : 0.07),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: Colors.white.withValues(alpha: dim ? 0.45 : 0.9),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: dim ? 0.5 : 0.95),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}