import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'supabase_config.dart';
import 'supabase_auth.dart';

/// Gestión de PERFILES (hasta 5 por cuenta).
/// Cada perfil: name, avatar_url, backdrop_url, pin, settings (JSON).
class SupabaseProfiles {
  static SupabaseClient? get _c => AppSupabase.client;

  /// Lista todos los perfiles de la cuenta actual
  static Future<List<Map<String, dynamic>>> list() async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null || !SupabaseAuth.isLoggedIn) {
      return SupabaseConfig.getLocalProfiles();
    }

    try {
      final res = await _c!
          .from('profiles')
          .select('id, name, avatar_url, backdrop_url, pin, settings, created_at, updated_at')
          .eq('account_id', AppSupabase.currentUser!.id)
          .order('created_at');

      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      await SupabaseConfig.saveLocalProfiles(list);
      return list;
    } catch (_) {
      return SupabaseConfig.getLocalProfiles();
    }
  }

  /// Crear perfil (máximo 5)
  static Future<Map<String, dynamic>?> create({
    required String name,
    String? avatarUrl,
    String? backdropUrl,
    String? pin,
    Map<String, dynamic>? settings,
  }) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null || !SupabaseAuth.isLoggedIn) return null;

    try {
      final data = <String, dynamic>{
        'account_id': AppSupabase.currentUser!.id,
        'name': name.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (backdropUrl != null) 'backdrop_url': backdropUrl,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
        'settings': settings ?? {},
      };

      final res = await _c!
          .from('profiles')
          .insert(data)
          .select('id, name, avatar_url, backdrop_url, pin, settings, created_at, updated_at')
          .single();

      final profile = Map<String, dynamic>.from(res as Map);
      await SupabaseConfig.addLocalProfile(profile);
      return profile;
    } catch (_) {
      return null;
    }
  }

  /// Actualizar perfil (nombre, avatar, backdrop, pin, settings)
  static Future<bool> update({
    required String id,
    String? name,
    String? avatarUrl,
    String? backdropUrl,
    String? pin,
    Map<String, dynamic>? settings,
  }) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null || !SupabaseAuth.isLoggedIn) return false;

    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name.trim();
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;
      if (backdropUrl != null) data['backdrop_url'] = backdropUrl;
      if (pin != null) data['pin'] = pin.isEmpty ? null : pin;
      if (settings != null) data['settings'] = settings;

      if (data.isEmpty) return true;

      await _c!.from('profiles').update(data).eq('id', id);

      // Actualizar cache local
      final list = await SupabaseConfig.getLocalProfiles();
      final idx = list.indexWhere((p) => p['id'] == id);
      if (idx >= 0) {
        if (name != null) list[idx]['name'] = name.trim();
        if (avatarUrl != null) list[idx]['avatar_url'] = avatarUrl;
        if (backdropUrl != null) list[idx]['backdrop_url'] = backdropUrl;
        if (pin != null) list[idx]['pin'] = pin.isEmpty ? null : pin;
        if (settings != null) list[idx]['settings'] = settings;
        await SupabaseConfig.saveLocalProfiles(list);
      }

      // Si es el perfil actual, actualizar también la sesión
      final currentId = await SupabaseConfig.getCurrentProfileId();
      if (currentId == id) {
        await SupabaseConfig.setCurrentProfile(
          id: id,
          name: name ?? (await SupabaseConfig.getCurrentProfileName()) ?? 'Usuario',
          avatarUrl: avatarUrl ?? await SupabaseConfig.getCurrentProfileAvatar(),
          backdropUrl: backdropUrl ?? await SupabaseConfig.getCurrentProfileBackdrop(),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Eliminar perfil
  static Future<bool> delete(String id) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null || !SupabaseAuth.isLoggedIn) return false;

    try {
      await _c!.from('profiles').delete().eq('id', id);
      await SupabaseConfig.removeLocalProfile(id);

      final current = await SupabaseConfig.getCurrentProfileId();
      if (current == id) {
        await SupabaseConfig.clearCurrentProfile();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Seleccionar perfil (iniciar sesión de perfil)
  static Future<bool> select(Map<String, dynamic> profile, {String? pinInput}) async {
    final id = profile['id']?.toString() ?? '';
    final name = profile['name']?.toString() ?? 'Usuario';
    if (id.isEmpty) return false;

    // Verificar PIN si tiene
    final storedPin = profile['pin']?.toString();
    if (storedPin != null && storedPin.isNotEmpty) {
      if (pinInput == null || pinInput != storedPin) {
        return false; // PIN incorrecto
      }
    }

    await SupabaseConfig.setCurrentProfile(
      id: id,
      name: name,
      avatarUrl: profile['avatar_url']?.toString(),
      backdropUrl: profile['backdrop_url']?.toString(),
    );
    return true;
  }

  /// Obtener settings del perfil actual
  static Future<Map<String, dynamic>> getSettings() async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    if (profileId == null) return {};

    final profiles = await list();
    final profile = profiles.firstWhere(
      (p) => p['id'] == profileId,
      orElse: () => {},
    );
    final settings = profile['settings'];
    if (settings is Map) return Map<String, dynamic>.from(settings);
    return {};
  }

  /// Guardar settings del perfil actual (blob JSON)
  static Future<bool> saveSettings(Map<String, dynamic> settings) async {
    final profileId = await SupabaseConfig.getCurrentProfileId();
    if (profileId == null) return false;
    return update(id: profileId, settings: settings);
  }
}
