import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/content.dart';
import 'stremio_addon_repository.dart';
import 'stremio_models.dart';
import 'stremio_url_builder.dart';

/// Resuelve streams vía protocolo Stremio:
/// GET {base}/stream/{type}/{id}.json  →  { "streams": [ ... ] }
///
/// Misma lógica que Nuvio StreamsRepository (buildAddonResourceUrl + resource=stream).
/// No sustituye las fuentes JS de la app: se suman a ellas.
class StremioStreamService {
  StremioStreamService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const _timeout = Duration(seconds: 18);
  static const _ua = 'LolPlusTV/1.0 (Stremio-compatible)';

  /// Addons activos que declaran resource "stream"
  List<ManagedStremioAddon> streamAddons() {
    return StremioAddonRepository.instance.enabledAddons.where((a) {
      final m = a.manifest;
      if (m == null) return false;
      return m.resources.any((r) => r.name.toLowerCase() == 'stream') ||
          // Si no lista resources pero tiene catalogs, algunos addons aún sirven stream
          m.resources.isEmpty;
    }).toList();
  }

  /// ID de vídeo Stremio a partir del contenido de la app.
  /// movie: tt… / tmdb:123 / id crudo
  /// series episodio: id:season:episode
  String resolveVideoId(ContentItem content, {int? season, int? episode}) {
    final extra = content.extra;
    final stremioId = extra['stremioId']?.toString();
    if (stremioId != null && stremioId.isNotEmpty) {
      if (season != null && episode != null && !stremioId.contains(':')) {
        return '$stremioId:$season:$episode';
      }
      return stremioId;
    }

    final imdb = extra['imdb']?.toString() ?? extra['imdb_id']?.toString();
    if (imdb != null && imdb.isNotEmpty) {
      final id = imdb.startsWith('tt') ? imdb : 'tt$imdb';
      if (season != null && episode != null) return '$id:$season:$episode';
      return id;
    }

    final tmdb = extra['tmdbId'] ?? extra['tmdb_id'];
    if (tmdb != null) {
      final prefix = content.type == ContentType.series ? 'tmdb' : 'tmdb';
      final base = '$prefix:$tmdb';
      if (season != null && episode != null) return '$base:$season:$episode';
      // Formato habitual en addons: tmdb:12345
      return 'tmdb:$tmdb';
    }

    // Fallback: id del ContentItem
    var id = content.id;
    if (id.contains('tmdb:')) {
      final n = id.split(':').last;
      id = 'tmdb:$n';
    }
    if (season != null && episode != null && !id.contains(':$season:')) {
      return '$id:$season:$episode';
    }
    return id;
  }

  String resolveType(ContentItem content) {
    final st = content.extra['stremioType']?.toString();
    if (st != null && st.isNotEmpty) return st;
    switch (content.type) {
      case ContentType.series:
      case ContentType.episode:
        return 'series';
      case ContentType.live:
        return 'channel';
      case ContentType.movie:
        return 'movie';
    }
  }

  Future<List<StreamItem>> getStreamsForContent({
    required ContentItem content,
    int? season,
    int? episode,
  }) async {
    await StremioAddonRepository.instance.init();
    final addons = streamAddons();
    if (addons.isEmpty) return [];

    final type = resolveType(content);
    final videoId = resolveVideoId(content, season: season, episode: episode);
    final results = <StreamItem>[];

    await Future.wait(addons.map((addon) async {
      try {
        final streams = await fetchStreamsFromAddon(
          manifestUrl: addon.manifestUrl,
          type: type,
          videoId: videoId,
          addonName: addon.displayName,
          addonId: addon.manifest?.id ?? addon.manifestUrl,
        );
        results.addAll(streams);
      } catch (e) {
        debugPrint('[StremioStream] ${addon.displayName}: $e');
      }
    }));

    final seen = <String>{};
    return results.where((s) => seen.add('${s.url}|${s.infoHash}')).toList();
  }

  Future<List<StreamItem>> fetchStreamsFromAddon({
    required String manifestUrl,
    required String type,
    required String videoId,
    required String addonName,
    required String addonId,
  }) async {
    final url = buildStremioResourceUrl(
      manifestUrl: manifestUrl,
      resource: 'stream',
      type: type,
      id: videoId,
    );
    debugPrint('[StremioStream] GET $url');
    final res = await _http.get(
      Uri.parse(url),
      headers: {'User-Agent': _ua, 'Accept': 'application/json'},
    ).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return parseStreamsPayload(
      res.body,
      addonName: addonName,
      addonId: addonId,
    );
  }

  /// Parsea { "streams": [ ... ] } según spec Stremio
  static List<StreamItem> parseStreamsPayload(
    String payload, {
    required String addonName,
    required String addonId,
  }) {
    final root = jsonDecode(payload) as Map<String, dynamic>;
    final list = root['streams'] as List? ?? [];
    final out = <StreamItem>[];

    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);

      final url = (m['url'] ?? '').toString();
      final infoHash = m['infoHash']?.toString();
      final ytId = m['ytId']?.toString();
      final externalUrl = m['externalUrl']?.toString();
      final magnet = m['magnet']?.toString();

      String finalUrl = url;
      if (finalUrl.isEmpty && magnet != null) finalUrl = magnet;
      if (finalUrl.isEmpty && infoHash != null && infoHash.isNotEmpty) {
        finalUrl = 'magnet:?xt=urn:btih:$infoHash';
      }
      if (finalUrl.isEmpty && ytId != null && ytId.isNotEmpty) {
        finalUrl = 'https://www.youtube.com/watch?v=$ytId';
      }
      if (finalUrl.isEmpty && externalUrl != null) finalUrl = externalUrl;
      if (finalUrl.isEmpty) continue;

      // Headers de proxy (behaviorHints.proxyHeaders.request)
      final headers = <String, String>{};
      final bh = m['behaviorHints'];
      if (bh is Map) {
        final ph = bh['proxyHeaders'];
        if (ph is Map) {
          final req = ph['request'];
          if (req is Map) {
            req.forEach((k, v) {
              if (k != null && v != null) headers[k.toString()] = v.toString();
            });
          }
        }
      }
      if (m['headers'] is Map) {
        (m['headers'] as Map).forEach((k, v) {
          if (k != null && v != null) headers[k.toString()] = v.toString();
        });
      }

      final name = (m['name'] ?? m['title'] ?? addonName).toString();
      final description = (m['description'] ?? m['title'] ?? '').toString();
      final quality = _guessQuality(name, description);

      out.add(StreamItem(
        url: finalUrl,
        title: description.isNotEmpty ? '$name · $description' : name,
        quality: quality,
        provider: addonName,
        addonId: addonId,
        headers: headers,
        isHls: finalUrl.contains('.m3u8'),
        infoHash: infoHash,
        lang: (m['lang'] ?? m['language'])?.toString(),
      ));
    }
    return out;
  }

  static String? _guessQuality(String name, String desc) {
    final t = '$name $desc'.toUpperCase();
    for (final q in ['4K', '2160P', '1080P', '720P', '480P', '360P', 'HD', 'SD']) {
      if (t.contains(q)) return q;
    }
    return null;
  }
}
