import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';
import 'supabase_guardados.dart';

/// Servicio unificado de Guardados.
///
/// REGLA IMPORTANTE:
/// - Si Supabase está activo (credenciales + perfil logueado) → lee/escribe SOLO en Supabase.
/// - Si NO está activo → lee/escribe SOLO en cache local (SharedPreferences).
/// - El cache local NUNCA se borra al activar o desactivar Supabase.
///   Así el usuario no pierde sus guardados locales si desactiva la nube.
class GuardadosService {
  static const String _kKey = 'guardados_items';

  // ─── Cache local (comportamiento original de la app) ──────────────────────

  static Future<List<Map<String, dynamic>>> _cacheGetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? [];
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

  static Future<bool> _cacheIsSaved(int idcontenido) async {
    final items = await _cacheGetAll();
    return items.any((e) => e['idcontenido'] == idcontenido);
  }

  static Future<bool> _cacheToggle(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _cacheGetAll();
    final id = item['idcontenido'];
    final exists = items.any((e) => e['idcontenido'] == id);

    if (exists) {
      items.removeWhere((e) => e['idcontenido'] == id);
    } else {
      items.insert(0, {
        'idcontenido': id,
        'poster': item['poster'],
        'titulo': item['titulo'] ?? item['title'],
        'tipo': item['tipo'] ?? item['type'] ?? item['mediaType'] ?? 'movie',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    final encoded = items.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(_kKey, encoded);
    return !exists;
  }

  static Future<void> _cacheRemove(int idcontenido) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _cacheGetAll();
    items.removeWhere((e) => e['idcontenido'] == idcontenido);
    final encoded = items.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(_kKey, encoded);
  }

  // ─── API pública ──────────────────────────────────────────────────────────

  /// Lista los guardados.
  /// Supabase activo → solo los del usuario en la nube.
  /// Supabase inactivo → los del cache local.
  static Future<List<Map<String, dynamic>>> getAll() async {
    if (await SupabaseConfig.isSupabaseActive()) {
      return SupabaseGuardados.list();
    }
    return _cacheGetAll();
  }

  static Future<bool> isSaved(int idcontenido) async {
    if (await SupabaseConfig.isSupabaseActive()) {
      return SupabaseGuardados.isSaved(idcontenido);
    }
    return _cacheIsSaved(idcontenido);
  }

  /// Toggle. Devuelve true si quedó guardado.
  static Future<bool> toggle(Map<String, dynamic> item) async {
    if (await SupabaseConfig.isSupabaseActive()) {
      return SupabaseGuardados.toggle(item);
    }
    return _cacheToggle(item);
  }

  static Future<void> remove(int idcontenido) async {
    if (await SupabaseConfig.isSupabaseActive()) {
      await SupabaseGuardados.remove(idcontenido);
    } else {
      await _cacheRemove(idcontenido);
    }
  }

  /// Solo limpia la fuente activa (Supabase o cache).
  /// Nunca borra la otra fuente.
  static Future<void> clearAll() async {
    if (await SupabaseConfig.isSupabaseActive()) {
      await SupabaseGuardados.clearAll();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    }
  }
}
