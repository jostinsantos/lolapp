import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'supabase_config.dart';

/// CRUD de perfiles/usuarios en la tabla `profiles` de Supabase.
///
/// Estructura esperada de la tabla `profiles`:
/// ```sql
/// create table public.profiles (
///   id uuid primary key default gen_random_uuid(),
///   name text not null,
///   avatar_url text,
///   created_at timestamptz default now()
/// );
/// ```
class SupabaseUsers {
  static SupabaseClient? get _c => AppSupabase.client;

  /// Lista todos los perfiles.
  static Future<List<Map<String, dynamic>>> list() async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return [];

    try {
      final res = await _c!
          .from('profiles')
          .select('id, name, avatar_url, created_at')
          .order('created_at', ascending: true);

      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Cache local
      await SupabaseConfig.saveLocalProfiles(list);
      return list;
    } catch (e) {
      // Fallback a cache local
      return SupabaseConfig.getLocalProfiles();
    }
  }

  /// Crea un nuevo perfil. Devuelve el mapa creado (con id).
  static Future<Map<String, dynamic>?> create({
    required String name,
    String? avatarUrl,
  }) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return null;

    try {
      final res = await _c!
          .from('profiles')
          .insert({
            'name': name.trim(),
            if (avatarUrl != null) 'avatar_url': avatarUrl,
          })
          .select('id, name, avatar_url, created_at')
          .single();

      final profile = Map<String, dynamic>.from(res as Map);
      await SupabaseConfig.addLocalProfile(profile);
      return profile;
    } catch (e) {
      return null;
    }
  }

  /// Edita un perfil existente.
  static Future<bool> update({
    required String id,
    String? name,
    String? avatarUrl,
  }) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return false;

    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name.trim();
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;

      if (data.isEmpty) return true;

      await _c!.from('profiles').update(data).eq('id', id);

      // Actualizar cache local
      final list = await SupabaseConfig.getLocalProfiles();
      final idx = list.indexWhere((p) => p['id'] == id);
      if (idx >= 0) {
        if (name != null) list[idx]['name'] = name.trim();
        if (avatarUrl != null) list[idx]['avatar_url'] = avatarUrl;
        await SupabaseConfig.saveLocalProfiles(list);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Elimina un perfil (y opcionalmente sus guardados).
  static Future<bool> delete(String id) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return false;

    try {
      // Primero borramos sus guardados
      await _c!.from('guardados').delete().eq('user_id', id);
      // Luego el perfil
      await _c!.from('profiles').delete().eq('id', id);

      await SupabaseConfig.removeLocalProfile(id);

      // Si era el usuario actual, cerramos sesión
      final current = await SupabaseConfig.getCurrentUserId();
      if (current == id) {
        await SupabaseConfig.clearCurrentUser();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Inicia sesión con un perfil (guarda id + name en cache local).
  static Future<void> login(Map<String, dynamic> profile) async {
    final id = profile['id']?.toString() ?? '';
    final name = profile['name']?.toString() ?? 'Usuario';
    if (id.isEmpty) return;
    await SupabaseConfig.setCurrentUser(userId: id, userName: name);
  }

  /// Cierra la sesión actual.
  static Future<void> logout() async {
    await SupabaseConfig.clearCurrentUser();
  }
}
