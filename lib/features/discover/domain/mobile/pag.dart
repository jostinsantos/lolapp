// lib/servicios/pag.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../data/scrapers/base/base_home_scraper.dart';
import '../../../../data/scrapers/base/scraper_context.dart';
import '../../../../data/scrapers/base/registry.dart';
import '../../../../data/scrapers/base/buscador.dart';
import 'derivar.dart';
const kAccentColor = Color(0xFFE50914);
const kBgColor = Colors.black;
const kCardBg = Color(0xFF1a1a2e);

class ServiciosPage extends StatefulWidget {
  const ServiciosPage({super.key});

  @override
  State<ServiciosPage> createState() => _ServiciosPageState();
}

class _ServiciosPageState extends State<ServiciosPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  // ── Modo listado ────────────────────────────────────────────────────────
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

  // ── Modo búsqueda ───────────────────────────────────────────────────────
  bool _isSearching = false;
  bool _searchLoading = false;
  String? _searchError;
  String _searchTipo = 'todas'; // todas | id de fuente
  List<BuscadorItem> _searchItems = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final listado = fuentesConListado;
    _servicio = listado.isNotEmpty
        ? listado.first
        : Fuente(id: 'none', label: 'Ninguna', hasListing: false, hasSearch: false);
    if (_servicio.tipos.isNotEmpty) {
      _tipo = _servicio.tipos.first;
    }
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Opciones dinámicas (desde la fuente actual) ─────────────────────────
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

  String get _searchTipoLabel {
    if (_searchTipo == 'todas') return 'Todas las fuentes';
    final f = fuenteById(_searchTipo);
    return f?.label ?? _searchTipo;
  }

  // ── Carga listado ───────────────────────────────────────────────────────
  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasNext = false;
      _loadMoreQueued = false;
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
    if (!_scroll.hasClients || _isSearching) return;
    if (_loadingMore || !_hasNext || _loadMoreQueued) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _load(reset: false);
    }
  }

  // ── Búsqueda ────────────────────────────────────────────────────────────
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchItems = [];
        _searchError = null;
        _searchLoading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _doSearch(value.trim());
    });
  }

  Future<void> _doSearch([String? force]) async {
    final q = (force ?? _searchCtrl.text).trim();
    if (q.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchLoading = true;
      _searchError = null;
      _searchItems = [];
    });

    try {
      final res = await buscarEnFuentes(q: q, tipo: _searchTipo);
      if (!mounted) return;

      if (!res.ok) {
        setState(() {
          _searchError = res.error ?? 'Error en la búsqueda';
          _searchLoading = false;
        });
        return;
      }

      final flat = <BuscadorItem>[];
      res.resultados.forEach((_, list) => flat.addAll(list));

      setState(() {
        _searchItems = flat;
        _searchLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Sin conexión o error de red';
        _searchLoading = false;
      });
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _isSearching = false;
      _searchItems = [];
      _searchError = null;
      _searchLoading = false;
    });
  }

  // ── Navegación a Derivar ────────────────────────────────────────────────
  void _openDerivar({
    required String servicio,
    required String url,
    required String titulo,
    required String tipo,
  }) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DerivarPage(
          servicio: servicio,
          url: url,
          titulo: titulo,
          tipo: tipo,
        ),
      ),
    );
  }

  // ── Cambios de filtros ──────────────────────────────────────────────────
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

  // ── Bottom sheets ───────────────────────────────────────────────────────
  void _showSearchFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSheet(
        title: 'Buscar en',
        children: [
          _sheetOption('Todas las fuentes', _searchTipo == 'todas', () {
            Navigator.pop(ctx);
            setState(() => _searchTipo = 'todas');
            if (_searchCtrl.text.trim().isNotEmpty) _doSearch();
          }),
          ...fuentesConBusqueda.map((f) => _sheetOption(
                f.label,
                _searchTipo == f.id,
                () {
                  Navigator.pop(ctx);
                  setState(() => _searchTipo = f.id);
                  if (_searchCtrl.text.trim().isNotEmpty) _doSearch();
                },
              )),
        ],
      ),
    );
  }

  void _showServicioSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSheet(
        title: 'Servicio / Fuente',
        children: fuentesConListado
            .map((f) => _sheetOption(
                  f.label,
                  _servicio.id == f.id,
                  () {
                    Navigator.pop(ctx);
                    _changeServicio(f);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _showTipoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSheet(
        title: 'Tipo',
        children: _tiposDisponibles.map((t) {
          return _sheetOption(Fuente.tipoLabel(t), _tipo == t, () {
            Navigator.pop(ctx);
            _changeTipo(t);
          });
        }).toList(),
      ),
    );
  }

  void _showGeneroSheet() {
    final gens = _generosDisponibles;
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
                  'Género / Categoría',
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
                    itemCount: gens.length,
                    itemBuilder: (_, i) {
                      final g = gens[i];
                      final label = g.isEmpty
                          ? (_servicio.supportsPopulares && _populares
                              ? 'Populares'
                              : 'Recientes')
                          : Fuente.generoLabel(g);
                      return _sheetOption(
                        label,
                        (g.isEmpty && _genero.isEmpty) || g == _genero,
                        () {
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

  Widget _buildSheet({required String title, required List<Widget> children}) {
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
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _sheetOption(String label, bool selected, VoidCallback onTap) {
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

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom + 72;

    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Barra de búsqueda ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) => _doSearch(),
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        cursorColor: kAccentColor,
                        decoration: InputDecoration(
                          hintText: 'Buscar en fuentes...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Colors.white54,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  onPressed: _clearSearch,
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
                  const SizedBox(width: 8),
                  Material(
                    color: kCardBg,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _showSearchFilterSheet,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.filter_list_rounded,
                              size: 18,
                              color: kAccentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _searchTipo == 'todas' ? 'Todas' : _searchTipoLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Contenido ─────────────────────────────────────────────────
            Expanded(
              child: _isSearching
                  ? _buildSearchResults(bottomPad)
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _FilterChipButton(
                                  label: _servicioLabel,
                                  icon: Icons.cloud_rounded,
                                  onTap: _showServicioSheet,
                                ),
                              ),
                              const SizedBox(width: 8),
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
                                  label: _generoLabel,
                                  icon: Icons.category_rounded,
                                  onTap: _showGeneroSheet,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            '$_servicioLabel · $_tipoLabel · $_generoLabel',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(child: _buildListBody(bottomPad)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Resultados de búsqueda ──────────────────────────────────────────────
  Widget _buildSearchResults(double bottomPad) {
    if (_searchLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kAccentColor, strokeWidth: 2.5),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _searchError!,
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

    if (_searchItems.isEmpty) {
      return Center(
        child: Text(
          'Sin resultados para "${_searchCtrl.text.trim()}"',
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
            '${_searchItems.length} resultado${_searchItems.length == 1 ? '' : 's'} · $_searchTipoLabel',
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
            itemCount: _searchItems.length,
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
              final item = _searchItems[index];
              return _SearchPosterCard(
                item: item,
                onTap: () => _openDerivar(
                  servicio: item.sitio,
                  url: item.url,
                  titulo: item.titulo,
                  tipo: item.tipo,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Listado normal ──────────────────────────────────────────────────────
  Widget _buildListBody(double bottomPad) {
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
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
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
      return RefreshIndicator(
        color: kAccentColor,
        backgroundColor: kCardBg,
        onRefresh: () => _load(reset: true),
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
      onRefresh: () => _load(reset: true),
      child: GridView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
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
          if (index >= _items.length) {
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

          final item = _items[index];
          return _PosterCard(
            item: item,
            onTap: () => _openDerivar(
              servicio: _servicio.id,
              url: item.url,
              titulo: item.titulo,
              tipo: item.tipo,
            ),
          );
        },
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────

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

class _PosterCard extends StatelessWidget {
  final ScraperItem item;
  final VoidCallback onTap;

  const _PosterCard({required this.item, required this.onTap});

  static const double _w = 120;
  static const double _h = 180;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    final ratingText = (item.rating != null && item.rating! > 0)
        ? item.rating!.toStringAsFixed(1)
        : 'N/A';
    final poster = item.poster;
    final memW = (_w * dpr).round();
    final memH = (_h * dpr).round();
    final year = item.year?.toString() ?? '';

    return GestureDetector(
      onTap: onTap,
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
          if (year.isNotEmpty)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  year,
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

class _SearchPosterCard extends StatelessWidget {
  final BuscadorItem item;
  final VoidCallback onTap;

  const _SearchPosterCard({required this.item, required this.onTap});

  static const double _w = 120;
  static const double _h = 180;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    final ratingText = (item.rating != null && item.rating! > 0)
        ? item.rating!.toStringAsFixed(1)
        : 'N/A';
    final poster = item.imagen;
    final memW = (_w * dpr).round();
    final memH = (_h * dpr).round();
    final year = item.anio?.toString() ?? '';

    return GestureDetector(
      onTap: onTap,
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
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.sitio,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
          if (year.isNotEmpty)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  year,
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