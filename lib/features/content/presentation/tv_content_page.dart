import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../servers/presentation/tv_servers_modal.dart';
import '../../player/presentation/tv/tv_player_controller.dart';
import '../../player/presentation/tv/tv_player_page.dart';
import '../../../data/datasources/remote/tmdb/tmdb_content.dart';
import '../../../data/datasources/remote/tmdb/tmdb_recommendations_api.dart';

const kAccentColor = Color(0xFFE50914);
const double _kEpisodeItemExtent =
    214.0; // ancho tarjeta + margen (slider horizontal)
const double _kRecoItemExtent = 148.0; // ancho poster reco + margen

class GuardadosBus {
  GuardadosBus._();
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void bump() => version.value++;
}

class HistorialBus {
  HistorialBus._();
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void bump() => version.value++;
}

class GuardadosCache {
  static const String _kKey = 'guardados_items';

  static Future<List<Map<String, dynamic>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? [];
    return raw
        .map((e) {
          try {
            return Map<String, dynamic>.from(jsonDecode(e));
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  static Future<bool> isSaved(int idcontenido) async {
    final items = await getAll();
    return items.any((e) => e['idcontenido'] == idcontenido);
  }

  static Future<bool> toggle(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getAll();
    final id = item['idcontenido'];
    final exists = items.any((e) => e['idcontenido'] == id);

    if (exists) {
      items.removeWhere((e) => e['idcontenido'] == id);
    } else {
      items.insert(0, item);
    }

    await prefs.setStringList(_kKey, items.map((e) => jsonEncode(e)).toList());
    GuardadosBus.bump();
    return !exists;
  }
}

class EpisodeProgressInfo {
  final int season;
  final int episode;
  final int segundo;
  final DateTime? timestamp;

  const EpisodeProgressInfo({
    required this.season,
    required this.episode,
    required this.segundo,
    this.timestamp,
  });
}

class PageContenido extends StatefulWidget {
  final int idcontenido;
  final int? tmdbId;
  final String mediaType;

  const PageContenido({
    super.key,
    required this.idcontenido,
    this.tmdbId,
    this.mediaType = 'movie',
  });

  @override
  State<PageContenido> createState() => _PageContenidoState();
}

class _PageContenidoState extends State<PageContenido>
    with WidgetsBindingObserver {
  final TmdbContentService _tmdb = TmdbContentService();
  final TmdbRecommendationsService _recoService = TmdbRecommendationsService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  int _selectedSeasonIndex = 0;

  final ValueNotifier<bool> _isSavedNotifier = ValueNotifier(false);
  final ValueNotifier<Map<String, dynamic>?> _progressNotifier = ValueNotifier(
    null,
  );

  Map<String, EpisodeProgressInfo> _allEpisodeProgress = {};
  EpisodeProgressInfo? _mostRecentEpisode;
  bool _refreshingProgress = false;

  final FocusNode _playFocusNode = FocusNode();
  final FocusNode _addFocusNode = FocusNode();
  final FocusNode _randomFocusNode = FocusNode();
  final FocusNode _restartFocusNode = FocusNode();
  final FocusNode _letterboxdFocusNode = FocusNode();
  List<FocusNode> _seasonFocusNodes = [];
  List<FocusNode> _episodeFocusNodes = [];
  List<FocusNode> _recoFocusNodes = [];

  final ScrollController _episodeScrollController = ScrollController();
  final ScrollController _recoScrollController = ScrollController();

  Timer? _liveRefreshTimer;

  // ---- vista de capítulos (slider inferior) ----
  bool _showEpisodesView = false;
  bool _showEpisodesHint = false;
  Timer? _hintTimer;
  final ValueNotifier<String> _episodeBgNotifier = ValueNotifier<String>('');

  // ---- vista de recomendaciones ----
  bool _showRecommendationsView = false;
  bool _recoLoading = false;
  List<Map<String, dynamic>> _recommendations = [];
  int _selectedRecoIndex = 0;
  final ValueNotifier<String> _recoBgNotifier = ValueNotifier<String>('');
  final ValueNotifier<Map<String, dynamic>?> _selectedRecoNotifier =
      ValueNotifier(null);

  int get _resolvedTmdbId => widget.tmdbId ?? widget.idcontenido;

  String get _resolvedMediaType {
    final t = widget.mediaType.toLowerCase().trim();
    if (t == 'tv' || t == 'serie' || t == 'series') return 'tv';
    return 'movie';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GuardadosBus.version.addListener(_onExternalCacheChange);
    HistorialBus.version.addListener(_onExternalCacheChange);
    _fetchContent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GuardadosBus.version.removeListener(_onExternalCacheChange);
    HistorialBus.version.removeListener(_onExternalCacheChange);
    _liveRefreshTimer?.cancel();
    _hintTimer?.cancel();
    _playFocusNode.dispose();
    _addFocusNode.dispose();
    _randomFocusNode.dispose();
    _restartFocusNode.dispose();
    _letterboxdFocusNode.dispose();
    _episodeScrollController.dispose();
    _recoScrollController.dispose();
    _isSavedNotifier.dispose();
    _progressNotifier.dispose();
    _episodeBgNotifier.dispose();
    _recoBgNotifier.dispose();
    _selectedRecoNotifier.dispose();
    for (final n in _seasonFocusNodes) {
      n.dispose();
    }
    for (final n in _episodeFocusNodes) {
      n.dispose();
    }
    for (final n in _recoFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadFullProgress(silent: true);
    }
  }

  void _onExternalCacheChange() {
    if (!mounted || _loading) return;
    _loadFullProgress(silent: true);
  }

  void _startLiveRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_loading) _loadFullProgress(silent: true);
    });
  }

  Future<void> _fetchContent() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final json = await _tmdb.fetchContent(
        tmdbId: _resolvedTmdbId,
        mediaType: _resolvedMediaType,
      );

      if (json['success'] == true && json['data'] != null) {
        setState(() {
          _data = Map<String, dynamic>.from(json['data'] as Map);
          _loading = false;
          _selectedSeasonIndex = 0;
        });
        _resyncFocusNodes();
        _loadSavedState();
        await _loadFullProgress();
        _startLiveRefresh();

        // Aviso superior: solo para TV, dura 10s y luego se borra.
        if (_resolvedMediaType == 'tv' && _seasons.isNotEmpty) {
          _hintTimer?.cancel();
          setState(() => _showEpisodesHint = true);
          _hintTimer = Timer(const Duration(seconds: 10), () {
            if (mounted) setState(() => _showEpisodesHint = false);
          });
        }
      } else {
        setState(() {
          _error = json['error']?.toString() ?? 'No se encontró el contenido';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Sin conexión';
        _loading = false;
      });
    }
  }

  Future<void> _loadSavedState() async {
    final saved = await GuardadosCache.isSaved(widget.idcontenido);
    if (mounted) _isSavedNotifier.value = saved;
  }

  Future<void> _loadFullProgress({bool silent = false}) async {
    if (_refreshingProgress) return;
    _refreshingProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_resolvedMediaType == 'movie') {
        String? raw = prefs.getString('cachePlayer_${widget.idcontenido}');
        raw ??= prefs.getString('cachePlayerRapido_${widget.idcontenido}');

        Map<String, dynamic>? data;
        if (raw != null) {
          try {
            data = Map<String, dynamic>.from(jsonDecode(raw));
          } catch (_) {}
        }

        final current = _progressNotifier.value;
        final same =
            (data == null && current == null) ||
            (data != null &&
                current != null &&
                data['segundo'] == current['segundo']);
        if (!same && mounted) {
          _progressNotifier.value = data;
        }
        return;
      }

      final seasons = _seasons;
      if (seasons.isEmpty) return;

      final map = <String, EpisodeProgressInfo>{};
      EpisodeProgressInfo? mostRecent;

      for (final season in seasons) {
        final sNum = (season['season_number'] as num?)?.toInt() ?? 0;
        final episodes = List<Map<String, dynamic>>.from(
          season['episodes'] ?? [],
        );
        for (final ep in episodes) {
          final eNum = (ep['episode_number'] as num?)?.toInt() ?? 0;
          final fullKey = 'cachePlayer_${widget.idcontenido}_T${sNum}_C$eNum';
          final rapidoKey =
              'cachePlayerRapido_${widget.idcontenido}_T${sNum}_C$eNum';

          int? sec;
          DateTime? ts;

          final rawFull = prefs.getString(fullKey);
          if (rawFull != null) {
            try {
              final d = Map<String, dynamic>.from(jsonDecode(rawFull));
              sec = (d['segundo'] as num?)?.toInt();
              final tsRaw = d['timestamp']?.toString();
              if (tsRaw != null) ts = DateTime.tryParse(tsRaw);
            } catch (_) {}
          }

          if (sec == null) {
            final rawRapido = prefs.getString(rapidoKey);
            if (rawRapido != null) {
              try {
                final d = Map<String, dynamic>.from(jsonDecode(rawRapido));
                sec = (d['segundo'] as num?)?.toInt();
              } catch (_) {}
            }
          }

          if (sec != null && sec > 5) {
            final info = EpisodeProgressInfo(
              season: sNum,
              episode: eNum,
              segundo: sec,
              timestamp: ts,
            );
            map['S${sNum}E$eNum'] = info;
            if (mostRecent == null) {
              mostRecent = info;
            } else if (ts != null &&
                (mostRecent.timestamp == null ||
                    ts.isAfter(mostRecent.timestamp!))) {
              mostRecent = info;
            }
          }
        }
      }

      if (!mounted) return;
      if (_sameProgressState(map, mostRecent)) return;

      setState(() {
        _allEpisodeProgress = map;
        _mostRecentEpisode = mostRecent;
      });

      _progressNotifier.value = mostRecent == null
          ? null
          : {
              'temporada': mostRecent.season,
              'capitulo': mostRecent.episode,
              'segundo': mostRecent.segundo,
            };

      if (!silent && mostRecent != null) {
        final idx = seasons.indexWhere(
          (s) =>
              ((s['season_number'] as num?)?.toInt() ?? -1) ==
              mostRecent!.season,
        );
        if (idx != -1 && idx != _selectedSeasonIndex) {
          setState(() => _selectedSeasonIndex = idx);
          _resyncEpisodeFocusNodes();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToPreferredEpisode(animate: false);
        });
      }
    } finally {
      _refreshingProgress = false;
    }
  }

  bool _sameProgressState(
    Map<String, EpisodeProgressInfo> newMap,
    EpisodeProgressInfo? newMostRecent,
  ) {
    if (newMap.length != _allEpisodeProgress.length) return false;
    if ((newMostRecent == null) != (_mostRecentEpisode == null)) return false;
    if (newMostRecent != null && _mostRecentEpisode != null) {
      if (newMostRecent.season != _mostRecentEpisode!.season ||
          newMostRecent.episode != _mostRecentEpisode!.episode ||
          newMostRecent.segundo != _mostRecentEpisode!.segundo) {
        return false;
      }
    }
    for (final entry in newMap.entries) {
      final old = _allEpisodeProgress[entry.key];
      if (old == null || old.segundo != entry.value.segundo) return false;
    }
    return true;
  }

  Future<void> _toggleSaved() async {
    if (_data == null) return;
    final data = _data!;
    final item = <String, dynamic>{
      'idcontenido': widget.idcontenido,
      'tmdb_id': _resolvedTmdbId,
      'media_type': _resolvedMediaType,
      'type': data['type'] ?? _resolvedMediaType,
      'title': data['title'],
      'poster_path': _firstUrl(data['poster_path']),
      'backdrop_path': _firstUrl(data['backdrop_path']),
      'vote_average': data['vote_average'],
      'addedAt': DateTime.now().toIso8601String(),
    };
    final nowSaved = await GuardadosCache.toggle(item);
    if (mounted) _isSavedNotifier.value = nowSaved;
  }

  Future<void> _clearProgress() async {
    final prefs = await SharedPreferences.getInstance();
    if (_resolvedMediaType == 'movie') {
      await prefs.remove('cachePlayer_${widget.idcontenido}');
      await prefs.remove('cachePlayerRapido_${widget.idcontenido}');
      if (mounted) _progressNotifier.value = null;
    } else {
      final mr = _mostRecentEpisode;
      if (mr != null) {
        await prefs.remove(
          'cachePlayer_${widget.idcontenido}_T${mr.season}_C${mr.episode}',
        );
        await prefs.remove(
          'cachePlayerRapido_${widget.idcontenido}_T${mr.season}_C${mr.episode}',
        );
        if (mounted) {
          setState(() {
            _allEpisodeProgress.remove('S${mr.season}E${mr.episode}');
            _mostRecentEpisode = null;
          });
        }
        _progressNotifier.value = null;
      }
    }
    GuardadosBus.bump();
    HistorialBus.bump();
  }

  /// Reinicia (borra historial) y abre el player desde cero.
  Future<void> _restartAndPlay() async {
    await _clearProgress();
    if (!mounted) return;
    if (_resolvedMediaType == 'movie') {
      _openServidores();
    } else {
      final mr = _mostRecentEpisode;
      // Si había un episodio reciente, lo reabrimos desde 0; si no, el primero de la temporada actual.
      final temp = mr?.season ?? _currentSeasonNumber;
      final cap =
          mr?.episode ??
          (_currentEpisodes.isNotEmpty
              ? (_currentEpisodes.first['episode_number'] as num?)?.toInt() ?? 1
              : 1);
      _openServidores(temporada: temp, capitulo: cap);
    }
  }

  void _openRandomEpisode() {
    final options = <Map<String, int>>[];
    for (final s in _seasons) {
      final sNum = (s['season_number'] as num?)?.toInt() ?? 0;
      final episodes = List<Map<String, dynamic>>.from(s['episodes'] ?? []);
      for (final ep in episodes) {
        final eNum = (ep['episode_number'] as num?)?.toInt() ?? 0;
        options.add({'season': sNum, 'episode': eNum});
      }
    }
    if (options.isEmpty) return;

    final rnd = math.Random();
    var pick = options[rnd.nextInt(options.length)];
    if (options.length > 1 && _mostRecentEpisode != null) {
      var guard = 0;
      while (pick['season'] == _mostRecentEpisode!.season &&
          pick['episode'] == _mostRecentEpisode!.episode &&
          guard < 8) {
        pick = options[rnd.nextInt(options.length)];
        guard++;
      }
    }
    _openServidores(temporada: pick['season'], capitulo: pick['episode']);
  }

  void _openLetterboxdQr() {
    final imdbId = (_data?['imdb_id']?.toString() ?? '').trim();
    if (imdbId.isEmpty) return;

    final url = 'https://letterboxd.com/imdb/$imdbId';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/letterboxd.png',
                      width: 28,
                      height: 28,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.movie,
                        color: Colors.white70,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Letterboxd',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Escanea el código para abrir en Letterboxd',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  url,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: kAccentColor,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- filtra temporadas 0 (especiales) y temporadas vacías ----
  List<Map<String, dynamic>> get _seasons {
    final all = List<Map<String, dynamic>>.from(_data?['seasons'] ?? []);
    return all.where((s) {
      final seasonNum = (s['season_number'] as num?)?.toInt() ?? -1;
      final episodes = List.from(s['episodes'] ?? []);
      if (seasonNum <= 0) return false; // sin especiales / T0
      if (episodes.isEmpty) return false; // sin temporadas vacías
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _currentEpisodes {
    final seasons = _seasons;
    if (seasons.isEmpty) return [];
    final idx = _selectedSeasonIndex.clamp(0, seasons.length - 1);
    return List<Map<String, dynamic>>.from(seasons[idx]['episodes'] ?? []);
  }

  int get _totalEpisodesCount {
    var count = 0;
    for (final s in _seasons) {
      count += List.from(s['episodes'] ?? []).length;
    }
    return count;
  }

  int get _currentSeasonNumber {
    final seasons = _seasons;
    if (seasons.isEmpty) return 1;
    final idx = _selectedSeasonIndex.clamp(0, seasons.length - 1);
    return (seasons[idx]['season_number'] as num?)?.toInt() ?? 1;
  }

  int _preferredEpisodeIndexFor(
    int seasonNumber,
    List<Map<String, dynamic>> episodes,
  ) {
    final mostRecent = _mostRecentEpisode;
    if (mostRecent != null && mostRecent.season == seasonNumber) {
      final idx = episodes.indexWhere(
        (e) =>
            ((e['episode_number'] as num?)?.toInt() ?? -1) ==
            mostRecent.episode,
      );
      if (idx != -1) return idx;
    }
    return 0;
  }

  void _scrollToPreferredEpisode({bool animate = true}) {
    if (!_episodeScrollController.hasClients) return;
    final episodes = _currentEpisodes;
    if (episodes.isEmpty) return;

    final idx = _preferredEpisodeIndexFor(_currentSeasonNumber, episodes);

    final max = _episodeScrollController.position.maxScrollExtent;
    final target = (idx * _kEpisodeItemExtent) - 12;
    final clamped = target.clamp(0.0, max);

    if (animate) {
      _episodeScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else {
      _episodeScrollController.jumpTo(clamped);
    }
  }

  void _resyncFocusNodes() {
    for (final n in _seasonFocusNodes) {
      n.dispose();
    }
    _seasonFocusNodes = List.generate(_seasons.length, (_) => FocusNode());
    _resyncEpisodeFocusNodes();
  }

  void _resyncEpisodeFocusNodes() {
    for (final n in _episodeFocusNodes) {
      n.dispose();
    }
    _episodeFocusNodes = List.generate(
      _currentEpisodes.length,
      (_) => FocusNode(),
    );
  }

  void _resyncRecoFocusNodes() {
    for (final n in _recoFocusNodes) {
      n.dispose();
    }
    _recoFocusNodes = List.generate(
      _recommendations.length,
      (_) => FocusNode(),
    );
  }

  void _selectSeason(int index, {bool focusPreferredEpisode = false}) {
    setState(() => _selectedSeasonIndex = index);
    _resyncEpisodeFocusNodes();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final episodes = _currentEpisodes;
      if (episodes.isEmpty) return;

      final targetIdx = focusPreferredEpisode
          ? _preferredEpisodeIndexFor(
              _currentSeasonNumber,
              episodes,
            ).clamp(0, episodes.length - 1)
          : 0;

      _episodeBgNotifier.value = _episodeBackdropUrl(episodes[targetIdx]);

      if (_episodeScrollController.hasClients) {
        final max = _episodeScrollController.position.maxScrollExtent;
        final target = (targetIdx * _kEpisodeItemExtent) - 12;
        _episodeScrollController.jumpTo(target.clamp(0.0, max));
      }

      if (_episodeFocusNodes.isNotEmpty &&
          targetIdx < _episodeFocusNodes.length) {
        _episodeFocusNodes[targetIdx].requestFocus();
      }
    });
  }

  // ---- construye la url grande del backdrop de un capítulo para el fondo ----
  String _episodeBackdropUrl(Map ep) {
    final raw = ep['still_path']?.toString() ?? '';
    if (raw.isEmpty) return '';
    return raw.startsWith('http')
        ? raw
        : 'https://image.tmdb.org/t/p/w1280$raw';
  }

  String _recoBackdropUrl(Map item) {
    final raw = item['backdrop_path']?.toString() ?? '';
    if (raw.isEmpty) {
      final poster = item['poster_path']?.toString() ?? '';
      if (poster.isEmpty) return '';
      return poster.startsWith('http')
          ? poster
          : 'https://image.tmdb.org/t/p/w1280$poster';
    }
    return raw.startsWith('http')
        ? raw
        : 'https://image.tmdb.org/t/p/w1280$raw';
  }

  String _recoPosterUrl(Map item) {
    final raw = item['poster_path']?.toString() ?? '';
    if (raw.isEmpty) return '';
    return raw.startsWith('http') ? raw : 'https://image.tmdb.org/t/p/w342$raw';
  }

  void _handleEpisodeFocusChanged(Map<String, dynamic> ep) {
    _episodeBgNotifier.value = _episodeBackdropUrl(ep);
  }

  int? _recoDetailsRequestId;

  void _handleRecoFocusChanged(int index) {
    if (index < 0 || index >= _recommendations.length) return;
    _selectedRecoIndex = index;
    final item = _recommendations[index];
    // Mostrar datos básicos de inmediato; enriquecer con detalle (logo, géneros, IMDb).
    _selectedRecoNotifier.value = Map<String, dynamic>.from(item);
    _recoBgNotifier.value = _recoBackdropUrl(item);
    _enrichRecoDetails(item, index);
  }

  Future<void> _enrichRecoDetails(Map<String, dynamic> item, int index) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final mt = (item['media_type']?.toString() ?? 'movie').toLowerCase();
    final mediaType = (mt == 'tv' || mt == 'serie' || mt == 'series')
        ? 'tv'
        : 'movie';
    final requestId = DateTime.now().microsecondsSinceEpoch;
    _recoDetailsRequestId = requestId;
    try {
      final details = await _recoService.fetchItemDetails(
        tmdbId: id,
        mediaType: mediaType,
      );
      if (!mounted || _recoDetailsRequestId != requestId) return;
      if (_selectedRecoIndex != index) return;
      if (details == null) return;
      final merged = Map<String, dynamic>.from(item);
      // Preferir overview / logo / genres / imdb del detalle
      for (final key in [
        'overview',
        'logo_path',
        'genres',
        'imdb_id',
        'vote_average',
        'release_date',
        'first_air_date',
        'runtime',
        'episode_run_time',
        'title',
        'name',
      ]) {
        final v = details[key];
        if (v == null) continue;
        if (v is String && v.trim().isEmpty) continue;
        if (v is List && v.isEmpty) continue;
        merged[key] = v;
      }
      // vote_imdb si viene
      if (details['imdb_rating'] != null) {
        merged['imdb_rating'] = details['imdb_rating'];
      }
      if (details['vote_imdb'] != null) {
        merged['vote_imdb'] = details['vote_imdb'];
      }
      _selectedRecoNotifier.value = merged;
      final bg = _recoBackdropUrl(merged);
      if (bg.isNotEmpty) _recoBgNotifier.value = bg;
    } catch (_) {}
  }

  // ---- entra / sale de la vista de capítulos (activada con flecha abajo en "VER AHORA") ----
  void _enterEpisodesView() {
    if (_resolvedMediaType != 'tv') return;
    final seasons = _seasons;
    if (seasons.isEmpty) return;

    _hintTimer?.cancel();

    // Asegurar que la temporada seleccionada sea la del progreso más reciente.
    if (_mostRecentEpisode != null) {
      final idx = seasons.indexWhere(
        (s) =>
            ((s['season_number'] as num?)?.toInt() ?? -1) ==
            _mostRecentEpisode!.season,
      );
      if (idx != -1) {
        _selectedSeasonIndex = idx;
      }
    }

    setState(() {
      _showEpisodesView = true;
      _showEpisodesHint = false;
      _showRecommendationsView = false;
    });
    _resyncEpisodeFocusNodes();

    final episodes = _currentEpisodes;
    final preferredIdx = episodes.isEmpty
        ? 0
        : _preferredEpisodeIndexFor(
            _currentSeasonNumber,
            episodes,
          ).clamp(0, episodes.length - 1);

    if (episodes.isNotEmpty) {
      _episodeBgNotifier.value = _episodeBackdropUrl(episodes[preferredIdx]);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Foco inicial: temporada del progreso + capítulo más reciente.
      if (_seasonFocusNodes.isNotEmpty) {
        final sIdx = _selectedSeasonIndex.clamp(
          0,
          _seasonFocusNodes.length - 1,
        );
        _seasonFocusNodes[sIdx].requestFocus();
      }

      // Inmediatamente pasar el foco al capítulo preferido para que el usuario
      // pueda reproducir sin tener que bajar de nuevo.
      if (_episodeFocusNodes.isNotEmpty &&
          preferredIdx < _episodeFocusNodes.length) {
        _episodeFocusNodes[preferredIdx].requestFocus();
        _scrollToPreferredEpisode(animate: false);
      }
    });
  }

  void _exitEpisodesView() {
    if (!_showEpisodesView) return;
    setState(() => _showEpisodesView = false);
    _episodeBgNotifier.value = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playFocusNode.requestFocus();
    });
  }

  // ---- recomendaciones ----
  int? _collectionIdFromData() {
    final col = _data?['belongs_to_collection'];
    if (col is Map) {
      return (col['id'] as num?)?.toInt();
    }
    // algunos backends pueden aplanar el id
    final flat = _data?['collection_id'];
    if (flat is num) return flat.toInt();
    return null;
  }

  Future<void> _enterRecommendationsView() async {
    if (_showRecommendationsView) return;

    setState(() {
      _showRecommendationsView = true;
      _showEpisodesHint = false;
      _recoLoading = true;
    });

    try {
      final list = await _recoService.fetchRecommendations(
        tmdbId: _resolvedTmdbId,
        mediaType: _resolvedMediaType,
        collectionId: _collectionIdFromData(),
      );
      if (!mounted) return;
      setState(() {
        _recommendations = list;
        _recoLoading = false;
        _selectedRecoIndex = 0;
      });
      _resyncRecoFocusNodes();

      if (list.isNotEmpty) {
        _selectedRecoNotifier.value = Map<String, dynamic>.from(list.first);
        _recoBgNotifier.value = _recoBackdropUrl(list.first);
        _enrichRecoDetails(list.first, 0);
      } else {
        _selectedRecoNotifier.value = null;
        _recoBgNotifier.value = '';
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_recoFocusNodes.isNotEmpty) {
          _recoFocusNodes.first.requestFocus();
          if (_recoScrollController.hasClients) {
            _recoScrollController.jumpTo(0);
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recoLoading = false;
        _recommendations = [];
      });
    }
  }

  void _exitRecommendationsView() {
    if (!_showRecommendationsView) return;
    setState(() => _showRecommendationsView = false);
    _recoBgNotifier.value = '';
    _selectedRecoNotifier.value = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_resolvedMediaType == 'tv' && _showEpisodesView) {
        // Regresar al primer capítulo de la temporada seleccionada
        final episodes = _currentEpisodes;
        if (episodes.isNotEmpty && _episodeFocusNodes.isNotEmpty) {
          _episodeBgNotifier.value = _episodeBackdropUrl(episodes.first);
          _episodeFocusNodes.first.requestFocus();
          if (_episodeScrollController.hasClients) {
            _episodeScrollController.jumpTo(0);
          }
        } else if (_seasonFocusNodes.isNotEmpty) {
          final sIdx = _selectedSeasonIndex.clamp(
            0,
            _seasonFocusNodes.length - 1,
          );
          _seasonFocusNodes[sIdx].requestFocus();
        } else {
          _playFocusNode.requestFocus();
        }
      } else {
        // Movie (o TV sin episodes view): volver a info / play
        _playFocusNode.requestFocus();
      }
    });
  }

  /// Al seleccionar una recomendación: cierra esta página y abre la nueva
  /// (evita apilar PageContenido una encima de otra).
  void _openRecommendation(Map<String, dynamic> item) {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final mt = (item['media_type']?.toString() ?? 'movie').toLowerCase();
    final mediaType = (mt == 'tv' || mt == 'serie' || mt == 'series')
        ? 'tv'
        : 'movie';

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            PageContenido(idcontenido: id, tmdbId: id, mediaType: mediaType),
      ),
    );
  }

  String _firstUrl(dynamic value) {
    if (value == null) return '';
    String str = value.toString().trim();

    if (str.startsWith('http') && !str.contains('[')) {
      return str;
    }

    final match = RegExp(r'https?:\\?/\\?/[^\s,"\]\\]+').firstMatch(str);
    if (match != null) {
      return match.group(0)!.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');
    }

    try {
      String cleaned = str
          .replaceAll(r'\/', '/')
          .replaceAll("'", '"')
          .replaceAll('""', '"');
      if (!cleaned.startsWith('[')) cleaned = '[$cleaned]';
      final list = jsonDecode(cleaned);
      if (list is List && list.isNotEmpty) {
        return list.first.toString().replaceAll(r'\/', '/');
      }
    } catch (_) {}

    return '';
  }

  List<String> _parseGenres(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      final out = <String>[];
      for (final g in value) {
        if (g is String && g.isNotEmpty) {
          out.add(g);
        } else if (g is Map && g['name'] != null) {
          out.add(g['name'].toString());
        }
      }
      if (out.isNotEmpty) return out;
    }
    String str = value.toString();
    try {
      final cleaned = str.replaceAll(r'\/', '/').replaceAll("'", '"');
      final list = jsonDecode(cleaned);
      if (list is List) return list.map((e) => e.toString()).toList();
    } catch (_) {}
    return str
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _formatTime(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
    }
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  Future<void> _openServidores({int? temporada, int? capitulo}) async {
    final data = _data;
    final tipo = data?['type']?.toString() ?? _resolvedMediaType;
    final titulo = data?['title']?.toString() ?? '';
    final isMovie = tipo.toLowerCase() != 'tv';

    final prefs = await SharedPreferences.getInstance();
    final modo = prefs.getString('seleccionar_servidores') ?? 'auto';

    // Manual → lista TV (mismo diseño)
    if (modo != 'auto') {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => ServidoresModalTv(
          idcontenido: widget.idcontenido,
          tmdbId: _resolvedTmdbId,
          temporada: temporada,
          capitulo: capitulo,
          titulo: titulo,
          tipo: tipo,
          backdropUrl: _firstUrl(data?['backdrop_path']),
          posterUrl: _firstUrl(data?['poster_path']),
          logoUrl: _firstUrl(data?['logo_path']),
        ),
      ).then((_) {
        _loadFullProgress();
        HistorialBus.bump();
      });
      return;
    }

    // AUTO: ServerLoader (first-win) → player solo si hay fuente;
    // si no encuentra servidor óptimo → modal de servidores.
    bool dialogShown = false;
    if (mounted) {
      dialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (_) => const _BuscandoServidorDialog(),
      );
    }

    String videoUrl = '';
    String? idioma;
    try {
      final loader = ServerLoader();
      final playable = await loader.resolvePlayable(
        contentId: _resolvedTmdbId,
        isMovie: isMovie,
        season: isMovie ? 0 : (temporada ?? 0),
        episode: isMovie ? 0 : (capitulo ?? 0),
        context: mounted ? context : null,
      );
      if (playable != null && playable.url.isNotEmpty) {
        videoUrl = playable.url;
        idioma = playable.idioma;
      }
    } catch (e) {
      debugPrint('ServerLoader precarga TV: $e');
    } finally {
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;

    // Sin fuente óptima → abrir modal de servidores (no player vacío).
    if (videoUrl.isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => ServidoresModalTv(
          idcontenido: widget.idcontenido,
          tmdbId: _resolvedTmdbId,
          temporada: temporada,
          capitulo: capitulo,
          titulo: titulo,
          tipo: tipo,
          backdropUrl: _firstUrl(data?['backdrop_path']),
          posterUrl: _firstUrl(data?['poster_path']),
          logoUrl: _firstUrl(data?['logo_path']),
        ),
      ).then((_) {
        _loadFullProgress();
        HistorialBus.bump();
      });
      return;
    }

    // Sí hay fuente → abrir player.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoUrl: videoUrl,
          idcontenido: widget.idcontenido,
          tmdbId: _resolvedTmdbId,
          temporada: isMovie ? null : temporada,
          capitulo: isMovie ? null : capitulo,
          tipo: tipo,
          titulo: titulo,
          idioma: idioma,
        ),
      ),
    );
    if (mounted) {
      _loadFullProgress();
      HistorialBus.bump();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_error != null || _data == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Error',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchContent,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    final isMovie = (data['type']?.toString() ?? _resolvedMediaType) == 'movie';
    final title = data['title']?.toString() ?? '';
    final overview = data['overview']?.toString() ?? '';
    final poster = _firstUrl(data['poster_path']);
    final backdrop = _firstUrl(data['backdrop_path']);
    final logo = _firstUrl(data['logo_path']);
    final imdbId = (data['imdb_id']?.toString() ?? '').trim();
    final bgImage = backdrop.isNotEmpty ? backdrop : poster;

    double ratingValue = 0;
    final va = data['vote_average'];
    if (va is num) {
      ratingValue = va.toDouble();
    } else {
      ratingValue =
          double.tryParse(
            data['imdb_rating']?.toString() ??
                data['vote_imdb']?.toString() ??
                '',
          ) ??
          0;
    }

    dynamic runtime = data['runtime'];
    if (runtime == null) {
      final epRuntimes = data['episode_run_time'];
      if (epRuntimes is List && epRuntimes.isNotEmpty) {
        runtime = epRuntimes.first;
      }
    }

    final genres = _parseGenres(data['genres']);
    final year = (data['release_date'] ?? data['first_air_date'] ?? '')
        .toString()
        .split('-')
        .first;
    final seasons = _seasons;
    final currentEpisodes = _currentEpisodes;

    if (_seasonFocusNodes.length != seasons.length) {
      _resyncFocusNodes();
    }

    final int currentSeasonNumber = _currentSeasonNumber;

    final bool canRandomEpisode = !isMovie && _totalEpisodesCount > 1;
    final bool episodesViewActive = _showEpisodesView && !isMovie;
    final bool recoViewActive = _showRecommendationsView;
    final bool canShowLetterboxd = isMovie && imdbId.isNotEmpty;

    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.6);
    final bgMemW = math.min(size.width * dpr, 1280).round();
    final bgMemH = math.min(size.height * dpr, 720).round();
    final posterMemW = math.min(size.width * 0.34 * dpr, 640).round();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: bgImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: bgImage,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    memCacheWidth: bgMemW,
                    memCacheHeight: bgMemH,
                    fadeInDuration: const Duration(milliseconds: 220),
                    placeholder: (_, __) => Container(color: Colors.black),
                    errorWidget: (_, __, ___) => Container(color: Colors.black),
                  )
                : Container(color: Colors.black),
          ),

          // ---- fondo del capítulo enfocado con blur (solo TV) ----
          if (!isMovie)
            ValueListenableBuilder<String>(
              valueListenable: _episodeBgNotifier,
              builder: (context, epBg, _) {
                final visible =
                    episodesViewActive && !recoViewActive && epBg.isNotEmpty;
                return IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: visible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 320),
                    child: epBg.isEmpty
                        ? const SizedBox.shrink()
                        : RepaintBoundary(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: epBg,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  memCacheWidth: bgMemW,
                                  memCacheHeight: bgMemH,
                                  fadeInDuration: const Duration(
                                    milliseconds: 200,
                                  ),
                                ),
                                BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: 26,
                                    sigmaY: 26,
                                  ),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.32),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                );
              },
            ),

          // ---- fondo de la recomendación enfocada con blur ----
          ValueListenableBuilder<String>(
            valueListenable: _recoBgNotifier,
            builder: (context, recoBg, _) {
              final visible = recoViewActive && recoBg.isNotEmpty;
              return IgnorePointer(
                child: AnimatedOpacity(
                  opacity: visible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 320),
                  child: recoBg.isEmpty
                      ? const SizedBox.shrink()
                      : RepaintBoundary(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: recoBg,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                memCacheWidth: bgMemW,
                                memCacheHeight: bgMemH,
                                fadeInDuration: const Duration(
                                  milliseconds: 200,
                                ),
                              ),
                              BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 26,
                                  sigmaY: 26,
                                ),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.36),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              );
            },
          ),

          const _ContenidoOverlayGradient(),

          SafeArea(
            child: recoViewActive
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(44, 28, 44, 30),
                    child: _RecommendationsPanel(
                      loading: _recoLoading,
                      items: _recommendations,
                      focusNodes: _recoFocusNodes,
                      scrollController: _recoScrollController,
                      selectedIndex: _selectedRecoIndex,
                      selectedNotifier: _selectedRecoNotifier,
                      onFocusChanged: _handleRecoFocusChanged,
                      onSelect: _openRecommendation,
                      onExit: _exitRecommendationsView,
                      posterUrlBuilder: _recoPosterUrl,
                    ),
                  )
                : episodesViewActive
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(44, 28, 44, 30),
                    child: ValueListenableBuilder<Map<String, dynamic>?>(
                      valueListenable: _progressNotifier,
                      builder: (context, progress, _) {
                        final progTemp = progress?['temporada'] as int?;
                        final progCap = progress?['capitulo'] as int?;
                        final progSec = progress?['segundo'] as int?;

                        return _EpisodesBottomPanel(
                          seasons: seasons,
                          selectedSeasonIndex: _selectedSeasonIndex,
                          episodes: currentEpisodes,
                          seasonFocusNodes: _seasonFocusNodes,
                          episodeFocusNodes: _episodeFocusNodes,
                          episodeScrollController: _episodeScrollController,
                          onSeasonSelected: (i) =>
                              _selectSeason(i, focusPreferredEpisode: false),
                          onEpisodeTap: (epNumber) => _openServidores(
                            temporada: currentSeasonNumber,
                            capitulo: epNumber,
                          ),
                          onExitEpisodesView: _exitEpisodesView,
                          onEpisodeFocusChanged: _handleEpisodeFocusChanged,
                          onRequestRecommendations: _enterRecommendationsView,
                          currentSeasonNumber: currentSeasonNumber,
                          progressSeasonNumber: progTemp,
                          progressEpisodeNumber: progCap,
                          progressSeconds: (progSec != null && progSec > 5)
                              ? progSec
                              : null,
                          allEpisodeProgress: _allEpisodeProgress,
                          preferredEpisodeIndex: _preferredEpisodeIndexFor(
                            currentSeasonNumber,
                            currentEpisodes,
                          ),
                          seriesCast: List<Map<String, dynamic>>.from(
                            (data['cast'] is List)
                                ? data['cast'] as List
                                : const [],
                          ),
                        );
                      },
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(44, 20, 44, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 6,
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              _isSavedNotifier,
                              _progressNotifier,
                            ]),
                            builder: (context, _) {
                              final progress = _progressNotifier.value;
                              final isSaved = _isSavedNotifier.value;

                              final int? resumeSec =
                                  progress?['segundo'] as int?;
                              final int? resumeTemp =
                                  progress?['temporada'] as int?;
                              final int? resumeCap =
                                  progress?['capitulo'] as int?;
                              final bool hasProgress =
                                  resumeSec != null && resumeSec > 5;

                              String playLabel;
                              if (isMovie) {
                                playLabel = hasProgress
                                    ? 'Reanudar · ${_formatTime(resumeSec!)}'
                                    : 'VER AHORA';
                              } else {
                                if (hasProgress &&
                                    resumeTemp != null &&
                                    resumeCap != null) {
                                  playLabel =
                                      'Reanudar · S${resumeTemp.toString().padLeft(2, '0')}E${resumeCap.toString().padLeft(2, '0')}';
                                } else {
                                  playLabel = currentEpisodes.isNotEmpty
                                      ? 'Play Episodio ${currentEpisodes.first['episode_number'] ?? 1}'
                                      : 'Reproducir';
                                }
                              }

                              return _InfoColumn(
                                title: title,
                                logoUrl: logo,
                                overview: overview,
                                ratingValue: ratingValue,
                                extraMeta: runtime != null
                                    ? '$runtime min'
                                    : null,
                                year: year,
                                genres: genres,
                                playLabel: playLabel,
                                playFocusNode: _playFocusNode,
                                addFocusNode: _addFocusNode,
                                randomFocusNode: _randomFocusNode,
                                restartFocusNode: _restartFocusNode,
                                letterboxdFocusNode: _letterboxdFocusNode,
                                isSaved: isSaved,
                                showLetterboxd: canShowLetterboxd,
                                onPlay: () {
                                  if (isMovie) {
                                    _openServidores();
                                  } else {
                                    final temp =
                                        (hasProgress && resumeTemp != null)
                                        ? resumeTemp
                                        : currentSeasonNumber;
                                    final cap =
                                        (hasProgress && resumeCap != null)
                                        ? resumeCap
                                        : (currentEpisodes.isNotEmpty
                                              ? (currentEpisodes
                                                        .first['episode_number'] ??
                                                    1)
                                              : 1);
                                    _openServidores(
                                      temporada: temp,
                                      capitulo: cap,
                                    );
                                  }
                                },
                                onToggleSaved: _toggleSaved,
                                onRandomEpisode: canRandomEpisode
                                    ? _openRandomEpisode
                                    : null,
                                onRestart: hasProgress ? _restartAndPlay : null,
                                onLetterboxd: canShowLetterboxd
                                    ? _openLetterboxdQr
                                    : null,
                                // Solo en TV: bajar desde "VER AHORA" abre la vista de capítulos.
                                onRequestEpisodesView: isMovie
                                    ? null
                                    : _enterEpisodesView,
                                // Movie: bajar desde play abre recomendaciones.
                                onRequestRecommendations: isMovie
                                    ? _enterRecommendationsView
                                    : null,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 36),
                        Expanded(
                          flex: 4,
                          child: RepaintBoundary(
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 2 / 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: poster.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: poster,
                                          fit: BoxFit.cover,
                                          memCacheWidth: posterMemW,
                                          fadeInDuration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          placeholder: (_, __) => Container(
                                            color: Colors.grey[900],
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (_, __, ___) =>
                                              Container(
                                                color: Colors.grey[900],
                                                child: const Icon(
                                                  Icons.movie,
                                                  color: Colors.white24,
                                                  size: 48,
                                                ),
                                              ),
                                        )
                                      : Container(
                                          color: Colors.grey[900],
                                          child: const Icon(
                                            Icons.movie,
                                            color: Colors.white24,
                                            size: 48,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // ---- notificación superior derecha (solo TV, dura 10s) ----
          if (!isMovie)
            Positioned(
              top: 22,
              right: 44,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity:
                      (_showEpisodesHint &&
                          !episodesViewActive &&
                          !recoViewActive)
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 350),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: kAccentColor,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Presiona ↓ para ver capítulos',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Spinner de "buscando servidor" mostrado mientras ServerLoader resuelve
/// la fuente de video. Evita que la app parezca congelada.
class _BuscandoServidorDialog extends StatelessWidget {
  const _BuscandoServidorDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: kAccentColor),
            const SizedBox(height: 18),
            Text(
              'Buscando servidor…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContenidoOverlayGradient extends StatelessWidget {
  const _ContenidoOverlayGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xC7000000), Color(0x8C000000), Color(0x6B000000)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

class _SecondaryButtonSpec {
  final FocusNode focusNode;
  final Widget iconWidget;
  final bool highlighted;
  final VoidCallback onTap;

  const _SecondaryButtonSpec({
    required this.focusNode,
    required this.iconWidget,
    required this.onTap,
    this.highlighted = false,
  });
}

class _CircleIconButton extends StatelessWidget {
  final FocusNode focusNode;
  final Widget iconWidget;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onArrowUp;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;

  const _CircleIconButton({
    required this.focusNode,
    required this.iconWidget,
    required this.onTap,
    required this.onArrowUp,
    this.highlighted = false,
    this.onArrowLeft,
    this.onArrowRight,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (onArrowLeft != null) {
            onArrowLeft!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (onArrowRight != null) {
            onArrowRight!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highlighted
                    ? kAccentColor.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.14),
                border: Border.all(
                  color: hasFocus ? kAccentColor : Colors.white38,
                  width: hasFocus ? 2.5 : 1.2,
                ),
              ),
              child: Center(child: iconWidget),
            ),
          );
        },
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String title;
  final String logoUrl;
  final String overview;
  final double ratingValue;
  final String? extraMeta;
  final String year;
  final List<String> genres;
  final String playLabel;
  final FocusNode playFocusNode;
  final FocusNode addFocusNode;
  final FocusNode randomFocusNode;
  final FocusNode restartFocusNode;
  final FocusNode letterboxdFocusNode;
  final bool isSaved;
  final bool showLetterboxd;
  final VoidCallback onPlay;
  final VoidCallback onToggleSaved;
  final VoidCallback? onRandomEpisode;
  final VoidCallback? onRestart;
  final VoidCallback? onLetterboxd;
  // Si no es null (solo TV), bajar desde el botón Play abre la vista de capítulos
  // en vez de ir al botón de "agregar".
  final VoidCallback? onRequestEpisodesView;
  // Si no es null (solo movie), bajar desde Play abre recomendaciones.
  final VoidCallback? onRequestRecommendations;

  const _InfoColumn({
    required this.title,
    required this.logoUrl,
    required this.overview,
    required this.ratingValue,
    required this.year,
    required this.genres,
    required this.playLabel,
    required this.playFocusNode,
    required this.addFocusNode,
    required this.randomFocusNode,
    required this.restartFocusNode,
    required this.letterboxdFocusNode,
    required this.isSaved,
    required this.showLetterboxd,
    required this.onPlay,
    required this.onToggleSaved,
    this.onRandomEpisode,
    this.onRestart,
    this.onLetterboxd,
    this.extraMeta,
    this.onRequestEpisodesView,
    this.onRequestRecommendations,
  });

  @override
  Widget build(BuildContext context) {
    final List<_SecondaryButtonSpec> secondaryButtons = [
      _SecondaryButtonSpec(
        focusNode: addFocusNode,
        iconWidget: Icon(
          isSaved ? Icons.check_rounded : Icons.add_rounded,
          color: Colors.white,
          size: 22,
        ),
        highlighted: isSaved,
        onTap: onToggleSaved,
      ),
      if (onRandomEpisode != null)
        _SecondaryButtonSpec(
          focusNode: randomFocusNode,
          iconWidget: const Icon(
            Icons.shuffle_rounded,
            color: Colors.white,
            size: 22,
          ),
          onTap: onRandomEpisode!,
        ),
      if (onRestart != null)
        _SecondaryButtonSpec(
          focusNode: restartFocusNode,
          iconWidget: const Icon(
            Icons.replay_rounded,
            color: Colors.white,
            size: 22,
          ),
          onTap: onRestart!,
        ),
      if (showLetterboxd && onLetterboxd != null)
        _SecondaryButtonSpec(
          focusNode: letterboxdFocusNode,
          iconWidget: Image.asset(
            'assets/images/letterboxd.png',
            width: 28,
            height: 28,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.movie, color: Colors.white70, size: 22);
            },
          ),
          onTap: onLetterboxd!,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo o título — siempre justificado a la izquierda desde el inicio
        Align(
          alignment: Alignment.centerLeft,
          child: logoUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: logoUrl,
                  height: 52,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  fadeInDuration: const Duration(milliseconds: 180),
                  placeholder: (_, __) => const SizedBox(height: 52),
                  errorWidget: (_, __, ___) => Text(
                    title,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                )
              : Text(
                  title,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
            if (extraMeta != null)
              Text(
                extraMeta!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (year.isNotEmpty)
              Text(
                year,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (ratingValue > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ratingValue.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                ],
              ),
          ],
        ),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'GENRES',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: genres.take(4).map((g) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  g,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'SUMMARY',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            overview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              autofocus: true,
              focusNode: playFocusNode,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (onRequestEpisodesView != null) {
                    onRequestEpisodesView!();
                  } else if (onRequestRecommendations != null) {
                    onRequestRecommendations!();
                  } else {
                    addFocusNode.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  onPlay();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final hasFocus = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: onPlay,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasFocus ? kAccentColor : Colors.white38,
                          width: hasFocus ? 2.5 : 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            playLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            for (int i = 0; i < secondaryButtons.length; i++) ...[
              const SizedBox(width: 12),
              _CircleIconButton(
                focusNode: secondaryButtons[i].focusNode,
                iconWidget: secondaryButtons[i].iconWidget,
                highlighted: secondaryButtons[i].highlighted,
                onTap: secondaryButtons[i].onTap,
                onArrowUp: () => playFocusNode.requestFocus(),
                onArrowLeft: i > 0
                    ? () => secondaryButtons[i - 1].focusNode.requestFocus()
                    : null,
                onArrowRight: i < secondaryButtons.length - 1
                    ? () => secondaryButtons[i + 1].focusNode.requestFocus()
                    : null,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Vista de capítulos: tabs de temporadas arriba + slider de capítulos +
/// ficha del episodio enfocado + reparto (serie + episodio en una sola línea).
/// Subir desde los tabs regresa a la información.
///
/// Lógica de foco mejorada:
/// - Izquierda/derecha en temporadas solo mueve el foco (no selecciona).
/// - OK/Enter o flecha abajo selecciona la temporada enfocada y entra a sus capítulos.
/// - Al entrar a la vista, el foco va a la temporada + capítulo más reciente según historial.
/// - Desde un capítulo, flecha abajo abre recomendaciones.
class _EpisodesBottomPanel extends StatefulWidget {
  final List<Map<String, dynamic>> seasons;
  final int selectedSeasonIndex;
  final List<Map<String, dynamic>> episodes;
  final List<FocusNode> seasonFocusNodes;
  final List<FocusNode> episodeFocusNodes;
  final ScrollController episodeScrollController;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<int> onEpisodeTap;
  final VoidCallback onExitEpisodesView;
  final ValueChanged<Map<String, dynamic>> onEpisodeFocusChanged;
  final VoidCallback? onRequestRecommendations;
  final int currentSeasonNumber;
  final int? progressSeasonNumber;
  final int? progressEpisodeNumber;
  final int? progressSeconds;
  final Map<String, EpisodeProgressInfo> allEpisodeProgress;
  final int preferredEpisodeIndex;
  final List<Map<String, dynamic>> seriesCast;

  const _EpisodesBottomPanel({
    required this.seasons,
    required this.selectedSeasonIndex,
    required this.episodes,
    required this.seasonFocusNodes,
    required this.episodeFocusNodes,
    required this.episodeScrollController,
    required this.onSeasonSelected,
    required this.onEpisodeTap,
    required this.onExitEpisodesView,
    required this.onEpisodeFocusChanged,
    required this.currentSeasonNumber,
    required this.allEpisodeProgress,
    this.onRequestRecommendations,
    this.progressSeasonNumber,
    this.progressEpisodeNumber,
    this.progressSeconds,
    this.preferredEpisodeIndex = 0,
    this.seriesCast = const [],
  });

  @override
  State<_EpisodesBottomPanel> createState() => _EpisodesBottomPanelState();
}

class _EpisodesBottomPanelState extends State<_EpisodesBottomPanel> {
  static const double _cardWidth = 200.0;
  static const double _cardImageHeight = 112.0;
  static const double _itemExtent = _kEpisodeItemExtent;

  Map<String, dynamic>? _focusedEpisode;

  @override
  void initState() {
    super.initState();
    _syncFocusedEpisode(forceFirst: false);
  }

  @override
  void didUpdateWidget(covariant _EpisodesBottomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSeasonIndex != widget.selectedSeasonIndex) {
      // Cambio de temporada → siempre el primer capítulo (salvo que se pida preferred).
      _syncFocusedEpisode(forceFirst: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToIndex(0, animate: false);
        if (widget.episodeFocusNodes.isNotEmpty) {
          widget.episodeFocusNodes.first.requestFocus();
        }
      });
    } else if (oldWidget.episodes != widget.episodes ||
        oldWidget.preferredEpisodeIndex != widget.preferredEpisodeIndex) {
      _syncFocusedEpisode(forceFirst: false);
    }
  }

  void _syncFocusedEpisode({required bool forceFirst}) {
    if (widget.episodes.isEmpty) {
      _focusedEpisode = null;
      return;
    }
    if (forceFirst) {
      _focusedEpisode = widget.episodes.first;
      return;
    }
    final idx = widget.preferredEpisodeIndex.clamp(
      0,
      widget.episodes.length - 1,
    );
    _focusedEpisode = widget.episodes[idx];
  }

  void _scrollToIndex(int index, {bool animate = true}) {
    if (!widget.episodeScrollController.hasClients) return;
    final max = widget.episodeScrollController.position.maxScrollExtent;
    final target = (index * _itemExtent) - 12;
    final clamped = target.clamp(0.0, max);
    if (animate) {
      widget.episodeScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      widget.episodeScrollController.jumpTo(clamped);
    }
  }

  double _progressFraction(Map ep, int seconds) {
    final runtimeMin = ep['runtime'];
    final totalSec = (runtimeMin is num && runtimeMin > 0)
        ? runtimeMin * 60
        : 2700;
    return (seconds / totalSec).clamp(0.03, 1.0).toDouble();
  }

  String _formatSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatAirDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final parts = raw.split('-');
    if (parts.length >= 3) {
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    return raw;
  }

  List<String> _crewNames(Map? ep, List<String> jobs) {
    if (ep == null) return const [];
    final raw = ep['crew'];
    if (raw is! List) return const [];
    final names = <String>[];
    final seen = <String>{};
    for (final c in raw) {
      if (c is! Map) continue;
      final job = (c['job']?.toString() ?? '').toLowerCase();
      final name = (c['name']?.toString() ?? '').trim();
      if (name.isEmpty || seen.contains(name)) continue;
      if (jobs.any((j) => job == j.toLowerCase())) {
        seen.add(name);
        names.add(name);
      }
    }
    return names;
  }

  List<Map<String, String>> _guestStars(Map? ep) {
    if (ep == null) return const [];
    final raw = ep['guest_stars'];
    if (raw is! List) return const [];
    final out = <Map<String, String>>[];
    final seen = <String>{};
    for (final g in raw) {
      if (g is! Map) continue;
      final name = (g['name']?.toString() ?? '').trim();
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      var photo = (g['profile_path']?.toString() ?? '').trim();
      if (photo.isNotEmpty && !photo.startsWith('http')) {
        photo = 'https://image.tmdb.org/t/p/w185$photo';
      }
      out.add({
        'name': name,
        'character': (g['character']?.toString() ?? '').trim(),
        'profile_path': photo,
      });
      if (out.length >= 5) break;
    }
    return out;
  }

  List<Map<String, String>> _seriesCastList() {
    final out = <Map<String, String>>[];
    final seen = <String>{};
    for (final c in widget.seriesCast) {
      final name = (c['name']?.toString() ?? '').trim();
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      var photo = (c['profile_path']?.toString() ?? '').trim();
      if (photo.isNotEmpty && !photo.startsWith('http')) {
        photo = 'https://image.tmdb.org/t/p/w185$photo';
      }
      out.add({
        'name': name,
        'character': (c['character']?.toString() ?? '').trim(),
        'profile_path': photo,
      });
      if (out.length >= 5) break;
    }
    return out;
  }

  /// Reparto combinado: primero hasta 5 de la serie, luego hasta 5 del
  /// capítulo enfocado, mostrados en una sola fila horizontal.
  Widget _buildCastSection(Map? ep) {
    final h = MediaQuery.sizeOf(context).height;
    if (h < 460) return const SizedBox.shrink();

    final series = _seriesCastList();
    final guests = _guestStars(ep);
    final combined = <Map<String, String>>[...series, ...guests];
    if (combined.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'REPARTO',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: combined.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                return _GuestStarChip(
                  name: combined[i]['name'] ?? '',
                  character: combined[i]['character'] ?? '',
                  photoUrl: combined[i]['profile_path'] ?? '',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.seasons.isEmpty) return const SizedBox.shrink();
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.8);
    final stillMemW = (_cardWidth * dpr).round();
    final stillMemH = (_cardImageHeight * dpr).round();

    final ep = _focusedEpisode;
    final epNumber = (ep?['episode_number'] as num?)?.toInt();
    final epName = ep?['name']?.toString() ?? '';
    final epOverview = (ep?['overview']?.toString() ?? '').trim();
    final epAirDate = _formatAirDate(ep?['air_date']?.toString());
    final epRating = (ep?['vote_average'] is num)
        ? (ep!['vote_average'] as num).toDouble()
        : double.tryParse('${ep?['vote_average']}') ?? 0;
    final epRuntime = (ep?['runtime'] is num)
        ? (ep!['runtime'] as num).toInt()
        : int.tryParse('${ep?['runtime'] ?? ''}');
    final directors = _crewNames(ep, const ['Director']);
    final writers = _crewNames(ep, const [
      'Writer',
      'Screenplay',
      'Teleplay',
      'Story',
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        // ---- 1) Tabs de temporadas ----
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(widget.seasons.length, (i) {
              final season = widget.seasons[i];
              final name =
                  season['name']?.toString() ??
                  'Temporada ${season['season_number']}';
              final isSelected = i == widget.selectedSeasonIndex;

              return Padding(
                padding: EdgeInsets.only(
                  right: i < widget.seasons.length - 1 ? 10 : 0,
                ),
                child: Focus(
                  focusNode: widget.seasonFocusNodes.length > i
                      ? widget.seasonFocusNodes[i]
                      : null,
                  onFocusChange: (hasFocus) {
                    if (hasFocus) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final ctx = widget.seasonFocusNodes.length > i
                            ? widget.seasonFocusNodes[i].context
                            : null;
                        if (ctx != null) {
                          Scrollable.ensureVisible(
                            ctx,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            alignment: 0.5,
                          );
                        }
                      });
                    }
                  },
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;

                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      widget.onExitEpisodesView();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      // Solo mueve el foco, NO selecciona la temporada.
                      if (i > 0) {
                        widget.seasonFocusNodes[i - 1].requestFocus();
                      }
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      // Solo mueve el foco, NO selecciona la temporada.
                      if (i < widget.seasonFocusNodes.length - 1) {
                        widget.seasonFocusNodes[i + 1].requestFocus();
                      }
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                        event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter) {
                      // Seleccionar esta temporada y entrar a sus capítulos.
                      if (i != widget.selectedSeasonIndex) {
                        widget.onSeasonSelected(i);
                      } else if (widget.episodeFocusNodes.isNotEmpty) {
                        final target = 0;
                        _scrollToIndex(target, animate: false);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (widget.episodeFocusNodes.isNotEmpty) {
                            widget.episodeFocusNodes[target].requestFocus();
                          }
                          _scrollToIndex(target, animate: true);
                        });
                      }
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final hasFocus = Focus.of(context).hasFocus;
                      return GestureDetector(
                        onTap: () => widget.onSeasonSelected(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.9)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hasFocus
                                  ? kAccentColor
                                  : Colors.transparent,
                              width: 2.2,
                            ),
                          ),
                          child: Text(
                            name,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 14),

        // ---- 2) Slider de capítulos ----
        SizedBox(
          height: _cardImageHeight + 28,
          child: widget.episodes.isEmpty
              ? const Center(
                  child: Text(
                    'No hay capítulos disponibles',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  controller: widget.episodeScrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.episodes.length,
                  // Margen final para que el último capítulo no quede cortado
                  // al llegar al límite del bloque.
                  padding: const EdgeInsets.only(right: 56, left: 2, top: 2),
                  clipBehavior: Clip.none,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final item = widget.episodes[index];
                    final itemNumber =
                        (item['episode_number'] as num?)?.toInt() ?? 0;

                    String still = '';
                    if (item['still_path'] != null) {
                      final raw = item['still_path'].toString();
                      still = raw.startsWith('http')
                          ? raw
                          : 'https://image.tmdb.org/t/p/w300$raw';
                    }

                    final isCurrentProgress =
                        widget.progressEpisodeNumber != null &&
                        widget.progressSeasonNumber ==
                            widget.currentSeasonNumber &&
                        itemNumber == widget.progressEpisodeNumber;

                    final watchedInfo = widget
                        .allEpisodeProgress['S${widget.currentSeasonNumber}E$itemNumber'];
                    final isWatched = watchedInfo != null && !isCurrentProgress;

                    final showProgressBar =
                        isCurrentProgress && widget.progressSeconds != null;
                    final showWatchedBar = isWatched;

                    return Focus(
                      focusNode: widget.episodeFocusNodes.length > index
                          ? widget.episodeFocusNodes[index]
                          : null,
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          if (widget.seasonFocusNodes.isNotEmpty) {
                            widget
                                .seasonFocusNodes[widget.selectedSeasonIndex
                                    .clamp(
                                      0,
                                      widget.seasonFocusNodes.length - 1,
                                    )]
                                .requestFocus();
                          } else {
                            widget.onExitEpisodesView();
                          }
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          if (index > 0) {
                            widget.episodeFocusNodes[index - 1].requestFocus();
                            _scrollToIndex(index - 1);
                          }
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          if (index < widget.episodeFocusNodes.length - 1) {
                            widget.episodeFocusNodes[index + 1].requestFocus();
                            _scrollToIndex(index + 1);
                          }
                          return KeyEventResult.handled;
                        }

                        // Flecha abajo → recomendaciones (si está disponible)
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (widget.onRequestRecommendations != null) {
                            widget.onRequestRecommendations!();
                            return KeyEventResult.handled;
                          }
                        }

                        if (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          widget.onEpisodeTap(itemNumber);
                          return KeyEventResult.handled;
                        }

                        return KeyEventResult.ignored;
                      },
                      onFocusChange: (hasFocus) {
                        if (hasFocus) {
                          widget.onEpisodeFocusChanged(item);
                          if (_focusedEpisode != item) {
                            setState(() => _focusedEpisode = item);
                          }
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _scrollToIndex(index);
                          });
                        }
                      },
                      child: Builder(
                        builder: (context) {
                          final hasFocus = Focus.of(context).hasFocus;
                          return GestureDetector(
                            onTap: () => widget.onEpisodeTap(itemNumber),
                            child: Container(
                              width: _cardWidth,
                              margin: const EdgeInsets.only(right: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    height: _cardImageHeight,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: hasFocus
                                            ? Colors.white
                                            : (isCurrentProgress
                                                  ? kAccentColor.withValues(
                                                      alpha: 0.65,
                                                    )
                                                  : Colors.transparent),
                                        width: hasFocus ? 2.4 : 1.6,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          still.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: still,
                                                  fit: BoxFit.cover,
                                                  memCacheWidth: stillMemW,
                                                  memCacheHeight: stillMemH,
                                                  fadeInDuration:
                                                      const Duration(
                                                        milliseconds: 120,
                                                      ),
                                                  placeholder: (_, __) =>
                                                      Container(
                                                        color: Colors.grey[900],
                                                      ),
                                                  errorWidget: (_, __, ___) =>
                                                      Container(
                                                        color: Colors.grey[900],
                                                        child: const Icon(
                                                          Icons.movie,
                                                          color: Colors.white24,
                                                        ),
                                                      ),
                                                )
                                              : Container(
                                                  color: Colors.grey[900],
                                                ),
                                          const DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Color(0xB3000000),
                                                ],
                                                stops: [0.5, 1.0],
                                              ),
                                            ),
                                          ),
                                          if (isCurrentProgress)
                                            const Positioned(
                                              top: 6,
                                              left: 6,
                                              child: Icon(
                                                Icons.play_circle_fill_rounded,
                                                color: kAccentColor,
                                                size: 22,
                                              ),
                                            )
                                          else if (isWatched)
                                            Positioned(
                                              top: 6,
                                              left: 6,
                                              child: Icon(
                                                Icons.check_circle_rounded,
                                                color: Colors.white.withValues(
                                                  alpha: 0.9,
                                                ),
                                                size: 18,
                                              ),
                                            ),
                                          Positioned(
                                            left: 8,
                                            bottom: 6,
                                            child: Text(
                                              itemNumber.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          if (showProgressBar)
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                height: 3,
                                                color: Colors.white.withValues(
                                                  alpha: 0.25,
                                                ),
                                                child: FractionallySizedBox(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  widthFactor:
                                                      _progressFraction(
                                                        item,
                                                        widget.progressSeconds!,
                                                      ),
                                                  child: const ColoredBox(
                                                    color: kAccentColor,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else if (showWatchedBar)
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                height: 3,
                                                color: Colors.white.withValues(
                                                  alpha: 0.18,
                                                ),
                                                child: FractionallySizedBox(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  widthFactor:
                                                      _progressFraction(
                                                        item,
                                                        watchedInfo!.segundo,
                                                      ),
                                                  child: ColoredBox(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (showProgressBar) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Continuar · ${_formatSeconds(widget.progressSeconds!)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: kAccentColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ] else if (showWatchedBar) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Visto · ${_formatSeconds(watchedInfo!.segundo)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.55,
                                        ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),

        const SizedBox(height: 16),

        // ---- 3) Ficha del capítulo enfocado (título, badge, meta, sinopsis) ----
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ep == null
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final maxSynopsisH = (constraints.maxHeight * 0.55).clamp(
                        36.0,
                        84.0,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Título + badge + meta en el mismo bloque
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              if (epName.isNotEmpty)
                                Text(
                                  epName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                              if (epNumber != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kAccentColor.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'S${widget.currentSeasonNumber.toString().padLeft(2, '0')}E${epNumber.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              if (epAirDate.isNotEmpty)
                                Text(
                                  epAirDate,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (epRuntime != null && epRuntime > 0)
                                Text(
                                  '$epRuntime min',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (epRating > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      epRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          if (directors.isNotEmpty || writers.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            if (directors.isNotEmpty)
                              _MetaLine(
                                label: 'Director',
                                value: directors.take(3).join(', '),
                              ),
                            if (writers.isNotEmpty) ...[
                              if (directors.isNotEmpty)
                                const SizedBox(height: 4),
                              _MetaLine(
                                label: 'Guion',
                                value: writers.take(3).join(', '),
                              ),
                            ],
                          ],
                          if (epOverview.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: maxSynopsisH,
                              ),
                              child: Text(
                                epOverview,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 13.5,
                                  height: 1.38,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ),

        // ---- 4) Reparto: serie + capítulo, una sola fila ----
        _buildCastSection(ep),
      ],
    );
  }
}

/// Panel de recomendaciones:
/// - Slider horizontal de posters arriba
/// - Abajo: logo del seleccionado | info (géneros, fecha, ratings, sinopsis)
/// - Sin título del contenido (ya se ve en el slider)
/// - Sinopsis solo en pantallas grandes; sin encabezado "SUMMARY"
/// - Fondo blur del seleccionado lo gestiona el padre
class _RecommendationsPanel extends StatelessWidget {
  final bool loading;
  final List<Map<String, dynamic>> items;
  final List<FocusNode> focusNodes;
  final ScrollController scrollController;
  final int selectedIndex;
  final ValueNotifier<Map<String, dynamic>?> selectedNotifier;
  final ValueChanged<int> onFocusChanged;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onExit;
  final String Function(Map<String, dynamic>) posterUrlBuilder;

  const _RecommendationsPanel({
    required this.loading,
    required this.items,
    required this.focusNodes,
    required this.scrollController,
    required this.selectedIndex,
    required this.selectedNotifier,
    required this.onFocusChanged,
    required this.onSelect,
    required this.onExit,
    required this.posterUrlBuilder,
  });

  static const double _posterW = 130.0;
  static const double _posterH = 195.0;

  void _scrollTo(int index, {bool animate = true}) {
    if (!scrollController.hasClients) return;
    final max = scrollController.position.maxScrollExtent;
    final target = (index * _kRecoItemExtent) - 12;
    final clamped = target.clamp(0.0, max);
    if (animate) {
      scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      scrollController.jumpTo(clamped);
    }
  }

  String _formatDate(Map item) {
    final raw = (item['release_date'] ?? item['first_air_date'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return '';
    final parts = raw.split('-');
    if (parts.length >= 3) {
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    if (parts.length >= 1) return parts.first;
    return raw;
  }

  double _tmdbRating(Map item) {
    final v = item['vote_average'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  double _imdbRating(Map item) {
    for (final key in ['imdb_rating', 'vote_imdb', 'imdb']) {
      final v = item[key];
      if (v is num && v > 0) return v.toDouble();
      final p = double.tryParse('$v');
      if (p != null && p > 0) return p;
    }
    return 0;
  }

  List<String> _genresOf(Map item) {
    final g = item['genres'];
    if (g is List) {
      final out = <String>[];
      for (final e in g) {
        if (e is String && e.trim().isNotEmpty) {
          out.add(e.trim());
        } else if (e is Map && e['name'] != null) {
          final n = e['name'].toString().trim();
          if (n.isNotEmpty) out.add(n);
        }
      }
      return out;
    }
    return const [];
  }

  String _logoUrl(Map item) {
    final raw = item['logo_path']?.toString() ?? '';
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    return 'https://image.tmdb.org/t/p/w500$raw';
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.8);
    final size = MediaQuery.sizeOf(context);
    final isLarge = size.height >= 520 && size.width >= 720;
    final posterMemW = (_posterW * dpr).round();
    final posterMemH = (_posterH * dpr).round();

    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: kAccentColor),
      );
    }

    if (items.isEmpty) {
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            onExit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_filter_outlined,
                color: Colors.white.withValues(alpha: 0.35),
                size: 48,
              ),
              const SizedBox(height: 14),
              Text(
                'Sin recomendaciones disponibles',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '↑ para volver',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RECOMENDACIONES',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),

        // ---- Slider de posters ----
        SizedBox(
          height: _posterH + 10,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            padding: const EdgeInsets.only(right: 40, left: 2, top: 2),
            clipBehavior: Clip.none,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final item = items[index];
              final poster = posterUrlBuilder(item);
              final isCollection = item['source'] == 'collection';

              return Focus(
                focusNode: focusNodes.length > index ? focusNodes[index] : null,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    onExit();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    if (index > 0) {
                      focusNodes[index - 1].requestFocus();
                      _scrollTo(index - 1);
                    }
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    if (index < focusNodes.length - 1) {
                      focusNodes[index + 1].requestFocus();
                      _scrollTo(index + 1);
                    }
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    onSelect(item);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                onFocusChange: (hasFocus) {
                  if (hasFocus) {
                    onFocusChanged(index);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollTo(index);
                    });
                  }
                },
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () => onSelect(item),
                      child: Container(
                        width: _posterW,
                        margin: const EdgeInsets.only(right: 18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: hasFocus
                                  ? Colors.white
                                  : (isCollection
                                        ? kAccentColor.withValues(alpha: 0.55)
                                        : Colors.transparent),
                              width: hasFocus ? 2.6 : 1.5,
                            ),
                            boxShadow: hasFocus
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                poster.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: poster,
                                        fit: BoxFit.cover,
                                        memCacheWidth: posterMemW,
                                        memCacheHeight: posterMemH,
                                        fadeInDuration: const Duration(
                                          milliseconds: 140,
                                        ),
                                        placeholder: (_, __) =>
                                            Container(color: Colors.grey[900]),
                                        errorWidget: (_, __, ___) => Container(
                                          color: Colors.grey[900],
                                          child: const Icon(
                                            Icons.movie,
                                            color: Colors.white24,
                                          ),
                                        ),
                                      )
                                    : Container(color: Colors.grey[900]),
                                if (isCollection)
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: kAccentColor.withValues(
                                          alpha: 0.92,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'COLECCIÓN',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 22),

        // ---- Detalle: logo | géneros, fecha, ratings, sinopsis (sin título) ----
        Expanded(
          child: ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: selectedNotifier,
            builder: (context, selected, _) {
              if (selected == null) return const SizedBox.shrink();

              final logo = _logoUrl(selected);
              final date = _formatDate(selected);
              final genres = _genresOf(selected);
              final tmdb = _tmdbRating(selected);
              final imdb = _imdbRating(selected);
              final overview = (selected['overview'] ?? '').toString().trim();
              final showSynopsis = isLarge && overview.isNotEmpty;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo del contenido seleccionado
                  SizedBox(
                    width: isLarge ? 220 : 160,
                    height: isLarge ? 90 : 64,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: logo.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: logo,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              fadeInDuration: const Duration(milliseconds: 160),
                              placeholder: (_, __) => const SizedBox.shrink(),
                              errorWidget: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 28),

                  // Información (sin título del contenido)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Géneros primero
                        if (genres.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: genres.take(5).map((g) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  g,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                        if (genres.isNotEmpty) const SizedBox(height: 12),

                        // Fecha + puntuaciones
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 6,
                          children: [
                            if (date.isNotEmpty)
                              Text(
                                date,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (tmdb > 0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    tmdb.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                    size: 17,
                                  ),
                                ],
                              ),
                            if (imdb > 0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'IMDb ${imdb.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),

                        // Sinopsis solo en dispositivos grandes, sin encabezado
                        if (showSynopsis) ...[
                          const SizedBox(height: 14),
                          Expanded(
                            child: Text(
                              overview,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 14,
                                height: 1.42,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),

                        const SizedBox(height: 8),
                        Text(
                          'OK para abrir · ↑ para volver',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  final String label;
  final String value;

  const _MetaLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestStarChip extends StatelessWidget {
  final String name;
  final String character;
  final String photoUrl;

  const _GuestStarChip({
    required this.name,
    required this.character,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: photoUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                    fadeInDuration: Duration.zero,
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.person_rounded,
                      color: Colors.white38,
                      size: 22,
                    ),
                  )
                : const Icon(
                    Icons.person_rounded,
                    color: Colors.white38,
                    size: 22,
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (character.isNotEmpty)
            Text(
              character,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}
