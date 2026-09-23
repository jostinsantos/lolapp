import 'dart:async';
import 'package:dart_cast/dart_cast.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// =============================================================================
// CastManager – mantiene la sesión viva aunque salgas del reproductor / app
// =============================================================================

class CastManager {
  static final CastManager _instance = CastManager._();
  factory CastManager() => _instance;
  CastManager._();

  CastService? _castService;
  CastSession? _session;
  bool _isConnected = false;
  String _currentTitle = '';

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  static const int _notifId = 9999;

  bool get isConnected => _isConnected;
  CastSession? get session => _session;

  Future<void> connect(
    CastService service,
    CastSession session,
    String title,
  ) async {
    // Cerrar sesión anterior si existía
    await disconnect(showNotif: false);

    _castService = service;
    _session = session;
    _isConnected = true;
    _currentTitle = title;

    await _showCastNotification(title);
    await _startForegroundService(title);
  }

  Future<void> disconnect({bool showNotif = true}) async {
    try {
      await _session?.stop();
      await _session?.disconnect();
    } catch (_) {}

    try {
      _castService?.dispose();
    } catch (_) {}

    _session = null;
    _castService = null;
    _isConnected = false;
    _currentTitle = '';

    if (showNotif) {
      await _notif.cancel(_notifId);
    }

    // Parar el Foreground Service si no hay descargas activas
    // (el DownloadManager también lo gestiona; aquí solo paramos si nosotros lo arrancamos)
    await _stopForegroundServiceIfNeeded();
  }

  Future<void> _showCastNotification(String title) async {
    const androidDetails = AndroidNotificationDetails(
      'cast_channel',
      'Cast en curso',
      channelDescription: 'Notificación mientras se transmite a la TV',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      category: AndroidNotificationCategory.service,
    );

    await _notif.show(
      _notifId,
      'Transmitiendo a TV',
      title.isNotEmpty ? title : 'Reproduciendo en Chromecast / TV',
      const NotificationDetails(android: androidDetails),
    );
  }

  // ── Foreground Service (igual que en descargas) ─────────────────────────

  Future<void> _startForegroundService(String title) async {
    // Si ya hay un servicio corriendo (p. ej. por una descarga), solo actualizamos el texto
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Transmitiendo a TV',
        notificationText:
            title.isNotEmpty ? title : 'Reproduciendo en Chromecast / TV',
      );
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Transmitiendo a TV',
      notificationText:
          title.isNotEmpty ? title : 'Reproduciendo en Chromecast / TV',
      callback: startCastCallback,
    );
  }

  Future<void> _stopForegroundServiceIfNeeded() async {
    // Solo paramos si NO hay descargas activas.
    // Si hay una descarga en curso, el DownloadManager se encargará de pararlo.
    // Aquí simplemente intentamos parar; si el DownloadManager lo necesita, lo volverá a arrancar.
    if (await FlutterForegroundTask.isRunningService) {
      // Si el Cast se desconectó, actualizamos o paramos.
      // Para no interferir con descargas, solo paramos si no hay Cast.
      if (!_isConnected) {
        await FlutterForegroundTask.stopService();
      }
    }
  }
}

// Callback obligatorio del Foreground Service para Cast
@pragma('vm:entry-point')
void startCastCallback() {
  FlutterForegroundTask.setTaskHandler(CastTaskHandler());
}

class CastTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Mantiene vivo el proceso mientras se casteá
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}