import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/aggregators/source_aggregator.dart';
import '../../../data/datasources/remote/tmdb/tmdb_content.dart';
import '../../player/data/extractor.dart';
import '../../player/presentation/player_page.dart'; // ← ajusta ruta
import '../../player/presentation/web_player_view.dart'; // WEBVIEW → página dedicada
import '../../downloads/presentation/extractor_download_page.dart';
import '../../discover/presentation/source_discovery_page.dart';
import 'server_preloader_service.dart';

const _kAccent = Color(0xFFE50914);
const _kOrange = Color(0xFFFF6B00);
const _kCard = Color(0xFF1C1C1E);
const _kBg = Color(0xFF0A0A0A);

// ═══════════════════════════════════════════════════════════════════════════
// CACHÉ M3U8 (1 hora, con timestamp POR ENTRADA)
// ═══════════════════════════════════════════════════════════════════════════

class TvM3u8Entry {
  final String m3u8;
  final int ts;
  const TvM3u8Entry(this.m3u8, this.ts);
}

class TvM3u8Cache {
  TvM3u8Cache._();

  static const int ttlMs = 60 * 60 * 1000; // 1 hora

  static Future<void> _chain = Future<void>.value();

  static Future<T> _serial<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  static String _key({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) =>
      'm3u8_cache_v2_${tmdbId}_${tipo}_T${season}_C$episode';

  static Map<String, TvM3u8Entry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final out = <String, TvM3u8Entry>{};
      map.forEach((k, v) {
        if (v is Map) {
          final m = v['m']?.toString() ?? '';
          final t = v['t'];
          if (m.isNotEmpty && t is int) out[k] = TvM3u8Entry(m, t);
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static String _encode(Map<String, TvM3u8Entry> entries) => jsonEncode(
        entries.map((k, v) => MapEntry(k, {'m': v.m3u8, 't': v.ts})),
      );

  static Future<Map<String, TvM3u8Entry>> load({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) =>
      _serial(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final key = _key(
            tmdbId: tmdbId,
            tipo: tipo,
            season: season,
            episode: episode,
          );
          final all = _decode(prefs.getString(key));
          final now = DateTime.now().millisecondsSinceEpoch;
          final fresh = <String, TvM3u8Entry>{};
          all.forEach((k, v) {
            if (now - v.ts <= ttlMs) fresh[k] = v;
          });
          if (fresh.length != all.length) {
            if (fresh.isEmpty) {
              await prefs.remove(key);
            } else {
              await prefs.setString(key, _encode(fresh));
            }
          }
          return fresh;
        } catch (_) {
          return <String, TvM3u8Entry>{};
        }
      });

  static Future<void> save({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
    required String embedUrl,
    required String m3u8,
  }) =>
      _serial(() async {
        if (embedUrl.isEmpty || m3u8.isEmpty) return;
        try {
          final prefs = await SharedPreferences.getInstance();
          final key = _key(
            tmdbId: tmdbId,
            tipo: tipo,
            season: season,
            episode: episode,
          );
          final now = DateTime.now().millisecondsSinceEpoch;
          final all = _decode(prefs.getString(key))
            ..removeWhere((_, v) => now - v.ts > ttlMs);
          all[embedUrl] = TvM3u8Entry(m3u8, now);
          await prefs.setString(key, _encode(all));
        } catch (_) {}
      });

  static Future<void> clear({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) =>
      _serial(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_key(
            tmdbId: tmdbId,
            tipo: tipo,
            season: season,
            episode: episode,
          ));
        } catch (_) {}
      });
}

/// Pestaña: FuenteId normal O String "custom_48392"
class _TabKey {
  final FuenteId? fuente;
  final String? customId; // custom_XXXXX
  final String label;
  final Color color;

  const _TabKey.todos()
      : fuente = FuenteId.todos,
        customId = null,
        label = 'Todos',
        color = _kAccent;

  const _TabKey.fuente(FuenteId f)
      : fuente = f,
        customId = null,
        label = '', // se resuelve con f.label
        color = Colors.white;

  const _TabKey.custom({
    required this.customId,
    required this.label,
    required this.color,
  }) : fuente = null;

  bool get isTodos => fuente == FuenteId.todos;
  bool get isCustom => customId != null;

  String get displayLabel {
    if (isCustom) return label;
    return fuente?.label ?? label;
  }

  Color get displayColor {
    if (isCustom) return color;
    return fuente?.badgeColor ?? color;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _TabKey) return false;
    if (isCustom && other.isCustom) return customId == other.customId;
    return fuente == other.fuente && customId == other.customId;
  }

  @override
  int get hashCode => Object.hash(fuente, customId);
}

class ServidoresModal extends StatefulWidget {
  final int idcontenido;
  final int? tmdbId;
  final int? temporada;
  final int? capitulo;
  final String? tipo;
  final String? titulo;
  final bool fromPlayer;
  final bool esSiguienteCapitulo;
  final bool forDownload;
  final String? backdropUrl;
  final String? posterUrl;
  final String? logoUrl;

  const ServidoresModal({
    super.key,
    required this.idcontenido,
    this.tmdbId,
    this.temporada,
    this.capitulo,
    this.tipo,
    this.titulo,
    this.fromPlayer = false,
    this.esSiguienteCapitulo = false,
    this.forDownload = false,
    this.backdropUrl,
    this.posterUrl,
    this.logoUrl,
  });

  @override
  State<ServidoresModal> createState() => _ServidoresModalState();
}

class _ServidoresModalState extends State<ServidoresModal>
    with SingleTickerProviderStateMixin {
  final MainFuentes _fuentes = MainFuentes();
  final TmdbContentService _tmdb = TmdbContentService();

  FuentesConfig? _cfg;
  bool _loadingConfig = true;
  bool _loadingMeta = true;
  bool _scraping = false;
  bool _navigating = false;

  String? _error;
  String? _backdrop;
  String? _logo;
  String _titulo = '';

  final Map<FuenteId, List<Map<String, dynamic>>> _porFuente = {};
  /// Cada código API = lista propia (pestaña independiente)
  final Map<String, List<Map<String, dynamic>>> _porCustom = {};
  final Map<String, String> _customLabels = {};
  final Map<String, Color> _customColors = {};

  final List<Map<String, dynamic>> _todos = [];
  final Map<String, List<Map<String, dynamic>>> _porIdioma = {};
  final Set<String> _seenUrls = {};
  final Map<FuenteId, bool> _fuenteDone = {};
  final Map<FuenteId, String?> _fuenteError = {};

  TabController? _tabController;
  List<_TabKey> _tabs = [const _TabKey.todos()];

  StreamSubscription<FuenteEvent>? _sub;
  int? _resumeSec;
  bool _fromCache = false;
  String? _cacheAgeLabel;

  /// Settings: idioma_audio_predeterminado → prioridad de lista
  String _preferredAudio = 'latino'; // latino | castellano | subtitulado
  /// Settings: servidores_concurrent_checks (1–5)
  int _concurrentChecks = 2;

  int get _resolvedTmdbId => widget.tmdbId ?? widget.idcontenido;

  String get _mediaType {
    final raw = widget.tipo?.toLowerCase().trim();
    if (raw == 'tv' || raw == 'serie' || raw == 'series') return 'tv';
    if (raw == 'movie' || raw == 'pelicula' || raw == 'película') {
      return 'movie';
    }
    if (widget.temporada != null || widget.capitulo != null) return 'tv';
    return 'movie';
  }

  bool get _isMovie => _mediaType == 'movie';
  int get _season => widget.temporada ?? 1;
  int get _episode => widget.capitulo ?? 1;

  Color _parseColor(String? hex) {
    try {
      var h = (hex ?? '').trim();
      if (h.startsWith('#')) h = h.substring(1);
      if (h.length == 6) {
        return Color(int.parse(h, radix: 16) + 0xFF000000);
      }
    } catch (_) {}
    return const Color(0xFF60A5FA);
  }

  @override
  void initState() {
    super.initState();
    _titulo = widget.titulo?.trim().isNotEmpty == true
        ? widget.titulo!.trim()
        : '';
    _backdrop = widget.backdropUrl;
    _logo = widget.logoUrl;
    _bootstrap();
    _loadResumeProgress();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  void _rebuildTabs(List<_TabKey> next, {_TabKey? prefer}) {
    if (!mounted) return;
    final same = next.length == _tabs.length &&
        List.generate(next.length, (i) => next[i] == _tabs[i]).every((e) => e);
    if (same) return;

    final current = prefer ??
        ((_tabController != null && _tabs.isNotEmpty)
            ? _tabs[_tabController!.index.clamp(0, _tabs.length - 1)]
            : const _TabKey.todos());

    _tabs = next;
    final old = _tabController;
    _tabController = TabController(length: _tabs.length, vsync: this);
    final idx = _tabs.indexWhere((t) => t == current);
    _tabController!.index = idx >= 0 ? idx : 0;
    old?.dispose();
  }

  /// Pestañas: Todos + fuentes normales (sin customapi genérico) + cada código API
  void _syncTabs({bool reorderByContent = false}) {
    final cfg = _cfg;
    final activas = cfg?.fuentesActivas ?? <FuenteId>[];

    final normal = activas.where((f) => f != FuenteId.customapi).toList();
    List<FuenteId> orderedNormal = normal;

    if (reorderByContent && cfg?.verificarServidores == true) {
      final withContent = <FuenteId>[];
      final empty = <FuenteId>[];
      for (final f in normal) {
        if ((_porFuente[f]?.length ?? 0) > 0) {
          withContent.add(f);
        } else {
          empty.add(f);
        }
      }
      orderedNormal = [...withContent, ...empty];
    }

    final customKeys = _porCustom.keys.toList()..sort();
    // Preferir códigos con contenido primero
    if (reorderByContent) {
      customKeys.sort((a, b) {
        final na = _porCustom[a]?.length ?? 0;
        final nb = _porCustom[b]?.length ?? 0;
        if (na == 0 && nb > 0) return 1;
        if (nb == 0 && na > 0) return -1;
        return a.compareTo(b);
      });
    }

    final next = <_TabKey>[
      const _TabKey.todos(),
      ...orderedNormal.map((f) => _TabKey.fuente(f)),
      ...customKeys.map(
        (k) => _TabKey.custom(
          customId: k,
          label: _customLabels[k] ?? k.replaceFirst('custom_', 'API '),
          color: _customColors[k] ?? const Color(0xFF60A5FA),
        ),
      ),
    ];

    _rebuildTabs(next);
  }

  void _maybeReorderTabs() => _syncTabs(reorderByContent: true);

  Future<void> _loadUserPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final audio = prefs.getString('idioma_audio_predeterminado') ?? 'latino';
      final concurrent =
          (prefs.getInt('servidores_concurrent_checks') ?? 2).clamp(1, 5);
      if (!mounted) return;
      setState(() {
        _preferredAudio = audio;
        _concurrentChecks = concurrent;
      });
      // Si MainFuentes/ServerLoader expone concurrency, aplicarlo aquí:
      try {
        // ignore: avoid_dynamic_calls
        (_fuentes as dynamic).maxConcurrent = concurrent;
      } catch (_) {}
      try {
        // ignore: avoid_dynamic_calls
        (_fuentes as dynamic).setMaxConcurrent?.call(concurrent);
      } catch (_) {}
    } catch (e) {
      debugPrint('ServidoresModal prefs: $e');
    }
  }

  /// Código de idioma normalizado según preferencia de Settings.
  String get _preferredLangCode {
    switch (_preferredAudio) {
      case 'castellano':
        return 'es_ES';
      case 'subtitulado':
        return 'en_US';
      case 'latino':
      default:
        return 'es_MX';
    }
  }

  int _langSortKey(String lang) {
    final pref = _preferredLangCode;
    if (lang == pref) return 0;
    if (pref.startsWith('es') && lang.startsWith('es')) return 1;
    const order = ['es_MX', 'es_ES', 'en_US', 'ja_JA'];
    final i = order.indexOf(lang);
    if (i >= 0) return 2 + i;
    return 50;
  }

    Future<void> _bootstrap() async {
    try {
      await _loadUserPrefs();
      final cfg = await _fuentes.loadConfig();
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _loadingConfig = false;
      });
      _syncTabs();

      final needMeta = _titulo.isEmpty ||
          (_backdrop == null || _backdrop!.isEmpty) ||
          (_logo == null || _logo!.isEmpty);
      if (needMeta) {
        _loadMeta();
      } else {
        setState(() => _loadingMeta = false);
      }

      await _startFlow();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingConfig = false;
          _error = 'Error cargando configuración: $e';
        });
      }
    }
  }

  Future<void> _loadMeta() async {
    try {
      final json = await _tmdb.fetchContent(
        tmdbId: _resolvedTmdbId,
        mediaType: _mediaType,
      );
      if (!mounted) return;
      if (json['success'] == true && json['data'] is Map) {
        final data = Map<String, dynamic>.from(json['data'] as Map);
        setState(() {
          _titulo = (data['title']?.toString().isNotEmpty == true)
              ? data['title'].toString()
              : _titulo;
          _backdrop = _firstUrl(data['backdrop_path']).isNotEmpty
              ? _firstUrl(data['backdrop_path'])
              : _backdrop;
          _logo = _firstUrl(data['logo_path']).isNotEmpty
              ? _firstUrl(data['logo_path'])
              : _logo;
          _loadingMeta = false;
        });
      } else {
        setState(() => _loadingMeta = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  String _firstUrl(dynamic value) {
    if (value == null) return '';
    final s = value.toString().trim();
    if (s.startsWith('http')) return s;
    if (s.startsWith('/')) return 'https://image.tmdb.org/t/p/w780$s';
    return '';
  }

  Future<void> _startFlow({bool forceRefresh = false}) async {
    final season = _isMovie ? 0 : _season;
    final episode = _isMovie ? 0 : _episode;
    final tmdb = _resolvedTmdbId;

    if (forceRefresh && mounted) {
      setState(() {
        _fromCache = false;
        _cacheAgeLabel = null;
      });
    }

    if (!forceRefresh) {
      final cached = await FuentesCache.loadServers(
        tmdbId: tmdb,
        tipo: _mediaType,
        season: season,
        episode: episode,
      );
      if (cached != null && cached.isNotEmpty && mounted) {
        final ageMs = await FuentesCache.serversCacheAgeMs(
          tmdbId: tmdb,
          tipo: _mediaType,
          season: season,
          episode: episode,
        );
        setState(() {
          _fromCache = true;
          _cacheAgeLabel = _formatCacheAge(ageMs);
        });
        _ingestCached(cached);
        return;
      }

      final fromServerLoader = await _loadServerLoaderCacheB(
        tmdbId: tmdb,
        season: season,
        episode: episode,
      );
      if (fromServerLoader != null && fromServerLoader.isNotEmpty && mounted) {
        setState(() {
          _fromCache = true;
          _cacheAgeLabel = 'ServerLoader';
        });
        _ingestCached(fromServerLoader);
        return;
      }
    }

    _runManual();
  }

  Future<List<Map<String, dynamic>>?> _loadServerLoaderCacheB({
    required int tmdbId,
    required int season,
    required int episode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idiomas = ['es_MX', 'es_ES', 'en_US', 'latino', 'castellano'];
      final merged = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final idioma in idiomas) {
        final key = 'srv_valid_${tmdbId}_${season}_${episode}_$idioma';
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final list = map['servidores'];
          if (list is! List) continue;
          for (final item in list) {
            if (item is! Map) continue;
            final m = Map<String, dynamic>.from(item);
            final url = m['servidor_url']?.toString() ??
                m['resolved_m3u8']?.toString() ??
                '';
            if (url.isEmpty || seen.contains(url)) continue;
            seen.add(url);
            merged.add(m);
          }
        } catch (_) {}
      }
      return merged.isEmpty ? null : merged;
    } catch (_) {
      return null;
    }
  }

  void _registerCustomMeta(Map<String, dynamic> map) {
    final fid = map['fuente_id']?.toString() ?? '';
    if (!fid.startsWith('custom_')) return;
    final label = map['fuente_label']?.toString();
    if (label != null && label.isNotEmpty) {
      _customLabels[fid] = label;
    }
    final colorRaw =
        map['fuente_color']?.toString() ?? map['badge_color']?.toString();
    if (colorRaw != null && colorRaw.isNotEmpty) {
      _customColors[fid] = _parseColor(colorRaw);
    }
  }

  void _addServerToBuckets(Map<String, dynamic> map, {FuenteId? eventFuente}) {
    _todos.add(map);

    final fid = map['fuente_id']?.toString() ?? '';
    final isCustom = map['es_customapi'] == true || fid.startsWith('custom_');

    if (isCustom && fid.startsWith('custom_')) {
      _registerCustomMeta(map);
      _porCustom.putIfAbsent(fid, () => []).add(map);
    } else {
      FuenteId? src = eventFuente;
      if (src == null || src == FuenteId.customapi || src == FuenteId.todos) {
        for (final f in FuenteId.values) {
          if (f.name == fid) {
            src = f;
            break;
          }
        }
      }
      src ??= eventFuente ?? FuenteId.todos;
      if (src != FuenteId.customapi) {
        _porFuente.putIfAbsent(src, () => []).add(map);
      }
    }

    final idioma = MainFuentes.normalizeIdioma(map['idioma']?.toString());
    _porIdioma.putIfAbsent(idioma, () => []).add(map);
  }

  void _ingestCached(List<Map<String, dynamic>> list) {
    for (final map in list) {
      final url = map['servidor_url']?.toString() ??
          map['resolved_m3u8']?.toString() ??
          '';
      if (url.isEmpty || _seenUrls.contains(url)) continue;
      _seenUrls.add(url);
      if ((map['servidor_url']?.toString() ?? '').isEmpty &&
          (map['resolved_m3u8']?.toString() ?? '').isNotEmpty) {
        map['servidor_url'] = map['resolved_m3u8'];
        map['verificado'] = true;
      }
      _addServerToBuckets(map);
    }
    setState(() {
      _scraping = false;
      for (final f in _cfg?.fuentesActivas ?? <FuenteId>[]) {
        _fuenteDone[f] = true;
      }
      _syncTabs(reorderByContent: true);
    });
    // Hidratar m3u8 frescos desde el caché por URL
    unawaited(_hydrateM3u8FromCache());
  }

  Future<void> _hydrateM3u8FromCache() async {
    final cache = await TvM3u8Cache.load(
      tmdbId: _resolvedTmdbId,
      tipo: _mediaType,
      season: _isMovie ? 0 : _season,
      episode: _isMovie ? 0 : _episode,
    );
    if (cache.isEmpty || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      for (final s in _todos) {
        final url = s['servidor_url']?.toString() ?? '';
        final entry = cache[url];
        if (entry != null && entry.m3u8.isNotEmpty) {
          s['resolved_m3u8'] = entry.m3u8;
          s['m3u8_ts'] = entry.ts;
          s['verificado'] = true;
        } else {
          final ts = s['m3u8_ts'];
          if (ts is! int || now - ts > TvM3u8Cache.ttlMs) {
            s.remove('resolved_m3u8');
            s.remove('m3u8_ts');
          }
        }
      }
    });
  }

  void _runManual() {
    setState(() {
      _scraping = true;
      _error = null;
      _todos.clear();
      _porFuente.clear();
      _porCustom.clear();
      _customLabels.clear();
      _customColors.clear();
      _porIdioma.clear();
      _seenUrls.clear();
      _fuenteDone.clear();
      _fuenteError.clear();
      _fromCache = false;
      _cacheAgeLabel = null;
    });
    _syncTabs();

    final tmdb = _resolvedTmdbId;
    if (tmdb <= 0) {
      setState(() {
        _scraping = false;
        _error = 'ID de contenido inválido';
      });
      return;
    }

    _sub?.cancel();
    _sub = _fuentes
        .fetchProgressive(
          tmdbId: tmdb,
          isMovie: _isMovie,
          season: _isMovie ? 1 : _season,
          episode: _isMovie ? 1 : _episode,
          context: context,
        )
        .listen(
          (event) {
            if (!mounted) return;
            if (event.isDone) {
              setState(() {
                _fuenteDone[event.fuente] = true;
                if (event.error != null) {
                  _fuenteError[event.fuente] = event.error;
                }
                _maybeReorderTabs();
                final activas = _cfg!.fuentesActivas;
                if (activas.every((f) => _fuenteDone[f] == true)) {
                  _scraping = false;
                  _persistCache(); // final
                  _schedulePreload();
                } else {
                  // Fuente terminó: guardar lo acumulado hasta ahora
                  unawaited(_persistCache());
                }
              });
              return;
            }

            final raw = event.servidor;
            if (raw == null) return;

            final map = Map<String, dynamic>.from(raw);
            final url = map['servidor_url']?.toString() ?? '';
            if (url.isEmpty || _seenUrls.contains(url)) return;

            // m3u8 resuelto por el verificador → guardar con timestamp
            final m3u8 = (event.resolvedM3u8 ??
                    map['resolved_m3u8']?.toString() ??
                    '')
                .trim();
            if (m3u8.isNotEmpty) {
              map['resolved_m3u8'] = m3u8;
              map['m3u8_ts'] = DateTime.now().millisecondsSinceEpoch;
              map['verificado'] = true;
              unawaited(TvM3u8Cache.save(
                tmdbId: _resolvedTmdbId,
                tipo: _mediaType,
                season: _isMovie ? 0 : _season,
                episode: _isMovie ? 0 : _episode,
                embedUrl: url,
                m3u8: m3u8,
              ));
            }

            _seenUrls.add(url);
            setState(() {
              _addServerToBuckets(map, eventFuente: event.fuente);
              _maybeReorderTabs();
            });
            // Guardar en caché YA (uno a uno), sin esperar el final
            unawaited(_persistCache());
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                _scraping = false;
                _error = e.toString().replaceFirst(
                      RegExp(r'^Exception:\s*'),
                      '',
                    );
              });
            }
          },
          onDone: () {
            if (mounted) {
              setState(() => _scraping = false);
              _persistCache();
            }
          },
        );
  }

  void _schedulePreload() {
    if (_isMovie) return;
    ServidoresPreloaderService.instance.scheduleFromEpisode(
      tmdbId: _resolvedTmdbId,
      season: _season,
      episode: _episode,
    );
  }

  Future<void> _persistCache() async {
    if (_todos.isEmpty) return;
    await FuentesCache.saveServers(
      tmdbId: _resolvedTmdbId,
      tipo: _mediaType,
      season: _isMovie ? 0 : _season,
      episode: _isMovie ? 0 : _episode,
      servidores: List.from(_todos),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Abrir servidor
  //   · m3u8 vigente (caché 1 h) o URL directa → PLAYER
  //   · m3u8 vencido / inexistente             → EXTRACTOR (WEBVIEW)
  // ═════════════════════════════════════════════════════════════════════════

  bool _isDirectUrl(String url) {
    final l = url.toLowerCase();
    return l.contains('.m3u8') || l.contains('.mp4');
  }

  bool _hasFreshM3u8(Map<String, dynamic> s) {
    final m = s['resolved_m3u8']?.toString() ?? '';
    if (m.isEmpty) return false;
    final ts = s['m3u8_ts'];
    if (ts is! int) return false;
    return DateTime.now().millisecondsSinceEpoch - ts <= TvM3u8Cache.ttlMs;
  }

  /// true = va al PLAYER nativo. false = va a WebPlayerView.
  bool _esPlayer(Map<String, dynamic> s) {
    if (_hasFreshM3u8(s)) return true;
    final url = s['servidor_url']?.toString() ?? '';
    return _isDirectUrl(url);
  }

  Future<void> _openServer(Map<String, dynamic> servidor) async {
    if (_navigating || !mounted) return;
    _navigating = true;

    final embedUrl = servidor['servidor_url']?.toString() ?? '';
    final nombre = servidor['servidor_nombre']?.toString() ?? 'Servidor';
    final idioma = servidor['idioma']?.toString();
    final tituloFinal = _titulo.isNotEmpty
        ? _titulo
        : (widget.titulo?.isNotEmpty == true ? widget.titulo! : 'Contenido');

    // m3u8 vigente (< 1h) desde el caché
    var m3u8 = '';
    if (embedUrl.isNotEmpty) {
      final cache = await TvM3u8Cache.load(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _isMovie ? 0 : _season,
        episode: _isMovie ? 0 : _episode,
      );
      m3u8 = cache[embedUrl]?.m3u8 ?? '';
    }
    if (m3u8.isEmpty && _hasFreshM3u8(servidor)) {
      m3u8 = servidor['resolved_m3u8'].toString();
    }

    final esDirecto = _isDirectUrl(embedUrl);
    final esPlayer = m3u8.isNotEmpty || esDirecto;
    final videoUrl = m3u8.isNotEmpty ? m3u8 : (esDirecto ? embedUrl : '');

    if (_cfg?.reutilizarUltimoEnlace == true) {
      final toSave = Map<String, dynamic>.from(servidor);
      if (m3u8.isNotEmpty) {
        toSave['resolved_m3u8'] = m3u8;
      } else {
        toSave.remove('resolved_m3u8');
      }
      await FuentesCache.saveLastLink(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _isMovie ? 0 : _season,
        episode: _isMovie ? 0 : _episode,
        servidor: toSave,
      );
    }

    if (!mounted) return;

    final nav = Navigator.of(context);

    // ── Descarga: siempre al ExtractorDownloadPage ────────────────────
    if (widget.forDownload) {
      final downloadRoute = MaterialPageRoute(
        builder: (_) => ExtractorDownloadPage(
          idcontenido: widget.idcontenido,
          temporada: _isMovie ? null : widget.temporada,
          capitulo: _isMovie ? null : widget.capitulo,
          servidorUrl: embedUrl,
          servidorNombre: nombre,
          tipo: _mediaType,
          titulo: tituloFinal,
          idServidor: servidor['id_servidor'] as int?,
          tmdbId: _resolvedTmdbId,
          posterUrl: widget.posterUrl,
          backdropUrl: _backdrop ?? widget.backdropUrl,
        ),
      );
      if (widget.fromPlayer) {
        nav.pop();
        nav.pushReplacement(downloadRoute);
      } else {
        nav.pushReplacement(downloadRoute);
      }
      _schedulePreload();
      return;
    }

    // ── PLAYER nativo (m3u8 fresco o URL directa) ─────────────────────
    if (esPlayer && videoUrl.isNotEmpty) {
      final route = MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoUrl: videoUrl,
          idcontenido: widget.idcontenido,
          tmdbId: _resolvedTmdbId,
          temporada: _isMovie ? null : widget.temporada,
          capitulo: _isMovie ? null : widget.capitulo,
          tipo: _mediaType,
          titulo: tituloFinal,
        ),
      );
      if (widget.fromPlayer) {
        nav.pop();
        nav.pushReplacement(route);
      } else {
        nav.pushReplacement(route);
      }
      _schedulePreload();
      return;
    }

    // ── WEBVIEW → WebPlayerView (ya no ExtractorPage) ─────────────────
    final webRoute = MaterialPageRoute(
      builder: (_) => WebPlayerView(
        idcontenido: widget.idcontenido,
        tmdbId: _resolvedTmdbId,
        temporada: _isMovie ? null : widget.temporada,
        capitulo: _isMovie ? null : widget.capitulo,
        servidorUrl: embedUrl,
        servidorNombre: nombre,
        tipo: _mediaType,
        titulo: tituloFinal,
        idioma: idioma,
        backdropUrl: _backdrop ?? widget.backdropUrl,
        posterUrl: widget.posterUrl,
      ),
    );
    if (widget.fromPlayer) {
      nav.pop();
      nav.pushReplacement(webRoute);
    } else {
      nav.pushReplacement(webRoute);
    }
    _schedulePreload();
  }

  String? _formatCacheAge(int? ageMs) {
    if (ageMs == null) return null;
    final sec = ageMs ~/ 1000;
    if (sec < 60) return 'hace ${sec}s';
    final min = sec ~/ 60;
    if (min < 60) return 'hace ${min}m';
    final h = min ~/ 60;
    if (h < 48) return 'hace ${h}h';
    return 'hace ${h ~/ 24}d';
  }

  String _formatTime(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
    }
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  Future<void> _loadResumeProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tmdb = _resolvedTmdbId;
      String? raw;
      if (_isMovie) {
        raw = prefs.getString('cachePlayer_$tmdb');
        raw ??= prefs.getString('cachePlayerRapido_$tmdb');
      } else {
        final t = _season;
        final c = _episode;
        raw = prefs.getString('cachePlayerRapido_${tmdb}_T${t}_C$c');
        raw ??= prefs.getString('cachePlayer_${tmdb}_T${t}_C$c');
        raw ??= prefs.getString('cachePlayer_$tmdb');
      }
      if (raw == null) return;
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final sec = data['segundo'] as int?;
      if (sec != null && sec > 5 && mounted) {
        setState(() => _resumeSec = sec);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
        title: Text(
          widget.forDownload ? 'Descargar' : 'Servidores',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_scraping)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kOrange,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Recargar',
            onPressed: _scraping ? null : _onReload,
            icon: Icon(
              Icons.refresh_rounded,
              color: _scraping ? Colors.white24 : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Configuración',
            onPressed: _openFuentesConfig,
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_backdrop != null && _backdrop!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _backdrop!,
              fit: BoxFit.cover,
              memCacheWidth: (size.width * 1.2).round().clamp(400, 900),
              errorWidget: (_, __, ___) => const ColoredBox(color: _kBg),
            )
          else
            const ColoredBox(color: _kBg),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.65),
                  Colors.black.withValues(alpha: 0.88),
                  _kBg,
                ],
                stops: const [0.0, 0.35, 1.0],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: MediaQuery.paddingOf(context).top + kToolbarHeight,
              ),
              _buildContentHeader(),
              if (_loadingConfig || (_scraping && _todos.isEmpty))
                Expanded(child: _buildLoadingBody())
              else if (_error != null && _todos.isEmpty)
                Expanded(child: _buildErrorBody())
              else ...[
                if (_tabController != null) _buildTabs(),
                Expanded(
                  child: _tabController == null
                      ? _buildServerList(_todos)
                      : TabBarView(
                          controller: _tabController,
                          children: _tabs.map((tab) {
                            if (tab.isTodos) {
                              return _buildServerList(_todos);
                            }
                            if (tab.isCustom) {
                              return _buildServerList(
                                _porCustom[tab.customId] ?? const [],
                              );
                            }
                            return _buildServerList(
                              _porFuente[tab.fuente] ?? const [],
                              fuente: tab.fuente,
                            );
                          }).toList(),
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContentHeader() {
    final seasonEp = (!_isMovie && widget.temporada != null)
        ? 'T${widget.temporada!.toString().padLeft(2, '0')} · E${(widget.capitulo ?? 1).toString().padLeft(2, '0')}'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 40,
            width: double.infinity,
            child: Center(
              child: (_logo != null && _logo!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: _logo!,
                      height: 40,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      memCacheHeight: 80,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) =>
                          const SizedBox(height: 40, width: 160),
                      errorWidget: (_, __, ___) => Text(
                        _titulo.isNotEmpty ? _titulo : 'Contenido',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : Text(
                      _titulo.isNotEmpty ? _titulo : 'Contenido',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          if (seasonEp != null) ...[
            const SizedBox(height: 8),
            Text(
              seasonEp,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_todos.length} servidor${_todos.length == 1 ? '' : 'es'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_fromCache && _cacheAgeLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Caché · $_cacheAgeLabel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (_resumeSec != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kOrange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Visto · ${_formatTime(_resumeSec!)}',
                    style: const TextStyle(
                      color: _kOrange,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (widget.forDownload)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Descarga',
                    style: TextStyle(
                      color: Color(0xFF64B5F6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onReload() async {
    _sub?.cancel();
    await Future.wait([
      FuentesCache.clearFor(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _isMovie ? 0 : _season,
        episode: _isMovie ? 0 : _episode,
      ),
      TvM3u8Cache.clear(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _isMovie ? 0 : _season,
        episode: _isMovie ? 0 : _episode,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _error = null;
      _todos.clear();
      _porFuente.clear();
      _porCustom.clear();
      _customLabels.clear();
      _customColors.clear();
      _porIdioma.clear();
      _seenUrls.clear();
      _fuenteDone.clear();
      _fuenteError.clear();
      _scraping = false;
      _navigating = false;
      _fromCache = false;
      _cacheAgeLabel = null;
    });
    _syncTabs();
    await _startFlow(forceRefresh: true);
  }

  void _openFuentesConfig() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const FuentesConfigScreen(),
          ),
        )
        .then((_) async {
          if (!mounted) return;
          await _loadUserPrefs();
          final cfg = await _fuentes.loadConfig();
          if (!mounted) return;
          setState(() => _cfg = cfg);
          _syncTabs();
        });
  }

  Widget _buildTabs() {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 4),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: _kAccent,
        indicatorWeight: 2.5,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        dividerColor: Colors.transparent,
        tabs: _tabs.map((t) {
          int count;
          bool done;
          if (t.isTodos) {
            count = _todos.length;
            done = _cfg?.fuentesActivas.every((f) => _fuenteDone[f] == true) ??
                false;
          } else if (t.isCustom) {
            count = _porCustom[t.customId]?.length ?? 0;
            done = _fuenteDone[FuenteId.customapi] == true;
          } else {
            count = _porFuente[t.fuente]?.length ?? 0;
            done = _fuenteDone[t.fuente] == true;
          }

          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: t.displayColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(t.displayLabel),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$count', style: const TextStyle(fontSize: 11)),
                  ),
                ] else if (!done && _scraping && !t.isTodos) ...[
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoadingBody() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: _kOrange, strokeWidth: 3.5),
          ),
          const SizedBox(height: 20),
          Text(
            'Buscando servidores…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 15,
            ),
          ),
          if (_cfg?.verificarServidores == true) ...[
            const SizedBox(height: 8),
            Text(
              'Verificando enlaces · $_concurrentChecks en paralelo',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kAccent, size: 52),
            const SizedBox(height: 14),
            Text(
              _error ?? 'No se encontraron servidores',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _error = null);
                _startFlow(forceRefresh: true);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerList(List<Map<String, dynamic>> list, {FuenteId? fuente}) {
    if (list.isEmpty) {
      final waiting =
          _scraping && (fuente == null || _fuenteDone[fuente] != true);
      if (waiting) {
        return const Center(
          child: CircularProgressIndicator(
            color: Colors.white38,
            strokeWidth: 2,
          ),
        );
      }
      final err = fuente != null ? _fuenteError[fuente] : null;
      return Center(
        child: Text(
          err ?? 'Sin servidores en esta fuente',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 14,
          ),
        ),
      );
    }

    // Agrupar por idioma
    final byLang = <String, List<Map<String, dynamic>>>{};
    for (final s in list) {
      final lang = MainFuentes.normalizeIdioma(s['idioma']?.toString());
      byLang.putIfAbsent(lang, () => []).add(s);
    }

    // ★ ORDENAR: primero PLAYER, luego WEBVIEW
    for (final entry in byLang.entries) {
      entry.value.sort((a, b) {
        final pa = _esPlayer(a) ? 0 : 1;
        final pb = _esPlayer(b) ? 0 : 1;
        return pa.compareTo(pb);
      });
    }

    // Idioma preferido (Settings) primero, luego LAT → ESP → EN → resto
    final langKeys = byLang.keys.toList()
      ..sort((a, b) => _langSortKey(a).compareTo(_langSortKey(b)));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: langKeys.length,
      itemBuilder: (ctx, i) {
        final lang = langKeys[i];
        final servers = byLang[lang]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Row(
                children: [
                  _langFlag(lang),
                  const SizedBox(width: 8),
                  Text(
                    MainFuentes.idiomaLabel(lang),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${servers.length})',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ...servers.map((s) => _serverTile(s)),
          ],
        );
      },
    );
  }

  String? _getLangFlagUrl(String? code) {
    if (code == null || code.isEmpty) return null;
    final c = code.toLowerCase().trim();
    if (c == 'es_es' || c == 'es-es' || c == 'esp' || c == 'castellano') {
      return 'https://embed69.org/static/lang/ESP.png';
    }
    if (c == 'es_mx' ||
        c == 'es-mx' ||
        c == 'es_la' ||
        c == 'es-la' ||
        c == 'lat' ||
        c == 'latino' ||
        c == 'es') {
      return 'https://embed69.org/static/lang/LAT.png';
    }
    if (c.startsWith('ja') || c == 'jap') {
      return 'https://embed69.org/static/lang/JAP.png';
    }
    if (c.startsWith('en') ||
        c.startsWith('pt') ||
        c.startsWith('fr') ||
        c.contains('sub')) {
      return 'https://embed69.org/static/lang/SUB.png';
    }
    return 'https://embed69.org/static/lang/SUB.png';
  }

  Widget _langFlag(String code, {double size = 22}) {
    final url = _getLangFlagUrl(code);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? ColoredBox(
              color: Colors.white.withValues(alpha: 0.1),
              child: const Icon(
                Icons.language,
                size: 12,
                color: Colors.white54,
              ),
            )
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: (size * 2).round(),
              memCacheHeight: (size * 2).round(),
              errorWidget: (_, __, ___) => ColoredBox(
                color: Colors.white.withValues(alpha: 0.1),
                child: Center(
                  child: Text(
                    MainFuentes.idiomaLabel(code).substring(0, 1),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _serverTile(Map<String, dynamic> s) {
    final nombre = s['servidor_nombre']?.toString() ?? 'Servidor';
    final calidad = s['calidad']?.toString() ?? 'HD';
    final verificado = s['verificado'] == true;
    final fuenteLabel = s['fuente_label']?.toString();
    final idioma = MainFuentes.normalizeIdioma(s['idioma']?.toString());
    final esPlayer = _esPlayer(s);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openServer(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                _langFlag(idioma, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // ★ ETIQUETA PLAYER / WEBVIEW
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: esPlayer
                                  ? const Color(0xFF22C55E)
                                      .withValues(alpha: 0.16)
                                  : const Color(0xFF3B82F6)
                                      .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: esPlayer
                                    ? const Color(0xFF22C55E)
                                        .withValues(alpha: 0.5)
                                    : const Color(0xFF3B82F6)
                                        .withValues(alpha: 0.5),
                                width: 0.7,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  esPlayer
                                      ? Icons.play_circle_fill_rounded
                                      : Icons.language_rounded,
                                  size: 11,
                                  color: esPlayer
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFF3B82F6),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  esPlayer ? 'PLAYER' : 'WEBVIEW',
                                  style: TextStyle(
                                    color: esPlayer
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFF3B82F6),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              [
                                MainFuentes.idiomaLabel(idioma),
                                if (fuenteLabel != null) fuenteLabel,
                                calidad,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          if (verificado) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.9),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}