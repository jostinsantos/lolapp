import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../content/presentation/content_page.dart';
// Ajusta rutas si hace falta
import '../../../data/datasources/remote/tmdb/tmdb_search_api.dart';
import '../../../data/datasources/remote/tmdb/tmdb_discover_api.dart';
// Modal de opciones móvil
import '../../content/presentation/content_options_modal.dart';
const kAccentColor = Colors.purpleAccent;
const kBgColor = Colors.black;
const kCardBg = Color(0xFF1a1a2e);

String _posterUrl(dynamic raw) {
  final p = raw?.toString() ?? '';
  if (p.isEmpty || p == 'null') return '';
  if (p.startsWith('http')) {
    if (p.contains('image.tmdb.org')) {
      return p
          .replaceFirst(RegExp(r'/t/p/(original|w\d+)/'), '/t/p/w342/')
          .replaceFirst(RegExp(r'/original/'), '/w342/');
    }
    return p;
  }
  return 'https://image.tmdb.org/t/p/w342$p';
}

class BuscarPage extends StatefulWidget {
  const BuscarPage({super.key});

  @override
  State<BuscarPage> createState() => BuscarPageState();
}

class BuscarPageState extends State<BuscarPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _discoverScroll = ScrollController();

  final TmdbSearchService _searchService = TmdbSearchService();
  final TmdbDiscoverService _discoverService = TmdbDiscoverService();

  // ── Búsqueda ────────────────────────────────────────────────────────────
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Timer? _debounce;

  // ── Descubrir ───────────────────────────────────────────────────────────
  String _tipo = 'movie'; // movie | tv
  String _genero = 'Recientes';
  /// popularity | year | title | rating
  String _sortBy = 'popularity';
  bool _discoverLoading = true;
  bool _discoverLoadingMore = false;
  String? _discoverError;
  List<Map<String, dynamic>> _discoverItems = [];
  int _page = 1;
  bool _hasNext = false;
  bool _loadMoreQueued = false;

  static const _sortLabels = <String, String>{
    'popularity': 'Popularidad',
    'year': 'Año',
    'title': 'Título',
    'rating': 'Calificación',
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _discoverScroll.addListener(_onDiscoverScroll);
    _loadDiscover(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _inputFocus.dispose();
    _discoverScroll.dispose();
    super.dispose();
  }

  List<String> get _currentGenres => _tipo == 'tv'
      ? TmdbDiscoverService.tvGenreLabels()
      : TmdbDiscoverService.movieGenreLabels();

  String get _tipoLabel => _tipo == 'tv' ? 'Series' : 'Películas';
  String get _sortLabel => _sortLabels[_sortBy] ?? 'Popularidad';

  // ═══════════════════════════════════════════════════════════════════════
  // BÚSQUEDA (TMDB)
  // ═══════════════════════════════════════════════════════════════════════
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      if (!_searched && _items.isEmpty && !_loading) return;
      setState(() {
        _items = [];
        _searched = false;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _doSearch(value.trim());
    });
  }

  Future<void> _doSearch([String? forceQuery]) async {
    final q = (forceQuery ?? _controller.text).trim();
    if (q.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });

    try {
      final json = await _searchService.search(q, limit: 40);
      if (!mounted) return;

      if (json['success'] == true) {
        final raw = json['data']?['items'];
        final items = raw is List
            ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];
        setState(() {
          _items = items;
          _loading = false;
        });
      } else {
        setState(() {
          _error = json['message']?.toString() ?? 'No se pudo buscar';
          _items = [];
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexión o error de red';
        _items = [];
        _loading = false;
      });
    }
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _items = [];
      _searched = false;
      _error = null;
      _loading = false;
    });
  }

  void _openContent(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;
    final tipo =
        item['media_type']?.toString() ?? item['type']?.toString() ?? 'movie';
    FocusScope.of(context).unfocus();
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

  // ── LONG PRESS → abre modal de opciones ────────────────────────────────
  void _showOpcionesModal(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;

    final tipo =
        (item['media_type'] ?? item['type'] ?? 'movie').toString().toLowerCase();

    final titulo = item['title']?.toString() ??
        item['titulo']?.toString() ??
        item['name']?.toString() ??
        'Sin título';

    String poster = _posterUrl(item['poster_path']);
    String backdrop = item['backdrop_path']?.toString() ?? '';
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DESCUBRIR (TMDB)
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _loadDiscover({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasNext = false;
      _loadMoreQueued = false;
      if (mounted) {
        setState(() {
          _discoverLoading = true;
          _discoverError = null;
          _discoverItems = [];
        });
      }
    } else {
      if (_discoverLoadingMore || !_hasNext || _loadMoreQueued) return;
      _loadMoreQueued = true;
      if (mounted) setState(() => _discoverLoadingMore = true);
    }

    try {
      final json = await _discoverService.discover(
        mediaType: _tipo,
        genero: _genero,
        sortBy: _sortBy,
        page: _page,
      );

      if (json['success'] != true) {
        throw Exception(json['error']?.toString() ?? 'Error API');
      }

      final raw = json['data'];
      final List<Map<String, dynamic>> newItems = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];

      final hasNext = json['has_next'] == true;
      final currentPage = json['page'] as int? ?? _page;

      if (!mounted) return;
      setState(() {
        if (reset) {
          _discoverItems = newItems;
        } else {
          _discoverItems.addAll(newItems);
        }
        _hasNext = hasNext;
        _page = currentPage + 1;
        _discoverLoading = false;
        _discoverLoadingMore = false;
        _loadMoreQueued = false;
        _discoverError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _discoverError = 'Sin conexión o error de red';
        _discoverLoading = false;
        _discoverLoadingMore = false;
        _loadMoreQueued = false;
        if (reset) _discoverItems = [];
      });
    }
  }

  void _onDiscoverScroll() {
    if (!_discoverScroll.hasClients) return;
    if (_discoverLoadingMore || !_hasNext || _loadMoreQueued) return;
    final pos = _discoverScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadDiscover(reset: false);
    }
  }

  void _changeTipo(String tipo) {
    if (tipo == _tipo) return;
    final genres = tipo == 'tv'
        ? TmdbDiscoverService.tvGenreLabels()
        : TmdbDiscoverService.movieGenreLabels();
    final newGenero = genres.contains(_genero) ? _genero : 'Recientes';
    setState(() {
      _tipo = tipo;
      _genero = newGenero;
    });
    _loadDiscover(reset: true);
  }

  void _changeGenero(String genero) {
    if (genero == _genero) return;
    setState(() => _genero = genero);
    _loadDiscover(reset: true);
  }

  void _changeSort(String sort) {
    if (sort == _sortBy) return;
    setState(() => _sortBy = sort);
    _loadDiscover(reset: true);
  }

  // ── Bottom sheets ───────────────────────────────────────────────────────
  void _showTipoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Tipo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                _sheetOption(
                  label: 'Películas',
                  selected: _tipo == 'movie',
                  onTap: () {
                    Navigator.pop(ctx);
                    _changeTipo('movie');
                  },
                ),
                _sheetOption(
                  label: 'Series',
                  selected: _tipo == 'tv',
                  onTap: () {
                    Navigator.pop(ctx);
                    _changeTipo('tv');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showGeneroSheet() {
    final genres = _currentGenres;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          decoration: const BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Género',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: genres.length,
                    itemBuilder: (_, i) {
                      final g = genres[i];
                      return _sheetOption(
                        label: g,
                        selected: g == _genero,
                        onTap: () {
                          Navigator.pop(ctx);
                          _changeGenero(g);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Ordenar por',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                for (final e in _sortLabels.entries)
                  _sheetOption(
                    label: e.value,
                    selected: _sortBy == e.key,
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeSort(e.key);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? kAccentColor.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? kAccentColor.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: kAccentColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _inputFocus,
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) => _doSearch(),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  cursorColor: kAccentColor,
                  decoration: InputDecoration(
                    hintText: 'Buscar películas, series...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white54,
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white54,
                              size: 20,
                            ),
                            onPressed: _clear,
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _searched ? _buildSearchResults() : _buildDiscover(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final bottomPad = MediaQuery.paddingOf(context).bottom + 72;

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kAccentColor, strokeWidth: 2.5),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => _doSearch(),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Sin resultados para "${_controller.text.trim()}"',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text(
            '${_items.length} resultado${_items.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
            itemCount: _items.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            cacheExtent: 200,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              childAspectRatio: 120 / 180,
            ),
            itemBuilder: (context, index) {
              final item = _items[index];
              return _DiscoverPosterCard(
                item: item,
                onTap: () => _openContent(item),
                onLongPress: () => _showOpcionesModal(item), // ← long press
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiscover() {
    final bottomPad = MediaQuery.paddingOf(context).bottom + 72;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: _FilterChipButton(
                  label: _tipoLabel,
                  icon: Icons.movie_filter_rounded,
                  onTap: _showTipoSheet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterChipButton(
                  label: _genero,
                  icon: Icons.category_rounded,
                  onTap: _showGeneroSheet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterChipButton(
                  label: _sortLabel,
                  icon: Icons.sort_rounded,
                  onTap: _showSortSheet,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _genero == 'Recientes'
                ? 'Agregados recientemente · $_tipoLabel · $_sortLabel'
                : '$_genero · $_tipoLabel · $_sortLabel',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: _buildDiscoverBody(bottomPad)),
      ],
    );
  }

  Widget _buildDiscoverBody(double bottomPad) {
    if (_discoverLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kAccentColor, strokeWidth: 2.5),
      );
    }

    if (_discoverError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _discoverError!,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => _loadDiscover(reset: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_discoverItems.isEmpty) {
      return RefreshIndicator(
        color: kAccentColor,
        backgroundColor: kCardBg,
        onRefresh: () => _loadDiscover(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'Sin contenido',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kAccentColor,
      backgroundColor: kCardBg,
      onRefresh: () => _loadDiscover(reset: true),
      child: GridView.builder(
        controller: _discoverScroll,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
        itemCount: _discoverItems.length + (_discoverLoadingMore ? 1 : 0),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        cacheExtent: 280,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
          childAspectRatio: 120 / 180,
        ),
        itemBuilder: (context, index) {
          if (index >= _discoverItems.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: kAccentColor,
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          }

          final item = _discoverItems[index];
          return _DiscoverPosterCard(
            item: item,
            onTap: () => _openContent(item),
            onLongPress: () => _showOpcionesModal(item), // ← long press
          );
        },
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCardBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: kAccentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white54,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverPosterCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _DiscoverPosterCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
  });

  static const double _w = 120;
  static const double _h = 180;

  double get _rating {
    final r = item['vote_average'];
    if (r is num) return r.toDouble();
    return double.tryParse('$r') ?? 0;
  }

  String get _year {
    final rd = item['release_date']?.toString() ??
        item['first_air_date']?.toString() ??
        '';
    if (rd.length >= 4) return rd.substring(0, 4);
    return item['year']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    final ratingText = _rating > 0 ? _rating.toStringAsFixed(1) : 'N/A';
    final poster = _posterUrl(item['poster_path']);
    final memW = (_w * dpr).round();
    final memH = (_h * dpr).round();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: kCardBg,
            ),
            clipBehavior: Clip.antiAlias,
            child: poster.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: poster,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    memCacheWidth: memW,
                    memCacheHeight: memH,
                    maxWidthDiskCache: memW,
                    maxHeightDiskCache: memH,
                    fadeInDuration: const Duration(milliseconds: 80),
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, __) => const ColoredBox(color: kCardBg),
                    errorWidget: (_, __, ___) => const ColoredBox(
                      color: kCardBg,
                      child: Icon(Icons.movie, color: Colors.white24, size: 28),
                    ),
                  )
                : const ColoredBox(
                    color: kCardBg,
                    child: Icon(Icons.movie, color: Colors.white24, size: 28),
                  ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 11),
                  const SizedBox(width: 3),
                  Text(
                    ratingText,
                    style: const TextStyle(
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _year,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}