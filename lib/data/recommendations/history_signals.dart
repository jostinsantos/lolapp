import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Señal de lo visto, igual que HistorySignals de Kino.
class WatchedSignal {
  final String title;
  final String kind; // movie | tv
  final String status; // terminado | abandonado
  final int? tmdbId;
  final List<String> genres;

  const WatchedSignal({
    required this.title,
    required this.kind,
    required this.status,
    this.tmdbId,
    this.genres = const [],
  });
}

/// Convierte el historial local (cachePlayer_*) en señales para el modelo.
class HistorySignals {
  static const abandonThreshold = 0.10;
  static const cap = 30;

  /// Carga el historial desde SharedPreferences (misma fuente que HomePage).
  static Future<List<Map<String, dynamic>>> loadRawHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys =
          prefs.getKeys().where((k) => k.startsWith('cachePlayer_')).toList();
      final result = <Map<String, dynamic>>[];
      for (final key in keys) {
        try {
          final raw = prefs.getString(key);
          if (raw == null) continue;
          final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          final segundo = data['segundo'] as int? ?? 0;
          if (segundo < 8) continue;
          result.add(data);
        } catch (_) {}
      }
      result.sort((a, b) {
        final ta = a['timestamp']?.toString() ?? '';
        final tb = b['timestamp']?.toString() ?? '';
        return tb.compareTo(ta);
      });
      return result;
    } catch (_) {
      return [];
    }
  }

  static List<WatchedSignal> of(List<Map<String, dynamic>> rows) {
    final decided = <String>{};
    final out = <WatchedSignal>[];
    for (final f in rows) {
      final itemId = (f['idcontenido'] ?? f['tmdb_id'] ?? f['id'] ?? '').toString();
      if (itemId.isEmpty || decided.contains(itemId)) continue;

      final segundo = (f['segundo'] as num?)?.toDouble() ?? 0;
      final duracion = (f['duracion'] as num?)?.toDouble() ?? 0;
      final watched = f['watched'] == true ||
          f['terminado'] == true ||
          (duracion > 0 && segundo / duracion >= 0.9);

      String? status;
      if (watched) {
        status = 'terminado';
      } else if (duracion > 0 && segundo / duracion < abandonThreshold) {
        status = 'abandonado';
      } else {
        continue; // a medias: no cuenta
      }

      decided.add(itemId);
      final title = (f['titulo'] ?? f['title'] ?? f['name'] ?? 'Sin título')
          .toString()
          .trim();
      final tipo = (f['media_type'] ?? f['type'] ?? f['tipo'] ?? 'movie')
          .toString()
          .toLowerCase();
      final kind = tipo.contains('tv') || tipo.contains('serie') ? 'tv' : 'movie';
      final tmdbId = (f['tmdb_id'] as num?)?.toInt() ??
          (f['idcontenido'] as num?)?.toInt();
      final genres = <String>[];
      if (f['genres'] is List) {
        for (final g in f['genres'] as List) {
          genres.add(g.toString());
        }
      } else if (f['genero'] != null) {
        genres.addAll(f['genero'].toString().split(',').map((s) => s.trim()));
      }

      out.add(WatchedSignal(
        title: title,
        kind: kind,
        status: status,
        tmdbId: tmdbId,
        genres: genres,
      ));
      if (out.length >= cap) break;
    }
    return out;
  }

  /// Líneas para el prompt (igual que Kino).
  static String lines(List<WatchedSignal> watched) {
    return watched
        .map((w) => '- ${w.title} (${w.kind}): ${w.status}')
        .join('\n');
  }
}
