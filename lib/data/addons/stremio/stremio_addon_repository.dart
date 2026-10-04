import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/content.dart';
import 'stremio_catalog_client.dart';
import 'stremio_models.dart';
import 'stremio_url_builder.dart';

/// Repositorio de addons Stremio/Nuvio de **catálogo**.
/// No toca el sistema de fuentes JS/Git (AddonManager).
class StremioAddonRepository extends ChangeNotifier {
  StremioAddonRepository._();
  static final StremioAddonRepository instance = StremioAddonRepository._();

  static const _prefsKey = 'stremio_catalog_addons_v1';

  final _client = StremioCatalogClient();
  List<ManagedStremioAddon> _addons = [];
  bool _loaded = false;

  List<ManagedStremioAddon> get addons => List.unmodifiable(_addons);
  List<ManagedStremioAddon> get enabledAddons =>
      _addons.where((a) => a.isActive).toList();

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _addons = list
            .whereType<Map>()
            .map((e) =>
                ManagedStremioAddon.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        _addons = [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_addons.map((e) => e.toJson()).toList()),
    );
  }

  /// Instala o refresca un addon desde URL de manifest.json
  Future<ManagedStremioAddon> addOrRefresh(String manifestUrl) async {
    await init();
    final url = normalizeManifestUrl(manifestUrl);
    try {
      final manifest = await _client.fetchManifest(url);
      final managed = ManagedStremioAddon(
        manifestUrl: url,
        manifest: manifest,
        enabled: true,
      );
      final idx = _addons.indexWhere((a) => a.manifestUrl == url);
      if (idx >= 0) {
        _addons[idx] = managed;
      } else {
        _addons.add(managed);
      }
      await _persist();
      notifyListeners();
      return managed;
    } catch (e) {
      final failed = ManagedStremioAddon(
        manifestUrl: url,
        enabled: true,
        errorMessage: e.toString(),
      );
      final idx = _addons.indexWhere((a) => a.manifestUrl == url);
      if (idx >= 0) {
        _addons[idx] = failed;
      } else {
        _addons.add(failed);
      }
      await _persist();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setEnabled(String manifestUrl, bool enabled) async {
    await init();
    final idx = _addons.indexWhere((a) => a.manifestUrl == manifestUrl);
    if (idx < 0) return;
    _addons[idx] = _addons[idx].copyWith(enabled: enabled);
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String manifestUrl) async {
    await init();
    _addons.removeWhere((a) => a.manifestUrl == manifestUrl);
    await _persist();
    notifyListeners();
  }

  /// Todas las definiciones de catálogo de addons activos
  List<CatalogTarget> allCatalogTargets() {
    final out = <CatalogTarget>[];
    for (final a in enabledAddons) {
      final m = a.manifest!;
      for (final c in m.catalogs) {
        out.add(CatalogTarget(
          manifestUrl: a.manifestUrl,
          type: c.type,
          catalogId: c.id,
          catalogName: c.name,
          addonName: m.name,
        ));
      }
    }
    return out;
  }

  Future<StremioCatalogPage> fetchPage(
    CatalogTarget target, {
    int? skip,
    String? search,
    String? genre,
    int? maxItems,
  }) {
    return _client.fetchCatalogPage(
      manifestUrl: target.manifestUrl,
      type: target.type,
      catalogId: target.catalogId,
      skip: skip,
      search: search,
      genre: genre,
      maxItems: maxItems,
    );
  }

  /// Secciones para el Home: cada catálogo → fila de ítems.
  Future<List<StremioHomeSection>> buildHomeSections({
    int maxPerSection = 20,
    int maxSections = 30,
  }) async {
    await init();
    final targets = allCatalogTargets().take(maxSections).toList();
    final sections = <StremioHomeSection>[];

    await Future.wait(targets.map((t) async {
      try {
        final page = await fetchPage(t, maxItems: maxPerSection);
        if (page.items.isEmpty) return;
        sections.add(StremioHomeSection(
          target: t,
          title: t.catalogName ?? t.catalogId,
          subtitle: t.addonName,
          items: page.items.map(_toContentItem).toList(),
        ));
      } catch (e) {
        debugPrint('[Stremio] home ${t.key}: $e');
      }
    }));

    // Orden estable por addon + nombre
    sections.sort((a, b) {
      final aa = a.subtitle ?? '';
      final bb = b.subtitle ?? '';
      final c = aa.compareTo(bb);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });
    return sections;
  }

  ContentItem _toContentItem(StremioMeta m) {
    ContentType type = ContentType.movie;
    final t = m.type.toLowerCase();
    if (t == 'series' || t == 'tv' || t == 'show' || t == 'anime') {
      type = ContentType.series;
    } else if (t == 'channel' || t == 'tv_channel') {
      type = ContentType.live;
    }

    // Extraer tmdb id si viene en id tipo "tmdb:123" o "tt..."
    int? tmdbId;
    final id = m.id;
    if (id.contains(':')) {
      final parts = id.split(':');
      tmdbId = int.tryParse(parts.last);
    } else {
      tmdbId = int.tryParse(id);
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
      addonId: 'stremio',
      extra: {
        'stremioId': m.id,
        'stremioType': m.type,
        if (m.logo != null) 'logo': m.logo,
        if (tmdbId != null) 'tmdbId': tmdbId,
        'source': 'stremio_catalog',
      },
    );
  }
}

class StremioHomeSection {
  final CatalogTarget target;
  final String title;
  final String? subtitle;
  final List<ContentItem> items;

  const StremioHomeSection({
    required this.target,
    required this.title,
    this.subtitle,
    required this.items,
  });
}
