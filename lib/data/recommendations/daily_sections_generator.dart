import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../ai/ai_client.dart';
import '../ai/daily_ai_gate.dart';
import 'history_signals.dart';
import 'user_taste_profile.dart';

class HomeSectionItem {
  final int tmdbId;
  final String tipo;
  final String titulo;
  final String? posterUrl;
  final String? backdropUrl;
  final String? porque;

  const HomeSectionItem({
    required this.tmdbId,
    required this.tipo,
    required this.titulo,
    this.posterUrl,
    this.backdropUrl,
    this.porque,
  });

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'tipo': tipo,
        'titulo': titulo,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'porque': porque,
      };

  factory HomeSectionItem.fromJson(Map<String, dynamic> j) => HomeSectionItem(
        tmdbId: (j['tmdbId'] as num).toInt(),
        tipo: j['tipo']?.toString() ?? 'movie',
        titulo: j['titulo']?.toString() ?? '',
        posterUrl: j['posterUrl']?.toString(),
        backdropUrl: j['backdropUrl']?.toString(),
        porque: j['porque']?.toString(),
      );
}

class HomeSection {
  final String id;
  final String title; // "Porque te gusta Inception", "Un poco de ciencia ficción"...
  final List<HomeSectionItem> items;

  const HomeSection({
    required this.id,
    required this.title,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory HomeSection.fromJson(Map<String, dynamic> j) => HomeSection(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        items: ((j['items'] as List?) ?? [])
            .map((e) =>
                HomeSectionItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Genera secciones personalizadas del home **como máximo 1 vez al día**.
/// Si ya se generó hoy → solo lee cache. No regenera.
class DailySectionsGenerator {
  static const _cacheKey = 'daily_home_sections_v1';
  static const tmdbKeyFallback = 'a2d9bbed370d9f678e34006f8750a5a5';

  final AiClient ai;
  final String? tmdbApiKey;

  DailySectionsGenerator({required this.ai, this.tmdbApiKey});

  Future<List<HomeSection>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => HomeSection.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<HomeSection> sections) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode(sections.map((e) => e.toJson()).toList()),
    );
  }

  /// Devuelve secciones. Solo llama a Kilo si [DailyAiGate.canGenerateToday].
  Future<List<HomeSection>> getSections({bool force = false}) async {
    final cached = await loadCached();
    if (!force && !await DailyAiGate.canGenerateToday()) {
      return cached;
    }

    final profile = await UserTasteProfile.load();
    final rawHist = await HistorySignals.loadRawHistory();
    final watched = HistorySignals.of(rawHist);

    // Si no hay gustos ni historial, no gastar IA
    if (profile.likes.isEmpty &&
        profile.genreWeights.isEmpty &&
        watched.isEmpty) {
      return cached;
    }

    final prompt = _buildPrompt(profile, watched);
    final resp = await ai.complete(prompt, usageKind: 'foryou');
    if (resp is! AiText) return cached;

    final parsed = _parseSections(resp.text);
    if (parsed.isEmpty) return cached;

    final verified = <HomeSection>[];
    for (final s in parsed.take(6)) {
      final candidates = s.items.take(12).toList();
      final hits = <Map<String, dynamic>?>[];
      for (var i = 0; i < candidates.length; i += 5) {
        final end = i + 5 > candidates.length ? candidates.length : i + 5;
        final chunk = candidates.sublist(i, end);
        final part = await Future.wait(
          chunk.map((c) => _tmdbSearch(c.tipo, c.titulo)),
        );
        hits.addAll(part);
      }
      final items = <HomeSectionItem>[];
      final seen = <int>{};
      for (var i = 0; i < candidates.length && items.length < 10; i++) {
        final c = candidates[i];
        final hit = i < hits.length ? hits[i] : null;
        if (hit == null) continue;
        final id = (hit['id'] as num?)?.toInt();
        if (id == null || seen.contains(id)) continue;
        seen.add(id);
        final poster = hit['poster_path']?.toString();
        final bd = hit['backdrop_path']?.toString();
        items.add(HomeSectionItem(
          tmdbId: id,
          tipo: c.tipo,
          titulo: (hit['title'] ?? hit['name'] ?? c.titulo).toString(),
          posterUrl: (poster != null && poster.isNotEmpty)
              ? 'https://image.tmdb.org/t/p/w342$poster'
              : null,
          backdropUrl: (bd != null && bd.isNotEmpty)
              ? 'https://image.tmdb.org/t/p/w780$bd'
              : null,
          porque: c.porque,
        ));
      }
      if (items.isNotEmpty) {
        verified.add(HomeSection(id: s.id, title: s.title, items: items));
      }
    }

    if (verified.isEmpty) return cached;

    await _save(verified);
    await DailyAiGate.markGeneratedToday();
    return verified;
  }

  String _buildPrompt(UserTasteProfile profile, List<WatchedSignal> watched) {
    final taste = profile.toPromptSnippet();
    final hist = watched.isEmpty
        ? '(sin historial de reproducción aún)'
        : HistorySignals.lines(watched);
    final liked = profile.likes.values
        .take(20)
        .map((v) => '${v['title']} (${v['type']})')
        .join(', ');

    return '''
Eres el curador de una app de cine/series en español (Latinoamérica).
Con el perfil y el historial, inventa entre 4 y 6 secciones tipo Netflix/Spotify
para el home. Cada sección tiene un título atractivo y corto, por ejemplo:
- "Porque te gusta Inception"
- "Un poco de ciencia ficción"
- "Lo mejor de [actor]"
- "Series para maratón"
- "Terror que no falla"
Varían según gustos e historial. No repitas títulos entre secciones.
Responde SOLO un JSON array, sin texto alrededor:
[
  {
    "id": "slug_corto",
    "title": "Título de la sección",
    "items": [
      {"titulo": "Nombre exacto", "tipo": "movie|tv", "porque": "frase corta"}
    ]
  }
]
Máximo 8 items por sección. Nada de contenido adulto.
Me gusta del usuario: ${liked.isEmpty ? '(ninguno aún)' : liked}
$taste
Historial:
$hist
''';
  }

  List<HomeSection> _parseSections(String text) {
    try {
      var t = text.trim();
      final start = t.indexOf('[');
      final end = t.lastIndexOf(']');
      if (start < 0 || end <= start) return [];
      t = t.substring(start, end + 1);
      final arr = jsonDecode(t) as List;
      final out = <HomeSection>[];
      for (final o in arr) {
        if (o is! Map) continue;
        final title = (o['title'] ?? o['titulo'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final id = (o['id'] ?? title).toString();
        final items = <HomeSectionItem>[];
        for (final it in (o['items'] as List? ?? [])) {
          if (it is! Map) continue;
          final tit = (it['titulo'] ?? it['title'] ?? '').toString().trim();
          if (tit.isEmpty) continue;
          final tipo =
              (it['tipo'] ?? 'movie').toString().toLowerCase().contains('tv')
                  ? 'tv'
                  : 'movie';
          items.add(HomeSectionItem(
            tmdbId: 0,
            tipo: tipo,
            titulo: tit,
            porque: (it['porque'] ?? '').toString(),
          ));
        }
        if (items.isNotEmpty) {
          out.add(HomeSection(id: id, title: title, items: items));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> _tmdbSearch(String kind, String title) async {
    final key = tmdbApiKey ?? tmdbKeyFallback;
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
}
