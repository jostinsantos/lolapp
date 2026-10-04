import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Perfil ligero del usuario: géneros y palabras clave aprendidos de lo que ve
/// y de los "Me gusta". Se actualiza localmente; se usa para enriquecer el prompt
/// de recomendaciones y el contexto de Lolbot.
class UserTasteProfile {
  static const _prefsKey = 'user_taste_profile_v1';
  static const _likesKey = 'user_likes_v1';

  /// género → peso (más alto = más le gusta)
  final Map<String, double> genreWeights;
  /// keyword → peso
  final Map<String, double> keywordWeights;
  /// tmdbId → {title, type, genres, keywords, likedAt}
  final Map<String, Map<String, dynamic>> likes;

  UserTasteProfile({
    Map<String, double>? genreWeights,
    Map<String, double>? keywordWeights,
    Map<String, Map<String, dynamic>>? likes,
  })  : genreWeights = genreWeights ?? {},
        keywordWeights = keywordWeights ?? {},
        likes = likes ?? {};

  static Future<UserTasteProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_prefsKey);
      final likesRaw = prefs.getString(_likesKey);
      final genres = <String, double>{};
      final keywords = <String, double>{};
      final likes = <String, Map<String, dynamic>>{};
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        (map['genres'] as Map?)?.forEach((k, v) {
          genres[k.toString()] = (v as num).toDouble();
        });
        (map['keywords'] as Map?)?.forEach((k, v) {
          keywords[k.toString()] = (v as num).toDouble();
        });
      }
      if (likesRaw != null) {
        final map = jsonDecode(likesRaw) as Map<String, dynamic>;
        map.forEach((k, v) {
          if (v is Map) likes[k] = Map<String, dynamic>.from(v);
        });
      }
      return UserTasteProfile(
        genreWeights: genres,
        keywordWeights: keywords,
        likes: likes,
      );
    } catch (_) {
      return UserTasteProfile();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'genres': genreWeights,
        'keywords': keywordWeights,
      }),
    );
    await prefs.setString(_likesKey, jsonEncode(likes));
  }

  /// Registrar que el usuario vio contenido (géneros / keywords de TMDB).
  void recordWatch({
    required List<String> genres,
    List<String> keywords = const [],
    double weight = 1.0,
  }) {
    for (final g in genres) {
      final key = g.trim().toLowerCase();
      if (key.isEmpty) continue;
      genreWeights[key] = (genreWeights[key] ?? 0) + weight;
    }
    for (final k in keywords) {
      final key = k.trim().toLowerCase();
      if (key.isEmpty) continue;
      keywordWeights[key] = (keywordWeights[key] ?? 0) + weight * 0.5;
    }
  }

  /// Botón "Me gusta este contenido".
  Future<void> likeContent({
    required int tmdbId,
    required String title,
    required String type, // movie | tv
    List<String> genres = const [],
    List<String> keywords = const [],
    bool persist = true,
  }) async {
    final id = tmdbId.toString();
    likes[id] = {
      'title': title,
      'type': type,
      'genres': genres,
      'keywords': keywords,
      'likedAt': DateTime.now().toIso8601String(),
    };
    // Refuerzo fuerte de gustos
    recordWatch(genres: genres, keywords: keywords, weight: 3.0);
    if (persist) await save();
  }

  Future<void> unlikeContent(int tmdbId) async {
    likes.remove(tmdbId.toString());
    await save();
  }

  bool isLiked(int tmdbId) => likes.containsKey(tmdbId.toString());

  /// Top géneros para el prompt.
  List<String> topGenres({int n = 8}) {
    final entries = genreWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).map((e) => e.key).toList();
  }

  List<String> topKeywords({int n = 10}) {
    final entries = keywordWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).map((e) => e.key).toList();
  }

  /// Texto para inyectar en el prompt de For You / Lolbot.
  String toPromptSnippet() {
    final g = topGenres();
    final k = topKeywords();
    final liked = likes.values.take(15).map((v) => v['title']).join(', ');
    final buf = StringBuffer();
    if (g.isNotEmpty) buf.writeln('Géneros que le gustan: ${g.join(', ')}.');
    if (k.isNotEmpty) buf.writeln('Temas/palabras clave: ${k.join(', ')}.');
    if (liked.isNotEmpty) buf.writeln('Le dio Me gusta a: $liked.');
    return buf.toString().trim();
  }
}
