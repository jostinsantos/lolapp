//app 2
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../servers/presentation/servers_modal.dart';
import '../../../data/datasources/remote/tmdb/tmdb_content.dart';
import '../../player/presentation/player_controller.dart';
import '../../player/presentation/player_page.dart';
import '../../downloads/presentation/download_manager.dart';
import '../../downloads/presentation/extractor_download_page.dart';
import '../../../supabase/guardados_service.dart';
import 'widgets/tmdb_upcoming_service.dart';
import 'widgets/upcoming_episodes_modal.dart';
import '../../foryou/presentation/like_button.dart';

// ── Design tokens ──────────────────────────────────────────────────────────
const kBg = Color(0xFF000000);
const kAccent = Color(0xFF9B1B30); // rojo vino (legacy, poco uso)
const kAccentDark = Color(0xFF7A1526);
const kSelected = Color(0xFF4A2A5A); // morado oscuro para seleccionados
const kSelectedLight = Color(0xFF6B3D7A);
const kGlass = Color(0xB31A1A1A);
const kGlassBorder = Color(0x14FFFFFF);
const kCardBg = Color(0xE6121212);
const kOrangeVer = Color(0xFFFF6B00);
const kDownloadGreen = Color(0xFF22C55E);
const kPurpleSeason = Color(0xFFC026FF);

class GuardadosBus {
  GuardadosBus._();
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static void bump() => version.value++;
}

class GuardadosCache {
  static Future<List<Map<String, dynamic>>> getAll() async {
    return GuardadosService.getAll();
  }

  static Future<bool> isSaved(int idcontenido) async {
    return GuardadosService.isSaved(idcontenido);
  }

  static Future<bool> toggle(Map<String, dynamic> item) async {
    final result = await GuardadosService.toggle(item);
    GuardadosBus.bump();
    return result;
  }
}

class PageContenido extends StatefulWidget {
  final int idcontenido;
  final int? tmdbId;
  final String? mediaType;

  const PageContenido({
    super.key,
    required this.idcontenido,
    this.tmdbId,
    this.mediaType,
  });

  @override
  State<PageContenido> createState() => _PageContenidoState();
}

class _PageContenidoState extends State<PageContenido>
    with SingleTickerProviderStateMixin {
  final TmdbContentService _tmdb = TmdbContentService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  int _selectedSeasonIndex = 0;
  bool _isSaved = false;
  Map<String, dynamic>? _progress;

  Map<String, int> _episodeProgress = {};
  bool _overviewExpanded = false;

  bool _idmDownloadEnabled = false;
  bool _enableDownloads = true;
  bool _autoDirectDownload = false;

  bool _isMovieDownloaded = false;
  Map<String, bool> _episodeDownloaded = {};

  bool _playLoading = false;
  String? _loadingEpisodeKey;

  bool _isSeriesAiring = false;

  // Tabs: Movie 0=Resumen 1=Cast 2=Videos | TV 0=Resumen 1=Capítulos 2=Cast 3=Videos
  int _selectedTab = 0;

  int get _resolvedTmdbId => widget.tmdbId ?? widget.idcontenido;

  String get _resolvedMediaType {
    final t = widget.mediaType?.toString().toLowerCase();
    if (t == 'tv' || t == 'movie') return t!;
    return 'movie';
  }

  @override
  void initState() {
    super.initState();
    GuardadosBus.version.addListener(_onProgressBus);
    _loadDownloadSettings();
    _fetchContent();
  }

  void _onProgressBus() {
    if (!mounted) return;
    _loadProgress();
    _loadEpisodeProgress();
    _loadDownloadedState();
  }

  @override
  void dispose() {
    GuardadosBus.version.removeListener(_onProgressBus);
    super.dispose();
  }

  Future<void> _loadDownloadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _idmDownloadEnabled = prefs.getBool('idm_download_enabled') ?? false;
      _enableDownloads = prefs.getBool('enable_downloads') ?? true;
      _autoDirectDownload = prefs.getBool('auto_direct_download') ?? false;
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

      if (json['success'] == true && json['data'] is Map) {
        setState(() {
          _data = Map<String, dynamic>.from(json['data'] as Map);
          _loading = false;
          _selectedSeasonIndex = 0;
          final isMovie =
              (_data?['type']?.toString() ?? _resolvedMediaType) == 'movie';
          _selectedTab = isMovie ? 0 : 1; // TV defaults to Capítulos
        });
        _loadSavedState();
        _loadProgress();
        _loadEpisodeProgress();
        _loadDownloadedState();
        _checkAiring();
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
    final saved = await GuardadosCache.isSaved(_resolvedTmdbId);
    if (mounted) setState(() => _isSaved = saved);
  }

  Future<void> _loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = _resolvedTmdbId;

      Map<String, dynamic>? best;
      DateTime? bestTs;

      void consider(String? raw) {
        if (raw == null || raw.isEmpty) return;
        try {
          final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          final sec = data['segundo'] as int?;
          if (sec == null || sec <= 5) return;
          DateTime? ts;
          final tsRaw = data['timestamp']?.toString();
          if (tsRaw != null && tsRaw.isNotEmpty) {
            ts = DateTime.tryParse(tsRaw);
          }
          final better =
              best == null ||
              (ts != null && (bestTs == null || ts.isAfter(bestTs!))) ||
              (ts == null &&
                  bestTs == null &&
                  sec > ((best!['segundo'] as int?) ?? 0));
          if (better) {
            best = data;
            bestTs = ts;
          }
        } catch (_) {}
      }

      consider(prefs.getString('cachePlayer_$id'));
      consider(prefs.getString('cachePlayerRapido_$id'));

      final prefixFull = 'cachePlayer_${id}_T';
      final prefixRapido = 'cachePlayerRapido_${id}_T';
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefixFull) || key.startsWith(prefixRapido)) {
          consider(prefs.getString(key));
        }
      }

      if (mounted) {
        setState(() => _progress = best);
      }
    } catch (_) {}
  }

  Future<void> _loadEpisodeProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, int>{};
      final seasons = _seasons;

      for (final season in seasons) {
        final tNum = season['season_number'];
        if (tNum == null) continue;
        final eps = List<Map<String, dynamic>>.from(season['episodes'] ?? []);
        for (final ep in eps) {
          final cNum = ep['episode_number'];
          if (cNum == null) continue;

          final keyRapido =
              'cachePlayerRapido_${_resolvedTmdbId}_T${tNum}_C$cNum';
          final keyFull = 'cachePlayer_${_resolvedTmdbId}_T${tNum}_C$cNum';

          String? raw = prefs.getString(keyRapido);
          raw ??= prefs.getString(keyFull);
          if (raw == null) continue;

          try {
            final data = jsonDecode(raw);
            final sec = data['segundo'] as int?;
            if (sec != null && sec > 5) {
              map['T${tNum}_C$cNum'] = sec;
            }
          } catch (_) {}
        }
      }

      if (mounted) setState(() => _episodeProgress = map);
    } catch (e) {
      debugPrint('Error cargando progreso episodios: $e');
    }
  }

  Future<void> _loadDownloadedState() async {
    try {
      final isMovie =
          (_data?['type']?.toString() ?? _resolvedMediaType) == 'movie';

      if (isMovie) {
        final ok = await DownloadManager.isDownloaded(
          tmdbId: _resolvedTmdbId,
          tipo: 'movie',
        );
        if (mounted) setState(() => _isMovieDownloaded = ok);
        return;
      }

      final map = <String, bool>{};
      for (final season in _seasons) {
        final tNum = season['season_number'];
        if (tNum == null) continue;
        final t = tNum is int ? tNum : int.tryParse('$tNum');
        if (t == null) continue;

        final eps = List<Map<String, dynamic>>.from(season['episodes'] ?? []);
        for (final ep in eps) {
          final cNum = ep['episode_number'];
          if (cNum == null) continue;
          final c = cNum is int ? cNum : int.tryParse('$cNum');
          if (c == null) continue;

          final ok = await DownloadManager.isDownloaded(
            tmdbId: _resolvedTmdbId,
            tipo: 'tv',
            temporada: t,
            capitulo: c,
          );
          if (ok) map['T${t}_C$c'] = true;
        }
      }
      if (mounted) setState(() => _episodeDownloaded = map);
    } catch (e) {
      debugPrint('Error cargando estado descargas: $e');
    }
  }

  int? _progressForEpisode(int seasonNumber, int episodeNumber) {
    return _episodeProgress['T${seasonNumber}_C$episodeNumber'];
  }

  bool _isEpisodeDownloaded(int seasonNumber, int episodeNumber) {
    return _episodeDownloaded['T${seasonNumber}_C$episodeNumber'] == true;
  }

  Future<void> _toggleSaved() async {
    if (_data == null) return;
    final data = _data!;

    final tipo = (data['type'] ?? data['media_type'] ?? _resolvedMediaType)
        .toString()
        .toLowerCase();

    // 🔧 Helper: convierte path relativo TMDB → URL completa
    String buildTmdbUrl(dynamic value, {String size = 'w500'}) {
      if (value == null) return '';
      String s = value.toString().trim();
      if (s.isEmpty || s == 'null' || s == 'undefined') return '';

      // Si ya es URL completa, devolverla
      if (s.startsWith('http://') || s.startsWith('https://')) return s;

      // Lista JSON-like: ["/abc.jpg"] → extraer primer elemento
      if (s.startsWith('[')) {
        try {
          final list = jsonDecode(s.replaceAll("'", '"'));
          if (list is List && list.isNotEmpty) {
            return buildTmdbUrl(list.first, size: size);
          }
        } catch (_) {}
        return '';
      }

      // Path relativo → URL completa
      final path = s.startsWith('/') ? s : '/$s';
      return 'https://image.tmdb.org/t/p/$size$path';
    }

    final posterUrl = buildTmdbUrl(data['poster_path'], size: 'w500');
    final backdropUrl = buildTmdbUrl(data['backdrop_path'], size: 'w780');
    final logoUrl = buildTmdbUrl(data['logo_path'], size: 'w500');

    final item = <String, dynamic>{
      'idcontenido': _resolvedTmdbId,
      'tmdb_id': _resolvedTmdbId,
      'idtmdb': _resolvedTmdbId,
      'tipo': tipo,
      'type': tipo,
      'media_type': tipo,
      'title': data['title'] ?? data['titulo_contenido'] ?? '',
      'titulo': data['title'] ?? data['titulo_contenido'] ?? '',
      'poster': posterUrl,
      'poster_path': posterUrl,
      'posterUrl': posterUrl, // 👈 alias extra por seguridad
      'backdrop_path': backdropUrl,
      'backdrop': backdropUrl, // 👈 alias extra
      'backdropUrl': backdropUrl, // 👈 alias extra
      'logo_path': logoUrl,
      'vote_average': data['vote_average'],
      'overview': data['overview'] ?? '',
      'release_date': data['release_date'] ?? data['first_air_date'],
      'addedAt': DateTime.now().toIso8601String(),
    };

    final nowSaved = await GuardadosCache.toggle(item);
    if (mounted) setState(() => _isSaved = nowSaved);
  }

  List<Map<String, dynamic>> get _seasons =>
      List<Map<String, dynamic>>.from(_data?['seasons'] ?? []);

  List<Map<String, dynamic>> get _currentEpisodes {
    final seasons = _seasons;
    if (seasons.isEmpty) return [];
    final idx = _selectedSeasonIndex.clamp(0, seasons.length - 1);
    return List<Map<String, dynamic>>.from(seasons[idx]['episodes'] ?? []);
  }

  List<Map<String, dynamic>> get _cast =>
      List<Map<String, dynamic>>.from(_data?['cast'] ?? []);

  List<Map<String, dynamic>> get _similar =>
      List<Map<String, dynamic>>.from(_data?['similar'] ?? []);

  Map<String, dynamic>? get _collection {
    final c = _data?['collection'];
    if (c is Map) return Map<String, dynamic>.from(c);
    return null;
  }

  List<Map<String, dynamic>> get _collectionParts {
    final c = _collection;
    if (c == null) return [];
    return List<Map<String, dynamic>>.from(c['parts'] ?? []);
  }

  List<Map<String, dynamic>> get _videos {
    final videos = _data?['videos'];
    if (videos is! Map) return [];
    final es = List<Map<String, dynamic>>.from(videos['es'] ?? []);
    final en = List<Map<String, dynamic>>.from(videos['en'] ?? []);
    return [...es, ...en];
  }

  String _firstUrl(dynamic value) {
    if (value == null) return '';
    String str = value.toString().trim();

    if (str.startsWith('http') && !str.contains('[')) return str;

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

  String _profileUrl(dynamic path) {
    if (path == null) return '';
    final s = path.toString();
    if (s.startsWith('http')) return s;
    if (s.isEmpty || s == 'null') return '';
    return 'https://image.tmdb.org/t/p/w92$s';
  }

  String _stillUrl(dynamic path) {
    if (path == null) return '';
    final s = path.toString();
    if (s.startsWith('http')) return s;
    if (s.isEmpty || s == 'null') return '';
    return 'https://image.tmdb.org/t/p/w300$s';
  }

  String _formatTime(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
    }
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  String _formatRuntime(dynamic runtime) {
    if (runtime == null) return '';
    final n = runtime is num ? runtime.toInt() : int.tryParse('$runtime') ?? 0;
    if (n <= 0) return '';
    if (n >= 60) {
      final h = n ~/ 60;
      final m = n % 60;
      return m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h';
    }
    return '${n} min';
  }

  // ── Modal de episodio ─────────────────────────────────────────────────────
  Future<void> _openEpisodeModal({
    required int seasonNumber,
    required int episodeNumber,
    required Map<String, dynamic> epBasic,
  }) async {
    final seenSec = _progressForEpisode(seasonNumber, episodeNumber);
    final hasSeen = seenSec != null && seenSec > 5;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _EpisodeDetailModal(
          tmdbId: _resolvedTmdbId,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          epBasic: epBasic,
          seriesTitle: _data?['title']?.toString() ?? '',
          seriesBackdrop: _firstUrl(_data?['backdrop_path']),
          seenSeconds: hasSeen ? seenSec : null,
          onPlay: () {
            Navigator.pop(ctx);
            _openServidores(temporada: seasonNumber, capitulo: episodeNumber);
          },
          tmdbService: _tmdb,
          formatTime: _formatTime,
          stillUrl: _stillUrl,
          profileUrl: _profileUrl,
        );
      },
    );
  }

  // ── Reproducir ────────────────────────────────────────────────────────────
  Future<void> _openServidores({
    int? temporada,
    int? capitulo,
    bool forDownload = false,
  }) async {
    final data = _data;
    final tipo = data?['type']?.toString() ?? _resolvedMediaType;
    final titulo = data?['title']?.toString() ?? '';

    if (forDownload) {
      await _startDownload(temporada: temporada, capitulo: capitulo);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final modo = prefs.getString('seleccionar_servidores') ?? 'auto';

    if (modo != 'auto') {
      _showServidoresModal(
        temporada: temporada,
        capitulo: capitulo,
        forDownload: false,
        tipo: tipo,
        titulo: titulo,
      );
      return;
    }

    if (!mounted || _playLoading) return;
    final isMovie = tipo.toLowerCase() != 'tv';

    final epKey = (!isMovie && temporada != null && capitulo != null)
        ? 'T${temporada}_C$capitulo'
        : null;

    setState(() {
      _playLoading = true;
      if (epKey != null) _loadingEpisodeKey = epKey;
    });

    PlayableSource? source;
    try {
      final loader = ServerLoader();
      source = await loader.resolvePlayable(
        contentId: _resolvedTmdbId,
        isMovie: isMovie,
        season: isMovie ? 0 : (temporada ?? 0),
        episode: isMovie ? 0 : (capitulo ?? 0),
        context: mounted ? context : null,
      );
    } catch (e) {
      debugPrint('Precarga ServerLoader: $e');
    }

    if (!mounted) return;
    setState(() {
      _playLoading = false;
      _loadingEpisodeKey = null;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoUrl: source?.url ?? '',
          idcontenido: _resolvedTmdbId,
          tmdbId: _resolvedTmdbId,
          temporada: isMovie ? null : temporada,
          capitulo: isMovie ? null : capitulo,
          tipo: tipo,
          titulo: titulo,
          idioma: source?.idioma,
          headers: source?.headers,
        ),
      ),
    );
    if (mounted) {
      _loadProgress();
      _loadEpisodeProgress();
      _loadDownloadedState();
    }
  }

  // ── Descargas ─────────────────────────────────────────────────────────────
  Future<void> _startDownload({int? temporada, int? capitulo}) async {
    if (!_enableDownloads) return;

    final data = _data;
    final tipo = data?['type']?.toString() ?? _resolvedMediaType;
    final titulo = data?['title']?.toString() ?? '';

    if (_autoDirectDownload) {
      await _autoDownloadAndOpenExtractor(
        temporada: temporada,
        capitulo: capitulo,
        tipo: tipo,
        titulo: titulo,
      );
      return;
    }

    _showServidoresModal(
      temporada: temporada,
      capitulo: capitulo,
      forDownload: true,
      tipo: tipo,
      titulo: titulo,
    );
  }

  Future<void> _autoDownloadAndOpenExtractor({
    int? temporada,
    int? capitulo,
    required String tipo,
    required String titulo,
  }) async {
    if (!mounted || _playLoading) return;

    final isMovie = tipo.toLowerCase() != 'tv';
    final epKey = (!isMovie && temporada != null && capitulo != null)
        ? 'T${temporada}_C$capitulo'
        : null;

    setState(() {
      _playLoading = true;
      if (epKey != null) _loadingEpisodeKey = epKey;
    });

    String? resolvedUrl;
    String servidorNombre = 'Auto';

    try {
      final loader = ServerLoader();
      final PlayableSource? source = await loader.resolvePlayable(
        contentId: _resolvedTmdbId,
        isMovie: isMovie,
        season: isMovie ? 0 : (temporada ?? 0),
        episode: isMovie ? 0 : (capitulo ?? 0),
        context: mounted ? context : null,
      );

      if (source != null && source.url.isNotEmpty) {
        resolvedUrl = source.url;
        if (source.serverName.isNotEmpty) {
          servidorNombre = source.serverName;
        }
      }

      if (resolvedUrl == null || resolvedUrl.isEmpty) {
        resolvedUrl = await _readCachedPlayableUrl(
          isMovie: isMovie,
          temporada: temporada,
          capitulo: capitulo,
        );
      }
    } catch (e) {
      debugPrint('Auto download resolve error: $e');
      resolvedUrl = await _readCachedPlayableUrl(
        isMovie: isMovie,
        temporada: temporada,
        capitulo: capitulo,
      );
    }

    if (!mounted) return;
    setState(() {
      _playLoading = false;
      _loadingEpisodeKey = null;
    });

    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      _showServidoresModal(
        temporada: temporada,
        capitulo: capitulo,
        forDownload: true,
        tipo: tipo,
        titulo: titulo,
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExtractorDownloadPage(
          idcontenido: _resolvedTmdbId,
          temporada: isMovie ? null : temporada,
          capitulo: isMovie ? null : capitulo,
          servidorUrl: resolvedUrl!,
          servidorNombre: servidorNombre,
          tipo: tipo,
          titulo: titulo,
          tmdbId: _resolvedTmdbId,
          posterUrl: _firstUrl(_data?['poster_path']),
          backdropUrl: _firstUrl(_data?['backdrop_path']),
        ),
      ),
    );

    if (mounted) {
      _loadDownloadedState();
      _loadProgress();
      _loadEpisodeProgress();
    }
  }

  Future<String?> _readCachedPlayableUrl({
    required bool isMovie,
    int? temporada,
    int? capitulo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = _resolvedTmdbId;
      final keys = <String>[];

      if (isMovie) {
        keys.addAll([
          'serv_cache_$id',
          'cachePlayer_$id',
          'cachePlayerRapido_$id',
        ]);
      } else if (temporada != null && capitulo != null) {
        keys.addAll([
          'serv_cache_${id}_T${temporada}_C$capitulo',
          'cachePlayer_${id}_T${temporada}_C$capitulo',
          'cachePlayerRapido_${id}_T${temporada}_C$capitulo',
        ]);
      }

      for (final key in keys) {
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final data = jsonDecode(raw);
          if (data is Map) {
            final url =
                data['url']?.toString() ??
                data['playableUrl']?.toString() ??
                data['m3u8']?.toString() ??
                data['videoUrl']?.toString();
            if (url != null &&
                url.isNotEmpty &&
                (url.contains('.m3u8') ||
                    url.contains('.mp4') ||
                    url.startsWith('http'))) {
              return url;
            }
          } else if (data is String &&
              (data.contains('.m3u8') ||
                  data.contains('.mp4') ||
                  data.startsWith('http'))) {
            return data;
          }
        } catch (_) {
          if (raw.contains('.m3u8') ||
              raw.contains('.mp4') ||
              raw.startsWith('http')) {
            return raw;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  void _showServidoresModal({
    int? temporada,
    int? capitulo,
    bool forDownload = false,
    required String tipo,
    required String titulo,
  }) {
    final data = _data;
    showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: false,
      builder: (_) => ServidoresModal(
        idcontenido: _resolvedTmdbId,
        temporada: temporada,
        capitulo: capitulo,
        tipo: tipo,
        titulo: titulo,
        forDownload: forDownload,
        backdropUrl: _firstUrl(data?['backdrop_path']),
        posterUrl: _firstUrl(data?['poster_path']),
        logoUrl: _firstUrl(data?['logo_path']),
      ),
    ).then((_) {
      _loadProgress();
      _loadEpisodeProgress();
      _loadDownloadedState();
    });
  }

  Future<void> _openYoutube(String key) async {
    if (key.isEmpty) return;
    final uri = Uri.parse('https://www.youtube.com/watch?v=$key');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error opening YouTube: $e');
    }
  }

  Future<void> _openLetterboxd() async {
    if (_data == null) return;

    String? imdbId = _data!['imdb_id']?.toString();
    if (imdbId == null || imdbId.isEmpty) {
      imdbId = _data!['external_ids']?['imdb_id']?.toString();
    }
    if (imdbId == null || imdbId.isEmpty) {
      imdbId = _data!['imdb_data']?['imdbID']?.toString();
    }

    if (imdbId == null || imdbId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró ID de IMDb'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF1a1a1a),
          ),
        );
      }
      return;
    }

    final url = 'https://letterboxd.com/imdb/$imdbId';
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error opening Letterboxd: $e');
    }
  }

  Future<void> _checkAiring() async {
    final isMovie =
        (_data?['type']?.toString() ?? _resolvedMediaType) == 'movie';
    if (isMovie) {
      if (mounted) setState(() => _isSeriesAiring = false);
      return;
    }
    final status = (_data?['status']?.toString() ?? '').toLowerCase().trim();
    var airing =
        status == 'returning series' ||
        status == 'in production' ||
        status == 'planned';

    if (!airing && status.isEmpty) {
      try {
        airing = await TmdbUpcomingService().isSeriesAiring(_resolvedTmdbId);
      } catch (_) {}
    }

    if (mounted) setState(() => _isSeriesAiring = airing);
  }

  void _openUpcomingReminders() {
    final title = _data?['title']?.toString() ?? '';
    UpcomingEpisodesModal.show(
      context: context,
      tmdbId: _resolvedTmdbId,
      seriesTitle: title,
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: kBg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Esqueleto
            Column(
              children: [
                Container(height: 280, color: const Color(0xFF111111)),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 110,
                        height: 162,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 22,
                              width: 180,
                              color: const Color(0xFF1A1A1A),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              height: 12,
                              width: 120,
                              color: const Color(0xFF1A1A1A),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 12,
                              width: 80,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
            // Spinner
            Center(
              child: Image.asset(
                'assets/spiner.gif',
                width: 64,
                height: 64,
                errorBuilder: (_, __, ___) =>
                    const CircularProgressIndicator(color: kAccent),
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null || _data == null) {
      return Scaffold(
        backgroundColor: kBg,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                ),
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
    final bgImage = backdrop.isNotEmpty ? backdrop : poster;
    final logo = _firstUrl(data['logo_path']);

    final voteAverage = (data['vote_average'] as num?)?.toDouble() ?? 0;
    final imdbRating =
        double.tryParse(
          data['imdb_rating']?.toString() ??
              data['vote_imdb']?.toString() ??
              '',
        ) ??
        0;
    final metaScore =
        int.tryParse(data['imdb_data']?['Metascore']?.toString() ?? '') ?? 0;
    final List ratings = data['imdb_data']?['Ratings'] as List? ?? [];

    dynamic runtime = data['runtime'];
    if (runtime == null) {
      final epRuntimes = data['episode_run_time'];
      if (epRuntimes is List && epRuntimes.isNotEmpty) {
        runtime = epRuntimes.first;
      }
    }

    final year = (data['release_date'] ?? data['first_air_date'] ?? '')
        .toString()
        .split('-')
        .first;
    final director = data['director']?.toString();
    final seasons = _seasons;
    final currentEpisodes = _currentEpisodes;
    final cast = _cast;
    final similar = _similar;
    final videos = _videos;
    final collectionParts = _collectionParts;
    final collectionName = _collection?['name']?.toString() ?? 'Colección';

    final status = (data['status']?.toString() ?? '').trim();
    final statusLabel = status.isNotEmpty
        ? (status.toLowerCase().contains('released') ||
                  status.toLowerCase().contains('ended')
              ? 'Estrenado'
              : status)
        : '';

    int currentSeasonNumber = 1;
    if (!isMovie && seasons.isNotEmpty) {
      final safeIndex = _selectedSeasonIndex.clamp(0, seasons.length - 1);
      currentSeasonNumber = seasons[safeIndex]['season_number'] ?? 1;
    }

    final int? resumeSec = _progress?['segundo'] as int?;
    final bool hasProgress = resumeSec != null && resumeSec > 5;

    final int? bestTemp = (_progress?['temporada'] as num?)?.toInt();
    final int? bestCap = (_progress?['capitulo'] as num?)?.toInt();
    final bool hasEpisodeProgress =
        hasProgress &&
        bestTemp != null &&
        bestTemp > 0 &&
        bestCap != null &&
        bestCap > 0;

    String playLabel;
    if (isMovie) {
      playLabel = hasProgress
          ? 'Reanudar · ${_formatTime(resumeSec!)}'
          : 'Ver ahora';
    } else {
      if (hasEpisodeProgress) {
        playLabel =
            'Reanudar · S${bestTemp.toString().padLeft(2, '0')}E${bestCap.toString().padLeft(2, '0')}';
      } else {
        playLabel = 'Ver ahora';
      }
    }

    final topPad = MediaQuery.paddingOf(context).top;
    final size = MediaQuery.sizeOf(context);

    final tabLabels = isMovie
        ? ['Resumen', 'Cast', 'Videos']
        : ['Resumen', 'Capítulos', 'Cast', 'Videos'];

    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 380,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bgImage.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: bgImage,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      // HD backdrop
                      memCacheWidth: (size.width * 2).round().clamp(720, 1280),
                      placeholder: (_, __) => Container(color: kBg),
                      errorWidget: (_, __, ___) => Container(color: kBg),
                    )
                  else
                    Container(color: kBg),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          kBg.withValues(alpha: 0.2),
                          kBg.withValues(alpha: 0.5),
                          kBg.withValues(alpha: 0.9),
                          kBg,
                        ],
                        stops: const [0.0, 0.4, 0.75, 1.0],
                      ),
                    ),
                  ),
                  // Solo atrás + notificaciones (TV airing). Sin menú 4 puntos.
                  Positioned(
                    top: topPad + 8,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        _glassCircleBtn(
                          icon: Icons.chevron_left_rounded,
                          onTap: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        if (!isMovie && _isSeriesAiring)
                          _glassCircleBtn(
                            icon: Icons.notifications_none_rounded,
                            onTap: _openUpcomingReminders,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Poster (P) + meta: zona1 logo | zona3 info + zona2 ratings ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // ── Zona P: Poster HD con blur shadow ──
                  Container(
                    width: 110,
                    height: 162,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.7),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: poster,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            placeholder: (_, __) =>
                                Container(color: const Color(0xFF1A1A1A)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF1A1A1A),
                              child: const Icon(
                                Icons.movie,
                                color: Colors.white24,
                              ),
                            ),
                          )
                        : Container(color: const Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(width: 14),
                  // Derecha: zona 1 (logo) + fila (zona 3 info | zona 2 ratings)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Zona 1: Logo o título (izquierda) ──
                        if (logo.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 52,
                              maxWidth: 220,
                            ),
                            child: CachedNetworkImage(
                              imageUrl: logo,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              memCacheHeight: 104,
                              errorWidget: (_, __, ___) => Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
                              ),
                            ),
                          )
                        else
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                          ),
                        const SizedBox(height: 10),
                        // ── Debajo del logo: 2 columnas ──
                        // Columna 3 (mayor) = info | Columna 2 (menor) = ratings
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Zona 3 — info (columna más ancha)
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (director != null &&
                                      director.isNotEmpty) ...[
                                    Text.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.55,
                                          ),
                                          fontSize: 11.5,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: isMovie
                                                ? 'Dirigida por '
                                                : 'Creado por ',
                                          ),
                                          TextSpan(
                                            text: director,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.9,
                                              ),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 5),
                                  ],
                                  // Año · Estado
                                  Row(
                                    children: [
                                      if (year.isNotEmpty)
                                        Text(
                                          year,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.6,
                                            ),
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      if (year.isNotEmpty &&
                                          statusLabel.isNotEmpty)
                                        Text(
                                          '  ·  ',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.3,
                                            ),
                                            fontSize: 10,
                                          ),
                                        ),
                                      if (statusLabel.isNotEmpty)
                                        Text(
                                          statusLabel,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.75,
                                            ),
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Badges Runtime / Age
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (runtime != null)
                                        _metaBadge(
                                          _formatRuntime(runtime),
                                          sub: 'Runtime',
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Zona 2 — ratings vertical (columna más estrecha)
                            _buildVerticalRatings(
                              ratings: ratings,
                              imdbRating: imdbRating,
                              metaScore: metaScore,
                              tmdb: voteAverage,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Play + acciones ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                children: [
                  if (isMovie)
                    _playButton(
                      label: _playLoading ? 'Buscando servidor…' : playLabel,
                      loading: _playLoading,
                      onTap: _playLoading ? null : () => _openServidores(),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _playButton(
                            label: _playLoading ? 'Buscando…' : playLabel,
                            loading: _playLoading,
                            onTap: _playLoading
                                ? null
                                : () {
                                    final temp = hasEpisodeProgress
                                        ? bestTemp
                                        : (currentSeasonNumber > 0
                                              ? currentSeasonNumber
                                              : 1);
                                    final cap = hasEpisodeProgress
                                        ? bestCap
                                        : (currentEpisodes.isNotEmpty
                                              ? (currentEpisodes
                                                            .first['episode_number']
                                                        as int? ??
                                                    1)
                                              : 1);
                                    _openServidores(
                                      temporada: temp,
                                      capitulo: cap,
                                    );
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        _savePillButton(),
                      ],
                    ),

                  // Movie: grid de acciones + Me gusta (IA)
                  if (isMovie) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _actionTile(
                            icon: _isSaved
                                ? Icons.bookmark
                                : Icons.bookmark_border_rounded,
                            label: 'Watchlist',
                            active: _isSaved,
                            onTap: _toggleSaved,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LikeContentButton(
                            tmdbId: _resolvedTmdbId,
                            title: (_data?['title'] ?? _data?['name'] ?? '').toString(),
                            mediaType: _resolvedMediaType,
                            genres: ((_data?['genres'] as List?) ?? [])
                                .map((g) => (g is Map ? g['name'] : g).toString())
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_enableDownloads)
                          Expanded(
                            child: _actionTile(
                              icon: _isMovieDownloaded
                                  ? Icons.download_done_rounded
                                  : Icons.download_rounded,
                              label: _isMovieDownloaded
                                  ? 'Descargada'
                                  : 'Descargar',
                              active: _isMovieDownloaded,
                              activeColor: kDownloadGreen,
                              onTap: () => _startDownload(),
                            ),
                          ),
                        if (_enableDownloads) const SizedBox(width: 8),
                        Expanded(
                          child: _actionTile(
                            iconWidget: Image.asset(
                              'assets/images/letterboxd.png',
                              width: 18,
                              height: 18,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.movie_outlined,
                                size: 18,
                                color: Colors.white70,
                              ),
                            ),
                            label: 'Letterboxd',
                            onTap: _openLetterboxd,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionTile(
                            icon: Icons.replay_rounded,
                            label: 'Desde inicio',
                            onTap: () => _openServidores(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Tabs ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: kGlass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kGlassBorder),
                ),
                child: Row(
                  children: List.generate(tabLabels.length, (i) {
                    final selected = _selectedTab == i;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: selected ? kSelected : null,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: kSelected.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            tabLabels[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white54,
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),

          // ── Tab content (scroll de página, sin scroll interno) ───────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildTabContent(
                isMovie: isMovie,
                overview: overview,
                cast: cast,
                videos: videos,
                seasons: seasons,
                currentEpisodes: currentEpisodes,
                currentSeasonNumber: currentSeasonNumber,
              ),
            ),
          ),

          // ── Colección ────────────────────────────────────────────────────
          if (collectionParts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: kGlass,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kGlassBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          collectionName.isNotEmpty
                              ? collectionName
                              : 'Ver colección',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (collectionParts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: collectionParts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final s = collectionParts[i];
                      final sTitle = s['title']?.toString() ?? '';
                      final sPoster = _firstUrl(s['poster_path']);
                      final sId =
                          s['tmdb_id'] as int? ??
                          s['idcontenido'] as int? ??
                          s['id'] as int? ??
                          0;
                      final isCurrent = sId == _resolvedTmdbId;
                      return GestureDetector(
                        onTap: isCurrent || sId <= 0
                            ? null
                            : () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PageContenido(
                                      idcontenido: sId,
                                      tmdbId: sId,
                                      mediaType: 'movie',
                                    ),
                                  ),
                                );
                              },
                        child: Opacity(
                          opacity: isCurrent ? 0.5 : 1,
                          child: SizedBox(
                            width: 100,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: sPoster.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: sPoster,
                                            fit: BoxFit.cover,
                                            width: 100,
                                            // baja calidad
                                            memCacheWidth: 160,
                                            placeholder: (_, __) => Container(
                                              color: const Color(0xFF1A1A1A),
                                            ),
                                            errorWidget: (_, __, ___) =>
                                                Container(
                                                  color: const Color(
                                                    0xFF1A1A1A,
                                                  ),
                                                ),
                                          )
                                        : Container(
                                            color: const Color(0xFF1A1A1A),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  sTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

          // ── Similares ────────────────────────────────────────────────────
          if (similar.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contenido similar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: similar.length.clamp(0, 12),
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          final s = similar[i];
                          final sTitle = s['title']?.toString() ?? '';
                          final sPoster = _firstUrl(s['poster_path']);
                          final sId =
                              s['tmdb_id'] as int? ??
                              s['idcontenido'] as int? ??
                              s['id'] as int? ??
                              0;
                          final sType =
                              s['media_type']?.toString() ??
                              s['type']?.toString() ??
                              (isMovie ? 'movie' : 'tv');
                          return GestureDetector(
                            onTap: sId <= 0
                                ? null
                                : () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PageContenido(
                                          idcontenido: sId,
                                          tmdbId: sId,
                                          mediaType: sType,
                                        ),
                                      ),
                                    );
                                  },
                            child: SizedBox(
                              width: 100,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: sPoster.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: sPoster,
                                              fit: BoxFit.cover,
                                              width: 100,
                                              // baja calidad
                                              memCacheWidth: 160,
                                              placeholder: (_, __) => Container(
                                                color: const Color(0xFF1A1A1A),
                                              ),
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                    color: const Color(
                                                      0xFF1A1A1A,
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              color: const Color(0xFF1A1A1A),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    sTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  // ── Tab content ───────────────────────────────────────────────────────────
  Widget _buildTabContent({
    required bool isMovie,
    required String overview,
    required List<Map<String, dynamic>> cast,
    required List<Map<String, dynamic>> videos,
    required List<Map<String, dynamic>> seasons,
    required List<Map<String, dynamic>> currentEpisodes,
    required int currentSeasonNumber,
  }) {
    final tab = _selectedTab;

    if ((!isMovie && tab == 0) || (isMovie && tab == 0)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overview.isNotEmpty) ...[
            GestureDetector(
              onTap: () {
                if (overview.length > 140) {
                  setState(() => _overviewExpanded = !_overviewExpanded);
                }
              },
              child: Text(
                overview,
                maxLines: _overviewExpanded ? null : 4,
                overflow: _overviewExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildDatosSection(_data!, isMovie),
        ],
      );
    }

    if (!isMovie && tab == 1) {
      return _buildEpisodesSection(
        seasons: seasons,
        currentEpisodes: currentEpisodes,
        currentSeasonNumber: currentSeasonNumber,
      );
    }

    final isCastTab = isMovie ? tab == 1 : tab == 2;
    if (isCastTab) {
      return _buildCastSection(cast);
    }

    return _buildVideosSection(videos);
  }

  Widget _buildEpisodesSection({
    required List<Map<String, dynamic>> seasons,
    required List<Map<String, dynamic>> currentEpisodes,
    required int currentSeasonNumber,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (seasons.length > 1)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final season = seasons[i];
                final name =
                    season['name']?.toString() ?? 'T${season['season_number']}';
                final selected = i == _selectedSeasonIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSeasonIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? kSelected : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? kSelected
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      name,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (seasons.length > 1) const SizedBox(height: 14),

        if (currentEpisodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No hay capítulos disponibles',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          )
        else
          ...List.generate(currentEpisodes.length, (index) {
            final ep = currentEpisodes[index];
            final epNumber = ep['episode_number'] as int? ?? 0;
            final epName = ep['name']?.toString() ?? 'Episodio $epNumber';
            final still = _stillUrl(ep['still_path']);
            final epRuntime = ep['runtime'] as int?;
            final seenSec = _progressForEpisode(currentSeasonNumber, epNumber);
            final hasSeen = seenSec != null && seenSec > 5;
            final progressFactor = hasSeen
                ? (seenSec! / ((epRuntime ?? 45) * 60)).clamp(0.06, 1.0)
                : 0.0;
            final isDownloaded = _isEpisodeDownloaded(
              currentSeasonNumber,
              epNumber,
            );
            final isLoadingThis =
                _loadingEpisodeKey == 'T${currentSeasonNumber}_C$epNumber';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: kGlass,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: (_playLoading || isLoadingThis)
                      ? null
                      : () => _openEpisodeModal(
                          seasonNumber: currentSeasonNumber,
                          episodeNumber: epNumber,
                          epBasic: ep,
                        ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 96,
                            height: 56,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                still.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: still,
                                        fit: BoxFit.cover,
                                        // baja calidad stills
                                        memCacheWidth: 200,
                                        placeholder: (_, __) => Container(
                                          color: const Color(0xFF1A1A1A),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: const Color(0xFF1A1A1A),
                                          child: const Icon(
                                            Icons.movie,
                                            color: Colors.white24,
                                            size: 20,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: const Color(0xFF1A1A1A),
                                        child: const Icon(
                                          Icons.movie,
                                          color: Colors.white24,
                                          size: 20,
                                        ),
                                      ),
                                Center(
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: hasSeen
                                          ? kAccent.withValues(alpha: 0.95)
                                          : Colors.white.withValues(
                                              alpha: 0.25,
                                            ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      size: 16,
                                      color: hasSeen
                                          ? Colors.white
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                                if (epRuntime != null && epRuntime > 0)
                                  Positioned(
                                    bottom: 3,
                                    right: 3,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        '$epRuntime min',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (hasSeen)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      height: 2.5,
                                      color: Colors.white24,
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: progressFactor,
                                        child: Container(color: kAccent),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Capítulo $epNumber',
                                style: TextStyle(
                                  color: hasSeen ? kAccent : Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                epName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (hasSeen) ...[
                                const SizedBox(height: 3),
                                Text(
                                  'Visto · ${_formatTime(seenSec!)}',
                                  style: TextStyle(
                                    color: kAccent.withValues(alpha: 0.95),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isLoadingThis)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kAccent,
                            ),
                          )
                        else if (_enableDownloads)
                          GestureDetector(
                            onTap: () => _startDownload(
                              temporada: currentSeasonNumber,
                              capitulo: epNumber,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                isDownloaded
                                    ? Icons.download_done_rounded
                                    : Icons.download_rounded,
                                size: 20,
                                color: isDownloaded
                                    ? kDownloadGreen
                                    : Colors.white54,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCastSection(List<Map<String, dynamic>> cast) {
    if (cast.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Sin datos de elenco',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return Column(
      children: cast.take(20).map((c) {
        final name = c['name']?.toString() ?? '';
        final character = c['character']?.toString() ?? '';
        final photo = _profileUrl(c['profile_path']);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: kGlass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kGlassBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      kAccent.withValues(alpha: 0.35),
                      const Color(0xFF8A4FFF).withValues(alpha: 0.25),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(1.5),
                child: CircleAvatar(
                  backgroundColor: const Color(0xFF111111),
                  backgroundImage: photo.isNotEmpty
                      ? CachedNetworkImageProvider(photo)
                      : null,
                  child: photo.isEmpty
                      ? const Icon(
                          Icons.person,
                          color: Colors.white38,
                          size: 20,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (character.isNotEmpty)
                      Text(
                        character,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildVideosSection(List<Map<String, dynamic>> videos) {
    if (videos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No hay videos disponibles',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return Column(
      children: videos.take(10).map((v) {
        final key = v['key']?.toString() ?? '';
        final name = v['name']?.toString() ?? 'Trailer';
        final type = v['type']?.toString() ?? '';
        final thumb = 'https://img.youtube.com/vi/$key/mqdefault.jpg';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => _openYoutube(key),
            child: Container(
              decoration: BoxDecoration(
                color: kGlass,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kGlassBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          memCacheWidth: 480,
                          errorWidget: (_, __, ___) =>
                              Container(color: const Color(0xFF1A1A1A)),
                        ),
                        Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: kAccent.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: kAccent,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (type.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              type,
                              style: TextStyle(
                                color: kAccent.withValues(alpha: 0.9),
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDatosSection(Map<String, dynamic> data, bool isMovie) {
    final rows = <MapEntry<String, String>>[];

    void add(String label, dynamic value) {
      if (value == null) return;
      final s = value.toString().trim();
      if (s.isEmpty || s == 'null' || s == '0' || s == '—') return;
      rows.add(MapEntry(label, s));
    }

    add('Estado', data['status']);
    add('Idioma original', data['original_language']?.toString().toUpperCase());
    if (isMovie) {
      add(
        'Duración',
        data['runtime'] != null ? '${data['runtime']} min' : null,
      );
    } else {
      add(
        'Temporadas',
        data['number_of_seasons_tmdb'] ?? data['number_of_seasons'],
      );
      add(
        'Episodios',
        data['number_of_episodes_tmdb'] ?? data['number_of_episodes'],
      );
      if (data['last_air_date'] != null) {
        add(
          'Última emisión',
          data['last_air_date']?.toString().split('T').first,
        );
      }
    }

    final countries = data['production_countries'];
    if (countries is List && countries.isNotEmpty) {
      add('Países', countries.join(', '));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Datos',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kGlass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kGlassBorder),
          ),
          child: Column(
            children: rows.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────
  Widget _metaBadge(String value, {String? sub}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub != null)
                  TextSpan(
                    text: ' $sub',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassCircleBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.9),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  /// Ratings uno encima de otro (vertical)
  Widget _buildVerticalRatings({
    required List ratings,
    required double imdbRating,
    required int metaScore,
    required double tmdb,
  }) {
    final children = <Widget>[];

    void addRow(String? asset, String value, {Color? color}) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (asset != null)
                Image.asset(
                  asset,
                  width: 16,
                  height: 16,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              if (asset != null) const SizedBox(width: 5),
              Text(
                value,
                style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (ratings.isNotEmpty) {
      for (final r in ratings.take(3)) {
        final source = r['Source']?.toString() ?? '';
        final value = r['Value']?.toString() ?? '';
        String? asset;
        if (source.contains('Internet Movie')) {
          asset = 'assets/images/imdb.png';
        } else if (source.contains('Rotten')) {
          asset = 'assets/images/rottentomatoes.png';
        } else if (source.contains('Metacritic')) {
          asset = 'assets/images/metacritic.png';
        }
        addRow(asset, value);
      }
    } else {
      if (imdbRating > 0) {
        addRow(
          'assets/images/imdb.png',
          imdbRating.toStringAsFixed(1),
          color: Colors.amber,
        );
      }
      if (metaScore > 0) {
        addRow('assets/images/metacritic.png', '$metaScore');
      }
    }

    if (tmdb > 0) {
      addRow(
        'assets/images/tmdb.png',
        tmdb.toStringAsFixed(1),
        color: const Color(0xFF01B4E4),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _playButton({
    required String label,
    required bool loading,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFF333333),
                ),
              )
            else
              const Icon(
                Icons.play_arrow_rounded,
                color: Color(0xFF222222),
                size: 24,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _savePillButton() {
    return GestureDetector(
      onTap: _toggleSaved,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _isSaved ? kSelected : kGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isSaved
                ? kSelectedLight.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSaved ? Icons.bookmark : Icons.bookmark_border_rounded,
              size: 18,
              color: _isSaved ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              _isSaved ? 'Guardado' : 'Guardar',
              style: TextStyle(
                color: _isSaved ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    bool active = false,
    Color? activeColor,
    required VoidCallback onTap,
  }) {
    final color = active ? (activeColor ?? kSelectedLight) : Colors.white70;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: kGlass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kGlassBorder),
        ),
        child: Column(
          children: [
            iconWidget ?? Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Modal de detalle de episodio
// ═══════════════════════════════════════════════════════════════════════════

class _EpisodeDetailModal extends StatefulWidget {
  final int tmdbId;
  final int seasonNumber;
  final int episodeNumber;
  final Map<String, dynamic> epBasic;
  final String seriesTitle;
  final String seriesBackdrop;
  final int? seenSeconds;
  final VoidCallback onPlay;
  final TmdbContentService tmdbService;
  final String Function(int) formatTime;
  final String Function(dynamic) stillUrl;
  final String Function(dynamic) profileUrl;

  const _EpisodeDetailModal({
    required this.tmdbId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.epBasic,
    required this.seriesTitle,
    required this.seriesBackdrop,
    required this.seenSeconds,
    required this.onPlay,
    required this.tmdbService,
    required this.formatTime,
    required this.stillUrl,
    required this.profileUrl,
  });

  @override
  State<_EpisodeDetailModal> createState() => _EpisodeDetailModalState();
}

class _EpisodeDetailModalState extends State<_EpisodeDetailModal> {
  Map<String, dynamic>? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _detail = Map<String, dynamic>.from(widget.epBasic);
      _loading = true;
    });

    try {
      final res = await widget.tmdbService.fetchEpisode(
        tmdbId: widget.tmdbId,
        seasonNumber: widget.seasonNumber,
        episodeNumber: widget.episodeNumber,
      );
      if (res['success'] == true && res['data'] is Map && mounted) {
        setState(() {
          _detail = Map<String, dynamic>.from(res['data'] as Map);
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ep = _detail ?? widget.epBasic;
    final name = ep['name']?.toString() ?? 'Episodio ${widget.episodeNumber}';
    final overview = ep['overview']?.toString() ?? '';
    final still = widget.stillUrl(ep['still_path']);
    final runtime = ep['runtime'] as int?;
    final rating = (ep['vote_average'] as num?)?.toDouble() ?? 0;
    final airDate = (ep['air_date']?.toString() ?? '').split('T').first;
    final guestStars = List<Map<String, dynamic>>.from(ep['guest_stars'] ?? []);
    final hasSeen = widget.seenSeconds != null && widget.seenSeconds! > 5;

    final playLabel = hasSeen
        ? 'Reanudar · ${widget.formatTime(widget.seenSeconds!)}'
        : 'Ver ahora';

    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: still.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: still,
                              fit: BoxFit.cover,
                              memCacheWidth: 480,
                              placeholder: (_, __) =>
                                  Container(color: const Color(0xFF1A1A1A)),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF1A1A1A),
                                child: const Icon(
                                  Icons.movie,
                                  color: Colors.white24,
                                  size: 48,
                                ),
                              ),
                            )
                          : Container(
                              color: const Color(0xFF1A1A1A),
                              child: const Icon(
                                Icons.movie,
                                color: Colors.white24,
                                size: 48,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'S${widget.seasonNumber.toString().padLeft(2, '0')}E${widget.episodeNumber.toString().padLeft(2, '0')} · $name',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      if (runtime != null && runtime > 0)
                        Text(
                          '$runtime min',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 13,
                          ),
                        ),
                      if (rating > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 15,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      if (airDate.isNotEmpty)
                        Text(
                          airDate,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: widget.onPlay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(
                        hasSeen
                            ? Icons.replay_rounded
                            : Icons.play_arrow_rounded,
                        size: 24,
                      ),
                      label: Text(
                        playLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (overview.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Sinopsis',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      overview,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    )
                  else if (guestStars.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Actores invitados',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: guestStars.length.clamp(0, 12),
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          final g = guestStars[i];
                          final gName = g['name']?.toString() ?? '';
                          final gChar = g['character']?.toString() ?? '';
                          final photo = widget.profileUrl(g['profile_path']);
                          return SizedBox(
                            width: 70,
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: const Color(0xFF1A1A1A),
                                  backgroundImage: photo.isNotEmpty
                                      ? CachedNetworkImageProvider(photo)
                                      : null,
                                  child: photo.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.white38,
                                          size: 24,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  gName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (gChar.isNotEmpty)
                                  Text(
                                    gChar,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
