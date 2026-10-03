import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Resultado de programar un recordatorio (éxito o motivo del fallo).
class ScheduleResult {
  final bool ok;
  final String? error;
  final String? errorDetail;

  const ScheduleResult.success()
      : ok = true,
        error = null,
        errorDetail = null;

  const ScheduleResult.fail(this.error, [this.errorDetail]) : ok = false;
}

class EpisodeReminder {
  final int tmdbId;
  final int season;
  final int episode;
  final String seriesTitle;
  final String episodeTitle;
  final DateTime airDate;
  final int notificationId;

  const EpisodeReminder({
    required this.tmdbId,
    required this.season,
    required this.episode,
    required this.seriesTitle,
    required this.episodeTitle,
    required this.airDate,
    required this.notificationId,
  });

  String get key => '${tmdbId}_S${season}_E$episode';

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'season': season,
        'episode': episode,
        'seriesTitle': seriesTitle,
        'episodeTitle': episodeTitle,
        'airDate': airDate.toIso8601String(),
        'notificationId': notificationId,
      };

  factory EpisodeReminder.fromJson(Map<String, dynamic> j) => EpisodeReminder(
        tmdbId: j['tmdbId'] as int,
        season: j['season'] as int,
        episode: j['episode'] as int,
        seriesTitle: j['seriesTitle']?.toString() ?? '',
        episodeTitle: j['episodeTitle']?.toString() ?? '',
        airDate: DateTime.parse(j['airDate'] as String),
        notificationId: j['notificationId'] as int,
      );
}

class EpisodeReminderService {
  EpisodeReminderService._();
  static final EpisodeReminderService instance = EpisodeReminderService._();

  static const _prefsKey = 'episode_reminders_v1';
  static const _channelId = 'episode_premiere_channel';
  static const _channelName = 'Estrenos de capítulos';

  static const int notifyHour = 11;
  static const int notifyMinute = 0;
  static const _prefsHour = 'notifications_hour';
  static const _prefsMinute = 'notifications_minute';
  static const _prefsEnabled = 'notifications_enabled';

  Future<({int hour, int minute})> getNotifyTime() async {
    final prefs = await SharedPreferences.getInstance();
    final h = (prefs.getInt(_prefsHour) ?? notifyHour).clamp(0, 23);
    final m = (prefs.getInt(_prefsMinute) ?? notifyMinute).clamp(0, 59);
    return (hour: h, minute: m);
  }

  Future<bool> areNotificationsEnabledInApp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabled) ?? true;
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _tzReady = false;
  bool _channelReady = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _ensureTz() async {
    if (_tzReady) return;
    try {
      tzdata.initializeTimeZones();
    } catch (_) {}
    _tzReady = true;
  }

  Future<void> _ensureChannel() async {
    if (_channelReady) return;
    final android = _android;
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Avisos cuando se estrena un capítulo',
          importance: Importance.high,
        ),
      );
    }
    _channelReady = true;
  }

  /// Intenta pedir permisos. Nunca bloquea por `areNotificationsEnabled`
  /// (en muchos OEM devuelve false aunque el permiso ya esté dado y `show()`
  /// funcione, p.ej. la prueba de Ajustes). El fallo real lo reporta
  /// `zonedSchedule` / `show` si ocurre.
  Future<String?> ensurePermissions() async {
    if (!Platform.isAndroid) return null;

    final android = _android;
    if (android == null) return null;

    // Notificaciones: solo intentar request si el sistema dice que no están.
    // Si el request falla o el check miente → seguimos igual (no error).
    try {
      final enabled = await android.areNotificationsEnabled();
      debugPrint('areNotificationsEnabled => $enabled');
      if (enabled != true) {
        try {
          final granted = await android.requestNotificationsPermission();
          debugPrint('requestNotificationsPermission => $granted');
        } catch (e) {
          debugPrint('requestNotificationsPermission: $e');
        }
      }
    } catch (e) {
      debugPrint('notif perm: $e');
    }

    // Alarmas exactas: pedir si hace falta; si no, schedule usará inexact.
    try {
      final canExact = await android.canScheduleExactNotifications();
      debugPrint('canScheduleExactNotifications => $canExact');
      if (canExact == false) {
        try {
          await android.requestExactAlarmsPermission();
        } catch (e) {
          debugPrint('requestExactAlarmsPermission: $e');
        }
      }
    } catch (e) {
      debugPrint('exact alarm: $e');
    }

    return null; // nunca bloquear aquí
  }

  int notificationIdFor({
    required int tmdbId,
    required int season,
    required int episode,
  }) {
    final h = Object.hash(tmdbId, season, episode);
    return h & 0x7fffffff;
  }

  Future<List<EpisodeReminder>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => EpisodeReminder.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<EpisodeReminder> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<bool> isScheduled({
    required int tmdbId,
    required int season,
    required int episode,
  }) async {
    final all = await getAll();
    final key = '${tmdbId}_S${season}_E$episode';
    return all.any((r) => r.key == key);
  }

  Future<Set<String>> scheduledKeysForSeries(int tmdbId) async {
    final all = await getAll();
    return all.where((r) => r.tmdbId == tmdbId).map((r) => r.key).toSet();
  }

  /// Programa aviso a las 11:00 del día de [airDate].
  Future<ScheduleResult> schedule({
    required int tmdbId,
    required int season,
    required int episode,
    required String seriesTitle,
    required String episodeTitle,
    required DateTime airDate,
  }) async {
    try {
      await _ensureTz();
      await _ensureChannel();

      final permErr = await ensurePermissions();
      if (permErr != null) {
        return ScheduleResult.fail(permErr);
      }

      // Respetar preferencia "desactivar notificaciones" de la app
      if (!await areNotificationsEnabledInApp()) {
        return const ScheduleResult.fail(
          'Las notificaciones están desactivadas en Ajustes → Notificaciones.',
        );
      }

      final time = await getNotifyTime();
      final localDay = DateTime(airDate.year, airDate.month, airDate.day);
      var when = tz.TZDateTime.local(
        localDay.year,
        localDay.month,
        localDay.day,
        time.hour,
        time.minute,
      );

      final now = tz.TZDateTime.now(tz.local);
      if (when.isBefore(now)) {
        if (localDay.year == now.year &&
            localDay.month == now.month &&
            localDay.day == now.day) {
          when = now.add(const Duration(minutes: 1));
        } else {
          return const ScheduleResult.fail(
            'La fecha de estreno ya pasó; no se puede programar.',
          );
        }
      }

      final id = notificationIdFor(
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      );

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription:
            'Avisos cuando se estrena un capítulo de tus series',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.reminder,
      );
      const details = NotificationDetails(android: androidDetails);

      final sLabel =
          'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
      final series = seriesTitle.isNotEmpty ? seriesTitle : 'tu serie';
      final title = 'Capítulo nuevo hoy';
      final body = episodeTitle.isNotEmpty
          ? 'No te olvides que hoy se estrena capítulo de $series · $sLabel · $episodeTitle'
          : 'No te olvides que hoy se estrena capítulo de $series · $sLabel';

      final payload = jsonEncode({
        'type': 'episode_premiere',
        'tmdbId': tmdbId,
        'season': season,
        'episode': episode,
      });

      // Programar: exact → inexact → alarmClock. Reintento si R8/Gson falla.
      final scheduleErr = await _tryZonedSchedule(
        id: id,
        title: title,
        body: body,
        when: when,
        details: details,
        payload: payload,
      );
      if (scheduleErr != null) {
        return scheduleErr;
      }

      final reminder = EpisodeReminder(
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        seriesTitle: seriesTitle,
        episodeTitle: episodeTitle,
        airDate: airDate,
        notificationId: id,
      );

      final all = await getAll();
      all.removeWhere((r) => r.key == reminder.key);
      all.add(reminder);
      await _saveAll(all);
      return const ScheduleResult.success();
    } catch (e, st) {
      debugPrint('schedule error: $e\n$st');
      return ScheduleResult.fail(
        'Error al programar.',
        e.toString().length > 160
            ? '${e.toString().substring(0, 160)}…'
            : e.toString(),
      );
    }
  }


  /// Intenta varios modos de programación. El error "Missing type parameter"
  /// suele ser R8/ProGuard + Gson del plugin en release: hay que conservar
  /// clases con proguard-rules (ver proguard_notifications.pro).
  Future<ScheduleResult?> _tryZonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    required String payload,
  }) async {
    final modes = <AndroidScheduleMode>[
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
      AndroidScheduleMode.alarmClock,
    ];

    Object? lastError;

    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        try {
          await _plugin.cancel(id);
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      for (final mode in modes) {
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            when,
            details,
            androidScheduleMode: mode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload,
          );
          return null; // OK
        } catch (e) {
          lastError = e;
          debugPrint('zonedSchedule mode=$mode attempt=$attempt => $e');
        }
      }
    }

    final msg = lastError?.toString() ?? 'error desconocido';

    if (msg.contains('Missing type parameter')) {
      return ScheduleResult.fail(
        'Error al programar (build release).',
        'Añade las reglas ProGuard de notificaciones (proguard_notifications.pro) '
        'y vuelve a generar el APK. En debug suele funcionar; en release R8 borra tipos de Gson.',
      );
    }
    if (msg.contains('exact') || msg.contains('SCHEDULE_EXACT')) {
      return ScheduleResult.fail(
        'Android bloqueó la alarma exacta.',
        'Ajustes → Apps → Alarmas y recordatorios → permitir. '
        'También desactiva optimización de batería para esta app.',
      );
    }
    if (msg.contains('POST_NOTIFICATION') ||
        msg.contains('notifications permission')) {
      return ScheduleResult.fail(
        'No se pudo programar el aviso.',
        'Revisa Ajustes → Apps → Notificaciones.',
      );
    }
    return ScheduleResult.fail(
      'No se pudo programar el aviso.',
      msg.length > 200 ? '${msg.substring(0, 200)}…' : msg,
    );
  }

  Future<void> cancel({
    required int tmdbId,
    required int season,
    required int episode,
  }) async {
    final id = notificationIdFor(
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );
    try {
      await _plugin.cancel(id);
    } catch (_) {}

    final all = await getAll();
    all.removeWhere(
      (r) =>
          r.tmdbId == tmdbId && r.season == season && r.episode == episode,
    );
    await _saveAll(all);
  }

  /// Programa varios. [onError] recibe el primer fallo (si todos fallan).
  Future<({int ok, String? error, String? detail})> scheduleAll({
    required int tmdbId,
    required String seriesTitle,
    required List<Map<String, dynamic>> episodes,
  }) async {
    var ok = 0;
    String? lastErr;
    String? lastDetail;

    // Permisos una sola vez
    final permErr = await ensurePermissions();
    if (permErr != null) {
      return (ok: 0, error: permErr, detail: null);
    }

    for (final ep in episodes) {
      final season = (ep['season_number'] as num?)?.toInt();
      final episode = (ep['episode_number'] as num?)?.toInt();
      final airRaw = ep['air_date']?.toString();
      if (season == null || episode == null || airRaw == null) continue;
      final air = DateTime.tryParse(airRaw);
      if (air == null) continue;

      final r = await schedule(
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        seriesTitle: seriesTitle,
        episodeTitle: ep['name']?.toString() ?? '',
        airDate: air,
      );
      if (r.ok) {
        ok++;
      } else {
        lastErr = r.error;
        lastDetail = r.errorDetail;
      }
    }
    return (ok: ok, error: ok == 0 ? lastErr : null, detail: lastDetail);
  }

  Future<void> cancelAllForSeries(int tmdbId) async {
    final all = await getAll();
    final mine = all.where((r) => r.tmdbId == tmdbId).toList();
    for (final r in mine) {
      try {
        await _plugin.cancel(r.notificationId);
      } catch (_) {}
    }
    all.removeWhere((r) => r.tmdbId == tmdbId);
    await _saveAll(all);
  }
}