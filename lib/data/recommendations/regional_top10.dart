import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../ai/ai_client.dart';
import '../ai/daily_ai_gate.dart';

/// Ítem del Top 10 del día.
class Top10Item {
  final int tmdbId;
  final String tipo; // movie | tv
  final String titulo;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final String? logoUrl;
  final double? rating;
  final int orden;

  const Top10Item({
    required this.tmdbId,
    required this.tipo,
    required this.titulo,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.logoUrl,
    this.rating,
    required this.orden,
  });

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'tipo': tipo,
        'titulo': titulo,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'overview': overview,
        'logoUrl': logoUrl,
        'rating': rating,
        'orden': orden,
      };

  factory Top10Item.fromJson(Map<String, dynamic> j) => Top10Item(
        tmdbId: (j['tmdbId'] as num).toInt(),
        tipo: j['tipo']?.toString() ?? 'movie',
        titulo: j['titulo']?.toString() ?? '',
        posterUrl: j['posterUrl']?.toString(),
        backdropUrl: j['backdropUrl']?.toString(),
        overview: j['overview']?.toString(),
        logoUrl: j['logoUrl']?.toString(),
        rating: (j['rating'] as num?)?.toDouble(),
        orden: (j['orden'] as num?)?.toInt() ?? 0,
      );

  Top10Item copyWith({int? orden}) => Top10Item(
        tmdbId: tmdbId,
        tipo: tipo,
        titulo: titulo,
        posterUrl: posterUrl,
        backdropUrl: backdropUrl,
        overview: overview,
        logoUrl: logoUrl,
        rating: rating,
        orden: orden ?? this.orden,
      );
}

/// Top 10 películas + Top 10 series del día.
///
/// Con IA (máx 1 vez/día): títulos MUY conocidos / taquilleros en LatAm.
/// Fallback TMDB popular + now_playing filtrado por votos (sin rarezas).
class RegionalTop10Service {
  static const _cacheKey = 'regional_top10_ai_v2';
  static const _dayKey = 'regional_top10_day_v2'; // legado
  static const _tsKey = 'regional_top10_ts_v2'; // ms de última generación
  static const _ttlMs = 24 * 60 * 60 * 1000; // 24 horas
  static const tmdbKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const minVotesMovie = 500;
  static const minVotesTv = 200;
  static const minPopularity = 40.0;

  final AiClient? ai;
  final String? apiKey;
  final String language;

  RegionalTop10Service({
    this.ai,
    this.apiKey,
    this.language = 'es-MX',
  });

  Future<(List<Top10Item> movies, List<Top10Item> series)> load({
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final raw = prefs.getString(_cacheKey);
      final ts = prefs.getInt(_tsKey) ?? 0;
      final ageOk = ts > 0 &&
          (DateTime.now().millisecondsSinceEpoch - ts) < _ttlMs;
      if (ageOk && raw != null) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final movies = (map['movies'] as List)
              .map((e) =>
                  Top10Item.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          final series = (map['series'] as List)
              .map((e) =>
                  Top10Item.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          if (movies.isNotEmpty || series.isNotEmpty) return (movies, series);
        } catch (_) {}
      }
    }

    final canAi = force || await DailyAiGate.canGenerateToday();
    List<Top10Item> movies = [];
    List<Top10Item> series = [];

    if (canAi && ai != null) {
      final curated = await _generateWithAi();
      movies = curated.$1;
      series = curated.$2;
      if (movies.isNotEmpty || series.isNotEmpty) {
        await DailyAiGate.markGeneratedToday();
      }
    }

    if (movies.length < 10) {
      final fb = await _fetchPopularFiltered('movie');
      final seen = movies.map((e) => e.tmdbId).toSet();
      for (final x in fb) {
        if (seen.contains(x.tmdbId)) continue;
        movies.add(x.copyWith(orden: movies.length));
        if (movies.length >= 10) break;
      }
    }
    if (series.length < 10) {
      final fb = await _fetchPopularFiltered('tv');
      final seen = series.map((e) => e.tmdbId).toSet();
      for (final x in fb) {
        if (seen.contains(x.tmdbId)) continue;
        series.add(x.copyWith(orden: series.length));
        if (series.length >= 10) break;
      }
    }

    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'movies': movies.map((e) => e.toJson()).toList(),
        'series': series.map((e) => e.toJson()).toList(),
      }),
    );
    final now = DateTime.now();
    await prefs.setInt(_tsKey, now.millisecondsSinceEpoch);
    // legado
    final dayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await prefs.setString(_dayKey, dayKey);
    return (movies, series);
  }

  Future<(List<Top10Item>, List<Top10Item>)> _generateWithAi() async {
    final client = ai!;
    final year = DateTime.now().year;
    final prompt = '''
Eres un editor de un ranking de streaming para Latinoamérica (México, Colombia, Argentina, España).
Arma el TOP 10 de PELÍCULAS y el TOP 10 de SERIES del día: títulos MUY conocidos,
taquilleros o de los que todo el mundo habla ahora. Nada de cine de autor oscuro,
cortos, documentales raros ni series desconocidas.
Prioriza: estrenos recientes populares, hits en Netflix/Prime/Disney, clásicos
que siempre se ven, y lo que está de moda en $year.
Responde SOLO un JSON sin texto alrededor:
{
  "movies": [{"titulo":"...","anio":"2024"}, ...],
  "series": [{"titulo":"...","anio":"2023"}, ...]
}
Exactamente 10 películas y 10 series. Títulos en el nombre más conocido en español o original famoso.
''';

    final resp = await client.complete(prompt, usageKind: 'foryou');
    if (resp is! AiText) return (<Top10Item>[], <Top10Item>[]);

    try {
      var t = resp.text.trim();
      final start = t.indexOf('{');
      final end = t.lastIndexOf('}');
      if (start < 0 || end <= start) return (<Top10Item>[], <Top10Item>[]);
      final map = jsonDecode(t.substring(start, end + 1)) as Map;
      final movies = await _verifyList(map['movies'] as List? ?? [], 'movie');
      final series = await _verifyList(map['series'] as List? ?? [], 'tv');
      return (movies, series);
    } catch (_) {
      return (<Top10Item>[], <Top10Item>[]);
    }
  }

  Future<List<Top10Item>> _verifyList(List raw, String media) async {
    final titles = <String>[];
    for (final o in raw) {
      if (o is! Map) continue;
      final titulo = (o['titulo'] ?? o['title'] ?? '').toString().trim();
      if (titulo.isEmpty) continue;
      titles.add(titulo);
      if (titles.length >= 14) break;
    }
    final hits = <Map<String, dynamic>?>[];
    for (var i = 0; i < titles.length; i += 5) {
      final end = i + 5 > titles.length ? titles.length : i + 5;
      final chunk = titles.sublist(i, end);
      final part = await Future.wait(chunk.map((t) => _tmdbSearch(media, t)));
      hits.addAll(part);
    }
    final out = <Top10Item>[];
    final seen = <int>{};
    final minVotes = media == 'tv' ? minVotesTv : minVotesMovie;
    for (var i = 0; i < titles.length && out.length < 10; i++) {
      final hit = i < hits.length ? hits[i] : null;
      if (hit == null) continue;
      final id = (hit['id'] as num?)?.toInt();
      if (id == null || seen.contains(id)) continue;
      final votes = (hit['vote_count'] as num?)?.toInt() ?? 0;
      final pop = (hit['popularity'] as num?)?.toDouble() ?? 0;
      if (votes < minVotes && pop < minPopularity) continue;
      seen.add(id);
      final poster = hit['poster_path']?.toString();
      final titulo = titles[i];
      final bd = hit['backdrop_path']?.toString();
      out.add(Top10Item(
        tmdbId: id,
        tipo: media == 'tv' ? 'tv' : 'movie',
        titulo: (hit['title'] ?? hit['name'] ?? titulo).toString(),
        posterUrl: (poster != null && poster.isNotEmpty)
            ? 'https://image.tmdb.org/t/p/w342$poster'
            : null,
        backdropUrl: (bd != null && bd.isNotEmpty)
            ? 'https://image.tmdb.org/t/p/w780$bd'
            : null,
        overview: hit['overview']?.toString(),
        rating: (hit['vote_average'] as num?)?.toDouble(),
        orden: out.length,
      ));
    }
    return out;
  }

  Future<List<Top10Item>> _fetchPopularFiltered(String media) async {
    final key = apiKey ?? tmdbKeyFallback;
    final endpoints = media == 'tv'
        ? [
            'https://api.themoviedb.org/3/tv/popular?api_key=$key&language=$language&page=1',
            'https://api.themoviedb.org/3/tv/on_the_air?api_key=$key&language=$language&page=1',
          ]
        : [
            'https://api.themoviedb.org/3/movie/popular?api_key=$key&language=$language&page=1',
            'https://api.themoviedb.org/3/movie/now_playing?api_key=$key&language=$language&page=1',
          ];

    final minVotes = media == 'tv' ? minVotesTv : minVotesMovie;
    final byId = <int, Top10Item>{};

    for (final url in endpoints) {
      try {
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map;
        for (final r in (data['results'] as List? ?? [])) {
          if (r is! Map) continue;
          final id = (r['id'] as num?)?.toInt();
          if (id == null || byId.containsKey(id)) continue;
          final votes = (r['vote_count'] as num?)?.toInt() ?? 0;
          final pop = (r['popularity'] as num?)?.toDouble() ?? 0;
          if (votes < minVotes && pop < minPopularity) continue;
          final title = (r['title'] ?? r['name'] ?? '').toString();
          if (title.isEmpty) continue;
          final poster = r['poster_path']?.toString();
          final bd = r['backdrop_path']?.toString();
          byId[id] = Top10Item(
            tmdbId: id,
            tipo: media == 'tv' ? 'tv' : 'movie',
            titulo: title,
            posterUrl: (poster != null && poster.isNotEmpty)
                ? 'https://image.tmdb.org/t/p/w342$poster'
                : null,
            backdropUrl: (bd != null && bd.isNotEmpty)
                ? 'https://image.tmdb.org/t/p/w780$bd'
                : null,
            overview: r['overview']?.toString(),
            rating: (r['vote_average'] as num?)?.toDouble(),
            orden: byId.length,
          );
        }
      } catch (_) {}
    }

    final list = byId.values.toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    return [
      for (var i = 0; i < list.length && i < 10; i++)
        list[i].copyWith(orden: i),
    ];
  }

  Future<Map<String, dynamic>?> _tmdbSearch(String media, String title) async {
    final key = apiKey ?? tmdbKeyFallback;
    final uri = Uri.parse(
      'https://api.themoviedb.org/3/search/$media'
      '?api_key=$key&language=$language&query=${Uri.encodeQueryComponent(title)}&page=1',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map;
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;
      Map<String, dynamic>? best;
      var bestVotes = -1;
      for (final r in results.take(3)) {
        if (r is! Map) continue;
        final v = (r['vote_count'] as num?)?.toInt() ?? 0;
        if (v > bestVotes) {
          bestVotes = v;
          best = Map<String, dynamic>.from(r);
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }
}
