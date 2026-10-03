import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/addon.dart';
import '../models/content.dart';
import 'catalog_js_bridge.dart';

/// La app NO llama a TMDB directamente.
/// Cada catálogo (repo Git) aporta datos vía:
/// 1) JS del addon (getHome / search / discover / getMeta)
/// 2) o json_api / static_json en extra
class CatalogService {
  final _js = CatalogJsBridge.instance;

  /// Config que se pasa al JS del addon.
  /// Prioridad: userConfig > defaults del schema > extra del manifest.
  /// La API key debe venir del ADDON (extra o hardcode en index.js), no de la app.
  Map<String, String> _config(AddonManifest a) {
    final m = <String, String>{};
    // 1) extra del manifest (el addon declara apiKey / language aquí)
    a.extra.forEach((k, v) {
      if (v is String) {
        m[k] = v;
      } else if (v is num || v is bool) {
        m[k] = v.toString();
      }
    });
    // 2) defaults del schema
    for (final f in a.configSchema) {
      if (f.defaultValue != null && f.defaultValue!.isNotEmpty) {
        m.putIfAbsent(f.key, () => f.defaultValue!);
      }
    }
    // 3) lo que el usuario guardó en Configurar (opcional)
    a.userConfig.forEach((k, v) {
      if (v.isNotEmpty) m[k] = v;
    });
    return m;
  }

  Future<List<CatalogRow>> getHomeRows(List<AddonManifest> catalogs) async {
    final rows = <CatalogRow>[];
    for (final a in catalogs.where((c) => c.enabled && c.isCatalog)) {
      try {
        rows.addAll(await _homeFor(a));
      } catch (e) {
        debugPrint('[Catalog] home ${a.id}: $e');
      }
    }
    return rows;
  }

  Future<List<ContentItem>> search(
    String query,
    List<AddonManifest> catalogs,
  ) async {
    final out = <ContentItem>[];
    final seen = <String>{};
    for (final a in catalogs.where((c) => c.enabled && c.isCatalog)) {
      try {
        for (final item in await _searchFor(a, query)) {
          if (seen.add(item.id)) out.add(item);
        }
      } catch (e) {
        debugPrint('[Catalog] search ${a.id}: $e');
      }
    }
    return out;
  }

  Future<List<ContentItem>> discover({
    required AddonManifest addon,
    required String category,
    dynamic genreId,
    int page = 1,
  }) async {
    if (!addon.enabled || !addon.isCatalog) return [];
    final code = addon.rawCode;
    if (code != null && code.isNotEmpty) {
      final data = await _js.call(
        addonId: addon.id,
        code: code,
        method: 'discover',
        args: {
          'category': category,
          if (genreId != null) 'genreId': genreId,
          if (genreId != null) 'genero': genreId.toString(),
          if (genreId != null) 'genre': genreId.toString(),
          'page': page,
        },
        config: _config(addon),
      );
      return _parseItems(data);
    }
    return _jsonApiList(addon, 'discover', {
      'category': category,
      if (genreId != null) 'genre': '$genreId',
      'page': '$page',
    });
  }

  Future<ContentItem?> getDetails(
    ContentItem item,
    List<AddonManifest> catalogs,
  ) async {
    for (final a in catalogs.where((c) => c.enabled && c.isCatalog)) {
      try {
        final code = a.rawCode;
        if (code == null || code.isEmpty) continue;
        final data = await _js.call(
          addonId: a.id,
          code: code,
          method: 'getMeta',
          args: {
            'id': item.id,
            'type': item.type.name,
          },
          config: _config(a),
        );
        final parsed = _parseSingleItem(data);
        if (parsed != null) return parsed;
      } catch (e) {
        debugPrint('[Catalog] meta ${a.id}: $e');
      }
    }
    return item;
  }

  Future<List<CatalogRow>> _homeFor(AddonManifest a) async {
    final code = a.rawCode;
    if (code != null && code.isNotEmpty) {
      final data = await _js.call(
        addonId: a.id,
        code: code,
        method: 'getHome',
        args: const {},
        config: _config(a),
      );
      return _parseRows(data, a);
    }
    final provider = (a.extra['provider'] ?? '').toString();
    if (provider == 'json_api' || provider == 'static_json') {
      final items = await _jsonApiList(a, 'home', {});
      if (items.isEmpty) return [];
      return [CatalogRow(id: '${a.id}-home', title: a.name, items: items)];
    }
    return [];
  }

  Future<List<ContentItem>> _searchFor(AddonManifest a, String q) async {
    final code = a.rawCode;
    List<ContentItem> items = [];
    if (code != null && code.isNotEmpty) {
      try {
        final data = await _js.call(
          addonId: a.id,
          code: code,
          method: 'search',
          // query + q: compat con todos los addons JS
          args: {'query': q, 'q': q},
          config: _config(a),
        );
        items = _parseItems(data);
      } catch (e) {
        debugPrint('[Catalog] search JS ${a.id}: $e');
      }
    }
    if (items.isEmpty) {
      try {
        items = await _jsonApiList(a, 'search', {'q': q, 'query': q});
      } catch (e) {
        debugPrint('[Catalog] search JSON ${a.id}: $e');
      }
    }
    // Marcar de qué catálogo vino cada resultado
    return items
        .map((it) => ContentItem(
              id: it.id,
              title: it.title,
              originalTitle: it.originalTitle,
              type: it.type,
              poster: it.poster,
              backdrop: it.backdrop,
              overview: it.overview,
              year: it.year,
              rating: it.rating,
              genres: it.genres,
              addonId: it.addonId ?? a.id,
              extra: {...it.extra, 'catalogId': a.id, 'catalogName': a.name},
            ))
        .toList();
  }

  List<CatalogRow> _parseRows(dynamic data, AddonManifest a) {
    if (data == null) return [];
    List? rows;
    if (data is Map) {
      rows = data['rows'] as List? ?? data['catalogs'] as List?;
      if (rows == null && data['items'] is List) {
        return [
          CatalogRow(
            id: '${a.id}-home',
            title: a.name,
            items: _parseItems(data),
          ),
        ];
      }
    } else if (data is List) {
      rows = data;
    }
    if (rows == null) return [];
    final out = <CatalogRow>[];
    for (final r in rows) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      final items = _parseItems(m['items'] ?? m['results']);
      out.add(CatalogRow(
        id: m['id']?.toString() ?? '${a.id}-${out.length}',
        title: m['title']?.toString() ?? m['name']?.toString() ?? '',
        items: items,
      ));
    }
    return out;
  }

  List<ContentItem> _parseItems(dynamic data) {
    List list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['items'] ?? data['results'] ?? data['data'] ?? []) as List;
    } else {
      return [];
    }
    return list
        .whereType<Map>()
        .map((e) {
          try {
            return ContentItem.fromJson(Map<String, dynamic>.from(e));
          } catch (_) {
            return _mapLoose(Map<String, dynamic>.from(e));
          }
        })
        .whereType<ContentItem>()
        .toList();
  }

  ContentItem? _parseSingleItem(dynamic data) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final list = m['item'] is Map
          ? _parseItems([m['item']])
          : _parseItems([m]);
      if (list.isEmpty) return null;
      return list.first;
    }
    return null;
  }

  ContentItem? _mapLoose(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? m['contentId']?.toString();
    final title = m['title']?.toString() ?? m['name']?.toString();
    if (id == null || title == null) return null;
    final typeStr =
        (m['type'] ?? m['mediaType'] ?? 'movie').toString().toLowerCase();
    final type = (typeStr.contains('tv') ||
            typeStr.contains('series') ||
            typeStr.contains('anime') ||
            typeStr == 'show')
        ? ContentType.series
        : (typeStr.contains('live') || typeStr.contains('channel')
            ? ContentType.live
            : ContentType.movie);
    final genres = <String>[];
    final g = m['genres'];
    if (g is List) {
      for (final e in g) {
        if (e is String && e.isNotEmpty) {
          genres.add(e);
        } else if (e is Map && e['name'] != null) {
          genres.add(e['name'].toString());
        }
      }
    }
    final extra = Map<String, dynamic>.from(m['extra'] as Map? ?? {});
    // Temporadas: normalizar seasonNumber / episodes desde varios formatos
    dynamic seasonsRaw = m['seasons'] ?? extra['seasons'];
    if (seasonsRaw is List && seasonsRaw.isNotEmpty) {
      final norm = <Map<String, dynamic>>[];
      for (final s in seasonsRaw) {
        if (s is! Map) continue;
        final sm = Map<String, dynamic>.from(s);
        final sn = (sm['seasonNumber'] as num?)?.toInt() ??
            (sm['season_number'] as num?)?.toInt() ??
            (sm['number'] as num?)?.toInt() ??
            1;
        final epsRaw = sm['episodes'] as List? ?? [];
        final eps = <Map<String, dynamic>>[];
        for (final e in epsRaw) {
          if (e is! Map) continue;
          final em = Map<String, dynamic>.from(e);
          final epNum = (em['episodeNumber'] as num?)?.toInt() ??
              (em['episode_number'] as num?)?.toInt() ??
              (em['number'] as num?)?.toInt() ??
              (eps.length + 1);
          final url = em['url']?.toString() ??
              em['link']?.toString() ??
              (em['extra'] is Map
                  ? (em['extra']['url'] ?? em['extra']['jkanimeUrl'])?.toString()
                  : null);
          final epExtra = Map<String, dynamic>.from(em['extra'] as Map? ?? {});
          if (url != null && url.isNotEmpty) {
            epExtra['url_personalizada'] = url;
            epExtra['jkanimeUrl'] = url;
            epExtra['tmdbId'] = url;
          }
          eps.add({
            'episodeNumber': epNum,
            'number': epNum,
            'title': em['title'] ?? em['name'] ?? 'Episodio $epNum',
            'name': em['name'] ?? em['title'] ?? 'Episodio $epNum',
            'overview': em['overview'] ?? em['description'],
            'still': em['still'] ?? em['poster'] ?? em['image'],
            'poster': em['poster'] ?? em['still'] ?? em['image'],
            'airDate': em['airDate'] ?? em['air_date'],
            'url': url,
            'extra': epExtra,
          });
        }
        final count = (sm['episodeCount'] as num?)?.toInt() ??
            (sm['episode_count'] as num?)?.toInt() ??
            eps.length;
        norm.add({
          'seasonNumber': sn,
          'season_number': sn,
          'name': sm['name'] ?? sm['title'] ?? 'Temporada $sn',
          'episodeCount': count,
          'episode_count': count,
          'poster': sm['poster'] ?? sm['poster_path'],
          'overview': sm['overview'],
          'episodes': eps,
        });
      }
      extra['seasons'] = norm;
    }
    if (m['tmdbId'] != null && !extra.containsKey('tmdbId')) {
      extra['tmdbId'] = m['tmdbId'];
    }
    if (m['url'] != null) {
      extra['jkanimeUrl'] = m['url'];
      extra.putIfAbsent('url_personalizada', () => m['url']);
    }
    if (m['slug'] != null) extra['jkanimeSlug'] = m['slug'];
    // Series si hay temporadas aunque el type venga mal
    var resolvedType = type;
    if (resolvedType == ContentType.movie &&
        (extra['seasons'] is List && (extra['seasons'] as List).isNotEmpty)) {
      resolvedType = ContentType.series;
    }
    // Evitar título = nombre del addon
    var resolvedTitle = title;
    final lower = title.toLowerCase();
    if (lower == 'jkanime' || lower == 'jk anime' || lower.startsWith('jkanime ')) {
      final alt = m['originalTitle']?.toString() ??
          m['original_title']?.toString() ??
          m['name']?.toString();
      if (alt != null && alt.isNotEmpty && alt.toLowerCase() != lower) {
        resolvedTitle = alt;
      }
    }
    return ContentItem(
      id: id,
      title: resolvedTitle,
      originalTitle: m['originalTitle']?.toString() ?? m['original_title']?.toString(),
      type: resolvedType,
      poster: m['poster']?.toString() ?? m['posterUrl']?.toString() ?? m['image']?.toString(),
      backdrop: m['backdrop']?.toString() ?? m['banner']?.toString(),
      overview: m['overview']?.toString() ?? m['description']?.toString() ?? m['synopsis']?.toString(),
      year: m['year']?.toString() ?? m['releaseYear']?.toString(),
      rating: (m['rating'] as num?)?.toDouble() ??
          (m['vote_average'] as num?)?.toDouble() ??
          (m['score'] as num?)?.toDouble(),
      genres: genres,
      addonId: m['addonId']?.toString(),
      extra: extra,
    );
  }

  Future<List<ContentItem>> _jsonApiList(
    AddonManifest a,
    String action,
    Map<String, String> params,
  ) async {
    final base = a.configValue('baseUrl') ??
        a.extra['baseUrl']?.toString() ??
        a.extra['base']?.toString() ??
        '';
    if (base.isEmpty) return [];
    final paths = Map<String, dynamic>.from(a.extra['paths'] as Map? ?? {});
    final path = paths[action]?.toString() ?? '/$action';
    final uri = Uri.parse(base.replaceAll(RegExp(r'/$'), '') + path)
        .replace(queryParameters: params);
    final res = await http.get(Uri.parse(uri.toString()));
    if (res.statusCode != 200) return [];
    return _parseItems(jsonDecode(res.body));
  }
}
