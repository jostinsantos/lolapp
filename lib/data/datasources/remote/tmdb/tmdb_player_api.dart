import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/tmdb_apis.dart';

class TmdbPlayerService {
  static const String _apiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5'; // unused fallback
  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
  };

  Future<String> _apiLanguage() async {
    return TmdbApis.getLanguage();
  }

  Future<({bool showSpecials, bool showUnreleasedEps})> _episodePrefs() async {
    final p = await SharedPreferences.getInstance();
    return (
      showSpecials: p.getBool('show_season_specials') ?? false,
      showUnreleasedEps: p.getBool('show_unreleased_episodes') ?? false,
    );
  }

  Future<Map<String, dynamic>?> _get(
    String path, {
    Map<String, String>? query,
    required String language,
  }) async {
    final q = <String, String>{
      'api_key': await TmdbApis.getApiKey(),
      'language': language,
      ...?query,
    };
    final uri = Uri.parse('$_base$path').replace(queryParameters: q);
    try {
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 16));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return null;
      if (body['success'] == false) return null;
      return body;
    } catch (_) {
      return null;
    }
  }

  String? _tmdbUrl(String? path, {String size = 'original'}) {
    if (path == null || path.isEmpty || path == 'null') return null;
    var p = path.trim();
    if ((p.startsWith('[') && p.endsWith(']')) ||
        (p.startsWith('"') && p.endsWith('"'))) {
      try {
        final decoded = jsonDecode(p);
        if (decoded is List && decoded.isNotEmpty) {
          p = decoded.first.toString();
        } else if (decoded is String) {
          p = decoded;
        }
      } catch (_) {}
    }
    p = p.trim().replaceAll(RegExp(r'''^["']+|["']+$'''), '');
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('/')) return '$_imgBase/$size$p';
    if (p.isNotEmpty) {
      return '$_imgBase/$size/${p.replaceFirst(RegExp(r'^/+'), '')}';
    }
    return null;
  }

  String _formatoS00E00(int temp, int cap) {
    final s = temp.toString().padLeft(2, '0');
    final e = cap.toString().padLeft(2, '0');
    return 's${s}e$e';
  }

  bool _isUnreleased(String? airDate, DateTime now) {
    if (airDate == null || airDate.isEmpty) return false;
    final d = DateTime.tryParse(airDate);
    if (d == null) return false;
    // Solo día (sin hora): si es hoy o pasado → estrenado
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(d.year, d.month, d.day);
    return dateOnly.isAfter(today);
  }

  /// True si ya se estrenó (tiene fecha y no es futura).
  /// Sin fecha se considera NO estrenado (evita trailers / anuncios).
  bool _isReleased(String? dateStr, DateTime now) {
    if (dateStr == null || dateStr.isEmpty) return false;
    return !_isUnreleased(dateStr, now);
  }

  Future<String?> _fetchLogo({
    required int tmdbId,
    required bool isMovie,
    required String language,
  }) async {
    final path = isMovie ? '/movie/$tmdbId/images' : '/tv/$tmdbId/images';
    final data = await _get(
      path,
      query: {'include_image_language': '$language,null,en,es-MX,es'},
      language: language,
    );
    if (data == null) return null;

    final logos = (data['logos'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['logos'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    if (logos.isEmpty) return null;

    final langCode = language.split('-').first;
    Map<String, dynamic>? pick;

    for (final l in logos) {
      if ((l['iso_639_1']?.toString() ?? '') == langCode) {
        pick = l;
        break;
      }
    }
    pick ??= logos.cast<Map<String, dynamic>?>().firstWhere(
          (l) {
            final iso = l?['iso_639_1'];
            return iso == null || (iso is String && iso.isEmpty);
          },
          orElse: () => null,
        );
    if (pick == null) {
      for (final l in logos) {
        if ((l['iso_639_1']?.toString() ?? '') == 'en') {
          pick = l;
          break;
        }
      }
    }
    pick ??= logos.first;

    final file = pick['file_path']?.toString() ?? '';
    return file.isEmpty ? null : _tmdbUrl(file, size: 'w500');
  }

  Future<Map<String, dynamic>> fetchPlayer({
    required int tmdbId,
    required String mediaType,
    int temporada = 0,
    int capitulo = 0,
  }) async {
    if (tmdbId <= 0) {
      return {
        'error': true,
        'mensaje': 'Falta el parámetro tmdbId / idcontenido',
      };
    }

    final isMovie = mediaType.toLowerCase() != 'tv';
    final language = await _apiLanguage();

    if (isMovie) {
      return _fetchMoviePlayer(tmdbId: tmdbId, language: language);
    }
    return _fetchTvPlayer(
      tmdbId: tmdbId,
      language: language,
      temporada: temporada,
      capitulo: capitulo,
    );
  }

  Future<Map<String, dynamic>> _fetchMoviePlayer({
    required int tmdbId,
    required String language,
  }) async {
    final detail = await _get(
      '/movie/$tmdbId',
      query: {
        'append_to_response':
            'external_ids,recommendations,belongs_to_collection',
      },
      language: language,
    );

    if (detail == null) {
      return {
        'error': true,
        'mensaje': 'Contenido no encontrado',
      };
    }

    final external = detail['external_ids'] is Map
        ? Map<String, dynamic>.from(detail['external_ids'] as Map)
        : <String, dynamic>{};
    final imdbId =
        (external['imdb_id'] ?? detail['imdb_id'] ?? '').toString();

    final logoFuture = _fetchLogo(
      tmdbId: tmdbId,
      isMovie: true,
      language: language,
    );

    final collectionId = detail['belongs_to_collection'] is Map
        ? (detail['belongs_to_collection'] as Map)['id'] as int?
        : null;

    Future<List<Map<String, dynamic>>> recsFuture;
    if (collectionId != null && collectionId > 0) {
      recsFuture = _fetchCollectionParts(
        collectionId: collectionId,
        excludeId: tmdbId,
        language: language,
      );
    } else {
      recsFuture = _mapRecommendations(
        detail['recommendations'],
        isMovie: true,
        excludeId: tmdbId,
      );
    }

    final results = await Future.wait([logoFuture, recsFuture]);
    final logo = results[0] as String?;
    var recomendaciones = results[1] as List<Map<String, dynamic>>;

    // Completar con populares estrenados si hay pocos
    if (recomendaciones.length < 8) {
      final populares = await _fetchPopular(
        isMovie: true,
        language: language,
        excludeId: tmdbId,
        excludeIds: recomendaciones
            .map((e) => e['idcontenido'] as int? ?? 0)
            .where((id) => id > 0)
            .toSet(),
        limit: 12 - recomendaciones.length,
      );
      recomendaciones = [...recomendaciones, ...populares];
    }

    final titulo = detail['title']?.toString() ??
        detail['original_title']?.toString() ??
        'Sin título';

    return {
      'idcontenido': tmdbId,
      'tmdb_id': tmdbId,
      'tipo': 'movie',
      'imdb_id': imdbId.isEmpty ? null : imdbId,
      'titulo_contenido': titulo,
      'titulo_capitulo': null,
      'capitulo': null,
      'temporada': null,
      'numero_capitulo': null,
      'backdrop': _tmdbUrl(detail['backdrop_path']?.toString()),
      'poster': _tmdbUrl(detail['poster_path']?.toString(), size: 'w500'),
      'logo': logo,
      'overview': detail['overview']?.toString(),
      'fecha_salida': detail['release_date']?.toString(),
      'calificacion': _toDouble(detail['vote_average']),
      'subtitulo':
          'https://modlyo.com/subtitulo/contenido/$tmdbId/es_MX.vtt',
      'siguiente': null,
      'recomendaciones': recomendaciones,
      'temporadas': <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _fetchTvPlayer({
    required int tmdbId,
    required String language,
    required int temporada,
    required int capitulo,
  }) async {
    final prefs = await _episodePrefs();
    final now = DateTime.now();

    final detail = await _get(
      '/tv/$tmdbId',
      query: {
        'append_to_response': 'external_ids,recommendations',
      },
      language: language,
    );

    if (detail == null) {
      return {
        'error': true,
        'mensaje': 'Contenido no encontrado',
      };
    }

    final external = detail['external_ids'] is Map
        ? Map<String, dynamic>.from(detail['external_ids'] as Map)
        : <String, dynamic>{};
    final imdbId =
        (external['imdb_id'] ?? detail['imdb_id'] ?? '').toString();

    final tituloContenido = detail['name']?.toString() ??
        detail['original_name']?.toString() ??
        'Sin título';
    final overviewSerie = detail['overview']?.toString();
    final calificacionSerie = _toDouble(detail['vote_average']);
    var poster = _tmdbUrl(detail['poster_path']?.toString(), size: 'w500');
    var backdrop = _tmdbUrl(detail['backdrop_path']?.toString());

    final seasonsMeta = (detail['seasons'] is List)
        ? List<Map<String, dynamic>>.from(
            (detail['seasons'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    var temp = temporada;
    var cap = capitulo;
    if (temp <= 0 || cap <= 0) {
      final first = await _findFirstEpisode(
        tmdbId: tmdbId,
        language: language,
        seasonsMeta: seasonsMeta,
        prefs: prefs,
        now: now,
      );
      if (first != null) {
        temp = first.$1;
        cap = first.$2;
      } else {
        temp = 0;
        cap = 0;
      }
    }

    String? tituloCapitulo;
    String? overview = overviewSerie;
    String? fechaSalida = detail['first_air_date']?.toString();
    double? calificacion = calificacionSerie;
    String? capituloFmt;
    Map<String, int>? siguiente;
    var esEpisodio = false;

    Map<String, dynamic>? seasonData;
    if (temp > 0 || (temp == 0 && prefs.showSpecials)) {
      seasonData = await _get(
        '/tv/$tmdbId/season/$temp',
        language: language,
      );
    }

    List<Map<String, dynamic>> episodesActual = [];
    if (seasonData != null && seasonData['episodes'] is List) {
      for (final e in (seasonData['episodes'] as List).whereType<Map>()) {
        final ep = Map<String, dynamic>.from(e);
        if (!prefs.showUnreleasedEps &&
            _isUnreleased(ep['air_date']?.toString(), now)) {
          continue;
        }
        episodesActual.add(ep);
      }
    }

    Map<String, dynamic>? capActual;
    if (cap > 0 && episodesActual.isNotEmpty) {
      for (final ep in episodesActual) {
        if ((ep['episode_number'] as int? ?? 0) == cap) {
          capActual = ep;
          break;
        }
      }
    }

    if (capActual != null) {
      esEpisodio = true;
      tituloCapitulo = capActual['name']?.toString() ?? 'Episodio $cap';
      final ov = capActual['overview']?.toString() ?? '';
      overview = ov.isNotEmpty ? ov : overviewSerie;
      fechaSalida = capActual['air_date']?.toString() ?? fechaSalida;
      calificacion =
          _toDouble(capActual['vote_average']) ?? calificacionSerie;
      final still = _tmdbUrl(capActual['still_path']?.toString());
      if (still != null) backdrop = still;
      capituloFmt = _formatoS00E00(temp, cap);

      siguiente = _resolveNextEpisode(
        currentSeason: temp,
        currentEpisode: cap,
        episodesInSeason: episodesActual,
      );
      if (siguiente == null) {
        siguiente = await _resolveNextSeasonFirst(
          tmdbId: tmdbId,
          language: language,
          afterSeason: temp,
          seasonsMeta: seasonsMeta,
          prefs: prefs,
          now: now,
        );
      }
    }

    final logoFuture = _fetchLogo(
      tmdbId: tmdbId,
      isMovie: false,
      language: language,
    );
    final temporadasFuture = _buildAllSeasons(
      tmdbId: tmdbId,
      language: language,
      seasonsMeta: seasonsMeta,
      currentSeason: temp,
      currentEpisode: cap,
      esEpisodio: esEpisodio,
      prefs: prefs,
      now: now,
    );
    final recsFuture = _mapRecommendations(
      detail['recommendations'],
      isMovie: false,
      excludeId: tmdbId,
    );

    final parallel = await Future.wait([
      logoFuture,
      temporadasFuture,
      recsFuture,
    ]);
    final logo = parallel[0] as String?;
    final temporadas = parallel[1] as List<Map<String, dynamic>>;
    var recomendaciones = parallel[2] as List<Map<String, dynamic>>;

    // Completar con series populares ya estrenadas
    if (recomendaciones.length < 8) {
      final populares = await _fetchPopular(
        isMovie: false,
        language: language,
        excludeId: tmdbId,
        excludeIds: recomendaciones
            .map((e) => e['idcontenido'] as int? ?? 0)
            .where((id) => id > 0)
            .toSet(),
        limit: 12 - recomendaciones.length,
      );
      recomendaciones = [...recomendaciones, ...populares];
    }

    return {
      'idcontenido': tmdbId,
      'tmdb_id': tmdbId,
      'tipo': 'tv',
      'imdb_id': imdbId.isEmpty ? null : imdbId,
      'titulo_contenido': tituloContenido,
      'titulo_capitulo': tituloCapitulo,
      'capitulo': capituloFmt,
      'temporada': temp > 0 || (temp == 0 && prefs.showSpecials) ? temp : null,
      'numero_capitulo': cap > 0 ? cap : null,
      'backdrop': backdrop,
      'poster': poster,
      'logo': logo,
      'overview': overview,
      'fecha_salida': fechaSalida,
      'calificacion': calificacion,
      'subtitulo':
          'https://modlyo.com/subtitulo/contenido/$tmdbId/es_MX.vtt',
      'siguiente': siguiente,
      'recomendaciones': recomendaciones,
      'temporadas': temporadas,
    };
  }

  Future<(int, int)?> _findFirstEpisode({
    required int tmdbId,
    required String language,
    required List<Map<String, dynamic>> seasonsMeta,
    required ({bool showSpecials, bool showUnreleasedEps}) prefs,
    required DateTime now,
  }) async {
    final numbers = seasonsMeta
        .map((s) => s['season_number'] as int? ?? -1)
        .where((n) {
          if (n < 0) return false;
          if (n == 0 && !prefs.showSpecials) return false;
          return true;
        })
        .toList()
      ..sort();

    for (final n in numbers) {
      final data = await _get('/tv/$tmdbId/season/$n', language: language);
      if (data == null) continue;
      final eps = data['episodes'];
      if (eps is! List || eps.isEmpty) continue;
      for (final raw in eps) {
        if (raw is! Map) continue;
        final ep = Map<String, dynamic>.from(raw);
        if (!prefs.showUnreleasedEps &&
            _isUnreleased(ep['air_date']?.toString(), now)) {
          continue;
        }
        final epNum = ep['episode_number'] as int? ?? 1;
        return (n, epNum);
      }
    }
    return null;
  }

  Map<String, int>? _resolveNextEpisode({
    required int currentSeason,
    required int currentEpisode,
    required List<Map<String, dynamic>> episodesInSeason,
  }) {
    final sorted = List<Map<String, dynamic>>.from(episodesInSeason)
      ..sort((a, b) => (a['episode_number'] as int? ?? 0)
          .compareTo(b['episode_number'] as int? ?? 0));

    for (final ep in sorted) {
      final num = ep['episode_number'] as int? ?? 0;
      if (num > currentEpisode) {
        return {
          'temporada': currentSeason,
          'capitulo': num,
        };
      }
    }
    return null;
  }

  Future<Map<String, int>?> _resolveNextSeasonFirst({
    required int tmdbId,
    required String language,
    required int afterSeason,
    required List<Map<String, dynamic>> seasonsMeta,
    required ({bool showSpecials, bool showUnreleasedEps}) prefs,
    required DateTime now,
  }) async {
    final numbers = seasonsMeta
        .map((s) => s['season_number'] as int? ?? -1)
        .where((n) {
          if (n <= afterSeason) return false;
          if (n == 0 && !prefs.showSpecials) return false;
          return true;
        })
        .toList()
      ..sort();

    for (final n in numbers) {
      final data = await _get('/tv/$tmdbId/season/$n', language: language);
      if (data == null) continue;
      final eps = data['episodes'];
      if (eps is! List || eps.isEmpty) continue;
      for (final raw in eps) {
        if (raw is! Map) continue;
        final ep = Map<String, dynamic>.from(raw);
        if (!prefs.showUnreleasedEps &&
            _isUnreleased(ep['air_date']?.toString(), now)) {
          continue;
        }
        final epNum = ep['episode_number'] as int? ?? 1;
        return {
          'temporada': n,
          'capitulo': epNum,
        };
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _buildAllSeasons({
    required int tmdbId,
    required String language,
    required List<Map<String, dynamic>> seasonsMeta,
    required int currentSeason,
    required int currentEpisode,
    required bool esEpisodio,
    required ({bool showSpecials, bool showUnreleasedEps}) prefs,
    required DateTime now,
  }) async {
    final numbers = seasonsMeta
        .map((s) => s['season_number'] as int? ?? -1)
        .where((n) {
          if (n < 0) return false;
          if (n == 0 && !prefs.showSpecials) return false;
          return true;
        })
        .toList()
      ..sort();

    if (numbers.isEmpty) return [];

    final futures = numbers.map((n) async {
      final data = await _get('/tv/$tmdbId/season/$n', language: language);
      if (data == null) return null;

      final epsRaw = data['episodes'] is List
          ? List<Map<String, dynamic>>.from(
              (data['episodes'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e)),
            )
          : <Map<String, dynamic>>[];

      final listaCaps = <Map<String, dynamic>>[];
      for (final c in epsRaw) {
        if (!prefs.showUnreleasedEps &&
            _isUnreleased(c['air_date']?.toString(), now)) {
          continue;
        }
        final numCap = c['episode_number'] as int? ?? 0;
        final esActual =
            esEpisodio && n == currentSeason && numCap == currentEpisode;
        listaCaps.add({
          'numero': numCap,
          'titulo': c['name']?.toString() ?? 'Episodio $numCap',
          'calificacion': _toDouble(c['vote_average']),
          'duracion': c['runtime'],
          'backdrop': _tmdbUrl(c['still_path']?.toString()),
          'overview': c['overview']?.toString(),
          'air_date': c['air_date']?.toString(),
          'actual': esActual,
        });
      }

      if (listaCaps.isEmpty && n == 0) return null;

      return {
        'numero': data['season_number'] ?? n,
        'nombre': data['name']?.toString() ?? 'Temporada $n',
        'poster': _tmdbUrl(data['poster_path']?.toString(), size: 'w342'),
        'overview': data['overview']?.toString(),
        'cantidad_episodios': listaCaps.length,
        'capitulos': listaCaps,
      };
    });

    final results = await Future.wait(futures);
    return results.whereType<Map<String, dynamic>>().toList()
      ..sort((a, b) => (a['numero'] as int).compareTo(b['numero'] as int));
  }

  Future<List<Map<String, dynamic>>> _mapRecommendations(
    dynamic raw, {
    required bool isMovie,
    required int excludeId,
  }) async {
    final now = DateTime.now();
    final results = (raw is Map && raw['results'] is List)
        ? List<Map<String, dynamic>>.from(
            (raw['results'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final r in results) {
      final id = r['id'] as int? ?? 0;
      if (id <= 0 || id == excludeId) continue;

      // Solo contenido ya estrenado
      final dateStr = isMovie
          ? r['release_date']?.toString()
          : r['first_air_date']?.toString();
      if (!_isReleased(dateStr, now)) continue;

      final titulo = isMovie
          ? (r['title']?.toString() ?? 'Sin título')
          : (r['name']?.toString() ?? 'Sin título');
      out.add({
        'idcontenido': id,
        'idtmdb': id,
        'tmdb_id': id,
        'imdb': null,
        'tipo': isMovie ? 'movie' : 'tv',
        'titulo': titulo,
        'backdrop': _tmdbUrl(r['backdrop_path']?.toString()),
        'logo': null,
        'poster': _tmdbUrl(r['poster_path']?.toString(), size: 'w342'),
        'calificacion': _toDouble(r['vote_average']),
        'fecha_salida': dateStr,
      });
      if (out.length >= 12) break;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _fetchCollectionParts({
    required int collectionId,
    required int excludeId,
    required String language,
  }) async {
    final now = DateTime.now();
    final data = await _get(
      '/collection/$collectionId',
      language: language,
    );
    if (data == null) return [];

    final parts = (data['parts'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['parts'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    parts.sort((a, b) {
      final da = a['release_date']?.toString() ?? '';
      final db = b['release_date']?.toString() ?? '';
      return da.compareTo(db);
    });

    final out = <Map<String, dynamic>>[];
    for (final r in parts) {
      final id = r['id'] as int? ?? 0;
      if (id <= 0 || id == excludeId) continue;

      // Solo partes de la colección ya estrenadas
      final dateStr = r['release_date']?.toString();
      if (!_isReleased(dateStr, now)) continue;

      out.add({
        'idcontenido': id,
        'idtmdb': id,
        'tmdb_id': id,
        'imdb': null,
        'tipo': 'movie',
        'titulo': r['title']?.toString() ?? 'Sin título',
        'backdrop': _tmdbUrl(r['backdrop_path']?.toString()),
        'logo': null,
        'poster': _tmdbUrl(r['poster_path']?.toString(), size: 'w342'),
        'calificacion': _toDouble(r['vote_average']),
        'fecha_salida': dateStr,
      });
    }
    return out;
  }

  /// Contenido popular ya estrenado (películas o series).
  Future<List<Map<String, dynamic>>> _fetchPopular({
    required bool isMovie,
    required String language,
    required int excludeId,
    Set<int> excludeIds = const {},
    int limit = 8,
  }) async {
    final now = DateTime.now();
    final path = isMovie ? '/movie/popular' : '/tv/popular';
    final data = await _get(
      path,
      query: {'page': '1'},
      language: language,
    );
    if (data == null) return [];

    final results = (data['results'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['results'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final r in results) {
      final id = r['id'] as int? ?? 0;
      if (id <= 0 || id == excludeId || excludeIds.contains(id)) continue;

      final dateStr = isMovie
          ? r['release_date']?.toString()
          : r['first_air_date']?.toString();
      if (!_isReleased(dateStr, now)) continue;

      final titulo = isMovie
          ? (r['title']?.toString() ?? 'Sin título')
          : (r['name']?.toString() ?? 'Sin título');

      out.add({
        'idcontenido': id,
        'idtmdb': id,
        'tmdb_id': id,
        'imdb': null,
        'tipo': isMovie ? 'movie' : 'tv',
        'titulo': titulo,
        'backdrop': _tmdbUrl(r['backdrop_path']?.toString()),
        'logo': null,
        'poster': _tmdbUrl(r['poster_path']?.toString(), size: 'w342'),
        'calificacion': _toDouble(r['vote_average']),
        'fecha_salida': dateStr,
      });
      if (out.length >= limit) break;
    }
    return out;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}