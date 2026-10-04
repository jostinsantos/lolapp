import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../ai/ai_client.dart';
import 'history_signals.dart';
import 'user_taste_profile.dart';

/// Candidato crudo del modelo.
class ForYouCandidate {
  final String titulo;
  final String anio;
  final String tipo; // movie | tv
  final String porque;

  const ForYouCandidate({
    required this.titulo,
    required this.anio,
    required this.tipo,
    required this.porque,
  });
}

/// Recomendación verificada y lista para mostrar.
class ForYouItem {
  final int tmdbId;
  final String tipo;
  final String titulo;
  final String? posterUrl;
  final String porque;
  final int orden;
  final int generadoAt;

  const ForYouItem({
    required this.tmdbId,
    required this.tipo,
    required this.titulo,
    this.posterUrl,
    required this.porque,
    required this.orden,
    required this.generadoAt,
  });

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'tipo': tipo,
        'titulo': titulo,
        'posterUrl': posterUrl,
        'porque': porque,
        'orden': orden,
        'generadoAt': generadoAt,
      };

  factory ForYouItem.fromJson(Map<String, dynamic> j) => ForYouItem(
        tmdbId: (j['tmdbId'] as num).toInt(),
        tipo: j['tipo']?.toString() ?? 'movie',
        titulo: j['titulo']?.toString() ?? '',
        posterUrl: j['posterUrl']?.toString(),
        porque: j['porque']?.toString() ?? '',
        orden: (j['orden'] as num?)?.toInt() ?? 0,
        generadoAt: (j['generadoAt'] as num?)?.toInt() ?? 0,
      );
}

/// Ventana de 20 horas como pediste (Kino usa 24h; aquí 20h para ahorrar IA).
class ForYouGate {
  static const windowMs = 20 * 60 * 60 * 1000; // 20 horas
  static const windowAfterFailureMs = 15 * 60 * 1000; // 15 min

  static bool isDue(int lastAttemptMs, bool lastWasModelFailure, int nowMs) {
    if (lastAttemptMs <= 0) return true;
    final window = lastWasModelFailure ? windowAfterFailureMs : windowMs;
    return nowMs - lastAttemptMs >= window;
  }
}

/// Generador "Para ti" copiado de la lógica de Kino (ForYouGenerator + prompt + verificación TMDB).
class ForYouGenerator {
  static const _cacheKey = 'for_you_recs_v1';
  static const _marksKey = 'for_you_marks_v1';
  static const howMany = 20;
  static const tmdbApiKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5';

  final AiClient ai;
  final String? tmdbApiKey;
  bool _inProgress = false;

  ForYouGenerator({required this.ai, this.tmdbApiKey});

  Future<(int lastAttempt, bool wasFailure)> _readMarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_marksKey);
    if (raw == null) return (0, false);
    try {
      final m = jsonDecode(raw) as Map;
      return (
        (m['t'] as num?)?.toInt() ?? 0,
        m['f'] == true,
      );
    } catch (_) {
      return (0, false);
    }
  }

  Future<void> _writeMarks(int now, bool wasFailure) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _marksKey,
      jsonEncode({'t': now, 'f': wasFailure}),
    );
  }

  Future<List<ForYouItem>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ForYouItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<ForYouItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  String _prompt(String lines, String tasteSnippet) {
    final extra = tasteSnippet.isEmpty ? '' : '\n\nPerfil del usuario:\n$tasteSnippet';
    return 'Eres un recomendador de películas y series para una persona de Colombia. '
        "Te doy lo que vio: 'terminado' le gustó, 'abandonado' lo dejó (NO propongas nada "
        "parecido), 'repetido' le gustó mucho. Propón $howMany títulos que NO estén en la "
        'lista. Responde SOLO un arreglo JSON, sin texto alrededor, con objetos '
        '{"titulo","anio","tipo","porque"}. "tipo" es "movie" o "tv". '
        '"porque" es UNA frase corta en español de Colombia, sin voseo, que explique la '
        'relación con lo que vio. Nada de contenido para adultos.'
        '$extra'
        '\n\n$lines';
  }

  List<ForYouCandidate>? _parseCandidates(String text) {
    try {
      // Buscar el array JSON en el texto
      var t = text.trim();
      final start = t.indexOf('[');
      final end = t.lastIndexOf(']');
      if (start < 0 || end <= start) return null;
      t = t.substring(start, end + 1);
      final arr = jsonDecode(t) as List;
      final out = <ForYouCandidate>[];
      for (final o in arr) {
        if (o is! Map) continue;
        final titulo = (o['titulo'] ?? '').toString().trim();
        if (titulo.isEmpty) continue;
        out.add(ForYouCandidate(
          titulo: titulo,
          anio: (o['anio'] ?? '').toString(),
          tipo: (o['tipo'] ?? 'movie').toString().toLowerCase().contains('tv')
              ? 'tv'
              : 'movie',
          porque: (o['porque'] ?? '').toString().trim(),
        ));
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// Busca en TMDB el primer resultado del título.
  Future<Map<String, dynamic>?> _tmdbSearch(String kind, String title) async {
    final key = tmdbApiKey ?? tmdbApiKeyFallback;
    final mt = kind == 'tv' ? 'tv' : 'movie';
    final uri = Uri.parse(
      'https://api.themoviedb.org/3/search/$mt'
      '?api_key=$key&language=es-MX&query=${Uri.encodeQueryComponent(title)}&page=1',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map;
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;
      return Map<String, dynamic>.from(results.first as Map);
    } catch (_) {
      return null;
    }
  }

  Future<List<ForYouItem>> _verify(
    List<ForYouCandidate> candidates,
    Set<String> alreadySeenTitles,
  ) async {
    final out = <ForYouItem>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    var orden = 0;
    for (final c in candidates) {
      if (out.length >= 12) break;
      final norm = _normalize(c.titulo);
      if (alreadySeenTitles.contains(norm)) continue;
      final hit = await _tmdbSearch(c.tipo, c.titulo);
      if (hit == null) continue;
      final id = (hit['id'] as num?)?.toInt();
      if (id == null) continue;
      final title = (hit['title'] ?? hit['name'] ?? c.titulo).toString();
      final poster = hit['poster_path']?.toString();
      final posterUrl = (poster != null && poster.isNotEmpty)
          ? 'https://image.tmdb.org/t/p/w342$poster'
          : null;
      out.add(ForYouItem(
        tmdbId: id,
        tipo: c.tipo,
        titulo: title,
        posterUrl: posterUrl,
        porque: c.porque.isEmpty ? 'Porque encaja con lo que te gusta' : c.porque,
        orden: orden++,
        generadoAt: now,
      ));
      alreadySeenTitles.add(_normalize(title));
    }
    return out;
  }

  String _normalize(String text) {
    var t = text.toLowerCase().trim();
    const accents = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
    };
    accents.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return t.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
  }

  /// Genera si toca (ventana 20h). Devuelve la lista cacheada o la nueva.
  Future<List<ForYouItem>> generateIfDue({bool force = false}) async {
    if (_inProgress) return loadCached();
    _inProgress = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final (last, wasFailure) = await _readMarks();
      if (!force && !ForYouGate.isDue(last, wasFailure, now)) {
        return loadCached();
      }

      final raw = await HistorySignals.loadRawHistory();
      final watched = HistorySignals.of(raw);
      if (watched.isEmpty && !force) {
        return loadCached();
      }

      await _writeMarks(now, false);

      final profile = await UserTasteProfile.load();
      // Enriquecer perfil con lo visto
      for (final w in watched) {
        if (w.status == 'terminado' && w.genres.isNotEmpty) {
          profile.recordWatch(genres: w.genres, weight: 1.5);
        }
      }
      await profile.save();

      final lines = watched.isEmpty
          ? '- (sin historial aún)'
          : HistorySignals.lines(watched);
      final prompt = _prompt(lines, profile.toPromptSnippet());

      final resp = await ai.complete(prompt, usageKind: 'foryou');
      if (resp is! AiText) {
        await _writeMarks(now, true);
        return loadCached();
      }

      final candidates = _parseCandidates(resp.text);
      if (candidates == null || candidates.isEmpty) {
        await _writeMarks(now, true);
        return loadCached();
      }

      final seen = watched.map((w) => _normalize(w.title)).toSet();
      // también excluir likes
      for (final like in profile.likes.values) {
        final t = like['title']?.toString();
        if (t != null) seen.add(_normalize(t));
      }

      final verified = await _verify(candidates, seen);
      if (verified.isEmpty) {
        final prev = await loadCached();
        if (prev.isEmpty) await _writeMarks(now, true);
        return prev;
      }

      await _save(verified);
      return verified;
    } catch (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeMarks(now, true);
      return loadCached();
    } finally {
      _inProgress = false;
    }
  }
}
