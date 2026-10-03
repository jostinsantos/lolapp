import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ── Canales ────────────────────────────────────────────────
  static const _channelId = 'downloads_channel';
  static const _channelName = 'Descargas';
  static const _channelDesc = 'Progreso de descargas de video';

  static const _castChannelId = 'cast_channel';
  static const _castChannelName = 'Cast en curso';
  static const _castChannelDesc = 'Notificación mientras se transmite a la TV';

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Canal de descargas (Foreground Service)
    const downloadChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.low,
      showBadge: false,
      playSound: false,
      enableVibration: false,
    );

    // Canal de Cast
    const castChannel = AndroidNotificationChannel(
      _castChannelId,
      _castChannelName,
      description: _castChannelDesc,
      importance: Importance.low,
    );

    await androidPlugin?.createNotificationChannel(downloadChannel);
    await androidPlugin?.createNotificationChannel(castChannel);

    // Android 13+ permiso de notificaciones
    await androidPlugin?.requestNotificationsPermission();
  }

  /// Muestra / actualiza la notificación de progreso
  /// Esta notificación se ejecuta como Foreground Service
  /// para que Android no mate la descarga en segundo plano.
  static Future<void> showProgress({
    required int id,
    required String title,
    required int progress, // 0-100
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress.clamp(0, 100),
      ongoing: true,           // no se puede deslizar
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      category: AndroidNotificationCategory.progress,
      // ↓↓↓ CLAVE: convierte la notificación en Foreground Service
      // Esto evita que Android mate el proceso mientras descarga
      // (requiere el permiso FOREGROUND_SERVICE en el Manifest)
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// Notificación de completado
  static Future<void> showCompleted({
    required int id,
    required String title,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      onlyAlertOnce: true,
      autoCancel: true,
      ongoing: false,
    );

    await _plugin.show(
      id,
      title,
      'Descarga completada',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Cancelar notificación
  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }
}