import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

import 'download_manager.dart';
import 'downloads_page_tv.dart';
import '../../player/data/native_resolvers.dart';

/// Modelo de calidad HLS (misma estructura que mobile).
class HlsQualityOptionTv {
  final String url;
  final String label;
  final int? bandwidth;
  final int? width;
  final int? height;
  final int? approxBytes;

  const HlsQualityOptionTv({
    required this.url,
    required this.label,
    this.bandwidth,
    this.width,
    this.height,
    this.approxBytes,
  });

  String? get sizeLabel {
    final b = approxBytes;
    if (b == null || b <= 0) return null;
    if (b >= 1073741824) {
      return '≈ ${(b / 1073741824).toStringAsFixed(1)} GB';
    }
    if (b >= 1048576) {
      return '≈ ${(b / 1048576).toStringAsFixed(0)} MB';
    }
    if (b >= 1024) {
      return '≈ ${(b / 1024).toStringAsFixed(0)} KB';
    }
    return '≈ $b B';
  }
}

/// Versión TV de ExtractorDownloadPage.
/// Misma lógica de detección que móvil + UI con foco D-pad.
///
/// Navegación de foco (D-pad):
///   Volver  → (→/↓) Calidades
///   Calidad → ←/→ cambia de calidad, OK la selecciona, ↓ Hilos, ↑ Volver
///   Hilos   → ←/→ resta/suma hilos (1-8), ↑ Calidades, ↓ Descargar
///   Descargar / Abrir enlace → ↑ Hilos, ←/→ entre ambos
class ExtractorDownloadPageTv extends StatefulWidget {
  final int idcontenido;
  final int? temporada;
  final int? capitulo;
  final String servidorUrl;
  final String servidorNombre;
  final String tipo;
  final String titulo;
  final int? idServidor;
  final int? tmdbId;
  final String? posterUrl;
  final String? backdropUrl;
  final Map<String, String>? headers;

  const ExtractorDownloadPageTv({
    super.key,
    required this.idcontenido,
    this.temporada,
    this.capitulo,
    required this.servidorUrl,
    required this.servidorNombre,
    required this.tipo,
    required this.titulo,
    this.idServidor,
    this.tmdbId,
    this.posterUrl,
    this.backdropUrl,
    this.headers,
  });

  @override
  State<ExtractorDownloadPageTv> createState() =>
      _ExtractorDownloadPageTvState();
}

class _ExtractorDownloadPageTvState extends State<ExtractorDownloadPageTv>
    with WidgetsBindingObserver {
  static const String _kHostCacheKey = 'extractor_host_methods';
  static const String _kMethodWebview = 'webview_media_detector';
  static const String _kMethodNative = 'native_resolver';
  static const _kAccent = Color(0xFFE50914);
  static const _kGreen = Color(0xFF4CAF50);

  late final String initialUrl;
  late final String _hostKey;
  late WebViewController _webViewController;

  final Set<String> detectedUrls = {};
  bool isSearching = true;
  bool _detectionStopped = false;
  bool _isClosing = false;
  bool _nativeTried = false;
  bool _hostKnown = false;
  String? _cachedMethod;

  String? selectedMediaUrl;
  String? selectedQualityUrl;
  String? selectedQualityLabel;
  List<HlsQualityOptionTv> _qualities = [];
  bool _qualitiesLoaded = false;
  bool _loadingQualities = false;
  String? _statusMessage;
  Timer? _searchTimer;
  final _dm = DownloadManager.instance;

  /// Hilos de descarga seleccionados (1-8)
  int _selectedConcurrency = 4;

  // Foco TV
  final FocusNode _backFocus = FocusNode(debugLabel: 'ext_tv_back');
  final FocusNode _downloadFocus = FocusNode(debugLabel: 'ext_tv_dl');
  final FocusNode _idmFocus = FocusNode(debugLabel: 'ext_tv_idm');
  final FocusNode _concurrencyFocus = FocusNode(debugLabel: 'ext_tv_threads');
  List<FocusNode> _qualityFocusNodes = [];

  static const _idmPackages = <String>[
    'idm.internet.download.manager',
    'idm.internet.download.manager.plus',
    'idm.internet.download.manager.adm.lite',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialUrl = widget.servidorUrl.trim();
    _hostKey = _extractHost(initialUrl);
    _selectedConcurrency = _dm.segmentConcurrency.clamp(1, 8);
    _initWebView();
    _loadHostCache().then((_) {
      if (_cachedMethod == _kMethodNative) {
        _tryNativeResolver(early: true);
      }
    });
    _dm.addListener(_onDmUpdate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchTimer?.cancel();
    _detectionStopped = true;
    _stopDetectionJs();
    _dm.removeListener(_onDmUpdate);
    _backFocus.dispose();
    _downloadFocus.dispose();
    _idmFocus.dispose();
    _concurrencyFocus.dispose();
    for (final n in _qualityFocusNodes) {
      n.dispose();
    }
    try {
      _webViewController.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    super.dispose();
  }

  void _onDmUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  // ─── Headers (igual que móvil) ─────────────────────────────────────────
  Map<String, String> _downloadHeaders([String? url]) {
    final u = (url ?? widget.servidorUrl).toLowerCase();
    final h = <String, String>{
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'accept': '*/*',
      'accept-language': 'es-ES,es;q=0.9,en;q=0.8',
    };
    if (widget.headers != null) {
      widget.headers!.forEach((k, v) {
        if (v.isNotEmpty) h[k.toLowerCase()] = v;
      });
    }
    if (u.contains('net27.cc') ||
        u.contains('hakunaymatata') ||
        u.contains('/bt/')) {
      h['referer'] = 'https://net27.cc/';
      h['origin'] = 'https://net27.cc';
    } else {
      try {
        final uri = Uri.parse(url ?? widget.servidorUrl);
        if (uri.hasScheme && uri.host.isNotEmpty) {
          final o = '${uri.scheme}://${uri.host}';
          h.putIfAbsent('referer', () => '$o/');
          h.putIfAbsent('origin', () => o);
        }
      } catch (_) {}
    }
    String canon(String k) {
      const map = {
        'user-agent': 'User-Agent',
        'referer': 'Referer',
        'origin': 'Origin',
        'accept': 'Accept',
        'accept-language': 'Accept-Language',
        'cookie': 'Cookie',
        'range': 'Range',
      };
      return map[k.toLowerCase()] ?? k;
    }

    return {for (final e in h.entries) canon(e.key): e.value};
  }

  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      var host = uri.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      return host;
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadHostCache() async {
    if (_hostKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kHostCacheKey);
      if (raw == null || raw.isEmpty) return;
      final map = Map<String, dynamic>.from(jsonDecode(raw));
      final entry = map[_hostKey];
      if (entry is Map) {
        _cachedMethod = entry['method']?.toString();
        _hostKnown = _cachedMethod != null && _cachedMethod!.isNotEmpty;
      }
    } catch (_) {}
  }

  Future<void> _saveHostMethod(String method) async {
    if (_hostKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kHostCacheKey);
      final map = raw != null && raw.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(raw))
          : <String, dynamic>{};
      map[_hostKey] = {
        'method': method,
        'servidor': widget.servidorNombre,
        'ts': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_kHostCacheKey, jsonEncode(map));
      _cachedMethod = method;
      _hostKnown = true;
    } catch (_) {}
  }

  Future<void> _tryNativeResolver({bool early = false}) async {
    if (_nativeTried || _isClosing || _detectionStopped) return;
    _nativeTried = true;

    try {
      final result = await NativeResolvers.resolve(initialUrl);
      if (result != null &&
          result.url.isNotEmpty &&
          mounted &&
          !_isClosing) {
        selectedMediaUrl = result.url;
        await _saveHostMethod(_kMethodNative);
        _onSourceFound();
      }
    } catch (e) {
      debugPrint('Native resolver TV: $e');
    }
  }

  // ─── WebView (misma lógica potente que móvil) ──────────────────────────
  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      )
      ..addJavaScriptChannel(
        'MediaDetector',
        onMessageReceived: (JavaScriptMessage message) {
          if (_detectionStopped || _isClosing) return;
          final url = message.message.trim();
          if (url.isNotEmpty && _isMediaUrl(url)) {
            _addDetectedUrl(url);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_detectionStopped || _isClosing) return;
            _injectPowerfulMediaDetector();
            _startPeriodicSearch();
          },
          onNavigationRequest: (request) {
            if (_detectionStopped || _isClosing) {
              return NavigationDecision.prevent;
            }
            final uri = Uri.tryParse(request.url);
            final baseUri = Uri.tryParse(initialUrl);
            if (uri == null || baseUri == null) {
              return NavigationDecision.prevent;
            }
            if (uri.host == baseUri.host || uri.host.isEmpty) {
              if (_isMediaUrl(request.url)) {
                _addDetectedUrl(request.url);
              }
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));
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
      return Uri.parse(initialUrl).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  void _addDetectedUrl(String url) {
    if (_isClosing || _detectionStopped) return;
    final absoluteUrl = _toAbsoluteUrl(url);
    if (detectedUrls.add(absoluteUrl)) {
      if (absoluteUrl.contains('.m3u8') ||
          (selectedMediaUrl == null && absoluteUrl.contains('.mp4'))) {
        selectedMediaUrl = absoluteUrl;
        _saveHostMethod(_kMethodWebview);
        _onSourceFound();
      }
    }
  }

  void _onSourceFound() {
    if (_detectionStopped || !mounted) return;
    _detectionStopped = true;
    _searchTimer?.cancel();
    _stopDetectionJs();
    setState(() => isSearching = false);
    _loadQualities();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _downloadFocus.requestFocus();
    });
  }

  // ─── Calidades (igual que móvil, con duración aprox.) ──────────────────
  Future<void> _loadQualities() async {
    final master = selectedMediaUrl;
    if (master == null || master.isEmpty) return;

    void fallbackOriginal() {
      if (!mounted || _isClosing) return;
      setState(() {
        selectedQualityUrl = master;
        selectedQualityLabel = 'Original';
        _qualities = [
          HlsQualityOptionTv(url: master, label: 'Original'),
        ];
        _qualitiesLoaded = true;
        _loadingQualities = false;
        _resyncQualityFocus();
      });
    }

    if (!master.toLowerCase().contains('.m3u8')) {
      fallbackOriginal();
      return;
    }

    setState(() {
      _loadingQualities = true;
      _qualitiesLoaded = false;
      selectedQualityUrl ??= master;
      selectedQualityLabel ??= 'Original';
    });

    try {
      final list = await _parseHlsQualities(master);
      if (!mounted || _isClosing) return;

      if (list.isEmpty) {
        fallbackOriginal();
      } else {
        list.sort((a, b) {
          final ha = a.height ?? 0;
          final hb = b.height ?? 0;
          if (ha != hb) return hb.compareTo(ha);
          return (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0);
        });
        final best = list.first;
        setState(() {
          _qualities = list;
          selectedQualityUrl = best.url;
          selectedQualityLabel = best.label;
          _qualitiesLoaded = true;
          _loadingQualities = false;
          _resyncQualityFocus();
        });
      }
    } catch (e) {
      debugPrint('Error cargando calidades TV: $e');
      fallbackOriginal();
    }
  }

  void _resyncQualityFocus() {
    for (final n in _qualityFocusNodes) {
      n.dispose();
    }
    _qualityFocusNodes =
        List.generate(_qualities.length, (i) => FocusNode(debugLabel: 'q_$i'));
  }

  Future<List<HlsQualityOptionTv>> _parseHlsQualities(String masterUrl) async {
    final headers = _downloadHeaders(masterUrl);
    final response = await http
        .get(Uri.parse(masterUrl), headers: headers)
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final content = response.body;
    final baseUri = Uri.parse(masterUrl);
    final lines = content.split('\n');
    final raw =
        <({String url, int? bandwidth, int? width, int? height, String? name})>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

      int? bandwidth;
      int? width;
      int? height;
      String? nameAttr;

      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      if (bwMatch != null) bandwidth = int.tryParse(bwMatch.group(1)!);

      final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      if (resMatch != null) {
        width = int.tryParse(resMatch.group(1)!);
        height = int.tryParse(resMatch.group(2)!);
      }

      final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);
      if (nameMatch != null) nameAttr = nameMatch.group(1);

      String? variantUrl;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) continue;
        variantUrl = baseUri.resolve(next).toString();
        break;
      }
      if (variantUrl == null || variantUrl.isEmpty) continue;

      raw.add((
        url: variantUrl,
        bandwidth: bandwidth,
        width: width,
        height: height,
        name: nameAttr,
      ));
    }

    if (raw.isEmpty) return [];

    double? durationSec;
    try {
      durationSec = await _fetchPlaylistDuration(raw.first.url, headers);
    } catch (_) {}

    final result = <HlsQualityOptionTv>[];
    for (final v in raw) {
      String label;
      if (v.name != null && v.name!.isNotEmpty) {
        label = v.name!;
      } else if (v.height != null) {
        label = '${v.height}p';
      } else if (v.bandwidth != null) {
        final kbps = (v.bandwidth! / 1000).round();
        label = kbps >= 1000
            ? '${(kbps / 1000).toStringAsFixed(1)} Mbps'
            : '$kbps kbps';
      } else {
        label = 'Calidad ${result.length + 1}';
      }

      int? approxBytes;
      if (v.bandwidth != null && durationSec != null && durationSec > 0) {
        approxBytes = ((v.bandwidth! * durationSec) / 8).round();
      }

      result.add(HlsQualityOptionTv(
        url: v.url,
        label: label,
        bandwidth: v.bandwidth,
        width: v.width,
        height: v.height,
        approxBytes: approxBytes,
      ));
    }
    return result;
  }

  Future<double?> _fetchPlaylistDuration(
    String mediaUrl,
    Map<String, String> headers,
  ) async {
    final response = await http
        .get(Uri.parse(mediaUrl), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    double total = 0;
    final re = RegExp(r'#EXTINF:([\d.]+)');
    for (final m in re.allMatches(response.body)) {
      final d = double.tryParse(m.group(1)!);
      if (d != null) total += d;
    }
    return total > 0 ? total : null;
  }

  // ─── Detector JS potente (igual que móvil) ─────────────────────────────
  void _injectPowerfulMediaDetector() {
    final aggressive = _hostKnown && _cachedMethod == _kMethodWebview;
    final intervalMs = aggressive ? 1800 : 3500;

    _webViewController.runJavaScript('''
      (function() {
        if (window.__mdCleanup) {
          try { window.__mdCleanup(); } catch(e) {}
        }
        let stopped = false;
        const urls = new Set();
        const sendUrl = (url) => {
          if (stopped || !url) return;
          try {
            const absUrl = new URL(url, location.href).href;
            if ((absUrl.includes('.m3u8') || absUrl.includes('.mp4') ||
                 absUrl.includes('.ts') || absUrl.includes('.m4s')) && !urls.has(absUrl)) {
              urls.add(absUrl);
              if (window.MediaDetector && window.MediaDetector.postMessage) {
                window.MediaDetector.postMessage(absUrl);
              }
            }
          } catch(e) {}
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
        const mdInterval = setInterval(combinedCheck, $intervalMs);
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
          if (window._mutationObserver) window._mutationObserver.disconnect();
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

  void _stopDetectionJs() {
    try {
      _webViewController.runJavaScript('''
        (function() {
          if (window.__mdCleanup) {
            try { window.__mdCleanup(); } catch(e) {}
          }
          document.querySelectorAll('video').forEach(v => {
            try { v.pause(); } catch(e) {}
          });
        })();
      ''');
    } catch (_) {}
  }

  void _startPeriodicSearch() {
    _searchTimer?.cancel();
    final timeoutSec = _hostKnown ? 7 : 15;
    _searchTimer = Timer(Duration(seconds: timeoutSec), () {
      if (!mounted ||
          selectedMediaUrl != null ||
          _isClosing ||
          _detectionStopped) {
        return;
      }
      _tryNativeResolver().then((_) {
        if (mounted &&
            selectedMediaUrl == null &&
            !_isClosing &&
            !_detectionStopped) {
          _detectionStopped = true;
          _searchTimer?.cancel();
          _stopDetectionJs();
          _failAndPop();
        }
      });
    });
  }

  void _failAndPop() {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    setState(() {
      isSearching = false;
      _statusMessage = 'No se encontró fuente descargable';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _selectQuality(HlsQualityOptionTv q) {
    setState(() {
      selectedQualityUrl = q.url;
      selectedQualityLabel = q.label;
    });
  }

  // ─── Descarga ──────────────────────────────────────────────────────────
  Future<void> _onDirectDownload() async {
    final url = selectedQualityUrl ?? selectedMediaUrl;
    if (url == null || url.isEmpty) return;

    if (!url.toLowerCase().contains('.m3u8')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La descarga directa solo soporta m3u8. Usa “Abrir enlace”.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      // Aplicar hilos seleccionados ANTES de iniciar
      await _dm.setSegmentConcurrency(_selectedConcurrency);

      // Marcar cierre ANTES de navegar para no cortar detección/descarga
      _isClosing = true;
      _detectionStopped = true;
      _searchTimer?.cancel();
      _stopDetectionJs();

      await _dm.startHlsDownload(
        m3u8Url: url,
        headers: _downloadHeaders(url),
        titulo: widget.titulo,
        temporada: widget.temporada,
        capitulo: widget.capitulo,
        tmdbId: widget.tmdbId ?? widget.idcontenido,
        tipo: widget.tipo,
        posterUrl: widget.posterUrl,
        backdropUrl: widget.backdropUrl,
      );

      if (!mounted) return;

      // Igual que móvil: ir a la página de descargas para que continúe
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DescargasPageTv()),
        (route) => route.isFirst,
      );
    } catch (e) {
      _isClosing = false;
      _detectionStopped = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar descarga: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onIdmDownload() async {
    final url = selectedQualityUrl ?? selectedMediaUrl;
    if (url == null || url.isEmpty) return;

    final fileName = _buildSuggestedFileName();
    bool launched = false;

    if (Platform.isAndroid) {
      for (final pkg in _idmPackages) {
        try {
          final intent = AndroidIntent(
            action: 'android.intent.action.VIEW',
            data: url,
            package: pkg,
            componentName: 'idm.internet.download.manager.Downloader',
            arguments: <String, dynamic>{'extra_filename': fileName},
            flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
          );
          await intent.launch();
          launched = true;
          break;
        } catch (e) {
          debugPrint('1DM launch failed for $pkg: $e');
        }
      }
      if (!launched) {
        final safeTitle = Uri.encodeComponent(fileName);
        for (final pkg in _idmPackages) {
          try {
            final intentUri = Uri.parse(
              'intent:$url#Intent;package=$pkg;scheme=idmdownload;S.title=$safeTitle;end',
            );
            launched = await launchUrl(
              intentUri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) break;
          } catch (e) {
            debugPrint('1DM scheme launch failed for $pkg: $e');
          }
        }
      }
    }

    if (!launched) {
      try {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launched = true;
        }
      } catch (_) {}
    }

    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir 1DM. Enlace copiado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _buildSuggestedFileName() {
    final base =
        widget.titulo.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    String name = base.isEmpty ? 'video' : base;
    if (widget.temporada != null && widget.capitulo != null) {
      final t = widget.temporada!.toString().padLeft(2, '0');
      final c = widget.capitulo!.toString().padLeft(2, '0');
      name = '${name}_T${t}C$c';
    }
    final url = selectedQualityUrl ?? selectedMediaUrl ?? '';
    if (url.contains('.m3u8')) return '$name.mp4';
    if (url.toLowerCase().contains('.mp4')) return '$name.mp4';
    return name;
  }

  void _goBack() {
    if (_isClosing) return;
    _isClosing = true;
    _detectionStopped = true;
    _searchTimer?.cancel();
    _stopDetectionJs();
    Navigator.of(context).pop();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      _goBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── Navegación de foco ────────────────────────────────────────────────
  void _focusQualities() {
    if (_qualityFocusNodes.isEmpty) {
      _concurrencyFocus.requestFocus();
      return;
    }
    // Ir a la calidad seleccionada (si existe), si no a la primera.
    var idx = _qualities.indexWhere((q) => q.url == selectedQualityUrl);
    if (idx < 0 || idx >= _qualityFocusNodes.length) idx = 0;
    _qualityFocusNodes[idx].requestFocus();
  }

  void _changeThreads(int delta) {
    final next = (_selectedConcurrency + delta).clamp(1, 8);
    if (next != _selectedConcurrency) {
      setState(() => _selectedConcurrency = next);
    }
  }

  // ─── UI ────────────────────────────────────────────────────────────────
  Widget _buildHeader(String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(
        children: [
          Focus(
            focusNode: _backFocus,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter) {
                _goBack();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowRight ||
                  key == LogicalKeyboardKey.arrowDown) {
                if (_qualityFocusNodes.isNotEmpty) {
                  _focusQualities();
                } else {
                  _concurrencyFocus.requestFocus();
                }
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (ctx) {
                final hasFocus = Focus.of(ctx).hasFocus;
                return GestureDetector(
                  onTap: _goBack,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: hasFocus
                          ? Colors.white.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: hasFocus ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityChip(int i) {
    final q = _qualities[i];
    final selected = q.url == selectedQualityUrl;
    return Focus(
      focusNode: _qualityFocusNodes[i],
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _selectQuality(q);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          if (i < _qualityFocusNodes.length - 1) {
            _qualityFocusNodes[i + 1].requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (i > 0) {
            _qualityFocusNodes[i - 1].requestFocus();
          } else {
            _backFocus.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _concurrencyFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _backFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: () => _selectQuality(q),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? _kAccent.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : (selected ? _kAccent : Colors.transparent),
                  width: hasFocus ? 2 : 1.3,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    q.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: selected || hasFocus
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  if (q.sizeLabel != null)
                    Text(
                      q.sizeLabel!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
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

  /// Selector de hilos SIN Slider (el Slider roba el foco y atrapa el D-pad).
  /// ←/→ restan/suman, ↑ sube a calidades, ↓ baja a Descargar.
  Widget _buildThreadsSelector() {
    return Focus(
      focusNode: _concurrencyFocus,
      onKeyEvent: (node, event) {
        // Permitir mantener presionado para subir/bajar rápido
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowRight) {
          _changeThreads(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          _changeThreads(-1);
          return KeyEventResult.handled;
        }
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (key == LogicalKeyboardKey.arrowDown) {
          _downloadFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (_qualityFocusNodes.isNotEmpty) {
            _focusQualities();
          } else {
            _backFocus.requestFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: () {},
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: hasFocus
                    ? _kAccent.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    color: hasFocus ? Colors.white : Colors.white24,
                    size: 22,
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '$_selectedConcurrency',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hasFocus ? _kAccent : Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Barra segmentada 1-8 (solo visual, no enfocable)
                  ...List.generate(8, (i) {
                    final on = i < _selectedConcurrency;
                    return Container(
                      width: 22,
                      height: 8,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: on ? _kAccent : Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: hasFocus ? Colors.white : Colors.white24,
                    size: 22,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReady() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: _kGreen, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Fuente lista',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_loadingQualities) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kGreen,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Cargando calidades…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Calidad',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (_qualitiesLoaded)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: List.generate(_qualities.length, _buildQualityChip),
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Hilos de descarga',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '← → para cambiar · más hilos = más rápido',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildThreadsSelector(),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _TvActionButton(
                  focusNode: _downloadFocus,
                  label: 'Descargar',
                  icon: Icons.download_rounded,
                  primary: true,
                  onTap: _onDirectDownload,
                  onUp: () => _concurrencyFocus.requestFocus(),
                  onRight: () => _idmFocus.requestFocus(),
                  onLeft: null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TvActionButton(
                  focusNode: _idmFocus,
                  label: 'Abrir enlace',
                  icon: Icons.open_in_new_rounded,
                  primary: false,
                  onTap: _onIdmDownload,
                  onUp: () => _concurrencyFocus.requestFocus(),
                  onLeft: () => _downloadFocus.requestFocus(),
                  onRight: null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = (widget.temporada != null && widget.capitulo != null)
        ? 'T${widget.temporada!.toString().padLeft(2, '0')} '
            'C${widget.capitulo!.toString().padLeft(2, '0')} · ${widget.servidorNombre}'
        : widget.servidorNombre;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Focus(
          onKeyEvent: (n, e) => _handleKey(n, e),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(subtitle),

                // WebView oculto para detección
                Offstage(
                  offstage: true,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: WebViewWidget(controller: _webViewController),
                  ),
                ),

                Expanded(
                  child: isSearching
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  color: _kAccent,
                                  strokeWidth: 3,
                                ),
                              ),
                              SizedBox(height: 14),
                              Text(
                                'Buscando fuente para descargar…',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : selectedMediaUrl == null
                          ? Center(
                              child: Text(
                                _statusMessage ??
                                    'No se encontró fuente descargable',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : _buildReady(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvActionButton extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _TvActionButton({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
    this.onUp,
    this.onLeft,
    this.onRight,
  });

  static const _kAccent = Color(0xFFE50914);

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp && onUp != null) {
          onUp!();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft && onLeft != null) {
          onLeft!();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight && onRight != null) {
          onRight!();
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
              duration: const Duration(milliseconds: 140),
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primary
                    ? (hasFocus ? _kAccent : _kAccent.withValues(alpha: 0.85))
                    : (hasFocus
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: hasFocus ? FontWeight.w700 : FontWeight.w600,
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