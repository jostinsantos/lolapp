import 'package:equatable/equatable.dart';

enum ContentType { movie, series, episode, live }

extension ContentTypeX on ContentType {
  String get label {
    switch (this) {
      case ContentType.movie:
        return 'Película';
      case ContentType.series:
        return 'Serie';
      case ContentType.episode:
        return 'Episodio';
      case ContentType.live:
        return 'En vivo';
    }
  }
}

/// Ítem de catálogo / resultado de búsqueda.
class ContentItem extends Equatable {
  final String id; // tmdb:movie:123 o similar
  final String title;
  final String? originalTitle;
  final ContentType type;
  final String? poster;
  final String? backdrop;
  final String? overview;
  final String? year;
  final double? rating;
  final List<String> genres;
  final String? addonId; // de qué catálogo vino
  final Map<String, dynamic> extra;

  const ContentItem({
    required this.id,
    required this.title,
    this.originalTitle,
    required this.type,
    this.poster,
    this.backdrop,
    this.overview,
    this.year,
    this.rating,
    this.genres = const [],
    this.addonId,
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'originalTitle': originalTitle,
        'type': type.name,
        'poster': poster,
        'backdrop': backdrop,
        'overview': overview,
        'year': year,
        'rating': rating,
        'genres': genres,
        'addonId': addonId,
        'extra': extra,
      };

  factory ContentItem.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? json['mediaType'] ?? 'movie').toString().toLowerCase();
    final type = ContentType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () {
        if (typeStr.contains('series') ||
            typeStr.contains('tv') ||
            typeStr.contains('anime') ||
            typeStr == 'show') {
          return ContentType.series;
        }
        if (typeStr.contains('live') || typeStr.contains('channel')) {
          return ContentType.live;
        }
        if (typeStr.contains('episode')) return ContentType.episode;
        return ContentType.movie;
      },
    );
    final extra = Map<String, dynamic>.from(json['extra'] as Map? ?? {});
    // Temporadas a nivel raíz → extra.seasons (addons sin tmdb)
    if (json['seasons'] is List && extra['seasons'] == null) {
      extra['seasons'] = json['seasons'];
    }
    if (json['episodes'] is List && extra['episodes'] == null) {
      extra['episodes'] = json['episodes'];
    }
    // Enlace directo fuente (JKAnime, etc.)
    for (final k in [
      'url_personalizada',
      'jkanimeUrl',
      'jkanimeSlug',
      'tmdbId',
      'sourceUrl'
    ]) {
      if (json[k] != null && extra[k] == null) {
        extra[k] = json[k];
      }
    }
    return ContentItem(
      id: (json['id'] ?? json['contentId'] ?? '').toString(),
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      originalTitle: json['originalTitle'] as String?,
      type: type,
      poster: json['poster'] as String? ?? json['posterUrl'] as String? ?? json['image'] as String?,
      backdrop: json['backdrop'] as String?,
      overview: json['overview'] as String?,
      year: json['year']?.toString(),
      rating: (json['rating'] as num?)?.toDouble(),
      genres: List<String>.from(json['genres'] ?? []),
      addonId: json['addonId'] as String?,
      extra: extra,
    );
  }

  @override
  List<Object?> get props => [id];
}

/// Stream / servidor de reproducción.
class StreamItem extends Equatable {
  final String url;
  final String title;
  final String? quality;
  final String? provider;
  final String? addonId;
  final Map<String, String> headers;
  final bool isHls;
  final String? infoHash; // torrent / magnet
  /// Código de idioma del servidor (es_MX, es_ES, en_US, …).
  final String? lang;

  const StreamItem({
    required this.url,
    required this.title,
    this.quality,
    this.provider,
    this.addonId,
    this.headers = const {},
    this.isHls = false,
    this.infoHash,
    this.lang,
  });

  bool get isTorrent =>
      (infoHash != null && infoHash!.isNotEmpty) ||
      url.startsWith('magnet:') ||
      url.startsWith('torrent:');

  factory StreamItem.fromJson(Map<String, dynamic> json) {
    final headersRaw = json['headers'];
    final headers = <String, String>{};
    if (headersRaw is Map) {
      headersRaw.forEach((k, v) {
        if (k != null && v != null) headers[k.toString()] = v.toString();
      });
    }
    final url = (json['url'] as String? ?? '').toString();
    final infoHash = (json['infoHash'] ?? json['info_hash'])?.toString();
    final magnet = json['magnet']?.toString();
    final finalUrl = url.isNotEmpty
        ? url
        : (magnet ?? (infoHash != null ? 'magnet:?xt=urn:btih:$infoHash' : ''));
    final langRaw = (json['lang'] ??
            json['language'] ??
            json['idioma'] ??
            json['audio'])
        ?.toString();
    return StreamItem(
      url: finalUrl,
      title: json['title'] as String? ?? json['name'] as String? ?? 'Stream',
      quality: json['quality'] as String?,
      provider: json['provider'] as String? ?? json['name'] as String?,
      addonId: json['addonId'] as String?,
      headers: headers,
      isHls: finalUrl.contains('.m3u8') || (json['isHls'] as bool? ?? false),
      infoHash: infoHash,
      lang: (langRaw != null && langRaw.isNotEmpty) ? langRaw : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'quality': quality,
        'provider': provider,
        'addonId': addonId,
        'headers': headers,
        'isHls': isHls,
        'infoHash': infoHash,
        if (lang != null) 'lang': lang,
      };

  @override
  List<Object?> get props => [url, quality, lang];
}

/// Subtítulo.
class SubtitleItem extends Equatable {
  final String url;
  final String language;
  final String? label;
  final String? addonId;

  const SubtitleItem({
    required this.url,
    required this.language,
    this.label,
    this.addonId,
  });

  factory SubtitleItem.fromJson(Map<String, dynamic> json) {
    return SubtitleItem(
      url: json['url'] as String? ?? '',
      language: json['language'] as String? ?? 'es',
      label: json['label'] as String? ?? json['lang'] as String?,
      addonId: json['addonId'] as String?,
    );
  }

  @override
  List<Object?> get props => [url, language];
}

/// Fila de home / catálogo.
class CatalogRow extends Equatable {
  final String id;
  final String title;
  final List<ContentItem> items;
  final String? addonId;

  const CatalogRow({
    required this.id,
    required this.title,
    required this.items,
    this.addonId,
  });

  @override
  List<Object?> get props => [id];
}

/// Item guardado / continuar viendo.
class SavedItem extends Equatable {
  final ContentItem content;
  final int? progressMs;
  final int? durationMs;
  final DateTime savedAt;
  final bool isFavorite;

  const SavedItem({
    required this.content,
    this.progressMs,
    this.durationMs,
    required this.savedAt,
    this.isFavorite = false,
  });

  double get progressFraction {
    if (durationMs == null || durationMs == 0 || progressMs == null) return 0;
    return (progressMs! / durationMs!).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'content': content.toJson(),
        'progressMs': progressMs,
        'durationMs': durationMs,
        'savedAt': savedAt.toIso8601String(),
        'isFavorite': isFavorite,
      };

  factory SavedItem.fromJson(Map<String, dynamic> json) {
    return SavedItem(
      content: ContentItem.fromJson(json['content'] as Map<String, dynamic>),
      progressMs: json['progressMs'] as int?,
      durationMs: json['durationMs'] as int?,
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.now(),
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [content.id];
}


/// Temporada de una serie (TMDB).
class SeasonInfo extends Equatable {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? poster;
  final String? overview;

  const SeasonInfo({
    required this.seasonNumber,
    required this.name,
    this.episodeCount = 0,
    this.poster,
    this.overview,
  });

  @override
  List<Object?> get props => [seasonNumber];
}

/// Episodio de una serie.
class EpisodeInfo extends Equatable {
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? still;
  final String? airDate;
  final double? rating;
  final int? runtime;
  /// Metadatos extra (p. ej. kinoRef de un paquete Kino).
  final Map<String, dynamic> extra;

  const EpisodeInfo({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.still,
    this.airDate,
    this.rating,
    this.runtime,
    this.extra = const {},
  });

  /// ID de contenido para buscar streams: tmdb:series:ID:S:E
  String contentId(String seriesTmdbId) =>
      'tmdb:series:$seriesTmdbId:$seasonNumber:$episodeNumber';

  @override
  List<Object?> get props => [seasonNumber, episodeNumber];
}
