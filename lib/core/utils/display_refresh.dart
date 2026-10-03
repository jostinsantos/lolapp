import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Solicita al sistema que use el modo de pantalla con mayor tasa de refresco
/// disponible (60 / 90 / 120 / 144 Hz según el dispositivo).
///
/// En Android hay que registrar el MethodChannel en MainActivity (ver
/// `android_main_activity_snippet.kt` incluido en el ZIP de fixes).
///
/// Llamar una vez al arrancar la app, por ejemplo en `main()` o en el
/// `initState` del shell principal:
/// ```dart
/// await DisplayRefresh.requestHighest();
/// ```
class DisplayRefresh {
  DisplayRefresh._();

  static const _channel = MethodChannel('app/display_refresh');

  /// Intenta activar el modo con más Hz. No lanza; falla en silencio.
  static Future<double?> requestHighest() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final rate = await _channel.invokeMethod<double>('requestHighestRefreshRate');
      if (rate != null && kDebugMode) {
        debugPrint('DisplayRefresh: modo activo @ ${rate.toStringAsFixed(1)} Hz');
      }
      return rate;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DisplayRefresh: no disponible ($e)');
      }
      return null;
    }
  }

  /// Devuelve la tasa actual reportada por el sistema (o null).
  static Future<double?> currentRefreshRate() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      return await _channel.invokeMethod<double>('getRefreshRate');
    } catch (_) {
      return null;
    }
  }
}
