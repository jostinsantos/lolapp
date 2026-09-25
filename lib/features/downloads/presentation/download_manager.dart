import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_helper.dart';

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class ActiveDownload {
  final String id;
  final String titulo;
  final int? temporada;
  final int? capitulo;
  final String m3u8Url;
  // Metadatos para offline
  final int? tmdbId;
  final String? tipo; // 'movie' | 'tv'
  final String? posterUrl;
  final String? backdropUrl;

  DownloadStatus status;
  double progress;
  String statusText;
  int completedSegments;
  int totalSegments;
  DateTime startedAt;
  DateTime? lastUpdate;
  String? folderPath;
  String? playlistPath;
  String? error;
  double speedBps;
  CancelToken? cancelToken;
  int attempt;

  ActiveDownload({
    required this.id,
    required this.titulo,
    this.temporada,
    this.capitulo,
    required this.m3u8Url,
    this.tmdbId,
    this.tipo,
    this.posterUrl,
    this.backdropUrl,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.statusText = 'En cola…',
    this.completedSegments = 0,
    this.totalSegments = 0,
    DateTime? startedAt,
    this.speedBps = 0,
    this.cancelToken,
    this.attempt = 1,
  }) : startedAt = startedAt ?? DateTime.now();

  String get displayTitle {
    var t = titulo;
    if (temporada != null && capitulo != null) {
      final s = temporada!.toString().padLeft(2, '0');
      final e = capitulo!.toString().padLeft(2, '0');
      t = '$t · T$s C$e';
    }
    return t;
  }

  int? get etaSeconds {
    if (progress <= 0.02 || totalSegments <= 0) return null;
    final remaining = totalSegments - completedSegments;
    if (remaining <= 0) return 0;
    final elapsed =
        DateTime.now().difference(startedAt).inMilliseconds / 1000.0;
    if (elapsed < 1 || completedSegments < 1) return null;
    final segPerSec = completedSegments / elapsed;
    if (segPerSec <= 0) return null;
    return (remaining / segPerSec).round();
  }

  String get etaLabel {
    final s = etaSeconds;
    if (s == null) return 'Calculando…';
    if (s < 60) return '~$s s';
    final m = s ~/ 60;
    final r = s % 60;
    if (m < 60) return '~$m min ${r}s';
    final h = m ~/ 60;
    return '~$h h ${m % 60} min';
  }

  int get notificationId => id.hashCode & 0x7FFFFFFF;
}

// ── Callback del Foreground Service (obligatorio) ───────────────────────────
@pragma('vm:entry-point')
void startDownloadCallback() {
  FlutterForegroundTask.setTaskHandler(DownloadTaskHandler());
}

class DownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Se llama cada 5 s; la descarga real corre en el isolate principal
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final Map<String, ActiveDownload> _active = {};
  final Dio _dio = Dio();

  static const String _kConcurrencyKey = 'download_segment_concurrency';
  static const int _defaultConcurrency = 3;

  /// Reintentos de la descarga completa (p. ej. si el SO hiberna la app).
  static const int _maxDownloadRetries = 3;

  /// Reintentos por segmento individual (red intermitente).
  static const int _maxSegmentRetries = 3;

  int _segmentConcurrency = _defaultConcurrency;

  int get segmentConcurrency => _segmentConcurrency;

  /// Cargar hilos guardados (llamar al iniciar la app o la página de descargas)
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _segmentConcurrency =
          (prefs.getInt(_kConcurrencyKey) ?? _defaultConcurrency).clamp(1, 8);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setSegmentConcurrency(int value) async {
    final v = value.clamp(1, 8);
    _segmentConcurrency = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kConcurrencyKey, v);
    } catch (_) {}
    notifyListeners();
  }

  List<ActiveDownload> get activeDownloads => _active.values
      .where(
        (d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued,
      )
      .toList();

  List<ActiveDownload> get all => _active.values.toList();

  ActiveDownload? get(String id) => _active[id];

  Future<Directory> getBaseDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/lolplustv_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeName(String titulo, {int? temporada, int? capitulo}) {
    var name = titulo
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    if (name.isEmpty) name = 'video';
    if (temporada != null && capitulo != null) {
      final t = temporada.toString().padLeft(2, '0');
      final c = capitulo.toString().padLeft(2, '0');
      name = '${name}_T${t}C$c';
    }
    return name;
  }

  String _formatStartTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _notificationBody(ActiveDownload item) {
    final pct = (item.progress * 100).round().clamp(0, 100);
    final start = _formatStartTime(item.startedAt);
    final retry = item.attempt > 1 ? ' · Reintento ${item.attempt}' : '';
    return '$pct% · ${item.etaLabel} · Inicio $start$retry';
  }

  // ── Foreground Service ─────────────────────────────────────────────────

  Future<void> _startForegroundService(ActiveDownload item) async {
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      notificationTitle: item.displayTitle,
      notificationText: _notificationBody(item),
      callback: startDownloadCallback,
    );
  }

  Future<void> _updateForegroundNotification(ActiveDownload item) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: item.displayTitle,
      notificationText: _notificationBody(item),
    );
  }

  Future<void> _stopForegroundServiceIfNeeded() async {
    final stillActive = _active.values.any(
      (d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.queued,
    );
    if (!stillActive && await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Convierte URL de TMDB a baja calidad para que ocupe poco espacio
  String _lowQualityUrl(String url, {bool isBackdrop = false}) {
    if (url.contains('image.tmdb.org') || url.contains('/t/p/')) {
      final size = isBackdrop ? 'w300' : 'w185'; // muy pequeño
      return url.replaceAllMapped(RegExp(r'/t/p/[^/]+/'), (m) => '/t/p/$size/');
    }
    return url; // si no es TMDB, descarga tal cual
  }

  /// Marca en SharedPreferences que este contenido/capítulo está descargado
  Future<void> _markDownloadedInCache(ActiveDownload item) async {
    if (item.tmdbId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key =
          item.tipo == 'tv' && item.temporada != null && item.capitulo != null
          ? 'downloaded_${item.tmdbId}_T${item.temporada}_C${item.capitulo}'
          : 'downloaded_${item.tmdbId}';
      await prefs.setBool(key, true);
      // Lista global de descargados (opcional, para UI rápida)
      final listKey = 'downloaded_list';
      final raw = prefs.getString(listKey);
      final list = raw != null
          ? List<String>.from(jsonDecode(raw) as List)
          : <String>[];
      if (!list.contains(key)) {
        list.add(key);
        await prefs.setString(listKey, jsonEncode(list));
      }
    } catch (_) {}
  }

  static Future<bool> isDownloaded({
    required int tmdbId,
    String? tipo,
    int? temporada,
    int? capitulo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = tipo == 'tv' && temporada != null && capitulo != null
          ? 'downloaded_${tmdbId}_T${temporada}_C$capitulo'
          : 'downloaded_$tmdbId';
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Quita la marca de descargado en SharedPreferences (al borrar la carpeta).
  Future<void> unmarkDownloaded({
    int? tmdbId,
    String? tipo,
    int? temporada,
    int? capitulo,
  }) async {
    if (tmdbId == null || tmdbId <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = tipo == 'tv' && temporada != null && capitulo != null
          ? 'downloaded_${tmdbId}_T${temporada}_C$capitulo'
          : 'downloaded_$tmdbId';
      await prefs.remove(key);

      final listKey = 'downloaded_list';
      final raw = prefs.getString(listKey);
      if (raw != null) {
        final list = List<String>.from(jsonDecode(raw) as List);
        list.remove(key);
        await prefs.setString(listKey, jsonEncode(list));
      }
    } catch (_) {}
  }

  Future<String> startHlsDownload({
    required String m3u8Url,
    required String titulo,
    int? temporada,
    int? capitulo,
    int? tmdbId,
    String? tipo,
    String? posterUrl,
    String? backdropUrl,
  }) async {
    final id = '${DateTime.now().millisecondsSinceEpoch}_$titulo';
    final item = ActiveDownload(
      id: id,
      titulo: titulo,
      temporada: temporada,
      capitulo: capitulo,
      m3u8Url: m3u8Url,
      tmdbId: tmdbId,
      tipo: tipo,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      status: DownloadStatus.downloading,
      statusText: 'Preparando…',
      cancelToken: CancelToken(),
      attempt: 1,
    );
    _active[id] = item;
    notifyListeners();

    // Arrancar Foreground Service (mantiene la app viva en segundo plano)
    unawaited(_startForegroundService(item));

    unawaited(
      NotificationHelper.showProgress(
        id: item.notificationId,
        title: item.displayTitle,
        progress: 0,
        body: _notificationBody(item),
      ),
    );

    unawaited(_runDownload(item));
    return id;
  }

  /// true si el error es cancelación del usuario (no reintentar).
  bool _isUserCancel(Object e) {
    if (e is DioException && e.type == DioExceptionType.cancel) return true;
    return false;
  }

  /// Descarga un segmento con reintentos (red / hibernación breve).
  Future<void> _downloadSegmentWithRetry({
    required String url,
    required String localPath,
    required CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (var tryN = 1; tryN <= _maxSegmentRetries; tryN++) {
      if (cancelToken?.isCancelled == true) {
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.cancel,
          error: 'Usuario',
        );
      }
      try {
        // Si quedó un archivo a medias de un intento anterior, borrar
        final f = File(localPath);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
        await _dio.download(
          url,
          localPath,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            receiveTimeout: const Duration(minutes: 3),
            sendTimeout: const Duration(seconds: 30),
          ),
        );
        // Comprobar que el archivo existe y no está vacío
        if (!await f.exists() || await f.length() == 0) {
          throw Exception('Segmento vacío o no escrito');
        }
        return;
      } catch (e) {
        lastError = e;
        if (_isUserCancel(e)) rethrow;
        if (tryN < _maxSegmentRetries) {
          // Espera creciente: 1s, 2s, 4s…
          final delaySec = 1 << (tryN - 1);
          await Future.delayed(Duration(seconds: delaySec));
        }
      }
    }
    throw lastError ?? Exception('Fallo al descargar segmento');
  }

  Future<void> _runDownload(ActiveDownload item) async {
    Object? lastError;

    for (
      var attempt = item.attempt;
      attempt <= _maxDownloadRetries;
      attempt++
    ) {
      item.attempt = attempt;
      // Nuevo CancelToken por intento (el anterior puede estar cancelado)
      if (item.cancelToken == null || item.cancelToken!.isCancelled) {
        item.cancelToken = CancelToken();
      }

      try {
        await _runDownloadOnce(item);
        await _stopForegroundServiceIfNeeded();
        return; // éxito
      } catch (e) {
        lastError = e;
        if (_isUserCancel(e)) {
          item.status = DownloadStatus.cancelled;
          item.statusText = 'Cancelado';
          notifyListeners();
          await NotificationHelper.cancel(item.notificationId);
          await _stopForegroundServiceIfNeeded();
          return;
        }

        if (attempt < _maxDownloadRetries) {
          item.status = DownloadStatus.downloading;
          item.statusText = 'Reintentando ($attempt/$_maxDownloadRetries)…';
          item.progress = 0.02;
          item.completedSegments = 0;
          notifyListeners();
          await _updateNotification(item);
          // Pausa antes del siguiente intento (hibernación / red)
          final delaySec = 2 * attempt; // 2s, 4s, 6s…
          await Future.delayed(Duration(seconds: delaySec));
          if (item.cancelToken?.isCancelled == true) {
            item.status = DownloadStatus.cancelled;
            item.statusText = 'Cancelado';
            notifyListeners();
            await NotificationHelper.cancel(item.notificationId);
            await _stopForegroundServiceIfNeeded();
            return;
          }
          continue;
        }

        // Agotados los reintentos
        item.status = DownloadStatus.failed;
        item.statusText = 'Error';
        item.error = e.toString();
        notifyListeners();
        await NotificationHelper.cancel(item.notificationId);
        await _stopForegroundServiceIfNeeded();
        return;
      }
    }

    // Fallback por si no entró en el catch final
    item.status = DownloadStatus.failed;
    item.statusText = 'Error';
    item.error = lastError?.toString() ?? 'Error desconocido';
    notifyListeners();
    await NotificationHelper.cancel(item.notificationId);
    await _stopForegroundServiceIfNeeded();
  }

  Future<void> _runDownloadOnce(ActiveDownload item) async {
    final baseDir = await getBaseDir();
    final folderName = _safeName(
      item.titulo,
      temporada: item.temporada,
      capitulo: item.capitulo,
    );
    final contentDir = Directory('${baseDir.path}/$folderName');
    if (await contentDir.exists()) await contentDir.delete(recursive: true);
    await contentDir.create(recursive: true);

    item.status = DownloadStatus.downloading;
    item.statusText = item.attempt > 1
        ? 'Reintento ${item.attempt}: playlist…'
        : 'Descargando playlist…';
    item.progress = 0.02;
    item.completedSegments = 0;
    item.totalSegments = 0;
    notifyListeners();
    await _updateNotification(item);

    final playlistResponse = await _dio.get<String>(
      item.m3u8Url,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 30),
      ),
      cancelToken: item.cancelToken,
    );
    String playlistContent = playlistResponse.data ?? '';
    if (playlistContent.isEmpty) throw Exception('Playlist vacío');

    final baseUri = Uri.parse(item.m3u8Url);
    final mediaUrl = _findFirstMediaPlaylist(playlistContent, baseUri);
    Uri resolvedBase = baseUri;

    if (mediaUrl != null) {
      item.statusText = 'Seleccionando calidad…';
      item.progress = 0.05;
      notifyListeners();
      await _updateNotification(item);

      final mediaRes = await _dio.get<String>(
        mediaUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 30),
        ),
        cancelToken: item.cancelToken,
      );
      playlistContent = mediaRes.data ?? '';
      if (playlistContent.isEmpty) throw Exception('Media playlist vacío');
      resolvedBase = Uri.parse(mediaUrl);
    }

    final lines = playlistContent.split('\n');
    final segmentUrls = <String>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      segmentUrls.add(resolvedBase.resolve(t).toString());
    }
    if (segmentUrls.isEmpty) throw Exception('Sin segmentos');

    item.totalSegments = segmentUrls.length;
    item.completedSegments = 0;
    final localNames = List<String?>.filled(segmentUrls.length, null);
    final start = DateTime.now();
    const notifyEvery = 3;
    final concurrency = _segmentConcurrency;

    for (var i = 0; i < segmentUrls.length; i += concurrency) {
      if (item.cancelToken?.isCancelled == true) {
        throw DioException(
          requestOptions: RequestOptions(path: item.m3u8Url),
          type: DioExceptionType.cancel,
          error: 'Usuario',
        );
      }

      final end = (i + concurrency < segmentUrls.length)
          ? i + concurrency
          : segmentUrls.length;

      final batch = <Future<void>>[];
      for (var j = i; j < end; j++) {
        final index = j;
        final fileName = 'seg_${index.toString().padLeft(5, '0')}.ts';
        final localPath = '${contentDir.path}/$fileName';

        batch.add(
          _downloadSegmentWithRetry(
            url: segmentUrls[index],
            localPath: localPath,
            cancelToken: item.cancelToken,
          ).then((_) {
            localNames[index] = fileName;
          }),
        );
      }

      await Future.wait(batch);

      item.completedSegments = end;
      item.progress = 0.05 + (0.90 * end / segmentUrls.length);
      item.statusText = 'Segmento $end/${segmentUrls.length}';
      item.lastUpdate = DateTime.now();

      final elapsed = DateTime.now().difference(start).inMilliseconds / 1000.0;
      if (elapsed > 0.5) {
        item.speedBps = end / elapsed;
      }

      notifyListeners();

      if (end % notifyEvery == 0 || end == segmentUrls.length) {
        await _updateNotification(item);
      }
    }

    if (localNames.any((n) => n == null)) {
      throw Exception('Faltan segmentos descargados');
    }

    // Playlist local
    final buf = StringBuffer();
    var idx = 0;
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) {
        buf.writeln(line);
        continue;
      }
      if (idx < localNames.length) {
        buf.writeln(localNames[idx]!);
        idx++;
      }
    }
    final localM3u8 = '${contentDir.path}/playlist.m3u8';
    await File(localM3u8).writeAsString(buf.toString());

    // ─── Descargar poster y backdrop en BAJA CALIDAD ───────────────────
    String? localPosterFile;
    String? localBackdropFile;

    if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
      try {
        final lowUrl = _lowQualityUrl(item.posterUrl!);
        final posterPath = '${contentDir.path}/poster.jpg';
        await _dio.download(
          lowUrl,
          posterPath,
          cancelToken: item.cancelToken,
          options: Options(followRedirects: true),
        );
        localPosterFile = 'poster.jpg';
      } catch (_) {}
    }

    if (item.backdropUrl != null && item.backdropUrl!.isNotEmpty) {
      try {
        final lowUrl = _lowQualityUrl(item.backdropUrl!, isBackdrop: true);
        final backdropPath = '${contentDir.path}/backdrop.jpg';
        await _dio.download(
          lowUrl,
          backdropPath,
          cancelToken: item.cancelToken,
          options: Options(followRedirects: true),
        );
        localBackdropFile = 'backdrop.jpg';
      } catch (_) {}
    }

    // Metadatos offline (incluye archivos locales de las imágenes)
    final meta = <String, dynamic>{
      'titulo': item.titulo,
      'tmdbId': item.tmdbId,
      'tipo': item.tipo,
      'temporada': item.temporada,
      'capitulo': item.capitulo,
      'posterUrl': item.posterUrl,
      'backdropUrl': item.backdropUrl,
      'posterFile': localPosterFile,
      'backdropFile': localBackdropFile,
      'downloadedAt': DateTime.now().toIso8601String(),
    };
    await File('${contentDir.path}/meta.json').writeAsString(jsonEncode(meta));

    item.folderPath = contentDir.path;
    item.playlistPath = localM3u8;
    item.progress = 1.0;
    item.status = DownloadStatus.completed;
    item.statusText = 'Completado';
    notifyListeners();

    await _markDownloadedInCache(item);

    await NotificationHelper.showCompleted(
      id: item.notificationId,
      title: item.displayTitle,
    );
  }

  Future<void> _updateNotification(ActiveDownload item) async {
    await NotificationHelper.showProgress(
      id: item.notificationId,
      title: item.displayTitle,
      progress: (item.progress * 100).round().clamp(0, 100),
      body: _notificationBody(item),
    );
    // Actualizar también la notificación del Foreground Service
    await _updateForegroundNotification(item);
  }

  void cancel(String id) {
    final item = _active[id];
    if (item == null) return;
    item.cancelToken?.cancel('Usuario');
  }

  void remove(String id) {
    final item = _active[id];
    if (item != null) {
      unawaited(NotificationHelper.cancel(item.notificationId));
    }
    _active.remove(id);
    notifyListeners();
    unawaited(_stopForegroundServiceIfNeeded());
  }

  String? _findFirstMediaPlaylist(String content, Uri baseUri) {
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('#EXT-X-STREAM-INF')) {
        for (var j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isNotEmpty && !next.startsWith('#')) {
            return baseUri.resolve(next).toString();
          }
        }
      }
    }
    return null;
  }

  Future<({int usedBytes, int freeBytes})> storageStats() async {
    final base = await getBaseDir();
    int used = 0;
    try {
      await for (final e in base.list(recursive: true)) {
        if (e is File) used += await e.length();
      }
    } catch (_) {}
    return (usedBytes: used, freeBytes: 0);
  }
}