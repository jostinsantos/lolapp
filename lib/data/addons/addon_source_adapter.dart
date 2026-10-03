import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'addon_manager.dart';
import 'models/addon.dart';
import 'models/content.dart';

/// Adapta las fuentes instaladas (addons Git) al formato Map que usa
/// ServidoresModal / SourceAggregator de App1.
/// No cambia la UI: emite los mismos campos (servidor_url, idioma, calidad, fuente...).
class AddonSourceAdapter {
  AddonSourceAdapter._();
  static final AddonSourceAdapter instance = AddonSourceAdapter._();

  /// Límite de addons consultados en paralelo (Settings: servidores_concurrent_checks).
  /// Default 3; rango 1–5. Así los servidores de addons aparecen tan rápido
  /// como las fuentes nativas (que ya usan Future.wait).
  static Future<int> _readMaxConcurrent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getInt('servidores_concurrent_checks') ?? 3).clamp(1, 5);
    } catch (_) {
      return 3;
    }
  }

  /// Stream de mapas compatibles con el modal de servidores,
  /// uno por cada stream de cada fuente instalada y habilitada.
  ///
  /// **Paralelo**: varios addons se consultan a la vez (hasta [maxConcurrent]),
  /// y los resultados se emiten en cuanto llegan (no se espera al más lento).
  Stream<Map<String, dynamic>> scrapeAll({
    required int tmdbId,
    required bool isMovie,
    int season = 0,
    int episode = 0,
    String? title,
    int? maxConcurrent,
  }) {
    final controller = StreamController<Map<String, dynamic>>();

    () async {
      try {
        final mgr = AddonManager.instance;
        await mgr.init();
        // Excluye addons solo-canales (type/capabilities channels) del modal de servidores VOD
        final sources = mgr.sourceAddons
            .where((a) => !a.isChannelsOnly)
            .toList();
        if (sources.isEmpty) {
          debugPrint('[AddonSourceAdapter] no hay fuentes VOD instaladas');
          return;
        }

        final content = ContentItem(
          id: isMovie ? 'tmdb:movie:$tmdbId' : 'tmdb:series:$tmdbId',
          title: title ?? '',
          type: isMovie ? ContentType.movie : ContentType.series,
          extra: {
            'tmdbId': tmdbId.toString(),
            if (!isMovie) 'season': season,
            if (!isMovie) 'episode': episode,
          },
        );

        final limit = maxConcurrent ?? await _readMaxConcurrent();
        debugPrint(
          '[AddonSourceAdapter] scrapeAll: ${sources.length} addons, '
          'concurrencia=$limit',
        );

        // Cola de addons + workers en paralelo
        final queue = List<AddonManifest>.from(sources);
        var nextIndex = 0;
        var active = 0;
        final done = Completer<void>();

        void pump() {
          while (active < limit && nextIndex < queue.length) {
            final addon = queue[nextIndex++];
            active++;
            () async {
              try {
                final streams = await mgr.sources
                    .getStreamsForAddon(content: content, addon: addon)
                    .timeout(const Duration(seconds: 25), onTimeout: () => []);
                for (final s in streams) {
                  if (s.url.isEmpty) continue;
                  if (controller.isClosed) return;
                  controller.add(_toModalMap(s, addon));
                }
              } catch (e, st) {
                debugPrint('[AddonSourceAdapter] ${addon.id}: $e\n$st');
              } finally {
                active--;
                if (nextIndex >= queue.length && active == 0) {
                  if (!done.isCompleted) done.complete();
                } else {
                  pump();
                }
              }
            }();
          }
          // Caso sin trabajo (sources vacío ya se filtró)
          if (nextIndex >= queue.length && active == 0) {
            if (!done.isCompleted) done.complete();
          }
        }

        pump();
        await done.future;
      } catch (e, st) {
        debugPrint('[AddonSourceAdapter] scrapeAll error: $e\n$st');
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }();

    return controller.stream;
  }

  /// Solo una fuente (por id de addon).
  Stream<Map<String, dynamic>> scrapeOne({
    required String addonId,
    required int tmdbId,
    required bool isMovie,
    int season = 0,
    int episode = 0,
    String? title,
  }) async* {
    final mgr = AddonManager.instance;
    await mgr.init();
    AddonManifest? addon;
    for (final a in mgr.sourceAddons) {
      if (a.id == addonId) {
        addon = a;
        break;
      }
    }
    if (addon == null) return;

    final content = ContentItem(
      id: isMovie ? 'tmdb:movie:$tmdbId' : 'tmdb:series:$tmdbId',
      title: title ?? '',
      type: isMovie ? ContentType.movie : ContentType.series,
      extra: {
        'tmdbId': tmdbId.toString(),
        if (!isMovie) 'season': season,
        if (!isMovie) 'episode': episode,
      },
    );

    try {
      final streams = await mgr.sources
          .getStreamsForAddon(content: content, addon: addon)
          .timeout(const Duration(seconds: 25), onTimeout: () => []);
      for (final s in streams) {
        if (s.url.isEmpty) continue;
        yield _toModalMap(s, addon);
      }
    } catch (e, st) {
      debugPrint('[AddonSourceAdapter] $addonId: $e\n$st');
    }
  }

  /// Lista de fuentes instaladas para poblar pestañas del modal (sin UI nueva).
  Future<List<({String id, String label, String badge})>> listSources() async {
    final mgr = AddonManager.instance;
    await mgr.init();
    return mgr.sourceAddons
        .map((a) => (
              id: a.id,
              label: a.name,
              badge: (a.name.length > 8 ? a.name.substring(0, 8) : a.name)
                  .toUpperCase(),
            ))
        .toList();
  }

  Map<String, dynamic> _toModalMap(StreamItem s, AddonManifest addon) {
    final lang = _guessLang(s.title, s.provider);
    return {
      'servidor_url': s.url,
      'url': s.url,
      'calidad': s.quality ?? 'Digital',
      'idioma': lang,
      'servidor_nombre': s.title.isNotEmpty ? s.title : (s.provider ?? addon.name),
      'nombre': s.title.isNotEmpty ? s.title : (s.provider ?? addon.name),
      'fuente': addon.id,
      'addon_id': addon.id,
      'addon_name': addon.name,
      'provider': s.provider ?? addon.name,
      'is_hls': s.isHls,
      'headers': s.headers,
      if (s.infoHash != null) 'infoHash': s.infoHash,
      // flags estilo extractores para filtros de idioma en el modal
      if (lang.startsWith('es')) 'es_${addon.id}': true,
      if (lang.startsWith('en') || lang == 'SUB') 'en_${addon.id}': true,
      if (lang.contains('LAT')) 'lat_${addon.id}': true,
    };
  }

  String _guessLang(String title, String? provider) {
    final t = '${title.toLowerCase()} ${(provider ?? '').toLowerCase()}';
    if (t.contains('latino') || t.contains('lat ')) return 'es_MX';
    if (t.contains('castellano') || t.contains('español') || t.contains('spanish')) {
      return 'es_ES';
    }
    if (t.contains('sub') || t.contains('vos') || t.contains('english')) {
      return 'SUB';
    }
    return 'es_MX';
  }
}
