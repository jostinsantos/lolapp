import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _kCacheTtl = Duration(days: 2);

class ServidoresPreloader {
  static final Map<String, Future<void>> _inFlight = {};
  static final Map<String, List<Map<String, dynamic>>> _memory = {};

  static String cacheKey({
    required int idcontenido,
    required String tipo,
    int? temporada,
    int? capitulo,
  }) {
    final t = temporada ?? 0;
    final c = capitulo ?? 0;
    return 'serv_cache_${idcontenido}_${tipo}_${t}_$c';
  }

  static String memoryKey({
    required int idcontenido,
    required String tipo,
    int? temporada,
    int? capitulo,
  }) =>
      cacheKey(
        idcontenido: idcontenido,
        tipo: tipo,
        temporada: temporada,
        capitulo: capitulo,
      );

  static Future<List<Map<String, dynamic>>?> loadCache({
    required int idcontenido,
    required String tipo,
    int? temporada,
    int? capitulo,
  }) async {
    final key = cacheKey(
      idcontenido: idcontenido,
      tipo: tipo,
      temporada: temporada,
      capitulo: capitulo,
    );
    if (_memory.containsKey(key)) {
      return List<Map<String, dynamic>>.from(_memory[key]!);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = map['ts'] as int?;
      if (ts == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _kCacheTtl.inMilliseconds) {
        await prefs.remove(key);
        return null;
      }
      final lista = List<Map<String, dynamic>>.from(map['servidores'] ?? []);
      _memory[key] = lista;
      return lista;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCache({
    required int idcontenido,
    required String tipo,
    int? temporada,
    int? capitulo,
    required List<Map<String, dynamic>> servidores,
  }) async {
    final key = cacheKey(
      idcontenido: idcontenido,
      tipo: tipo,
      temporada: temporada,
      capitulo: capitulo,
    );
    _memory[key] = List<Map<String, dynamic>>.from(servidores);
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'servidores': servidores,
      };
      await prefs.setString(key, jsonEncode(payload));
    } catch (_) {}
  }

  static Future<void> clearCache({
    required int idcontenido,
    required String tipo,
    int? temporada,
    int? capitulo,
  }) async {
    final key = cacheKey(
      idcontenido: idcontenido,
      tipo: tipo,
      temporada: temporada,
      capitulo: capitulo,
    );
    _memory.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  static Future<void> preload({
    required int idcontenido,
    String tipo = 'movie',
    int? temporada,
    int? capitulo,
    int? tmdbId,
  }) {
    final key = memoryKey(
      idcontenido: idcontenido,
      tipo: tipo,
      temporada: temporada,
      capitulo: capitulo,
    );
    if (_inFlight.containsKey(key)) return _inFlight[key]!;
    final future = _doPreload(
      idcontenido: idcontenido,
      tipo: tipo,
      temporada: temporada,
      capitulo: capitulo,
      tmdbId: tmdbId,
    );
    _inFlight[key] = future;
    future.whenComplete(() => _inFlight.remove(key));
    return future;
  }

  static Future<void> _doPreload({
    required int idcontenido,
    required String tipo,
    int? temporada,
    int? capitulo,
    int? tmdbId,
  }) async {
    final existing = await loadCache(
      idcontenido: idcontenido,
      tipo: tipo,
      temporada: temporada,
      capitulo: capitulo,
    );
    if (existing != null && existing.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final cuevanaEnabled = prefs.getBool('cuevana_enabled') ?? false;
    final verificar = prefs.getBool('verificar_servidores') ?? true;

    final isMovie = temporada == null && capitulo == null;
    final todos = <Map<String, dynamic>>[];

    try {
      final String url = isMovie
          ? 'https://modlyo.com/appapi/api_servidores.php?idcontenido=$idcontenido&tipo=movie'
          : 'https://modlyo.com/appapi/api_servidores.php?idcontenido=$idcontenido&tipo=tv&temporada=$temporada&capitulo=$capitulo';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          final lista =
              List<Map<String, dynamic>>.from(json['servidores'] ?? [])
                  .where(
                    (s) =>
                        (s['estado']?.toString().toLowerCase() ?? 'activo') ==
                        'activo',
                  )
                  .toList();
          todos.addAll(lista);
        }
      }
    } catch (_) {}

    if (cuevanaEnabled) {
      try {
        final String cuevanaUrl = isMovie
            ? 'https://www.modlyo.com/apitv/apicuevana.php?type=movie&id=$idcontenido'
            : 'https://www.modlyo.com/apitv/apicuevana.php?type=capitulo&id=$idcontenido&temporada=$temporada&capitulo=$capitulo';
        final response = await http
            .get(Uri.parse(cuevanaUrl))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final cuevanaJson = jsonDecode(response.body);
          if (cuevanaJson['success'] == true &&
              cuevanaJson['video_groups'] != null) {
            for (final group in cuevanaJson['video_groups']) {
              final String language = group['language']?.toString() ?? '';
              final List videos = group['videos'] ?? [];
              String idiomaCode = 'es_MX';
              final langLower = language.toLowerCase();
              if (langLower.contains('castellano') ||
                  langLower.contains('españa')) {
                idiomaCode = 'es_ES';
              } else if (langLower.contains('inglés') ||
                  langLower.contains('english') ||
                  langLower.contains('sub')) {
                idiomaCode = 'en_US';
              } else if (langLower.contains('japon')) {
                idiomaCode = 'ja_JA';
              }
              for (final v in videos) {
                final String cleanUrl = v['mapped_url']?.toString() ?? '';
                if (cleanUrl.isEmpty) continue;
                todos.add({
                  'servidor_nombre':
                      'Cuevana · ${v['cyberlocker'] ?? 'Servidor'}',
                  'servidor_url': cleanUrl,
                  'calidad': v['quality'] ?? 'HD',
                  'idioma': idiomaCode,
                  'estado': 'activo',
                  'es_cuevana': true,
                });
              }
            }
          }
        }
      } catch (_) {}
    }

    if (!verificar || todos.isEmpty) {
      if (todos.isNotEmpty) {
        await saveCache(
          idcontenido: idcontenido,
          tipo: tipo,
          temporada: temporada,
          capitulo: capitulo,
          servidores: todos,
        );
      }
      return;
    }

    final validos = <Map<String, dynamic>>[];
    for (final servidor in todos) {
      final url = servidor['servidor_url']?.toString() ?? '';
      if (url.isEmpty) continue;
      try {
        final head = await http
            .head(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (head.statusCode >= 200 && head.statusCode < 400) {
          validos.add(servidor);
        }
      } catch (_) {
        try {
          final get = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 6));
          if (get.statusCode >= 200 && get.statusCode < 400) {
            validos.add(servidor);
          }
        } catch (_) {}
      }
    }

    if (validos.isNotEmpty) {
      await saveCache(
        idcontenido: idcontenido,
        tipo: tipo,
        temporada: temporada,
        capitulo: capitulo,
        servidores: validos,
      );
    }
  }
}