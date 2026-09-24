import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'episode_reminder_service.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF16161A);
const _kBorder = Color(0x22FFFFFF);

/// Página de notificaciones (desde Configuración).
class NotificationsSectionPage extends StatefulWidget {
  const NotificationsSectionPage({super.key});

  @override
  State<NotificationsSectionPage> createState() =>
      _NotificationsSectionPageState();
}

class _NotificationsSectionPageState extends State<NotificationsSectionPage> {
  static const _prefsEnabled = 'notifications_enabled';
  static const _prefsHour = 'notifications_hour';
  static const _prefsMinute = 'notifications_minute';
  static const _testNotifId = 88001;

  final _svc = EpisodeReminderService.instance;
  final _plugin = FlutterLocalNotificationsPlugin();

  bool _loading = true;
  bool _enabled = true;
  int _hour = 11;
  int _minute = 0;
  List<EpisodeReminder> _active = [];

  /// Cuenta atrás de prueba
  int? _countdown; // null = idle
  Timer? _timer;
  String? _statusMsg;
  Color _statusColor = Colors.white54;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsEnabled) ?? true;
    final hour = prefs.getInt(_prefsHour) ?? EpisodeReminderService.notifyHour;
    final minute =
        prefs.getInt(_prefsMinute) ?? EpisodeReminderService.notifyMinute;
    final list = await _svc.getAll();
    // Ordenar por fecha
    list.sort((a, b) => a.airDate.compareTo(b.airDate));
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _hour = hour.clamp(0, 23);
      _minute = minute.clamp(0, 59);
      _active = list;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabled, v);
    setState(() => _enabled = v);
    if (v) {
      final err = await _svc.ensurePermissions();
      if (err != null && mounted) {
        _setStatus(err, Colors.orangeAccent);
      } else {
        _setStatus('Notificaciones activadas', const Color(0xFF4ADE80));
      }
    } else {
      _setStatus('Notificaciones desactivadas', Colors.white54);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _kAccent,
              surface: _kCard,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsHour, picked.hour);
    await prefs.setInt(_prefsMinute, picked.minute);
    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
    });
    _setStatus(
      'Hora de aviso: ${_fmtTime(_hour, _minute)}',
      const Color(0xFF4ADE80),
    );
  }

  String _fmtTime(int h, int m) {
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _fmtDate(DateTime d) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  void _setStatus(String msg, Color c) {
    setState(() {
      _statusMsg = msg;
      _statusColor = c;
    });
  }

  Future<void> _startTestCountdown() async {
    if (_countdown != null || _busy) return;

    if (!_enabled) {
      _setStatus(
        'Activa las notificaciones primero',
        Colors.orangeAccent,
      );
      return;
    }

    setState(() => _busy = true);
    final err = await _svc.ensurePermissions();
    if (!mounted) return;
    if (err != null) {
      setState(() => _busy = false);
      _setStatus(err, Colors.redAccent);
      return;
    }
    setState(() => _busy = false);

    _timer?.cancel();
    setState(() => _countdown = 10);
    _setStatus('Prueba en 10 s…', Colors.white70);

    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = (_countdown ?? 1) - 1;
      if (next <= 0) {
        t.cancel();
        setState(() => _countdown = null);
        await _fireTestNotification();
      } else {
        setState(() => _countdown = next);
        _setStatus('Prueba en $next s…', Colors.white70);
      }
    });
  }

  void _cancelCountdown() {
    _timer?.cancel();
    setState(() => _countdown = null);
    _setStatus('Prueba cancelada', Colors.white54);
  }

  Future<void> _fireTestNotification() async {
    try {
      try {
        tzdata.initializeTimeZones();
      } catch (_) {}

      const android = AndroidNotificationDetails(
        'episode_premiere_channel',
        'Estrenos de capítulos',
        channelDescription: 'Avisos de prueba y estrenos',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );
      const details = NotificationDetails(android: android);

      await _plugin.show(
        _testNotifId,
        'Prueba de notificación',
        'Si ves esto, las notificaciones funcionan correctamente.',
        details,
        payload: 'test',
      );
      if (mounted) {
        _setStatus('Notificación de prueba enviada', const Color(0xFF4ADE80));
      }
    } catch (e) {
      if (mounted) {
        _setStatus(
          'No se pudo mostrar la notificación',
          Colors.redAccent,
        );
      }
      debugPrint('test notif: $e');
    }
  }

  Future<void> _cancelOne(EpisodeReminder r) async {
    await _svc.cancel(
      tmdbId: r.tmdbId,
      season: r.season,
      episode: r.episode,
    );
    await _load();
    if (mounted) {
      _setStatus('Aviso cancelado', Colors.white54);
    }
  }

  Future<void> _cancelAll() async {
    final list = List<EpisodeReminder>.from(_active);
    for (final r in list) {
      await _svc.cancel(
        tmdbId: r.tmdbId,
        season: r.season,
        episode: r.episode,
      );
    }
    await _load();
    if (mounted) {
      _setStatus('Todos los avisos cancelados', Colors.white54);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Notificaciones',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kAccent),
            )
          : ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
              children: [
                // ── Activar ──────────────────────────────────────────
                _card(
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _enabled
                              ? _kAccent.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _enabled
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_off_rounded,
                          color: _enabled ? _kAccent : Colors.white38,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Activar notificaciones',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _enabled
                                  ? 'Recibirás avisos de estrenos'
                                  : 'Desactivadas en la app',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        onChanged: _setEnabled,
                        activeColor: _kAccent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Hora del día ─────────────────────────────────────
                _card(
                  child: InkWell(
                    onTap: _enabled ? _pickTime : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Hora del aviso',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Día del estreno a las ${_fmtTime(_hour, _minute)}',
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.45),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _fmtTime(_hour, _minute),
                            style: TextStyle(
                              color: _enabled
                                  ? _kAccent
                                  : Colors.white.withValues(alpha: 0.35),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Prueba ───────────────────────────────────────────
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.science_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Probar notificación',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Cuenta atrás de 10 segundos y se muestra el aviso',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_countdown != null) ...[
                        Center(
                          child: Text(
                            '$_countdown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _countdown! / 10,
                            backgroundColor: Colors.white12,
                            color: _kAccent,
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _cancelCountdown,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancelar prueba'),
                        ),
                      ] else
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _startTestCountdown,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.notifications_rounded),
                          label: Text(
                            _busy ? 'Comprobando permisos…' : 'Probar ahora',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                if (_statusMsg != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _statusColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      _statusMsg!,
                      style: TextStyle(color: _statusColor, fontSize: 13),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Avisos activos',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_active.isNotEmpty)
                      TextButton(
                        onPressed: _cancelAll,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent.withValues(
                            alpha: 0.9,
                          ),
                        ),
                        child: const Text(
                          'Cancelar todos',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_active.isEmpty)
                  _card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 36,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No hay avisos programados',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Actívalos desde el detalle de una serie',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._active.map((r) {
                    final sLabel =
                        'S${r.season.toString().padLeft(2, '0')}E${r.episode.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _card(
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _kAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.notifications_active_rounded,
                                color: _kAccent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.seriesTitle.isNotEmpty
                                        ? r.seriesTitle
                                        : 'Serie',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$sLabel'
                                    '${r.episodeTitle.isNotEmpty ? ' · ${r.episodeTitle}' : ''}'
                                    ' · ${_fmtDate(r.airDate)} ${_fmtTime(_hour, _minute)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.45,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cancelar',
                              onPressed: () => _cancelOne(r),
                              icon: Icon(
                                Icons.close_rounded,
                                color: Colors.white.withValues(alpha: 0.4),
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }
}