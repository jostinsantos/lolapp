class JsonUtils {
  static Map<String, dynamic>? asMap(dynamic v) =>
      v is Map<String, dynamic> ? v : null;
}
