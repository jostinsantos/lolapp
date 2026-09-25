// lib/escrubir/escrubir.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/datasources/remote/tmdb/tmdb_discover_api.dart';
import '../../content/presentation/tv_content_page.dart';
import '../../content/presentation/tv_content_options_modal.dart';
const kAccentColor = Color(0xFFE50914);
const kBgColor = Colors.black;
const kCardBg = Color(0xFF1A1A1A);
const kFilterBg = Color(0xFF2A2A38);

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

class EscrubirPage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const EscrubirPage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<EscrubirPage> createState() => _EscrubirPageState();
}

class _EscrubirPageState extends State<EscrubirPage>
    with AutomaticKeepAliveClientMixin {
  final TmdbDiscoverService _discoverService = TmdbDiscoverService();
  final ScrollController _scrollController = ScrollController();

  String _tipo = 'movie';
  String _genero = 'Recientes';
  String _sortBy = 'popularity';

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _hasNext = false;
  bool _loadMoreQueued = false;

  final FocusNode _tipoFocus = FocusNode(debugLabel: 'filtro_tipo');
  final FocusNode _catalogoFocus = FocusNode(debugLabel: 'filtro_catalogo');
  final FocusNode _generoFocus = FocusNode(debugLabel: 'filtro_genero');

  final Map<int, FocusNode> _posterFocusNodes = {};
  final Map<int, GlobalKey> _posterKeys = {};

  static const int _kCols = 6;

  static const _sortLabels = <String, String>{
    'popularity': 'Popular',
    'year': 'Año',
    'title': 'Título',
    'rating': 'Calificación',
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMainFocusNodeCreated?.call(_tipoFocus);
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tipoFocus.dispose();
    _catalogoFocus.dispose();
    _generoFocus.dispose();
    for (final n in _posterFocusNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  List<String> get _currentGenres => _tipo == 'tv'
      ? TmdbDiscoverService.tvGenreLabels()
      : TmdbDiscoverService.movieGenreLabels();

  String get _tipoLabel => _tipo == 'tv' ? 'Series' : 'Película';
  String get _sortLabel => _sortLabels[_sortBy] ?? 'Popular';

  FocusNode _getPosterFocus(int index) {
    return _posterFocusNodes.putIfAbsent(index, () {
      final node = FocusNode(debugLabel: 'poster_$index');
      node.addListener(() {
        if (node.hasFocus) _scrollPosterIntoView(index);
      });
      return node;
    });
  }

  GlobalKey _getPosterKey(int index) {
    return _posterKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _scrollPosterIntoView(int index) {
    final key = _posterKeys[index];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: 0.25,
    );
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasNext = false;
      _loadMoreQueued = false;
      for (final n in _posterFocusNodes.values) {
        n.dispose();
      }
      _posterFocusNodes.clear();
      _posterKeys.clear();

      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
          _items = [];
        });
      }
    } else {
      if (_loadingMore || !_hasNext || _loadMoreQueued) return;
      _loadMoreQueued = true;
      if (mounted) setState(() => _loadingMore = true);
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
          _items = newItems;
        } else {
          _items.addAll(newItems);
        }
        _hasNext = hasNext;
        _page = currentPage + 1;
        _loading = false;
        _loadingMore = false;
        _loadMoreQueued = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexión o error de red';
        _loading = false;
        _loadingMore = false;
        _loadMoreQueued = false;
        if (reset) _items = [];
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_loadingMore || !_hasNext || _loadMoreQueued) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _load(reset: false);
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
    _load(reset: true);
  }

  void _changeGenero(String genero) {
    if (genero == _genero) return;
    setState(() => _genero = genero);
    _load(reset: true);
  }

  void _changeSort(String sort) {
    if (sort == _sortBy) return;
    setState(() => _sortBy = sort);
    _load(reset: true);
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
    );
  }

  void _openOpciones(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ?? item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;
    final tipo =
        item['media_type']?.toString() ?? item['type']?.toString() ?? 'movie';
    showContenidoOpcionesModal(
      context,
      tmdbId: id,
      tipo: tipo,
      idcontenido: id,
      titulo: item['title']?.toString() ?? item['titulo']?.toString(),
      posterUrl: item['poster_path']?.toString() ?? item['poster']?.toString(),
      backdropUrl:
          item['backdrop_path']?.toString() ?? item['backdrop']?.toString(),
    );
  }

  void _showTipoMenu() {
    _showFilterMenu(
      title: 'Tipo',
      options: const [('movie', 'Película'), ('tv', 'Series')],
      current: _tipo,
      onSelected: _changeTipo,
    );
  }

  void _showCatalogoMenu() {
    _showFilterMenu(
      title: 'Catálogo',
      options: _sortLabels.entries.map((e) => (e.key, e.value)).toList(),
      current: _sortBy,
      onSelected: _changeSort,
    );
  }

  void _showGeneroMenu() {
    final genres = _currentGenres;
    _showFilterMenu(
      title: 'Género',
      options: genres.map((g) => (g, g)).toList(),
      current: _genero,
      onSelected: _changeGenero,
      maxHeightFactor: 0.62,
    );
  }

  void _showFilterMenu({
    required String title,
    required List<(String value, String label)> options,
    required String current,
    required void Function(String) onSelected,
    double maxHeightFactor = 0.48,
  }) {
    final optionNodes = List.generate(options.length, (_) => FocusNode());
    final optionKeys = List.generate(options.length, (_) => GlobalKey());
    int selectedIndex = options.indexWhere((o) => o.$1 == current);
    if (selectedIndex < 0) selectedIndex = 0;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (optionNodes.isNotEmpty && selectedIndex < optionNodes.length) {
            optionNodes[selectedIndex].requestFocus();
          }
        });

        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 100),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 300,
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.sizeOf(context).height * maxHeightFactor,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                      child: Text(
                        title,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                        itemCount: options.length,
                        itemBuilder: (_, i) {
                          final (value, label) = options[i];
                          final isCurrent = value == current;

                          return Focus(
                            key: optionKeys[i],
                            focusNode: optionNodes[i],
                            onFocusChange: (hasFocus) {
                              if (hasFocus) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  final c = optionKeys[i].currentContext;
                                  if (c != null) {
                                    Scrollable.ensureVisible(
                                      c,
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      curve: Curves.easeOut,
                                      alignment: 0.4,
                                    );
                                  }
                                });
                              }
                            },
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                if (i > 0) {
                                  optionNodes[i - 1].requestFocus();
                                }
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                if (i < optionNodes.length - 1) {
                                  optionNodes[i + 1].requestFocus();
                                }
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.select ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter) {
                                Navigator.pop(ctx);
                                onSelected(value);
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.escape ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.goBack) {
                                Navigator.pop(ctx);
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final hasFocus = Focus.of(context).hasFocus;
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    onSelected(value);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    margin: const EdgeInsets.only(bottom: 5),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 13,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hasFocus
                                          ? Colors.white.withValues(alpha: 0.18)
                                          : (isCurrent
                                                ? kAccentColor.withValues(
                                                    alpha: 0.22,
                                                  )
                                                : Colors.transparent),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: hasFocus
                                            ? Colors.white
                                            : (isCurrent
                                                  ? kAccentColor.withValues(
                                                      alpha: 0.6,
                                                    )
                                                  : Colors.transparent),
                                        width: hasFocus ? 2.2 : 1.4,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              color: hasFocus || isCurrent
                                                  ? Colors.white
                                                  : Colors.white70,
                                              fontSize: 15,
                                              fontWeight: hasFocus || isCurrent
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (isCurrent)
                                          const Icon(
                                            Icons.check_rounded,
                                            color: kAccentColor,
                                            size: 20,
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
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      for (final n in optionNodes) {
        n.dispose();
      }
    });
  }

  KeyEventResult _onFilterKey(
    FocusNode node,
    KeyEvent event,
    int filterIndex,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (filterIndex == 0) {
        widget.onRequestMenuFocus?.call();
      } else if (filterIndex == 1) {
        _tipoFocus.requestFocus();
      } else if (filterIndex == 2) {
        _catalogoFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (filterIndex == 0) {
        _catalogoFocus.requestFocus();
      } else if (filterIndex == 1) {
        _generoFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onRequestMenuFocus?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_items.isNotEmpty) {
        _getPosterFocus(0).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (filterIndex == 0) _showTipoMenu();
      if (filterIndex == 1) _showCatalogoMenu();
      if (filterIndex == 2) _showGeneroMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onPosterKey(KeyEvent event, int index) {
    final col = index % _kCols;
    final row = index ~/ _kCols;

    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          if (col > 0) {
            _getPosterFocus(index - 1).requestFocus();
          } else {
            widget.onRequestMenuFocus?.call();
          }
          return KeyEventResult.handled;

        case LogicalKeyboardKey.arrowRight:
          if (col < _kCols - 1 && index + 1 < _items.length) {
            _getPosterFocus(index + 1).requestFocus();
          }
          return KeyEventResult.handled;

        case LogicalKeyboardKey.arrowUp:
          if (row > 0) {
            _getPosterFocus(index - _kCols).requestFocus();
          } else {
            _tipoFocus.requestFocus();
          }
          return KeyEventResult.handled;

        case LogicalKeyboardKey.arrowDown:
          final next = index + _kCols;
          if (next < _items.length) {
            _getPosterFocus(next).requestFocus();
          } else if (_hasNext) {
            _load(reset: false);
          }
          return KeyEventResult.handled;

        case LogicalKeyboardKey.contextMenu:
        case LogicalKeyboardKey.mediaPlay:
          _openOpciones(_items[index]);
          return KeyEventResult.handled;

        default:
          break;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    const topPad = 12.0;

    return Scaffold(
      backgroundColor: kBgColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: topPad),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: _FilterPill(
                    focusNode: _tipoFocus,
                    label: 'Tipo',
                    value: _tipoLabel,
                    onKeyEvent: (n, e) => _onFilterKey(n, e, 0),
                    onTap: _showTipoMenu,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FilterPill(
                    focusNode: _catalogoFocus,
                    label: 'Catálogo',
                    value: _sortLabel,
                    onKeyEvent: (n, e) => _onFilterKey(n, e, 1),
                    onTap: _showCatalogoMenu,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FilterPill(
                    focusNode: _generoFocus,
                    label: 'Género',
                    value: _genero == 'Recientes' ? 'Predeterminado' : _genero,
                    onKeyEvent: (n, e) => _onFilterKey(n, e, 2),
                    onTap: _showGeneroMenu,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
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
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _load(reset: true),
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
      return const Center(
        child: Text(
          'Sin contenido',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      cacheExtent: 500,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _kCols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 8,
        childAspectRatio: 0.68,
      ),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: kAccentColor,
                strokeWidth: 2,
              ),
            ),
          );
        }
        return _buildPoster(index);
      },
    );
  }

  Widget _buildPoster(int index) {
    final item = _items[index];
    final poster = _posterUrl(item['poster_path']);
    final year =
        (item['year']?.toString() ??
                (item['release_date'] ?? item['first_air_date'] ?? '')
                    .toString()
                    .split('-')
                    .first)
            .toString();
    final rating = (() {
      final r = item['vote_average'];
      if (r is num && r > 0) return r.toStringAsFixed(1);
      return '';
    })();

    final focusNode = _getPosterFocus(index);
    final key = _getPosterKey(index);
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);

    return _PosterTile(
      key: key,
      focusNode: focusNode,
      poster: poster,
      year: year,
      rating: rating,
      dpr: dpr,
      onKeyEvent: (event) => _onPosterKey(event, index),
      onTap: () {
        focusNode.requestFocus();
        _openContent(item);
      },
      onLongPress: () => _openOpciones(item),
    );
  }
}

class _PosterTile extends StatefulWidget {
  final FocusNode focusNode;
  final String poster;
  final String year;
  final String rating;
  final double dpr;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PosterTile({
    super.key,
    required this.focusNode,
    required this.poster,
    required this.year,
    required this.rating,
    required this.dpr,
    required this.onKeyEvent,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<_PosterTile> {
  Timer? _holdTimer;
  bool _longFired = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    _holdTimer?.cancel();
    _longFired = false;
    _holdTimer = Timer(const Duration(milliseconds: 550), () {
      _longFired = true;
      widget.onLongPress();
    });
  }

  void _endHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_longFired) {
      widget.onTap();
    }
    _longFired = false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (event is KeyDownEvent) {
            _startHold();
            return KeyEventResult.handled;
          }
          if (event is KeyUpEvent) {
            _endHold();
            return KeyEventResult.handled;
          }
        }
        return widget.onKeyEvent(event);
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2.4,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.18),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.poster,
                            fit: BoxFit.cover,
                            memCacheWidth: (140 * widget.dpr).round(),
                            memCacheHeight: (210 * widget.dpr).round(),
                            fadeInDuration: const Duration(milliseconds: 80),
                            placeholder: (_, __) =>
                                const ColoredBox(color: kCardBg),
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
                            child: Icon(
                              Icons.movie,
                              color: Colors.white24,
                              size: 28,
                            ),
                          ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 36,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xE6000000)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 5,
                      right: 5,
                      bottom: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (widget.year.isNotEmpty && widget.year != 'null')
                            Text(
                              widget.year,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          if (widget.rating.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 12,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  widget.rating,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
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
          );
        },
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final String value;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onTap;

  const _FilterPill({
    required this.focusNode,
    required this.label,
    required this.value,
    required this.onKeyEvent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKeyEvent(node, event),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              focusNode.requestFocus();
              onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: hasFocus
                    ? Colors.white.withValues(alpha: 0.18)
                    : kFilterBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.white24,
                  width: hasFocus ? 2.2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white.withValues(alpha: 0.65),
                    size: 20,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}