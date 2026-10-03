import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuración local de Supabase.
/// Supabase es 100 % OPCIONAL:
/// - Sin URL/KEY → la app funciona solo con cache local (como siempre).
/// - Con URL/KEY + usuario logueado → guardados y perfiles van a Supabase.
/// El cache local NUNCA se borra al activar Supabase.
class SupabaseConfig {
  static const String _kUrl = 'supabase_url';
  static const String _kAnonKey = 'supabase_anon_key';
  static const String _kUserId = 'supabase_user_id';
  static const String _kUserName = 'supabase_user_name';
  static const String _kProfiles = 'supabase_local_profiles';

  // ─── URL y ANON KEY ───────────────────────────────────────────────────────

  static Future<String?> getUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUrl);
  }

  static Future<String?> getAnonKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAnonKey);
  }

  static Future<void> setCredentials({
    required String url,
    required String anonKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl, url.trim());
    await prefs.setString(_kAnonKey, anonKey.trim());
  }

  /// Borra solo las credenciales y la sesión de usuario.
  /// NO toca el cache local de guardados (guardados_items).
  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUrl);
    await prefs.remove(_kAnonKey);
    await prefs.remove(_kUserId);
    await prefs.remove(_kUserName);
  }

  static Future<bool> hasCredentials() async {
    final url = await getUrl();
    final key = await getAnonKey();
    return url != null && url.isNotEmpty && key != null && key.isNotEmpty;
  }

  // ─── Usuario actual (sesión cacheada) ─────────────────────────────────────

  static Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserId);
  }

  static Future<String?> getCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserName);
  }

  static Future<void> setCurrentUser({
    required String userId,
    required String userName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, userId);
    await prefs.setString(_kUserName, userName);
  }

  static Future<void> clearCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
    await prefs.remove(_kUserName);
  }

  static Future<bool> isLoggedIn() async {
    final id = await getCurrentUserId();
    return id != null && id.isNotEmpty;
  }

  /// true solo si hay URL+KEY configurados Y hay un perfil seleccionado.
  /// En ese caso la app usa Supabase para guardados/perfiles.
  /// Si es false → todo sigue en cache local (comportamiento original).
  static Future<bool> isSupabaseActive() async {
    return await hasCredentials() && await isLoggedIn();
  }

  static const String _kAskProfileEveryLaunch = 'supabase_ask_profile_every_launch';

  /// true → cada arranque pide perfil (solo si Supabase activo).
  /// false → usa el último perfil en cache.
  static Future<bool> getAskProfileEveryLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAskProfileEveryLaunch) ?? true; // por defecto: pedir perfil
  }

  static Future<void> setAskProfileEveryLaunch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAskProfileEveryLaunch, value);
  }

  // ─── Perfiles locales (cache de lista) ────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getLocalProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kProfiles) ?? [];
    return raw
        .map((e) {
          try {
            return Map<String, dynamic>.from(jsonDecode(e));
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  static Future<void> saveLocalProfiles(
      List<Map<String, dynamic>> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = profiles.map((p) => jsonEncode(p)).toList();
    await prefs.setStringList(_kProfiles, encoded);
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
}
