import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/aggregators/source_aggregator.dart';
import '../../../data/datasources/remote/tmdb/tmdb_content.dart';
import '../../player/data/extractor.dart';
import '../../player/presentation/tv/tv_player_page.dart';
import 'tv_server_preloader_service.dart';
import '../../player/presentation/tv/tv_player_webview.dart';

const _kAccent = Color(0xFFE50914);
const _kOrange = Color(0xFFFF6B00);
const _kPanel = Color(0x1A141416);
const _kCard = Color(0x4D1C1C1E);
const _kBg = Color(0xFF0A0A0A);
const _kGreen = Color(0xFF22C55E);
const _kBlue = Color(0xFF3B82F6);
const double _kItemExtent = 78.0;

const bool _kHideEmptyTabs = true;

// ═══════════════════════════════════════════════════════════════════════════
// CACHÉ 2 · M3U8 (1 hora)
// ═══════════════════════════════════════════════════════════════════════════

class TvM3u8Entry {
  final String m3u8;
  final int ts;
  const TvM3u8Entry(this.m3u8, this.ts);
}

class TvM3u8Cache {
  TvM3u8Cache._();

  static const int ttlMs = 60 * 60 * 1000;

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

// ═══════════════════════════════════════════════════════════════════════════
// CACHÉ 1 · SERVIDORES (2 días)
// ═══════════════════════════════════════════════════════════════════════════

class TvCachedServers {
  final List<Map<String, dynamic>> servers;
  final int ageMs;
  final bool complete;

  const TvCachedServers(this.servers, this.ageMs, this.complete);
}

class TvServersCache {
  TvServersCache._();

  static const int ttlMs = 2 * 24 * 60 * 60 * 1000;

  static String _key({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) =>
      'tv_valid_servers_v1_${tmdbId}_${tipo}_${season}_$episode';

  static Future<void> save({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
    required List<Map<String, dynamic>> servidores,
    required bool complete,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clean = servidores.map((s) {
        final m = Map<String, dynamic>.from(s);
        m.remove('resolved_m3u8');
        m.remove('m3u8_ts');
        return m;
      }).toList();
      await prefs.setString(
        _key(tmdbId: tmdbId, tipo: tipo, season: season, episode: episode),
        jsonEncode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'complete': complete,
          'servidores': clean,
        }),
      );
    } catch (_) {}
  }

  static Future<TvCachedServers?> load({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key =
          _key(tmdbId: tmdbId, tipo: tipo, season: season, episode: episode);
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final ts = map['ts'];
      if (ts is! int) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > ttlMs) {
        await prefs.remove(key);
        return null;
      }
      final list = map['servidores'];
      if (list is! List) return null;
      final servers = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (servers.isEmpty) return null;
      return TvCachedServers(servers, age, map['complete'] == true);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear({
    required int tmdbId,
    required String tipo,
    int season = 0,
    int episode = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(
        _key(tmdbId: tmdbId, tipo: tipo, season: season, episode: episode),
      );
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Pestañas
// ═══════════════════════════════════════════════════════════════════════════

class _TabKey {
  final FuenteId? fuente;
  final String? customId;
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
        label = '',
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

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ServidoresModalTv extends StatefulWidget {
  final int idcontenido;
  final int? tmdbId;
  final int? temporada;
  final int? capitulo;
  final String? tipo;
  final String? titulo;
  final bool fromPlayer;
  final bool esSiguienteCapitulo;
  final String? backdropUrl;
  final String? posterUrl;
  final String? logoUrl;
  final String? currentIdioma;
  final String? currentServidorUrl;
  final String? currentServidorNombre;

  const ServidoresModalTv({
    super.key,
    required this.idcontenido,
    this.tmdbId,
    this.temporada,
    this.capitulo,
    this.tipo,
    this.titulo,
    this.fromPlayer = false,
    this.esSiguienteCapitulo = false,
    this.backdropUrl,
    this.posterUrl,
    this.logoUrl,
    this.currentIdioma,
    this.currentServidorUrl,
    this.currentServidorNombre,
  });

  @override
  State<ServidoresModalTv> createState() => _ServidoresModalTvState();
}

class _ServidoresModalTvState extends State<ServidoresModalTv> {
  final MainFuentes _fuentes = MainFuentes();
  final TmdbContentService _tmdb = TmdbContentService();

  FuentesConfig? _cfg;
  bool _loadingConfig = true;
  bool _scraping = false;
  bool _navigating = false;

  bool _scrapeComplete = false;
  bool _finishHandled = false;

  bool _dirty = false;
  Timer? _persistTimer;

  String? _error;
  String? _backdrop;
  String? _logo;
  String _titulo = '';

  final Map<FuenteId, List<Map<String, dynamic>>> _porFuente = {};
  final Map<String, List<Map<String, dynamic>>> _porCustom = {};
  final Map<String, String> _customLabels = {};
  final Map<String, Color> _customColors = {};

  final List<Map<String, dynamic>> _todos = [];
  final Map<String, List<Map<String, dynamic>>> _porIdioma = {};
  final Set<String> _seenUrls = {};
  final Map<FuenteId, bool> _fuenteDone = {};
  final Map<FuenteId, String?> _fuenteError = {};

  List<_TabKey> _tabs = [const _TabKey.todos()];
  int _selectedTab = 0;

  /// Dos streams: listado + verificación
  final List<StreamSubscription<FuenteEvent>> _subs = [];

  int? _resumeSec;
  bool _fromCache = false;
  String? _cacheAgeLabel;

  final FocusNode _closeFocus = FocusNode(debugLabel: 'close');
  final FocusNode _reloadFocus = FocusNode(debugLabel: 'reload');
  final List<FocusNode> _tabFocus = [];
  final List<FocusNode> _cardFocus = [];
  final ScrollController _listScroll = ScrollController();
  final ScrollController _tabsScroll = ScrollController();
  int _lastCardIndex = 0;

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

  int get _cSeason => _isMovie ? 0 : _season;
  int get _cEpisode => _isMovie ? 0 : _episode;

  List<Map<String, dynamic>> _listFor(_TabKey tab) {
    List<Map<String, dynamic>> raw;
    if (tab.isTodos) {
      raw = _todos;
    } else if (tab.isCustom) {
      raw = _porCustom[tab.customId] ?? const [];
    } else {
      raw = _porFuente[tab.fuente] ?? const [];
    }
    // PLAYER primero, WEBVIEW al final
    return List<Map<String, dynamic>>.from(raw)
      ..sort((a, b) {
        final aPlayer = _isPlayerServer(a);
        final bPlayer = _isPlayerServer(b);
        if (aPlayer == bPlayer) return 0;
        return aPlayer ? -1 : 1;
      });
  }

  List<Map<String, dynamic>> get _currentList {
    if (_tabs.isEmpty) return _listFor(const _TabKey.todos());
    return _listFor(_tabs[_selectedTab.clamp(0, _tabs.length - 1)]);
  }

  bool _isPlayerServer(Map<String, dynamic> s) {
    final url = s['servidor_url']?.toString() ?? '';
    return _hasFreshM3u8(s) || _isDirectUrl(url);
  }

  @override
  void initState() {
    super.initState();
    _titulo = widget.titulo?.trim().isNotEmpty == true
        ? widget.titulo!.trim()
        : '';
    _backdrop = widget.backdropUrl ?? widget.posterUrl;
    _logo = widget.logoUrl;
    _ensureTabNodes();
    _bootstrap();
    _loadResumeProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _closeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _persistTimer?.cancel();
    if (_dirty && _todos.isNotEmpty) {
      unawaited(_persistNow());
    }
    _closeFocus.dispose();
    _reloadFocus.dispose();
    _listScroll.dispose();
    _tabsScroll.dispose();
    for (final n in _tabFocus) {
      n.dispose();
    }
    for (final n in _cardFocus) {
      n.dispose();
    }
    super.dispose();
  }

  void _ensureTabNodes() {
    while (_tabFocus.length < _tabs.length) {
      _tabFocus.add(FocusNode(debugLabel: 'tab${_tabFocus.length}'));
    }
  }

  void _ensureCardNodes(int needed) {
    while (_cardFocus.length < needed) {
      _cardFocus.add(FocusNode(debugLabel: 'card${_cardFocus.length}'));
    }
  }

  void _tryInheritFocusToList() {
    if (!widget.esSiguienteCapitulo && !widget.fromPlayer) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentList.isEmpty) return;
      _focusCurrentOrFirst();
    });
  }

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

  void _syncTabs() {
    final activas = _cfg?.fuentesActivas ?? <FuenteId>[];

    final withContent = <FuenteId>[];
    final empty = <FuenteId>[];
    for (final f in activas) {
      if (f == FuenteId.customapi) continue;
      if ((_porFuente[f]?.length ?? 0) > 0) {
        withContent.add(f);
      } else if (!_kHideEmptyTabs || _fuenteDone[f] != true) {
        empty.add(f);
      }
    }

    final customKeys = _porCustom.keys.toList()..sort();

    final next = <_TabKey>[
      const _TabKey.todos(),
      ...withContent.map((f) => _TabKey.fuente(f)),
      ...empty.map((f) => _TabKey.fuente(f)),
      ...customKeys.map(
        (k) => _TabKey.custom(
          customId: k,
          label: _customLabels[k] ?? k.replaceFirst('custom_', 'API '),
          color: _customColors[k] ?? const Color(0xFF60A5FA),
        ),
      ),
    ];

    _setTabs(next);
  }

  void _setTabs(List<_TabKey> next) {
    final same = next.length == _tabs.length &&
        List.generate(next.length, (i) => next[i] == _tabs[i]).every((e) => e);

    if (same) {
      _tabs = next;
      return;
    }

    final current = _tabs[_selectedTab.clamp(0, _tabs.length - 1)];
    _tabs = next;
    final idx = _tabs.indexOf(current);
    _selectedTab = idx >= 0 ? idx : 0;
    _ensureTabNodes();
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

  Future<void> _bootstrap() async {
    try {
      final cfg = await _fuentes.loadConfig();
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _loadingConfig = false;
        _syncTabs();
      });
      if (_backdrop == null || _backdrop!.isEmpty || _titulo.isEmpty) {
        _loadMeta();
      }
      await _startFlow();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingConfig = false;
          _error = e.toString();
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
          if (_titulo.isEmpty) {
            _titulo = data['title']?.toString() ?? 'Contenido';
          }
          final bd = _firstUrl(data['backdrop_path']);
          final pt = _firstUrl(data['poster_path']);
          final lg = _firstUrl(data['logo_path']);
          if ((_backdrop == null || _backdrop!.isEmpty) && bd.isNotEmpty) {
            _backdrop = bd;
          } else if ((_backdrop == null || _backdrop!.isEmpty) &&
              pt.isNotEmpty) {
            _backdrop = pt;
          }
          if ((_logo == null || _logo!.isEmpty) && lg.isNotEmpty) {
            _logo = lg;
          }
        });
      }
    } catch (_) {}
  }

  String _firstUrl(dynamic value) {
    if (value == null) return '';
    final str = value.toString().trim();
    if (str.startsWith('http') && !str.contains('[')) return str;
    final match = RegExp(r'https?:\\?/\\?/[^\s,"\]\\]+').firstMatch(str);
    if (match != null) {
      return match.group(0)!.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');
    }
    return '';
  }

  Future<void> _startFlow({bool forceRefresh = false}) async {
    final cfg = _cfg!;

    if (forceRefresh && mounted) {
      setState(() {
        _fromCache = false;
        _cacheAgeLabel = null;
      });
    }

    if (!forceRefresh) {
      if (cfg.reutilizarUltimoEnlace && widget.esSiguienteCapitulo) {
        final last = await _fuentes.tryReuseLastLink(
          tmdbId: _resolvedTmdbId,
          tipo: _mediaType,
          season: _cSeason,
          episode: _cEpisode,
          context: context,
        );
        if (last != null && mounted) {
          await _openServer(last);
          return;
        }
      }

      final cached = await _loadValidServersCache();
      if (!mounted) return;
      if (cached != null && cached.servers.isNotEmpty) {
        final merged = await _mergeM3u8Cache(cached.servers);
        if (!mounted) return;
        setState(() {
          _fromCache = true;
          _cacheAgeLabel = _formatCacheAge(cached.ageMs);
        });
        _ingestCached(merged, markDone: cached.complete);
        _tryInheritFocusToList();

        if (!cached.complete) _runManual(preserve: true);
        return;
      }
    }

    _runManual();
  }

  Future<TvCachedServers?> _loadValidServersCache() async {
    final own = await TvServersCache.load(
      tmdbId: _resolvedTmdbId,
      tipo: _mediaType,
      season: _cSeason,
      episode: _cEpisode,
    );
    if (own != null && own.servers.isNotEmpty) return own;

    try {
      final list = await FuentesCache.loadServers(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _cSeason,
        episode: _cEpisode,
      );
      if (list == null || list.isEmpty) return null;
      final ageMs = await FuentesCache.serversCacheAgeMs(
            tmdbId: _resolvedTmdbId,
            tipo: _mediaType,
            season: _cSeason,
            episode: _cEpisode,
          ) ??
          0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final all = <Map<String, dynamic>>[];
      for (final s in list) {
        final m = Map<String, dynamic>.from(s);
        final hasM3u8 = (m['resolved_m3u8']?.toString() ?? '').isNotEmpty;
        if (hasM3u8 && ageMs <= TvM3u8Cache.ttlMs) {
          m['m3u8_ts'] = now - ageMs;
        } else {
          m.remove('resolved_m3u8');
          m.remove('m3u8_ts');
        }
        all.add(m);
      }
      if (all.isEmpty) return null;
      return TvCachedServers(all, ageMs, true);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _mergeM3u8Cache(
    List<Map<String, dynamic>> list,
  ) async {
    final cache = await TvM3u8Cache.load(
      tmdbId: _resolvedTmdbId,
      tipo: _mediaType,
      season: _cSeason,
      episode: _cEpisode,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    return list.map((s) {
      final m = Map<String, dynamic>.from(s);
      final url = m['servidor_url']?.toString() ?? '';
      final entry = cache[url];

      if (entry != null && entry.m3u8.isNotEmpty) {
        m['resolved_m3u8'] = entry.m3u8;
        m['m3u8_ts'] = entry.ts;
      } else {
        final own = m['resolved_m3u8']?.toString() ?? '';
        final ts = m['m3u8_ts'];
        final fresh = own.isNotEmpty &&
            ts is int &&
            now - ts <= TvM3u8Cache.ttlMs;
        if (!fresh) {
          m.remove('resolved_m3u8');
          m.remove('m3u8_ts');
        }
      }
      return m;
    }).toList();
  }

  void _schedulePersist() {
    _dirty = true;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 1200), _persistNow);
  }

  Future<void> _persistNow({bool force = false}) async {
    _persistTimer?.cancel();
    if (_todos.isEmpty) return;
    if (!force && !_dirty) return;
    _dirty = false;

    final snapshot =
        _todos.map((e) => Map<String, dynamic>.from(e)).toList();
    await TvServersCache.save(
      tmdbId: _resolvedTmdbId,
      tipo: _mediaType,
      season: _cSeason,
      episode: _cEpisode,
      servidores: snapshot,
      complete: _scrapeComplete,
    );
  }

  bool _hasFreshM3u8(Map<String, dynamic> s) {
    final m = s['resolved_m3u8']?.toString() ?? '';
    if (m.isEmpty) return false;
    final ts = s['m3u8_ts'];
    if (ts is! int) return false;
    return DateTime.now().millisecondsSinceEpoch - ts <= TvM3u8Cache.ttlMs;
  }

  bool _isDirectUrl(String url) {
    final l = url.toLowerCase();
    return l.contains('.m3u8') || l.contains('.mp4');
  }

  void _ingestCached(
    List<Map<String, dynamic>> list, {
    required bool markDone,
  }) {
    setState(() {
      for (final map in list) {
        final url = map['servidor_url']?.toString() ?? '';
        if (url.isEmpty || _seenUrls.contains(url)) continue;
        _seenUrls.add(url);
        _addServerToBuckets(map);
      }
      if (markDone) {
        _scrapeComplete = true;
        _scraping = false;
        for (final f in _cfg?.fuentesActivas ?? <FuenteId>[]) {
          _fuenteDone[f] = true;
        }
      }
      _syncTabs();
    });
    _ensureCardNodes(_currentList.length);
  }

  /// Verifica SIEMPRE (HLS → PLAYER).
  /// Sin HLS → se lista igual como WEBVIEW.
  void _runManual({bool preserve = false}) {
    final tmdb = _resolvedTmdbId;
    if (tmdb <= 0) {
      setState(() {
        _scraping = false;
        _error = 'ID de contenido inválido';
      });
      return;
    }

    setState(() {
      _scraping = true;
      _error = null;
      _scrapeComplete = false;
      _finishHandled = false;
      if (!preserve) {
        _todos.clear();
        _porFuente.clear();
        _porCustom.clear();
        _customLabels.clear();
        _customColors.clear();
        _porIdioma.clear();
        _seenUrls.clear();
        _fromCache = false;
        _cacheAgeLabel = null;
      }
      _fuenteDone.clear();
      _fuenteError.clear();
      _syncTabs();
    });

    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();

    var finishedStreams = 0;
    void markStreamFinished() {
      finishedStreams++;
      if (finishedStreams >= 2) {
        _onScrapeFinished();
      }
    }

    void onFuenteDone(FuenteEvent event) {
      setState(() {
        _fuenteDone[event.fuente] = true;
        if (event.error != null) {
          _fuenteError[event.fuente] = event.error;
        }
        _syncTabs();
      });
    }

    void ingestServer(Map<String, dynamic> raw, {FuenteId? eventFuente}) {
      final map = Map<String, dynamic>.from(raw);
      final url = map['servidor_url']?.toString() ?? '';
      if (url.isEmpty) return;

      final m3u8 = (map['resolved_m3u8']?.toString() ?? '').trim();

      // Ya listado: upgrade WEBVIEW → PLAYER si llega m3u8
      if (_seenUrls.contains(url)) {
        if (m3u8.isEmpty) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        setState(() {
          void upgrade(List<Map<String, dynamic>> list) {
            for (final s in list) {
              if (s['servidor_url']?.toString() == url) {
                s['resolved_m3u8'] = m3u8;
                s['m3u8_ts'] = now;
                s['verificado'] = true;
              }
            }
          }

          upgrade(_todos);
          for (final l in _porFuente.values) {
            upgrade(l);
          }
          for (final l in _porCustom.values) {
            upgrade(l);
          }
          _syncTabs();
        });
        unawaited(TvM3u8Cache.save(
          tmdbId: _resolvedTmdbId,
          tipo: _mediaType,
          season: _cSeason,
          episode: _cEpisode,
          embedUrl: url,
          m3u8: m3u8,
        ));
        _schedulePersist();
        return;
      }

      _seenUrls.add(url);

      if (m3u8.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        map['resolved_m3u8'] = m3u8;
        map['m3u8_ts'] = now;
        map['verificado'] = true;
        unawaited(TvM3u8Cache.save(
          tmdbId: _resolvedTmdbId,
          tipo: _mediaType,
          season: _cSeason,
          episode: _cEpisode,
          embedUrl: url,
          m3u8: m3u8,
        ));
      } else {
        map.remove('resolved_m3u8');
        map.remove('m3u8_ts');
      }

      final wasEmpty = _todos.isEmpty;
      setState(() {
        _addServerToBuckets(map, eventFuente: eventFuente);
        _syncTabs();
      });
      _ensureCardNodes(_currentList.length);
      _schedulePersist();
      if (wasEmpty) _tryInheritFocusToList();
    }

    void onEvent(FuenteEvent event) {
      if (!mounted) return;
      if (event.isDone) {
        onFuenteDone(event);
        return;
      }
      final raw = event.servidor;
      if (raw == null) return;

      final map = Map<String, dynamic>.from(raw);
      final m3u8 =
          (event.resolvedM3u8 ?? raw['resolved_m3u8']?.toString() ?? '')
              .trim();
      if (m3u8.isNotEmpty) {
        map['resolved_m3u8'] = m3u8;
      }
      ingestServer(map, eventFuente: event.fuente);
    }

    // Stream 1: listado completo (sin exigir HLS)
    _subs.add(
      _fuentes
          .fetchProgressive(
            tmdbId: tmdb,
            isMovie: _isMovie,
            season: _isMovie ? 1 : _season,
            episode: _isMovie ? 1 : _episode,
            context: context,
            forzarVerificar: false,
          )
          .listen(
            onEvent,
            onError: (_) {
              if (mounted) markStreamFinished();
            },
            onDone: () {
              if (mounted) markStreamFinished();
            },
          ),
    );

    // Stream 2: verificación SIEMPRE → HLS → PLAYER
    _subs.add(
      _fuentes
          .fetchProgressive(
            tmdbId: tmdb,
            isMovie: _isMovie,
            season: _isMovie ? 1 : _season,
            episode: _isMovie ? 1 : _episode,
            context: context,
            forzarVerificar: true,
          )
          .listen(
            onEvent,
            onError: (_) {
              if (mounted) markStreamFinished();
            },
            onDone: () {
              if (mounted) markStreamFinished();
            },
          ),
    );
  }

  void _onScrapeFinished() {
    if (_finishHandled || !mounted) return;
    _finishHandled = true;
    setState(() {
      _scraping = false;
      _scrapeComplete = true;
      if (_todos.isEmpty && _error == null) {
        _error = 'No se encontraron servidores';
      }
      _syncTabs();
    });
    _persistNow(force: true);
    _schedulePreload();
  }

  void _schedulePreload() {
    if (_isMovie) return;
    ServidoresPreloaderService.instance.scheduleFromEpisode(
      tmdbId: _resolvedTmdbId,
      season: _season,
      episode: _episode,
    );
  }

  Future<void> _openServer(Map<String, dynamic> servidor) async {
    if (_navigating || !mounted) return;
    _navigating = true;

    if (_dirty && _todos.isNotEmpty) unawaited(_persistNow());

    final embedUrl = servidor['servidor_url']?.toString() ?? '';
    final nombre = servidor['servidor_nombre']?.toString() ?? 'Servidor';
    final idioma = servidor['idioma']?.toString();
    final tituloFinal = _titulo.isNotEmpty
        ? _titulo
        : (widget.titulo?.isNotEmpty == true ? widget.titulo! : 'Contenido');

    var m3u8 = '';
    if (embedUrl.isNotEmpty) {
      final cache = await TvM3u8Cache.load(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _cSeason,
        episode: _cEpisode,
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
        season: _cSeason,
        episode: _cEpisode,
        servidor: toSave,
      );
    }

    if (!mounted) return;

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
      final nav = Navigator.of(context);
      if (widget.fromPlayer) {
        nav.pop();
        nav.pushReplacement(route);
      } else {
        nav.pushReplacement(route);
      }
      _schedulePreload();
      return;
    }

    final webviewRoute = MaterialPageRoute(
      builder: (_) => TvPlayerWebViewPage(
        url: embedUrl,
        title: tituloFinal,
        servidorNombre: nombre,
        idioma: idioma,
        idcontenido: widget.idcontenido,
        tmdbId: _resolvedTmdbId,
        temporada: _isMovie ? null : widget.temporada,
        capitulo: _isMovie ? null : widget.capitulo,
        tipo: _mediaType,
      ),
    );

    final navigator = Navigator.of(context);
    if (widget.fromPlayer) {
      navigator.pop();
      navigator.pushReplacement(webviewRoute);
    } else {
      navigator.pushReplacement(webviewRoute);
    }
    _schedulePreload();
  }

  Future<void> _onReload() async {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _persistTimer?.cancel();
    _dirty = false;

    await Future.wait([
      TvServersCache.clear(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _cSeason,
        episode: _cEpisode,
      ),
      TvM3u8Cache.clear(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _cSeason,
        episode: _cEpisode,
      ),
      FuentesCache.clearFor(
        tmdbId: _resolvedTmdbId,
        tipo: _mediaType,
        season: _cSeason,
        episode: _cEpisode,
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
      _scrapeComplete = false;
      _finishHandled = false;
      _fromCache = false;
      _cacheAgeLabel = null;
      _selectedTab = 0;
      _syncTabs();
    });
    await _startFlow(forceRefresh: true);
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

  int _countFor(_TabKey t) {
    if (t.isTodos) return _todos.length;
    return _listFor(t).length;
  }

  bool _doneFor(_TabKey t) {
    if (t.isTodos) {
      return _cfg?.fuentesActivas.every((f) => _fuenteDone[f] == true) ??
          false;
    }
    if (t.isCustom) return _fuenteDone[FuenteId.customapi] == true;
    return _fuenteDone[t.fuente] == true;
  }

  void _go(FocusNode node) {
    if (!node.canRequestFocus) return;
    node.requestFocus();
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
    _ensureCardNodes(_currentList.length);
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
  }

  void _focusCard(int idx) {
    final n = _currentList.length;
    if (n == 0) return;
    final i = idx.clamp(0, n - 1);
    _ensureCardNodes(n);
    _lastCardIndex = i;
    _ensureCardVisible(i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || i >= _cardFocus.length) return;
      _cardFocus[i].requestFocus();
    });
  }

  void _focusCurrentOrFirst() {
    final current = widget.currentServidorUrl;
    if (current != null && current.isNotEmpty) {
      final idx = _currentList.indexWhere(
        (s) => s['servidor_url']?.toString() == current,
      );
      if (idx >= 0) {
        _focusCard(idx);
        return;
      }
    }
    _focusFirstCard();
  }

  void _focusFirstCard() {
    if (_currentList.isEmpty) return;
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
    _focusCard(0);
  }

  void _focusTabsOrClose() {
    if (_tabFocus.isNotEmpty) {
      _go(_tabFocus[_selectedTab.clamp(0, _tabFocus.length - 1)]);
    } else {
      _go(_closeFocus);
    }
  }

  KeyEventResult _onCloseKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(_reloadFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_tabFocus.isNotEmpty) {
        _focusTabsOrClose();
      } else if (_currentList.isNotEmpty) {
        _focusFirstCard();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onReloadKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(_closeFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_tabFocus.isNotEmpty) {
        _focusTabsOrClose();
      } else if (_currentList.isNotEmpty) {
        _focusFirstCard();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (!_scraping) _onReload();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onTabKey(int index, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _go(_tabFocus[index - 1]);
      } else {
        _go(_closeFocus);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < _tabs.length - 1) _go(_tabFocus[index + 1]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _go(_closeFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      _selectTab(index);
      _focusCurrentOrFirst();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onCardKey(int index, FocusNode node, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final list = _currentList;
    _ensureCardNodes(list.length);

    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _lastCardIndex = index - 1;
        _go(_cardFocus[index - 1]);
        _ensureCardVisible(index - 1);
      } else if (isDown) {
        _focusTabsOrClose();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < list.length - 1) {
        _lastCardIndex = index + 1;
        _go(_cardFocus[index + 1]);
        _ensureCardVisible(index + 1);
      }
      return KeyEventResult.handled;
    }
    if (!isDown) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _focusTabsOrClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (index < list.length) _openServer(list[index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _ensureCardVisible(int index) {
    if (!_listScroll.hasClients) return;
    final pos = _listScroll.position;
    final top = index * _kItemExtent;
    final bottom = top + _kItemExtent;
    final viewTop = pos.pixels;
    final viewBottom = viewTop + pos.viewportDimension;
    double? target;
    if (top < viewTop) {
      target = top - 8;
    } else if (bottom > viewBottom) {
      target = bottom - pos.viewportDimension + 8;
    }
    if (target != null) {
      _listScroll.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelW = (size.width * 0.60).clamp(420.0, 900.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_backdrop != null && _backdrop!.isNotEmpty)
            RepaintBoundary(
              child: CachedNetworkImage(
                imageUrl: _backdrop!,
                fit: BoxFit.cover,
                memCacheWidth: (size.width * 0.85).round().clamp(400, 960),
                fadeInDuration: Duration.zero,
                errorWidget: (_, _, _) => const ColoredBox(color: _kBg),
              ),
            )
          else
            const ColoredBox(color: _kBg),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.black45, Colors.black87, Color(0xF2000000)],
                stops: [0.0, 0.32, 0.55],
              ),
            ),
          ),
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 32, 24, 32),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_logo != null && _logo!.isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: CachedNetworkImage(
                                  imageUrl: _logo!,
                                  height: 72,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.centerLeft,
                                  memCacheHeight: 144,
                                  fadeInDuration: Duration.zero,
                                  errorWidget: (_, _, _) => _titleText(),
                                ),
                              )
                            else
                              _titleText(),
                            if (!_isMovie && widget.temporada != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                'T${widget.temporada!.toString().padLeft(2, '0')} · E${(widget.capitulo ?? 1).toString().padLeft(2, '0')}',
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.start,
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                if (_resumeSec != null)
                                  _metaChip(
                                    'Retomar · ${_formatTime(_resumeSec!)}',
                                    accent: true,
                                  ),
                                if (_fromCache && _cacheAgeLabel != null)
                                  _metaChip('Caché · $_cacheAgeLabel'),
                                _metaChip(
                                  '${_todos.length} servidor${_todos.length == 1 ? '' : 'es'}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                      child: Container(
                        width: panelW,
                        decoration: BoxDecoration(
                          color: _kPanel,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildTopBar(),
                            _buildTabsRow(),
                            Expanded(child: _buildBody()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleText() {
    return Text(
      _titulo.isNotEmpty ? _titulo : 'Servidores',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.left,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 1.12,
      ),
    );
  }

  Widget _metaChip(String label, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent
            ? _kOrange.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? _kOrange : Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      child: Row(
        children: [
          _tvIconButton(
            focusNode: _closeFocus,
            icon: Icons.close_rounded,
            onKey: _onCloseKey,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Text(
            'Servidores',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (_scraping)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kOrange,
                ),
              ),
            ),
          _tvIconButton(
            focusNode: _reloadFocus,
            icon: Icons.refresh_rounded,
            enabled: !_scraping,
            onKey: _onReloadKey,
            onTap: _scraping ? null : _onReload,
          ),
        ],
      ),
    );
  }

  Widget _tvIconButton({
    required FocusNode focusNode,
    required IconData icon,
    required KeyEventResult Function(FocusNode, KeyEvent) onKey,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKey,
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: hasFocus
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2.2,
                ),
              ),
              child: Icon(
                icon,
                color: enabled
                    ? (hasFocus ? Colors.white : Colors.white70)
                    : Colors.white24,
                size: 24,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabsRow() {
    if (_tabs.isEmpty) return const SizedBox.shrink();
    _ensureTabNodes();
    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        controller: _tabsScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _tabs.length; i++) _buildTab(i),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int i) {
    final tab = _tabs[i];
    final selected = i == _selectedTab;
    final count = _countFor(tab);
    final done = _doneFor(tab);
    final color = tab.displayColor;

    return Focus(
      focusNode: _tabFocus[i],
      onKeyEvent: (n, e) => _onTabKey(i, n, e),
      onFocusChange: (has) {
        if (!has) return;
        final ctx = _tabFocus[i].context;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: Duration.zero,
            alignment: 0.45,
          );
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              _selectTab(i);
              _focusFirstCard();
            },
            child: Container(
              height: 36,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : (selected
                          ? color.withValues(alpha: 0.75)
                          : Colors.transparent),
                  width: hasFocus ? 2.2 : 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tab.displayLabel,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 7),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12.5,
                      ),
                    ),
                  ] else if (!done && _scraping && !tab.isTodos)
                    const Padding(
                      padding: EdgeInsets.only(left: 7),
                      child: SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String? _flagUrl(String code) {
    final c = code.toLowerCase().trim();
    if (c == 'es_es' || c.contains('castellano')) {
      return 'https://embed69.org/static/lang/ESP.png';
    }
    if (c == 'es_mx' || c == 'lat' || c == 'es' || c.contains('latino')) {
      return 'https://embed69.org/static/lang/LAT.png';
    }
    if (c.startsWith('ja')) {
      return 'https://embed69.org/static/lang/JAP.png';
    }
    return 'https://embed69.org/static/lang/SUB.png';
  }

  Widget _langFlag(String code, {double size = 36}) {
    final url = _flagUrl(code);
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: Colors.white.withValues(alpha: 0.08),
          child: url == null
              ? Icon(Icons.language, size: size * 0.4, color: Colors.white54)
              : CachedNetworkImage(
                  imageUrl: url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  memCacheWidth: (size * 3).round(),
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, _, _) => Icon(
                    Icons.language,
                    size: size * 0.4,
                    color: Colors.white54,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingConfig || (_scraping && _todos.isEmpty)) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(color: _kOrange, strokeWidth: 3),
            ),
            SizedBox(height: 14),
            Text(
              'Buscando y verificando servidores…',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (_error != null && _todos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }

    final list = _currentList;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _scraping ? 'Verificando…' : 'Sin servidores en esta fuente',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 15,
          ),
        ),
      );
    }

    _ensureCardNodes(list.length);

    return ListView.builder(
      controller: _listScroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: list.length,
      itemExtent: _kItemExtent,
      cacheExtent: _kItemExtent * 8,
      itemBuilder: (context, index) {
        final s = list[index];
        final nombre = s['servidor_nombre']?.toString() ?? 'Servidor';
        final calidad = s['calidad']?.toString() ?? 'HD';
        final fuenteLabel = s['fuente_label']?.toString() ?? '';
        final idioma = MainFuentes.normalizeIdioma(s['idioma']?.toString());
        final url = s['servidor_url']?.toString() ?? '';

        final esPlayer = _isPlayerServer(s);
        final isCurrent = widget.currentServidorUrl != null &&
            widget.currentServidorUrl == url;

        _ensureCardNodes(index + 1);
        final focusNode = _cardFocus[index];

        return Focus(
          focusNode: focusNode,
          onKeyEvent: (n, e) => _onCardKey(index, n, e),
          onFocusChange: (has) {
            if (has) _lastCardIndex = index;
          },
          child: Builder(
            builder: (context) {
              final hasFocus = Focus.of(context).hasFocus;
              return GestureDetector(
                onTap: () => _openServer(s),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: hasFocus
                        ? Colors.white.withValues(alpha: 0.18)
                        : (isCurrent
                            ? _kAccent.withValues(alpha: 0.22)
                            : _kCard),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasFocus
                          ? Colors.white
                          : (esPlayer
                              ? _kGreen.withValues(alpha: 0.4)
                              : (isCurrent
                                  ? _kAccent.withValues(alpha: 0.75)
                                  : Colors.white.withValues(alpha: 0.06))),
                      width: hasFocus || isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      _langFlag(idioma, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    [
                                      MainFuentes.idiomaLabel(idioma),
                                      if (fuenteLabel.isNotEmpty) fuenteLabel,
                                      calidad,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (esPlayer)
                                  _badge(
                                    'PLAYER',
                                    _kGreen,
                                    Icons.play_circle_fill_rounded,
                                  )
                                else
                                  _badge(
                                    'WEBVIEW',
                                    _kBlue,
                                    Icons.language_rounded,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.play_arrow_rounded,
                        color: esPlayer
                            ? _kGreen
                            : Colors.white.withValues(alpha: 0.3),
                        size: 22,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}