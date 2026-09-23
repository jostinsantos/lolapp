import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../servers/presentation/servers_modal.dart';
import '../../../data/datasources/remote/tmdb/tmdb_content.dart';
import '../../player/presentation/player_controller.dart';
import '../../player/presentation/player_page.dart';
// Ajusta estas rutas a tu estructura
import '../../downloads/presentation/download_manager.dart';
import '../../downloads/presentation/extractor_download_page.dart';
import '../../../supabase/guardados_service.dart';

const kAccentColor = Color(0xFFE50914);
const kPurpleSeason = Color(0xFFC026FF);
const kOrangeVer = Color(0xFFFF6B00);
const kDownloadGreen = Color(0xFF22C55E);

class GuardadosBus {
  GuardadosBus._();
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static void bump() => version.value++;
}

class GuardadosCache {
  /// Delega a GuardadosService (Supabase si hay usuario logueado, cache local si no).
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

  // ── Config descargas ──────────────────────────────────────────────────────
  bool _idmDownloadEnabled = false;
  bool _enableDownloads = true;
  bool _autoDirectDownload = false;

  /// Película completa descargada
  bool _isMovieDownloaded = false;

  /// "T{n}_C{n}" → true si el episodio está descargado
  Map<String, bool> _episodeDownloaded = {};

  bool _showOptions = false;
  bool _playLoading = false;
  String? _loadingEpisodeKey;
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  int get _resolvedTmdbId => widget.tmdbId ?? widget.idcontenido;

  String get _resolvedMediaType {
    final t = widget.mediaType?.toString().toLowerCase();
    if (t == 'tv' || t == 'movie') return t!;
    return 'movie';
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
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
    _animController.dispose();
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
        });
        _loadSavedState();
        _loadProgress();
        _loadEpisodeProgress();
        _loadDownloadedState();
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

    final posterUrl = _firstUrl(data['poster_path']);
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
      'backdrop_path': _firstUrl(data['backdrop_path']),
      'logo_path': _firstUrl(data['logo_path']),
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

    try {
      final loader = ServerLoader();
      await loader.resolvePlayable(
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
          videoUrl: '',
          idcontenido: _resolvedTmdbId,
          tmdbId: _resolvedTmdbId,
          temporada: isMovie ? null : temporada,
          capitulo: isMovie ? null : capitulo,
          tipo: tipo,
          titulo: titulo,
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

  void _toggleOptions() {
    setState(() {
      _showOptions = !_showOptions;
      if (_showOptions) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  Widget _buildTmdbRatingBadge(
    double rating, {
    double iconSize = 18,
    double fontSize = 13,
  }) {
    if (rating <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/tmdb.png',
            width: iconSize,
            height: iconSize,
            errorBuilder: (_, __, ___) =>
                SizedBox(width: iconSize, height: iconSize),
          ),
          const SizedBox(width: 5),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingsBlock({
    required List ratings,
    required double imdbRating,
    required int metaScore,
  }) {
    if (ratings.isEmpty && imdbRating <= 0 && metaScore <= 0) {
      return const SizedBox.shrink();
    }

    const ratingLogos = <String, String>{
      'Internet Movie Database': 'assets/images/imdb.png',
      'Rotten Tomatoes': 'assets/images/rottentomatoes.png',
      'Metacritic': 'assets/images/metacritic.png',
    };

    final children = <Widget>[];

    if (ratings.isNotEmpty) {
      for (final rating in ratings) {
        final source = rating['Source']?.toString() ?? '';
        final value = rating['Value'] ?? '';
        final logoPath = ratingLogos[source] ?? 'assets/images/tmdb.png';
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  logoPath,
                  width: 22,
                  height: 22,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox(width: 22, height: 22),
                ),
                const SizedBox(width: 8),
                Text(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      if (imdbRating > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/imdb.png',
                  width: 22,
                  height: 22,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox(width: 22, height: 22),
                ),
                const SizedBox(width: 8),
                Text(
                  '${imdbRating.toStringAsFixed(1)}/10',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (metaScore > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/metacritic.png',
                  width: 22,
                  height: 22,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox(width: 22, height: 22),
                ),
                const SizedBox(width: 8),
                Text(
                  '$metaScore/100',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccentColor,
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

    List<String> genreNames = [];
    final genresData = data['genres'];
    if (genresData is List) {
      for (final g in genresData) {
        if (g is String && g.isNotEmpty) {
          genreNames.add(g);
        } else if (g is Map && g['name'] != null) {
          genreNames.add(g['name'].toString());
        }
      }
    }

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
          : 'Reproducir';
    } else {
      if (hasEpisodeProgress) {
        playLabel =
            'Reanudar · S${bestTemp.toString().padLeft(2, '0')}E${bestCap.toString().padLeft(2, '0')}';
      } else {
        final firstEp = currentEpisodes.isNotEmpty
            ? (currentEpisodes.first['episode_number'] as int? ?? 1)
            : 1;
        final sNum = currentSeasonNumber > 0 ? currentSeasonNumber : 1;
        playLabel =
            'Reproducir S${sNum.toString().padLeft(2, '0')}E${firstEp.toString().padLeft(2, '0')}';
      }
    }

    final size = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: size.height * 0.68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bgImage.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: bgImage,
                      fit: BoxFit.cover,
                      memCacheWidth: (size.width * 1.2).round().clamp(400, 720),
                      placeholder: (_, __) => Container(color: Colors.black),
                      errorWidget: (_, __, ___) =>
                          Container(color: Colors.black),
                    )
                  else
                    Container(color: Colors.black),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.75),
                          Colors.black,
                        ],
                        stops: const [0.0, 0.35, 0.7, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    top: topPad + 4,
                    left: 8,
                    right: 8,
                    child: Row(
                      children: [
                        _buildCircleButton(
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        if (isMovie) _buildLetterboxdButton(),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: logo.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: logo,
                                  height: 70,
                                  fit: BoxFit.contain,
                                  memCacheHeight: 140,
                                  errorWidget: (_, __, ___) =>
                                      _buildTitle(title),
                                )
                              : _buildTitle(title),
                        ),
                        const SizedBox(height: 12),
                        if (genreNames.isNotEmpty)
                          Center(
                            child: Text(
                              genreNames.take(4).join('  •  '),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (isMovie && _isMovieDownloaded) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: kDownloadGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: kDownloadGreen.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.download_done_rounded,
                                  color: kDownloadGreen,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Descargada',
                                  style: TextStyle(
                                    color: kDownloadGreen,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 200,
                              child: GestureDetector(
                                onTap: _playLoading
                                    ? null
                                    : () {
                                        if (isMovie) {
                                          _openServidores();
                                        } else {
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
                                        }
                                      },
                                child: Container(
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_playLoading)
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.black87,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.black,
                                          size: 28,
                                        ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _playLoading
                                              ? 'Buscando servidor…'
                                              : playLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizeTransition(
                              sizeFactor: _scaleAnim,
                              axis: Axis.horizontal,
                              axisAlignment: -1,
                              child: FadeTransition(
                                opacity: _fadeAnim,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildCircleAction(
                                      icon: _isSaved
                                          ? Icons.check_circle
                                          : Icons.check_circle_outline,
                                      isActive: _isSaved,
                                      activeColor: Colors.greenAccent,
                                      onTap: _toggleSaved,
                                    ),
                                    if (isMovie && _enableDownloads) ...[
                                      const SizedBox(width: 8),
                                      _buildCircleAction(
                                        icon: _isMovieDownloaded
                                            ? Icons.download_done_rounded
                                            : Icons.download_rounded,
                                        isActive: _isMovieDownloaded,
                                        activeColor: kDownloadGreen,
                                        onTap: () => _startDownload(),
                                      ),
                                    ],
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _toggleOptions,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: _showOptions
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.more_vert,
                                  color: _showOptions
                                      ? Colors.black
                                      : Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (year.isNotEmpty)
                                  Text(
                                    year,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                if (year.isNotEmpty && runtime != null)
                                  Text(
                                    '  •  ',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                if (runtime != null)
                                  Text(
                                    '$runtime min',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'HD',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (voteAverage > 0) ...[
                                  const SizedBox(width: 10),
                                  _buildTmdbRatingBadge(voteAverage),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (director != null && director.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              isMovie
                                  ? 'Director: $director'
                                  : 'Creado por: $director',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRatingsBlock(
                    ratings: ratings,
                    imdbRating: imdbRating,
                    metaScore: metaScore,
                  ),

                  if (overview.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Sinopsis',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        if (overview.length > 120) {
                          setState(
                            () => _overviewExpanded = !_overviewExpanded,
                          );
                        }
                      },
                      child: Text(
                        overview,
                        maxLines: _overviewExpanded ? null : 3,
                        overflow: _overviewExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                  if (cast.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Text(
                      'Elenco',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 130,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: cast.length.clamp(0, 12),
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, i) {
                          final c = cast[i];
                          final name = c['name']?.toString() ?? '';
                          final character = c['character']?.toString() ?? '';
                          final photo = _profileUrl(c['profile_path']);
                          return SizedBox(
                            width: 80,
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 36,
                                  backgroundColor: const Color(0xFF2C2C2E),
                                  backgroundImage: photo.isNotEmpty
                                      ? CachedNetworkImageProvider(photo)
                                      : null,
                                  child: photo.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.white38,
                                          size: 32,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (character.isNotEmpty)
                                  Text(
                                    character,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (videos.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Text(
                      'Videos',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: videos.length.clamp(0, 8),
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final v = videos[i];
                          final key = v['key']?.toString() ?? '';
                          final name = v['name']?.toString() ?? 'Trailer';
                          final thumb =
                              'https://img.youtube.com/vi/$key/mqdefault.jpg';
                          return GestureDetector(
                            onTap: () => _openYoutube(key),
                            child: SizedBox(
                              width: 200,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          CachedNetworkImage(
                                            imageUrl: thumb,
                                            fit: BoxFit.cover,
                                            memCacheWidth: 280,
                                            errorWidget: (_, __, ___) =>
                                                Container(
                                                  color: Colors.grey[900],
                                                ),
                                          ),
                                          const Center(
                                            child: Icon(
                                              Icons.play_circle_fill_rounded,
                                              color: Colors.white,
                                              size: 44,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
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
                  if (!isMovie && seasons.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Text(
                      'Temporadas y Episodios',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: seasons.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final season = seasons[i];
                          final name =
                              season['name']?.toString() ??
                              'Temporada ${season['season_number']}';
                          final selected = i == _selectedSeasonIndex;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedSeasonIndex = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? kPurpleSeason
                                    : const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        final epName =
                            ep['name']?.toString() ?? 'Episodio $epNumber';
                        final still = _stillUrl(ep['still_path']);
                        final epRating =
                            (ep['vote_average'] as num?)?.toDouble() ?? 0;
                        final epRuntime = ep['runtime'] as int?;
                        final seenSec = _progressForEpisode(
                          currentSeasonNumber,
                          epNumber,
                        );
                        final hasSeen = seenSec != null && seenSec > 5;
                        final progressFactor = hasSeen
                            ? (seenSec! / ((epRuntime ?? 45) * 60)).clamp(
                                0.06,
                                1.0,
                              )
                            : 0.0;
                        final isDownloaded = _isEpisodeDownloaded(
                          currentSeasonNumber,
                          epNumber,
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap:
                                  (_playLoading || _loadingEpisodeKey != null)
                                  ? null
                                  : () => _openServidores(
                                      temporada: currentSeasonNumber,
                                      capitulo: epNumber,
                                    ),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 110,
                                        height: 62,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            still.isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: still,
                                                    fit: BoxFit.cover,
                                                    memCacheWidth: 220,
                                                    memCacheHeight: 124,
                                                    placeholder: (_, __) =>
                                                        Container(
                                                          color: const Color(
                                                            0xFF2C2C2E,
                                                          ),
                                                        ),
                                                    errorWidget: (_, __, ___) =>
                                                        Container(
                                                          color: const Color(
                                                            0xFF2C2C2E,
                                                          ),
                                                          child: const Icon(
                                                            Icons.movie,
                                                            color:
                                                                Colors.white24,
                                                          ),
                                                        ),
                                                  )
                                                : Container(
                                                    color: const Color(
                                                      0xFF2C2C2E,
                                                    ),
                                                    child: const Icon(
                                                      Icons.movie,
                                                      color: Colors.white24,
                                                    ),
                                                  ),
                                            if (hasSeen)
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  height: 3.5,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.25),
                                                  child: FractionallySizedBox(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    widthFactor: progressFactor,
                                                    child: Container(
                                                      color: kOrangeVer,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (hasSeen)
                                              Positioned(
                                                top: 4,
                                                right: 4,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.75,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    _formatTime(seenSec!),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (isDownloaded)
                                              Positioned(
                                                top: 4,
                                                left: 4,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: kDownloadGreen
                                                        .withValues(
                                                          alpha: 0.95,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.download_done_rounded,
                                                    color: Colors.white,
                                                    size: 12,
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'E${epNumber.toString().padLeft(2, '0')} · $epName',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              if (epRating > 0)
                                                _buildTmdbRatingBadge(
                                                  epRating,
                                                  iconSize: 14,
                                                  fontSize: 12,
                                                ),
                                              if (hasSeen) ...[
                                                if (epRating > 0)
                                                  const SizedBox(width: 8),
                                                Text(
                                                  'Visto · ${_formatTime(seenSec!)}',
                                                  style: TextStyle(
                                                    color: kOrangeVer
                                                        .withValues(
                                                          alpha: 0.95,
                                                        ),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                              if (isDownloaded) ...[
                                                if (epRating > 0 || hasSeen)
                                                  const SizedBox(width: 8),
                                                Text(
                                                  'Descargado',
                                                  style: TextStyle(
                                                    color: kDownloadGreen
                                                        .withValues(
                                                          alpha: 0.95,
                                                        ),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_loadingEpisodeKey ==
                                        'T${currentSeasonNumber}_C$epNumber')
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: kOrangeVer,
                                          ),
                                        ),
                                      )
                                    else if (_enableDownloads)
                                      GestureDetector(
                                        onTap: () => _startDownload(
                                          temporada: currentSeasonNumber,
                                          capitulo: epNumber,
                                        ),
                                        behavior: HitTestBehavior.opaque,
                                        child: Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.15,
                                              ),
                                            ),
                                          ),
                                          child: Icon(
                                            isDownloaded
                                                ? Icons.download_done_rounded
                                                : Icons.download_rounded,
                                            color: isDownloaded
                                                ? kDownloadGreen
                                                : Colors.white,
                                            size: 22,
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
                  if (similar.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Text(
                      'Contenido Similar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 180,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: similar.length.clamp(0, 12),
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
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
                            onTap: () {
                              if (sId > 0) {
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
                              }
                            },
                            child: SizedBox(
                              width: 110,
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
                                              width: 110,
                                              memCacheWidth: 160,
                                              placeholder: (_, __) => Container(
                                                color: const Color(0xFF2C2C2E),
                                              ),
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                    color: const Color(
                                                      0xFF2C2C2E,
                                                    ),
                                                    child: const Icon(
                                                      Icons.movie,
                                                      color: Colors.white24,
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              color: const Color(0xFF2C2C2E),
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
                                      fontSize: 12,
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
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(String title) {
    return Text(
      title,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.5,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildLetterboxdButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: IconButton(
        icon: Image.asset(
          'assets/images/letterboxd.png',
          width: 36,
          height: 36,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.movie, color: Colors.white70, size: 28);
          },
        ),
        onPressed: _openLetterboxd,
        tooltip: 'Abrir en Letterboxd',
        style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
      ),
    );
  }

  Widget _buildCircleAction({
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Color(0xFF2a2a2a),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? activeColor : Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
