// lib/player/servicio/extractor_hls.dart
//
// Extrae la fuente (m3u8/mp4) de un servidor SIN mostrar UI al usuario.
// Usa exactamente la misma lógica de detección que ExtractorPage
// (hook de fetch/XHR, hls.js, jwplayer, videojs, MutationObserver,
// scan de DOM y performance entries), pero corre en un WebView de 1x1
// invisible insertado en el Overlay más cercano, solo para "probar"
// si el servidor puede ser procesado.
//
// Se usa desde ServidoresModal para filtrar, antes de mostrarlos al
// usuario, los servidores (nativos, cuevana, unlimplay) que sí van
// a encontrar una fuente reproducible.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lol/data/webview/app_webview.dart';

class ExtractorHlsService {
  ExtractorHlsService._();

  /// Devuelve la URL absoluta de la fuente encontrada, o null si no
  /// se encontró nada dentro de [timeout]. Requiere un [context] montado
  /// (se usa solo para ubicar el Overlay más cercano).
  static Future<String?> buscarFuente(
    BuildContext context,
    String servidorUrl, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return Future.value(null);

    final completer = Completer<String?>();
    late OverlayEntry entry;
    var resuelto = false;

    void resolver(String? url) {
      if (resuelto) return;
      resuelto = true;
      try {
        entry.remove();
      } catch (_) {}
      if (!completer.isCompleted) completer.complete(url);
    }

    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -5,
        top: -5,
        width: 1,
        height: 1,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.0,
            child: _HiddenProbe(
              servidorUrl: servidorUrl,
              timeout: timeout,
              onResult: resolver,
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    return completer.future;
  }
}

class _HiddenProbe extends StatefulWidget {
  final String servidorUrl;
  final Duration timeout;
  final ValueChanged<String?> onResult;

  const _HiddenProbe({
    required this.servidorUrl,
    required this.timeout,
    required this.onResult,
  });

  @override
  State<_HiddenProbe> createState() => _HiddenProbeState();
}

class _HiddenProbeState extends State<_HiddenProbe> {
  late final WebViewController _controller;
  final Set<String> _detectadas = {};
  Timer? _timeoutTimer;
  bool _resuelto = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      )
      ..addJavaScriptChannel(
        'MediaDetector',
        onMessageReceived: (JavaScriptMessage message) {
          if (_resuelto) return;
          final url = message.message.trim();
          if (url.isNotEmpty && _isMediaUrl(url)) {
            _addDetectedUrl(url);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_resuelto) return;
            _injectPowerfulMediaDetector();
          },
          onNavigationRequest: (request) {
            if (_resuelto) return NavigationDecision.prevent;
            final uri = Uri.tryParse(request.url);
            final baseUri = Uri.tryParse(widget.servidorUrl);
            if (uri != null &&
                baseUri != null &&
                (uri.host == baseUri.host || uri.host.isEmpty)) {
              if (_isMediaUrl(request.url)) {
                _addDetectedUrl(request.url);
              }
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.servidorUrl));

    _timeoutTimer = Timer(widget.timeout, () {
      if (!_resuelto) _finalizar(null);
    });
  }

  bool _isMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.ts') ||
        lower.contains('.m4s') ||
        lower.contains('master.m3u8') ||
        lower.contains('playlist.m3u8') ||
        lower.contains('index.m3u8');
  }

  String _toAbsoluteUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.isAbsolute) return url;
      return Uri.parse(widget.servidorUrl).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  void _addDetectedUrl(String url) {
    if (_resuelto) return;
    final absoluteUrl = _toAbsoluteUrl(url);
    if (_detectadas.add(absoluteUrl)) {
      if (absoluteUrl.contains('.m3u8') || absoluteUrl.contains('.mp4')) {
        _finalizar(absoluteUrl);
      }
    }
  }

  void _finalizar(String? url) {
    if (_resuelto) return;
    _resuelto = true;
    _timeoutTimer?.cancel();
    _stopDetectionJs();
    widget.onResult(url);
  }

  void _stopDetectionJs() {
    try {
      _controller.runJavaScript('''
        (function() {
          if (window.__mdCleanup) { try { window.__mdCleanup(); } catch(e) {} }
          document.querySelectorAll('video').forEach(v => { try { v.pause(); } catch(e) {} });
        })();
      ''');
      _controller.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
  }

  void _injectPowerfulMediaDetector() {
    // Idéntica a ExtractorPage._injectPowerfulMediaDetector, para
    // garantizar que el filtrado detecta exactamente lo mismo que
    // detectaría el extractor visible.
    _controller.runJavaScript('''
      (function() {
        if (window.__mdCleanup) { try { window.__mdCleanup(); } catch(e) {} }
        let stopped = false;
        const urls = new Set();

        const sendUrl = (url) => {
          if (stopped || !url) return;
          try {
            const absUrl = new URL(url, location.href).href;
            if ((absUrl.includes('.m3u8') || absUrl.includes('.mp4') ||
                 absUrl.includes('.ts') || absUrl.includes('.m4s')) && !urls.has(absUrl)) {
              urls.add(absUrl);
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('MediaDetector', absUrl);
              }
            }
          } catch(e) { /* ignorar */ }
        };

        if (!window.__mdOrigFetch) window.__mdOrigFetch = window.fetch;
        if (!window.__mdOrigXhrOpen) window.__mdOrigXhrOpen = XMLHttpRequest.prototype.open;

        window.fetch = function(...args) {
          if (!stopped) {
            const input = args[0];
            const url = typeof input === 'string' ? input : (input?.url || '');
            if (url) sendUrl(url);
          }
          return window.__mdOrigFetch.apply(this, args);
        };

        try {
          XMLHttpRequest.prototype.open = function(method, url) {
            if (!stopped && url) sendUrl(url);
            window.__mdOrigXhrOpen.apply(this, arguments);
          };
        } catch(e) {}

        try {
          if (window.Hls && Hls.isSupported() && !window.__mdHlsWrapped) {
            window.__mdHlsWrapped = true;
            const OriginalHls = window.Hls;
            window.Hls = function(config) {
              const hls = new OriginalHls(config);
              hls.on(Hls.Events.MANIFEST_PARSED, (event, data) => {
                if (stopped) return;
                data.levels?.forEach(level => {
                  [level.url, ...(level.url || [])].flat().forEach(u => sendUrl(u));
                });
              });
              hls.on(Hls.Events.LEVEL_LOADED, (event, data) => {
                if (stopped) return;
                data.details?.fragments?.forEach(f => sendUrl(f.url));
              });
              return hls;
            };
          }
        } catch(e) {}

        const combinedCheck = () => {
          if (stopped) return;
          try {
            performance.getEntriesByType('resource').forEach(entry => {
              const url = entry.name;
              const type = entry.initiatorType;
              const ct = entry.contentType || '';
              if (
                ct.startsWith('video/') || ct.startsWith('audio/') ||
                ['video','audio','xmlhttprequest','other'].includes(type) ||
                url.includes('.m3u8') || url.includes('.mp4') ||
                url.includes('.ts') || url.includes('.m4s')
              ) { sendUrl(url); }
            });
          } catch(e) {}

          try {
            document.querySelectorAll('video, source, [src], [href], iframe').forEach(el => {
              const src = el.src || el.href || el.getAttribute('src') || el.getAttribute('href') || '';
              if (src) sendUrl(src);
            });
          } catch(e) {}
        };
        combinedCheck();
        const mdInterval = setInterval(combinedCheck, 3500);

        try {
          if (window.jwplayer) {
            const playlist = window.jwplayer().getPlaylist?.() || [];
            playlist.forEach(item => {
              if (item.file) sendUrl(item.file);
              if (item.sources) item.sources.forEach(s => s.file && sendUrl(s.file));
            });
          }
        } catch(e) {}

        try {
          if (window.videojs) {
            window.videojs.getAllPlayers?.().forEach(p => {
              const src = p.tech?.()?.currentSource_?.src;
              if (src) sendUrl(src);
            });
          }
        } catch(e) {}

        try {
          if (window._mutationObserver) { window._mutationObserver.disconnect(); }
          window._mutationObserver = new MutationObserver(() => {
            if (stopped) return;
            document.querySelectorAll('video, source').forEach(el => {
              if (el.src) sendUrl(el.src);
            });
          });
          window._mutationObserver.observe(document.body, { childList: true, subtree: true });
        } catch(e) {}

        window.__mdCleanup = function() {
          stopped = true;
          try { clearInterval(mdInterval); } catch(e) {}
          try {
            if (window._mutationObserver) {
              window._mutationObserver.disconnect();
              window._mutationObserver = null;
            }
          } catch(e) {}
          try { window.fetch = window.__mdOrigFetch; } catch(e) {}
          try { XMLHttpRequest.prototype.open = window.__mdOrigXhrOpen; } catch(e) {}
        };
      })();
    ''');
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    if (!_resuelto) _stopDetectionJs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 1,
      child: WebViewWidget(controller: _controller),
    );
  }
}
