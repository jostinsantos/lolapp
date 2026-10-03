import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/models/scraper/detalle_model.dart';
import '../../../data/scrapers/base/detalle_scraper.dart';
import '../../../data/datasources/remote/tmdb/tmdb_content.dart';
import '../../content/presentation/tv_content_page.dart';
import '../../servers/presentation/tv_servers_modal_fuentes.dart';
const kAccentColor = Color(0xFFE50914);
const kBgColor = Colors.black;
const kCardBg = Color(0xFF1a1a2e);
const double _kEpisodeItemExtent = 98.0;

class DerivarTvPage extends StatefulWidget {
  final String servicio;
  final String url;
  final String titulo;
  final String tipo;

  const DerivarTvPage({
    super.key,
    required this.servicio,
    required this.url,
    required this.titulo,
    required this.tipo,
  });

  @override
  State<DerivarTvPage> createState() => _DerivarTvPageState();
}

class _DerivarTvPageState extends State<DerivarTvPage> {
  bool _loading = true;
  String? _error;
  DetalleContenido? _data;
  int _selectedSeasonIndex = 0;
  bool _nativePromptShown = false;

  String _tmdbPoster = '';
  String _tmdbBackdrop = '';
  String _tmdbLogo = '';
  String _tmdbOverview = '';
  double? _tmdbRating;
  String _tmdbYear = '';
  List<String> _tmdbGenres = [];

  final FocusNode _playFocusNode = FocusNode();
  List<FocusNode> _seasonFocusNodes = [];
  List<FocusNode> _episodeFocusNodes = [];
  final ScrollController _episodeScrollController = ScrollController();

  final TmdbContentService _tmdb = TmdbContentService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _playFocusNode.dispose();
    _episodeScrollController.dispose();
    for (final n in _seasonFocusNodes) {
      n.dispose();
    }
    for (final n in _episodeFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _tmdbPoster = '';
      _tmdbBackdrop = '';
      _tmdbLogo = '';
      _tmdbOverview = '';
      _tmdbRating = null;
      _tmdbYear = '';
      _tmdbGenres = [];
      _nativePromptShown = false;
    });

    final res = await DetalleScraper.fetch(
      servicio: widget.servicio,
      url: widget.url,
      titulo: widget.titulo,
      tipo: widget.tipo,
    );

    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _error = res.error ?? 'Error al cargar';
        _loading = false;
      });
      return;
    }

    setState(() {
      _data = res;
      _loading = false;
      _selectedSeasonIndex = 0;
    });
    _resyncFocusNodes();

    await _enrichFromTmdb(res);

    if (!mounted) return;
    final tmdbId = res.tmdbId ?? 0;
    if (tmdbId > 0 && !_nativePromptShown) {
      _nativePromptShown = true;
      await _askOpenNative(tmdbId, _resolveMediaType(res));
    }
  }

  Future<void> _askOpenNative(int tmdbId, String mediaType) async {
    if (!mounted) return;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final nativeFocus = FocusNode();
        final fuenteFocus = FocusNode();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          nativeFocus.requestFocus();
        });

        Widget option({
          required FocusNode node,
          required FocusNode other,
          required String title,
          required String subtitle,
          required IconData icon,
          required String value,
          required bool primary,
        }) {
          return Focus(
            focusNode: node,
            onKeyEvent: (n, e) {
              if (e is! KeyDownEvent) return KeyEventResult.ignored;
              if (e.logicalKey == LogicalKeyboardKey.arrowDown ||
                  e.logicalKey == LogicalKeyboardKey.arrowUp) {
                other.requestFocus();
                return KeyEventResult.handled;
              }
              if (e.logicalKey == LogicalKeyboardKey.select ||
                  e.logicalKey == LogicalKeyboardKey.enter) {
                Navigator.of(ctx).pop(value);
                return KeyEventResult.handled;
              }
              if (e.logicalKey == LogicalKeyboardKey.escape ||
                  e.logicalKey == LogicalKeyboardKey.goBack ||
                  e.logicalKey == LogicalKeyboardKey.backspace) {
                Navigator.of(ctx).pop('fuente');
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final hasFocus = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: hasFocus
                          ? (primary
                              ? kAccentColor.withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.12))
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hasFocus
                            ? (primary ? kAccentColor : Colors.white)
                            : Colors.white.withValues(alpha: 0.08),
                        width: hasFocus ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: hasFocus
                                ? (primary
                                    ? kAccentColor.withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.12))
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            icon,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasFocus)
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white70,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }

        return Dialog(
          backgroundColor: const Color(0xFF16161C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.open_in_new_rounded,
                    color: kAccentColor,
                    size: 36,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '¿Cómo quieres abrirlo?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hay datos nativos de TMDB para este contenido.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 22),
                  option(
                    node: nativeFocus,
                    other: fuenteFocus,
                    title: 'Vista nativa',
                    subtitle: 'Abrir ficha completa de la app',
                    icon: Icons.movie_filter_rounded,
                    value: 'nativa',
                    primary: true,
                  ),
                  option(
                    node: fuenteFocus,
                    other: nativeFocus,
                    title: 'Seguir en la fuente',
                    subtitle: 'Quedarte en esta vista de servidores',
                    icon: Icons.cloud_rounded,
                    value: 'fuente',
                    primary: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (choice == 'nativa') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PageContenido(
            idcontenido: tmdbId,
            tmdbId: tmdbId,
            mediaType: mediaType,
          ),
        ),
      );
    }
  }

  Future<void> _enrichFromTmdb(DetalleContenido data) async {
    final tmdbId = data.tmdbId ?? 0;
    if (tmdbId <= 0) return;

    final mediaType = _resolveMediaType(data);
    try {
      final result = await _tmdb.fetchContent(
        tmdbId: tmdbId,
        mediaType: mediaType,
      );
      if (!mounted) return;
      if (result['success'] != true) return;

      final map = result['data'];
      if (map is! Map<String, dynamic>) return;

      final poster = (map['poster_path']?.toString() ?? '').trim();
      final backdrop = (map['backdrop_path']?.toString() ?? '').trim();
      final logo = (map['logo_path']?.toString() ?? '').trim();
      final overview = (map['overview']?.toString() ?? '').trim();

      double? rating;
      final va = map['vote_average'];
      if (va is num && va > 0) {
        rating = va.toDouble();
      } else if (map['imdb_rating'] is num && (map['imdb_rating'] as num) > 0) {
        rating = (map['imdb_rating'] as num).toDouble();
      }

      String year = '';
      final rd = (map['release_date'] ?? map['first_air_date'] ?? '')
          .toString()
          .trim();
      if (rd.length >= 4) year = rd.substring(0, 4);

      final genres = <String>[];
      if (map['genres'] is List) {
        for (final g in map['genres'] as List) {
          if (g is Map && g['name'] != null) {
            final name = g['name'].toString().trim();
            if (name.isNotEmpty) genres.add(name);
          }
        }
      }

      setState(() {
        if (poster.isNotEmpty) _tmdbPoster = poster;
        if (backdrop.isNotEmpty) _tmdbBackdrop = backdrop;
        if (logo.isNotEmpty) _tmdbLogo = logo;
        if (overview.isNotEmpty) _tmdbOverview = overview;
        if (rating != null && rating > 0) _tmdbRating = rating;
        if (year.isNotEmpty) _tmdbYear = year;
        if (genres.isNotEmpty) _tmdbGenres = genres;
      });
    } catch (_) {}
  }

  String _resolveMediaType(DetalleContenido data) {
    final t = (data.tipo ?? widget.tipo).toLowerCase();
    if (t == 'tv' ||
        t == 'serie' ||
        t == 'series' ||
        t == 'anime' ||
        t.contains('show')) {
      return 'tv';
    }
    return 'movie';
  }

  bool get _isMovie {
    final t = (_data?.tipo ?? widget.tipo).toLowerCase();
    return t == 'movie' || t == 'pelicula' || t == 'película';
  }

  bool get _usaUrlCapitulo {
    final s = widget.servicio.trim().toLowerCase().replaceAll(' ', '');
    return s == 'animejk' ||
        s == 'jkanime' ||
        s == 'jk' ||
        (_data?.servicio.toLowerCase() == 'animejk');
  }

  List<DetalleTemporada> get _temporadas => _data?.temporadas ?? [];

  List<DetalleCapitulo> get _currentEpisodes {
    if (_temporadas.isEmpty) return [];
    final idx = _selectedSeasonIndex.clamp(0, _temporadas.length - 1);
    return _temporadas[idx].episodios;
  }

  void _resyncFocusNodes() {
    for (final n in _seasonFocusNodes) {
      n.dispose();
    }
    _seasonFocusNodes = List.generate(_temporadas.length, (_) => FocusNode());
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

  void _selectSeason(int index) {
    setState(() => _selectedSeasonIndex = index);
    _resyncEpisodeFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToPreferredEpisode(animate: true);
    });
  }

  void _scrollToPreferredEpisode({bool animate = true}) {
    if (!_episodeScrollController.hasClients) return;
    final episodes = _currentEpisodes;
    if (episodes.isEmpty) return;

    const idx = 0;
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

  void _openServersModal({DetalleCapitulo? cap}) {
    if (_usaUrlCapitulo) {
      final episodeUrl =
          (cap?.url.isNotEmpty == true) ? cap!.url : widget.url;
      if (episodeUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay URL para buscar servidores'),
            backgroundColor: kCardBg,
          ),
        );
        return;
      }
    } else {
      final tmdbId = _data?.tmdbId ?? 0;
      if (tmdbId <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay TMDB ID para buscar servidores'),
            backgroundColor: kCardBg,
          ),
        );
        return;
      }
    }

    final tmdbId = _data?.tmdbId ?? 0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ServidoresModalFuentesTv(
        tmdbId: tmdbId,
        idcontenido: tmdbId > 0 ? tmdbId : null,
        temporada: _isMovie ? null : (cap?.temporada ?? 1),
        capitulo: _isMovie ? null : (cap?.numero ?? 1),
        tipo: _data?.tipo ?? widget.tipo,
        titulo: _data?.titulo ?? widget.titulo,
        backdropUrl: _effectiveBackdrop.isNotEmpty
            ? _effectiveBackdrop
            : _data?.backdrop,
        posterUrl:
            _effectivePoster.isNotEmpty ? _effectivePoster : _data?.poster,
        logoUrl: _effectiveLogo.isNotEmpty ? _effectiveLogo : _data?.logo,
        fuente: widget.servicio,
      ),
    );
  }

  String get _effectivePoster {
    if (_tmdbPoster.isNotEmpty) return _tmdbPoster;
    return (_data?.poster ?? '').trim();
  }

  String get _effectiveBackdrop {
    if (_tmdbBackdrop.isNotEmpty) return _tmdbBackdrop;
    return (_data?.backdrop ?? '').trim();
  }

  String get _effectiveOverview {
    if (_tmdbOverview.isNotEmpty) return _tmdbOverview;
    return (_data?.sinopsis ?? '').trim();
  }

  String get _effectiveLogo {
    if (_tmdbLogo.isNotEmpty) return _tmdbLogo;
    return (_data?.logo ?? '').trim();
  }

  double get _effectiveRating {
    if (_tmdbRating != null && _tmdbRating! > 0) return _tmdbRating!;
    return _data?.rating ?? 0.0;
  }

  String get _effectiveYear {
    if (_tmdbYear.isNotEmpty) return _tmdbYear;
    return (_data?.anio ?? '').trim();
  }

  List<String> get _effectiveGenres {
    if (_tmdbGenres.isNotEmpty) return _tmdbGenres;
    return _data?.generos ?? [];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
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
                style: const TextStyle(color: Colors.white70, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _TvElevatedButton(
                label: 'Reintentar',
                onPressed: _load,
                autofocus: true,
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    final isMovie = _isMovie;
    final title = data.titulo;
    final overview = _effectiveOverview;
    final poster = _effectivePoster;
    final backdrop = _effectiveBackdrop;
    final logo = _effectiveLogo;
    final bgImage = backdrop.isNotEmpty ? backdrop : poster;
    final ratingValue = _effectiveRating;
    final year = _effectiveYear;
    final genres = _effectiveGenres;
    final seasons = _temporadas;
    final currentEpisodes = _currentEpisodes;

    if (_seasonFocusNodes.length != seasons.length) {
      _resyncFocusNodes();
    }

    int currentSeasonNumber = 1;
    if (!isMovie && seasons.isNotEmpty) {
      final safeIndex = _selectedSeasonIndex.clamp(0, seasons.length - 1);
      currentSeasonNumber = seasons[safeIndex].numero;
    }

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
                    placeholder: (_, _) => Container(color: Colors.black),
                    errorWidget: (_, _, _) =>
                        Container(color: Colors.black),
                  )
                : Container(color: Colors.black),
          ),
          const _ContenidoOverlayGradient(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(44, 20, 44, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: isMovie ? 6 : 5,
                    child: _InfoColumn(
                      title: title,
                      logoUrl: logo,
                      overview: overview,
                      ratingValue: ratingValue,
                      year: year,
                      genres: genres,
                      playFocusNode: _playFocusNode,
                      onPlay: () {
                        if (isMovie) {
                          _openServersModal();
                        } else if (currentEpisodes.isNotEmpty) {
                          _openServersModal(cap: currentEpisodes.first);
                        } else {
                          _openServersModal();
                        }
                      },
                      onRequestRight: isMovie
                          ? null
                          : () {
                              if (_seasonFocusNodes.isNotEmpty) {
                                _seasonFocusNodes[_selectedSeasonIndex.clamp(
                                  0,
                                  _seasonFocusNodes.length - 1,
                                )].requestFocus();
                              } else if (_episodeFocusNodes.isNotEmpty) {
                                _episodeFocusNodes[0].requestFocus();
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 36),
                  Expanded(
                    flex: 4,
                    child: isMovie
                        ? RepaintBoundary(
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
                                          placeholder: (_, _) => Container(
                                            color: Colors.grey[900],
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (_, _, _) =>
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
                          )
                        : _SeasonsAndEpisodesPanel(
                            seasons: seasons,
                            selectedSeasonIndex: _selectedSeasonIndex,
                            episodes: currentEpisodes,
                            seasonFocusNodes: _seasonFocusNodes,
                            episodeFocusNodes: _episodeFocusNodes,
                            episodeScrollController: _episodeScrollController,
                            onSeasonSelected: _selectSeason,
                            onEpisodeTap: (ep) => _openServersModal(cap: ep),
                            onRequestLeft: () => _playFocusNode.requestFocus(),
                            currentSeasonNumber: currentSeasonNumber,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

class _InfoColumn extends StatelessWidget {
  final String title;
  final String logoUrl;
  final String overview;
  final double ratingValue;
  final String year;
  final List<String> genres;
  final FocusNode playFocusNode;
  final VoidCallback onPlay;
  final VoidCallback? onRequestRight;

  const _InfoColumn({
    required this.title,
    required this.logoUrl,
    required this.overview,
    required this.ratingValue,
    required this.year,
    required this.genres,
    required this.playFocusNode,
    required this.onPlay,
    this.onRequestRight,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logoUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 340,
                maxHeight: 110,
              ),
              child: CachedNetworkImage(
                imageUrl: logoUrl,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                fadeInDuration: const Duration(milliseconds: 180),
                errorWidget: (_, _, _) => Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          )
        else
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 22),
        Focus(
          autofocus: true,
          focusNode: playFocusNode,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                onRequestRight != null) {
              onRequestRight!();
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
                    horizontal: 26,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: hasFocus
                        ? kAccentColor
                        : Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasFocus ? Colors.white : Colors.white38,
                      width: hasFocus ? 2.5 : 1.2,
                    ),
                    boxShadow: hasFocus
                        ? [
                            BoxShadow(
                              color: kAccentColor.withValues(alpha: 0.45),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'VER AHORA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
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
    );
  }
}

class _SeasonsAndEpisodesPanel extends StatelessWidget {
  final List<DetalleTemporada> seasons;
  final int selectedSeasonIndex;
  final List<DetalleCapitulo> episodes;
  final List<FocusNode> seasonFocusNodes;
  final List<FocusNode> episodeFocusNodes;
  final ScrollController episodeScrollController;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<DetalleCapitulo> onEpisodeTap;
  final VoidCallback onRequestLeft;
  final int currentSeasonNumber;

  const _SeasonsAndEpisodesPanel({
    required this.seasons,
    required this.selectedSeasonIndex,
    required this.episodes,
    required this.seasonFocusNodes,
    required this.episodeFocusNodes,
    required this.episodeScrollController,
    required this.onSeasonSelected,
    required this.onEpisodeTap,
    required this.onRequestLeft,
    required this.currentSeasonNumber,
  });

  static const double _itemExtent = _kEpisodeItemExtent;

  void _scrollToIndex(int index) {
    if (!episodeScrollController.hasClients) return;
    final max = episodeScrollController.position.maxScrollExtent;
    final target = (index * _itemExtent) - 12;
    final clamped = target.clamp(0.0, max);
    episodeScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.8);
    const stillW = 120.0;
    const stillH = 76.0;
    final stillMemW = (stillW * dpr).round();
    final stillMemH = (stillH * dpr).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (seasons.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(seasons.length, (i) {
                final season = seasons[i];
                final name = season.nombre.isNotEmpty
                    ? season.nombre
                    : 'Temporada ${season.numero}';
                final isSelected = i == selectedSeasonIndex;

                return Padding(
                  padding: EdgeInsets.only(
                    right: i < seasons.length - 1 ? 10 : 0,
                  ),
                  child: Focus(
                    focusNode: seasonFocusNodes.length > i
                        ? seasonFocusNodes[i]
                        : null,
                    onFocusChange: (hasFocus) {
                      if (hasFocus) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final ctx = seasonFocusNodes.length > i
                              ? seasonFocusNodes[i].context
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

                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        if (i > 0) {
                          seasonFocusNodes[i - 1].requestFocus();
                        } else {
                          onRequestLeft();
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        if (i < seasonFocusNodes.length - 1) {
                          seasonFocusNodes[i + 1].requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (episodeFocusNodes.isNotEmpty) {
                          episodeFocusNodes[0].requestFocus();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollToIndex(0);
                          });
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        onSeasonSelected(i);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final hasFocus = Focus.of(context).hasFocus;
                        return GestureDetector(
                          onTap: () => onSeasonSelected(i),
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
                                color:
                                    isSelected ? Colors.black : Colors.white,
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
        Expanded(
          child: episodes.isEmpty
              ? const Center(
                  child: Text(
                    'No hay capítulos disponibles',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  controller: episodeScrollController,
                  itemCount: episodes.length,
                  padding: EdgeInsets.zero,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final ep = episodes[index];
                    final epNumber = ep.numero;
                    final epName = ep.titulo.isNotEmpty
                        ? ep.titulo
                        : 'Capítulo $epNumber';
                    final still = ep.imagen ?? '';
                    final epAirDate = ep.airDate ?? '';

                    return Focus(
                      focusNode: episodeFocusNodes.length > index
                          ? episodeFocusNodes[index]
                          : null,
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          if (index > 0) {
                            episodeFocusNodes[index - 1].requestFocus();
                            _scrollToIndex(index - 1);
                          } else if (seasonFocusNodes.isNotEmpty) {
                            seasonFocusNodes[selectedSeasonIndex.clamp(
                              0,
                              seasonFocusNodes.length - 1,
                            )].requestFocus();
                          }
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (index < episodeFocusNodes.length - 1) {
                            episodeFocusNodes[index + 1].requestFocus();
                            _scrollToIndex(index + 1);
                          }
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          onRequestLeft();
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          onEpisodeTap(ep);
                          return KeyEventResult.handled;
                        }

                        return KeyEventResult.ignored;
                      },
                      onFocusChange: (hasFocus) {
                        if (hasFocus) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollToIndex(index);
                          });
                        }
                      },
                      child: Builder(
                        builder: (context) {
                          final hasFocus = Focus.of(context).hasFocus;
                          return GestureDetector(
                            onTap: () => onEpisodeTap(ep),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141414)
                                    .withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: hasFocus
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: hasFocus ? 2 : 1.4,
                                ),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: SizedBox(
                                      width: stillW,
                                      height: stillH,
                                      child: still.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: still,
                                              fit: BoxFit.cover,
                                              memCacheWidth: stillMemW,
                                              memCacheHeight: stillMemH,
                                              fadeInDuration: const Duration(
                                                milliseconds: 100,
                                              ),
                                              placeholder: (_, _) =>
                                                  Container(
                                                color: Colors.grey[900],
                                              ),
                                              errorWidget: (_, _, _) =>
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
                                              child: Center(
                                                child: Text(
                                                  'E$epNumber',
                                                  style: const TextStyle(
                                                    color: kAccentColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '$epNumber. $epName',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            height: 1.25,
                                          ),
                                        ),
                                        if (epAirDate.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            epAirDate,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.55),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
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
      ],
    );
  }
}

class _TvElevatedButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  const _TvElevatedButton({
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  State<_TvElevatedButton> createState() => _TvElevatedButtonState();
}

class _TvElevatedButtonState extends State<_TvElevatedButton> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: kAccentColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}