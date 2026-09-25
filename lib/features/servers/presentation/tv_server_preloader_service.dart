import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/aggregators/source_aggregator.dart';
/// Servicio global de precarga silenciosa de servidores.
///
/// Uso típico (una sola vez al arrancar la app):
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   ServidoresPreloaderService.instance.start();
///   runApp(MyApp());
/// }
/// ```
///
/// O en el primer frame de la home:
/// ```dart
/// ServidoresPreloaderService.instance.start();
/// ```
///
/// Desde el modal / player al reproducir un episodio:
/// ```dart
/// ServidoresPreloaderService.instance.scheduleFromEpisode(
///   tmdbId: id,
///   season: t,
///   episode: c,
/// );
/// ```
class ServidoresPreloaderService {
  ServidoresPreloaderService._();
  static final ServidoresPreloaderService instance =
      ServidoresPreloaderService._();

  static const _kCapitulosPrecarga = 'capitulos_precarga';
  static const _kDefaultCapitulos = 2;
  static const _kMaxParallel = 1;

  final MainFuentes _fuentes = MainFuentes();
  final List<_PreloadJob> _queue = [];
  final Set<String> _queuedKeys = {};
  final Set<String> _inFlight = {};
  bool _running = false;
  bool _started = false;
  int _active = 0;

  bool get isStarted => _started;

  /// Activa el worker. Seguro llamar varias veces.
  void start() {
    if (_started) return;
    _started = true;
    _pump();
  }

  /// Lee cuántos capítulos precargar (config).
  static Future<int> capitulosPrecarga() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = p.getInt(_kCapitulosPrecarga);
      if (n == null) return _kDefaultCapitulos;
      return n.clamp(0, 10);
    } catch (_) {
      return _kDefaultCapitulos;
    }
  }

  static Future<void> setCapitulosPrecarga(int n) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCapitulosPrecarga, n.clamp(0, 10));
  }

  /// Encola los siguientes N episodios de la misma temporada.
  Future<void> scheduleFromEpisode({
    required int tmdbId,
    required int season,
    required int episode,
    int? count,
  }) async {
    if (tmdbId <= 0 || season <= 0) return;
    start();
    final n = count ?? await capitulosPrecarga();
    if (n <= 0) return;

    for (var i = 1; i <= n; i++) {
      _enqueue(
        tmdbId: tmdbId,
        tipo: 'tv',
        season: season,
        episode: episode + i,
      );
    }
    _pump();
  }

  /// Precarga un contenido concreto (película o episodio).
  void scheduleContent({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) {
    if (tmdbId <= 0) return;
    start();
    _enqueue(
      tmdbId: tmdbId,
      tipo: tipo,
      season: season,
      episode: episode,
    );
    _pump();
  }

  void _enqueue({
    required int tmdbId,
    required String tipo,
    required int season,
    required int episode,
  }) {
    final key = '$tmdbId|$tipo|$season|$episode';
    if (_queuedKeys.contains(key) || _inFlight.contains(key)) return;
    _queuedKeys.add(key);
    _queue.add(_PreloadJob(
      tmdbId: tmdbId,
      tipo: tipo,
      season: season,
      episode: episode,
      key: key,
    ));
  }

  void _pump() {
    if (!_started) return;
    while (_active < _kMaxParallel && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _queuedKeys.remove(job.key);
      _active++;
      _inFlight.add(job.key);
      _runJob(job).whenComplete(() {
        _active--;
        _inFlight.remove(job.key);
        _pump();
      });
    }
  }

  Future<void> _runJob(_PreloadJob job) async {
    try {
      final existing = await FuentesCache.loadServers(
        tmdbId: job.tmdbId,
        tipo: job.tipo,
        season: job.season,
        episode: job.episode,
      );
      if (existing != null && existing.isNotEmpty) return;

      await _fuentes.loadConfig();
      final cfg = _fuentes.config;
      if (cfg.fuentesActivas.isEmpty) return;

      final collected = <Map<String, dynamic>>[];
      final seen = <String>{};
      final isMovie = job.tipo == 'movie';

      await for (final event in _fuentes.fetchProgressive(
        tmdbId: job.tmdbId,
        isMovie: isMovie,
        season: isMovie ? 1 : job.season,
        episode: isMovie ? 1 : job.episode,
        context: null,
      )) {
        if (event.isDone) continue;
        final map = event.servidor;
        if (map == null) continue;
        final url = map['servidor_url']?.toString() ?? '';
        if (url.isEmpty || seen.contains(url)) continue;
        seen.add(url);
        collected.add(map);
        if (collected.length >= 8) break;
      }

      if (collected.isNotEmpty) {
        await FuentesCache.saveServers(
          tmdbId: job.tmdbId,
          tipo: job.tipo,
          season: job.season,
          episode: job.episode,
          servidores: collected,
        );
      }
    } catch (_) {}
  }

  /// Cancela trabajos pendientes (no interrumpe el que ya corre).
  void clearQueue() {
    _queue.clear();
    _queuedKeys.clear();
  }
}

class _PreloadJob {
  final int tmdbId;
  final String tipo;
  final int season;
  final int episode;
  final String key;

  const _PreloadJob({
    required this.tmdbId,
    required this.tipo,
    required this.season,
    required this.episode,
    required this.key,
  });
}