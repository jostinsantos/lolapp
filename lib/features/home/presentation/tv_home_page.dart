// home.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../content/presentation/tv_content_page.dart';
import '../../../data/datasources/remote/tmdb/tmdb_home_api.dart';
const kAccentColor = Color(0xFFE50914);
const kBgColor = Colors.black;

class HomePage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const HomePage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  final TmdbHomeService _tmdb = TmdbHomeService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  List<_SectionData> _sections = [];

  final List<FocusNode> _sectionFocusNodes = [];
  bool _reportedMainNode = false;

  final ValueNotifier<Map<String, dynamic>?> _focusedItemNotifier =
      ValueNotifier(null);
  final ValueNotifier<String> _heroBackdropNotifier = ValueNotifier('');
  Timer? _focusDebounce;
  int _backdropRequestId = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Siempre landscape (horizontal)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _fetchHome();
  }

  @override
  void dispose() {
    _focusDebounce?.cancel();
    _focusedItemNotifier.dispose();
    _heroBackdropNotifier.dispose();
    for (final node in _sectionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes(int count) {
    while (_sectionFocusNodes.length < count) {
      _sectionFocusNodes.add(
        FocusNode(debugLabel: 'home_section_${_sectionFocusNodes.length}'),
      );
    }
    while (_sectionFocusNodes.length > count) {
      _sectionFocusNodes.removeLast().dispose();
    }
  }

  List<_SectionData> _buildSections(Map<String, dynamic> data) {
    final sections = <_SectionData>[];

    void addSection(String key, {bool horizontalCards = false}) {
      final section = data[key];
      if (section != null && section['items'] != null) {
        final items = List<Map<String, dynamic>>.from(section['items']);
        if (items.isEmpty) return;
        sections.add(
          _SectionData(
            title: section['title'] ?? key,
            items: items,
            horizontalCards: horizontalCards,
          ),
        );
      }
    }

    addSection('continue_watching');
    addSection('recent_movies');
    addSection('recent_tv');
    addSection('top_movies');
    addSection('top_tv');
    addSection('popular_movies');
    addSection('popular_tv');
    addSection('year_movies');
    addSection('year_tv');
    addSection('trending_movies');
    addSection('trending_tv');
    addSection('recent_episodes', horizontalCards: true);

    final genreSliders = data['movie_genre_sliders'];
    if (genreSliders is List) {
      for (final genre in genreSliders) {
        final items = List<Map<String, dynamic>>.from(genre['items'] ?? []);
        if (items.isEmpty) continue;
        sections.add(
          _SectionData(
            title: genre['name'] ?? 'Género',
            items: items,
          ),
        );
      }
    }

    return sections;
  }

  Map<String, dynamic>? _pickInitialFocusedItem(Map<String, dynamic> data) {
    const candidates = [
      'continue_watching',
      'recent_movies',
      'recent_tv',
      'top_movies',
      'top_tv',
      'popular_movies',
      'popular_tv',
      'year_movies',
      'year_tv',
      'trending_movies',
      'trending_tv',
      'recent_episodes',
    ];
    for (final key in candidates) {
      final section = data[key];
      if (section != null &&
          section['items'] is List &&
          (section['items'] as List).isNotEmpty) {
        return Map<String, dynamic>.from(section['items'][0]);
      }
    }
    final genreSliders = data['movie_genre_sliders'];
    if (genreSliders is List) {
      for (final genre in genreSliders) {
        if (genre['items'] is List && (genre['items'] as List).isNotEmpty) {
          return Map<String, dynamic>.from(genre['items'][0]);
        }
      }
    }
    return null;
  }

  Future<void> _fetchHome() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final json = await _tmdb.fetchHome();
      if (json['success'] == true) {
        final data = Map<String, dynamic>.from(json['data'] as Map);
        final allSections = _buildSections(data);
        final initialItem = _pickInitialFocusedItem(data);

        // Primero solo 3 sliders para que el inicio no demore
        final firstBatch = allSections.take(3).toList();
        _syncFocusNodes(1 + allSections.length);

        setState(() {
          _data = data;
          _sections = firstBatch;
          _loading = false;
        });

        _focusedItemNotifier.value = initialItem;
        if (initialItem != null) {
          _refreshHeroBackdrop(initialItem);
        }

        // Resto de sliders en el siguiente frame
        if (allSections.length > 3) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _sections = allSections);
          });
        }
      } else {
        setState(() {
          _error = 'Error en la respuesta de TMDB';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Sin conexión o error de red';
        _loading = false;
      });
    }
  }

  Future<void> _refreshHeroBackdrop(Map<String, dynamic> item) async {
    final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
    if (id <= 0) {
      _heroBackdropNotifier.value = _fallbackBackdrop(item);
      return;
    }

    final requestId = ++_backdropRequestId;
    final isMovie = (item['media_type']?.toString() ?? 'movie') == 'movie';
    final fallbackPath = item['backdrop_path']?.toString();

    _heroBackdropNotifier.value = _fallbackBackdrop(item);

    try {
      final url = await _tmdb.pickRandomBackdropWithoutLanguage(
        tmdbId: id,
        isMovie: isMovie,
        fallbackPath: fallbackPath,
      );
      if (requestId != _backdropRequestId) return;
      if (url.isNotEmpty) {
        _heroBackdropNotifier.value = url;
      }
    } catch (_) {}
  }

  String _fallbackBackdrop(Map? item) {
    if (item == null) return '';
    final backdrop = item['backdrop_path']?.toString() ?? '';
    if (backdrop.startsWith('http') && !backdrop.contains('[')) return backdrop;
    final poster = item['poster_path']?.toString() ?? '';
    if (poster.startsWith('http') && !poster.contains('[')) return poster;
    return '';
  }

  void _onItemFocused(Map<String, dynamic> item) {
    if (_focusedItemNotifier.value?['idcontenido'] == item['idcontenido'] &&
        _focusedItemNotifier.value?['media_type'] == item['media_type']) {
      _refreshHeroBackdrop(item);
      return;
    }
    _focusDebounce?.cancel();
    _focusDebounce = Timer(const Duration(milliseconds: 90), () {
      _focusedItemNotifier.value = item;
      _refreshHeroBackdrop(item);
    });
  }

  void _openContent(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;
    final tipo = item['media_type']?.toString() ?? 'movie';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PageContenido(
          idcontenido: id,
          tmdbId: id,
          mediaType: tipo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // obligatorio con AutomaticKeepAliveClientMixin

    if (_loading) {
      return const Scaffold(
        backgroundColor: kBgColor,
        body: _HomeSkeleton(),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: kBgColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _fetchHome,
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

    final sections = _sections;

    if (!_reportedMainNode) {
      _reportedMainNode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sectionFocusNodes.isNotEmpty) {
          widget.onMainFocusNodeCreated?.call(_sectionFocusNodes[0]);
        }
      });
    }

    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.6);
    final heroHeight = size.height * 0.52;
    final bgMemW = math.min(size.width * dpr, 1280).round();
    final bgMemH = math.min(size.height * dpr, 720).round();

    return Scaffold(
      backgroundColor: kBgColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<String>(
              valueListenable: _heroBackdropNotifier,
              builder: (context, backdropUrl, _) {
                if (backdropUrl.isEmpty) {
                  return const ColoredBox(color: Color(0xFF0a0a0a));
                }
                return CachedNetworkImage(
                  imageUrl: backdropUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  memCacheWidth: bgMemW,
                  memCacheHeight: bgMemH,
                  fadeInDuration: const Duration(milliseconds: 280),
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF0a0a0a)),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF0a0a0a)),
                );
              },
            ),
          ),
          const _HomeOverlayGradient(),
          Column(
            children: [
              SizedBox(
                height: heroHeight,
                width: double.infinity,
                child: RepaintBoundary(
                  child: ValueListenableBuilder<Map<String, dynamic>?>(
                    valueListenable: _focusedItemNotifier,
                    builder: (context, item, _) => _HeroSection(
                      item: item,
                      focusNode: _sectionFocusNodes[0],
                      onRequestMenuFocus: widget.onRequestMenuFocus,
                      onRequestNextFocus: sections.isNotEmpty
                          ? () => _sectionFocusNodes[1].requestFocus()
                          : null,
                      onTap: _openContent,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  cacheExtent: 300,
                  slivers: [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          if (i + 1 >= _sectionFocusNodes.length) {
                            return const SizedBox.shrink();
                          }
                          final section = sections[i];
                          final node = _sectionFocusNodes[i + 1];
                          final upNode = _sectionFocusNodes[i];
                          final hasDown =
                              (i + 2) < _sectionFocusNodes.length &&
                                  (i + 1) < sections.length;
                          final downNode = hasDown &&
                                  (i + 2) < _sectionFocusNodes.length
                              ? _sectionFocusNodes[i + 2]
                              : null;

                          return RepaintBoundary(
                            child: _HorizontalSlider(
                              title: section.title,
                              items: section.items,
                              onTap: _openContent,
                              focusNode: node,
                              onRequestFocusUp: () => upNode.requestFocus(),
                              onRequestFocusDown: downNode != null &&
                                      (i + 1) < sections.length
                                  ? () => downNode.requestFocus()
                                  : null,
                              onRequestMenuFocus: widget.onRequestMenuFocus,
                              onItemFocused: _onItemFocused,
                              horizontalCards: section.horizontalCards,
                            ),
                          );
                        },
                        childCount: sections.length,
                        addRepaintBoundaries: false,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 48)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Skeleton de carga ───────────────────────────────────────────────────────
class _HomeSkeleton extends StatefulWidget {
  const _HomeSkeleton();

  @override
  State<_HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<_HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.18, end: 0.38).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final heroHeight = size.height * 0.52;

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) {
        final bone = Color.fromRGBO(255, 255, 255, _opacity.value);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: heroHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF0a0a0a)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xE0000000),
                          Color(0x80000000),
                          Color(0x40000000),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 36,
                    bottom: 28,
                    right: size.width * 0.36,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: size.width * 0.28,
                          height: 36,
                          decoration: BoxDecoration(
                            color: bone,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: size.width * 0.32,
                          height: 12,
                          decoration: BoxDecoration(
                            color: bone,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: size.width * 0.40,
                          height: 10,
                          decoration: BoxDecoration(
                            color: bone,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: size.width * 0.34,
                          height: 10,
                          decoration: BoxDecoration(
                            color: bone,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                itemCount: 3,
                itemBuilder: (_, row) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
                          child: Container(
                            width: 140 + (row * 18).toDouble(),
                            height: 16,
                            decoration: BoxDecoration(
                              color: bone,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 124,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 22),
                            itemCount: 6,
                            itemBuilder: (_, i) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Container(
                                  width: 210,
                                  height: 118,
                                  decoration: BoxDecoration(
                                    color: bone,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HomeOverlayGradient extends StatelessWidget {
  const _HomeOverlayGradient();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xF0000000),
                Color(0xC4000000),
                Color(0x9C000000),
                Color(0x7A000000),
                Color(0x7A000000),
              ],
              stops: [0.0, 0.28, 0.50, 0.78, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Color(0x59000000),
                Color(0xD1000000),
              ],
              stops: [0.35, 0.58, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionData {
  final String title;
  final List<Map<String, dynamic>> items;
  final bool horizontalCards;

  _SectionData({
    required this.title,
    required this.items,
    this.horizontalCards = false,
  });
}

class _HeroSection extends StatelessWidget {
  final Map<String, dynamic>? item;
  final FocusNode focusNode;
  final VoidCallback? onRequestMenuFocus;
  final VoidCallback? onRequestNextFocus;
  final void Function(Map<String, dynamic> item) onTap;

  const _HeroSection({
    required this.item,
    required this.focusNode,
    this.onRequestMenuFocus,
    this.onRequestNextFocus,
    required this.onTap,
  });

  String _logo(Map? item) {
    if (item == null) return '';
    final logo = item['logo_path']?.toString() ?? '';
    if (logo.startsWith('http') && !logo.contains('[')) return logo;
    return '';
  }

  String _title(Map? item) =>
      item?['title']?.toString() ?? item?['series_title']?.toString() ?? '';

  String _genres(Map? item) {
    final g = item?['genres']?.toString() ??
        item?['genre']?.toString() ??
        item?['genres_text']?.toString() ??
        '';
    if (g.isNotEmpty) return g;
    return '';
  }

  String _year(Map? item) {
    final rd = item?['release_date']?.toString() ??
        item?['first_air_date']?.toString() ??
        '';
    if (rd.length >= 4) return rd.substring(0, 4);
    return item?['year']?.toString() ?? '';
  }

  String _runtime(Map? item) {
    final r = item?['runtime'];
    if (r == null) return '';
    final mins = r is int ? r : int.tryParse(r.toString()) ?? 0;
    if (mins <= 0) return '';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  String _overview(Map? item) {
    return item?['overview']?.toString() ?? '';
  }

  double? _tmdbRating(Map? item) {
    final v = item?['vote_average'];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  double? _imdbRating(Map? item) {
    final imdb = item?['imdb'];
    if (imdb is Map) {
      final r = imdb['rating'];
      if (r is num && r > 0) return r.toDouble();
      return double.tryParse(r?.toString() ?? '');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoUrl = _logo(item);
    final title = _title(item);
    final genres = _genres(item);
    final year = _year(item);
    final runtime = _runtime(item);
    final overview = _overview(item);
    final tmdb = _tmdbRating(item);
    final imdb = _imdbRating(item);
    final id = item?['tmdb_id'] as int? ?? item?['idcontenido'] as int? ?? 0;

    final topSafe = MediaQuery.paddingOf(context).top + 72;

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onRequestMenuFocus?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onRequestNextFocus?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (item != null && id > 0) {
            onTap(Map<String, dynamic>.from(item!));
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (_) {},
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: (item != null && id > 0)
                ? () => onTap(Map<String, dynamic>.from(item!))
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasFocus)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 36,
                  top: topSafe,
                  right: size.width * 0.36,
                  bottom: 14,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.bottomLeft,
                        clipBehavior: Clip.hardEdge,
                        children: <Widget>[
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    child: SizedBox(
                      key: ValueKey('${id}_${item?['media_type']}'),
                      width: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (logoUrl.isNotEmpty)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: size.width * 0.42,
                                maxHeight: 52,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: logoUrl,
                                fit: BoxFit.contain,
                                alignment: Alignment.centerLeft,
                                memCacheHeight: 104,
                                fadeInDuration:
                                    const Duration(milliseconds: 160),
                                placeholder: (_, __) => const SizedBox(
                                  height: 32,
                                  width: 140,
                                ),
                                errorWidget: (_, __, ___) => Text(
                                  title.toUpperCase(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    height: 1.08,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                            )
                          else
                            Text(
                              title.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                                letterSpacing: -0.4,
                              ),
                            ),
                          const SizedBox(height: 6),
                          if (year.isNotEmpty ||
                              genres.isNotEmpty ||
                              runtime.isNotEmpty ||
                              (imdb != null && imdb > 0) ||
                              (tmdb != null && tmdb > 0))
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    [
                                      if (year.isNotEmpty) year,
                                      if (genres.isNotEmpty) genres,
                                      if (runtime.isNotEmpty) runtime,
                                    ].join('  ·  '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.88),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if ((imdb != null && imdb > 0) ||
                                    (tmdb != null && tmdb > 0)) ...[
                                  const SizedBox(width: 10),
                                  if (imdb != null && imdb > 0) ...[
                                    _RatingBadge(
                                      label: 'IMDb',
                                      value: imdb.toStringAsFixed(1),
                                      color: const Color(0xFFF5C518),
                                    ),
                                    if (tmdb != null && tmdb > 0)
                                      const SizedBox(width: 6),
                                  ],
                                  if (tmdb != null && tmdb > 0)
                                    _RatingBadge(
                                      label: 'TMDB',
                                      value: tmdb.toStringAsFixed(1),
                                      color: const Color(0xFF01B4E4),
                                    ),
                                ],
                              ],
                            ),
                          if (overview.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              overview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 12,
                                height: 1.28,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _RatingBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalSlider extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onTap;
  final FocusNode focusNode;
  final VoidCallback? onRequestFocusUp;
  final VoidCallback? onRequestFocusDown;
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<Map<String, dynamic>> onItemFocused;
  final bool horizontalCards;

  const _HorizontalSlider({
    required this.title,
    required this.items,
    required this.onTap,
    required this.focusNode,
    required this.onItemFocused,
    this.onRequestFocusUp,
    this.onRequestFocusDown,
    this.onRequestMenuFocus,
    this.horizontalCards = false,
  });

  @override
  State<_HorizontalSlider> createState() => _HorizontalSliderState();
}

class _HorizontalSliderState extends State<_HorizontalSlider> {
  static const double _backdropW = 210;
  static const double _backdropH = 118;
  static const double _episodeW = 210;
  static const double _episodeH = 118;
  static const int _maxVisible = 7;

  int _focusedIndex = 0;

  void _cycle(int delta) {
    if (widget.items.isEmpty) return;
    final len = widget.items.length;
    final next = _focusedIndex + delta;
    if (next < 0 || next >= len) return;
    setState(() => _focusedIndex = next);
    widget.onItemFocused(widget.items[_focusedIndex]);
  }

  @override
  void didUpdateWidget(covariant _HorizontalSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _focusedIndex = 0;
    }
  }

  String _imageUrl(Map item) {
    final backdrop = item['backdrop_path']?.toString() ?? '';
    if (backdrop.isNotEmpty &&
        backdrop.startsWith('http') &&
        !backdrop.contains('[')) {
      return backdrop;
    }
    final poster = item['poster_path']?.toString() ?? '';
    if (poster.isNotEmpty &&
        poster.startsWith('http') &&
        !poster.contains('[')) {
      return poster;
    }
    return '';
  }

  String _logoUrl(Map item) {
    final logo = item['logo_path']?.toString() ?? '';
    if (logo.isNotEmpty &&
        logo.startsWith('http') &&
        !logo.contains('[')) {
      return logo;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.8);
    final cardW = widget.horizontalCards ? _episodeW : _backdropW;
    final cardH = widget.horizontalCards ? _episodeH : _backdropH;
    final memW = (cardW * dpr).round();
    final memH = (cardH * dpr).round();

    final visibleCount =
        widget.items.length < _maxVisible ? widget.items.length : _maxVisible;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _cycle(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (_focusedIndex <= 0) {
            widget.onRequestMenuFocus?.call();
            return KeyEventResult.handled;
          }
          _cycle(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onRequestFocusUp?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onRequestFocusDown?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap(widget.items[_focusedIndex]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        setState(() {});
        if (hasFocus) {
          widget.onItemFocused(widget.items[_focusedIndex]);
          Scrollable.ensureVisible(
            context,
            alignment: 0.25,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'ver más +',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: cardH + 6,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    itemCount: visibleCount,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, slot) {
                      final itemIndex = _focusedIndex + slot;
                      if (itemIndex >= widget.items.length) {
                        return const SizedBox.shrink();
                      }
                      final item = widget.items[itemIndex];
                      final isFocusedSlot = slot == 0 && hasFocus;

                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _PosterCard(
                          posterUrl: _imageUrl(item),
                          logoUrl: _logoUrl(item),
                          isFocused: isFocusedSlot,
                          width: cardW,
                          height: cardH,
                          memW: memW,
                          memH: memH,
                          onTap: () => widget.onTap(item),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final String posterUrl;
  final String logoUrl;
  final bool isFocused;
  final double width;
  final double height;
  final int memW;
  final int memH;
  final VoidCallback onTap;

  const _PosterCard({
    required this.posterUrl,
    this.logoUrl = '',
    required this.isFocused,
    required this.width,
    required this.height,
    required this.memW,
    required this.memH,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const radius = 12.0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: isFocused ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: posterUrl,
                fit: BoxFit.cover,
                width: width,
                height: height,
                memCacheWidth: memW,
                memCacheHeight: memH,
                fadeInDuration: const Duration(milliseconds: 90),
                placeholder: (_, __) =>
                    Container(color: const Color(0xFF1a1a1a)),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF1a1a1a),
                  child:
                      const Icon(Icons.movie, color: Colors.white24, size: 28),
                ),
              ),
              if (logoUrl.isNotEmpty)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x99000000),
                        ],
                      ),
                    ),
                  ),
                ),
              if (logoUrl.isNotEmpty)
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: width * 0.28,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: height * 0.32,
                        maxWidth: width * 0.62,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: logoUrl,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomLeft,
                        memCacheHeight: 64,
                        fadeInDuration: const Duration(milliseconds: 100),
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}