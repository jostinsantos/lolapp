import 'dart:developer' as dev;
class Logger {
  static void d(String msg, [String name = 'app']) => dev.log(msg, name: name);
  static void e(String msg, [Object? error]) => dev.log(msg, name: 'error', error: error);
}
