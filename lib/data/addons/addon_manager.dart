import 'package:flutter/foundation.dart';
import 'models/addon.dart';
import 'services/addon_loader.dart';
import 'services/source_service.dart';
import 'services/catalog_service.dart';
import 'services/storage_service.dart';
import 'models/content.dart';
import 'stremio/stremio_addon_repository.dart';
import 'stremio/stremio_collection_repository.dart';
import 'stremio/stream_badge_repository.dart';
import 'stremio/stremio_models.dart';

/// Gestor central de addons (fuentes + catálogos) estilo App2.
/// Fuentes y catálogos por Git/URL (JS) — sin cambios.
/// Además: catálogos + streams + colecciones Stremio/Nuvio (paralelo).
class AddonManager extends ChangeNotifier {
  AddonManager._();
  static final AddonManager instance = AddonManager._();

  final StorageService _storage = StorageService();
  final AddonLoader _loader = AddonLoader();
  final SourceService sources = SourceService();
  final CatalogService catalogs = CatalogService();

  List<AddonManifest> addons = [];
  List<SourcePackage> packages = [];
  bool loading = false;
  String? error;
  bool _initialized = false;

  List<AddonManifest> get sourceAddons =>
      addons
          .where((a) => a.enabled && a.isSource && !a.isChannelsOnly)
          .toList();

  /// Fuentes instaladas incluyendo solo-canales (para UI de addons, no para ServidoresModal).
  List<AddonManifest> get sourceAddonsIncludingChannels =>
      addons.where((a) => a.enabled && a.isSource).toList();

  List<AddonManifest> get catalogAddons =>
      addons.where((a) => a.enabled && a.isCatalog).toList();

  List<AddonManifest> get allSources =>
      addons.where((a) => a.isSource).toList();

  List<AddonManifest> get allCatalogs =>
      addons.where((a) => a.isCatalog).toList();

  Future<void> init() async {
    if (_initialized) return;
    loading = true;
    notifyListeners();
    try {
      final stored = await _storage.loadAddons();
      addons = stored;
      packages = await _storage.loadPackages();
      // Catálogos / streams / colecciones Stremio/Nuvio — no mezcla con addons JS
      await StremioAddonRepository.instance.init();
      await StremioCollectionRepository.instance.init();
      await StreamBadgeRepository.instance.init();
      _initialized = true;
      error = null;
    } catch (e, st) {
      error = e.toString();
      debugPrint('[AddonManager] init: $e\n$st');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Stremio / Nuvio catalog addons (paralelo al sistema JS) ───────────

  List<ManagedStremioAddon> get stremioCatalogAddons =>
      StremioAddonRepository.instance.addons;

  Future<ManagedStremioAddon> addStremioCatalog(String manifestUrl) async {
    final m = await StremioAddonRepository.instance.addOrRefresh(manifestUrl);
    notifyListeners();
    return m;
  }

  Future<void> removeStremioCatalog(String manifestUrl) async {
    await StremioAddonRepository.instance.remove(manifestUrl);
    notifyListeners();
  }

  Future<void> setStremioCatalogEnabled(String manifestUrl, bool enabled) async {
    await StremioAddonRepository.instance.setEnabled(manifestUrl, enabled);
    notifyListeners();
  }

  List<StremioCollection> get stremioCollections =>
      StremioCollectionRepository.instance.collections;

  Future<int> importStremioCollectionsJson(String raw) async {
    final n = await StremioCollectionRepository.instance.importJson(raw);
    notifyListeners();
    return n;
  }

  Future<void> removeStremioCollection(String id) async {
    await StremioCollectionRepository.instance.remove(id);
    notifyListeners();
  }

  Future<StremioCollection> createCollectionFromCatalog(
      CatalogTarget target) async {
    final c =
        await StremioCollectionRepository.instance.createFromCatalog(target);
    notifyListeners();
    return c;
  }

  Future<void> reload() async {
    _initialized = false;
    await init();
  }

  Future<void> _persist() async {
    await _storage.saveAddons(addons);
    notifyListeners();
  }

  AddonManifest _upsert(AddonManifest manifest) {
    addons = [
      ...addons.where((a) => a.id != manifest.id),
      manifest,
    ];
    return manifest;
  }

  /// Instalar addon desde URL de GitHub (user/repo o raw).
  Future<AddonManifest> installFromGitHub({
    required String repoOrUrl,
    required AddonType type,
  }) async {
    await init();
    var manifest = await _loader.fromGitHub(
      repoOrUrl,
      expectedType: type,
    );
    final repoClean = repoOrUrl
        .trim()
        .replaceAll(RegExp(r'^https?://github.com/'), '')
        .split('@')
        .first
        .split('#')
        .first;
    // Forzar tipo pedido (Comunidad Fuente/Catálogo) y activo
    manifest = manifest.copyWith(
      types: [type],
      enabled: true,
      githubCanonical: (manifest.githubCanonical == null ||
              manifest.githubCanonical!.isEmpty)
          ? repoClean
          : manifest.githubCanonical,
    );
    // Código JS se resuelve al scrapear (rawCode / sourceUrl / githubCanonical)
    _upsert(manifest);
    await _persist();
    // Asegurar lista en memoria fresca
    _initialized = true;
    notifyListeners();
    return manifest;
  }

  /// Instalar desde URL directa de manifest.json o index.js
  Future<AddonManifest> installFromUrl(String url) async {
    await init();
    final manifest = await _loader.fromUrl(url);
    _upsert(manifest);
    await _persist();
    return manifest;
  }

  /// Instalar desde item de Comunidad (misma lógica que manual + fallbacks).
  Future<AddonManifest> installCommunity({
    required String repo,
    required AddonType type,
  }) async {
    await init();
    final cleaned = repo.trim().replaceAll(RegExp(r'^https?://github.com/'), '');
    Object? lastErr;

    // 1) Misma ruta que instalación manual
    try {
      return await installFromGitHub(repoOrUrl: cleaned, type: type);
    } catch (e) {
      lastErr = e;
      debugPrint('[AddonManager] community fromGitHub fail $cleaned: $e');
    }

    // 2) Fallbacks raw.githubusercontent.com
    final branches = ['main', 'master'];
    final files = type == AddonType.catalog
        ? ['manifest.json', 'addon.json', 'index.js', 'catalog.json']
        : ['manifest.json', 'addon.json', 'index.js', 'main.js'];
    for (final br in branches) {
      for (final f in files) {
        final url = 'https://raw.githubusercontent.com/$cleaned/$br/$f';
        try {
          var m = await _loader.fromUrl(url);
          m = m.copyWith(types: [type], enabled: true);
          // Si solo bajó JSON sin JS, intentar index.js
          final codeEmpty = m.rawCode == null ||
              m.rawCode!.trim().isEmpty ||
              m.rawCode!.trimLeft().startsWith('{');
          if (codeEmpty && type == AddonType.source) {
            for (final js in ['index.js', 'main.js', 'addon.js']) {
              final jsUrl = 'https://raw.githubusercontent.com/$cleaned/$br/$js';
              try {
                final m2 = await _loader.fromUrl(jsUrl);
                if (m2.rawCode != null &&
                    m2.rawCode!.contains('getStreams')) {
                  m = m.copyWith(
                    rawCode: m2.rawCode,
                    sourceUrl: jsUrl,
                    types: [type],
                    enabled: true,
                  );
                  break;
                }
              } catch (_) {}
            }
          }
          _upsert(m);
          await _persist();
          notifyListeners();
          return m;
        } catch (e) {
          lastErr = e;
        }
      }
    }
    throw Exception(lastErr?.toString() ?? 'No se pudo instalar $cleaned');
  }


  Future<void> uninstall(String id) async {
    await init();
    addons = addons.where((a) => a.id != id).toList();
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await init();
    final i = addons.indexWhere((a) => a.id == id);
    if (i < 0) return;
    addons[i] = addons[i].copyWith(enabled: enabled);
    addons = [...addons];
    await _persist();
  }

  Future<bool> updateAddon(String id) async {
    await init();
    final i = addons.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    final a = addons[i];
    try {
      AddonManifest? fresh;
      if (a.githubCanonical != null && a.githubCanonical!.isNotEmpty) {
        fresh = await _loader.fromGitHub(
          a.githubCanonical!,
          expectedType: a.types.isNotEmpty ? a.types.first : AddonType.source,
        );
      } else if (a.sourceUrl != null && a.sourceUrl!.isNotEmpty) {
        fresh = await _loader.fromUrl(a.sourceUrl!);
      }
      if (fresh == null) return false;
      addons[i] = fresh.copyWith(
        enabled: a.enabled,
        userConfig: a.userConfig,
      );
      addons = [...addons];
      await _persist();
      return true;
    } catch (e) {
      debugPrint('[AddonManager] update $id: $e');
      return false;
    }
  }

  Future<void> updateAll() async {
    await init();
    final current = List<AddonManifest>.from(addons);
    for (final a in current) {
      await updateAddon(a.id);
    }
  }

  /// Obtener streams de todas las fuentes instaladas (como App2).
  Future<List<StreamItem>> getStreams(ContentItem content) async {
    await init();
    return sources.getStreams(
      content: content,
      sourceAddons: sourceAddons,
    );
  }

  /// Primer stream disponible (modo auto).
  Future<StreamItem?> getFirstStream(ContentItem content) async {
    await init();
    return sources.getFirstStream(
      content: content,
      sourceAddons: sourceAddons,
    );
  }

  /// Streams de una sola fuente (por id de addon).
  Future<List<StreamItem>> getStreamsForAddon(
    String addonId,
    ContentItem content,
  ) async {
    await init();
    AddonManifest? addon;
    for (final a in sourceAddons) {
      if (a.id == addonId) {
        addon = a;
        break;
      }
    }
    if (addon == null) return [];
    return sources.getStreamsForAddon(addon: addon, content: content);
  }

  // ── Paquetes Nuvio (manifest con "scrapers") ─────────────────

  Future<void> _persistPackages() async {
    await _storage.savePackages(packages);
    notifyListeners();
  }

  /// Carga un manifest Nuvio por URL y lo guarda en la lista de paquetes.
  Future<SourcePackage> addNuvioPackage(String manifestUrl) async {
    await init();
    final url = manifestUrl.trim();
    if (url.isEmpty) throw Exception('URL vacía');
    final pkg = await _loader.fetchPackage(url);
    packages = [
      ...packages.where((p) => p.manifestUrl != pkg.manifestUrl),
      pkg,
    ];
    await _persistPackages();
    return pkg;
  }

  Future<void> removeNuvioPackage(String manifestUrl) async {
    await init();
    packages = packages.where((p) => p.manifestUrl != manifestUrl).toList();
    await _persistPackages();
  }

  Future<void> refreshNuvioPackage(String manifestUrl) async {
    await init();
    final pkg = await _loader.fetchPackage(manifestUrl);
    packages = [
      for (final p in packages)
        if (p.manifestUrl == manifestUrl) pkg else p,
    ];
    // Si no estaba, añadir
    if (!packages.any((p) => p.manifestUrl == manifestUrl)) {
      packages = [...packages, pkg];
    }
    await _persistPackages();
  }

  /// Instala un scraper individual del paquete como fuente addon.
  Future<AddonManifest> installNuvioScraper(
    SourcePackage package,
    PackageScraper scraper,
  ) async {
    await init();
    final manifest = await _loader.installScraperFromPackage(
      package: package,
      scraper: scraper,
    );
    // Forzar fuente activa
    final forced = manifest.copyWith(
      types: [AddonType.source],
      enabled: true,
    );
    _upsert(forced);
    await _persist();
    notifyListeners();
    return forced;
  }

  /// Instala todos los scrapers del paquete.
  Future<({int ok, int fail})> installAllNuvioScrapers(
    SourcePackage package,
  ) async {
    await init();
    var ok = 0;
    var fail = 0;
    for (final scraper in package.scrapers) {
      try {
        await installNuvioScraper(package, scraper);
        ok++;
      } catch (e) {
        debugPrint('[Nuvio] install ${scraper.id}: $e');
        fail++;
      }
    }
    return (ok: ok, fail: fail);
  }

  bool isNuvioScraperInstalled(String scraperId) {
    return addons.any((a) => a.id == scraperId && a.isSource);
  }

}
