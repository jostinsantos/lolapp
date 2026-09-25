// lib/servicios/pag_tv.dart  (o descrubir/pag_tv.dart)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/scrapers/base/base_home_scraper.dart';
import '../../../data/scrapers/base/scraper_context.dart';
import '../../../data/scrapers/base/registry.dart';
import '../domain/derivar.dart';
import 'source_search.dart';
const kAccentColor = Color(0xFFE50914);
const kBgColor = Colors.black;
const kCardBg = Color(0xFF1A1A1A);
const kFilterBg = Color(0xFF2A2A38);

class ServiciosTvPage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const ServiciosTvPage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<ServiciosTvPage> createState() => _ServiciosTvPageState();
}

class _ServiciosTvPageState extends State<ServiciosTvPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  late Fuente _servicio;
  String _tipo = 'movie';
  String _genero = '';
  bool _populares = false;

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<ScraperItem> _items = [];
  int _page = 1;
  bool _hasNext = false;
  bool _loadMoreQueued = false;

  // Filtros en orden: Servicio → Tipo → Género → Buscar
  final FocusNode _servicioFocus = FocusNode(debugLabel: 'filtro_servicio');
  final FocusNode _tipoFocus = FocusNode(debugLabel: 'filtro_tipo');
  final FocusNode _generoFocus = FocusNode(debugLabel: 'filtro_genero');
  final FocusNode _buscarFocus = FocusNode(debugLabel: 'filtro_buscar');

  final Map<int, FocusNode> _posterFocusNodes = {};
  final Map<int, GlobalKey> _posterKeys = {};

  static const int _kCols = 6;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final listado = fuentesConListado;
    _servicio = listado.isNotEmpty
        ? listado.first
        : Fuente(
            id: 'none',
            label: 'Ninguna',
            hasListing: false,
            hasSearch: false,
          );
    if (_servicio.tipos.isNotEmpty) {
      _tipo = _servicio.tipos.first;
    }

    _scrollController.addListener(_onScroll);

    // Primer filtro = nodo principal para el menú
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMainFocusNodeCreated?.call(_servicioFocus);
    });

    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _servicioFocus.dispose();
    _tipoFocus.dispose();
    _generoFocus.dispose();
    _buscarFocus.dispose();
    for (final n in _posterFocusNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  List<String> get _tiposDisponibles => _servicio.tipos;
  List<String> get _generosDisponibles => ['', ..._servicio.generos];
  String get _servicioLabel => _servicio.label;
  String get _tipoLabel => Fuente.tipoLabel(_tipo);

  String get _generoLabel {
    if (_genero.isEmpty) {
      if (_servicio.supportsPopulares && _populares) return 'Populares';
      return 'Recientes';
    }
    return Fuente.generoLabel(_genero);
  }

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

  void _clearPosterFocus() {
    for (final n in _posterFocusNodes.values) {
      n.dispose();
    }
    _posterFocusNodes.clear();
    _posterKeys.clear();
  }

  // ── Carga ────────────────────────────────────────────────────────────────
  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasNext = false;
      _loadMoreQueued = false;
      _clearPosterFocus();
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
      if (_servicio.fetch == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Esta fuente no tiene listado';
          _loading = false;
          _loadingMore = false;
          _loadMoreQueued = false;
          if (reset) _items = [];
        });
        return;
      }

      final result = await _servicio.fetch!(
        tipo: _genero.isEmpty ? _tipo : null,
        genero: _genero.isEmpty ? null : _genero,
        populares: _populares,
        page: _page,
      );

      if (!mounted) return;

      if (!result.ok) {
        setState(() {
          _error = result.error ?? 'Error desconocido';
          _loading = false;
          _loadingMore = false;
          _loadMoreQueued = false;
          if (reset) _items = [];
        });
        return;
      }

      setState(() {
        if (reset) {
          _items = result.items;
        } else {
          _items.addAll(result.items);
        }
        _hasNext = result.hasNext;
        _page = result.currentPage + 1;
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

  void _openDerivar(ScraperItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DerivarTvPage(
          servicio: _servicio.id,
          url: item.url,
          titulo: item.titulo,
          tipo: item.tipo,
        ),
      ),
    );
  }

  void _changeServicio(Fuente s) {
    if (s.id == _servicio.id) return;
    setState(() {
      _servicio = s;
      _tipo = s.tipos.isNotEmpty ? s.tipos.first : 'movie';
      _genero = '';
      _populares = false;
    });
    _load(reset: true);
  }

  void _changeTipo(String t) {
    if (t == _tipo) return;
    setState(() {
      _tipo = t;
      if (!_generosDisponibles.contains(_genero)) _genero = '';
    });
    _load(reset: true);
  }

  void _changeGenero(String g) {
    if (g == _genero) return;
    setState(() {
      _genero = g;
      if (g.isNotEmpty) _populares = false;
    });
    _load(reset: true);
  }

  void _openBuscar() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BuscarFuentesPage()),
    );
  }

  // ── Menús de filtros (mando) ─────────────────────────────────────────────
  void _showServicioMenu() {
    final list = fuentesConListado;
    _showFilterMenu(
      title: 'Fuente',
      options: list.map((f) => (f.id, f.label)).toList(),
      current: _servicio.id,
      onSelected: (id) {
        final f = list.where((e) => e.id == id).firstOrNull;
        if (f != null) _changeServicio(f);
      },
    );
  }

  void _showTipoMenu() {
    _showFilterMenu(
      title: 'Tipo',
      options: _tiposDisponibles
          .map((t) => (t, Fuente.tipoLabel(t)))
          .toList(),
      current: _tipo,
      onSelected: _changeTipo,
    );
  }

  void _showGeneroMenu() {
    final gens = _generosDisponibles;
    _showFilterMenu(
      title: 'Género',
      options: gens.map((g) {
        final label = g.isEmpty
            ? (_servicio.supportsPopulares && _populares
                ? 'Populares'
                : 'Recientes')
            : Fuente.generoLabel(g);
        return (g, label);
      }).toList(),
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
    if (options.isEmpty) return;

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
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  final c = optionKeys[i].currentContext;
                                  if (c != null) {
                                    Scrollable.ensureVisible(
                                      c,
                                      duration:
                                          const Duration(milliseconds: 180),
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
                                if (i > 0) optionNodes[i - 1].requestFocus();
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
                                    duration:
                                        const Duration(milliseconds: 120),
                                    margin: const EdgeInsets.only(bottom: 5),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 13,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hasFocus
                                          ? Colors.white
                                              .withValues(alpha: 0.18)
                                          : (isCurrent
                                              ? kAccentColor.withValues(
                                                  alpha: 0.22)
                                              : Colors.transparent),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: hasFocus
                                            ? Colors.white
                                            : (isCurrent
                                                ? kAccentColor.withValues(
                                                    alpha: 0.6)
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

  // ── Navegación de filtros ────────────────────────────────────────────────
  // 0=Servicio, 1=Tipo, 2=Género, 3=Buscar
  KeyEventResult _onFilterKey(FocusNode node, KeyEvent event, int filterIndex) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (filterIndex == 0) {
        widget.onRequestMenuFocus?.call();
      } else if (filterIndex == 1) {
        _servicioFocus.requestFocus();
      } else if (filterIndex == 2) {
        _tipoFocus.requestFocus();
      } else if (filterIndex == 3) {
        _generoFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (filterIndex == 0) {
        _tipoFocus.requestFocus();
      } else if (filterIndex == 1) {
        _generoFocus.requestFocus();
      } else if (filterIndex == 2) {
        _buscarFocus.requestFocus();
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
      if (filterIndex == 0) _showServicioMenu();
      if (filterIndex == 1) _showTipoMenu();
      if (filterIndex == 2) _showGeneroMenu();
      if (filterIndex == 3) _openBuscar();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Navegación de pósters ────────────────────────────────────────────────
  KeyEventResult _onPosterKey(KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final col = index % _kCols;
    final row = index ~/ _kCols;

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
          // Primera fila → filtros
          _servicioFocus.requestFocus();
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

      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        _openDerivar(_items[index]);
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Menú siempre lateral: solo un pequeño padding superior
    const topPad = 12.0;

    return Scaffold(
      backgroundColor: kBgColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: topPad),

          // ── Filtros fijos ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _FilterPill(
                    focusNode: _servicioFocus,
                    label: 'Fuente',
                    value: _servicioLabel,
                    onKeyEvent: (n, e) => _onFilterKey(n, e, 0),
                    onTap: _showServicioMenu,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _FilterPill(
                    focusNode: _tipoFocus,
                    label: 'Tipo',
                    value: _tipoLabel,
                    onKeyEvent: (n, e) => _onFilterKey(n, e, 1),
                    onTap: _showTipoMenu,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _FilterPill(
                    focusNode: _generoFocus,
                    label: 'Género',
                    value: _generoLabel,
                    onKeyEvent: (n, e) => _onFilterKey(n, e, 2),
                    onTap: _showGeneroMenu,
                  ),
                ),
                const SizedBox(width: 12),
                _SearchPill(
                  focusNode: _buscarFocus,
                  onKeyEvent: (n, e) => _onFilterKey(n, e, 3),
                  onTap: _openBuscar,
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
        child: CircularProgressIndicator(
          color: kAccentColor,
          strokeWidth: 2.5,
        ),
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
            Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  _load(reset: true);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final hasFocus = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: () => _load(reset: true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: kAccentColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasFocus ? Colors.white : Colors.transparent,
                          width: 2.2,
                        ),
                      ),
                      child: const Text(
                        'Reintentar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
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
    final poster = item.poster;
    final year = item.year?.toString() ?? '';
    final hasRating = item.rating != null && item.rating! > 0;
    final rating =
        hasRating ? item.rating!.toStringAsFixed(1) : '';

    final focusNode = _getPosterFocus(index);
    final key = _getPosterKey(index);
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);

    return Focus(
      key: key,
      focusNode: focusNode,
      onKeyEvent: (node, event) => _onPosterKey(event, index),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              focusNode.requestFocus();
              _openDerivar(item);
            },
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
                    poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: poster,
                            fit: BoxFit.cover,
                            memCacheWidth: (140 * dpr).round(),
                            memCacheHeight: (210 * dpr).round(),
                            fadeInDuration:
                                const Duration(milliseconds: 80),
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
                          if (year.isNotEmpty && year != 'null')
                            Text(
                              year,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          if (rating.isNotEmpty)
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
                                  rating,
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

// ── Píldora de filtro ──────────────────────────────────────────────────────
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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

// ── Botón Buscar (píldora) ─────────────────────────────────────────────────
class _SearchPill extends StatelessWidget {
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onTap;

  const _SearchPill({
    required this.focusNode,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: hasFocus ? kAccentColor : kAccentColor.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: hasFocus ? 2.2 : 0,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: kAccentColor.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text(
                    'Buscar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
}