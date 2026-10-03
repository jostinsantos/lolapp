import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/tmdb_apis.dart';

/// Resultado: ¿está en emisión? + lista de capítulos por estrenar.
class UpcomingEpisodesResult {
  final bool isAiring;
  final String status;
  final List<Map<String, dynamic>> episodes;

  const UpcomingEpisodesResult({
    required this.isAiring,
    required this.status,
    required this.episodes,
  });

  static const empty = UpcomingEpisodesResult(
    isAiring: false,
    status: '',
    episodes: [],
  );
}

/// Servicio solo para capítulos futuros de series **en emisión**.
///
/// TMDB `status` típicos:
/// - Returning Series / In Production → en emisión (mostrar campana)
/// - Ended / Canceled / Pilot → no
class TmdbUpcomingService {
  static const _base = 'https://api.themoviedb.org/3';
  static const _headers = {'Accept': 'application/json'};

  /// Estados que consideramos "en emisión" / activos.
  static const _airingStatuses = {
    'returning series',
    'in production',
    'planned',
  };

  Future<String> _language() async {
    try {
      return await TmdbApis.getLanguage();
    } catch (_) {
      return 'es-MX';
    }
  }

  Future<String> _apiKey() async {
    try {
      return await TmdbApis.getApiKey();
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>?> _get(
    String path, {
    Map<String, String>? query,
    required String language,
  }) async {
    final key = await _apiKey();
    if (key.isEmpty) return null;
    final q = <String, String>{
      'api_key': key,
      'language': language,
      ...?query,
    };
    final uri = Uri.parse('$_base$path').replace(queryParameters: q);
    try {
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 16));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 1) Comprueba si la serie está en emisión.
  /// 2) Si lo está, trae temporadas y filtra episodios con air_date >= hoy.
  Future<UpcomingEpisodesResult> fetchUpcoming({
    required int tmdbId,
  }) async {
    final language = await _language();

    // Detail: status + lista de temporadas
    final detail = await _get('/tv/$tmdbId', language: language);
    if (detail == null) return UpcomingEpisodesResult.empty;

    final status = (detail['status']?.toString() ?? '').trim();
    final statusLower = status.toLowerCase();
    final isAiring = _airingStatuses.contains(statusLower);

    if (!isAiring) {
      return UpcomingEpisodesResult(
        isAiring: false,
        status: status,
        episodes: const [],
      );
    }

    final seasonsMeta = detail['seasons'] is List
        ? List<Map<String, dynamic>>.from(
            (detail['seasons'] as List).whereType<Map>().map(
                  (e) => Map<String, dynamic>.from(e),
                ),
          )
        : <Map<String, dynamic>>[];

    // Preferencia: ¿mostrar temporada 0 (especiales)?
    bool showSpecials = false;
    try {
      final p = await SharedPreferences.getInstance();
      showSpecials = p.getBool('show_season_specials') ?? false;
    } catch (_) {}

    final seasonNumbers = seasonsMeta
        .map((s) => s['season_number'] as int? ?? -1)
        .where((n) {
          if (n < 0) return false;
          if (n == 0 && !showSpecials) return false;
          return true;
        })
        .toSet()
        .toList()
      ..sort();

    if (seasonNumbers.isEmpty) {
      return UpcomingEpisodesResult(
        isAiring: true,
        status: status,
        episodes: const [],
      );
    }

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final futures = seasonNumbers.map((n) async {
      final data = await _get('/tv/$tmdbId/season/$n', language: language);
      if (data == null) return <Map<String, dynamic>>[];

      final epsRaw = data['episodes'] is List
          ? List<Map<String, dynamic>>.from(
              (data['episodes'] as List).whereType<Map>().map(
                    (e) => Map<String, dynamic>.from(e),
                  ),
            )
          : <Map<String, dynamic>>[];

      final upcoming = <Map<String, dynamic>>[];
      for (final ep in epsRaw) {
        final airRaw = ep['air_date']?.toString() ?? '';
        if (airRaw.isEmpty) continue;
        final air = DateTime.tryParse(airRaw);
        if (air == null) continue;
        final airDay = DateTime(air.year, air.month, air.day);
        // Solo hoy o futuro
        if (airDay.isBefore(startOfToday)) continue;

        upcoming.add({
          'id': ep['id'],
          'episode_number': ep['episode_number'],
          'season_number': ep['season_number'] ?? n,
          'name': ep['name']?.toString() ??
              'Episodio ${ep['episode_number'] ?? ''}',
          'overview': ep['overview']?.toString() ?? '',
          'still_path': ep['still_path']?.toString() ?? '',
          'air_date': airRaw,
          'runtime': ep['runtime'],
          'vote_average': ep['vote_average'],
        });
      }
      return upcoming;
    });

    final lists = await Future.wait(futures);
    final all = lists.expand((e) => e).toList();

    all.sort((a, b) {
      final da = DateTime.tryParse(a['air_date']?.toString() ?? '') ??
          DateTime(2099);
      final db = DateTime.tryParse(b['air_date']?.toString() ?? '') ??
          DateTime(2099);
      return da.compareTo(db);
    });

    return UpcomingEpisodesResult(
      isAiring: true,
      status: status,
      episodes: all,
    );
  }

  /// Solo comprueba status (rápido, para mostrar/ocultar el icono).
  Future<bool> isSeriesAiring(int tmdbId) async {
    final language = await _language();
    final detail = await _get('/tv/$tmdbId', language: language);
    if (detail == null) return false;
    final status = (detail['status']?.toString() ?? '').toLowerCase().trim();
    return _airingStatuses.contains(status);
  }
}