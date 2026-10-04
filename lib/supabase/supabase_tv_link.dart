import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'supabase_auth.dart';

/// Emparejar TV ↔ Móvil por código de 6 dígitos.
/// 
/// Flujo:
/// 1. TV genera código → createCode()
/// 2. Móvil (logueado) introduce el código → linkCode(code)
/// 3. TV hace polling → pollCode(code) hasta que recibe account_id
class SupabaseTvLink {
  static SupabaseClient? get _c => AppSupabase.client;

  static String _generateCode() {
    final rnd = Random.secure();
    return List.generate(6, (_) => rnd.nextInt(10)).join();
  }

  /// TV: crea un código y lo guarda en la tabla.
  /// Devuelve el código o null si falla.
  static Future<String?> createCode() async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return null;

    final code = _generateCode();
    try {
      await _c!.from('tv_link').insert({
        'code': code,
        'used': false,
      });
      return code;
    } catch (_) {
      return code; // devolver igual para mostrar en pantalla
    }
  }

  /// Móvil: vincula el código con la cuenta actual.
  static Future<bool> linkCode(String code) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null || !SupabaseAuth.isLoggedIn) return false;

    final trimmed = code.trim();
    if (trimmed.length != 6) return false;

    try {
      // Verificar que el código existe y no está usado / no expiró
      final rows = await _c!
          .from('tv_link')
          .select('id, used, expires_at')
          .eq('code', trimmed)
          .limit(1);

      if (rows.isEmpty) return false;

      final row = rows.first;
      if (row['used'] == true) return false;

      final expires = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (expires != null && expires.isBefore(DateTime.now())) return false;

      // Vincular con la cuenta
      await _c!.from('tv_link').update({
        'account_id': AppSupabase.currentUser!.id,
        'used': true,
      }).eq('code', trimmed);

      return true;
    } catch (_) {
      return false;
    }
  }

  /// TV: polling. Devuelve el account_id cuando se vincula, o null.
  static Future<String?> pollCode(String code) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return null;

    try {
      final rows = await _c!
          .from('tv_link')
          .select('account_id, used, expires_at')
          .eq('code', code.trim())
          .limit(1);

      if (rows.isEmpty) return null;

      final row = rows.first;
      final expires = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (expires != null && expires.isBefore(DateTime.now())) return null;

      if (row['used'] == true && row['account_id'] != null) {
        return row['account_id'].toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// TV: una vez tiene account_id, puede listar perfiles de esa cuenta.
  /// (La TV no tiene sesión de Auth, por eso usamos el account_id del link)
  /// Nota: para que esto funcione con RLS, la TV debe hacer sign-in
  /// o usar un approach de token. En la práctica la TV puede
  /// pedir al usuario que elija perfil después de vincular
  /// y guardar el profile_id localmente.
  static Future<List<Map<String, dynamic>>> getProfilesForAccount(
    String accountId,
  ) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return [];

    try {
      // Como la TV no está autenticada como ese usuario,
      // esta consulta solo funciona si la policy lo permite
      // o si usamos service_role (no recomendado en cliente).
      // Solución práctica: el móvil, al vincular, también
      // puede enviar los perfiles, o la TV pide login.
      // Por ahora devolvemos vacío y la TV muestra
      // "Ve a la app móvil y elige perfil" o hace login.
      return [];
    } catch (_) {
      return [];
    }
  }
}
