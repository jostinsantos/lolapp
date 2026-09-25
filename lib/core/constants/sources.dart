// lib/config/sources.dart
import 'package:flutter/material.dart';

import '../../data/extractors/providers/cuevana_extractor.dart';
import '../../data/extractors/providers/unlimplay_extractor.dart';
import '../../data/extractors/providers/cinecalidad_extractor.dart';
import '../../data/extractors/providers/tioplus_extractor.dart';
import '../../data/extractors/providers/embed69_extractor.dart';
import '../../data/extractors/providers/poseidon_extractor.dart';
import '../../data/extractors/providers/fuegocine_extractor.dart';
import '../../data/extractors/providers/hackstore_extractor.dart';
import '../../data/extractors/providers/pelisplus_extractor.dart';
import '../../data/extractors/providers/cinesrc_extractor.dart';
import '../../data/extractors/providers/pelispedia_extractor.dart';
import '../../data/extractors/providers/seriesmetro_extractor.dart';
import '../../data/extractors/providers/smartpelis_extractor.dart';
import '../../data/datasources/remote/sources/custom_api.dart';
typedef SourceScraper = Stream<Map<String, dynamic>> Function({
  required int tmdbId,
  required bool isMovie,
  required int season,
  required int episode,
});

class SourceDefinition {
  final String id;
  final String label;
  final String prefsKey;
  final Color badgeColor;
  final String badgeText;
  final SourceScraper scrape;
  final String? forceIdioma;
  final int maxResults;
  final String flagKey;
  final IconData icon;

  const SourceDefinition({
    required this.id,
    required this.label,
    required this.prefsKey,
    required this.badgeColor,
    required this.badgeText,
    required this.scrape,
    required this.flagKey,
    this.forceIdioma,
    this.maxResults = 12,
    this.icon = Icons.play_circle_outline_rounded,
  });
}

final List<SourceDefinition> kRegisteredSources = [
  SourceDefinition(
    id: 'embed69',
    label: 'Embed69',
    prefsKey: 'embed69_enabled',
    badgeColor: const Color(0xFFA855F7),
    badgeText: 'EMBED69',
    flagKey: 'es_embed69',
    icon: Icons.hub_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return Embed69Service.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_embed69'] = true;
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'poseidon',
    label: 'Poseidon',
    prefsKey: 'poseidon_enabled',
    badgeColor: const Color(0xFF06B6D4),
    badgeText: 'POSEIDON',
    flagKey: 'es_poseidon',
    icon: Icons.waves_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return PoseidonService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_poseidon'] = true;
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'cuevana',
    label: 'Cuevana',
    prefsKey: 'cuevana_enabled',
    badgeColor: const Color(0xFFE50914),
    badgeText: 'CUEVANA',
    flagKey: 'es_cuevana',
    icon: Icons.movie_filter_rounded,
    maxResults: 16,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return CuevanaService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_cuevana'] = true;
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'unlimplay',
    label: 'Unlimplay',
    prefsKey: 'unlimplay_enabled',
    badgeColor: const Color(0xFF3B82F6),
    badgeText: 'UNLIM',
    flagKey: 'es_unlimplay',
    icon: Icons.play_circle_fill_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return UnlimplayService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_unlimplay'] = true;
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'cinesrc',
    label: 'CineSRC',
    prefsKey: 'cinesrc_enabled',
    badgeColor: const Color(0xFF00FF66),
    badgeText: 'CINESRC',
    flagKey: 'es_cinesrc',
    icon: Icons.movie_creation_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return CineSrcService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_cinesrc'] = true;
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'cinecalidad',
    label: 'Cinecalidad',
    prefsKey: 'cinecalidad_enabled',
    badgeColor: const Color(0xFFF59E0B),
    badgeText: 'CINE',
    flagKey: 'es_cinecalidad',
    forceIdioma: 'es_MX',
    icon: Icons.local_movies_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return CinecalidadService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_cinecalidad'] = true;
        map['idioma'] = 'es_MX';
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'tioplus',
    label: 'TioPlus',
    prefsKey: 'tioplus_enabled',
    badgeColor: const Color(0xFF22C55E),
    badgeText: 'TIOPLUS',
    flagKey: 'es_tioplus',
    forceIdioma: 'es_MX',
    icon: Icons.tv_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return TioplusService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_tioplus'] = true;
        map['idioma'] ??= 'es_MX';
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'fuegocine',
    label: 'FuegoCine',
    prefsKey: 'fuegocine_enabled',
    badgeColor: const Color(0xFFFF6B00),
    badgeText: 'FUEGO',
    flagKey: 'es_fuegocine',
    forceIdioma: 'es_MX',
    icon: Icons.local_fire_department_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return FuegoCineService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((map) {
        final m = Map<String, dynamic>.from(map);
        m['es_fuegocine'] = true;
        m['idioma'] = m['idioma'] ?? 'es_MX';
        return m;
      });
    },
  ),
  SourceDefinition(
    id: 'hackstore',
    label: 'HackStore',
    prefsKey: 'hackstore_enabled',
    badgeColor: const Color(0xFFE74C3C),
    badgeText: 'HACK',
    flagKey: 'es_hackstore',
    icon: Icons.security_rounded,
    maxResults: 15,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return HackStoreService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((map) {
        final m = Map<String, dynamic>.from(map);
        m['es_hackstore'] = true;
        if (m['idioma'] == null || (m['idioma'] as String).isEmpty) {
          m['idioma'] = 'es_MX';
        }
        return m;
      });
    },
  ),
  SourceDefinition(
    id: 'pelisplus',
    label: 'PelisPlusHD',
    prefsKey: 'pelisplus_enabled',
    badgeColor: const Color(0xFF10B981),
    badgeText: 'PELIS+',
    flagKey: 'es_pelisplus',
    icon: Icons.hd_rounded,
    maxResults: 15,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return PelisPlusService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((map) {
        final m = Map<String, dynamic>.from(map);
        m['es_pelisplus'] = true;
        if (m['idioma'] == null || (m['idioma'] as String).isEmpty) {
          m['idioma'] = 'es_MX';
        }
        return m;
      });
    },
  ),
  SourceDefinition(
    id: 'pelispedia',
    label: 'Pelispedia',
    prefsKey: 'pelispedia_enabled',
    badgeColor: const Color(0xFF14B8A6),
    badgeText: 'PEDIA',
    flagKey: 'es_pelispedia',
    icon: Icons.video_library_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return PelispediaService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_pelispedia'] = true;
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'seriesmetro',
    label: 'SeriesMetro',
    prefsKey: 'seriesmetro_enabled',
    badgeColor: const Color(0xFF6366F1),
    badgeText: 'METRO',
    flagKey: 'es_seriesmetro',
    icon: Icons.subway_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return SeriesMetroService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_seriesmetro'] = true;
        return map;
      });
    },
  ),
  SourceDefinition(
    id: 'smartpelis',
    label: 'SmartPelis',
    prefsKey: 'smartpelis_enabled',
    badgeColor: const Color(0xFFF97316),
    badgeText: 'SMART',
    flagKey: 'es_smartpelis',
    icon: Icons.smart_display_rounded,
    maxResults: 12,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return SmartPelisService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_smartpelis'] = true;
        return map;
      });
    },
  ),
  // ── APIs personalizadas del usuario (códigos PHP ilimitados) ──
  SourceDefinition(
    id: 'customapi',
    label: 'Mis APIs',
    prefsKey: 'custom_api_enabled',
    badgeColor: const Color(0xFF60A5FA),
    badgeText: 'API',
    flagKey: 'es_customapi',
    icon: Icons.cloud_rounded,
    maxResults: 64,
    scrape: ({
      required tmdbId,
      required isMovie,
      required season,
      required episode,
    }) {
      return CustomApiService.scrape(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).map((s) {
        final map = s.toModalMap();
        map['es_customapi'] = true;
        return map;
      });
    },
  ),
];