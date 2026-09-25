import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../content/presentation/content_page.dart';
import '../../player/presentation/player_page.dart';
// Ajusta la ruta según tu estructura
import '../../../data/datasources/remote/tmdb/tmdb_home_mobile_api.dart';
import '../../content/presentation/content_options_modal.dart'; // ← modal de opciones

const kAccentColor = Colors.purpleAccent;
const kBgColor = Colors.black;
const kCardBg = Color(0xFF1a1a2e);
const kSectionTitleStyle = TextStyle(
  fontFamily: 'sans-serif',
  color: Colors.white,
  fontSize: 18,
  fontWeight: FontWeight.bold,
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  final TmdbHomeMobileService _tmdb = TmdbHomeMobileService();

  static Map<String, dynamic>? _cachedData;
  static List<Map<String, dynamic>> _cachedHistorial = [];
  static bool _hasLoadedOnce = false;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  final PageController _mainSliderController = PageController();
  int _mainSliderIndex = 0;

  List<Map<String, dynamic>> _historial = [];

  int _recentTab = 0;
  int _topTab = 0;
  int _popularTab = 0;
  int _genreTab = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    if (_hasLoadedOnce && _cachedData != null) {
      _data = _cachedData;
      _historial = List<Map<String, dynamic>>.from(_cachedHistorial);
      _loading = false;
      _refreshHistorialQuiet();
    } else {
      _fetchAll();
    }
  }

  @override
  void dispose() {
    _mainSliderController.dispose();
    super.dispose();
  }

  Future<void> _refreshHistorialQuiet() async {
    final historial = await _loadHistorial();
    if (!mounted) return;
    _cachedHistorial = historial;
    setState(() => _historial = historial);
  }

  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final apiFuture = _fetchHomeApi();
      final histFuture = _loadHistorial();

      final apiData = await apiFuture;
      final historial = await histFuture;

      if (!mounted) return;

      if (apiData == null) {
        setState(() {
          _error = 'Error en la respuesta de TMDB';
          _loading = false;
        });
        return;
      }

      _cachedData = apiData;
      _cachedHistorial = historial;
      _hasLoadedOnce = true;

      setState(() {
        _data = apiData;
        _historial = historial;
        _loading = false;
        _genreTab = 0;
      });
    } catch (e, st) {
      debugPrint('HomePage _fetchAll error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexión o error de red';
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchHomeApi() async {
    final json = await _tmdb.fetchHome();
    if (json['success'] != true) return null;
    final data = json['data'];
    if (data is! Map) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> _loadHistorial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith('cachePlayer_'))
          .toList();

      final List<Map<String, dynamic>> result = [];
      for (final key in keys) {
        try {
          final raw = prefs.getString(key);
          if (raw == null) continue;
          final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          final segundo = data['segundo'] as int? ?? 0;
          if (segundo < 8) continue;
          result.add(data);
        } catch (_) {}
      }

      result.sort((a, b) {
        final ta = a['timestamp']?.toString() ?? '';
        final tb = b['timestamp']?.toString() ?? '';
        return tb.compareTo(ta);
      });
      return result;
    } catch (_) {
      return [];
    }
  }

  void _openContent(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;
    final tipo =
        item['media_type']?.toString() ?? item['type']?.toString() ?? 'movie';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PageContenido(idcontenido: id, tmdbId: id, mediaType: tipo),
      ),
    ).then((_) {
      _refreshHistorialQuiet();
    });
  }

  // ── Continuar viendo → PLAYER directo ───────────────────────────────────
  void _openHistorial(Map<String, dynamic> item) {
    final id = item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;

    final temporada = item['temporada'] as int?;
    final capitulo = item['capitulo'] as int?;
    final tipo = (item['tipo'] ?? 'movie').toString().toLowerCase();
    final titulo = item['titulo']?.toString() ?? '';
    final videoUrl = item['videoUrl']?.toString() ?? '';
    final idioma = item['idioma']?.toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoUrl: videoUrl,
          idcontenido: id,
          tmdbId: id,
          temporada: temporada,
          capitulo: capitulo,
          tipo: tipo,
          titulo: titulo,
          idioma: idioma,
        ),
      ),
    ).then((_) {
      _refreshHistorialQuiet();
    });
  }

  // ── Long press → modal de opciones ──────────────────────────────────────
  void _showOpcionesModal(Map<String, dynamic> item) {
    final id =
        item['tmdb_id'] as int? ??
        item['idcontenido'] as int? ??
        item['idtmdb'] as int? ??
        0;
    if (id <= 0) return;

    final tipo = (item['media_type'] ?? item['type'] ?? item['tipo'] ?? 'movie')
        .toString()
        .toLowerCase();

    final titulo =
        item['title']?.toString() ??
        item['titulo']?.toString() ??
        item['name']?.toString() ??
        'Sin título';

    String poster =
        item['poster_path']?.toString() ?? item['poster']?.toString() ?? '';
    if (poster.isNotEmpty && !poster.startsWith('http')) {
      poster = 'https://image.tmdb.org/t/p/w500$poster';
    }

    String backdrop =
        item['backdrop_path']?.toString() ?? item['backdrop']?.toString() ?? '';
    if (backdrop.isNotEmpty && !backdrop.startsWith('http')) {
      backdrop = 'https://image.tmdb.org/t/p/w780$backdrop';
    }

    showContenidoOpcionesModal(
      context,
      tmdbId: id,
      idcontenido: id,
      tipo: tipo,
      titulo: titulo,
      posterUrl: poster.isNotEmpty ? poster : null,
      backdropUrl: backdrop.isNotEmpty ? backdrop : null,
    ).then((_) {
      if (mounted) _refreshHistorialQuiet();
    });
  }

  List<Map<String, dynamic>> _itemsOf(String key) {
    final section = _data?[key];
    if (section is! Map) return const [];
    final items = section['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _titleOf(String key, String fallback) {
    final section = _data?[key];
    if (section is Map && section['title'] != null) {
      return section['title'].toString();
    }
    return fallback;
  }

  List<Map<String, dynamic>> get _genreSliders {
    final raw = _data?['movie_genre_sliders'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> get _mainSlider {
    final raw = _data?['main_slider'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: kBgColor,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 350,
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(color: kAccentColor),
                  ),
                ),
                const SizedBox(height: 12),
                _skeletonTitle(),
                _skeletonHorizontalList(),
                const SizedBox(height: 12),
                _skeletonTitle(),
                _skeletonHorizontalList(),
              ],
            ),
          ),
        ),
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
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchAll,
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

    final slider = _mainSlider;
    final size = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final heroHeight = size.height * 0.58 + topPad;

    return Scaffold(
      backgroundColor: kBgColor,
      body: RefreshIndicator(
        color: kAccentColor,
        backgroundColor: kCardBg,
        onRefresh: _fetchAll,
        child: CustomScrollView(
          cacheExtent: 250,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            if (slider.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: heroHeight,
                  child: Stack(
                    children: [
                      PageView.builder(
                        controller: _mainSliderController,
                        itemCount: slider.length,
                        onPageChanged: (i) {
                          if (mounted) setState(() => _mainSliderIndex = i);
                        },
                        itemBuilder: (context, index) {
                          final item = slider[index];
                          return _HeroSlide(
                            item: item,
                            topPad: topPad,
                            onTap: () => _openContent(item),
                            onLongPress: () => _showOpcionesModal(item),
                          );
                        },
                      ),
                      if (slider.length > 1)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 12,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(slider.length, (i) {
                              final active = i == _mainSliderIndex;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                width: active ? 20 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: active
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_historial.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Continuar Viendo',
                  trailing: 'Ver Todo',
                  trailingColor: kAccentColor,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _historial.length.clamp(0, 20),
                    cacheExtent: 200,
                    itemBuilder: (context, index) {
                      final item = _historial[index];
                      return _ContinueCard(
                        item: item,
                        onTap: () => _openHistorial(item), // ← player
                        onLongPress: () => _showOpcionesModal(item), // ← modal
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
            ],
            _tabbedSliver(
              title: 'Agregados Recientemente',
              selectedTab: _recentTab,
              onTabChanged: (i) => setState(() => _recentTab = i),
              items: _recentTab == 0
                  ? _itemsOf('recent_movies')
                  : _itemsOf('recent_tv'),
            ),
            if (_itemsOf('recent_episodes').isNotEmpty)
              SliverToBoxAdapter(
                child: _EpisodeSection(
                  title: _titleOf('recent_episodes', 'Capítulos Recientes'),
                  items: _itemsOf('recent_episodes'),
                  onTap: _openContent,
                  onLongPress: _showOpcionesModal,
                ),
              ),
            _tabbedSliver(
              title: 'Mejores Valoradas',
              selectedTab: _topTab,
              onTabChanged: (i) => setState(() => _topTab = i),
              items: _topTab == 0 ? _itemsOf('top_movies') : _itemsOf('top_tv'),
            ),
            _tabbedSliver(
              title: 'Populares',
              selectedTab: _popularTab,
              onTabChanged: (i) => setState(() => _popularTab = i),
              items: _popularTab == 0
                  ? _itemsOf('popular_movies')
                  : _itemsOf('popular_tv'),
            ),
            if (_genreSliders.isNotEmpty) ..._buildGenreSection(),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 72,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeletonTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        width: 150,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _skeletonHorizontalList() {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Container(
            width: 120,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  Widget _tabbedSliver({
    required String title,
    required int selectedTab,
    required ValueChanged<int> onTabChanged,
    required List<Map<String, dynamic>> items,
  }) {
    return SliverToBoxAdapter(
      child: _TabbedSection(
        title: title,
        selectedTab: selectedTab,
        onTabChanged: onTabChanged,
        tabs: const ['Películas', 'Series'],
        items: items,
        onTap: _openContent,
        onLongPress: _showOpcionesModal,
        showRating: true,
      ),
    );
  }

  List<Widget> _buildGenreSection() {
    final genres = _genreSliders;
    if (genres.isEmpty) return const [];

    final safeIndex = _genreTab.clamp(0, genres.length - 1);
    final selected = genres[safeIndex];
    final rawItems = selected['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];

    return [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text('Películas por Género', style: kSectionTitleStyle),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: genres.length,
            itemBuilder: (context, i) {
              final name = genres[i]['name']?.toString() ?? 'Género';
              final active = i == safeIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _genreTab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: active
                          ? const LinearGradient(
                              colors: [Colors.purpleAccent, Colors.deepPurple],
                            )
                          : null,
                      color: active
                          ? null
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active
                            ? Colors.transparent
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.normal,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            itemCount: items.length,
            cacheExtent: 200,
            itemBuilder: (context, index) {
              final item = items[index];
              return _PosterCard(
                item: item,
                showRating: true,
                onTap: () => _openContent(item),
                onLongPress: () => _showOpcionesModal(item),
              );
            },
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 4)),
    ];
  }
}

// ─── Hero ────────────────────────────────────────────────────────────────────

class _HeroSlide extends StatelessWidget {
  final Map<String, dynamic> item;
  final double topPad;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _HeroSlide({
    required this.item,
    required this.topPad,
    required this.onTap,
    this.onLongPress,
  });

  String get _backdrop {
    final b = item['backdrop_path']?.toString() ?? '';
    if (b.isNotEmpty && b != 'null') {
      return b.startsWith('http') ? b : 'https://image.tmdb.org/t/p/original$b';
    }
    final p = item['poster_path']?.toString() ?? '';
    if (p.isNotEmpty && p != 'null') {
      return p.startsWith('http') ? p : 'https://image.tmdb.org/t/p/w780$p';
    }
    return '';
  }

  String get _title => item['title']?.toString() ?? '';

  String get _genres {
    final g = item['genres'];
    if (g is String) return g.trim();
    if (g is List) {
      return g
          .map((e) {
            if (e is String) return e;
            if (e is Map) return e['name']?.toString() ?? '';
            return '';
          })
          .where((s) => s.isNotEmpty)
          .take(3)
          .join('  •  ');
    }
    return '';
  }

  String get _type {
    final t =
        item['media_type']?.toString() ?? item['type']?.toString() ?? 'movie';
    return t == 'tv' ? 'Serie' : 'Película';
  }

  String get _year {
    final rd =
        item['release_date']?.toString() ??
        item['first_air_date']?.toString() ??
        '';
    if (rd.length >= 4) return rd.substring(0, 4);
    return item['year']?.toString() ?? '';
  }

  String get _metaLine {
    final parts = <String>[];
    if (_genres.isNotEmpty) parts.add(_genres);
    parts.add(_type);
    if (_year.isNotEmpty) parts.add(_year);
    return parts.join('  •  ');
  }

  String? get _logo {
    final l = item['logo_path']?.toString();
    if (l == null || l.isEmpty || l == 'null') return null;
    return l.startsWith('http') ? l : 'https://image.tmdb.org/t/p/w500$l';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_backdrop.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              width: double.infinity,
              height: double.infinity,
              memCacheWidth: (size.width * dpr).round(),
              fadeInDuration: const Duration(milliseconds: 160),
              placeholder: (_, __) =>
                  const ColoredBox(color: Color(0xFF111111)),
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF111111)),
            )
          else
            const ColoredBox(color: Color(0xFF111111)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.15),
                  Colors.black.withOpacity(0.35),
                  Colors.black.withOpacity(0.75),
                  Colors.black,
                ],
                stops: const [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 36,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_logo != null)
                  CachedNetworkImage(
                    imageUrl: _logo!,
                    height: 70,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => _titleText(),
                  )
                else
                  _titleText(),
                const SizedBox(height: 12),
                if (_metaLine.isNotEmpty)
                  Text(
                    _metaLine,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                const SizedBox(height: 18),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: onTap,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      child: Text(
                        'Ver detalles',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
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
      _title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.5,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Color? trailingColor;

  const _SectionHeader({
    required this.title,
    this.trailing,
    this.trailingColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: kSectionTitleStyle)),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontFamily: 'sans-serif',
                color: trailingColor ?? Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ContinueCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
  });

  String get _image {
    final b = item['backdrop']?.toString() ?? '';
    if (b.isNotEmpty) return b;
    return item['poster']?.toString() ?? '';
  }

  String get _title => item['titulo']?.toString() ?? 'Sin título';
  String get _tipo => item['tipo']?.toString() ?? 'movie';
  int get _segundo => item['segundo'] as int? ?? 0;

  String get _meta {
    final temporada = item['temporada'];
    final capitulo = item['capitulo'];
    if (_tipo == 'tv' && temporada != null && capitulo != null) {
      return 'S${temporada.toString().padLeft(2, '0')}E${capitulo.toString().padLeft(2, '0')}';
    }
    return '';
  }

  double get _progress => (_segundo / 4200).clamp(0.04, 1.0);
  int get _porcentaje => (_progress * 100).round();

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: kCardBg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_image.isNotEmpty)
              CachedNetworkImage(
                imageUrl: _image,
                fit: BoxFit.cover,
                memCacheWidth: (260 * dpr).round(),
                memCacheHeight: (150 * dpr).round(),
                fadeInDuration: const Duration(milliseconds: 100),
                placeholder: (_, __) => const ColoredBox(color: kCardBg),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: kCardBg,
                  child: Icon(Icons.movie, color: Colors.white24, size: 32),
                ),
              )
            else
              const ColoredBox(
                color: kCardBg,
                child: Icon(Icons.movie, color: Colors.white24, size: 32),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _tipo == 'movie'
                              ? Colors.blueAccent.withValues(alpha: 0.8)
                              : Colors.purpleAccent.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _tipo == 'movie' ? 'Película' : 'Serie',
                          style: const TextStyle(
                            fontFamily: 'sans-serif',
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_meta.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _meta,
                            style: const TextStyle(
                              fontFamily: 'sans-serif',
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$_porcentaje%',
                          style: const TextStyle(
                            fontFamily: 'sans-serif',
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _title,
                    style: const TextStyle(
                      fontFamily: 'sans-serif',
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      color: Colors.green,
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabbedSection extends StatelessWidget {
  final String title;
  final int selectedTab;
  final ValueChanged<int> onTabChanged;
  final List<String> tabs;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onTap;
  final void Function(Map<String, dynamic> item)? onLongPress;
  final bool showRating;

  const _TabbedSection({
    required this.title,
    required this.selectedTab,
    required this.onTabChanged,
    required this.tabs,
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.showRating = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, style: kSectionTitleStyle)),
              Container(
                height: 30,
                decoration: BoxDecoration(
                  color: kCardBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(tabs.length, (i) {
                    final active = i == selectedTab;
                    return GestureDetector(
                      onTap: () => onTabChanged(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? kAccentColor.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: active
                              ? Border.all(
                                  color: kAccentColor.withValues(alpha: 0.3),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Text(
                          tabs[i],
                          style: TextStyle(
                            fontFamily: 'sans-serif',
                            color: active ? Colors.white : Colors.white54,
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 190,
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'Sin contenido',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  cacheExtent: 200,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _PosterCard(
                      item: item,
                      showRating: showRating,
                      onTap: () => onTap(item),
                      onLongPress: onLongPress != null
                          ? () => onLongPress!(item)
                          : null,
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool showRating;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PosterCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.showRating = false,
  });

  static const double _w = 120;
  static const double _h = 180;

  String get _poster => item['poster_path']?.toString() ?? '';
  double get _rating {
    final r = item['vote_average'];
    if (r is num) return r.toDouble();
    return double.tryParse('$r') ?? 0;
  }

  String get _year {
    final rd =
        item['release_date']?.toString() ??
        item['first_air_date']?.toString() ??
        '';
    if (rd.length >= 4) return rd.substring(0, 4);
    return item['year']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    final ratingText = _rating > 0 ? _rating.toStringAsFixed(1) : 'N/A';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: _w,
        margin: const EdgeInsets.only(right: 10),
        child: Stack(
          children: [
            Container(
              width: _w,
              height: _h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: kCardBg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _poster.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _poster,
                      fit: BoxFit.cover,
                      width: _w,
                      height: _h,
                      memCacheWidth: (_w * dpr).round(),
                      memCacheHeight: (_h * dpr).round(),
                      fadeInDuration: const Duration(milliseconds: 100),
                      placeholder: (_, __) => const ColoredBox(color: kCardBg),
                      errorWidget: (_, __, ___) => const ColoredBox(
                        color: kCardBg,
                        child: Icon(
                          Icons.movie,
                          color: Colors.white24,
                          size: 28,
                        ),
                      ),
                    )
                  : const ColoredBox(
                      color: kCardBg,
                      child: Icon(Icons.movie, color: Colors.white24, size: 28),
                    ),
            ),
            if (showRating)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: kAccentColor.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 11,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        ratingText,
                        style: const TextStyle(
                          fontFamily: 'sans-serif',
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_year.isNotEmpty)
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _year,
                    style: const TextStyle(
                      fontFamily: 'sans-serif',
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onTap;
  final void Function(Map<String, dynamic> item)? onLongPress;

  const _EpisodeSection({
    required this.title,
    required this.items,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: title,
          trailing: 'Ver Todo',
          trailingColor: kAccentColor,
        ),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            cacheExtent: 200,
            itemBuilder: (context, index) {
              final item = items[index];
              return _EpisodeCard(
                item: item,
                onTap: () => onTap(item),
                onLongPress: onLongPress != null
                    ? () => onLongPress!(item)
                    : null,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _EpisodeCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
  });

  String get _image {
    final b = item['backdrop_path']?.toString() ?? '';
    if (b.isNotEmpty) return b;
    return item['poster_path']?.toString() ?? '';
  }

  String get _seriesTitle =>
      item['series_title']?.toString() ?? item['title']?.toString() ?? '';

  String get _epLabel {
    final s = item['season_number'];
    final e = item['episode_number'];
    if (s != null && e != null) {
      return 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}';
    }
    return '';
  }

  String get _epTitle =>
      item['episode_title']?.toString() ?? item['name']?.toString() ?? '';

  double get _rating {
    final r = item['vote_average'];
    if (r is num) return r.toDouble();
    return double.tryParse('$r') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: kCardBg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_image.isNotEmpty)
              CachedNetworkImage(
                imageUrl: _image,
                fit: BoxFit.cover,
                memCacheWidth: (260 * dpr).round(),
                memCacheHeight: (150 * dpr).round(),
                fadeInDuration: const Duration(milliseconds: 100),
                placeholder: (_, __) => const ColoredBox(color: kCardBg),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: kCardBg,
                  child: Icon(Icons.tv, color: Colors.white24, size: 28),
                ),
              )
            else
              const ColoredBox(
                color: kCardBg,
                child: Icon(Icons.tv, color: Colors.white24, size: 28),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_epLabel.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kAccentColor.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _epLabel,
                        style: const TextStyle(
                          fontFamily: 'sans-serif',
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    _seriesTitle,
                    style: const TextStyle(
                      fontFamily: 'sans-serif',
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_epTitle.isNotEmpty)
                    Text(
                      _epTitle,
                      style: TextStyle(
                        fontFamily: 'sans-serif',
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (_rating > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontFamily: 'sans-serif',
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
