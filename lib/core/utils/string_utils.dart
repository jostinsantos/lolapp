class StringUtils {
  static String? nullIfEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s;
}
