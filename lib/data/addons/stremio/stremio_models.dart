/// Modelos del protocolo Stremio / Nuvio (catálogos).
/// Independientes del sistema de addons JS/Git de la app.

class StremioManifest {
  final String id;
  final String name;
  final String description;
  final String version;
  final String? logoUrl;
  final List<StremioResource> resources;
  final List<String> types;
  final List<String> idPrefixes;
  final List<StremioCatalog> catalogs;
  final StremioBehaviorHints behaviorHints;
  /// URL del manifest.json (transport)
  final String transportUrl;

  const StremioManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    this.logoUrl,
    required this.resources,
    required this.types,
    this.idPrefixes = const [],
    this.catalogs = const [],
    this.behaviorHints = const StremioBehaviorHints(),
    required this.transportUrl,
  });

  bool get hasCatalog =>
      resources.any((r) => r.name == 'catalog') || catalogs.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        if (logoUrl != null) 'logoUrl': logoUrl,
        'resources': resources.map((e) => e.toJson()).toList(),
        'types': types,
        'idPrefixes': idPrefixes,
        'catalogs': catalogs.map((e) => e.toJson()).toList(),
        'behaviorHints': behaviorHints.toJson(),
        'transportUrl': transportUrl,
      };

  factory StremioManifest.fromJson(Map<String, dynamic> j) => StremioManifest(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        version: (j['version'] ?? '0').toString(),
        logoUrl: j['logoUrl']?.toString() ?? j['logo']?.toString(),
        resources: (j['resources'] as List? ?? [])
            .map((e) => e is Map
                ? StremioResource.fromJson(Map<String, dynamic>.from(e))
                : StremioResource(name: e.toString(), types: const []))
            .toList(),
        types: (j['types'] as List? ?? []).map((e) => e.toString()).toList(),
        idPrefixes:
            (j['idPrefixes'] as List? ?? []).map((e) => e.toString()).toList(),
        catalogs: (j['catalogs'] as List? ?? [])
            .whereType<Map>()
            .map((e) => StremioCatalog.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        behaviorHints: j['behaviorHints'] is Map
            ? StremioBehaviorHints.fromJson(
                Map<String, dynamic>.from(j['behaviorHints'] as Map))
            : const StremioBehaviorHints(),
        transportUrl: (j['transportUrl'] ?? '').toString(),
      );
}

class StremioResource {
  final String name;
  final List<String> types;
  final List<String> idPrefixes;

  const StremioResource({
    required this.name,
    required this.types,
    this.idPrefixes = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'types': types,
        'idPrefixes': idPrefixes,
      };

  factory StremioResource.fromJson(Map<String, dynamic> j) => StremioResource(
        name: (j['name'] ?? '').toString(),
        types: (j['types'] as List? ?? []).map((e) => e.toString()).toList(),
        idPrefixes:
            (j['idPrefixes'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

class StremioCatalog {
  final String type;
  final String id;
  final String name;
  final List<StremioExtra> extra;

  const StremioCatalog({
    required this.type,
    required this.id,
    required this.name,
    this.extra = const [],
  });

  bool get supportsSkip =>
      extra.any((e) => e.name.toLowerCase() == 'skip');
  bool get supportsSearch =>
      extra.any((e) => e.name.toLowerCase() == 'search');
  bool get supportsGenre =>
      extra.any((e) => e.name.toLowerCase() == 'genre');

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'extra': extra.map((e) => e.toJson()).toList(),
      };

  factory StremioCatalog.fromJson(Map<String, dynamic> j) => StremioCatalog(
        type: (j['type'] ?? 'movie').toString(),
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? j['id'] ?? '').toString(),
        extra: (j['extra'] as List? ?? [])
            .whereType<Map>()
            .map((e) => StremioExtra.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class StremioExtra {
  final String name;
  final bool isRequired;
  final List<String> options;
  final int? optionsLimit;

  const StremioExtra({
    required this.name,
    this.isRequired = false,
    this.options = const [],
    this.optionsLimit,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'isRequired': isRequired,
        'options': options,
        if (optionsLimit != null) 'optionsLimit': optionsLimit,
      };

  factory StremioExtra.fromJson(Map<String, dynamic> j) => StremioExtra(
        name: (j['name'] ?? '').toString(),
        isRequired: j['isRequired'] == true,
        options:
            (j['options'] as List? ?? []).map((e) => e.toString()).toList(),
        optionsLimit: (j['optionsLimit'] as num?)?.toInt(),
      );
}

class StremioBehaviorHints {
  final bool configurable;
  final bool configurationRequired;
  final bool adult;
  final bool p2p;

  const StremioBehaviorHints({
    this.configurable = false,
    this.configurationRequired = false,
    this.adult = false,
    this.p2p = false,
  });

  Map<String, dynamic> toJson() => {
        'configurable': configurable,
        'configurationRequired': configurationRequired,
        'adult': adult,
        'p2p': p2p,
      };

  factory StremioBehaviorHints.fromJson(Map<String, dynamic> j) =>
      StremioBehaviorHints(
        configurable: j['configurable'] == true,
        configurationRequired: j['configurationRequired'] == true,
        adult: j['adult'] == true,
        p2p: j['p2p'] == true,
      );
}

/// Addon Stremio instalado / gestionado (solo catálogo protocolo).
class ManagedStremioAddon {
  final String manifestUrl;
  final StremioManifest? manifest;
  final bool enabled;
  final String? errorMessage;

  const ManagedStremioAddon({
    required this.manifestUrl,
    this.manifest,
    this.enabled = true,
    this.errorMessage,
  });

  bool get isActive => enabled && manifest != null;

  String get displayName =>
      manifest?.name ??
      manifestUrl.split('/').where((s) => s.isNotEmpty).last;

  Map<String, dynamic> toJson() => {
        'manifestUrl': manifestUrl,
        if (manifest != null) 'manifest': manifest!.toJson(),
        'enabled': enabled,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  factory ManagedStremioAddon.fromJson(Map<String, dynamic> j) =>
      ManagedStremioAddon(
        manifestUrl: (j['manifestUrl'] ?? '').toString(),
        manifest: j['manifest'] is Map
            ? StremioManifest.fromJson(
                Map<String, dynamic>.from(j['manifest'] as Map))
            : null,
        enabled: j['enabled'] != false,
        errorMessage: j['errorMessage']?.toString(),
      );

  ManagedStremioAddon copyWith({
    StremioManifest? manifest,
    bool? enabled,
    String? errorMessage,
    bool clearError = false,
  }) =>
      ManagedStremioAddon(
        manifestUrl: manifestUrl,
        manifest: manifest ?? this.manifest,
        enabled: enabled ?? this.enabled,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Identifica un catálogo concreto (página / sección).
class CatalogTarget {
  final String manifestUrl;
  final String type;
  final String catalogId;
  final String? catalogName;
  final String? addonName;

  const CatalogTarget({
    required this.manifestUrl,
    required this.type,
    required this.catalogId,
    this.catalogName,
    this.addonName,
  });

  String get key => '$manifestUrl|$type|$catalogId';

  Map<String, dynamic> toJson() => {
        'manifestUrl': manifestUrl,
        'type': type,
        'catalogId': catalogId,
        if (catalogName != null) 'catalogName': catalogName,
        if (addonName != null) 'addonName': addonName,
      };

  factory CatalogTarget.fromJson(Map<String, dynamic> j) => CatalogTarget(
        manifestUrl: (j['manifestUrl'] ?? '').toString(),
        type: (j['type'] ?? 'movie').toString(),
        catalogId: (j['catalogId'] ?? '').toString(),
        catalogName: j['catalogName']?.toString(),
        addonName: j['addonName']?.toString(),
      );
}

/// Meta preview (elemento de /catalog/... metas[])
class StremioMeta {
  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? banner;
  final String? logo;
  final String? description;
  final String? releaseInfo;
  final String? imdbRating;
  final List<String> genres;

  const StremioMeta({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.banner,
    this.logo,
    this.description,
    this.releaseInfo,
    this.imdbRating,
    this.genres = const [],
  });

  factory StremioMeta.fromJson(Map<String, dynamic> j) => StremioMeta(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? 'movie').toString(),
        name: (j['name'] ?? j['title'] ?? '').toString(),
        poster: j['poster']?.toString(),
        banner: (j['banner'] ?? j['background'] ?? j['landscapePoster'])
            ?.toString(),
        logo: j['logo']?.toString(),
        description: j['description']?.toString(),
        releaseInfo: j['releaseInfo']?.toString() ?? j['released']?.toString(),
        imdbRating: j['imdbRating']?.toString(),
        genres: (j['genres'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

class StremioCatalogPage {
  final List<StremioMeta> items;
  final int rawCount;
  /// Siguiente skip si el catálogo soporta paginación; null = no más.
  final int? nextSkip;

  const StremioCatalogPage({
    required this.items,
    required this.rawCount,
    this.nextSkip,
  });
}
