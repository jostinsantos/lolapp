import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/addon.dart';
import '../models/content.dart';
import 'js_runtime.dart';
import 'tmdb_service.dart';

/// Resuelve streams desde addons de tipo source (JS Nuvio + JSON Stremio).
class SourceService {
  final JsAddonRuntime _js = JsAddonRuntime.instance;

  static const cinecalidadJsUrl =
      'https://raw.githubusercontent.com/KennethJYS/Nuvio-Providers-Latino/refs/heads/main/providers/cinecalidad.js';

  Future<List<StreamItem>> getStreams({
    required ContentItem content,
    required List<AddonManifest> sourceAddons,
  }) async {
    final results = <StreamItem>[];

    for (final addon in sourceAddons.where((a) => a.enabled && a.isSource)) {
      try {
        final streams = await _resolveAddon(addon, content);
        results.addAll(streams.where((s) => s.url.isNotEmpty));
      } catch (e, st) {
        debugPrint('[Source] ${addon.id}: $e\n$st');
      }
    }

    final seen = <String>{};
    final unique = <StreamItem>[];
    for (final s in results) {
      if (seen.add(s.url)) unique.add(s);
    }
    return unique;
  }

  /// Primer stream válido sin esperar al resto (modo automático).
  Future<StreamItem?> getFirstStream({
    required ContentItem content,
    required List<AddonManifest> sourceAddons,
  }) async {
    final enabled = sourceAddons.where((a) => a.enabled && a.isSource).toList();
    if (enabled.isEmpty) return null;

    // Secuencial: primera fuente que responda con al menos 1 URL
    for (final addon in enabled) {
      try {
        final streams = await getStreamsForAddon(
          content: content,
          addon: addon,
        ).timeout(const Duration(seconds: 20), onTimeout: () => []);
        final ok = streams.where((s) => s.url.isNotEmpty).toList();
        if (ok.isNotEmpty) {
          debugPrint('[Source] auto: primer stream de ${addon.id}');
          return ok.first;
        }
      } catch (e) {
        debugPrint('[Source] auto ${addon.id}: $e');
      }
    }
    return null;
  }

  /// Un solo addon (para UI progresiva en Servidores).
  Future<List<StreamItem>> getStreamsForAddon({
    required ContentItem content,
    required AddonManifest addon,
  }) async {
    if (!addon.enabled) {
      debugPrint('[Source] ${addon.id}: desactivado');
      return [];
    }
    if (!addon.isSource) {
      debugPrint('[Source] ${addon.id}: no es fuente types=${addon.types}');
      return [];
    }
    try {
      final streams = await _resolveAddon(addon, content);
      final ok = streams.where((s) => s.url.isNotEmpty).toList();
      debugPrint('[Source] ${addon.id}: ${ok.length} streams finales');
      return ok;
    } catch (e, st) {
      debugPrint('[Source] ${addon.id}: $e\n$st');
      rethrow;
    }
  }

  Future<List<StreamItem>> _resolveAddon(
    AddonManifest addon,
    ContentItem content,
  ) async {
    final jsCode = await _resolveJsCode(addon);
    if (jsCode != null && jsCode.trim().isNotEmpty) {
      final lower = jsCode.toLowerCase();
      final isStub = jsCode.length < 2000 &&
          (lower.contains('stub') ||
              lower.contains('sustituye este archivo') ||
              (lower.contains('getstreams') &&
                  !lower.contains('cuevana') &&
                  !lower.contains('scrape') &&
                  !lower.contains('fetch')));
      // Cuevana real tiene >10kb y scrape/extract
      final looksEmpty = jsCode.length < 1500 &&
          !jsCode.contains('scrape') &&
          !jsCode.contains('extract') &&
          !jsCode.contains('__NEXT_DATA__');
      if (isStub || looksEmpty) {
        throw Exception(
          'La fuente «${addon.name}» está incompleta '
          '(${jsCode.length} bytes, falta el index.js real). '
          'Sustituye source/index.js por el JS completo de Cuevana, '
          'súbelo a GitHub y reinstala el paquete o la fuente.',
        );
      }
      if (!jsCode.contains('getStreams') && !jsCode.contains('function stream')) {
        debugPrint(
          '[Source] ${addon.id}: el JS no define getStreams (${jsCode.length} bytes)',
        );
      }
      return _runJsGetStreams(addon, content, jsCode);
    }

    if (addon.rawCode != null && addon.rawCode!.trimLeft().startsWith('{')) {
      return _resolveStremioStyle(addon, content);
    }

    throw Exception(
      'La fuente «${addon.name}» no tiene código JS. '
      'Reinstálala desde Addons (GitHub) o desde el paquete.',
    );
  }

  /// Obtiene el JS del addon: rawCode, sourceUrl o githubCanonical.
  Future<String?> _resolveJsCode(AddonManifest addon) async {
    if (addon.rawCode != null &&
        addon.rawCode!.trim().isNotEmpty &&
        !addon.rawCode!.trimLeft().startsWith('{')) {
      // Ignorar stubs vacíos que solo loguean
      final code = addon.rawCode!;
      if (code.contains('getStreams') || code.contains('module.exports')) {
        return code;
      }
    }

    if (addon.id == 'embed69' ||
        addon.id == 'cinecalidad' ||
        (addon.sourceUrl == null && addon.origin == AddonOrigin.builtIn)) {
      try {
        final url = addon.sourceUrl ?? cinecalidadJsUrl;
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200 && res.body.contains('getStreams')) {
          return res.body;
        }
      } catch (e) {
        debugPrint('[Source] download JS ${addon.id}: $e');
      }
    }

    if (addon.sourceUrl != null && addon.sourceUrl!.isNotEmpty) {
      try {
        final res = await http
            .get(Uri.parse(addon.sourceUrl!))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
          debugPrint(
              '[Source] descargado JS ${addon.id} (${res.body.length}b)');
          return res.body;
        }
      } catch (e) {
        debugPrint('[Source] download ${addon.sourceUrl}: $e');
      }
    }

    final gh = addon.githubCanonical;
    if (gh != null && gh.isNotEmpty) {
      try {
        var s = gh;
        var branch = 'main';
        if (s.contains('@')) {
          final parts = s.split('@');
          s = parts[0];
          branch = parts.sublist(1).join('@');
          if (branch.isEmpty) branch = 'main';
        }
        final segs = s.split('/').where((e) => e.isNotEmpty).toList();
        if (segs.length >= 2) {
          final owner = segs[0];
          final repo = segs[1];
          final sub = segs.length > 2 ? segs.sublist(2).join('/') : '';
          final candidates = <String>[
            if (sub.isNotEmpty) '$sub/index.js',
            if (sub.isNotEmpty) '$sub/plugin.js',
            'index.js',
            'plugin.js',
          ];
          for (final file in candidates) {
            final url =
                'https://raw.githubusercontent.com/$owner/$repo/$branch/$file';
            final res = await http
                .get(Uri.parse(url))
                .timeout(const Duration(seconds: 15));
            if (res.statusCode == 200 &&
                (res.body.contains('getStreams') ||
                    res.body.contains('module.exports'))) {
              debugPrint('[Source] recuperado $url (${res.body.length}b)');
              return res.body;
            }
          }
        }
      } catch (e) {
        debugPrint('[Source] githubCanonical ${addon.id}: $e');
      }
    }

    debugPrint('[Source] sin código JS para ${addon.id}');
    return null;
  }

  /// Extrae URL http y S/E de ids compuestos:
  /// kino:pkg:https://site/serie/5:s1e1  →  url + S1E1
  static ({String? url, int? season, int? episode}) _unwrapStreamKey(String? raw) {
    if (raw == null || raw.trim().isEmpty) return (url: null, season: null, episode: null);
    var s = raw.trim();
    int? se;
    int? ep;
    final seRe = RegExp(r'[/:.]s(\d+)e(\d+)$', caseSensitive: false);
    final seM = seRe.firstMatch(s);
    if (seM != null) {
      se = int.tryParse(seM.group(1)!);
      ep = int.tryParse(seM.group(2)!);
      s = s.substring(0, seM.start);
    }
    // URL embebida en kino:package:https://...
    final http = RegExp(r'https?://[^\s]+').firstMatch(s);
    if (http != null) {
      var u = http.group(0)!;
      // cortar basura tras la URL si quedó
      u = u.replaceAll(RegExp(r'[:/]+$'), '');
      return (url: u, season: se, episode: ep);
    }
    if (s.startsWith('kino:') && s.split(':').length >= 3) {
      final rest = s.split(':').sublist(2).join(':');
      final nested = _unwrapStreamKey(rest);
      return (
        url: nested.url,
        season: se ?? nested.season,
        episode: ep ?? nested.episode,
      );
    }
    return (url: null, season: se, episode: ep);
  }

  /// Identificador para getStreams: TMDB numérico O URL personalizada (JKAnime…).
  ///
  /// Prioridad:
  /// 1) extra.url_personalizada (enlace del capítulo a scrapear)
  /// 2) URL embebida en id kino:…:https://…:sXeY
  /// 3) id tmdb:movie/series:N
  /// 4) extra.tmdbId (número o URL de la fuente)
  /// 5) extra.jkanimeUrl / lacartoonsUrl / sourceUrl / kinoRef
  /// 6) content.id si es jkanime:… o http…
  static ({String tmdbId, String type, int? season, int? episode})? resolveTmdb(
    ContentItem content,
  ) {
    final media =
        (content.extra['mediaType'] ?? content.extra['type'] ?? '')
            .toString()
            .toLowerCase();
    final type = media.contains('tv') ||
            media.contains('series') ||
            media.contains('anime') ||
            content.type == ContentType.series ||
            content.type == ContentType.episode
        ? 'tv'
        : 'movie';
    var season = _asInt(content.extra['season']) ??
        _asInt(content.extra['seasonNumber']);
    var episode = _asInt(content.extra['episode']) ??
        _asInt(content.extra['episodeNumber']);

    final custom = content.extra['url_personalizada']?.toString() ??
        content.extra['urlPersonalizada']?.toString() ??
        content.extra['episodeUrl']?.toString() ??
        content.extra['kinoRef']?.toString();
    if (custom != null && custom.trim().isNotEmpty) {
      final u = _unwrapStreamKey(custom);
      return (
        tmdbId: (u.url ?? custom).trim(),
        type: type,
        season: season ?? u.season,
        episode: episode ?? u.episode,
      );
    }

    // id o tmdbId estilo kino:pkg:https://…:s1e1
    for (final candidate in [
      content.id,
      content.extra['tmdbId']?.toString(),
      content.extra['tmdb_id']?.toString(),
      content.extra['lacartoonsUrl']?.toString(),
      content.extra['jkanimeUrl']?.toString(),
    ]) {
      final u = _unwrapStreamKey(candidate);
      if (u.url != null && u.url!.isNotEmpty) {
        return (
          tmdbId: u.url!,
          type: type,
          season: season ?? u.season,
          episode: episode ?? u.episode,
        );
      }
    }

    final parsed = TmdbService.parseId(content.id);
    if (parsed != null) {
      return (
        tmdbId: parsed.id,
        type: parsed.type == 'tv' || type == 'tv' ? 'tv' : 'movie',
        season: parsed.season ?? season,
        episode: parsed.episode ?? episode,
      );
    }

    final extraId = content.extra['tmdbId'] ?? content.extra['tmdb_id'];
    final id = extraId?.toString().trim();
    if (id != null && id.isNotEmpty) {
      return (
        tmdbId: id,
        type: type,
        season: season,
        episode: episode,
      );
    }

    final jk = content.extra['jkanimeUrl']?.toString() ??
        content.extra['lacartoonsUrl']?.toString() ??
        content.extra['sourceUrl']?.toString();
    if (jk != null && jk.trim().isNotEmpty) {
      return (
        tmdbId: jk.trim(),
        type: type,
        season: season,
        episode: episode,
      );
    }

    final cid = content.id;
    if (cid.startsWith('jkanime:') ||
        cid.contains('jkanime.net') ||
        cid.startsWith('lacartoons:') ||
        cid.contains('lacartoons.com') ||
        cid.startsWith('http')) {
      return (
        tmdbId: cid,
        type: type,
        season: season,
        episode: episode,
      );
    }

    return null;
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Future<List<StreamItem>> _runJsGetStreams(
    AddonManifest addon,
    ContentItem content,
    String code,
  ) async {
    final info = resolveTmdb(content);
    if (info == null) {
      debugPrint(
        '[Source] ${addon.id}: sin tmdbId (id=${content.id} extra=${content.extra.keys.toList()})',
      );
      return [];
    }

    debugPrint(
      '[Source] ${addon.name}: getStreams tmdb=${info.tmdbId} type=${info.type} '
      'S${info.season}E${info.episode} code=${code.length}b',
    );

    // Siempre recargar: evita quedar con stub viejo en el runtime JS
    await _js.loadAddonCode(addon.id, code);

    final streams = await _js.callGetStreams(
      addonId: addon.id,
      tmdbId: info.tmdbId,
      type: info.type,
      season: info.season,
      episode: info.episode,
      addonName: addon.name,
    );

    debugPrint('[Source] ${addon.name}: ${streams.length} streams crudos');
    return _applyExtractor(addon.id, streams);
  }

  bool _looksPlayable(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u8') ||
        u.contains('.mp4') ||
        u.contains('.mkv') ||
        u.contains('playlist') ||
        u.contains('/hls/');
  }

  Future<List<StreamItem>> _applyExtractor(
    String addonId,
    List<StreamItem> streams,
  ) async {
    if (streams.isEmpty) return streams;
    final out = <StreamItem>[];
    for (final s in streams) {
      if (_looksPlayable(s.url)) {
        out.add(s);
        continue;
      }
      try {
        final extracted = await _js.callExtract(
          addonId: addonId,
          embedUrl: s.url,
        );
        final newUrl = extracted?['url']?.toString();
        if (newUrl != null &&
            newUrl.isNotEmpty &&
            newUrl.startsWith('http')) {
          final headers = <String, String>{};
          final h = extracted!['headers'];
          if (h is Map) {
            h.forEach((k, v) {
              if (v != null) headers[k.toString()] = v.toString();
            });
          }
          out.add(StreamItem(
            url: newUrl,
            title: s.title,
            quality: extracted['quality']?.toString() ?? s.quality,
            provider: s.provider,
            headers: headers.isNotEmpty ? headers : s.headers,
            addonId: s.addonId,
            isHls: newUrl.contains('.m3u8'),
          ));
          debugPrint('[Source] extract OK ${s.title}: $newUrl');
        } else {
          out.add(s);
        }
      } catch (e) {
        debugPrint('[Source] extract fail: $e');
        out.add(s);
      }
    }
    return out;
  }

  Future<List<StreamItem>> _resolveStremioStyle(
    AddonManifest addon,
    ContentItem content,
  ) async {
    final base = addon.extra['baseUrl'] as String? ??
        _guessBase(addon.sourceUrl) ??
        '';
    if (base.isEmpty) return [];

    final info = resolveTmdb(content);
    final type = content.type == ContentType.series ? 'series' : 'movie';
    final id = info?.tmdbId ?? content.id;
    final url = '$base/stream/$type/$id.json';

    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      final list =
          data is Map ? (data['streams'] as List? ?? []) : (data as List? ?? []);
      return list
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            m['addonId'] = addon.id;
            return StreamItem.fromJson(m);
          })
          .where((s) => s.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  String? _guessBase(String? sourceUrl) {
    if (sourceUrl == null) return null;
    try {
      final u = Uri.parse(sourceUrl);
      final segs = List<String>.from(u.pathSegments);
      if (segs.isNotEmpty) segs.removeLast();
      return u.replace(pathSegments: segs).toString().replaceAll(RegExp(r'/$'), '');
    } catch (_) {
      return null;
    }
  }
}
