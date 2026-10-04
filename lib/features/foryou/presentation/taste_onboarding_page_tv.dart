import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../../../data/ai/ai_client.dart';
import '../../../data/ai/daily_ai_gate.dart';
import '../../../data/recommendations/user_taste_profile.dart';
import '../../../data/recommendations/daily_sections_generator.dart';
import '../../../data/recommendations/regional_top10.dart';
import 'taste_onboarding_page.dart' show HomeAlgorithmBus;

/// Onboarding de gustos adaptado a TV (D-pad / foco).
/// Rejilla focuseable con auto-scroll y foco siempre centrado.
class TasteOnboardingPageTv extends StatefulWidget {
  final VoidCallback onFinished;

  const TasteOnboardingPageTv({super.key, required this.onFinished});

  @override
  State<TasteOnboardingPageTv> createState() => _TasteOnboardingPageTvState();
}

class _TasteOnboardingPageTvState extends State<TasteOnboardingPageTv> {
  static const _tmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const _cols = 7;          // más columnas => pósters más pequeños
  static const _visibleRows = 3;   // filas visibles (foco centrado)

  final List<_TvPosterItem> _movies = [];
  final List<_TvPosterItem> _series = [];
  final Set<String> _selected = {};

  bool _loading = true;
  bool _saving = false;
  int _tab = 0;
  int _focusIndex = 0;
  int _pageMovie = 1;
  int _pageTv = 1;

  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _gridFocus = FocusNode(debugLabel: 'taste_grid');
  final FocusNode _tabMovies = FocusNode(debugLabel: 'taste_tab_movies');
  final FocusNode _tabSeries = FocusNode(debugLabel: 'taste_tab_series');
  final FocusNode _continueFocus = FocusNode(debugLabel: 'taste_continue');

  List<_TvPosterItem> get _list => _tab == 0 ? _movies : _series;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadInitial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _gridFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _gridFocus.dispose();
    _tabMovies.dispose();
    _tabSeries.dispose();
    _continueFocus.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    await Future.wait([
      _fetchPage('movie', 1),
      _fetchPage('tv', 1),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchPage(String media, int page) async {
    try {
      final url =
          'https://api.themoviedb.org/3/$media/popular?api_key=$_tmdbKey&language=es-MX&page=$page';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map;
      final results = data['results'] as List? ?? [];
      final out = <_TvPosterItem>[];
      for (final r in results) {
        if (r is! Map) continue;
        final id = (r['id'] as num?)?.toInt();
        final poster = r['poster_path']?.toString();
        if (id == null || poster == null || poster.isEmpty) continue;
        final title = (r['title'] ?? r['name'] ?? '').toString();
        out.add(_TvPosterItem(
          tmdbId: id,
          tipo: media == 'tv' ? 'tv' : 'movie',
          titulo: title,
          posterUrl: 'https://image.tmdb.org/t/p/w342$poster',
        ));
      }
      if (!mounted) return;
      setState(() {
        if (media == 'movie') {
          _movies.addAll(out);
          _pageMovie = page;
        } else {
          _series.addAll(out);
          _pageTv = page;
        }
      });
    } catch (_) {}
  }

  Future<void> _ensureMore() async {
    final list = _list;
    if (_focusIndex < list.length - _cols) return;
    if (_tab == 0) {
      await _fetchPage('movie', _pageMovie + 1);
    } else {
      await _fetchPage('tv', _pageTv + 1);
    }
  }

  void _toggleCurrent() {
    final list = _list;
    if (_focusIndex < 0 || _focusIndex >= list.length) return;
    final item = list[_focusIndex];
    final key = '${item.tipo}:${item.tmdbId}';
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  /// Centra la fila del foco en la zona visible (auto-scroll vertical).
  void _scrollToFocus() {
    if (!_scrollCtrl.hasClients) return;
    final row = _focusIndex ~/ _cols;
    // Cada fila mide aproximadamente lo mismo que el póster + spacing.
    // Usamos position para centrar la fila actual.
    final viewport = _scrollCtrl.position.viewportDimension;
    // Altura estimada de fila: la calculamos con el itemExtent real.
    // Como usamos GridView con childAspectRatio fijo, aproximamos:
    final rowHeight = _rowHeight;
    if (rowHeight <= 0) return;
    final target = (row * rowHeight) - (viewport / 2) + (rowHeight / 2);
    final clamped = target.clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(
      clamped,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  double _rowHeight = 0;
  double get rowHeightCache => _rowHeight;

  Future<void> _finish() async {
    if (_selected.length < 3) return;
    setState(() => _saving = true);
    final profile = await UserTasteProfile.load();
    final all = [..._movies, ..._series];
    for (final item in all) {
      final key = '${item.tipo}:${item.tmdbId}';
      if (!_selected.contains(key)) continue;
      await profile.likeContent(
        tmdbId: item.tmdbId,
        title: item.titulo,
        type: item.tipo,
        persist: false,
      );
    }
    await profile.save();
    await TasteOnboardingGate.markDone();
    if (mounted) {
      setState(() => _saving = false);
      widget.onFinished();
    }
    HomeAlgorithmBus.bump();
    // ignore: unawaited_futures
    Future(() async {
      try {
        final ai = AiClient();
        await RegionalTop10Service(ai: ai).load(force: true);
        await DailySectionsGenerator(ai: ai).getSections(force: true);
      } catch (_) {}
      HomeAlgorithmBus.bump();
    });
  }

  KeyEventResult _onGridKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final list = _list;
    if (list.isEmpty) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowRight) {
      if (_focusIndex < list.length - 1) {
        setState(() => _focusIndex++);
        _ensureMore();
        _scrollToFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_focusIndex > 0) {
        setState(() => _focusIndex--);
        _scrollToFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final next = _focusIndex + _cols;
      if (next < list.length) {
        setState(() => _focusIndex = next);
        _ensureMore();
        _scrollToFocus();
      } else {
        _continueFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final prev = _focusIndex - _cols;
      if (prev >= 0) {
        setState(() => _focusIndex = prev);
        _scrollToFocus();
      } else {
        (_tab == 0 ? _tabMovies : _tabSeries).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _toggleCurrent();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final list = _list;

    // Pósters más pequeños: 7 columnas y aspect ratio 2:3.
    const horizontalPadding = 40.0;
    const spacing = 10.0;
    final cardW =
        (size.width - horizontalPadding * 2 - (_cols - 1) * spacing) / _cols;
    final cardH = cardW / 0.67;
    _rowHeight = cardH + spacing;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ===== BARRA SUPERIOR: tabs + botón Continuar =====
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  horizontalPadding, 14, horizontalPadding, 8),
              child: Row(
                children: [
                  _TvChip(
                    label: 'Películas',
                    selected: _tab == 0,
                    focusNode: _tabMovies,
                    onSelect: () {
                      setState(() {
                        _tab = 0;
                        _focusIndex = 0;
                      });
                      _gridFocus.requestFocus();
                      _scrollToFocus();
                    },
                    onDown: () => _gridFocus.requestFocus(),
                    onRight: () => _tabSeries.requestFocus(),
                  ),
                  const SizedBox(width: 10),
                  _TvChip(
                    label: 'Series',
                    selected: _tab == 1,
                    focusNode: _tabSeries,
                    onSelect: () {
                      setState(() {
                        _tab = 1;
                        _focusIndex = 0;
                      });
                      _gridFocus.requestFocus();
                      _scrollToFocus();
                    },
                    onDown: () => _gridFocus.requestFocus(),
                    onLeft: () => _tabMovies.requestFocus(),
                    onRight: () => _continueFocus.requestFocus(),
                  ),
                  const Spacer(),
                  Text(
                    '${_selected.length} elegidas',
                    style: const TextStyle(
                      color: Colors.purpleAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Botón Continuar ARRIBA (no abajo)
                  _ContinueButton(
                    focusNode: _continueFocus,
                    saving: _saving,
                    canContinue: _selected.length >= 3 && !_saving,
                    count: _selected.length,
                    onUp: () => _gridFocus.requestFocus(),
                    onLeft: () => _tabSeries.requestFocus(),
                    onActivate: () {
                      if (_selected.length >= 3 && !_saving) _finish();
                    },
                  ),
                ],
              ),
            ),
            // ===== TÍTULO =====
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  horizontalPadding, 4, horizontalPadding, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '¿Qué te gusta?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text(
                      'OK para marcar · elige al menos 3',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            // ===== REJILLA con auto-scroll =====
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.purpleAccent,
                      ),
                    )
                  : Focus(
                      focusNode: _gridFocus,
                      onKeyEvent: _onGridKey,
                      child: Builder(
                        builder: (context) {
                          final gridFocused = Focus.of(context).hasFocus;
                          return Scrollbar(
                            controller: _scrollCtrl,
                            thumbVisibility: false,
                            child: GridView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                                vertical: 8,
                              ),
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _cols,
                                childAspectRatio: 0.67,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                              ),
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final item = list[i];
                                final key = '${item.tipo}:${item.tmdbId}';
                                final sel = _selected.contains(key);
                                final focused =
                                    gridFocused && i == _focusIndex;
                                return _PosterCard(
                                  item: item,
                                  selected: sel,
                                  focused: focused,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de póster con borde blanco bien visible cuando tiene foco.
class _PosterCard extends StatelessWidget {
  final _TvPosterItem item;
  final bool selected;
  final bool focused;

  const _PosterCard({
    required this.item,
    required this.selected,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focused
                ? Colors.white
                : (selected ? Colors.purpleAccent : Colors.transparent),
            width: focused ? 3 : (selected ? 2 : 0),
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: item.posterUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  const ColoredBox(color: Color(0xFF1a1a2e)),
              errorWidget: (_, __, ___) => const ColoredBox(
                color: Color(0xFF1a1a2e),
                child: Icon(Icons.movie, color: Colors.white24),
              ),
            ),
            if (selected)
              Container(
                color: Colors.purpleAccent.withValues(alpha: 0.28),
                alignment: Alignment.topRight,
                padding: const EdgeInsets.all(5),
                child: const Icon(
                  Icons.favorite,
                  color: Colors.pinkAccent,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Botón Continuar compacto para la barra superior.
class _ContinueButton extends StatelessWidget {
  final FocusNode focusNode;
  final bool saving;
  final bool canContinue;
  final int count;
  final VoidCallback onUp;
  final VoidCallback onLeft;
  final VoidCallback onActivate;

  const _ContinueButton({
    required this.focusNode,
    required this.saving,
    required this.canContinue,
    required this.count,
    required this.onUp,
    required this.onLeft,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onLeft();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onActivate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: canContinue
                    ? Colors.purpleAccent
                    : const Color(0xFF2a2a3e),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.3),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      canContinue
                          ? 'Continuar ($count)'
                          : 'Elige al menos 3',
                      style: TextStyle(
                        color:
                            canContinue ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _TvChip extends StatelessWidget {
  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _TvChip({
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onSelect,
    this.onDown,
    this.onLeft,
    this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          onDown?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          onRight?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onSelect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.purpleAccent
                    : const Color(0xFF1a1a2e),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TvPosterItem {
  final int tmdbId;
  final String tipo;
  final String titulo;
  final String posterUrl;

  const _TvPosterItem({
    required this.tmdbId,
    required this.tipo,
    required this.titulo,
    required this.posterUrl,
  });
}