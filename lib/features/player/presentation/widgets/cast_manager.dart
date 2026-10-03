import 'dart:async';
import 'package:dart_cast/dart_cast.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// CastManager – sesión viva aunque salgas del reproductor / app.
/// Usa Foreground Service + notificación con botones Play/Pause y tiempo.
class CastManager {
  static final CastManager _instance = CastManager._();
  factory CastManager() => _instance;
  CastManager._();

  CastService? _castService;
  CastSession? _session;
  bool _isConnected = false;
  String _currentTitle = '';
  String _backdropUrl = '';
  String _videoUrl = '';
  Map<String, String> _headers = {};
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = true;

  // Intro / outro (igual que PlayerScreen)
  double? introStartSec;
  double? introEndSec;
  double? outroStartSec;
  double? outroEndSec;

  StreamSubscription? _posSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _durSub;
  Timer? _notifUpdateTimer;

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  static const int _notifId = 9999;

  // ── Getters públicos ────────────────────────────────────────────────────
  bool get isConnected => _isConnected;
  CastSession? get session => _session;
  String get currentTitle => _currentTitle;
  String get backdropUrl => _backdropUrl;
  String get videoUrl => _videoUrl;
  Map<String, String> get headers => Map.unmodifiable(_headers);
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;

  final _positionController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _connectedController = StreamController<bool>.broadcast();

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<bool> get connectedStream => _connectedController.stream;

  // ── Conectar ────────────────────────────────────────────────────────────
  Future<void> connect({
    required CastService service,
    required CastSession session,
    required String title,
    required String videoUrl,
    Map<String, String> headers = const {},
    String backdropUrl = '',
    double? introStart,
    double? introEnd,
    double? outroStart,
    double? outroEnd,
  }) async {
    await disconnect(showNotif: false);

    _castService = service;
    _session = session;
    _isConnected = true;
    _currentTitle = title;
    _videoUrl = videoUrl;
    _headers = Map.from(headers);
    _backdropUrl = backdropUrl;
    introStartSec = introStart;
    introEndSec = introEnd;
    outroStartSec = outroStart;
    outroEndSec = outroEnd;
    _isPlaying = true;
    _position = Duration.zero;

    _attachSessionListeners(session);
    await _showCastNotification(title);
    await _startForegroundService(title);
    _startNotifTicker();

    _connectedController.add(true);
  }

  void _attachSessionListeners(CastSession session) {
    _posSub?.cancel();
    _stateSub?.cancel();
    _durSub?.cancel();

    _posSub = session.positionStream.listen((pos) {
      _position = pos;
      if (!_positionController.isClosed) _positionController.add(pos);
    });

    try {
      _durSub = session.durationStream.listen((d) {
        if (d > Duration.zero) _duration = d;
      });
    } catch (_) {}

    _stateSub = session.stateStream.listen((state) {
      final s = state.toString().toLowerCase();
      final playing = s.contains('play') && !s.contains('pause');
      if (playing != _isPlaying) {
        _isPlaying = playing;
        if (!_playingController.isClosed) _playingController.add(playing);
        _updateNotificationText();
      }
    });
  }

  // ── Controles de reproducción ───────────────────────────────────────────
  Future<void> play() async {
    try {
      await _session?.play();
      _isPlaying = true;
      if (!_playingController.isClosed) _playingController.add(true);
      await _updateNotificationText();
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _session?.pause();
      _isPlaying = false;
      if (!_playingController.isClosed) _playingController.add(false);
      await _updateNotificationText();
    } catch (_) {}
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration target) async {
    try {
      if (target < Duration.zero) target = Duration.zero;
      if (_duration > Duration.zero && target > _duration) target = _duration;
      await _session?.seek(target);
      _position = target;
      if (!_positionController.isClosed) _positionController.add(target);
    } catch (_) {}
  }

  Future<void> seekRelative(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    await seek(target);
  }

  Future<void> skipIntro() async {
    if (introEndSec == null) return;
    final target =
        Duration(milliseconds: (introEndSec! * 1000).round());
    await seek(target);
  }

  Future<void> skipOutro() async {
    if (outroEndSec == null || _duration <= Duration.zero) return;
    // Salta al final del outro (o casi al final del video)
    final target = Duration(
      milliseconds: (outroEndSec! * 1000).round(),
    );
    await seek(target);
  }

  bool get showSkipIntro {
    if (introStartSec == null || introEndSec == null) return false;
    final pos = _position.inMilliseconds / 1000.0;
    return pos >= introStartSec! && pos <= introEndSec!;
  }

  bool get showSkipOutro {
    if (outroStartSec == null || outroEndSec == null) return false;
    final pos = _position.inMilliseconds / 1000.0;
    return pos >= outroStartSec! && pos <= outroEndSec!;
  }

  // ── Desconectar ─────────────────────────────────────────────────────────
  Future<void> disconnect({bool showNotif = true}) async {
    _notifUpdateTimer?.cancel();
    _notifUpdateTimer = null;
    _posSub?.cancel();
    _stateSub?.cancel();
    _durSub?.cancel();
    _posSub = null;
    _stateSub = null;
    _durSub = null;

    try {
      await _session?.stop();
    } catch (_) {}
    try {
      await _session?.disconnect();
    } catch (_) {}
    try {
      await _castService?.dispose();
    } catch (_) {}

    _session = null;
    _castService = null;
    _isConnected = false;
    _currentTitle = '';
    _videoUrl = '';
    _headers = {};
    _backdropUrl = '';
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    introStartSec = null;
    introEndSec = null;
    outroStartSec = null;
    outroEndSec = null;

    if (showNotif) {
      try {
        await _notif.cancel(_notifId);
      } catch (_) {}
    }

    await _stopForegroundServiceIfNeeded();
    if (!_connectedController.isClosed) _connectedController.add(false);
  }

  // ── Botones de la notificación (máx 3 en Android) ─────────────────────
  List<NotificationButton> _castButtons() {
    return [
      NotificationButton(
        id: _isPlaying ? 'cast_pause' : 'cast_play',
        text: _isPlaying ? 'Pausa' : 'Play',
      ),
      const NotificationButton(
        id: 'cast_stop',
        text: 'Detener',
      ),
      const NotificationButton(
        id: 'cast_seek_fwd',
        text: '+10s',
      ),
    ];
  }

  // ── Notificación local CON botones (Play / Pausa / Detener) ────────────
  Future<void> _showCastNotification(String title) async {
    final body = title.isNotEmpty
        ? title
        : 'Reproduciendo en Chromecast / TV';

    final androidDetails = AndroidNotificationDetails(
      'cast_controls_channel',
      'Controles de Cast',
      channelDescription: 'Play, pausa y detener mientras se transmite a la TV',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      category: AndroidNotificationCategory.transport,
      playSound: false,
      enableVibration: false,
      onlyAlertOnce: true,
      // Botones visibles al expandir la notificación
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          _isPlaying ? 'cast_pause' : 'cast_play',
          _isPlaying ? 'Pausa' : 'Play',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          'cast_stop',
          'Detener',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          'cast_seek_fwd',
          '+10s',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    await _notif.show(
      _notifId,
      'Transmitiendo a TV',
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _updateNotificationText() async {
    if (!_isConnected) return;
    final posStr = _fmt(_position);
    final durStr = _duration > Duration.zero ? ' / ${_fmt(_duration)}' : '';
    final state = _isPlaying ? '▶' : '⏸';
    final text =
        '$_currentTitle  ·  $state $posStr$durStr';

    // 1) Actualizar notificación local (con botones de acción)
    try {
      await _showCastNotification(text);
    } catch (_) {}

    // 2) Actualizar Foreground Service (mantiene proceso vivo + botones)
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Transmitiendo a TV',
          notificationText: text,
          notificationButtons: _castButtons(),
        );
      }
    } catch (_) {}
  }

  void _startNotifTicker() {
    _notifUpdateTimer?.cancel();
    // Actualiza cada 3 s el texto + botones de la notificación
    _notifUpdateTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_isConnected) _updateNotificationText();
    });
  }

  // ── Foreground Service ──────────────────────────────────────────────────
  Future<void> _startForegroundService(String title) async {
    final text = title.isNotEmpty
        ? title
        : 'Reproduciendo en Chromecast / TV';

    // Si ya hay servicio (p. ej. descarga), solo actualizamos título + botones
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Transmitiendo a TV',
        notificationText: text,
        notificationButtons: _castButtons(),
      );
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Transmitiendo a TV',
      notificationText: text,
      notificationButtons: _castButtons(),
      callback: startCastCallback,
    );
  }

  Future<void> _stopForegroundServiceIfNeeded() async {
    if (await FlutterForegroundTask.isRunningService && !_isConnected) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
    }
  }

  /// Llamar desde TaskHandler / NotificationHelper cuando se pulsa un botón.
  Future<void> handleNotificationButton(String id) async {
    switch (id) {
      case 'cast_play':
        await play();
        await _updateNotificationText();
        break;
      case 'cast_pause':
        await pause();
        await _updateNotificationText();
        break;
      case 'cast_stop':
        await disconnect();
        break;
      case 'cast_seek_back':
        await seekRelative(-10);
        break;
      case 'cast_seek_fwd':
        await seekRelative(10);
        break;
    }
  }

  void disposeStreams() {
    _positionController.close();
    _playingController.close();
    _connectedController.close();
  }
}

// ── Callback obligatorio del Foreground Service ───────────────────────────
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

  @override
  void onNotificationButtonPressed(String id) {
    // Enviar al main isolate → CastManager.handleNotificationButton
    // ids: cast_play | cast_pause | cast_stop | cast_seek_fwd | cast_seek_back
    FlutterForegroundTask.sendDataToMain({'cast_btn': id});
  }

  @override
  void onNotificationPressed() {
    // Tocar la notificación → abrir app (comportamiento por defecto)
  }
}