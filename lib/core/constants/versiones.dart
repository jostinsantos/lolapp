import 'dart:convert';
import 'package:http/http.dart' as http;

class VersionService {
  // ============================================
  // CONFIGURA AQUÍ LA VERSIÓN ACTUAL DE TU APP
  // (la versión con la que estás trabajando ahora)
  // ============================================
  static const String currentVersionName = "1.0.0"; // version_aceptada
  static const int currentVersionCode = 11; // version_code_aceptada

  // URL de tu API
  static const String apiUrl =
      "https://www.modlyo.com/lol/versiones.php?tipo=lol";

  /// Obtiene la última versión de tipo "lol" desde la API
  static Future<VersionInfo?> getLatestAnimeVersion() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

        if (jsonData['success'] == true &&
            jsonData['data'] is List &&
            (jsonData['data'] as List).isNotEmpty) {
          // API ordena por version_code DESC → el primero es el más reciente
          final latest = jsonData['data'][0] as Map<String, dynamic>;
          return VersionInfo.fromJson(latest);
        }
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print("Error al obtener versión: $e");
      return null;
    }
  }

  /// Verifica si se requiere actualización
  static Future<UpdateStatus> checkForUpdate() async {
    final latest = await getLatestAnimeVersion();

    if (latest == null) {
      return UpdateStatus(
        requiresUpdate: false,
        isForceUpdate: false,
        latestVersion: null,
        message: "No se pudo obtener información de actualización",
      );
    }

    final bool needsUpdate = latest.versionCodeAceptada > currentVersionCode;

    return UpdateStatus(
      requiresUpdate: needsUpdate,
      isForceUpdate: needsUpdate,
      latestVersion: latest,
      message: needsUpdate
          ? "Hay una nueva versión disponible: ${latest.versionAceptada}"
          : "Tu aplicación está actualizada",
    );
  }
}

// Modelo de la versión
class VersionInfo {
  final int id;
  final String versionAceptada;
  final int versionCodeAceptada;
  final String novedades;
  final String urlApk; // legacy / fallback
  final String? urlApkArm64; // arm64-v8a
  final String? urlApkArmeabi; // armeabi-v7a
  final String? urlApkX86; // x86 / x86_64
  final String? urlApkUniversal; // APK universal (todas)
  final String tipo;
  final String fechaCreacion;

  VersionInfo({
    required this.id,
    required this.versionAceptada,
    required this.versionCodeAceptada,
    required this.novedades,
    required this.urlApk,
    this.urlApkArm64,
    this.urlApkArmeabi,
    this.urlApkX86,
    this.urlApkUniversal,
    required this.tipo,
    required this.fechaCreacion,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> j) {
    String? _opt(dynamic v) {
      final s = v?.toString().trim();
      return (s != null && s.isNotEmpty) ? s : null;
    }

    return VersionInfo(
      id: int.tryParse('${j['id']}') ?? 0,
      versionAceptada: j['version_aceptada']?.toString() ?? '',
      versionCodeAceptada:
          int.tryParse('${j['version_code_aceptada']}') ?? 0,
      novedades: j['novedades']?.toString() ?? '',
      urlApk: j['url_apk']?.toString() ?? '',
      urlApkArm64: _opt(j['url_apk_arm64']),
      urlApkArmeabi: _opt(j['url_apk_armeabi']),
      urlApkX86: _opt(j['url_apk_x86']),
      urlApkUniversal: _opt(j['url_apk_universal']),
      tipo: j['tipo']?.toString() ?? '',
      fechaCreacion: j['fecha_creacion']?.toString() ?? '',
    );
  }

  /// URL según arquitectura: arm64 | armeabi | x86 | universal
  String? urlForAbi(String abi) {
    switch (abi) {
      case 'arm64':
        return urlApkArm64;
      case 'armeabi':
        return urlApkArmeabi;
      case 'x86':
        return urlApkX86;
      case 'universal':
        return urlApkUniversal ??
            (urlApk.trim().isNotEmpty ? urlApk : null);
      default:
        return null;
    }
  }
}

// Estado de actualización
class UpdateStatus {
  final bool requiresUpdate;
  final bool isForceUpdate;
  final VersionInfo? latestVersion;
  final String message;

  UpdateStatus({
    required this.requiresUpdate,
    required this.isForceUpdate,
    required this.latestVersion,
    required this.message,
  });
}