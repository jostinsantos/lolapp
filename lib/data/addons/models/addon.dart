import 'package:equatable/equatable.dart';

enum AddonType { catalog, source, function }

extension AddonTypeX on AddonType {
  String get label {
    switch (this) {
      case AddonType.catalog:
        return 'Catálogo';
      case AddonType.source:
        return 'Fuente';
      case AddonType.function:
        return 'Función';
    }
  }

  String get icon {
    switch (this) {
      case AddonType.catalog:
        return '📚';
      case AddonType.source:
        return '🎬';
      case AddonType.function:
        return '⚙️';
    }
  }
}


enum FunctionPlacement {
  player,
  contentPage,
  home,
  search,
  servers,
  settings,
}

extension FunctionPlacementX on FunctionPlacement {
  String get label {
    switch (this) {
      case FunctionPlacement.player:
        return 'Reproductor';
      case FunctionPlacement.contentPage:
        return 'Página de contenido';
      case FunctionPlacement.home:
        return 'Inicio';
      case FunctionPlacement.search:
        return 'Buscador';
      case FunctionPlacement.servers:
        return 'Servidores';
      case FunctionPlacement.settings:
        return 'Ajustes';
    }
  }

  String get description {
    switch (this) {
      case FunctionPlacement.player:
        return 'Se ejecuta dentro del player';
      case FunctionPlacement.contentPage:
        return 'Ficha de película/serie';
      case FunctionPlacement.home:
        return 'Filas o widgets en inicio';
      case FunctionPlacement.search:
        return 'Búsqueda o filtros';
      case FunctionPlacement.servers:
        return 'Lista de streams';
      case FunctionPlacement.settings:
        return 'Solo configuración';
    }
  }
}

/// Tipo concreto de función: define qué hace y dónde encaja por defecto.
enum FunctionKind {
  subtitles,
  rating,
  posterTags,
  top10,
  mainSlider,
  generic,
}

extension FunctionKindX on FunctionKind {
  String get label {
    switch (this) {
      case FunctionKind.subtitles:
        return 'Subtítulos';
      case FunctionKind.rating:
        return 'Rating';
      case FunctionKind.posterTags:
        return 'Etiquetas en póster';
      case FunctionKind.top10:
        return 'Top 10';
      case FunctionKind.mainSlider:
        return 'Slider principal';
      case FunctionKind.generic:
        return 'Genérica';
    }
  }

  String get description {
    switch (this) {
      case FunctionKind.subtitles:
        return 'Subtítulos en el reproductor';
      case FunctionKind.rating:
        return 'Rating / puntuación en la ficha de contenido';
      case FunctionKind.posterTags:
        return 'Etiquetas sobre pósters en el inicio';
      case FunctionKind.top10:
        return 'Fila Top 10 en el inicio';
      case FunctionKind.mainSlider:
        return 'Slider / hero principal en el inicio';
      case FunctionKind.generic:
        return 'Función genérica (placement libre)';
    }
  }

  String get icon {
    switch (this) {
      case FunctionKind.subtitles:
        return '💬';
      case FunctionKind.rating:
        return '⭐';
      case FunctionKind.posterTags:
        return '🏷️';
      case FunctionKind.top10:
        return '🔟';
      case FunctionKind.mainSlider:
        return '🎠';
      case FunctionKind.generic:
        return '⚙️';
    }
  }

  /// Placement sugerido según el tipo de función.
  FunctionPlacement get defaultPlacement {
    switch (this) {
      case FunctionKind.subtitles:
        return FunctionPlacement.player;
      case FunctionKind.rating:
        return FunctionPlacement.contentPage;
      case FunctionKind.posterTags:
      case FunctionKind.top10:
      case FunctionKind.mainSlider:
        return FunctionPlacement.home;
      case FunctionKind.generic:
        return FunctionPlacement.contentPage;
    }
  }
}

enum AddonOrigin { builtIn, url, pasted, file, package, github }

/// Campo de configuración editable por el usuario (desde config.schema.json).
class AddonConfigField extends Equatable {
  final String key;
  final String label;
  final String type; // string, password, bool, number, select
  final String? defaultValue;
  final String? description;
  final List<String>? options;

  const AddonConfigField({
    required this.key,
    required this.label,
    this.type = 'string',
    this.defaultValue,
    this.description,
    this.options,
  });

  factory AddonConfigField.fromJson(Map<String, dynamic> j) {
    List<String>? opts;
    final rawOpts = j['options'];
    if (rawOpts is List) {
      opts = rawOpts.map((e) {
        if (e is Map) {
          return (e['value'] ?? e['label'] ?? e['id'] ?? '').toString();
        }
        return e.toString();
      }).where((s) => s.isNotEmpty).toList();
    }
    return AddonConfigField(
      key: j['key']?.toString() ?? '',
      label: j['label']?.toString() ?? j['key']?.toString() ?? '',
      type: j['type']?.toString() ?? 'string',
      defaultValue: j['default']?.toString() ?? j['defaultValue']?.toString(),
      description: j['description']?.toString() ?? j['hint']?.toString(),
      options: opts,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        if (defaultValue != null) 'default': defaultValue,
        if (description != null) 'description': description,
        if (options != null) 'options': options,
      };

  @override
  List<Object?> get props => [key];
}

class AddonManifest extends Equatable {
  final String id;
  final String name;
  final String version;
  final String description;
  final List<AddonType> types;
  final String? logo;
  final String? author;
  final List<String> resources;
  final List<String> exports;
  final String? rawCode;
  final String? sourceUrl;
  final String? manifestUrl;
  final AddonOrigin origin;
  final bool enabled;
  final Map<String, dynamic> extra;
  final DateTime installedAt;
  final String? packageUrl;
  final String? githubCanonical;
  final List<String> supportedTypes;
  final List<String> formats;
  final List<String> contentLanguage;
  /// Schema de config (si vacío → no hay botón Configurar)
  final List<AddonConfigField> configSchema;
  /// Valores guardados por el usuario
  final Map<String, String> userConfig;
  final List<FunctionPlacement> placements;
  final List<String> requiredFields;
  /// Tipo concreto de función (subtítulos, rating, top10, slider…).
  final FunctionKind functionKind;

  const AddonManifest({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.description = '',
    this.types = const [AddonType.source],
    this.logo,
    this.author,
    this.resources = const [],
    this.exports = const [],
    this.rawCode,
    this.sourceUrl,
    this.manifestUrl,
    this.origin = AddonOrigin.pasted,
    this.enabled = true,
    this.extra = const {},
    required this.installedAt,
    this.packageUrl,
    this.githubCanonical,
    this.supportedTypes = const ['movie', 'tv'],
    this.formats = const [],
    this.contentLanguage = const [],
    this.configSchema = const [],
    this.userConfig = const {},
    this.placements = const [],
    this.requiredFields = const [],
    this.functionKind = FunctionKind.generic,
  });

  bool get isCatalog => types.contains(AddonType.catalog);
  bool get isSource => types.contains(AddonType.source);
  bool get isFunction => types.contains(AddonType.function);
  bool get hasConfig => configSchema.isNotEmpty;

  // ── Comunidad / capabilities (leídos de extra + defaults) ─────────────
  /// vod | tv | both
  String get mode {
    final m = (extra['mode'] ?? '').toString().trim().toLowerCase();
    if (m == 'tv' || m == 'vod' || m == 'both') return m;
    final caps = capabilities;
    if (caps.contains('channels') &&
        !caps.any((c) => c == 'home' || c == 'search' || c == 'discover')) {
      return 'tv';
    }
    if (caps.contains('channels')) return 'both';
    return 'vod';
  }

  List<String> get capabilities {
    final raw = extra['capabilities'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  bool get hasCapabilityHome => capabilities.contains('home');
  bool get hasCapabilitySearch => capabilities.contains('search');
  bool get hasCapabilityDiscover => capabilities.contains('discover');
  bool get hasCapabilityMeta => capabilities.contains('meta');
  bool get hasCapabilityChannels => capabilities.contains('channels');
  /// Addon solo de canales en vivo (no sirve para VOD en ServidoresModal).
  /// Detecta por mode, capabilities o type del manifest (extra).
  bool get isChannelsOnly {
    final t = (extra['type'] ?? extra['addonType'] ?? extra['kind'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (t == 'channels' ||
        t == 'channel' ||
        t == 'live' ||
        t == 'tv' ||
        t == 'iptv' ||
        t == 'live-tv' ||
        t == 'livetv') {
      return true;
    }
    final typeList = extra['types'];
    if (typeList is List) {
      final lower = typeList.map((e) => e.toString().toLowerCase()).toSet();
      final channelish = lower.intersection({
        'channels',
        'channel',
        'live',
        'iptv',
        'live-tv',
        'livetv',
      });
      final vodish = lower.intersection({
        'movie',
        'series',
        'tv',
        'vod',
        'stream',
        'streams',
        'anime',
      });
      // types solo canales (sin VOD)
      if (channelish.isNotEmpty && vodish.isEmpty) return true;
    }
    if (mode == 'tv') return true;
    final caps = capabilities;
    if (caps.contains('channels') &&
        !caps.any((c) =>
            c == 'home' ||
            c == 'search' ||
            c == 'discover' ||
            c == 'stream' ||
            c == 'streams' ||
            c == 'meta' ||
            c == 'vod')) {
      return true;
    }
    return false;
  }

  bool get hasCapabilityDownload =>
      capabilities.contains('download') || extra['download'] == true;
  bool get isTvMode => mode == 'tv' || mode == 'both' || hasCapabilityChannels;
  bool get isVodMode => mode == 'vod' || mode == 'both' || !hasCapabilityChannels;

  List<String> get tags {
    final raw = extra['tags'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  List<String> get hosts {
    final raw = extra['hosts'] ?? extra['streamHosts'];
    if (raw is! List) return const [];
    return raw.map((e) {
      if (e is Map) return (e['host'] ?? e['name'] ?? '').toString();
      return e.toString();
    }).where((s) => s.isNotEmpty).toList();
  }

  List<String> get permissions {
    final raw = extra['permissions'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  String? get homepage {
    final h = (extra['homepage'] ?? extra['homeUrl'] ?? '').toString().trim();
    return h.isEmpty ? null : h;
  }

  int get apiVersion =>
      int.tryParse('${extra['apiVersion'] ?? extra['api_version'] ?? 1}') ?? 1;

  String? get minAppVersion {
    final v =
        (extra['minAppVersion'] ?? extra['min_app_version'] ?? '').toString();
    return v.isEmpty ? null : v;
  }

  String? get color {
    final c = (extra['color'] ?? '').toString().trim();
    return c.isEmpty ? null : c;
  }

  bool get nsfw =>
      extra['nsfw'] == true ||
      (extra['ageRating']?.toString().toUpperCase() == 'R') ||
      tags.any((t) => t.toLowerCase() == 'nsfw');

  /// Etiquetas legibles de capabilities para UI / consentimiento.
  List<String> get capabilityLabels {
    const labels = {
      'home': 'Filas en Inicio',
      'search': 'Búsqueda',
      'discover': 'Catálogos (tipo y género)',
      'meta': 'Ficha de contenido',
      'browse': 'Listados paginados',
      'episodes': 'Temporadas y capítulos',
      'resolve': 'Reproducir video',
      'channels': 'Canales en vivo',
      'download': 'Descargas',
      'subtitles': 'Subtítulos',
    };
    final out = <String>[];
    for (final c in capabilities) {
      out.add(labels[c] ?? c);
    }
    if (hasCapabilityDownload && !capabilities.contains('download')) {
      out.add(labels['download']!);
    }
    return out;
  }

  String? configValue(String key) =>
      userConfig[key] ??
      configSchema
          .where((f) => f.key == key)
          .map((f) => f.defaultValue)
          .firstWhere((_) => true, orElse: () => null);

  AddonManifest copyWith({
    bool? enabled,
    Map<String, String>? userConfig,
    List<AddonConfigField>? configSchema,
    String? rawCode,
    String? sourceUrl,
    Map<String, dynamic>? extra,
    List<FunctionPlacement>? placements,
    List<String>? requiredFields,
    FunctionKind? functionKind,
    List<AddonType>? types,
    String? githubCanonical,
  }) {
    return AddonManifest(
      id: id,
      name: name,
      version: version,
      description: description,
      types: types ?? this.types,
      logo: logo,
      author: author,
      resources: resources,
      exports: exports,
      rawCode: rawCode ?? this.rawCode,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      manifestUrl: manifestUrl,
      origin: origin,
      enabled: enabled ?? this.enabled,
      extra: extra ?? this.extra,
      installedAt: installedAt,
      packageUrl: packageUrl,
      githubCanonical: githubCanonical ?? this.githubCanonical,
      supportedTypes: supportedTypes,
      formats: formats,
      contentLanguage: contentLanguage,
      configSchema: configSchema ?? this.configSchema,
      userConfig: userConfig ?? this.userConfig,
      placements: placements ?? this.placements,
      requiredFields: requiredFields ?? this.requiredFields,
      functionKind: functionKind ?? this.functionKind,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'types': types.map((t) => t.name).toList(),
        'logo': logo,
        'author': author,
        'resources': resources,
        'exports': exports,
        'rawCode': rawCode,
        'sourceUrl': sourceUrl,
        'manifestUrl': manifestUrl,
        'origin': origin.name,
        'enabled': enabled,
        'extra': extra,
        'installedAt': installedAt.toIso8601String(),
        'packageUrl': packageUrl,
        'githubCanonical': githubCanonical,
        'supportedTypes': supportedTypes,
        'formats': formats,
        'contentLanguage': contentLanguage,
        'configSchema': configSchema.map((e) => e.toJson()).toList(),
        'userConfig': userConfig,
        'placements': placements.map((p) => p.name).toList(),
        'requiredFields': requiredFields,
        'functionKind': functionKind.name,
      };

  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    final typeList = (json['types'] as List?)
            ?.map((e) => AddonType.values.firstWhere(
                  (t) => t.name == e.toString(),
                  orElse: () => AddonType.source,
                ))
            .toList() ??
        [AddonType.source];

    // config.schema puede venir como configSchema, config, o config.fields
    List<AddonConfigField> schema = [];
    final rawSchema = json['configSchema'] ??
        json['config']?['fields'] ??
        json['config_fields'];
    if (rawSchema is List) {
      schema = rawSchema
          .whereType<Map>()
          .map((e) => AddonConfigField.fromJson(Map<String, dynamic>.from(e)))
          .where((f) => f.key.isNotEmpty)
          .toList();
    }

    final uc = <String, String>{};
    final rawUc = json['userConfig'];
    if (rawUc is Map) {
      rawUc.forEach((k, v) {
        if (k != null && v != null) uc[k.toString()] = v.toString();
      });
    }

    return AddonManifest(
      id: json['id'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Sin nombre',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      types: typeList,
      logo: json['logo'] as String?,
      author: json['author'] as String?,
      resources: List<String>.from(json['resources'] ?? []),
      exports: List<String>.from(json['exports'] ?? []),
      rawCode: json['rawCode'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      manifestUrl: json['manifestUrl'] as String?,
      origin: AddonOrigin.values.firstWhere(
        (o) => o.name == json['origin'],
        orElse: () => AddonOrigin.pasted,
      ),
      enabled: json['enabled'] as bool? ?? true,
      extra: Map<String, dynamic>.from(json['extra'] ?? {}),
      installedAt: DateTime.tryParse(json['installedAt'] as String? ?? '') ??
          DateTime.now(),
      packageUrl: json['packageUrl'] as String?,
      githubCanonical: json['githubCanonical'] as String?,
      supportedTypes:
          List<String>.from(json['supportedTypes'] ?? ['movie', 'tv']),
      formats: List<String>.from(json['formats'] ?? []),
      contentLanguage: List<String>.from(json['contentLanguage'] ?? []),
      configSchema: schema,
      userConfig: uc,
      placements: (json['placements'] as List?)
              ?.map((e) => FunctionPlacement.values.firstWhere(
                    (p) => p.name == e.toString(),
                    orElse: () => FunctionPlacement.player,
                  ))
              .toList() ??
          const [],
      requiredFields: List<String>.from(json['requiredFields'] ?? []),
      functionKind: FunctionKind.values.firstWhere(
        (k) => k.name == (json['functionKind']?.toString() ?? ''),
        orElse: () {
          // Inferencia legacy por resources / id
          final res = List<String>.from(json['resources'] ?? []);
          final id = (json['id'] as String? ?? '').toLowerCase();
          if (res.any((r) => r.contains('sub')) || id.contains('sub')) {
            return FunctionKind.subtitles;
          }
          if (id.contains('rating') || id.contains('score')) {
            return FunctionKind.rating;
          }
          if (id.contains('top10') || id.contains('top-10')) {
            return FunctionKind.top10;
          }
          if (id.contains('slider') || id.contains('hero')) {
            return FunctionKind.mainSlider;
          }
          if (id.contains('tag') || id.contains('badge')) {
            return FunctionKind.posterTags;
          }
          return FunctionKind.generic;
        },
      ),
    );
  }

  @override
  List<Object?> get props => [id, version, enabled, userConfig];
}

/// Paquete estilo Nuvio (manifest con scrapers)

class PackageScraper extends Equatable {
  final String id;
  final String name;
  final String description;
  final String version;
  final String? author;
  final List<String> supportedTypes;
  final String filename;
  final bool enabled;
  final bool hasSettings;
  final List<String> formats;
  final String? logo;
  final List<String> contentLanguage;
  final Map<String, dynamic> extra;

  const PackageScraper({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '1.0.0',
    this.author,
    this.supportedTypes = const ['movie', 'tv'],
    required this.filename,
    this.enabled = true,
    this.hasSettings = false,
    this.formats = const [],
    this.logo,
    this.contentLanguage = const [],
    this.extra = const {},
  });

  factory PackageScraper.fromJson(Map<String, dynamic> json) => PackageScraper(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        version: json['version']?.toString() ?? '1.0.0',
        author: json['author']?.toString(),
        supportedTypes:
            List<String>.from(json['supportedTypes'] ?? ['movie', 'tv']),
        filename:
            json['filename']?.toString() ?? json['file']?.toString() ?? '',
        enabled: json['enabled'] as bool? ?? true,
        hasSettings: json['hasSettings'] as bool? ?? false,
        formats: List<String>.from(json['formats'] ?? []),
        logo: json['logo']?.toString(),
        contentLanguage: List<String>.from(json['contentLanguage'] ?? []),
        extra: Map<String, dynamic>.from(json['extra'] ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        'author': author,
        'supportedTypes': supportedTypes,
        'filename': filename,
        'enabled': enabled,
        'hasSettings': hasSettings,
        'formats': formats,
        'logo': logo,
        'contentLanguage': contentLanguage,
        'extra': extra,
      };

  @override
  List<Object?> get props => [id];
}


class SourcePackage extends Equatable {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? author;
  final String? baseUrl;
  final String? manifestUrl;
  final List<PackageScraper> scrapers;
  final DateTime? addedAt;
  final DateTime? lastRefreshed;

  const SourcePackage({
    this.id = '',
    required this.name,
    this.version = '1.0.0',
    this.description,
    this.author,
    this.baseUrl,
    this.manifestUrl,
    this.scrapers = const [],
    this.addedAt,
    this.lastRefreshed,
  });

  int get scraperCount => scrapers.length;

  factory SourcePackage.fromJson(Map<String, dynamic> json) => SourcePackage(
        id: json['id']?.toString() ?? json['name']?.toString() ?? 'pkg',
        name: json['name']?.toString() ?? 'Paquete',
        version: json['version']?.toString() ?? '1.0.0',
        description: json['description']?.toString(),
        author: json['author']?.toString(),
        baseUrl: json['baseUrl']?.toString() ?? json['url']?.toString(),
        manifestUrl: json['manifestUrl']?.toString(),
        scrapers: (json['scrapers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => PackageScraper.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        addedAt: DateTime.tryParse(json['addedAt']?.toString() ?? ''),
        lastRefreshed:
            DateTime.tryParse(json['lastRefreshed']?.toString() ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'author': author,
        'baseUrl': baseUrl,
        'manifestUrl': manifestUrl,
        'scrapers': scrapers.map((s) => s.toJson()).toList(),
        'addedAt': addedAt?.toIso8601String(),
        'lastRefreshed': lastRefreshed?.toIso8601String(),
      };

  SourcePackage copyWith({
    String? manifestUrl,
    List<PackageScraper>? scrapers,
    DateTime? lastRefreshed,
  }) =>
      SourcePackage(
        id: id,
        name: name,
        version: version,
        description: description,
        author: author,
        baseUrl: baseUrl,
        manifestUrl: manifestUrl ?? this.manifestUrl,
        scrapers: scrapers ?? this.scrapers,
        addedAt: addedAt,
        lastRefreshed: lastRefreshed ?? this.lastRefreshed,
      );

  @override
  List<Object?> get props => [id, manifestUrl];
}
