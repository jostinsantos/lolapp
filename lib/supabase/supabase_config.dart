import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache local de sesión de perfil + modo invitado.
///
/// - Si el usuario entra como invitado → todo se guarda solo en local.
/// - Si tiene cuenta + perfil seleccionado → se sincroniza con Supabase.
class SupabaseConfig {
  static const String _kProfileId = 'current_profile_id';
  static const String _kProfileName = 'current_profile_name';
  static const String _kProfileAvatar = 'current_profile_avatar';
  static const String _kProfileBackdrop = 'current_profile_backdrop';
  static const String _kIsGuest = 'is_guest_mode';
  static const String _kLocalProfiles = 'local_profiles_cache';

  // ─── Perfil actual ───────────────────────────────────────────────────────

  static Future<String?> getCurrentProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kProfileId);
  }

  static Future<String?> getCurrentProfileName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kProfileName);
  }

  static Future<String?> getCurrentProfileAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kProfileAvatar);
  }

  static Future<String?> getCurrentProfileBackdrop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kProfileBackdrop);
  }

  static Future<void> setCurrentProfile({
    required String id,
    required String name,
    String? avatarUrl,
    String? backdropUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfileId, id);
    await prefs.setString(_kProfileName, name);
    if (avatarUrl != null) {
      await prefs.setString(_kProfileAvatar, avatarUrl);
    } else {
      await prefs.remove(_kProfileAvatar);
    }
    if (backdropUrl != null) {
      await prefs.setString(_kProfileBackdrop, backdropUrl);
    } else {
      await prefs.remove(_kProfileBackdrop);
    }
    await prefs.setBool(_kIsGuest, false);
  }

  static Future<void> clearCurrentProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfileId);
    await prefs.remove(_kProfileName);
    await prefs.remove(_kProfileAvatar);
    await prefs.remove(_kProfileBackdrop);
  }

  // ─── Modo invitado ───────────────────────────────────────────────────────

  static Future<bool> isGuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIsGuest) ?? false;
  }

  static Future<void> setGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsGuest, true);
    await prefs.remove(_kProfileId);
    await prefs.remove(_kProfileName);
    await prefs.remove(_kProfileAvatar);
    await prefs.remove(_kProfileBackdrop);
  }

  static Future<void> clearGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsGuest, false);
  }

  // ─── Cache local de perfiles ─────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getLocalProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLocalProfiles);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLocalProfiles(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocalProfiles, jsonEncode(list));
  }

  static Future<void> addLocalProfile(Map<String, dynamic> profile) async {
    final list = await getLocalProfiles();
    list.removeWhere((p) => p['id'] == profile['id']);
    list.add(profile);
    await saveLocalProfiles(list);
  }

  static Future<void> removeLocalProfile(String id) async {
    final list = await getLocalProfiles();
    list.removeWhere((p) => p['id'] == id);
    await saveLocalProfiles(list);
  }

  static Future<void> clearLocalProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLocalProfiles);
  }

  // ─── Compatibilidad con código antiguo ─────────────────────────────────

  /// true si hay sesión de perfil o modo invitado activo
  static Future<bool> isSupabaseActive() async {
    final id = await getCurrentProfileId();
    final guest = await isGuest();
    return id != null || guest;
  }

  /// Alias de getCurrentProfileName
  static Future<String?> getCurrentUserName() => getCurrentProfileName();

  /// Alias de getCurrentProfileId
  static Future<String?> getCurrentUserId() => getCurrentProfileId();

  /// true si hay perfil seleccionado (no invitado)
  static Future<bool> isLoggedIn() async {
    final id = await getCurrentProfileId();
    return id != null;
  }

  /// En el sistema central siempre hay "credenciales" (las del dev)
  static Future<bool> hasCredentials() async => true;

  static Future<bool> getAskProfileEveryLaunch() async => false;

  static Future<void> setAskProfileEveryLaunch(bool v) async {}
}
