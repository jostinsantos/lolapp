import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  static Future<SharedPreferences> get prefs => SharedPreferences.getInstance();
  static Future<String?> getString(String key) async => (await prefs).getString(key);
  static Future<bool> setString(String key, String value) async => (await prefs).setString(key, value);
  static Future<bool> remove(String key) async => (await prefs).remove(key);
}
