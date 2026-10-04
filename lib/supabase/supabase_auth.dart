import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'supabase_config.dart';

/// Resultado de login/registro con mensaje de error legible.
class AuthResult {
  final AuthResponse? response;
  final String? error;
  final bool needsEmailConfirm;

  AuthResult({this.response, this.error, this.needsEmailConfirm = false});

  bool get ok => response?.user != null && error == null;
  bool get hasSession => response?.session != null;
}

/// Servicio de autenticación de CUENTA (email + password).
class SupabaseAuth {
  static SupabaseClient? get _c => AppSupabase.client;

  /// Registrar nueva cuenta
  static Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) {
      return AuthResult(error: 'Supabase no configurado');
    }

    try {
      final res = await _c!.auth.signUp(
        email: email.trim(),
        password: password,
      );

      // Si el proyecto exige confirmar email, no hay session
      if (res.user != null && res.session == null) {
        return AuthResult(
          response: res,
          needsEmailConfirm: true,
          error:
              'Debes confirmar el email. En Supabase desactiva "Confirm email" para evitar esto.',
        );
      }

      if (res.user == null) {
        return AuthResult(error: 'No se pudo crear la cuenta');
      }

      // Limpiar modo invitado al registrar
      await SupabaseConfig.clearGuestMode();
      return AuthResult(response: res);
    } on AuthException catch (e) {
      return AuthResult(error: e.message);
    } catch (e) {
      return AuthResult(error: e.toString());
    }
  }

  /// Iniciar sesión
  static Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) {
      return AuthResult(error: 'Supabase no configurado');
    }

    try {
      final res = await _c!.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      if (res.user == null) {
        return AuthResult(error: 'Email o contraseña incorrectos');
      }

      await SupabaseConfig.clearGuestMode();
      return AuthResult(response: res);
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('email not confirmed') ||
          msg.contains('not confirmed')) {
        return AuthResult(
          error:
              'Email no confirmado. Desactiva "Confirm email" en Supabase → Authentication → Providers → Email.',
          needsEmailConfirm: true,
        );
      }
      return AuthResult(error: e.message);
    } catch (e) {
      return AuthResult(error: e.toString());
    }
  }

  /// Cerrar sesión de la cuenta + limpiar perfil actual
  static Future<void> signOut() async {
    await AppSupabase.signOut();
    await SupabaseConfig.clearCurrentProfile();
    await SupabaseConfig.clearGuestMode();
    await SupabaseConfig.clearLocalProfiles();
  }

  static Future<bool> resetPassword(String email) async {
    if (!AppSupabase.isInitialized) await AppSupabase.init();
    if (_c == null) return false;
    try {
      await _c!.auth.resetPasswordForEmail(email.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updatePassword(String newPassword) async {
    if (_c == null || !AppSupabase.isLoggedIn) return false;
    try {
      await _c!.auth.updateUser(UserAttributes(password: newPassword));
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? get currentEmail => AppSupabase.currentUser?.email;

  static DateTime? get accountCreatedAt {
    final created = AppSupabase.currentUser?.createdAt;
    if (created == null) return null;
    return DateTime.tryParse(created);
  }

  static bool get isLoggedIn => AppSupabase.isLoggedIn;
}
