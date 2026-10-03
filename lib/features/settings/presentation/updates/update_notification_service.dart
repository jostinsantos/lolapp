import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/versiones.dart';

/// Notifica al usuario cuando hay una actualización de la app
/// (versión nueva o parche), respetando la preferencia "recibir_parches".
///
/// - Versión: cambio de nombre (ej. 1.0.2 → 1.0.3)
/// - Parche: subida de version_code (parche diario)
///
/// Solo avisa una vez por cada combinación version+code detectada
/// (evita spam en cada arranque).
class UpdateNotificationService {
  UpdateNotificationService._();
  static final UpdateNotificationService instance =
      UpdateNotificationService._();

  static const _channelId = 'app_updates_channel';
  static const _channelName = 'Actualizaciones de la app';
  static const _channelDesc =
      'Avisos cuando hay nueva versión o parche disponible';

  static const _prefsLastNotifiedKey = 'update_notif_last_key';
  static const _notifId = 9001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _channelReady = false;

  Future<void> _ensureChannel() async {
    if (_channelReady) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
    _channelReady = true;
  }

  /// Llamar al arrancar la app (o al volver a foreground).
  /// Comprueba la API y, si hay actualización nueva y el usuario lo permite,
  /// muestra una notificación local indicando si es versión o parche.
  Future<void> checkAndNotify() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recibirParches = prefs.getBool('recibir_parches') ?? true;
      // Si el usuario desactivó parches, solo avisamos de cambio de versión (nombre).
      // Si está activado, avisamos de ambos.

      final status = await VersionService.checkForUpdate();
      if (!status.requiresUpdate || status.latestVersion == null) {
        debugPrint('[UpdateNotif] sin actualización');
        return;
      }

      final latest = status.latestVersion!;
      final key =
          '${latest.versionAceptada}|${latest.versionCodeAceptada}';
      final lastKey = prefs.getString(_prefsLastNotifiedKey);
      if (lastKey == key) {
        debugPrint('[UpdateNotif] ya notificado: $key');
        return;
      }

      // Si solo hay parche y el usuario no quiere parches → no notificar
      if (status.hasPatchUpdate &&
          !status.hasVersionUpdate &&
          !recibirParches) {
        debugPrint('[UpdateNotif] parche ignorado (recibir_parches=false)');
        return;
      }

      String title;
      String body;

      if (status.hasVersionUpdate && status.hasPatchUpdate) {
        title = 'Nueva versión y parche disponibles';
        body =
            'Versión ${latest.versionAceptada} · Parche ${latest.versionCodeAceptada}\n'
            'Tienes ${VersionService.currentVersionName} (parche ${VersionService.currentVersionCode})';
      } else if (status.hasVersionUpdate) {
        title = 'Nueva versión disponible';
        body =
            '${latest.versionAceptada} (tienes ${VersionService.currentVersionName})';
      } else {
        title = 'Nuevo parche disponible';
        body =
            'Parche ${latest.versionCodeAceptada} (tienes ${VersionService.currentVersionCode})';
      }

      if (latest.novedades.trim().isNotEmpty) {
        final nov = latest.novedades.trim();
        body = '$body\n${nov.length > 120 ? '${nov.substring(0, 120)}…' : nov}';
      }

      await _ensureChannel();

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: true,
        category: AndroidNotificationCategory.status,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _plugin.show(
        _notifId,
        title,
        body,
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
      );

      await prefs.setString(_prefsLastNotifiedKey, key);
      debugPrint('[UpdateNotif] notificado: $title');
    } catch (e, st) {
      debugPrint('[UpdateNotif] error: $e\n$st');
    }
  }
}
