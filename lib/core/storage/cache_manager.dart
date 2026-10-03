class CacheManager {
  static final Map<String, dynamic> _mem = {};
  static T? get<T>(String key) => _mem[key] as T?;
  static void set(String key, dynamic value) => _mem[key] = value;
  static void clear() => _mem.clear();
}
