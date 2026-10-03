import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/addon.dart';

/// Persistencia de addons (fuentes + catálogos) y paquetes Nuvio.
class StorageService {
  static const _addonsKey = 'addons_v1';
  static const _packagesKey = 'source_packages_v1';
  static const _settingsKey = 'addon_settings_v1';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<List<AddonManifest>> loadAddons() async {
    final p = await _prefs;
    final raw = p.getString(_addonsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => AddonManifest.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAddons(List<AddonManifest> addons) async {
    final p = await _prefs;
    final list = addons.map((a) {
      final j = a.toJson();
      final code = j['rawCode']?.toString() ?? '';
      if (code.length > 80000) {
        j['rawCode'] = null;
      }
      return j;
    }).toList();
    await p.setString(_addonsKey, jsonEncode(list));
  }

  Future<List<SourcePackage>> loadPackages() async {
    final p = await _prefs;
    final raw = p.getString(_packagesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SourcePackage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePackages(List<SourcePackage> packages) async {
    final p = await _prefs;
    await p.setString(
      _packagesKey,
      jsonEncode(packages.map((e) => e.toJson()).toList()),
    );
  }

  Future<Map<String, dynamic>> loadSettings() async {
    final p = await _prefs;
    final raw = p.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final p = await _prefs;
    await p.setString(_settingsKey, jsonEncode(settings));
  }
}
