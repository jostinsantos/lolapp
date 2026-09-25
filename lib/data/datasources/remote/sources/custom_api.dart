// lib/servicio/custom_api.dart
//
// Fuentes personalizadas ILIMITADAS.
//
// - Si el usuario pone solo un código (ej: 44029)
//   → se usa la API de Modlyo: https://modlyo.com/lolfuentes/api.php?idcodigo=44029
//
// - Si el usuario pone una URL completa
//   → se usa exactamente esa URL (no se fuerza Modlyo)
//
// Prefs:
//   custom_api_enabled  (bool)
//   custom_api_sources  (JSON list de strings URL)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CustomApiServer {
  final String name;
  final String url;
  final String idiomaCode;
  final String codigo;
  final String fuenteTitulo;
  final String sourceUrl;

  const CustomApiServer({
    required this.name,
    required this.url,
    required this.idiomaCode,
    required this.codigo,
    required this.fuenteTitulo,
    required this.sourceUrl,
  });

  Map<String, dynamic> toModalMap() {
    final label = fuenteTitulo.isNotEmpty
        ? fuenteTitulo
        : (codigo.isNotEmpty ? 'API $codigo' : 'Mi API');
    return {
      'servidor_nombre': name,
      'servidor_url': url,
      'calidad': 'HD',
      'idioma': idiomaCode,
      'estado': 'activo',
      'es_customapi': true,
      'custom_codigo': codigo,
      'custom_source_url': sourceUrl,
      'fuente_id': codigo.isNotEmpty ? 'custom_$codigo' : 'customapi',
      'fuente_label': label,
    };
  }
}

class CustomApiConfig {
  static const _kEnabled = 'custom_api_enabled';
  static const _kSources = 'custom_api_sources';

  /// Base de Modlyo (solo se usa cuando el usuario pone solo un código)
  static const String modlyoBase =
      'https://modlyo.com/lolfuentes/api.php?idcodigo=';

  final List<String> sources;

  const CustomApiConfig({required this.sources});

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
  }

  static Future<CustomApiConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSources);
    if (raw == null || raw.isEmpty) {
      return const CustomApiConfig(sources: []);
    }
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return CustomApiConfig(
          sources: list
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        );
      }
    } catch (_) {}

    // Compatibilidad con formato antiguo (CSV)
    final parts = raw
        .split(RegExp(r'[,;\s]+'))
        .map((e) => e.trim())
        .where((e) => e.startsWith('http'))
        .toList();
    return CustomApiConfig(sources: parts);
  }

  static Future<void> saveSources(List<String> sources) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSources, jsonEncode(sources));
  }

  /// Añade una fuente.
  /// 
  /// - Si recibe solo un código (ej: "44029") → usa Modlyo
  /// - Si recibe una URL completa → usa esa URL tal cual
  static Future<String?> addSource({
    String? fullUrl,
    String? codigo,
  }) async {
    String url = (fullUrl ?? '').trim();

    // Caso 1: el usuario puso solo un código
    if (url.isEmpty && codigo != null && codigo.trim().isNotEmpty) {
      final c = codigo.trim();
      // Si por error pegaron una URL en el campo de código
      if (c.startsWith('http')) {
        url = c;
      } else {
        url = '$modlyoBase$c';
      }
    }

    // Caso 2: el usuario pegó una URL completa
    if (url.isEmpty) {
      return 'Debes escribir un código o una URL completa';
    }

    if (!url.startsWith('http')) {
      // Si no empieza por http, asumimos que es un código
      url = '$modlyoBase$url';
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return 'URL no válida';

    // Si es una URL de Modlyo, exigimos que tenga idcodigo
    final isModlyo = url.contains('modlyo.com') && url.contains('api.php');
    if (isModlyo) {
      if (!uri.queryParameters.containsKey('idcodigo') ||
          (uri.queryParameters['idcodigo'] ?? '').isEmpty) {
        return 'La URL de Modlyo debe incluir idcodigo=XXXXX';
      }
    }

    final cfg = await load();
    if (cfg.sources.contains(url)) return 'Esa fuente ya está añadida';

    await saveSources([...cfg.sources, url]);
    return null; // ok
  }

  static Future<void> removeSource(String url) async {
    final cfg = await load();
    await saveSources(cfg.sources.where((e) => e != url).toList());
  }

  static String extractCodigo(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['idcodigo'] ?? '';
  }
}

class CustomApiService {
  static String _normIdioma(String? raw) {
    if (raw == null || raw.isEmpty) return 'es_MX';
    final l = raw.toLowerCase().trim();
    if (l.contains('castellano') || l.contains('es_es') || l == 'esp') {
      return 'es_ES';
    }
    if (l.contains('sub') ||
        l.startsWith('en') ||
        l.contains('ingl') ||
        l.contains('english')) {
      return 'en_US';
    }
    if (l.contains('japon')) return 'ja_JA';
    return 'es_MX';
  }

  /// Consulta UNA fuente (ya sea de Modlyo o de cualquier otra URL)
  static Stream<CustomApiServer> scrapeUrl({
    required String sourceUrl,
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (sourceUrl.isEmpty || tmdbId <= 0) return;

    final baseUri = Uri.tryParse(sourceUrl);
    if (baseUri == null) return;

    final codigo = baseUri.queryParameters['idcodigo'] ?? '';
    final tipo = isMovie ? 'movie' : 'tv';

    // Añadimos los parámetros que la App siempre envía
    final qp = Map<String, String>.from(baseUri.queryParameters);
    qp['idtmdb'] = '$tmdbId';
    qp['tipo'] = tipo;

    if (!isMovie) {
      qp['temporada'] = '$season';
      qp['capitulo'] = '$episode';
    } else {
      qp.remove('temporada');
      qp.remove('capitulo');
    }

    final uri = baseUri.replace(queryParameters: qp);

    debugPrint('[CustomAPI] Consultando: $uri');

    try {
      final res = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
              'Referer': 'https://modlyo.com/',
            },
          )
          .timeout(const Duration(seconds: 60));

      debugPrint('[CustomAPI] Status: ${res.statusCode}');

      if (res.statusCode != 200) {
        debugPrint('[CustomAPI] Error HTTP: ${res.statusCode}');
        debugPrint('[CustomAPI] Body: ${res.body}');
        return;
      }

      final body = jsonDecode(res.body);
      if (body is! Map) {
        debugPrint('[CustomAPI] Body no es Map');
        return;
      }

      if (body['status']?.toString() != 'ok') {
        debugPrint('[CustomAPI] status != ok → ${body['status']}');
        return;
      }

      final fuenteTitulo =
          (body['fuente'] is Map ? body['fuente']['titulo'] : null)
                  ?.toString() ??
              '';

      final list = body['servidores'];
      if (list is! List) {
        debugPrint('[CustomAPI] No hay lista de servidores');
        return;
      }

      debugPrint('[CustomAPI] Servidores recibidos: ${list.length}');

      for (final item in list) {
        if (item is! Map) continue;
        final playUrl = item['url']?.toString() ?? '';
        if (playUrl.isEmpty) continue;

        var name = (item['servidor']?.toString() ?? 'Servidor').trim();
        if (name.isNotEmpty) {
          name = name[0].toUpperCase() + name.substring(1);
        }

        yield CustomApiServer(
          name: name.isEmpty ? 'Servidor' : name,
          url: playUrl,
          idiomaCode: _normIdioma(item['idioma']?.toString()),
          codigo: codigo,
          fuenteTitulo: fuenteTitulo,
          sourceUrl: sourceUrl,
        );
      }
    } catch (e, st) {
      debugPrint('[CustomAPI] EXCEPCIÓN: $e');
      debugPrint(st.toString());
    }
  }

  /// Emite servidores de TODAS las fuentes configuradas
  static Stream<CustomApiServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    final enabled = await CustomApiConfig.isEnabled();
    if (!enabled) {
      debugPrint('[CustomAPI] Desactivado');
      return;
    }

    final cfg = await CustomApiConfig.load();
    if (cfg.sources.isEmpty) {
      debugPrint('[CustomAPI] No hay fuentes configuradas');
      return;
    }

    debugPrint('[CustomAPI] Fuentes a consultar: ${cfg.sources.length}');

    for (final sourceUrl in cfg.sources) {
      await for (final s in scrapeUrl(
        sourceUrl: sourceUrl,
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      )) {
        yield s;
      }
    }
  }
}