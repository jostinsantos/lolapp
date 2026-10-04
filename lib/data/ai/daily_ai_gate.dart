import 'package:shared_preferences/shared_preferences.dart';

/// Puerta dura: la IA de home (Para ti / secciones / top personalizado)
/// solo puede generarse **cada 24 horas** (ventana rodante, no día calendario).
class DailyAiGate {
  static const _keyLastDay = 'daily_ai_gate_day_v1'; // legado
  static const _keyLastMs = 'daily_ai_gate_ms_v1';
  static const ttlMs = 24 * 60 * 60 * 1000; // 24 horas

  /// true = han pasado ≥24h desde la última generación (o nunca se generó).
  static Future<bool> canGenerateToday() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyLastMs);
    if (ms == null || ms <= 0) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - ms;
    return elapsed >= ttlMs;
  }

  static Future<void> markGeneratedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setInt(_keyLastMs, now.millisecondsSinceEpoch);
    // Mantener clave de día por compatibilidad con lecturas antiguas
    final d = now;
    final dayKey =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await prefs.setString(_keyLastDay, dayKey);
  }

  static Future<DateTime?> lastGeneratedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyLastMs);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Forzar (solo debug / botón admin). No usar en UI normal.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastDay);
    await prefs.remove(_keyLastMs);
  }
}

/// Onboarding de gustos: ¿ya eligió pósters la primera vez?
class TasteOnboardingGate {
  static const _keyDone = 'taste_onboarding_done_v1';

  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDone) ?? false;
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDone, true);
  }
}
