import 'dart:convert';

/// Canal de TV en vivo
class TvChannel {
  final String id;
  final String name;
  final String url;
  final String? logo;
  final String? group;
  final String? country;
  final String? language;
  final Map<String, dynamic>? extra;

  const TvChannel({
    required this.id,
    required this.name,
    required this.url,
    this.logo,
    this.group,
    this.country,
    this.language,
    this.extra,
  });

  factory TvChannel.fromJson(Map<String, dynamic> json) {
    return TvChannel(
      id: (json['id'] ?? json['url'] ?? '').toString(),
      name: (json['name'] ?? 'Sin nombre').toString(),
      url: (json['url'] ?? '').toString(),
      logo: json['logo']?.toString(),
      group: (json['group'] ?? json['category'])?.toString(),
      country: json['country']?.toString(),
      language: json['language']?.toString(),
      extra: json['extra'] is Map
          ? Map<String, dynamic>.from(json['extra'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        if (logo != null) 'logo': logo,
        if (group != null) 'group': group,
        if (country != null) 'country': country,
        if (language != null) 'language': language,
        if (extra != null) 'extra': extra,
      };

  TvChannel copyWith({
    String? id,
    String? name,
    String? url,
    String? logo,
    String? group,
    String? country,
    String? language,
    Map<String, dynamic>? extra,
  }) {
    return TvChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      logo: logo ?? this.logo,
      group: group ?? this.group,
      country: country ?? this.country,
      language: language ?? this.language,
      extra: extra ?? this.extra,
    );
  }
}

/// Categoría de canales
class TvCategory {
  final String name;
  final List<TvChannel> channels;

  const TvCategory({
    required this.name,
    required this.channels,
  });

  factory TvCategory.fromJson(Map<String, dynamic> json) {
    final channels = (json['channels'] as List? ?? [])
        .map((e) => TvChannel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return TvCategory(
      name: (json['name'] ?? 'General').toString(),
      channels: channels,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'channels': channels.map((c) => c.toJson()).toList(),
      };
}

/// Manifest de un Addon de Canales
/// Estructura obligatoria del addon:
///   manifest.json
///   index.json
///   config.json (opcional)
///   logo.png / logo.jpg (OBLIGATORIO)
class TvAddonManifest {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? author;
  final String logoPath;
  final String? website;

  const TvAddonManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.logoPath,
    this.description,
    this.author,
    this.website,
  });

  factory TvAddonManifest.fromJson(
    Map<String, dynamic> json,
    String logoPath,
  ) {
    return TvAddonManifest(
      id: (json['id'] ?? json['name'] ?? '').toString(),
      name: (json['name'] ?? 'Addon').toString(),
      version: (json['version'] ?? '1.0.0').toString(),
      description: json['description']?.toString(),
      author: json['author']?.toString(),
      logoPath: logoPath,
      website: json['website']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        if (description != null) 'description': description,
        if (author != null) 'author': author,
        if (website != null) 'website': website,
      };
}

/// Addon de canales completo
class TvAddon {
  final TvAddonManifest manifest;
  final List<TvCategory> categories;
  final String folderPath;
  final Map<String, dynamic>? config;

  const TvAddon({
    required this.manifest,
    required this.categories,
    required this.folderPath,
    this.config,
  });

  int get totalChannels =>
      categories.fold(0, (sum, c) => sum + c.channels.length);
}

/// Lista M3U/M3U8 guardada por el usuario
class M3uPlaylist {
  final String id;
  final String name;
  final String url;
  final DateTime addedAt;
  final bool enabled;

  const M3uPlaylist({
    required this.id,
    required this.name,
    required this.url,
    required this.addedAt,
    this.enabled = true,
  });

  factory M3uPlaylist.fromJson(Map<String, dynamic> json) {
    return M3uPlaylist(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Lista').toString(),
      url: (json['url'] ?? '').toString(),
      addedAt: DateTime.tryParse(json['addedAt']?.toString() ?? '') ??
          DateTime.now(),
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'addedAt': addedAt.toIso8601String(),
        'enabled': enabled,
      };

  M3uPlaylist copyWith({
    String? id,
    String? name,
    String? url,
    DateTime? addedAt,
    bool? enabled,
  }) {
    return M3uPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      addedAt: addedAt ?? this.addedAt,
      enabled: enabled ?? this.enabled,
    );
  }
}
