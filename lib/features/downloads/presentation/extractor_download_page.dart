import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lol/data/webview/app_webview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'downloads_page.dart'; // ajusta la ruta
import 'download_manager.dart';
// Ajusta estas rutas a donde tengas los archivos
import '../../player/data/native_resolvers.dart'; // tu NativeResolvers (o el archivo donde esté)

/// Modelo simple de calidad HLS
class HlsQualityOption {
  final String url;
  final String label;
  final int? bandwidth;
  final int? width;
  final int? height;
  /// Tamaño aproximado en bytes (null si no se pudo estimar)
  final int? approxBytes;

  const HlsQualityOption({
    required this.url,
    required this.label,
    this.bandwidth,
    this.width,
    this.height,
    this.approxBytes,
  });

  /// Etiqueta legible del tamaño: "≈ 420 MB", "≈ 1.2 GB", etc.
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

class ExtractorDownloadPage extends StatefulWidget {
  final int idcontenido;
  final int? temporada;
  final int? capitulo;
  final String servidorUrl;
  final String servidorNombre;
  final String tipo;
  final String titulo;
  final int? idServidor;
  // NUEVO
  final int? tmdbId;
  final String? posterUrl;
  final String? backdropUrl;

  const ExtractorDownloadPage({
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
  });

  @override
  State<ExtractorDownloadPage> createState() => _ExtractorDownloadPageState();
}

class _ExtractorDownloadPageState extends State<ExtractorDownloadPage>
    with WidgetsBindingObserver {
  static const String _kHostCacheKey = 'extractor_host_methods';
  static const String _kMethodWebview = 'webview_media_detector';
  static const String _kMethodNative = 'native_resolver';

  late final String initialUrl;
  late final String _hostKey;
  late WebViewController _webViewController;

  final Set<String> detectedUrls = {};
  bool isSearching = true;
  String? selectedMediaUrl; // master o media playlist encontrado
  String? selectedQualityUrl; // URL final después de elegir calidad
  String? selectedQualityLabel;
  Timer? _searchTimer;
  bool _isClosing = false;
  bool _detectionStopped = false;
  bool _sendingToIdm = false;
  bool _hostKnown = false;
  String? _cachedMethod;
  bool _nativeTried = false;

  // ─── Calidades en pantalla (sin modal) ─────────────────────────────────
  List<HlsQualityOption> _qualities = [];
  bool _loadingQualities = false;
  bool _qualitiesLoaded = false;

  // Descarga directa
  final _dm = DownloadManager.instance;
  String? _activeDownloadId;
  bool _isDownloadingDirect = false;
  double _downloadProgress = 0.0;
  String? _downloadStatus;
  String? _etaLabel;

  static const _idmPackages = <String>[
    'idm.internet.download.manager',
    'idm.internet.download.manager.plus',
    'idm.internet.download.manager.adm.lite',
  ];

  @override
  void initState() {
    super.initState();
    initialUrl = widget.servidorUrl;
    _hostKey = _extractHost(initialUrl);
    WidgetsBinding.instance.addObserver(this);
    _dm.addListener(_onDmUpdate);
    _lockToPortrait();

    // ← Inicializa el controller YA (antes del primer build)
    _initWebView();

    // El caché solo se usa para el intento nativo temprano
    _loadHostCache().then((_) {
      if (_cachedMethod == _kMethodNative) {
        _tryNativeResolver(early: true);
      }
    });
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

    final result = await NativeResolvers.resolve(initialUrl);
    if (result != null && result.url.isNotEmpty && mounted && !_isClosing) {
      selectedMediaUrl = result.url;
      await _saveHostMethod(_kMethodNative);
      _onSourceFound();
    }
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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

  void _onDmUpdate() {
    if (!mounted || _activeDownloadId == null) return;
    final d = _dm.get(_activeDownloadId!);
    if (d == null) return;

    setState(() {
      _downloadProgress = d.progress;
      _downloadStatus = d.statusText;
      _etaLabel = d.etaLabel;
      _isDownloadingDirect =
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.queued;
    });

    if (d.status == DownloadStatus.completed && mounted) {
      _showTopAlert('Descarga completada. Véala en Descargas.');
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_isClosing) {
          _isClosing = true;
          _unlockOrientation();
          Navigator.pop(context);
        }
      });
    }
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

    // Cargar calidades en la misma pantalla (sin modal)
    _loadQualities();
  }

  // ─── Cargar calidades del master m3u8 ──────────────────────────────────
  Future<void> _loadQualities() async {
    final master = selectedMediaUrl;
    if (master == null || master.isEmpty) return;

    // Siempre dejamos una URL lista para descargar (aunque falle el parseo)
    void _fallbackOriginal() {
      if (!mounted || _isClosing) return;
      setState(() {
        selectedQualityUrl = master;
        selectedQualityLabel = 'Original';
        _qualities = [];
        _qualitiesLoaded = true;
        _loadingQualities = false;
      });
    }

    // Si no es m3u8 → sin calidades, usar la URL tal cual
    if (!master.toLowerCase().contains('.m3u8')) {
      _fallbackOriginal();
      return;
    }

    setState(() {
      _loadingQualities = true;
      _qualitiesLoaded = false;
      // Mientras carga, ya permitimos descargar con el master
      selectedQualityUrl ??= master;
      selectedQualityLabel ??= 'Original';
    });

    try {
      final list = await _parseHlsQualities(master);
      if (!mounted || _isClosing) return;

      if (list.isEmpty) {
        // Media playlist o sin variantes → descargar con el propio master
        _fallbackOriginal();
      } else {
        // Ordenar de mayor a menor resolución/bandwidth
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
        });
      }
    } catch (e) {
      debugPrint('Error cargando calidades: $e');
      // Si falla el parseo → igual se puede descargar con la URL original
      _fallbackOriginal();
    }
  }

  /// Parsea un master playlist y devuelve las variantes (con tamaño aprox).
  Future<List<HlsQualityOption>> _parseHlsQualities(String masterUrl) async {
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    };

    final response = await http
        .get(Uri.parse(masterUrl), headers: headers)
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final content = response.body;
    final baseUri = Uri.parse(masterUrl);
    final lines = content.split('\n');
    final raw = <({String url, int? bandwidth, int? width, int? height, String? name})>[];

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

    // Sin variantes → no es master (o está vacío)
    if (raw.isEmpty) return [];

    // Intentar obtener duración total del primer media playlist
    // (todas las variantes del mismo VOD suelen tener la misma duración)
    double? durationSec;
    try {
      durationSec = await _fetchPlaylistDuration(raw.first.url, headers);
    } catch (_) {}

    final result = <HlsQualityOption>[];
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

      // Tamaño aprox = bandwidth (bits/s) * duración (s) / 8
      int? approxBytes;
      if (v.bandwidth != null && durationSec != null && durationSec > 0) {
        approxBytes = ((v.bandwidth! * durationSec) / 8).round();
      }

      result.add(HlsQualityOption(
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

  /// Suma los #EXTINF de un media playlist → duración en segundos.
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

  void _selectQuality(HlsQualityOption q) {
    setState(() {
      selectedQualityUrl = q.url;
      selectedQualityLabel = q.label;
    });
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

  void _lockToPortrait() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _unlockOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

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
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('MediaDetector', absUrl);
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

  void _startPeriodicSearch() {
    _searchTimer?.cancel();
    final timeoutSec = _hostKnown ? 7 : 12;
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
    setState(() => isSearching = false);
    _showTopAlert('No se puede procesar la descarga');
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _unlockOrientation();
        Navigator.pop(context);
      }
    });
  }

  // ─── Alerta flotante superior 2 segundos ───────────────────────────────
  void _showTopAlert(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      entry.remove();
    });
  }

  String _buildSuggestedFileName() {
    final base = widget.titulo.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
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

  // ─── Acciones de descarga (ya no abren modal) ──────────────────────────
  Future<void> _onDirectDownload() async {
    final url = selectedQualityUrl ?? selectedMediaUrl;
    if (url == null || url.isEmpty) return;

    if (!url.toLowerCase().contains('.m3u8')) {
      _showTopAlert('La descarga directa solo soporta m3u8. Usa 1DM.');
      return;
    }
    await _startDirectDownload();
  }

  Future<void> _onIdmDownload() async {
    await _sendToIdm();
  }

  // ─── 1DM ───────────────────────────────────────────────────────────────
  Future<void> _sendToIdm() async {
    final url = selectedQualityUrl ?? selectedMediaUrl;
    if (url == null || url.isEmpty || _sendingToIdm) return;
    setState(() => _sendingToIdm = true);

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
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        _showTopAlert('No se pudo abrir 1DM. Enlace copiado al portapapeles.');
      }
    }
    if (mounted) setState(() => _sendingToIdm = false);
  }

  Future<void> _startDirectDownload() async {
    final url = selectedQualityUrl ?? selectedMediaUrl;
    if (url == null || url.isEmpty || _isDownloadingDirect) return;

    if (!url.toLowerCase().contains('.m3u8')) {
      _showTopAlert('La descarga directa solo soporta m3u8. Usa 1DM para mp4.');
      return;
    }

    try {
      setState(() {
        _isDownloadingDirect = true;
        _downloadProgress = 0;
        _downloadStatus = 'Preparando…';
        _etaLabel = 'Calculando…';
      });

      final id = await _dm.startHlsDownload(
        m3u8Url: url,
        titulo: widget.titulo,
        temporada: widget.temporada,
        capitulo: widget.capitulo,
        tmdbId: widget.tmdbId ?? widget.idcontenido,
        tipo: widget.tipo,
        posterUrl: widget.posterUrl,
        backdropUrl: widget.backdropUrl,
      );
      _activeDownloadId = id;

      // Ir a Descargas automáticamente
      if (!mounted) return;
      _isClosing = true;
      _detectionStopped = true;
      _searchTimer?.cancel();
      _stopDetectionJs();
      _unlockOrientation();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DescargasPage()),
        (route) =>
            route.isFirst, // o el criterio que uses para no romper el stack
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingDirect = false;
          _downloadStatus = null;
        });
        _showTopAlert('Error al iniciar descarga: $e');
      }
    }
  }

  void _cancelDirectDownload() {
    if (_activeDownloadId != null) {
      _dm.cancel(_activeDownloadId!);
    }
  }

  void _minimizeAndLeave() {
    _isClosing = true;
    _detectionStopped = true;
    _searchTimer?.cancel();
    _stopDetectionJs();
    _unlockOrientation();
    Navigator.pop(context);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _lockToPortrait();
  }

  @override
  void dispose() {
    _dm.removeListener(_onDmUpdate);
    WidgetsBinding.instance.removeObserver(this);
    _searchTimer?.cancel();
    _detectionStopped = true;
    _stopDetectionJs();
    try {
      _webViewController.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    if (!_isClosing) _unlockOrientation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = (widget.temporada != null && widget.capitulo != null)
        ? 'T${widget.temporada!.toString().padLeft(2, '0')}'
              'C${widget.capitulo!.toString().padLeft(2, '0')}'
        : widget.servidorNombre;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_isDownloadingDirect) {
              _minimizeAndLeave();
              return;
            }
            _isClosing = true;
            _detectionStopped = true;
            _searchTimer?.cancel();
            _stopDetectionJs();
            _unlockOrientation();
            Navigator.pop(context);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.titulo,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 1,
              height: 1,
              child: WebViewWidget(controller: _webViewController),
            ),
          ),
          if (isSearching)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 5,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Buscando fuente para descargar…',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ],
              ),
            ),
          if (!isSearching && selectedMediaUrl != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    const Icon(
                      Icons.download_for_offline_rounded,
                      color: Color(0xFF4CAF50),
                      size: 88,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Fuente lista',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.titulo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.temporada != null &&
                        widget.capitulo != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'T${widget.temporada!.toString().padLeft(2, '0')}'
                        'C${widget.capitulo!.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],

                    // ─── Sección de calidades en pantalla ─────────────────
                    if (_loadingQualities) ...[
                      const SizedBox(height: 24),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Cargando calidades…',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ] else if (_qualities.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const Text(
                        'Elige calidad',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: _qualities.map((q) {
                          final selected = selectedQualityUrl == q.url;
                          final size = q.sizeLabel;
                          return GestureDetector(
                            onTap: () => _selectQuality(q),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF4CAF50)
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF4CAF50)
                                      : Colors.white.withValues(alpha: 0.18),
                                  width: 1.2,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    q.label,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  if (size != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      size,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white.withValues(alpha: 0.85)
                                            : Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (selectedQualityLabel != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          () {
                            final sel = _qualities
                                .where((q) => q.url == selectedQualityUrl)
                                .toList();
                            final size = sel.isNotEmpty ? sel.first.sizeLabel : null;
                            return size != null
                                ? 'Seleccionada: $selectedQualityLabel  ·  $size'
                                : 'Seleccionada: $selectedQualityLabel';
                          }(),
                          style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ] else if (_qualitiesLoaded) ...[
                      // Sin variantes → se descarga con la URL original
                      const SizedBox(height: 12),
                      Text(
                        selectedQualityLabel != null
                            ? 'Calidad: $selectedQualityLabel'
                            : 'Sin variantes · se usará la fuente original',
                        style: const TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const Spacer(),
                    if (_isDownloadingDirect) ...[
                      Text(
                        _downloadStatus ?? 'Descargando…',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tiempo restante: ${_etaLabel ?? 'Calculando…'}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _downloadProgress > 0.02
                              ? _downloadProgress
                              : null,
                          backgroundColor: Colors.white12,
                          color: const Color(0xFF4CAF50),
                          minHeight: 7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _minimizeAndLeave,
                          icon: const Icon(Icons.minimize_rounded, size: 20),
                          label: const Text(
                            'Minimizar y seguir descargando',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _cancelDirectDownload,
                        child: const Text(
                          'Cancelar descarga',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      // Botón principal → descarga directa
                      // Habilitado aunque no haya calidades (usa master/original)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: selectedQualityUrl == null
                              ? null
                              : _onDirectDownload,
                          icon: const Icon(Icons.download_rounded, size: 26),
                          label: const Text(
                            'Descarga directa',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                const Color(0xFF4CAF50).withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 1DM — también funciona sin lista de calidades
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: (_sendingToIdm || selectedQualityUrl == null)
                              ? null
                              : _onIdmDownload,
                          icon: _sendingToIdm
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.open_in_new_rounded, size: 24),
                          label: Text(
                            _sendingToIdm
                                ? 'Abriendo 1DM…'
                                : 'Descargar con 1DM',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF1565C0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: () {
                          final url =
                              selectedQualityUrl ?? selectedMediaUrl;
                          if (url != null) {
                            Clipboard.setData(ClipboardData(text: url));
                            _showTopAlert('Enlace copiado al portapapeles');
                          }
                        },
                        child: const Text(
                          'Copiar enlace',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                    const Spacer(flex: 2),
                    Text(
                      'Servidor: ${widget.servidorNombre}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
