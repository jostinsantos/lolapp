import 'dart:async';
import 'package:dart_cast/dart_cast.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CastManager {
  static final CastManager _instance = CastManager._();
  factory CastManager() => _instance;
  CastManager._();

  CastService? _castService;
  CastSession? _session;
  bool _isConnected = false;

  final _notif = FlutterLocalNotificationsPlugin();
  static const _notifId = 9999;

  bool get isConnected => _isConnected;
  CastSession? get session => _session;

  Future<void> connect(CastService service, CastSession session, String title) async {
    // Si ya había una sesión anterior, la cerramos
    await disconnect(showNotif: false);

    _castService = service;
    _session = session;
    _isConnected = true;

    await _showCastNotification(title);
  }

  Future<void> disconnect({bool showNotif = true}) async {
    try {
      await _session?.stop();
      await _session?.disconnect();
    } catch (_) {}
    _castService?.dispose();

    _session = null;
    _castService = null;
    _isConnected = false;

    if (showNotif) {
      await _notif.cancel(_notifId);
    }
  }

  Future<void> _showCastNotification(String title) async {
    const android = AndroidNotificationDetails(
      'cast_channel',
      'Cast en curso',
      channelDescription: 'Notificación mientras se transmite a la TV',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,          // ← no se puede deslizar
      autoCancel: false,
      showWhen: false,
      category: AndroidNotificationCategory.service,
    );

    await _notif.show(
      _notifId,
      'Transmitiendo a TV',
      title.isNotEmpty ? title : 'Reproduciendo en Chromecast / TV',
      const NotificationDetails(android: android),
    );
  }
}