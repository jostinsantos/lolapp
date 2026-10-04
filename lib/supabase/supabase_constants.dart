///  Cambia solo estos dos valores y listo.
/// ============================================================
const String kSupabaseUrl = '';
const String kSupabaseAnonKey = '';

/// true si las constantes ya están configuradas (no son placeholders)
bool get isSupabaseConfigured {
  final url = kSupabaseUrl.trim();
  final key = kSupabaseAnonKey.trim();
  return !url.contains('TU_PROYECTO') &&
      !key.contains('TU_ANON_KEY') &&
      url.isNotEmpty &&
      key.isNotEmpty &&
      url.startsWith('https://');
}
