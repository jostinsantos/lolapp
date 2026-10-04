import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/home/presentation/home_page.dart';
import '../../features/tvchanel/home/home_tvchanel.dart';
import '../../features/lolbot/presentation/lolbot_page.dart';
import '../../features/foryou/presentation/taste_onboarding_page.dart';
import '../../data/ai/daily_ai_gate.dart';
import '../../core/services/session_watch_timer.dart';
import '../../features/player/presentation/widgets/mini_player_service.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/favorites/presentation/favorites_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/discover/domain/mobile/pag.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/tvchanel/player/player_tvchanel.dart';
import '../../features/tvchanel/models/tv_channel_models.dart';
import '../shared/modals/playback_setup_modal.dart';
import '../../core/constants/versiones.dart';
import '../../core/utils/display_refresh.dart';
import '../../supabase/supabase_config.dart';

const _kAccentColor = Color(0xFFE50914);

/// Notifica cambios de ajustes de descargas (si los usas desde Config).
class DownloadNavBus {
  DownloadNavBus._();
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static void bump() => version.value++;
}

///
/// ÍNDICES FIJOS:
///   0 → Home
///   1 → Biblioteca (Guardados + Historial + Descargas)
///   2 → Servicios
///   3 → Config
///   4 → Buscar
///
class MainHome extends StatefulWidget {
  const MainHome({super.key});

  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> with WidgetsBindingObserver {
  static const int _kHome = 0;
  static const int _kBiblioteca = 1;
  static const int _kServicios = 2;
  static const int _kConfig = 3;
  static const int _kBuscar = 4;

  int _currentIndex = _kHome;
  bool _tvLiveMode = false; // Home VOD vs TV en Vivo
  String? _profileAvatar;
  String? _profileName;

  final GlobalKey _homeKey = GlobalKey();
  final GlobalKey _bibliotecaKey = GlobalKey();
  final GlobalKey _serviciosKey = GlobalKey();

  bool _homeLoaded = true;
  bool _bibliotecaLoaded = false;
  bool _serviciosLoaded = false;

  Map<String, dynamic>? _continueItem;
  bool _continueDismissed = false;

  // ── Animación del menú inferior ────────────────────────────────────────
  bool _navCollapsed = false;

  // ── Actualización APK ──────────────────────────────────────────────────
  bool _updateAvailable = false;
  bool _updateBannerDismissed = false;
  String? _downloadUrl;
  String? _updateMessage;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;

  String? _urlArm64;
  String? _urlArmeabi;
  String? _urlX86;
  String? _urlUniversal;
  String? _preferredAbi;
  static const _prefAbiKey = 'apk_preferred_abi';

  bool get _showUpdateBanner => _updateAvailable && !_updateBannerDismissed;

  @override
  void initState() {
    super.initState();
    DisplayRefresh.requestHighest();
    WidgetsBinding.instance.addObserver(this);
    DownloadNavBus.version.addListener(_onDownloadNavBus);
    MiniPlayerService.instance.addListener(_onMiniPlayer);
    MiniPlayerService.instance.loadPref();
    _loadContinueItem();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfileSession();
      _bootstrapOfflineOrSetup();
      _checkForUpdate();
      SessionWatchTimer.instance.start(context);
      // Gustos: no bloquear el home (evita pantalla negra)
      // El usuario puede configurarlos desde For You más adelante.
    });
  }

  Future<void> _loadProfileSession() async {
    try {
      final avatar = await SupabaseConfig.getCurrentProfileAvatar();
      final name = await SupabaseConfig.getCurrentProfileName();
      try {
        await TasteOnboardingGate.markDone();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _profileAvatar = avatar;
        _profileName = name;
      });
    } catch (_) {}
  }

  Future<void> _maybeShowTasteOnboarding() async {
    final done = await TasteOnboardingGate.isDone();
    if (done || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TasteOnboardingPage(
          onFinished: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    DownloadNavBus.version.removeListener(_onDownloadNavBus);
    WidgetsBinding.instance.removeObserver(this);
    MiniPlayerService.instance.removeListener(_onMiniPlayer);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SCROLL → COLAPSAR / EXPANDIR MENÚ
  // ═══════════════════════════════════════════════════════════════════════

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    final pixels = notification.metrics.pixels;

    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      if (pixels > 40 && !_navCollapsed) {
        setState(() => _navCollapsed = true);
      } else if (pixels <= 10 && _navCollapsed) {
        setState(() => _navCollapsed = false);
      }
    } else if (notification is ScrollEndNotification) {
      if (pixels <= 10 && _navCollapsed) {
        setState(() => _navCollapsed = false);
      }
    }

    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DETECCIÓN DE ABI DEL DISPOSITIVO
  // ═══════════════════════════════════════════════════════════════════════

  /// Devuelve el ABI óptimo del dispositivo:
  /// 'arm64', 'armeabi', 'x86' o 'universal'.
  Future<String?> _detectDeviceAbi() async {
    if (!Platform.isAndroid) return 'universal';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis.map((e) => e.toLowerCase()).toList();

      if (abis.any((a) => a.contains('arm64'))) return 'arm64';
      if (abis.any((a) => a.contains('armeabi'))) return 'armeabi';
      if (abis.any((a) => a.contains('x86'))) return 'x86';
      return 'universal';
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTUALIZACIÓN
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _checkForUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recibirActualizaciones =
          prefs.getBool('recibir_actualizaciones') ?? true;
      final recibirParches = prefs.getBool('recibir_parches') ?? false;

      if (!recibirActualizaciones) {
        if (mounted) {
          setState(() {
            _updateAvailable = false;
            _updateBannerDismissed = true;
          });
        }
        return;
      }

      final status = await VersionService.checkForUpdate();
      if (!mounted) return;

      if (status.requiresUpdate && status.latestVersion != null) {
        final shouldShow =
            status.hasVersionUpdate ||
            (status.hasPatchUpdate && recibirParches);

        if (!shouldShow) {
          setState(() {
            _updateAvailable = false;
            _updateBannerDismissed = true;
          });
          return;
        }

        final v = status.latestVersion!;
        final savedAbi = prefs.getString(_prefAbiKey);
        final detectedAbi = await _detectDeviceAbi();

        if (!mounted) return;

        setState(() {
          _updateAvailable = true;
          _urlArm64 = _readUrl(v, 'urlApkArm64', 'url_apk_arm64');
          _urlArmeabi = _readUrl(v, 'urlApkArmeabi', 'url_apk_armeabi');
          _urlX86 = _readUrl(v, 'urlApkX86', 'url_apk_x86');
          _urlUniversal =
              _readUrl(v, 'urlApkUniversal', 'url_apk_universal') ??
              (v.urlApk.trim().isNotEmpty ? v.urlApk : null);
          _downloadUrl = v.urlApk;
          // Prioridad: elección guardada del usuario > detección automática
          _preferredAbi = savedAbi ?? detectedAbi;
          _updateMessage =
              '${v.versionAceptada} • ${v.novedades.isNotEmpty ? v.novedades : status.message}';
          _updateBannerDismissed = false;
        });
      } else if (mounted) {
        setState(() {
          _updateAvailable = false;
          _updateBannerDismissed = true;
        });
      }
    } catch (_) {}
  }

  String? _readUrl(dynamic v, String camel, String snake) {
    try {
      if (v is Map) {
        final a = v[camel]?.toString();
        final b = v[snake]?.toString();
        final s = (a != null && a.isNotEmpty) ? a : b;
        return (s != null && s.trim().isNotEmpty) ? s.trim() : null;
      }
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

  Future<void> _onTapDownload() async {
    if (_downloading) return;

    // Detecta el ABI del dispositivo si aún no lo tenemos.
    final detectedAbi = await _detectDeviceAbi();
    final initialAbi = _preferredAbi ?? detectedAbi ?? 'universal';

    if (!mounted) return;

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
                  'La más óptima para tu dispositivo es: ${_labelAbi(initialAbi)}',
                  style: TextStyle(
                    color: _kAccentColor.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map((o) {
                  final id = o['id']!;
                  final hasUrl = _urlForAbi(id) != null;
                  final isPreferred = _preferredAbi == id;
                  final isRecommended = detectedAbi == id;

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
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            o['title']!,
                            style: TextStyle(
                              color: hasUrl ? Colors.white : Colors.white38,
                              fontWeight: isPreferred
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isRecommended && hasUrl) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kAccentColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Óptima para tu dispositivo',
                              style: TextStyle(
                                color: _kAccentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
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
              : 'Activa "Instalar apps desconocidas" para esta app e inténtalo de nuevo.';
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

  // ═══════════════════════════════════════════════════════════════════════
  // BOOTSTRAP / CONTINUAR VIENDO
  // ═══════════════════════════════════════════════════════════════════════

  void _onDownloadNavBus() {}

  Future<void> _bootstrapOfflineOrSetup() async {
    if (!mounted) return;

    final online = await _hasConnection();
    if (!mounted) return;

    if (!online) {
      _selectTab(_kBiblioteca);
      return;
    }

    await _maybeShowPlaybackSetup();
  }

  Future<bool> _hasConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
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


  Future<void> _openMiniPlayer() async {
    final mini = MiniPlayerService.instance;
    if (!mini.isActive && !mini.isInitializing) return;

    // 1) Sincronizar posición actual del mini → caché del player
    //    (así al reabrir no vuelve al minuto del minimize)
    try {
      final c = mini.controller;
      if (c != null && c.value.isInitialized) {
        mini.position = c.value.position;
      }
    } catch (_) {}
    await mini.saveProgress(force: true);

    final args = mini.expandArgs();
    final startSec = args['startAt'] as int? ?? 0;

    // 2) Cerrar mini (libera decoder) después de guardar
    await mini.stop();
    if (!mounted) return;
    setState(() {});

    // 3) Pequeña pausa para liberar MediaCodec antes del full player
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final tipo = (args['tipo'] ?? 'movie').toString().toLowerCase();
    if (tipo == 'live') {
      // Canales en vivo → player de TV Channels (no el player VOD)
      final ch = TvChannel(
        id: 'mini-${args['idcontenido']}',
        name: (args['titulo'] ?? 'Canal').toString(),
        url: (args['videoUrl'] ?? '').toString(),
        logo: args['poster']?.toString(),
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerTvChanel(channel: ch),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            videoUrl: (args['videoUrl'] ?? '').toString(),
            idcontenido: args['idcontenido'] as int? ?? 0,
            temporada: args['temporada'] as int?,
            capitulo: args['capitulo'] as int?,
            tipo: (args['tipo'] ?? 'movie').toString(),
            titulo: (args['titulo'] ?? '').toString(),
            tmdbId: args['tmdbId'] as int?,
            idioma: args['idioma']?.toString(),
            headers: args['headers'] is Map
                ? Map<String, String>.from(args['headers'] as Map)
                : null,
          ),
        ),
      );
      _loadContinueItem();
    }
    if (mounted) setState(() {});
  }

  void _onMiniPlayer() {
    if (mounted) setState(() {});
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
      !_continueDismissed &&
      _continueItem != null &&
      _currentIndex == _kHome &&
      !_navCollapsed;

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

  // ═══════════════════════════════════════════════════════════════════════
  // CICLO DE VIDA / ORIENTACIÓN
  // ═══════════════════════════════════════════════════════════════════════

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _forcePortraitIfCurrent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _forcePortraitIfCurrent();
      _loadContinueItem();
    }
  }

  @override
  void didChangeMetrics() {
    _forcePortraitIfCurrent();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NAVEGACIÓN
  // ═══════════════════════════════════════════════════════════════════════

  void _scrollCurrentPageToTop() {
    // Intenta PrimaryScrollController del contexto del shell o de la página actual
    final candidates = <BuildContext?>[
      context,
      _homeKey.currentContext,
      _bibliotecaKey.currentContext,
      _serviciosKey.currentContext,
    ];
    for (final ctx in candidates) {
      if (ctx == null || !ctx.mounted) continue;
      final primary = PrimaryScrollController.maybeOf(ctx);
      if (primary != null && primary.hasClients) {
        primary.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      final scrollable = Scrollable.maybeOf(ctx);
      if (scrollable != null && scrollable.position.hasContentDimensions) {
        scrollable.position.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }
    // Fallback: notificar a través de un scroll notification no es viable aquí.
  }

  void _selectTab(int index) {
    if (index < 0 || index > _kBuscar) return;
    _forcePortraitIfCurrent();

    if (index == _kHome) {
      _homeLoaded = true;
      _loadContinueItem();
    } else if (index == _kBiblioteca) {
      _bibliotecaLoaded = true;
    } else if (index == _kServicios) {
      _serviciosLoaded = true;
    }

    if (_currentIndex == _kHome && index != _kHome) {
      _homeLoaded = false;
    }

    setState(() {
      _currentIndex = index;
      _navCollapsed = false; // al cambiar de pestaña se expande
    });
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
      case _kHome:
        if (!_homeLoaded) return const SizedBox.shrink();
        return _tvLiveMode
            ? const HomeTvChanel(key: ValueKey('tvLiveHome'))
            : HomePage(key: _homeKey);
      case _kBiblioteca:
        return _bibliotecaLoaded
            ? BibliotecaUnificadaPage(key: _bibliotecaKey)
            : const SizedBox.shrink();
      case _kServicios:
        return _serviciosLoaded
            ? ServiciosPage(key: _serviciosKey)
            : const SizedBox.shrink();
      case _kConfig:
        return const ConfigPage(key: ValueKey('configPage'));
      case _kBuscar:
        return const BuscarPage(key: ValueKey('buscarPage'));
      default:
        return const SizedBox.shrink();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BANNER UPDATE
  // ═══════════════════════════════════════════════════════════════════════

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
                      value: _downloadProgress > 0.02
                          ? _downloadProgress
                          : null,
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

  // ═══════════════════════════════════════════════════════════════════════
  // MENÚ INFERIOR (diseño final)
  // ═══════════════════════════════════════════════════════════════════════

  IconData get _activeIcon {
    switch (_currentIndex) {
      case _kHome:
        return Icons.home_rounded;
      case _kBiblioteca:
        return Icons.bookmark_rounded;
      case _kServicios:
        return Icons.grid_view_rounded;
      case _kConfig:
        return Icons.settings_rounded;
      case _kBuscar:
        return Icons.search_rounded;
      default:
        return Icons.home_rounded;
    }
  }

  /// Círculo reutilizable (mismo estilo que el botón de buscar)
  Widget _buildCircleNav({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 58,
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
          child: Center(
            child: _NavIcon(icon: icon, selected: selected, onTap: onTap),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(double bottomPad) {
    final isSearch = _currentIndex == _kBuscar;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 12 + bottomPad,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: child,
            ),
          );
        },
        child: _navCollapsed
            // ── COLAPSADO ──────────────────────────────────────────────
            ? Row(
                key: ValueKey(
                  isSearch ? 'collapsed-search' : 'collapsed-other',
                ),
                children: [
                  if (!isSearch)
                    _buildCircleNav(
                      icon: _activeIcon,
                      selected: true,
                      onTap: _scrollCurrentPageToTop,
                    ),
                  // Espacio central: mini-player compacto si está activo
                  if (!isSearch && MiniPlayerService.instance.isActive) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniPlayerBarCompact(
                        onExpand: _openMiniPlayer,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ] else
                    const Spacer(),
                  _buildCircleNav(
                    icon: Icons.search_rounded,
                    selected: true,
                    onTap: () => _selectTab(_kBuscar),
                  ),
                ],
              )
            // ── EXPANDIDO ──────────────────────────────────────────────
            : Row(
                key: const ValueKey('expanded'),
                children: [
                  Expanded(
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
                                selected: _currentIndex == _kHome,
                                onTap: () => _selectTab(_kHome),
                              ),
                              _NavIcon(
                                icon: Icons.bookmark_rounded,
                                selected: _currentIndex == _kBiblioteca,
                                onTap: () => _selectTab(_kBiblioteca),
                              ),
                              _NavIcon(
                                icon: Icons.grid_view_rounded,
                                selected: _currentIndex == _kServicios,
                                onTap: () => _selectTab(_kServicios),
                              ),
                              _ProfileNavIcon(
                                avatarUrl: _profileAvatar,
                                name: _profileName,
                                selected: _currentIndex == _kConfig,
                                onTap: () => _selectTab(_kConfig),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildCircleNav(
                    icon: Icons.search_rounded,
                    selected: _currentIndex == _kBuscar,
                    onTap: () => _selectTab(_kBuscar),
                  ),
                ],
              ),
      ),
    );
  }
  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_currentIndex != _kHome) {
          _selectTab(_kHome);
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
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: [
                          _buildPage(_kHome),
                          _buildPage(_kBiblioteca),
                          _buildPage(_kServicios),
                          _buildPage(_kConfig),
                          _buildPage(_kBuscar),
                        ],
                      ),
                    ),


                    // AppBar transparente solo en Home:
                    // - Izquierda: Lolbot (chat IA) — solo en modo VOD
                    // - Derecha: TV Live / VOD
                    if (_currentIndex == _kHome)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          bottom: false,
                          child: SizedBox(
                            height: 52,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  // Lolbot — extremo izquierdo (opuesto al TV)
                                  if (!_tvLiveMode)
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const LolbotPage(),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.black.withOpacity(0.55),
                                          border: Border.all(
                                            color: Colors.purpleAccent
                                                .withOpacity(0.7),
                                            width: 1.5,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        // Solo la letra L (ya no "LOL BOT" ni emoji)
                                        child: const Text(
                                          'L',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  // TV Live / VOD — extremo derecho
                                  GestureDetector(
                                    onTap: () {
                                      setState(
                                          () => _tvLiveMode = !_tvLiveMode);
                                    },
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Image.asset(
                                        _tvLiveMode
                                            ? 'assets/images/vod.png'
                                            : 'assets/images/tvlive.png',
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(
                                          color: const Color(0xFFE50914),
                                          child: Icon(
                                            _tvLiveMode
                                                ? Icons.movie_rounded
                                                : Icons.live_tv_rounded,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Mini-player GRANDE: solo en top (menú expandido)
                    if (!_navCollapsed &&
                        (MiniPlayerService.instance.isActive ||
                            MiniPlayerService.instance.isInitializing))
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 12 + bottomPad + 58 + 10,
                        child: _MiniPlayerBar(
                          onExpand: _openMiniPlayer,
                          onStop: () async {
                            await MiniPlayerService.instance.stop();
                            if (mounted) setState(() {});
                          },
                        ),
                      )
                    // Continuar viendo (solo si no hay mini-player y menú expandido)
                    else if (!_navCollapsed && _showContinueCard)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 12 + bottomPad + 58 + 10,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: _navCollapsed ? 0.0 : 1.0,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 220),
                            offset: _navCollapsed
                                ? const Offset(0, 0.3)
                                : Offset.zero,
                            child: _ContinueWatchingBar(
                              item: _continueItem!,
                              onPlay: _openContinuePlayer,
                              onClose: _dismissContinue,
                            ),
                          ),
                        ),
                      ),


                    // Menú inferior
                    _buildBottomNav(bottomPad),
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

// ─── Mini player bar ────────────────────────────────────────────────────────

class _MiniPlayerBar extends StatelessWidget {
  final VoidCallback onExpand;
  final VoidCallback onStop;

  const _MiniPlayerBar({required this.onExpand, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final mini = MiniPlayerService.instance;
    return AnimatedBuilder(
      animation: mini,
      builder: (context, _) {
        final isLive = mini.tipo.toLowerCase() == 'live';
        final dur = mini.duration.inMilliseconds;
        final pos = mini.position.inMilliseconds;
        final progress = (!isLive && dur > 0) ? (pos / dur).clamp(0.0, 1.0) : 0.0;
        final posLabel = _fmt(mini.position);
        final durLabel = _fmt(mini.duration);
        final timeText = isLive ? 'En vivo' : '$posLabel / $durLabel';

        return Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress solo VOD; live sin barra
                    if (!isLive)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white12,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    SizedBox(
                      height: 64,
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => mini.togglePlay(),
                            icon: Icon(
                              mini.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: onExpand,
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mini.title.isEmpty ? 'Reproduciendo…' : mini.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    timeText,
                                    style: TextStyle(
                                      color: isLive
                                          ? const Color(0xFFE50914)
                                          : Colors.white.withValues(alpha: 0.5),
                                      fontSize: 11,
                                      fontWeight: isLive ? FontWeight.w700 : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Pantalla completa',
                            onPressed: onExpand,
                            icon: const Icon(Icons.open_in_full_rounded,
                                color: Colors.white70, size: 20),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: onStop,
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white54, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _MiniPlayerBarCompact extends StatelessWidget {
  final VoidCallback onExpand;
  const _MiniPlayerBarCompact({required this.onExpand});

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final mini = MiniPlayerService.instance;
    return AnimatedBuilder(
      animation: mini,
      builder: (context, _) {
        final isLive = mini.tipo.toLowerCase() == 'live';
        final durMs = mini.duration.inMilliseconds;
        final posMs = mini.position.inMilliseconds;
        final progress = (!isLive && durMs > 0) ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
        final posLabel = _fmt(mini.position);
        final durLabel = _fmt(mini.duration);
        final timeText = isLive ? 'En vivo' : '$posLabel / $durLabel';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onExpand, // abre player en horizontal
            borderRadius: BorderRadius.circular(24),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (!isLive)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        color: const Color(0xFFE50914),
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => mini.togglePlay(),
                        icon: Icon(
                          mini.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mini.title.isEmpty
                                  ? 'Reproduciendo…'
                                  : mini.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              timeText,
                              maxLines: 1,
                              style: TextStyle(
                                color: isLive
                                    ? const Color(0xFFE50914)
                                    : Colors.white.withValues(alpha: 0.55),
                                fontSize: 10,
                                fontWeight:
                                    isLive ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: Icon(Icons.open_in_full_rounded,
                            color: Colors.white54, size: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Avatar del perfil en el menú inferior (reemplaza el icono de config).
class _ProfileNavIcon extends StatelessWidget {
  final String? avatarUrl;
  final String? name;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileNavIcon({
    required this.avatarUrl,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 36 : 32,
            height: selected ? 36 : 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? const Color(0xFFE50914) : Colors.white24,
                width: selected ? 2.2 : 1,
              ),
              color: Colors.white12,
            ),
            clipBehavior: Clip.antiAlias,
            child: hasAvatar
                ? Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person_rounded,
                      size: selected ? 20 : 18,
                      color: selected ? Colors.white : Colors.white54,
                    ),
                  )
                : Icon(
                    Icons.person_rounded,
                    size: selected ? 20 : 18,
                    color: selected ? Colors.white : Colors.white54,
                  ),
          ),
        ),
      ),
    );
  }
}
