import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/modals/playback_setup_modal.dart';
import '../../core/constants/versiones.dart'; // ← VersionService + VersionInfo con URLs por ABI
import '../../features/home/presentation/tv_home_page.dart';
import '../../features/search/presentation/tv_search_page.dart';
import '../../features/history/presentation/history_page.dart';
import '../../features/settings/presentation/tv_settings.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/discover/presentation/discover_page.dart';
import '../../features/discover/presentation/tv_discover_page.dart';
const _kAccentColor = Color(0xFFE50914);
const _kSideAccent = Color(0xFF7B5CFF);

class MainHome extends StatefulWidget {
  const MainHome({super.key});

  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> {
  int _currentIndex = 0;
  bool _menuActive = false;
  bool _navigatingMenu = false;
  bool _transferringToContent = false;

  final FocusNode _profileFocusNode = FocusNode(debugLabel: 'menu_perfil');
  final FocusNode _homeTabFocusNode = FocusNode(debugLabel: 'menu_home');
  final FocusNode _descubrirTabFocusNode =
      FocusNode(debugLabel: 'menu_descubrir');
  final FocusNode _fuentesTabFocusNode = FocusNode(debugLabel: 'menu_fuentes');
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'menu_buscar');
  final FocusNode _guardadosTabFocusNode =
      FocusNode(debugLabel: 'menu_biblio');
  final FocusNode _settingsFocusNode = FocusNode(debugLabel: 'menu_config');

  // Foco del banner de actualización
  final FocusNode _updateDownloadFocus =
      FocusNode(debugLabel: 'update_download');
  final FocusNode _updateCloseFocus = FocusNode(debugLabel: 'update_close');

  late final List<FocusNode> _menuFocusNodes;

  FocusNode? _homeContentFocusNode;
  FocusNode? _descubrirContentFocusNode;
  FocusNode? _fuentesContentFocusNode;
  FocusNode? _guardadosContentFocusNode;
  FocusNode? _configContentFocusNode;
  FocusNode? _perfilContentFocusNode;
  BuscarPageState? _buscarPageState;

  final GlobalKey _homeKey = GlobalKey();
  final GlobalKey _descubrirKey = GlobalKey();
  final GlobalKey _fuentesKey = GlobalKey();
  final GlobalKey _guardadosKey = GlobalKey();
  final GlobalKey _perfilKey = GlobalKey();

  bool _homeLoaded = true;
  bool _descubrirLoaded = false;
  bool _fuentesLoaded = false;
  bool _guardadosLoaded = false;
  bool _perfilLoaded = false;

  static const int _kPerfilIndex = 6;
  static const int _kFuentesIndex = 2;
  static const double _railWidth = 52;

  String _currentTime = '';
  Timer? _clockTimer;
  Timer? _menuCollapseTimer;
  Timer? _transferTimer;

  // ── Actualización ──────────────────────────────────────────────────────
  bool _updateAvailable = false;
  bool _updateBannerDismissed = false;
  String? _downloadUrl;
  String? _updateMessage;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;

  /// URLs por arquitectura
  String? _urlArm64;
  String? _urlArmeabi;
  String? _urlX86;
  String? _urlUniversal;

  /// Preferencia: arm64 | armeabi | x86 | universal
  String? _preferredAbi;
  static const _prefAbiKey = 'apk_preferred_abi';

  bool get _showUpdateBanner =>
      _updateAvailable && !_updateBannerDismissed;

  @override
  void initState() {
    super.initState();
    _menuFocusNodes = [
      _profileFocusNode,
      _homeTabFocusNode,
      _descubrirTabFocusNode,
      _fuentesTabFocusNode,
      _searchFocusNode,
      _guardadosTabFocusNode,
      _settingsFocusNode,
    ];
    for (final node in _menuFocusNodes) {
      node.addListener(_handleMenuFocusChange);
    }
    _updateTime();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateTime(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      _maybeShowPlaybackSetup();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LÓGICA DE ACTUALIZACIÓN (VersionService + modal arquitectura TV)
  // ═══════════════════════════════════════════════════════════════════════

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
          _urlArm64 = v.urlApkArm64;
          _urlArmeabi = v.urlApkArmeabi;
          _urlX86 = v.urlApkX86;
          _urlUniversal = v.urlApkUniversal ??
              (v.urlApk.trim().isNotEmpty ? v.urlApk : null);
          _downloadUrl = v.urlApk;
          _preferredAbi = savedAbi;
          _updateMessage =
              '${v.versionAceptada} • ${v.novedades.isNotEmpty ? v.novedades : status.message}';
          _updateBannerDismissed = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showUpdateBanner) {
            _updateDownloadFocus.requestFocus();
          }
        });
      }
    } catch (_) {
      // Silencioso
    }
  }

  void _dismissUpdateBanner() {
    setState(() => _updateBannerDismissed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusMenu();
    });
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

  /// Abrir modal de arquitectura (TV / D-pad) y luego descargar.
  Future<void> _onTapDownload() async {
    if (_downloading) return;

    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _AbiPickerDialog(
        preferredAbi: _preferredAbi,
        urlForAbi: _urlForAbi,
        labelAbi: _labelAbi,
        accent: _kAccentColor,
      ),
    );

    if (selected == null || !mounted) {
      // Volver foco al botón Descargar del banner
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showUpdateBanner) {
          _updateDownloadFocus.requestFocus();
        }
      });
      return;
    }

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

  Future<void> _maybeShowPlaybackSetup() async {
    if (_showUpdateBanner) return;

    if (!mounted) return;

    final done = await hasPlaybackSetup();
    if (done || !mounted) return;

    final saved = await showPlaybackSetupModal(context);
    if (!mounted) return;

    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración de reproducción guardada'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configura reproducción en Configuración → Fuentes para ver contenido',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    }

    _focusContentOf(_currentIndex);
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final formatted = '$hour12:$minute $period';
    if (formatted != _currentTime && mounted) {
      setState(() => _currentTime = formatted);
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _menuCollapseTimer?.cancel();
    _transferTimer?.cancel();
    for (final node in _menuFocusNodes) {
      node.removeListener(_handleMenuFocusChange);
      node.dispose();
    }
    _updateDownloadFocus.dispose();
    _updateCloseFocus.dispose();
    super.dispose();
  }

  void _handleMenuFocusChange() {
    final active = _menuFocusNodes.any((n) => n.hasFocus);

    if (_transferringToContent) {
      if (!active) {
        _menuCollapseTimer?.cancel();
        if (_menuActive && mounted) setState(() => _menuActive = false);
      }
      return;
    }

    if (active) {
      _menuCollapseTimer?.cancel();
      if (!_menuActive && mounted) setState(() => _menuActive = true);
      return;
    }

    _menuCollapseTimer?.cancel();
    _menuCollapseTimer = Timer(const Duration(milliseconds: 60), () {
      if (!mounted || _transferringToContent) return;
      if (!_menuFocusNodes.any((n) => n.hasFocus) && _menuActive) {
        setState(() => _menuActive = false);
      }
    });
  }

  void _collapseMenu() {
    _menuCollapseTimer?.cancel();
    if (_menuActive && mounted) {
      setState(() => _menuActive = false);
    }
  }

  void _focusMenu() {
    _transferringToContent = false;
    _transferTimer?.cancel();
    _menuNodeOf(_currentIndex).requestFocus();
  }

  FocusNode? _contentNodeOf(int index) {
    switch (index) {
      case 0:
        return _homeContentFocusNode;
      case 1:
        return _descubrirContentFocusNode;
      case _kFuentesIndex:
        return _fuentesContentFocusNode;
      case 3:
        try {
          return _buscarPageState?.getAKeyFocusNode();
        } catch (_) {
          return null;
        }
      case 4:
        return _guardadosContentFocusNode;
      case 5:
        return _configContentFocusNode;
      case _kPerfilIndex:
        return _perfilContentFocusNode;
      default:
        return null;
    }
  }

  FocusNode _menuNodeOf(int index) {
    switch (index) {
      case 0:
        return _homeTabFocusNode;
      case 1:
        return _descubrirTabFocusNode;
      case _kFuentesIndex:
        return _fuentesTabFocusNode;
      case 3:
        return _searchFocusNode;
      case 4:
        return _guardadosTabFocusNode;
      case 5:
        return _settingsFocusNode;
      case _kPerfilIndex:
        return _profileFocusNode;
      default:
        return _homeTabFocusNode;
    }
  }

  void _unfocusMenu() {
    for (final n in _menuFocusNodes) {
      if (n.hasFocus) {
        n.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      }
    }
  }

  void _focusContentOf(int index) {
    _transferringToContent = true;
    _transferTimer?.cancel();
    _collapseMenu();
    _unfocusMenu();

    void finishTransfer() {
      if (!mounted) return;
      _transferringToContent = false;
      if (!_menuFocusNodes.any((n) => n.hasFocus)) {
        _collapseMenu();
      }
    }

    void tryFocus([int attempt = 0]) {
      if (!mounted) {
        _transferringToContent = false;
        return;
      }

      final node = _contentNodeOf(index);
      if (node != null && node.canRequestFocus) {
        _unfocusMenu();
        node.requestFocus();
        _collapseMenu();

        _transferTimer?.cancel();
        _transferTimer = Timer(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          if (_menuFocusNodes.any((n) => n.hasFocus)) {
            final again = _contentNodeOf(index);
            if (again != null && again.canRequestFocus) {
              again.requestFocus();
            }
            _collapseMenu();
          }
          finishTransfer();
        });
        return;
      }

      if (attempt < 12) {
        Future.delayed(
          const Duration(milliseconds: 40),
          () => tryFocus(attempt + 1),
        );
      } else {
        _transferringToContent = false;
        _menuNodeOf(index).requestFocus();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus());
  }

  void _ensureLoaded(int index) {
    if (index == 0) _homeLoaded = true;
    if (index == 1) _descubrirLoaded = true;
    if (index == _kFuentesIndex) _fuentesLoaded = true;
    if (index == 4) _guardadosLoaded = true;
    if (index == _kPerfilIndex) {
      _perfilLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          (_perfilKey.currentState as dynamic)?.refresh();
        } catch (_) {}
      });
    }
  }

  void _selectTab(int index, {bool focusContent = false}) {
    if (_navigatingMenu) return;

    _ensureLoaded(index);

    if (_currentIndex == 1 && index != 1) _descubrirLoaded = false;
    if (_currentIndex == _kFuentesIndex && index != _kFuentesIndex) {
      _fuentesLoaded = false;
    }
    if (_currentIndex == 4 && index != 4) _guardadosLoaded = false;
    if (_currentIndex == _kPerfilIndex && index != _kPerfilIndex) {
      _perfilLoaded = false;
    }

    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }

    if (focusContent) {
      _focusContentOf(index);
    }
  }

  void _enterPage(int tabIndex) {
    _collapseMenu();
    _selectTab(tabIndex, focusContent: true);
  }

  KeyEventResult _onMenuKey(FocusNode node, KeyEvent event, int tabIndex) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp && _showUpdateBanner) {
      final i = _menuFocusNodes.indexOf(node);
      if (i == 0 || node == _profileFocusNode || node == _homeTabFocusNode) {
        _updateDownloadFocus.requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      final i = _menuFocusNodes.indexOf(node);
      if (i >= 0 && i < _menuFocusNodes.length - 1) {
        _navigatingMenu = true;
        _menuFocusNodes[i + 1].requestFocus();
        _navigatingMenu = false;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      final i = _menuFocusNodes.indexOf(node);
      if (i > 0) {
        _navigatingMenu = true;
        _menuFocusNodes[i - 1].requestFocus();
        _navigatingMenu = false;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      _enterPage(tabIndex);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.backspace) {
      _confirmExit();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final okFocus = FocusNode();
        final cancelFocus = FocusNode();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          cancelFocus.requestFocus();
        });
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _kAccentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: _kAccentColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '¿Salir de la aplicación?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Se cerrará la app. Podrás abrirla de nuevo cuando quieras.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: _ExitDialogBtn(
                          focusNode: cancelFocus,
                          label: 'Cancelar',
                          primary: false,
                          onTap: () => Navigator.of(ctx).pop(false),
                          onLeft: null,
                          onRight: () => okFocus.requestFocus(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ExitDialogBtn(
                          focusNode: okFocus,
                          label: 'Salir',
                          primary: true,
                          onTap: () => Navigator.of(ctx).pop(true),
                          onLeft: () => cancelFocus.requestFocus(),
                          onRight: null,
                        ),
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

    if (shouldExit == true && mounted) {
      await SystemNavigator.pop();
    } else if (mounted) {
      if (_showUpdateBanner) {
        _updateDownloadFocus.requestFocus();
      } else {
        _focusMenu();
      }
    }
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return _homeLoaded
            ? HomePage(
                key: _homeKey,
                onRequestMenuFocus: _focusMenu,
                onMainFocusNodeCreated: (node) =>
                    _homeContentFocusNode = node,
              )
            : const SizedBox.shrink();
      case 1:
        return _descubrirLoaded
            ? EscrubirPage(
                key: _descubrirKey,
                onRequestMenuFocus: _focusMenu,
                onMainFocusNodeCreated: (node) =>
                    _descubrirContentFocusNode = node,
              )
            : const SizedBox.shrink();
      case _kFuentesIndex:
        return _fuentesLoaded
            ? ServiciosTvPage(
                key: _fuentesKey,
                onRequestMenuFocus: _focusMenu,
                onMainFocusNodeCreated: (node) =>
                    _fuentesContentFocusNode = node,
              )
            : const SizedBox.shrink();
      case 3:
        return BuscarPage(
          key: const ValueKey('buscarPage'),
          onPageCreated: (state) => _buscarPageState = state,
          onRequestMenuFocus: _focusMenu,
        );
      case 4:
        return _guardadosLoaded
            ? GuardadosPage(
                key: _guardadosKey,
                onRequestMenuFocus: _focusMenu,
                onMainFocusNodeCreated: (node) =>
                    _guardadosContentFocusNode = node,
              )
            : const SizedBox.shrink();
      case 5:
        return ConfigPage(
          onRequestMenuFocus: _focusMenu,
          onMainFocusNodeCreated: (node) => _configContentFocusNode = node,
        );
      case _kPerfilIndex:
        return _perfilLoaded
            ? PerfilPage(
                key: _perfilKey,
                onRequestMenuFocus: _focusMenu,
                onMainFocusNodeCreated: (node) =>
                    _perfilContentFocusNode = node,
              )
            : const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Banner de actualización (TV) ───────────────────────────────────────

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
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _kAccentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: _kAccentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Actualización disponible',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _updateMessage ??
                                'Hay una nueva versión · v${VersionService.currentVersionName} (${VersionService.currentVersionCode})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                          if (_preferredAbi != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'APK: ${_labelAbi(_preferredAbi!)}',
                              style: TextStyle(
                                color: _kAccentColor.withValues(alpha: 0.95),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Botón Descargar → abre modal de arquitectura
                    Focus(
                      focusNode: _updateDownloadFocus,
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        final key = event.logicalKey;

                        if (key == LogicalKeyboardKey.select ||
                            key == LogicalKeyboardKey.enter) {
                          if (!_downloading) _onTapDownload();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowRight) {
                          _updateCloseFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowDown) {
                          _homeTabFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final hasFocus = Focus.of(context).hasFocus;
                          return GestureDetector(
                            onTap: _downloading ? null : _onTapDownload,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              height: 42,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 18),
                              decoration: BoxDecoration(
                                color: _downloading
                                    ? _kAccentColor.withValues(alpha: 0.45)
                                    : (hasFocus
                                        ? _kAccentColor
                                        : _kAccentColor.withValues(
                                            alpha: 0.85)),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: hasFocus
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2.2,
                                ),
                              ),
                              child: _downloading
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            value: _downloadProgress > 0.02
                                                ? _downloadProgress
                                                : null,
                                            strokeWidth: 2.2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '$pct%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.download_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Descargar',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Botón X
                    Focus(
                      focusNode: _updateCloseFocus,
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        final key = event.logicalKey;

                        if (key == LogicalKeyboardKey.select ||
                            key == LogicalKeyboardKey.enter) {
                          _dismissUpdateBanner();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowLeft) {
                          _updateDownloadFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowDown) {
                          _homeTabFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final hasFocus = Focus.of(context).hasFocus;
                          return GestureDetector(
                            onTap: _dismissUpdateBanner,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: hasFocus
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: hasFocus
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2.2,
                                ),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                color: hasFocus
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.65),
                                size: 22,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                if (_downloadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _downloadError!,
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_downloading) ...[
                  const SizedBox(height: 10),
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
    final profileSelected = _currentIndex == _kPerfilIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
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
                    child: Padding(
                      padding: const EdgeInsets.only(left: _railWidth),
                      child: IndexedStack(
                        index:
                            _currentIndex == _kPerfilIndex ? 6 : _currentIndex,
                        children: [
                          _buildPage(0),
                          _buildPage(1),
                          _buildPage(_kFuentesIndex),
                          _buildPage(3),
                          _buildPage(4),
                          _buildPage(5),
                          _buildPage(_kPerfilIndex),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: _SideMenu(
                      expanded: _menuActive,
                      currentIndex: _currentIndex,
                      profileSelected: profileSelected,
                      currentTime: _currentTime,
                      profileFocus: _profileFocusNode,
                      homeFocus: _homeTabFocusNode,
                      descubrirFocus: _descubrirTabFocusNode,
                      fuentesFocus: _fuentesTabFocusNode,
                      searchFocus: _searchFocusNode,
                      guardadosFocus: _guardadosTabFocusNode,
                      settingsFocus: _settingsFocusNode,
                      onKeyEvent: _onMenuKey,
                      onSelect: _enterPage,
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

// ═══════════════════════════════════════════════════════════════════════════
// Modal arquitectura (TV) — foco D-pad, hereda del botón Descargar
// ═══════════════════════════════════════════════════════════════════════════

class _AbiPickerDialog extends StatefulWidget {
  final String? preferredAbi;
  final String? Function(String abi) urlForAbi;
  final String Function(String abi) labelAbi;
  final Color accent;

  const _AbiPickerDialog({
    required this.preferredAbi,
    required this.urlForAbi,
    required this.labelAbi,
    required this.accent,
  });

  @override
  State<_AbiPickerDialog> createState() => _AbiPickerDialogState();
}

class _AbiPickerDialogState extends State<_AbiPickerDialog> {
  static const _options = [
    {
      'id': 'arm64',
      'title': 'ARM64 (arm64-v8a)',
      'subtitle': 'Mayoría de dispositivos y Android TV',
    },
    {
      'id': 'armeabi',
      'title': 'ARMv7 (armeabi-v7a)',
      'subtitle': 'Dispositivos más antiguos',
    },
    {
      'id': 'x86',
      'title': 'x86 / x86_64',
      'subtitle': 'Emuladores y algunos boxes',
    },
    {
      'id': 'universal',
      'title': 'Universal (todas)',
      'subtitle': 'Más pesada · compatible con todo',
    },
  ];

  late final List<FocusNode> _nodes;
  late final List<int> _enabledIndexes; // índices con URL

  @override
  void initState() {
    super.initState();
    _nodes = List.generate(_options.length, (i) => FocusNode(debugLabel: 'abi_$i'));
    _enabledIndexes = [];
    for (var i = 0; i < _options.length; i++) {
      if (widget.urlForAbi(_options[i]['id']!) != null) {
        _enabledIndexes.add(i);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Preferencia previa si está disponible, si no la primera con URL
      int focusIdx = 0;
      if (widget.preferredAbi != null) {
        final i = _options.indexWhere((o) => o['id'] == widget.preferredAbi);
        if (i >= 0 && widget.urlForAbi(_options[i]['id']!) != null) {
          focusIdx = i;
        } else if (_enabledIndexes.isNotEmpty) {
          focusIdx = _enabledIndexes.first;
        }
      } else if (_enabledIndexes.isNotEmpty) {
        focusIdx = _enabledIndexes.first;
      }
      _nodes[focusIdx].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _moveFocus(int fromIndex, int delta) {
    if (_enabledIndexes.isEmpty) return;
    final pos = _enabledIndexes.indexOf(fromIndex);
    if (pos < 0) {
      _nodes[_enabledIndexes.first].requestFocus();
      return;
    }
    final next = (pos + delta).clamp(0, _enabledIndexes.length - 1);
    _nodes[_enabledIndexes[next]].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Elige arquitectura del APK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.preferredAbi != null
                    ? 'Última usada: ${widget.labelAbi(widget.preferredAbi!)}'
                    : 'Se recordará tu elección en este dispositivo',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(_options.length, (i) {
                final o = _options[i];
                final id = o['id']!;
                final hasUrl = widget.urlForAbi(id) != null;
                final isPreferred = widget.preferredAbi == id;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Focus(
                    focusNode: _nodes[i],
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;

                      if (key == LogicalKeyboardKey.arrowDown) {
                        _moveFocus(i, 1);
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowUp) {
                        _moveFocus(i, -1);
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.select ||
                          key == LogicalKeyboardKey.enter) {
                        if (hasUrl) Navigator.of(context).pop(id);
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.escape ||
                          key == LogicalKeyboardKey.goBack ||
                          key == LogicalKeyboardKey.backspace) {
                        Navigator.of(context).pop();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final hasFocus = Focus.of(context).hasFocus;
                        return GestureDetector(
                          onTap: hasUrl
                              ? () => Navigator.of(context).pop(id)
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: hasFocus
                                  ? widget.accent.withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasFocus
                                    ? Colors.white
                                    : (isPreferred
                                        ? widget.accent.withValues(alpha: 0.5)
                                        : Colors.transparent),
                                width: hasFocus ? 2.2 : 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isPreferred
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: !hasUrl
                                      ? Colors.white24
                                      : (hasFocus || isPreferred
                                          ? widget.accent
                                          : Colors.white54),
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o['title']!,
                                        style: TextStyle(
                                          color: hasUrl
                                              ? Colors.white
                                              : Colors.white38,
                                          fontSize: 15,
                                          fontWeight: hasFocus || isPreferred
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        hasUrl
                                            ? o['subtitle']!
                                            : 'No disponible en esta versión',
                                        style: TextStyle(
                                          color: hasUrl
                                              ? Colors.white
                                                  .withValues(alpha: 0.5)
                                              : Colors.white24,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isPreferred)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: widget.accent
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Anterior',
                                      style: TextStyle(
                                        color: widget.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
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
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SideMenu, _SideItem, _ExitDialogBtn ───────────────────────────────────

class _SideMenu extends StatelessWidget {
  final bool expanded;
  final int currentIndex;
  final bool profileSelected;
  final String currentTime;
  final FocusNode profileFocus;
  final FocusNode homeFocus;
  final FocusNode descubrirFocus;
  final FocusNode fuentesFocus;
  final FocusNode searchFocus;
  final FocusNode guardadosFocus;
  final FocusNode settingsFocus;
  final KeyEventResult Function(FocusNode, KeyEvent, int) onKeyEvent;
  final ValueChanged<int> onSelect;

  const _SideMenu({
    required this.expanded,
    required this.currentIndex,
    required this.profileSelected,
    required this.currentTime,
    required this.profileFocus,
    required this.homeFocus,
    required this.descubrirFocus,
    required this.fuentesFocus,
    required this.searchFocus,
    required this.guardadosFocus,
    required this.settingsFocus,
    required this.onKeyEvent,
    required this.onSelect,
  });

  static const double _collapsedW = 52;
  static const double _expandedW = 168;

  @override
  Widget build(BuildContext context) {
    final width = expanded ? _expandedW : _collapsedW;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      child: ClipRRect(
        borderRadius: expanded
            ? const BorderRadius.only(
                topRight: Radius.circular(22),
                bottomRight: Radius.circular(22),
              )
            : BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: expanded ? 24 : 12,
            sigmaY: expanded ? 24 : 12,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: expanded
                    ? const [Color(0xF214141A), Color(0xF00E0E12)]
                    : [
                        Colors.black.withValues(alpha: 0.42),
                        Colors.black.withValues(alpha: 0.28),
                      ],
              ),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: expanded ? 0.10 : 0.06),
                  width: 1,
                ),
              ),
              boxShadow: expanded
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 28,
                        offset: const Offset(8, 0),
                      ),
                    ]
                  : null,
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  _SideItem(
                    expanded: expanded,
                    icon: Icons.person_rounded,
                    label: 'Perfil',
                    focusNode: profileFocus,
                    selected: profileSelected,
                    isProfile: true,
                    onKeyEvent: (n, e) => onKeyEvent(n, e, 6),
                    onTap: () => onSelect(6),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else
                    const SizedBox(height: 8),
                  _SideItem(
                    expanded: expanded,
                    icon: Icons.home_rounded,
                    label: 'Inicio',
                    focusNode: homeFocus,
                    selected: currentIndex == 0,
                    onKeyEvent: (n, e) => onKeyEvent(n, e, 0),
                    onTap: () => onSelect(0),
                  ),
                  _SideItem(
                    expanded: expanded,
                    icon: Icons.explore_rounded,
                    label: 'Descubrir',
                    focusNode: descubrirFocus,
                    selected: currentIndex == 1,
                    onKeyEvent: (n, e) => onKeyEvent(n, e, 1),
                    onTap: () => onSelect(1),
                  ),
                  _SideItem(
                    expanded: expanded,
                    icon: Icons.cloud_rounded,
                    label: 'Fuentes',
                    focusNode: fuentesFocus,
                    selected: currentIndex == 2,
                    onKeyEvent: (n, e) => onKeyEvent(n, e, 2),
                    onTap: () => onSelect(2),
                  ),
                  _SideItem(
                    expanded: expanded,
                    icon: Icons.search_rounded,
                    label: 'Buscar',
                    focusNode: searchFocus,
                    selected: currentIndex == 3,
                    onKeyEvent: (n, e) => onKeyEvent(n, e, 3),
                    onTap: () => onSelect(3),
                  ),
                  _SideItem(
                    expanded: expanded,
                    icon: Icons.collections_bookmark_rounded,
                    label: 'Biblioteca',
                    focusNode: guardadosFocus,
                    selected: currentIndex == 4,
                    onKeyEvent: (n, e) => onKeyEvent(n, e, 4),
                    onTap: () => onSelect(4),
                  ),
                  const Spacer(),
                  if (expanded && currentTime.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Text(
                        currentTime,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  _SideItem(
                    expanded: expanded,
                    icon: Icons.settings_rounded,
                    label: 'Configuración',
                    focusNode: settingsFocus,
                    selected: currentIndex == 5,
                    onKeyEvent: (n, e) => onKeyEvent(n, e, 5),
                    onTap: () => onSelect(5),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  final bool expanded;
  final IconData icon;
  final String label;
  final FocusNode focusNode;
  final bool selected;
  final bool isProfile;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onTap;

  const _SideItem({
    required this.expanded,
    required this.icon,
    required this.label,
    required this.focusNode,
    required this.selected,
    required this.onKeyEvent,
    required this.onTap,
    this.isProfile = false,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKeyEvent(node, event),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 8 : 7,
              vertical: 2,
            ),
            child: GestureDetector(
              onTap: () {
                focusNode.requestFocus();
                onTap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                height: expanded ? 40 : 38,
                padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 0),
                decoration: BoxDecoration(
                  color: selected
                      ? _kSideAccent
                      : hasFocus
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(expanded ? 20 : 10),
                  border: Border.all(
                    color: hasFocus && !selected
                        ? Colors.white.withValues(alpha: 0.65)
                        : Colors.transparent,
                    width: 1.8,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: _kSideAccent.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: expanded
                    ? Row(
                        children: [
                          if (isProfile)
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? Colors.white.withValues(alpha: 0.22)
                                    : Colors.white.withValues(alpha: 0.10),
                              ),
                              child: Icon(
                                icon,
                                size: 14,
                                color:
                                    selected ? Colors.white : Colors.white70,
                              ),
                            )
                          else
                            Icon(
                              icon,
                              size: 18,
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.88),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: isProfile
                            ? Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.1),
                                ),
                                child: Icon(
                                  icon,
                                  size: 14,
                                  color:
                                      Colors.white.withValues(alpha: 0.92),
                                ),
                              )
                            : Icon(
                                icon,
                                size: 20,
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.78),
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

class _ExitDialogBtn extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final bool primary;
  final VoidCallback onTap;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _ExitDialogBtn({
    required this.focusNode,
    required this.label,
    required this.primary,
    required this.onTap,
    this.onLeft,
    this.onRight,
  });

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
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primary
                    ? (hasFocus
                        ? _kAccentColor
                        : _kAccentColor.withValues(alpha: 0.85))
                    : (hasFocus
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.08),
                  width: hasFocus ? 2 : 1,
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