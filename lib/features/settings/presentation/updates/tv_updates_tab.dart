import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv_config_shared.dart';
import '../../../../core/constants/versiones.dart'; // ← VersionService

class _SocialItem {
  final String name;
  final String url;
  final Color color;
  final String asset;

  const _SocialItem({
    required this.name,
    required this.url,
    required this.color,
    required this.asset,
  });
}

const _kSocials = [
  _SocialItem(
    name: 'Instagram',
    url: 'https://instagram.com/lol_oficialapp',
    color: Color(0xFFE1306C),
    asset: 'assets/redes/instagram.png',
  ),
  _SocialItem(
    name: 'Telegram',
    url: 'https://t.me/lol_oficialapp',
    color: Color(0xFF0088CC),
    asset: 'assets/redes/telegram.png',
  ),
  _SocialItem(
    name: 'TikTok',
    url: 'https://tiktok.com/@lol_oficialapp',
    color: Color(0xFF69C9D0),
    asset: 'assets/redes/tiktok.png',
  ),
];

class ActualizacionesTab extends StatefulWidget {
  final VoidCallback onRequestTabFocus;

  const ActualizacionesTab({
    super.key,
    required this.onRequestTabFocus,
  });

  @override
  State<ActualizacionesTab> createState() => ActualizacionesTabState();
}

class ActualizacionesTabState extends State<ActualizacionesTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingVersion = true;
  bool _hasUpdate = false;
  bool _hasVersionUpdate = false;
  bool _hasPatchUpdate = false;
  bool _isUpToDate = true;
  String? _latestName;
  int? _latestCode;
  String? _latestTitle;
  String? _description;
  String? _error;

  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;

  // URLs por ABI (última versión)
  String? _urlArm64;
  String? _urlArmeabi;
  String? _urlX86;
  String? _urlUniversal;
  String? _urlLegacy;

  /// ABI detectado del dispositivo (óptima)
  String? _detectedAbi;

  /// Preferencia guardada del usuario (última usada)
  String? _preferredAbi;
  static const _prefAbiKey = 'apk_preferred_abi';

  // Preferencias
  bool _recibirActualizaciones = true;
  bool _recibirParches = false;

  // Focus nodes: switches + botón versión + sociales
  late final FocusNode _switchActualizaciones;
  late final FocusNode _switchParches;
  late final FocusNode _btnVersion;
  late final FocusNode _btnVerificar;
  late final List<FocusNode> _socialNodes;

  FocusNode get firstFocusNode => _switchActualizaciones;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _switchActualizaciones = FocusNode(debugLabel: 'cfg_recibir_act');
    _switchParches = FocusNode(debugLabel: 'cfg_recibir_parches');
    _btnVersion = FocusNode(debugLabel: 'cfg_version');
    _btnVerificar = FocusNode(debugLabel: 'cfg_verificar');
    _socialNodes = List.generate(
      _kSocials.length,
      (i) => FocusNode(debugLabel: 'cfg_social_$i'),
    );
    _loadPrefsAndCheck();
  }

  @override
  void dispose() {
    _switchActualizaciones.dispose();
    _switchParches.dispose();
    _btnVersion.dispose();
    _btnVerificar.dispose();
    for (final n in _socialNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void refresh() => _checkVersion();

  void requestFirstFocus() => _switchActualizaciones.requestFocus();

  // ═══════════════════════════════════════════════════════════════════════
  // DETECCIÓN DE ABI
  // ═══════════════════════════════════════════════════════════════════════

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

  Future<void> _loadPrefsAndCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final detected = await _detectDeviceAbi();
    if (!mounted) return;
    setState(() {
      _recibirActualizaciones =
          prefs.getBool('recibir_actualizaciones') ?? true;
      _recibirParches = prefs.getBool('recibir_parches') ?? false;
      _preferredAbi = prefs.getString(_prefAbiKey);
      _detectedAbi = detected;
    });
    await _checkVersion();
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _setRecibirActualizaciones(bool value) async {
    if (!mounted) return;
    setState(() {
      _recibirActualizaciones = value;
      if (!value) _recibirParches = false;
    });
    await _saveBool('recibir_actualizaciones', value);
    if (!value) await _saveBool('recibir_parches', false);
  }

  Future<void> _setRecibirParches(bool value) async {
    if (value) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: kConfigCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Recibir parches',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: const Text(
              'Los parches se publican casi a diario.\n\n'
              'Pueden incluir correcciones rápidas, pero también '
              'cambios experimentales. ¿Deseas activarlos?',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kConfigAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Activar'),
              ),
            ],
          );
        },
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _recibirParches = value);
    await _saveBool('recibir_parches', value);
  }

  // ==================== VERSIÓN (VersionService) ====================
  Future<void> _checkVersion() async {
    setState(() {
      _loadingVersion = true;
      _error = null;
      _downloadError = null;
    });

    try {
      final status = await VersionService.checkForUpdate();

      if (!mounted) return;

      // Asegura ABI detectado
      final detected = _detectedAbi ?? await _detectDeviceAbi();
      if (!mounted) return;

      if (status.latestVersion != null) {
        final v = status.latestVersion!;
        setState(() {
          _detectedAbi = detected;
          _hasUpdate = status.requiresUpdate;
          _hasVersionUpdate = status.hasVersionUpdate;
          _hasPatchUpdate = status.hasPatchUpdate;
          _isUpToDate = !status.requiresUpdate;
          _latestName = v.versionAceptada;
          _latestCode = v.versionCodeAceptada;
          _latestTitle = status.requiresUpdate ? status.message : null;
          _description = v.novedades.isNotEmpty ? v.novedades : null;

          // URLs por arquitectura
          _urlArm64 = v.urlApkArm64;
          _urlArmeabi = v.urlApkArmeabi;
          _urlX86 = v.urlApkX86;
          _urlUniversal = v.urlApkUniversal;
          _urlLegacy =
              v.urlApk.trim().isNotEmpty ? v.urlApk.trim() : null;

          _loadingVersion = false;
        });
      } else {
        setState(() {
          _detectedAbi = detected;
          _hasUpdate = false;
          _hasVersionUpdate = false;
          _hasPatchUpdate = false;
          _isUpToDate = true;
          _latestName = null;
          _latestCode = null;
          _latestTitle = null;
          _description = null;
          _urlArm64 = null;
          _urlArmeabi = null;
          _urlX86 = null;
          _urlUniversal = null;
          _urlLegacy = null;
          _error = status.message.contains('No se pudo')
              ? 'Sin conexión'
              : null;
          _loadingVersion = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexión';
        _loadingVersion = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS ABI
  // ═══════════════════════════════════════════════════════════════════════

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
        if (_urlLegacy != null && _urlLegacy!.trim().isNotEmpty) {
          return _urlLegacy!.trim();
        }
        return null;
      default:
        return null;
    }
  }

  bool get _hasAnyApkUrl =>
      _urlForAbi('arm64') != null ||
      _urlForAbi('armeabi') != null ||
      _urlForAbi('x86') != null ||
      _urlForAbi('universal') != null;

  /// Abre modal de arquitectura (D-pad) y devuelve el ABI elegido.
  Future<String?> _pickAbi() async {
    if (!mounted) return null;

    final detected = _detectedAbi ?? await _detectDeviceAbi();
    if (!mounted) return null;

    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => _AbiPickerDialog(
        preferredAbi: _preferredAbi,
        detectedAbi: detected,
        urlForAbi: _urlForAbi,
        labelAbi: _labelAbi,
        accent: kConfigAccent,
      ),
    );

    return selected;
  }

  Future<void> _onVersionTap() async {
    if (_downloading) return;

    if (_hasUpdate && _hasAnyApkUrl) {
      await _startDownloadFlow();
    } else {
      await _checkVersion();
    }
  }

  Future<void> _startDownloadFlow() async {
    final selected = await _pickAbi();
    if (selected == null || !mounted) {
      // Restaurar foco al botón de versión
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _btnVersion.requestFocus();
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

    // Guarda preferencia
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAbiKey, selected);

    if (!mounted) return;
    setState(() {
      _preferredAbi = selected;
      _downloadError = null;
    });

    await _downloadAndInstallApk(url);
  }

  Future<void> _downloadAndInstallApk(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      setState(() => _downloadError = 'No hay enlace de descarga');
      return;
    }

    if (!Platform.isAndroid) {
      await openExternalUrl(trimmed);
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
        trimmed,
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
              : 'Activa “Instalar apps desconocidas” e inténtalo de nuevo.';
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

  void _openSocialQr(_SocialItem social) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) {
        return PopScope(
          canPop: true,
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack ||
                  key == LogicalKeyboardKey.backspace ||
                  key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter) {
                Navigator.of(ctx).pop();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Container(
                  width: 280,
                  height: 280,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: social.url,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      if (!mounted) return;
      final i = _kSocials.indexWhere((s) => s.url == social.url);
      if (i >= 0 && i < _socialNodes.length) {
        _socialNodes[i].requestFocus();
      }
    });
  }

  // ---------- UI helpers TV ----------

  Widget _buildSwitchRow({
    required FocusNode focusNode,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VoidCallback onArrowUp,
    required VoidCallback onArrowDown,
    Color? accent,
  }) {
    final color = accent ?? kConfigAccent;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onRequestTabFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onChanged(!value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          final ctx = focusNode.context;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.2,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: kConfigCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.08),
                  width: hasFocus ? 2.5 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeColor: color,
                    activeTrackColor: color.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Tarjeta informativa: arquitectura del dispositivo.
  Widget _buildDeviceInfoCard() {
    final detected = _detectedAbi;
    final preferred = _preferredAbi;

    final detectedLabel =
        detected != null ? _labelAbi(detected) : 'Detectando…';
    final preferredLabel =
        preferred != null ? _labelAbi(preferred) : null;

    final willUse = preferred ?? detected;
    final willUseLabel = willUse != null ? _labelAbi(willUse) : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kConfigCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.memory_rounded,
                color: kConfigAccent,
                size: 22,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Arquitectura de tu dispositivo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            'Tu dispositivo soporta',
            detectedLabel,
            highlight: true,
          ),
          if (preferredLabel != null) ...[
            const SizedBox(height: 6),
            _buildInfoRow('Última elegida por ti', preferredLabel),
          ],
          const SizedBox(height: 6),
          _buildInfoRow(
            'Se descargará',
            willUseLabel,
            accent: true,
          ),
          const SizedBox(height: 8),
          Text(
            'Al pulsar Descargar podrás confirmar o cambiar la arquitectura antes de bajar el APK.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value,
      {bool highlight = false, bool accent = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: accent
                ? kConfigAccent.withValues(alpha: 0.2)
                : (highlight
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: accent
                  ? kConfigAccent
                  : (highlight ? Colors.white : Colors.white70),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  String _statusSubtitle() {
    if (_loadingVersion) return 'Comprobando…';
    if (_downloading) {
      final pct = (_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);
      return _downloadProgress > 0.02
          ? 'Descargando $pct%'
          : 'Descargando…';
    }
    if (_hasUpdate) {
      final parts = <String>[];
      if (_hasVersionUpdate && _latestName != null) {
        parts.add('Versión $_latestName');
      }
      if (_hasPatchUpdate && _latestCode != null) {
        parts.add('Parche $_latestCode');
      }
      if (parts.isEmpty) return 'Nueva actualización disponible';
      return parts.join(' · ');
    }
    return 'Estás al día';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ----- Preferencias -----
        sectionTitle('PREFERENCIAS', first: true),
        _buildSwitchRow(
          focusNode: _switchActualizaciones,
          title: 'Recibir actualizaciones',
          subtitle:
              'Avisos cuando haya una nueva versión o parche disponible',
          value: _recibirActualizaciones,
          onChanged: (v) => _setRecibirActualizaciones(v),
          onArrowUp: widget.onRequestTabFocus,
          onArrowDown: () {
            if (_recibirActualizaciones) {
              _switchParches.requestFocus();
            } else {
              _btnVerificar.requestFocus();
            }
          },
        ),
        if (_recibirActualizaciones)
          _buildSwitchRow(
            focusNode: _switchParches,
            title: 'Recibir parches',
            subtitle:
                'Los parches se publican casi a diario. Pueden incluir cambios experimentales.',
            value: _recibirParches,
            onChanged: (v) => _setRecibirParches(v),
            accent: Colors.orangeAccent,
            onArrowUp: () => _switchActualizaciones.requestFocus(),
            onArrowDown: () => _btnVerificar.requestFocus(),
          ),

        // ----- Arquitectura del dispositivo -----
        sectionTitle('ARQUITECTURA'),
        _buildDeviceInfoCard(),

        // ----- Versión / estado -----
        sectionTitle('VERSIÓN'),
        // Botón verificar
        Focus(
          focusNode: _btnVerificar,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowUp) {
              if (_recibirActualizaciones) {
                _switchParches.requestFocus();
              } else {
                _switchActualizaciones.requestFocus();
              }
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowDown) {
              _btnVersion.requestFocus();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowLeft) {
              widget.onRequestTabFocus();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter) {
              if (!_loadingVersion && !_downloading) _checkVersion();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          onFocusChange: (hasFocus) {
            if (hasFocus) {
              final ctx = _btnVerificar.context;
              if (ctx != null) {
                Scrollable.ensureVisible(
                  ctx,
                  alignment: 0.2,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            }
          },
          child: Builder(
            builder: (context) {
              final hasFocus = Focus.of(context).hasFocus;
              return GestureDetector(
                onTap: (_loadingVersion || _downloading)
                    ? null
                    : () => _checkVersion(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: kConfigCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasFocus
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.08),
                      width: hasFocus ? 2.5 : 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        color: kConfigAccent,
                        size: 22,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _loadingVersion
                              ? 'Verificando…'
                              : 'Verificar actualización',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_loadingVersion)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white54,
                          ),
                        )
                      else
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withValues(alpha: 0.35),
                          size: 22,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Tarjeta de versión / descarga
        _VersionCard(
          focusNode: _btnVersion,
          loading: _loadingVersion,
          downloading: _downloading,
          downloadProgress: _downloadProgress,
          hasUpdate: _hasUpdate,
          hasVersionUpdate: _hasVersionUpdate,
          hasPatchUpdate: _hasPatchUpdate,
          isUpToDate: _isUpToDate,
          currentName: VersionService.currentVersionName,
          currentCode: VersionService.currentVersionCode,
          latestName: _latestName,
          latestCode: _latestCode,
          latestTitle: _latestTitle,
          description: _description,
          statusSubtitle: _statusSubtitle(),
          error: _error ?? _downloadError,
          onTap: _onVersionTap,
          onArrowUp: () => _btnVerificar.requestFocus(),
          onArrowDown: () {
            if (_socialNodes.isNotEmpty) _socialNodes[0].requestFocus();
          },
          onArrowLeft: widget.onRequestTabFocus,
        ),
        sectionTitle('REDES'),
        ...List.generate(_kSocials.length, (i) {
          final s = _kSocials[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Focus(
              focusNode: _socialNodes[i],
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.arrowUp) {
                  if (i == 0) {
                    _btnVersion.requestFocus();
                  } else {
                    _socialNodes[i - 1].requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  if (i < _socialNodes.length - 1) {
                    _socialNodes[i + 1].requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowLeft) {
                  widget.onRequestTabFocus();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.enter) {
                  _openSocialQr(s);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              onFocusChange: (hasFocus) {
                if (hasFocus) {
                  final ctx = _socialNodes[i].context;
                  if (ctx != null) {
                    Scrollable.ensureVisible(
                      ctx,
                      alignment: 0.2,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                }
              },
              child: Builder(
                builder: (context) {
                  final hasFocus = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: () => _openSocialQr(s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: kConfigCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: hasFocus
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.08),
                          width: hasFocus ? 2.5 : 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Image.asset(
                            s.asset,
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.link_rounded,
                              color: s.color,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Escanear QR · ${s.name}',
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.45),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.35),
                            size: 22,
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
        const SizedBox(height: 24),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Modal arquitectura (TV) — foco D-pad
// ═══════════════════════════════════════════════════════════════════════════

class _AbiPickerDialog extends StatefulWidget {
  final String? preferredAbi;
  final String? detectedAbi;
  final String? Function(String abi) urlForAbi;
  final String Function(String abi) labelAbi;
  final Color accent;

  const _AbiPickerDialog({
    required this.preferredAbi,
    required this.detectedAbi,
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
  late final List<int> _enabledIndexes;

  @override
  void initState() {
    super.initState();
    _nodes =
        List.generate(_options.length, (i) => FocusNode(debugLabel: 'abi_$i'));
    _enabledIndexes = [];
    for (var i = 0; i < _options.length; i++) {
      if (widget.urlForAbi(_options[i]['id']!) != null) {
        _enabledIndexes.add(i);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      int focusIdx = 0;
      bool resolved = false;

      if (widget.preferredAbi != null) {
        final i = _options.indexWhere((o) => o['id'] == widget.preferredAbi);
        if (i >= 0 && widget.urlForAbi(_options[i]['id']!) != null) {
          focusIdx = i;
          resolved = true;
        }
      }

      if (!resolved && widget.detectedAbi != null) {
        final i = _options.indexWhere((o) => o['id'] == widget.detectedAbi);
        if (i >= 0 && widget.urlForAbi(_options[i]['id']!) != null) {
          focusIdx = i;
          resolved = true;
        }
      }

      if (!resolved && _enabledIndexes.isNotEmpty) {
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
                widget.detectedAbi != null
                    ? 'La más óptima para tu dispositivo es: ${widget.labelAbi(widget.detectedAbi!)}'
                    : (widget.preferredAbi != null
                        ? 'Última usada: ${widget.labelAbi(widget.preferredAbi!)}'
                        : 'Se recordará tu elección en este dispositivo'),
                style: TextStyle(
                  color: widget.detectedAbi != null
                      ? widget.accent.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: widget.detectedAbi != null
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(_options.length, (i) {
                final o = _options[i];
                final id = o['id']!;
                final hasUrl = widget.urlForAbi(id) != null;
                final isPreferred = widget.preferredAbi == id;
                final isRecommended = widget.detectedAbi == id;

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
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              o['title']!,
                                              style: TextStyle(
                                                color: hasUrl
                                                    ? Colors.white
                                                    : Colors.white38,
                                                fontSize: 15,
                                                fontWeight:
                                                    hasFocus || isPreferred
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          if (isRecommended && hasUrl) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: widget.accent
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Óptima para tu dispositivo',
                                                style: TextStyle(
                                                  color: widget.accent,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
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

class _VersionCard extends StatelessWidget {
  final FocusNode focusNode;
  final bool loading;
  final bool downloading;
  final double downloadProgress;
  final bool hasUpdate;
  final bool hasVersionUpdate;
  final bool hasPatchUpdate;
  final bool isUpToDate;
  final String currentName;
  final int currentCode;
  final String? latestName;
  final int? latestCode;
  final String? latestTitle;
  final String? description;
  final String statusSubtitle;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;
  final VoidCallback? onArrowLeft;

  const _VersionCard({
    required this.focusNode,
    required this.loading,
    required this.downloading,
    required this.downloadProgress,
    required this.hasUpdate,
    required this.hasVersionUpdate,
    required this.hasPatchUpdate,
    required this.isUpToDate,
    required this.currentName,
    required this.currentCode,
    required this.latestName,
    required this.latestCode,
    required this.latestTitle,
    required this.description,
    required this.statusSubtitle,
    required this.error,
    required this.onTap,
    required this.onArrowUp,
    required this.onArrowDown,
    this.onArrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onArrowLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          if (!downloading) onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          final ctx = focusNode.context;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.2,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: downloading ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kConfigCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.08),
                  width: hasFocus ? 2.5 : 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: hasUpdate
                              ? kConfigAccent.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          hasUpdate
                              ? Icons.system_update_rounded
                              : Icons.check_circle_outline_rounded,
                          color:
                              hasUpdate ? kConfigAccent : Colors.greenAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusSubtitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Actual: $currentName  ·  Parche: $currentCode',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12.5,
                              ),
                            ),
                            if (hasUpdate) ...[
                              if (hasVersionUpdate && latestName != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Nueva versión: $latestName',
                                  style: TextStyle(
                                    color: kConfigAccent.withValues(alpha: 0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (hasPatchUpdate && latestCode != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Nuevo parche: $latestCode',
                                  style: TextStyle(
                                    color: Colors.orangeAccent
                                        .withValues(alpha: 0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                            if (error != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                error!,
                                style: TextStyle(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.9),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (downloading)
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            value: downloadProgress > 0.02
                                ? downloadProgress
                                : null,
                            strokeWidth: 2.5,
                            color: kConfigAccent,
                          ),
                        )
                      else if (hasUpdate)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: kConfigAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Descargar',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.refresh_rounded,
                          color: Colors.white.withValues(alpha: 0.35),
                          size: 22,
                        ),
                    ],
                  ),
                  if (description != null &&
                      description!.isNotEmpty &&
                      hasUpdate) ...[
                    const SizedBox(height: 12),
                    Text(
                      description!.replaceAll('\\n', '\n'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (downloading) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:
                            downloadProgress > 0.02 ? downloadProgress : null,
                        backgroundColor: Colors.white12,
                        color: kConfigAccent,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}