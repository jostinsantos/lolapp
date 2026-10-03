import 'dart:convert';
import 'package:http/http.dart' as http;

class VersionService {
  // ============================================
  // CONFIGURA AQUÍ LA VERSIÓN ACTUAL DE TU APP
  // (la versión con la que estás trabajando ahora)
  // ============================================
  static const String currentVersionName = "1.0.3"; // version_aceptada
  static const int currentVersionCode = 2; // version_code_aceptada (parche)

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


  /// Compara nombres tipo "1.0.3" vs "1.0.2".
  /// Devuelve >0 si a es más nueva, <0 si b es más nueva, 0 si iguales.
  static int compareVersionNames(String a, String b) {
    List<int> parts(String v) {
      final cleaned = v.trim();
      final only = RegExp(r'[0-9]+(?:\.[0-9]+)*').firstMatch(cleaned);
      final s = only?.group(0) ?? cleaned;
      return s
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Verifica si se requiere actualización
  /// Detecta tanto cambio de versión (nombre) como de parche (código)
  static Future<UpdateStatus> checkForUpdate() async {
    final latest = await getLatestAnimeVersion();

    if (latest == null) {
      return UpdateStatus(
        requiresUpdate: false,
        isForceUpdate: false,
        hasVersionUpdate: false,
        hasPatchUpdate: false,
        latestVersion: null,
        message: "No se pudo obtener información de actualización",
      );
    }

    final String remoteName = latest.versionAceptada.trim();
    final int remoteCode = latest.versionCodeAceptada;

    // Parche: código de versión mayor
    final bool hasPatchUpdate = remoteCode > currentVersionCode;

    // Versión por nombre (semver): 1.0.3 > 1.0.2 aunque el code remoto sea menor
    // (evita fallos si la API no incrementa version_code_aceptada).
    final int nameCmp = compareVersionNames(remoteName, currentVersionName);
    final bool hasVersionUpdate =
        remoteName.isNotEmpty && nameCmp > 0;

    // También si el nombre es distinto y el code remoto es >= (caso parche + rename)
    final bool hasNameDiffWithCode =
        remoteName.isNotEmpty &&
        remoteName != currentVersionName &&
        remoteCode >= currentVersionCode;

    final bool needsUpdate =
        hasPatchUpdate || hasVersionUpdate || hasNameDiffWithCode;

    String message;
    if (needsUpdate) {
      final parts = <String>[];
      if (hasVersionUpdate) {
        parts.add("nueva versión ${latest.versionAceptada}");
      }
      if (hasPatchUpdate) {
        parts.add("parche ($remoteCode)");
      }
      message = "Hay actualización disponible: ${parts.join(' y ')}";
    } else {
      message = "Tu aplicación está actualizada";
    }

    return UpdateStatus(
      requiresUpdate: needsUpdate,
      isForceUpdate: needsUpdate,
      hasVersionUpdate: hasVersionUpdate,
      hasPatchUpdate: hasPatchUpdate,
      latestVersion: latest,
      message: message,
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
  final bool hasVersionUpdate;
  final bool hasPatchUpdate;
  final VersionInfo? latestVersion;
  final String message;

  UpdateStatus({
    required this.requiresUpdate,
    required this.isForceUpdate,
    required this.hasVersionUpdate,
    required this.hasPatchUpdate,
    required this.latestVersion,
    required this.message,
  });
}