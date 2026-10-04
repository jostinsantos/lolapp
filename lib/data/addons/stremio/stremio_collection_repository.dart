import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/content.dart';
import 'stremio_addon_repository.dart';
import 'stremio_models.dart';

/// Colección estilo Nuvio: apunta a uno o más catálogos de addons
/// (o lista manual de metas) y se muestra en Inicio / biblioteca.
///
/// Formato de import compatible conceptualmente con Nuvio Collection:
/// { "id", "title", "sources": [ { "provider":"addon", "addonId", "type", "catalogId", "genre" } ] }
class StremioCollectionRepository extends ChangeNotifier {
  StremioCollectionRepository._();
  static final StremioCollectionRepository instance =
      StremioCollectionRepository._();

  static const _prefsKey = 'stremio_collections_v1';

  List<StremioCollection> _collections = [];
  bool _loaded = false;

  List<StremioCollection> get collections => List.unmodifiable(_collections);

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _collections = list
            .whereType<Map>()
            .map((e) =>
                StremioCollection.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        _collections = [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_collections.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(StremioCollection c) async {
    await init();
    _collections = [
      ..._collections.where((x) => x.id != c.id),
      c,
    ];
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await init();
    _collections.removeWhere((c) => c.id == id);
    await _persist();
    notifyListeners();
  }

  /// Importa JSON de colección (una o lista), estilo Nuvio.
  Future<int> importJson(String raw) async {
    await init();
    final decoded = jsonDecode(raw);
    final list = <Map<String, dynamic>>[];
    if (decoded is List) {
      for (final e in decoded) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    } else if (decoded is Map) {
      // Puede ser { collections: [...] } o una sola colección
      if (decoded['collections'] is List) {
        for (final e in decoded['collections'] as List) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      } else {
        list.add(Map<String, dynamic>.from(decoded));
      }
    }
    var n = 0;
    for (final m in list) {
      try {
        final c = StremioCollection.fromJson(m);
        if (c.id.isEmpty || c.title.isEmpty) continue;
        await add(c);
        n++;
      } catch (e) {
        debugPrint('[StremioCollection] import: $e');
      }
    }
    return n;
  }

  /// Crea colección desde un CatalogTarget ya conocido (un catálogo de addon).
  Future<StremioCollection> createFromCatalog(CatalogTarget target) async {
    final id =
        'col_${target.manifestUrl.hashCode.abs()}_${target.type}_${target.catalogId}';
    final c = StremioCollection(
      id: id,
      title: target.catalogName ?? target.catalogId,
      sources: [
        StremioCollectionSource(
          provider: 'addon',
          addonId: target.addonName,
          manifestUrl: target.manifestUrl,
          type: target.type,
          catalogId: target.catalogId,
        ),
      ],
    );
    await add(c);
    return c;
  }

  /// Resuelve ítems de una colección (consulta catálogos de addons).
  Future<List<ContentItem>> resolveItems(
    StremioCollection collection, {
    int maxPerSource = 40,
  }) async {
    await StremioAddonRepository.instance.init();
    final items = <ContentItem>[];
    final seen = <String>{};

    for (final src in collection.sources) {
      if (src.provider != 'addon') continue;
      final manifestUrl = src.manifestUrl;
      if (manifestUrl == null ||
          src.type == null ||
          src.catalogId == null) {
        continue;
      }
      try {
        final page = await StremioAddonRepository.instance.fetchPage(
          CatalogTarget(
            manifestUrl: manifestUrl,
            type: src.type!,
            catalogId: src.catalogId!,
            catalogName: collection.title,
            addonName: src.addonId,
          ),
          genre: src.genre,
          maxItems: maxPerSource,
        );
        for (final m in page.items) {
          final key = '${m.type}:${m.id}';
          if (!seen.add(key)) continue;
          items.add(_metaToContent(m));
        }
      } catch (e) {
        debugPrint('[StremioCollection] resolve ${collection.id}: $e');
      }
    }
    return items;
  }

  /// Secciones de home a partir de colecciones guardadas.
  Future<List<StremioHomeSection>> buildHomeSectionsFromCollections({
    int maxPerSection = 20,
  }) async {
    await init();
    final sections = <StremioHomeSection>[];
    for (final c in _collections) {
      if (!c.showOnHome) continue;
      final items = await resolveItems(c, maxPerSource: maxPerSection);
      if (items.isEmpty) continue;
      sections.add(StremioHomeSection(
        target: CatalogTarget(
          manifestUrl: c.sources.isNotEmpty
              ? (c.sources.first.manifestUrl ?? '')
              : '',
          type: c.sources.isNotEmpty
              ? (c.sources.first.type ?? 'movie')
              : 'movie',
          catalogId: c.id,
          catalogName: c.title,
          addonName: 'Colección',
        ),
        title: c.title,
        subtitle: 'Colección',
        items: items,
      ));
    }
    return sections;
  }

  ContentItem _metaToContent(StremioMeta m) {
    ContentType type = ContentType.movie;
    final t = m.type.toLowerCase();
    if (t == 'series' || t == 'tv' || t == 'show' || t == 'anime') {
      type = ContentType.series;
    }
    return ContentItem(
      id: m.id,
      title: m.name,
      type: type,
      poster: m.poster,
      backdrop: m.banner,
      overview: m.description,
      year: m.releaseInfo,
      rating: double.tryParse(m.imdbRating ?? ''),
      genres: m.genres,
      addonId: 'stremio_collection',
      extra: {
        'stremioId': m.id,
        'stremioType': m.type,
        'source': 'stremio_collection',
      },
    );
  }
}

class StremioCollection {
  final String id;
  final String title;
  final List<StremioCollectionSource> sources;
  final bool showOnHome;

  const StremioCollection({
    required this.id,
    required this.title,
    this.sources = const [],
    this.showOnHome = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sources': sources.map((e) => e.toJson()).toList(),
        'showOnHome': showOnHome,
      };

  factory StremioCollection.fromJson(Map<String, dynamic> j) {
    final sourcesRaw = j['sources'] as List? ?? [];
    return StremioCollection(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? j['name'] ?? '').toString(),
      sources: sourcesRaw
          .whereType<Map>()
          .map((e) =>
              StremioCollectionSource.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      showOnHome: j['showOnHome'] != false,
    );
  }
}

class StremioCollectionSource {
  final String provider; // addon | tmdb | trakt
  final String? addonId;
  final String? manifestUrl;
  final String? type;
  final String? catalogId;
  final String? genre;

  const StremioCollectionSource({
    this.provider = 'addon',
    this.addonId,
    this.manifestUrl,
    this.type,
    this.catalogId,
    this.genre,
  });

  Map<String, dynamic> toJson() => {
        'provider': provider,
        if (addonId != null) 'addonId': addonId,
        if (manifestUrl != null) 'manifestUrl': manifestUrl,
        if (type != null) 'type': type,
        if (catalogId != null) 'catalogId': catalogId,
        if (genre != null) 'genre': genre,
      };

  factory StremioCollectionSource.fromJson(Map<String, dynamic> j) {
    // Nuvio a veces usa addonId como id del addon; resolvemos manifestUrl
    // buscando en StremioAddonRepository si hace falta.
    var manifestUrl = j['manifestUrl']?.toString();
    final addonId = j['addonId']?.toString() ?? j['addon_id']?.toString();
    if ((manifestUrl == null || manifestUrl.isEmpty) && addonId != null) {
      final found = StremioAddonRepository.instance.addons.where((a) {
        return a.manifest?.id == addonId || a.manifestUrl.contains(addonId);
      });
      if (found.isNotEmpty) {
        manifestUrl = found.first.manifestUrl;
      }
    }
    return StremioCollectionSource(
      provider: (j['provider'] ?? 'addon').toString(),
      addonId: addonId,
      manifestUrl: manifestUrl,
      type: j['type']?.toString(),
      catalogId: j['catalogId']?.toString() ?? j['catalog_id']?.toString(),
      genre: j['genre']?.toString(),
    );
  }
}
