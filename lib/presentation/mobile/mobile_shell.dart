import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/home/presentation/home_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/favorites/presentation/favorites_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/discover/domain/mobile/pag.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/content/presentation/content_page.dart';
import '../../features/downloads/presentation/downloads_page.dart';
import '../shared/modals/playback_setup_modal.dart';
import '../../core/constants/versiones.dart'; // ← VersionService

const _kAccentColor = Color(0xFFE50914);

/// Notifica cambios de visibilidad del tab Descargas.
class DownloadNavBus {
  DownloadNavBus._();
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static void bump() => version.value++;
}

class MainHome extends StatefulWidget {
  const MainHome({super.key});

  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> with WidgetsBindingObserver {
  /// 0 Home | 1 Guardados | 2 Descargas | 3 Servicios | 4 Config | 5 Buscar
  int _currentIndex = 0;

  final GlobalKey _homeKey = GlobalKey();
  final GlobalKey _guardadosKey = GlobalKey();
  final GlobalKey _descargasKey = GlobalKey();
  final GlobalKey _serviciosKey = GlobalKey();

  bool _homeLoaded = true;
  bool _guardadosLoaded = false;
  bool _descargasLoaded = false;
  bool _serviciosLoaded = false;

  Map<String, dynamic>? _continueItem;
  bool _continueDismissed = false;

  bool _enableDownloads = true;
  bool _showDownloadButtonMain = true;

  // ── Actualización ──────────────────────────────────────────────────────
  bool _updateAvailable = false;
  bool _updateBannerDismissed = false;
  String? _downloadUrl;
  String? _updateMessage;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;

  /// URLs por arquitectura (VersionService / API)
  String? _urlArm64;
  String? _urlArmeabi;
  String? _urlX86;
  String? _urlUniversal;

  /// Preferencia guardada: arm64 | armeabi | x86 | universal
  String? _preferredAbi;

  static const _prefAbiKey = 'apk_preferred_abi';

  bool get _showDescargasTab =>
      _enableDownloads && _showDownloadButtonMain;

  bool get _showUpdateBanner =>
      _updateAvailable && !_updateBannerDismissed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GuardadosBus.version.addListener(_onContinueBus);
    DownloadNavBus.version.addListener(_onDownloadNavBus);
    _loadContinueItem();
    _loadDownloadNavSettings();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapOfflineOrSetup();
      _checkForUpdate();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LÓGICA DE ACTUALIZACIÓN (VersionService + modal arquitectura)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _checkForUpdate() async {
    try {
      final status = await VersionService.checkForUpdate();

      if (!mounted) return;

      if (status.requiresUpdate && status.latestVersion != null) {
        final v = status.latestVersion!;
        final prefs = await SharedPreferences.getInstance();
        final savedAbi = prefs.getString(_prefAbiKey);

        setState(() {
          _updateAvailable = true;
          // Campos nuevos de arquitectura (ajusta nombres si tu modelo difiere)
          _urlArm64 = _readUrl(v, 'urlApkArm64', 'url_apk_arm64');
          _urlArmeabi = _readUrl(v, 'urlApkArmeabi', 'url_apk_armeabi');
          _urlX86 = _readUrl(v, 'urlApkX86', 'url_apk_x86');
          _urlUniversal = _readUrl(v, 'urlApkUniversal', 'url_apk_universal') ??
              (v.urlApk.trim().isNotEmpty ? v.urlApk : null);
          _downloadUrl = v.urlApk;
          _preferredAbi = savedAbi;
          _updateMessage =
              '${v.versionAceptada} • ${v.novedades.isNotEmpty ? v.novedades : status.message}';
          _updateBannerDismissed = false;
        });
      }
    } catch (_) {
      // Silencioso
    }
  }

  /// Lee URL desde el modelo aunque use camelCase o snake_case / dynamic.
  String? _readUrl(dynamic v, String camel, String snake) {
    try {
      if (v is Map) {
        final a = v[camel]?.toString();
        final b = v[snake]?.toString();
        final s = (a != null && a.isNotEmpty) ? a : b;
        return (s != null && s.trim().isNotEmpty) ? s.trim() : null;
      }
      // Intentar getters del objeto AppVersion
      final dynamic obj = v;
      String? val;
      try {
        switch (camel) {
          case 'urlApkArm64':
            val = obj.urlApkArm64?.toString();
            break;
          case 'urlApkArmeabi':
            val = obj.urlApkArmeabi?.toString();
            break;
          case 'urlApkX86':
            val = obj.urlApkX86?.toString();
            break;
          case 'urlApkUniversal':
            val = obj.urlApkUniversal?.toString();
            break;
        }
      } catch (_) {}
      if (val != null && val.trim().isNotEmpty) return val.trim();
    } catch (_) {}
    return null;
  }

  void _dismissUpdateBanner() {
    setState(() => _updateBannerDismissed = true);
  }

  String? _urlForAbi(String abi) {
    switch (abi) {
      case 'arm64':
        return (_urlArm64 != null && _urlArm64!.trim().isNotEmpty)
            ? _urlArm64!.trim()
            : null;
      case 'armeabi':
        return (_urlArmeabi != null && _urlArmeabi!.trim().isNotEmpty)
            ? _urlArmeabi!.trim()
            : null;
      case 'x86':
        return (_urlX86 != null && _urlX86!.trim().isNotEmpty)
            ? _urlX86!.trim()
            : null;
      case 'universal':
        if (_urlUniversal != null && _urlUniversal!.trim().isNotEmpty) {
          return _urlUniversal!.trim();
        }
        if (_downloadUrl != null && _downloadUrl!.trim().isNotEmpty) {
          return _downloadUrl!.trim();
        }
        return null;
      default:
        return null;
    }
  }

  String _labelAbi(String abi) {
    switch (abi) {
      case 'arm64':
        return 'ARM64';
      case 'armeabi':
        return 'ARMv7';
      case 'x86':
        return 'x86';
      case 'universal':
        return 'Universal';
      default:
        return abi;
    }
  }

  /// Tap en "Descargar" → modal de arquitectura → descarga.
  Future<void> _onTapDownload() async {
    if (_downloading) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final options = <Map<String, String>>[
          {
            'id': 'arm64',
            'title': 'ARM64 (arm64-v8a)',
            'subtitle': 'Mayoría de móviles modernos',
          },
          {
            'id': 'armeabi',
            'title': 'ARMv7 (armeabi-v7a)',
            'subtitle': 'Móviles más antiguos',
          },
          {
            'id': 'x86',
            'title': 'x86 / x86_64',
            'subtitle': 'Emuladores y algunos tablets',
          },
          {
            'id': 'universal',
            'title': 'Universal (todas)',
            'subtitle': 'Más pesada · compatible con todo',
          },
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Elige arquitectura del APK',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _preferredAbi != null
                      ? 'Última usada: ${_labelAbi(_preferredAbi!)}'
                      : 'Se recordará tu elección',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map((o) {
                  final id = o['id']!;
                  final hasUrl = _urlForAbi(id) != null;
                  final isPreferred = _preferredAbi == id;
                  return ListTile(
                    enabled: hasUrl,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isPreferred
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isPreferred
                          ? _kAccentColor
                          : (hasUrl ? Colors.white54 : Colors.white24),
                    ),
                    title: Text(
                      o['title']!,
                      style: TextStyle(
                        color: hasUrl ? Colors.white : Colors.white38,
                        fontWeight:
                            isPreferred ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      hasUrl
                          ? o['subtitle']!
                          : 'No disponible en esta versión',
                      style: TextStyle(
                        color: hasUrl
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.white24,
                        fontSize: 12,
                      ),
                    ),
                    trailing: isPreferred
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _kAccentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Anterior',
                              style: TextStyle(
                                color: _kAccentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : null,
                    onTap: hasUrl ? () => Navigator.pop(ctx, id) : null,
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;

    final url = _urlForAbi(selected);
    if (url == null || url.isEmpty) {
      setState(
        () => _downloadError = 'URL no disponible para esa arquitectura',
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAbiKey, selected);

    setState(() {
      _preferredAbi = selected;
      _downloadUrl = url;
      _downloadError = null;
    });

    await _downloadAndInstallApk();
  }

  Future<void> _downloadAndInstallApk() async {
    final url = _downloadUrl?.trim();
    if (url == null || url.isEmpty) {
      setState(() => _downloadError = 'No hay enlace de descarga');
      return;
    }

    if (!Platform.isAndroid) {
      await _openUrlFallback(url);
      return;
    }

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadError = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/lol_update.apk';
      final file = File(filePath);
      if (await file.exists()) await file.delete();

      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (!mounted) return;

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && mounted) {
        setState(() {
          _downloadError = result.message.isNotEmpty
              ? result.message
              : 'Activa “Instalar apps desconocidas” para esta app e inténtalo de nuevo.';
        });
      }
    } catch (e) {
      debugPrint('Error descarga APK: $e');
      if (mounted) {
        setState(() => _downloadError = 'Error al descargar: $e');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openUrlFallback(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error abriendo enlace: $e');
    }
  }

  // ── Resto de lógica ─────────────────────────────────────────────────────

  void _onDownloadNavBus() {
    if (!mounted) return;
    _loadDownloadNavSettings();
  }

  Future<void> _loadDownloadNavSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final enable = prefs.getBool('enable_downloads') ?? true;
      final showBtn = prefs.getBool('show_download_button_main') ?? true;

      setState(() {
        _enableDownloads = enable;
        _showDownloadButtonMain = showBtn;
      });

      if (!(enable && showBtn) && _currentIndex == 2) {
        _selectTab(0);
      }
    } catch (_) {}
  }

  Future<void> _bootstrapOfflineOrSetup() async {
    if (!mounted) return;

    await _loadDownloadNavSettings();
    if (!mounted) return;

    final online = await _hasConnection();
    if (!mounted) return;

    if (!online) {
      if (_showDescargasTab) _goToDescargas();
      return;
    }

    await _maybeShowPlaybackSetup();
  }

  Future<bool> _hasConnection() async {
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _goToDescargas() {
    if (!_showDescargasTab) return;
    setState(() {
      _currentIndex = 2;
      _descargasLoaded = true;
      _homeLoaded = false;
    });
  }

  Future<void> _maybeShowPlaybackSetup() async {
    if (!mounted) return;

    final alreadySetup = await hasPlaybackSetup();
    if (!mounted) return;
    if (alreadySetup) return;
    if (!_isCurrentRoute) return;

    final saved = await showPlaybackSetupModal(context);
    if (!mounted) return;
    if (saved) _loadContinueItem();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _forcePortraitIfCurrent();
  }

  @override
  void dispose() {
    GuardadosBus.version.removeListener(_onContinueBus);
    DownloadNavBus.version.removeListener(_onDownloadNavBus);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onContinueBus() {
    if (!mounted) return;
    _continueDismissed = false;
    _loadContinueItem();
  }

  Future<void> _loadContinueItem() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith('cachePlayer_'))
          .toList();

      Map<String, dynamic>? best;
      String bestTs = '';

      for (final key in keys) {
        try {
          final raw = prefs.getString(key);
          if (raw == null) continue;
          final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          final segundo = data['segundo'] as int? ?? 0;
          if (segundo < 8) continue;
          final ts = data['timestamp']?.toString() ?? '';
          if (best == null || ts.compareTo(bestTs) > 0) {
            best = data;
            bestTs = ts;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _continueItem = best);
    } catch (_) {
      if (mounted) setState(() => _continueItem = null);
    }
  }

  bool get _showContinueCard =>
      !_continueDismissed && _continueItem != null && _currentIndex == 0;

  void _dismissContinue() {
    setState(() => _continueDismissed = true);
  }

  void _openContinuePlayer() {
    final item = _continueItem;
    if (item == null) return;

    final id = item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;

    final temporada = item['temporada'] as int?;
    final capitulo = item['capitulo'] as int?;
    final tipo = (item['tipo'] ?? 'movie').toString().toLowerCase();
    final titulo = item['titulo']?.toString() ?? '';
    final videoUrl = item['videoUrl']?.toString() ?? '';
    final idioma = item['idioma']?.toString();

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              videoUrl: videoUrl,
              idcontenido: id,
              tmdbId: id,
              temporada: temporada,
              capitulo: capitulo,
              tipo: tipo,
              titulo: titulo,
              idioma: idioma,
            ),
          ),
        )
        .then((_) {
          _continueDismissed = false;
          _loadContinueItem();
        });
  }

  bool get _isCurrentRoute {
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  void _forcePortraitIfCurrent() {
    if (!_isCurrentRoute) return;
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _forcePortraitIfCurrent();
      _loadContinueItem();
      _loadDownloadNavSettings();
      // Opcional: _checkForUpdate();
    }
  }

  @override
  void didChangeMetrics() {
    _forcePortraitIfCurrent();
  }

  void _selectTab(int index) {
    if (index == 2 && !_showDescargasTab) return;

    _forcePortraitIfCurrent();

    if (_currentIndex == 4 && index != 4) {
      _loadDownloadNavSettings();
    }

    if (index == 0) {
      _homeLoaded = true;
      _loadContinueItem();
    } else if (index == 1) {
      _guardadosLoaded = true;
    } else if (index == 2) {
      _descargasLoaded = true;
    } else if (index == 3) {
      _serviciosLoaded = true;
    }

    if (_currentIndex == 0 && index != 0) {
      _homeLoaded = false;
    } else if (_currentIndex == 1 && index != 1) {
      _guardadosLoaded = false;
    } else if (_currentIndex == 2 && index != 2) {
      _descargasLoaded = false;
    } else if (_currentIndex == 3 && index != 3) {
      _serviciosLoaded = false;
    }

    setState(() => _currentIndex = index);
  }

  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Salir de la app',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          '¿Seguro que quieres cerrar la aplicación?',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return _homeLoaded ? HomePage(key: _homeKey) : const SizedBox.shrink();
      case 1:
        return _guardadosLoaded
            ? GuardadosPage(key: _guardadosKey)
            : const SizedBox.shrink();
      case 2:
        return _descargasLoaded
            ? DescargasPage(key: _descargasKey)
            : const SizedBox.shrink();
      case 3:
        return _serviciosLoaded
            ? ServiciosPage(key: _serviciosKey)
            : const SizedBox.shrink();
      case 4:
        return const ConfigPage(key: ValueKey('configPage'));
      case 5:
        return const BuscarPage(key: ValueKey('buscarPage'));
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Banner de actualización ─────────────────────────────────────────────

  Widget _buildUpdateBanner() {
    final pct = (_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kAccentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: _kAccentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Actualización disponible',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _updateMessage ??
                                'Hay una nueva versión · v${VersionService.currentVersionName} (${VersionService.currentVersionCode})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                          if (_preferredAbi != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'APK: ${_labelAbi(_preferredAbi!)}',
                              style: TextStyle(
                                color: _kAccentColor.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!_downloading)
                      TextButton(
                        onPressed: _onTapDownload,
                        style: TextButton.styleFrom(
                          foregroundColor: _kAccentColor,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Descargar',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                value: _downloadProgress > 0.02
                                    ? _downloadProgress
                                    : null,
                                strokeWidth: 2,
                                color: _kAccentColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$pct%',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    IconButton(
                      onPressed: _dismissUpdateBanner,
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
                if (_downloadError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _downloadError!,
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 11,
                    ),
                  ),
                ],
                if (_downloading) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value:
                          _downloadProgress > 0.02 ? _downloadProgress : null,
                      backgroundColor: Colors.white12,
                      color: _kAccentColor,
                      minHeight: 3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        if (_currentIndex != 0) {
          _selectTab(0);
          return;
        }

        final exit = await _confirmExit();
        if (exit && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            if (_showUpdateBanner) _buildUpdateBanner(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: [
                        _buildPage(0),
                        _buildPage(1),
                        _buildPage(2),
                        _buildPage(3),
                        _buildPage(4),
                        _buildPage(5),
                      ],
                    ),
                  ),
                  if (_showContinueCard)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12 + bottomPad + 58 + 10,
                      child: _ContinueWatchingBar(
                        item: _continueItem!,
                        onPlay: _openContinuePlayer,
                        onClose: _dismissContinue,
                      ),
                    ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12 + bottomPad,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _NavIcon(
                                icon: Icons.home_rounded,
                                selected: _currentIndex == 0,
                                onTap: () => _selectTab(0),
                              ),
                              _NavIcon(
                                icon: Icons.bookmark_rounded,
                                selected: _currentIndex == 1,
                                onTap: () => _selectTab(1),
                              ),
                              if (_showDescargasTab)
                                _NavIcon(
                                  icon: Icons.download_rounded,
                                  selected: _currentIndex == 2,
                                  onTap: () => _selectTab(2),
                                ),
                              _NavIcon(
                                icon: Icons.grid_view_rounded,
                                selected: _currentIndex == 3,
                                onTap: () => _selectTab(3),
                              ),
                              _NavIcon(
                                icon: Icons.settings_rounded,
                                selected: _currentIndex == 4,
                                onTap: () => _selectTab(4),
                              ),
                              _NavIcon(
                                icon: Icons.search_rounded,
                                selected: _currentIndex == 5,
                                onTap: () => _selectTab(5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Continuar viendo ───────────────────────────────────────────────────────

class _ContinueWatchingBar extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onPlay;
  final VoidCallback onClose;

  const _ContinueWatchingBar({
    required this.item,
    required this.onPlay,
    required this.onClose,
  });

  String get _title => item['titulo']?.toString() ?? 'Sin título';

  String get _image {
    final b = item['backdrop']?.toString() ?? '';
    if (b.isNotEmpty) return b;
    final p =
        item['poster']?.toString() ?? item['poster_path']?.toString() ?? '';
    if (p.isEmpty) return '';
    if (p.startsWith('http')) return p;
    return 'https://image.tmdb.org/t/p/w500$p';
  }

  int get _segundo => item['segundo'] as int? ?? 0;

  String get _timeLabel {
    final h = _segundo ~/ 3600;
    final m = (_segundo % 3600) ~/ 60;
    final s = _segundo % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  String get _meta {
    final tipo = (item['tipo'] ?? 'movie').toString();
    final t = item['temporada'];
    final c = item['capitulo'];
    if (tipo == 'tv' && t != null && c != null) {
      return 'T${t.toString().padLeft(2, '0')}E${c.toString().padLeft(2, '0')} · $_timeLabel';
    }
    return _timeLabel;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                  child: SizedBox(
                    width: 52,
                    height: 72,
                    child: _image.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _image,
                            fit: BoxFit.cover,
                            memCacheWidth: 120,
                            placeholder: (_, __) =>
                                const ColoredBox(color: Color(0xFF2C2C2E)),
                            errorWidget: (_, __, ___) => const ColoredBox(
                              color: Color(0xFF2C2C2E),
                              child: Icon(
                                Icons.movie,
                                color: Colors.white24,
                                size: 22,
                              ),
                            ),
                          )
                        : const ColoredBox(
                            color: Color(0xFF2C2C2E),
                            child: Icon(
                              Icons.movie,
                              color: Colors.white24,
                              size: 22,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: onPlay,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onPlay,
                  icon: const Icon(
                    Icons.play_circle_filled_rounded,
                    color: _kAccentColor,
                    size: 36,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 58,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              icon,
              key: ValueKey(selected),
              size: 24,
              color: selected ? _kAccentColor : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}