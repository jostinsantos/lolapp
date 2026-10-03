import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/versiones.dart';
import '../config_shared.dart';

/// Página de Actualizaciones
/// - Interruptor: recibir actualizaciones
/// - Si está activo: interruptor de recibir parches (con advertencia)
/// - Descargar última actualización (según arquitectura del dispositivo)
/// - Verificar estado (versión + parche)
class ActualizacionesPage extends StatefulWidget {
  const ActualizacionesPage({super.key});

  @override
  State<ActualizacionesPage> createState() => _ActualizacionesPageState();
}

class _ActualizacionesPageState extends State<ActualizacionesPage> {
  bool _loading = true;
  bool _recibirActualizaciones = true;
  bool _recibirParches = false;

  bool _checking = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;
  String? _checkError;

  UpdateStatus? _status;
  VersionInfo? _latest;

  /// ABI detectado del dispositivo (arm64 | armeabi | x86 | universal)
  String? _detectedAbi;

  /// Preferencia guardada del usuario (última usada)
  String? _preferredAbi;
  static const _prefAbiKey = 'apk_preferred_abi';

  @override
  void initState() {
    super.initState();
    _loadSettingsAndCheck();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DETECCIÓN DE ABI
  // ═══════════════════════════════════════════════════════════════════════

  /// Devuelve el ABI óptimo del dispositivo.
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
  // CARGA INICIAL
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _loadSettingsAndCheck() async {
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
    await _checkUpdate(silent: true);
    if (mounted) setState(() => _loading = false);
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
        builder: (context) => AlertDialog(
          backgroundColor: kCardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancelar',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Activar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _recibirParches = value);
    await _saveBool('recibir_parches', value);
  }

  Future<void> _checkUpdate({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _checking = true;
        _checkError = null;
      });
    }

    try {
      final status = await VersionService.checkForUpdate();
      if (!mounted) return;

      // Asegura ABI detectado
      final detected = _detectedAbi ?? await _detectDeviceAbi();
      if (!mounted) return;

      setState(() {
        _status = status;
        _latest = status.latestVersion;
        _detectedAbi = detected;
        _checking = false;
        if (status.latestVersion == null &&
            status.message.contains('No se pudo')) {
          _checkError = 'Sin conexión o no se pudo obtener la información';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkError = 'Error al verificar: $e';
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
    final v = _latest;
    if (v == null) return null;
    switch (abi) {
      case 'arm64':
        return (v.urlApkArm64 != null && v.urlApkArm64!.trim().isNotEmpty)
            ? v.urlApkArm64!.trim()
            : null;
      case 'armeabi':
        return (v.urlApkArmeabi != null &&
                v.urlApkArmeabi!.trim().isNotEmpty)
            ? v.urlApkArmeabi!.trim()
            : null;
      case 'x86':
        return (v.urlApkX86 != null && v.urlApkX86!.trim().isNotEmpty)
            ? v.urlApkX86!.trim()
            : null;
      case 'universal':
        if (v.urlApkUniversal != null &&
            v.urlApkUniversal!.trim().isNotEmpty) {
          return v.urlApkUniversal!.trim();
        }
        if (v.urlApk.trim().isNotEmpty) return v.urlApk.trim();
        return null;
      default:
        return null;
    }
  }

  /// Abre modal de arquitectura y devuelve el ABI elegido.
  Future<String?> _pickAbi() async {
    if (!mounted) return null;

    final detected = _detectedAbi ?? await _detectDeviceAbi();
    if (!mounted) return null;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kCardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                  detected != null
                      ? 'La más óptima para tu dispositivo es: ${_labelAbi(detected)}'
                      : 'Se recordará tu elección',
                  style: TextStyle(
                    color: detected != null
                        ? kAccentColor.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight:
                        detected != null ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map((o) {
                  final id = o['id']!;
                  final hasUrl = _urlForAbi(id) != null;
                  final isPreferred = _preferredAbi == id;
                  final isRecommended = detected == id;

                  return ListTile(
                    enabled: hasUrl,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isPreferred
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isPreferred
                          ? kAccentColor
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
                              color: kAccentColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Óptima para tu dispositivo',
                              style: TextStyle(
                                color: kAccentColor,
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
                              color: kAccentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Anterior',
                              style: TextStyle(
                                color: kAccentColor,
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

    return selected;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DESCARGA / INSTALACIÓN
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _startDownloadFlow() async {
    final selected = await _pickAbi();
    if (selected == null || !mounted) return;

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
      await _openDownload(trimmed);
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

  Future<void> _openDownload(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error abriendo enlace: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace'),
            backgroundColor: Color(0xFF1a1a1a),
          ),
        );
      }
    }
  }

  String _statusText() {
    if (_status == null) return 'Pulsa “Verificar” para comprobar.';
    if (_status!.latestVersion == null) {
      return _checkError ?? _status!.message;
    }

    final v = _status!.latestVersion!;
    final parts = <String>[];

    if (_status!.hasVersionUpdate) {
      parts.add(
        'Nueva versión: ${v.versionAceptada} (tienes ${VersionService.currentVersionName})',
      );
    }
    if (_status!.hasPatchUpdate) {
      parts.add(
        'Nuevo parche: ${v.versionCodeAceptada} (tienes ${VersionService.currentVersionCode})',
      );
    }

    if (parts.isEmpty) {
      return 'Estás al día\n'
          'Versión: ${VersionService.currentVersionName}\n'
          'Parche: ${VersionService.currentVersionCode}';
    }

    return parts.join('\n');
  }

  /// URL de descarga legacy (universal) — usado como fallback informativo.
  String? get _fallbackUniversalUrl {
    final v = _latest;
    if (v == null) return null;
    return v.urlApkUniversal ??
        (v.urlApk.trim().isNotEmpty ? v.urlApk : null);
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? accent,
  }) {
    final color = accent ?? kAccentColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: color,
        activeTrackColor: color.withValues(alpha: 0.4),
      ),
    );
  }

  /// Tarjeta informativa: arquitectura del dispositivo y APK que se descargará.
  Widget _buildDeviceInfoCard() {
    final detected = _detectedAbi;
    final preferred = _preferredAbi;

    final detectedLabel =
        detected != null ? _labelAbi(detected) : 'Detectando…';
    final preferredLabel =
        preferred != null ? _labelAbi(preferred) : null;

    final willUse = preferred ?? detected;
    final willUseLabel =
        willUse != null ? _labelAbi(willUse) : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kAccentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.memory_rounded,
                  color: kAccentColor,
                  size: 20,
                ),
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
          const SizedBox(height: 12),
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
                ? kAccentColor.withValues(alpha: 0.2)
                : (highlight
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: accent
                  ? kAccentColor
                  : (highlight ? Colors.white : Colors.white70),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool loading = false,
    Color? color,
  }) {
    final c = color ?? kAccentColor;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: c,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      value: _downloadProgress > 0.02
                          ? _downloadProgress
                          : null,
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _downloadProgress > 0.02
                        ? 'Descargando ${(_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%'
                        : 'Descargando…',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final hasUpdate = _status?.requiresUpdate == true;
    final hasAnyApkUrl = (_urlForAbi('arm64') ??
            _urlForAbi('armeabi') ??
            _urlForAbi('x86') ??
            _urlForAbi('universal') ??
            _fallbackUniversalUrl) !=
        null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: kAccentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.system_update_rounded,
                color: kAccentColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Actualizaciones',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, 40.0 + bottomSafe),
              children: [
                // ----- Preferencias -----
                _buildSwitchTile(
                  title: 'Recibir actualizaciones',
                  subtitle:
                      'Avisos cuando haya una nueva versión o parche disponible',
                  value: _recibirActualizaciones,
                  onChanged: (v) => _setRecibirActualizaciones(v),
                ),
                if (_recibirActualizaciones)
                  _buildSwitchTile(
                    title: 'Recibir parches',
                    subtitle:
                        'Los parches se publican casi a diario. Pueden incluir correcciones rápidas o cambios experimentales.',
                    value: _recibirParches,
                    onChanged: (v) => _setRecibirParches(v),
                    accent: Colors.orangeAccent,
                  ),

                const SizedBox(height: 8),

                // ----- Arquitectura del dispositivo -----
                _buildDeviceInfoCard(),

                // ----- Estado actual -----
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: hasUpdate
                          ? kAccentColor.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hasUpdate
                                ? Icons.system_update_rounded
                                : Icons.check_circle_outline_rounded,
                            color: hasUpdate
                                ? kAccentColor
                                : Colors.greenAccent,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              hasUpdate
                                  ? 'Actualización disponible'
                                  : 'Estado de la app',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Versión actual: ${VersionService.currentVersionName}  ·  Parche: ${VersionService.currentVersionCode}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusText(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      if (_latest != null &&
                          _latest!.novedades.trim().isNotEmpty &&
                          hasUpdate) ...[
                        const SizedBox(height: 12),
                        Text(
                          _latest!.novedades.replaceAll('\\n', '\n'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (_checkError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _checkError!,
                          style: const TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 12,
                          ),
                        ),
                      ],
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
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _downloadProgress > 0.02
                                ? _downloadProgress
                                : null,
                            backgroundColor: Colors.white12,
                            color: kAccentColor,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ----- Acciones -----
                _buildActionButton(
                  label: _checking ? 'Verificando…' : 'Verificar actualización',
                  icon: Icons.refresh_rounded,
                  onPressed: _checking || _downloading
                      ? null
                      : () => _checkUpdate(),
                  loading: _checking,
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  label: 'Descargar última actualización',
                  icon: Icons.download_rounded,
                  onPressed: (_downloading || !hasUpdate || !hasAnyApkUrl)
                      ? null
                      : _startDownloadFlow,
                  loading: _downloading,
                ),
              ],
            ),
    );
  }
}