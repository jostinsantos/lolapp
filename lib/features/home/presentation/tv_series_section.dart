// home/tv.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

import '../../content/presentation/tv_content_page.dart';
const _kAccentColor = Color(0xFFE50914);
const _kBaseUrl = 'https://modlyo.com/apitv';
const _kPerPage = 18;
const _kCols = 6;

class TvPage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const TvPage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> {
  static const List<String> _generos = [
    'Recientes',
    'Acción y Aventura',
    'Animación',
    'Comedia',
    'Crimen',
    'Documental',
    'Drama',
    'Familia',
    'Kids',
    'Misterio',
    'News',
    'Reality',
    'Sci-Fi & Fantasy',
    'Soap',
    'Talk',
    'War & Politics',
    'Western',
    'Terror',
    'Suspense',
  ];

  String _generoSeleccionado = 'Recientes';
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _items = [];
  String? _error;

  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _generoScrollController = ScrollController();
  final List<FocusNode> _generoFocusNodes = [];
  final Map<int, FocusNode> _posterFocusNodes = {};
  final List<GlobalKey> _generoKeys = [];
  final Map<int, GlobalKey> _posterKeys = {};

  // Control de carga de géneros
  String _generoEnCarga = '';
  bool _cargandoGenero = false;

  @override
  void initState() {
    super.initState();
    _inicializarGeneros();
    widget.onMainFocusNodeCreated?.call(_generoFocusNodes[0]);
    _cargarContenido(reset: true);
    _gridScrollController.addListener(_onScroll);
  }

  void _inicializarGeneros() {
    for (var i = 0; i < _generos.length; i++) {
      final node = FocusNode();
      final key = GlobalKey();
      _generoFocusNodes.add(node);
      _generoKeys.add(key);
      node.addListener(() {
        if (node.hasFocus) _scrollGeneroIntoView(i);
      });
    }
  }

  void _scrollGeneroIntoView(int index) {
    if (index < 0 || index >= _generoKeys.length) return;
    final ctx = _generoKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
  }

  void _scrollPosterIntoView(int index) {
    final key = _posterKeys[index];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.3,
    );
  }

  @override
  void dispose() {
    _gridScrollController.removeListener(_onScroll);
    _gridScrollController.dispose();
    _generoScrollController.dispose();
    for (final n in _generoFocusNodes) {
      n.dispose();
    }
    for (final n in _posterFocusNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_gridScrollController.hasClients) return;
    if (!_hasMore || _loadingMore) return;
    try {
      final pos = _gridScrollController.position;
      if (pos.maxScrollExtent <= 0) return;
      if (pos.pixels >= pos.maxScrollExtent - 200) {
        _cargarMas();
      }
    } catch (_) {}
  }

  Future<void> _cargarContenido({bool reset = false}) async {
    // Evitar cargas simultáneas del mismo género
    if (_cargandoGenero && _generoEnCarga == _generoSeleccionado) return;

    if (reset) {
      setState(() {
        _page = 1;
        _items = [];
        _hasMore = true;
        _error = null;
        _loading = true;
        _cargandoGenero = true;
        _generoEnCarga = _generoSeleccionado;
      });
      for (final n in _posterFocusNodes.values) {
        n.dispose();
      }
      _posterFocusNodes.clear();
      _posterKeys.clear();
    }

    try {
      final generoParam =
          _generoSeleccionado == 'Recientes' ? 'recientes' : _generoSeleccionado;

      final uri = Uri.parse(
        '$_kBaseUrl/genero.php?tipo=tv&genero=${Uri.encodeComponent(generoParam)}&page=$_page',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        throw Exception('Error HTTP ${res.statusCode}');
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        throw Exception(json['error'] ?? 'Error desconocido');
      }

      final List data = json['data'] ?? [];
      final totalPages = (json['total_pages'] as num?)?.toInt() ?? 1;

      if (!mounted) return;

      setState(() {
        _items.addAll(List<Map<String, dynamic>>.from(data));
        _hasMore = _page < totalPages;
        _loading = false;
        _loadingMore = false;
        _cargandoGenero = false;
        _generoEnCarga = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
        _cargandoGenero = false;
        _generoEnCarga = '';
      });
    }
  }

  Future<void> _cargarMas() async {
    if (!_hasMore || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    await _cargarContenido();
  }

  void _seleccionarGenero(String genero) {
    if (genero == _generoSeleccionado) return;
    // Cancelar carga anterior si existe
    _cargandoGenero = false;
    _generoEnCarga = '';
    setState(() => _generoSeleccionado = genero);
    _cargarContenido(reset: true);
  }

  String _obtenerPoster(Map<String, dynamic> item) {
    final poster = item['poster_path'];
    if (poster is List && poster.isNotEmpty) return poster[0].toString();
    if (poster is String && poster.isNotEmpty) {
      try {
        final decoded = jsonDecode(poster);
        if (decoded is List && decoded.isNotEmpty) return decoded[0].toString();
      } catch (_) {}
      return poster;
    }
    return '';
  }

  String _obtenerAnio(Map<String, dynamic> item) {
    final date = item['first_air_date']?.toString() ?? '';
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  String _obtenerCalificacion(Map<String, dynamic> item) {
    final vote = item['vote_average'];
    if (vote == null) return '';
    final v = double.tryParse(vote.toString()) ?? 0;
    return v.toStringAsFixed(1);
  }

  void _abrirContenido(Map<String, dynamic> item) {
    final id = item['idcontenido'];
    if (id == null) return;
    final idInt = id is int ? id : int.tryParse(id.toString());
    if (idInt == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PageContenido(idcontenido: idInt),
      ),
    );
  }

  FocusNode _getPosterFocusNode(int index) {
    if (_posterFocusNodes.containsKey(index)) {
      return _posterFocusNodes[index]!;
    }
    final node = FocusNode();
    _posterFocusNodes[index] = node;
    // Cuando este poster gana foco → la cámara lo sigue
    node.addListener(() {
      if (node.hasFocus) {
        _scrollPosterIntoView(index);
      }
    });
    return node;
  }

  GlobalKey _getPosterKey(int index) {
    return _posterKeys.putIfAbsent(index, () => GlobalKey());
  }

  // Método público para recargar desde el padre (MainHome)
  void reload() {
    if (mounted) {
      _cargarContenido(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGenerosColumn(),
          _buildPosterGrid(),
        ],
      ),
    );
  }

  Widget _buildGenerosColumn() {
    return SizedBox(
      width: 120,
      child: ColoredBox(
        color: const Color(0xFF0A0A0A),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 80),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Text(
                'Géneros TV',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _generoScrollController,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: _generos.length,
                itemBuilder: (context, i) => _buildGeneroItem(i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneroItem(int index) {
    final genero = _generos[index];
    final isSelected = genero == _generoSeleccionado;
    final focusNode = _generoFocusNodes[index];
    final key = _generoKeys[index];

    return Focus(
      key: key,
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowDown:
            if (index < _generos.length - 1) {
              _generoFocusNodes[index + 1].requestFocus();
            }
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowUp:
            if (index > 0) {
              _generoFocusNodes[index - 1].requestFocus();
            } else {
              widget.onRequestMenuFocus?.call();
            }
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            if (_items.isNotEmpty) {
              _getPosterFocusNode(0).requestFocus();
            }
            return KeyEventResult.handled;
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.enter:
            _seleccionarGenero(genero);
            return KeyEventResult.handled;
          default:
            return KeyEventResult.ignored;
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              focusNode.requestFocus();
              _seleccionarGenero(genero);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? _kAccentColor
                    : hasFocus
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      genero,
                      style: TextStyle(
                        color: isSelected || hasFocus
                            ? Colors.white
                            : Colors.white60,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected && _cargandoGenero && _generoEnCarga == genero)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
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

  Widget _buildPosterGrid() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 80, 8, 8),
        child: _loading && _items.isEmpty
            ? const Center(
                child: CircularProgressIndicator(
                  color: _kAccentColor,
                  strokeWidth: 2,
                ),
              )
            : _error != null && _items.isEmpty
                ? _buildErrorWidget()
                : _items.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay resultados',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : GridView.builder(
                        controller: _gridScrollController,
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _kCols,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        cacheExtent: 500,
                        itemCount: _items.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) => _buildPosterItem(
                          context,
                          index,
                        ),
                      ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            style: const TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _cargarContenido(reset: true),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterItem(BuildContext context, int index) {
    if (index >= _items.length) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: _kAccentColor,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final item = _items[index];
    final posterUrl = _obtenerPoster(item);
    final anio = _obtenerAnio(item);
    final calif = _obtenerCalificacion(item);
    final focusNode = _getPosterFocusNode(index);
    final posterKey = _getPosterKey(index);

    return Focus(
      key: posterKey,
      focusNode: focusNode,
      onKeyEvent: (node, event) => _handlePosterKeyEvent(event, index),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              focusNode.requestFocus();
              _abrirContenido(item);
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPosterImage(posterUrl),
                    _buildPosterOverlay(anio, calif),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPosterImage(String posterUrl) {
    if (posterUrl.isEmpty) {
      return Container(
        color: Colors.grey[900],
        child: const Icon(Icons.tv, color: Colors.white24, size: 22),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.5);
    final memWidth = (120 * dpr).round();
    final memHeight = (180 * dpr).round();

    return CachedNetworkImage(
      imageUrl: posterUrl,
      fit: BoxFit.cover,
      memCacheWidth: memWidth,
      memCacheHeight: memHeight,
      maxWidthDiskCache: memWidth,
      maxHeightDiskCache: memHeight,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => Container(color: Colors.grey[900]),
      errorWidget: (_, __, ___) => Container(
        color: Colors.grey[900],
        child: const Icon(Icons.tv, color: Colors.white24, size: 22),
      ),
    );
  }

  Widget _buildPosterOverlay(String anio, String calif) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 28,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.9),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 3,
          right: 3,
          bottom: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (anio.isNotEmpty)
                Text(
                  anio,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (calif.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Colors.amber,
                      size: 10,
                    ),
                    Text(
                      calif,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  KeyEventResult _handlePosterKeyEvent(KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final col = index % _kCols;
    final row = index ~/ _kCols;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (col > 0) {
          _getPosterFocusNode(index - 1).requestFocus();
        } else {
          final genIdx = _generos.indexOf(_generoSeleccionado);
          if (genIdx >= 0) {
            _generoFocusNodes[genIdx].requestFocus();
          } else {
            _generoFocusNodes[0].requestFocus();
          }
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        if (col < _kCols - 1 && index + 1 < _items.length) {
          _getPosterFocusNode(index + 1).requestFocus();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp:
        if (row > 0) {
          _getPosterFocusNode(index - _kCols).requestFocus();
        } else {
          widget.onRequestMenuFocus?.call();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        final next = index + _kCols;
        if (next < _items.length) {
          _getPosterFocusNode(next).requestFocus();
        } else if (_hasMore) {
          _cargarMas();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        _abrirContenido(_items[index]);
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }
}