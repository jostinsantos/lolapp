// lib/mobil/servicios/main_fuentes_servidores.dart
import 'dart:async';

import 'package:flutter/material.dart';

// Ajusta las rutas según dónde tengas los scrapers
import '../extractors/providers/cuevana_extractor.dart'; // CuevanaService
import '../extractors/providers/embed69_extractor.dart'; // Embed69Service
import '../extractors/providers/pelisplus_extractor.dart'; // PelisPlusService
import '../extractors/providers/tioplus_extractor.dart'; // TioplusService
import '../extractors/providers/unlimplay_extractor.dart'; // UnlimplayService
import '../extractors/hls/hls_extractor.dart'; // ExtractorHlsService  ← NUEVO

class ServerEvent {
  final Map<String, dynamic>? servidor;
  final bool isDone;
  final bool isVerified;
  final String? error;
  final String? resolvedM3u8;

  const ServerEvent({
    this.servidor,
    this.isDone = false,
    this.isVerified = false,
    this.error,
    this.resolvedM3u8,
  });
}

class MainFuentesServidores {
  /// Mapeo servicio → fuente interna
  static String _mapServicio(String servicio) {
    switch (servicio.toLowerCase().trim()) {
      case 'cuevana':
        return 'cuevana';
      case 'serieskao':
        return 'embed69';
      case 'pelisplus':
        return 'pelisplus';
      case 'tioplus':
        return 'tioplus';
      case 'cinehax':
        return 'unlimplay';
      default:
        return servicio.toLowerCase().trim();
    }
  }

  /// Stream de servidores de UNA sola fuente.
  /// Verifica con ExtractorHlsService si [verificar] = true y hay [context].
  static Stream<ServerEvent> scrape({
    required String servicio,
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
    BuildContext? context,
    bool verificar = true,
    int maxServers = 20,
  }) {
    final controller = StreamController<ServerEvent>();

    if (tmdbId <= 0) {
      controller.add(ServerEvent(isDone: true, error: 'tmdb_id inválido'));
      controller.close();
      return controller.stream;
    }

    final fuente = _mapServicio(servicio);

    () async {
      try {
        var count = 0;
        final seen = <String>{};

        await for (final map in _scrapeOne(
          fuente: fuente,
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          if (controller.isClosed) break;
          if (count >= maxServers) break;

          final url = map['servidor_url']?.toString() ??
              map['url']?.toString() ??
              '';
          if (url.isEmpty || seen.contains(url)) continue;
          seen.add(url);

          // Normalizar idioma
          map['idioma'] = _normalizeIdioma(map['idioma']?.toString());
          map['fuente'] = fuente;
          map['servicio_origen'] = servicio;
          map['tmdb_id'] = tmdbId;
          map['season'] = isMovie ? 0 : season;
          map['episode'] = isMovie ? 0 : episode;

          final urlLower = url.toLowerCase();
          final esDirecto = map['type']?.toString() == 'direct' ||
              urlLower.contains('.mp4') ||
              urlLower.contains('.m3u8');

          if (verificar && context != null && context.mounted && !esDirecto) {
            // ── Verificación HLS ──────────────────────────────────────
            // Usa la misma lógica que MainFuentes.fetchProgressive:
            // nativos (VOE, Dood, StreamWish, VidHide, etc.)
            // + WebView oculto 1x1 con detección avanzada.
            final m3u8 = await ExtractorHlsService.buscarFuente(
              context,
              url,
              timeout: const Duration(seconds: 10),
            );
            if (m3u8 == null || m3u8.isEmpty) {
              // No pasó la verificación → lo saltamos
              continue;
            }
            map['resolved_m3u8'] = m3u8;
            map['verificado'] = true;
            count++;
            if (!controller.isClosed) {
              controller.add(ServerEvent(
                servidor: map,
                isVerified: true,
                resolvedM3u8: m3u8,
              ));
            }
          } else {
            // Directo o sin contexto → se emite tal cual
            map['verificado'] = esDirecto;
            count++;
            if (!controller.isClosed) {
              controller.add(ServerEvent(
                servidor: map,
                isVerified: esDirecto,
              ));
            }
          }
        }

        if (!controller.isClosed) {
          controller.add(const ServerEvent(isDone: true));
          await controller.close();
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.add(ServerEvent(
            isDone: true,
            error: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
          ));
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  // ─── Llamada a cada scraper ─────────────────────────────────────────────
  static Stream<Map<String, dynamic>> _scrapeOne({
    required String fuente,
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) async* {
    switch (fuente) {
      case 'cuevana':
        await for (final s in CuevanaService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;

      case 'embed69':
        await for (final s in Embed69Service.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;

      case 'pelisplus':
        await for (final map in PelisPlusService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          // PelisPlus ya emite Map
          yield {
            'servidor_nombre':
                'PelisPlus · ${map['servidor'] ?? map['server'] ?? 'Online'}',
            'servidor_url': map['servidor_url'] ?? map['url'] ?? '',
            'calidad': map['quality'] ?? 'HD',
            'idioma': map['idioma'] ?? 'es_MX',
            'estado': 'activo',
            'es_pelisplus': true,
          };
        }
        break;

      case 'tioplus':
        await for (final s in TioplusService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;

      case 'unlimplay':
        await for (final s in UnlimplayService.scrape(
          tmdbId: tmdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
        )) {
          yield s.toModalMap();
        }
        break;

      default:
        throw Exception('Fuente no soportada: $fuente');
    }
  }

  static String _normalizeIdioma(String? raw) {
    if (raw == null || raw.isEmpty) return 'es_MX';
    final l = raw.toLowerCase().trim();
    if (l.contains('castellano') ||
        l.contains('es_es') ||
        l.contains('es-es')) {
      return 'es_ES';
    }
    if (l.contains('sub') ||
        l.contains('en_us') ||
        l.contains('ingles') ||
        l.contains('inglés') ||
        l.contains('english')) {
      return 'en_US';
    }
    if (l.contains('japon')) return 'ja_JA';
    return 'es_MX';
  }

  static String idiomaLabel(String code) {
    switch (code) {
      case 'es_ES':
        return 'Castellano';
      case 'en_US':
        return 'Subtitulado';
      case 'ja_JA':
        return 'Japonés';
      default:
        return 'Latino';
    }
  }
}