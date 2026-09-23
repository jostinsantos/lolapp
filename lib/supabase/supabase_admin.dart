import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_admin_constants.dart';

/// Cliente y lógica de vinculación TV ↔ Móvil.
///
/// Usa SIEMPRE el proyecto ADMIN de la app (kAdminSupabaseUrl / kAdminSupabaseAnonKey).
/// Los usuarios no configuran esto: solo ponen su Supabase personal en Ajustes.
///
/// Tabla en el proyecto ADMIN:
/// ```sql
/// create table public.tv_link (
///   id uuid primary key default gen_random_uuid(),
///   code text not null unique,
///   supabase_url text,
///   supabase_anon_key text,
///   used boolean default false,
///   created_at timestamptz default now(),
///   expires_at timestamptz default (now() + interval '15 minutes')
/// );
/// ```
class SupabaseAdmin {
  static SupabaseClient? _adminClient;
  static bool _adminReady = false;

  /// Cliente dedicado al proyecto admin (solo tv_link).
  static Future<SupabaseClient?> _getAdminClient() async {
    if (_adminReady && _adminClient != null) return _adminClient;

    final url = kAdminSupabaseUrl.trim();
    final key = kAdminSupabaseAnonKey.trim();

    // Si el admin aún no configuró las constantes, no hay linking.
    if (url.contains('TU_PROYECTO_ADMIN') ||
        key.contains('TU_ANON_KEY_ADMIN') ||
        url.isEmpty ||
        key.isEmpty) {
      return null;
    }

    try {
      _adminClient = SupabaseClient(url, key);
      _adminReady = true;
      return _adminClient;
    } catch (_) {
      _adminClient = null;
      _adminReady = false;
      return null;
    }
  }

  /// true si las constantes admin están configuradas (no son placeholders).
  static bool get isAdminConfigured {
    final url = kAdminSupabaseUrl.trim();
    final key = kAdminSupabaseAnonKey.trim();
    return !url.contains('TU_PROYECTO_ADMIN') &&
        !key.contains('TU_ANON_KEY_ADMIN') &&
        url.isNotEmpty &&
        key.isNotEmpty;
  }

  static String generateCode() {
    final rnd = Random.secure();
    return List.generate(6, (_) => rnd.nextInt(10)).join();
  }

  /// TV: crea una fila en tv_link (proyecto ADMIN) con el código.
  /// Devuelve el código o null si el admin no está configurado / falla.
  static Future<String?> createLinkCode() async {
    final client = await _getAdminClient();
    if (client == null) return null;

    final code = generateCode();
    try {
      await client.from('tv_link').insert({
        'code': code,
        'used': false,
      });
      return code;
    } catch (_) {
      // Si falla el insert (tabla no existe, etc.), igual devolvemos el código
      // para mostrarlo; el móvil intentará hacer upsert al vincular.
      return code;
    }
  }

  /// Móvil: escribe las credenciales PERSONALES del usuario en la fila del código.
  /// Usa el cliente ADMIN, no el del usuario.
  static Future<bool> linkCodeWithCredentials({
    required String code,
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) async {
    final client = await _getAdminClient();
    if (client == null) return false;

    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;

    try {
      // Intentar update de fila existente
      final res = await client
          .from('tv_link')
          .update({
            'supabase_url': supabaseUrl.trim(),
            'supabase_anon_key': supabaseAnonKey.trim(),
            'used': true,
          })
          .eq('code', trimmed)
          .select();

      if ((res as List).isNotEmpty) return true;

      // Si no existía la fila (TV no pudo insertar), crear con upsert
      await client.from('tv_link').upsert({
        'code': trimmed,
        'supabase_url': supabaseUrl.trim(),
        'supabase_anon_key': supabaseAnonKey.trim(),
        'used': true,
      }, onConflict: 'code');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// TV: polling — ¿ya tiene el código URL + KEY del usuario?
  static Future<Map<String, String>?> checkLinkCode(String code) async {
    final client = await _getAdminClient();
    if (client == null) return null;

    try {
      final res = await client
          .from('tv_link')
          .select('supabase_url, supabase_anon_key, used')
          .eq('code', code.trim())
          .maybeSingle();

      if (res == null) return null;
      final map = Map<String, dynamic>.from(res as Map);
      final url = map['supabase_url']?.toString();
      final key = map['supabase_anon_key']?.toString();
      final used = map['used'] == true;

      if (used &&
          url != null &&
          url.isNotEmpty &&
          key != null &&
          key.isNotEmpty) {
        return {'url': url, 'anonKey': key};
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// TV: elimina la fila del código tras recibir las credenciales.
  static Future<void> deleteCode(String code) async {
    final client = await _getAdminClient();
    if (client == null) return;
    try {
      await client.from('tv_link').delete().eq('code', code.trim());
    } catch (_) {}
  }

  /// Limpia códigos expirados (opcional).
  static Future<void> cleanupOldCodes() async {
    final client = await _getAdminClient();
    if (client == null) return;
    try {
      await client
          .from('tv_link')
          .delete()
          .lt('expires_at', DateTime.now().toIso8601String());
    } catch (_) {}
  }
}
