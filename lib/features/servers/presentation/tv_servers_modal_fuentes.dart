// lib/tv/descrubir/servidores_modal_fuentes.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ajusta a tu ruta real de MainFuentesServidores
import '../../../data/aggregators/main_fuentes_servidores.dart';
import '../../discover/domain/extractor.dart';
import '../../player/presentation/tv/tv_discover_player.dart';
const _kAccent = Color(0xFFE50914);
const _kOrange = Color(0xFFFF6B00);
// Panel y cards más transparentes
const _kPanel = Color(0x4D141416);
const _kCard = Color(0x661C1C1E);
const _kBg = Color(0xFF0A0A0A);
const double _kItemExtent = 100.0;

class ServidoresModalFuentesTv extends StatefulWidget {
  final int tmdbId;
  final int? idcontenido;
  final String tipo;
  final int? temporada;
  final int? capitulo;
  final String fuente;
  final String? titulo;
  final String? tituloOverride;
  final String? backdropUrl;
  final String? posterUrl;
  final String? logoUrl;
  final bool fromPlayer;
  final bool esSiguienteCapitulo;
  final String? currentServidorUrl;

  const ServidoresModalFuentesTv({
    super.key,
    required this.tmdbId,
    this.idcontenido,
    required this.tipo,
    this.temporada,
    this.capitulo,
    required this.fuente,
    this.titulo,
    this.tituloOverride,
    this.backdropUrl,
    this.posterUrl,
    this.logoUrl,
    this.fromPlayer = false,
    this.esSiguienteCapitulo = false,
    this.currentServidorUrl,
  });

  @override
  State<ServidoresModalFuentesTv> createState() =>
      _ServidoresModalFuentesTvState();
}

class _ServidoresModalFuentesTvState extends State<ServidoresModalFuentesTv> {
  final List<Map<String, dynamic>> _servers = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;
  bool _fromCache = false;
  bool _navigating = false;

  String? _backdrop;
  String? _logo;
  String _titulo = '';

  final FocusNode _closeFocus = FocusNode(debugLabel: 'close');
  final FocusNode _reloadFocus = FocusNode(debugLabel: 'reload');
  final List<FocusNode> _cardFocus = [];
  final ScrollController _listScroll = ScrollController();
  int _lastCardIndex = 0;
  List<Map<String, dynamic>> _flatList = [];

  int get _resolvedId =>
      widget.tmdbId > 0 ? widget.tmdbId : (widget.idcontenido ?? 0);

  bool get _isMovie {
    final t = widget.tipo.toLowerCase();
    return t == 'movie' || t == 'pelicula' || t == 'película';
  }

  /// Misma normalización que el móvil + alias Serieskao
  String get _fuente {
    final raw = widget.fuente.trim().toLowerCase();
    if (raw.isEmpty) return '';
    // Asegura el mismo mapeo que MainFuentesServidores._mapServicio
    switch (raw) {
      case 'serieskao':
      case 'series kao':
      case 'embed69':
        return 'serieskao'; // MainFuentesServidores lo mapea a embed69
      default:
        return raw;
    }
  }

  String get _cacheKey {
    final s = widget.temporada ?? 0;
    final e = widget.capitulo ?? 0;
    return 'servidores_cache_${_resolvedId}_${widget.tipo}_${_fuente}_T${s}_C$e';
  }

  String get _tituloFinal {
    if (widget.tituloOverride != null &&
        widget.tituloOverride!.trim().isNotEmpty) {
      return widget.tituloOverride!.trim();
    }
    if (_titulo.isNotEmpty) return _titulo;
    return widget.titulo?.trim().isNotEmpty == true
        ? widget.titulo!.trim()
        : 'Contenido';
  }

  String? get _seasonEp {
    if (_isMovie || widget.temporada == null) return null;
    final s = widget.temporada!.toString().padLeft(2, '0');
    final e = (widget.capitulo ?? 1).toString().padLeft(2, '0');
    return 'T$s · E$e';
  }

  int get _playersCount => _servers
      .where((s) =>
          s['verificado'] == true &&
          (s['resolved_m3u8']?.toString().isNotEmpty ?? false))
      .length;

  int get _webviewsCount => _servers.length - _playersCount;

  @override
  void initState() {
    super.initState();
    _backdrop = widget.backdropUrl ?? widget.posterUrl;
    _logo = widget.logoUrl;
    _titulo = widget.titulo?.trim() ?? '';
    debugPrint(
      '[ServidoresFuentesTv] fuente="${_fuente}" tmdb=$_resolvedId '
      'tipo=${widget.tipo} T=${widget.temporada} E=${widget.capitulo}',
    );
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _closeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _closeFocus.dispose();
    _reloadFocus.dispose();
    _listScroll.dispose();
    for (final n in _cardFocus) {
      n.dispose();
    }
    super.dispose();
  }

  void _rebuildFlatList() {
    final byLang = <String, List<Map<String, dynamic>>>{};
    for (final s in _servers) {
      final lang = _normalizeIdioma(s['idioma']?.toString());
      byLang.putIfAbsent(lang, () => []).add(s);
    }
    final langKeys = byLang.keys.toList()
      ..sort((a, b) {
        const order = ['es_MX', 'es_ES', 'en_US', 'ja_JP'];
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    _flatList = [];
    for (final lang in langKeys) {
      _flatList.addAll(byLang[lang]!);
    }
  }

  void _resyncCardFocus({bool force = false}) {
    final needed = _flatList.length;
    if (!force && needed == _cardFocus.length) return;

    if (force) {
      for (final n in _cardFocus) {
        n.dispose();
      }
      _cardFocus
        ..clear()
        ..addAll(List.generate(needed, (_) => FocusNode()));
      _lastCardIndex = 0;
      return;
    }

    while (_cardFocus.length < needed) {
      _cardFocus.add(FocusNode());
    }
    while (_cardFocus.length > needed) {
      _cardFocus.removeLast().dispose();
    }
  }

  Future<void> _bootstrap() async {
    if (_fuente.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Fuente no soportada. Pasa la fuente (ej. serieskao) desde Derivar.';
        });
      }
      return;
    }

    final cached = await _loadCache();
    // Solo usar caché si tiene servidores
    if (cached != null && cached.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _servers
          ..clear()
          ..addAll(cached);
        _fromCache = true;
        _loading = false;
        _error = null;
      });
      _rebuildFlatList();
      _resyncCardFocus(force: true);
      return;
    }

    // Caché vacío → no sirve, scrapear de nuevo
    if (cached != null && cached.isEmpty) {
      await _clearCache();
    }

    _start(force: true);
  }

  Future<List<Map<String, dynamic>>?> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache() async {
    // No guardar lista vacía (evita “0 servidores” eterno en TV)
    if (_servers.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_servers));
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }

  /// Misma lógica que el modal móvil + fallback WEBVIEW si HLS falla en TV
  void _start({bool force = false}) {
    if (_fuente.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Fuente no soportada.';
      });
      return;
    }

    _sub?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
      if (force) {
        _servers.clear();
        _flatList.clear();
      }
    });
    if (force) _resyncCardFocus(force: true);

    debugPrint('[ServidoresFuentesTv] scrape servicio=$_fuente id=$_resolvedId');

    _sub = MainFuentesServidores.scrape(
      servicio: _fuente,
      tmdbId: _resolvedId,
      isMovie: _isMovie,
      season: widget.temporada ?? 1,
      episode: widget.capitulo ?? 1,
      context: context,
      verificar: true,
    ).listen((event) {
      if (!mounted) return;

      if (event.error != null && event.isDone) {
        setState(() {
          _error = event.error;
          _loading = false;
        });
        return;
      }

      if (event.servidor != null) {
        final s = Map<String, dynamic>.from(event.servidor!);
        final resuelto =
            event.resolvedM3u8 ?? s['resolved_m3u8']?.toString();
        if (resuelto != null && resuelto.isNotEmpty) {
          s['resolved_m3u8'] = resuelto;
          s['verificado'] = true;
        } else {
          // Sin m3u8 → se abre en extractor (WEBVIEW), igual que móvil
          s['verificado'] = s['verificado'] == true;
        }

        // Evitar duplicados por URL
        final url = s['servidor_url']?.toString() ?? '';
        final already = _servers.any(
          (x) => (x['servidor_url']?.toString() ?? '') == url && url.isNotEmpty,
        );
        if (already) return;

        setState(() {
          _servers.add(s);
          _rebuildFlatList();
        });
        _resyncCardFocus();
      }

      if (event.isDone) {
        setState(() => _loading = false);
        _saveCache();
        debugPrint(
          '[ServidoresFuentesTv] done → ${_servers.length} servidores '
          '(player=$_playersCount web=$_webviewsCount)',
        );
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    });
  }

  Future<void> _reload() async {
    await _clearCache();
    _start(force: true);
  }

  void _openServer(Map<String, dynamic> s) {
    if (_navigating) return;
    final embedUrl = s['servidor_url']?.toString() ?? '';
    final resuelto = s['resolved_m3u8']?.toString() ?? '';
    final verificado = s['verificado'] == true;
    final nombre = s['servidor_nombre']?.toString() ?? 'Servidor';
    final idioma = s['idioma']?.toString();
    final esPlayer = verificado && resuelto.isNotEmpty;

    // Directo m3u8/mp4 en la URL del embed
    final lower = embedUrl.toLowerCase();
    final esDirectoUrl =
        lower.contains('.m3u8') || lower.contains('.mp4');

    if (embedUrl.isEmpty && resuelto.isEmpty) return;
    _navigating = true;

    if (esPlayer) {
      _goToPlayer(videoUrl: resuelto, idioma: idioma);
      return;
    }
    if (esDirectoUrl) {
      _goToPlayer(videoUrl: embedUrl, idioma: idioma);
      return;
    }

    _goToExtractor(
      servidorUrl: embedUrl,
      servidorNombre: nombre,
      idioma: idioma,
    );
  }

  void _goToPlayer({required String videoUrl, String? idioma}) {
    final route = MaterialPageRoute(
      builder: (_) => PlayerScreen(
        videoUrl: videoUrl,
        idcontenido: _resolvedId,
        tmdbId: _resolvedId,
        temporada: _isMovie ? null : widget.temporada,
        capitulo: _isMovie ? null : widget.capitulo,
        tipo: _isMovie ? 'movie' : 'tv',
        titulo: _tituloFinal,
        idioma: idioma,
        fuente: _fuente,
      ),
    );

    final nav = Navigator.of(context);
    if (widget.fromPlayer) {
      nav.pop();
      nav.pushReplacement(route);
    } else {
      nav.pushReplacement(route);
    }
  }

  void _goToExtractor({
    required String servidorUrl,
    required String servidorNombre,
    String? idioma,
  }) {
    // ExtractorPage NO tiene parámetro `fuente` en tu proyecto
    final route = MaterialPageRoute(
      builder: (_) => ExtractorPage(
        idcontenido: _resolvedId,
        tmdbId: _resolvedId,
        temporada: _isMovie ? null : widget.temporada,
        capitulo: _isMovie ? null : widget.capitulo,
        servidorUrl: servidorUrl,
        servidorNombre: servidorNombre,
        tipo: _isMovie ? 'movie' : 'tv',
        titulo: _tituloFinal,
        idioma: idioma,
      ),
    );

    final nav = Navigator.of(context);
    if (widget.fromPlayer) {
      nav.pop();
      nav.pushReplacement(route);
    } else {
      nav.pushReplacement(route);
    }
  }

  String _normalizeIdioma(String? code) {
    if (code == null || code.isEmpty) return 'es_MX';
    final c = code.toLowerCase().trim();
    if (c.contains('es_es') || c == 'esp' || c == 'castellano') return 'es_ES';
    if (c.contains('es_mx') ||
        c.contains('es_la') ||
        c == 'lat' ||
        c == 'latino' ||
        c == 'es') {
      return 'es_MX';
    }
    if (c.startsWith('ja') || c == 'jap') return 'ja_JP';
    if (c.startsWith('en') || c.contains('sub')) return 'en_US';
    if (c.startsWith('pt')) return 'pt_BR';
    if (c.startsWith('fr')) return 'fr_FR';
    return c;
  }

  String _idiomaLabel(String code) {
    try {
      return MainFuentesServidores.idiomaLabel(code);
    } catch (_) {
      switch (code) {
        case 'es_MX':
          return 'Latino';
        case 'es_ES':
          return 'Castellano';
        case 'en_US':
          return 'Subtitulado';
        case 'ja_JP':
          return 'Japonés';
        default:
          return code;
      }
    }
  }

  String? _flagUrl(String? code) {
    if (code == null || code.isEmpty) return null;
    final c = code.toLowerCase().trim();
    if (c == 'es_es' || c == 'es-es' || c == 'esp' || c == 'castellano') {
      return 'https://embed69.org/static/lang/ESP.png';
    }
    if (c == 'es_mx' ||
        c == 'es-mx' ||
        c == 'es_la' ||
        c == 'es-la' ||
        c == 'lat' ||
        c == 'latino' ||
        c == 'es') {
      return 'https://embed69.org/static/lang/LAT.png';
    }
    if (c.startsWith('ja') || c == 'jap') {
      return 'https://embed69.org/static/lang/JAP.png';
    }
    return 'https://embed69.org/static/lang/SUB.png';
  }

  /// Círculo perfecto: ClipOval + tamaño fijo (evita óvalo de PNGs rectangulares)
  Widget _langFlag(String code, {double size = 44}) {
    final url = _flagUrl(code);
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: Colors.white.withValues(alpha: 0.08),
          child: url == null
              ? Icon(Icons.language, size: size * 0.4, color: Colors.white54)
              : CachedNetworkImage(
                  imageUrl: url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  memCacheWidth: (size * 3).round(),
                  memCacheHeight: (size * 3).round(),
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, __, ___) => Center(
                    child: Text(
                      _idiomaLabel(code).isNotEmpty
                          ? _idiomaLabel(code).characters.first
                          : '?',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: size * 0.32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _go(FocusNode node) {
    if (!node.canRequestFocus) return;
    node.requestFocus();
  }

  void _ensureCardVisible(int index) {
    if (!_listScroll.hasClients) return;
    final target = (index * _kItemExtent) - 8;
    final max = _listScroll.position.maxScrollExtent;
    _listScroll.jumpTo(target.clamp(0.0, max));
  }

  void _focusFirstCard() {
    if (_cardFocus.isEmpty) return;
    _lastCardIndex = 0;
    _cardFocus.first.requestFocus();
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
  }

  KeyEventResult _onCloseKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(_reloadFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_cardFocus.isNotEmpty) _focusFirstCard();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onReloadKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(_closeFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_cardFocus.isNotEmpty) _focusFirstCard();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (!_loading) _reload();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onCardKey(int index, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_cardFocus.length < _flatList.length) {
      _resyncCardFocus();
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        final prev = index - 1;
        _lastCardIndex = prev;
        _go(_cardFocus[prev]);
        _ensureCardVisible(prev);
      } else {
        _go(_closeFocus);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      final next = index + 1;
      if (next < _flatList.length) {
        while (_cardFocus.length <= next) {
          _cardFocus.add(FocusNode());
        }
        _lastCardIndex = next;
        _go(_cardFocus[next]);
        _ensureCardVisible(next);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(_closeFocus);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (index < _flatList.length) _openServer(_flatList[index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelW = (size.width * 0.58).clamp(400.0, 880.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_backdrop != null && _backdrop!.isNotEmpty)
            RepaintBoundary(
              child: CachedNetworkImage(
                imageUrl: _backdrop!,
                fit: BoxFit.cover,
                memCacheWidth: (size.width * 0.9).round().clamp(400, 1280),
                fadeInDuration: Duration.zero,
                errorWidget: (_, __, ___) => const ColoredBox(color: _kBg),
              ),
            )
          else
            const ColoredBox(color: _kBg),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black26,
                  Colors.black45,
                  Color(0x99000000),
                ],
                stops: [0.0, 0.35, 0.58],
              ),
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                // Info izquierda (más transparente / limpia)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 32, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(flex: 2),
                        SizedBox(
                          height: 80,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: (_logo != null && _logo!.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: _logo!,
                                    height: 72,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                    memCacheHeight: 144,
                                    fadeInDuration: Duration.zero,
                                    placeholder: (_, __) => _titleText(),
                                    errorWidget: (_, __, ___) => _titleText(),
                                  )
                                : _titleText(),
                          ),
                        ),
                        if (_seasonEp != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _seasonEp!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _metaChip(
                              '${_servers.length} servidor${_servers.length == 1 ? '' : 'es'}',
                            ),
                            if (_fuente.isNotEmpty)
                              _metaChip(_fuente, accent: true),
                            if (_fromCache) _metaChip('Caché'),
                            if (!_loading && _servers.isNotEmpty)
                              _metaChip(
                                '$_playersCount player · $_webviewsCount web',
                              ),
                            if (_loading)
                              _metaChip('Buscando…', accent: true),
                          ],
                        ),
                        const Spacer(flex: 3),
                      ],
                    ),
                  ),
                ),
                // Panel derecha (sin botón de configuración)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                      child: Container(
                        width: panelW,
                        decoration: BoxDecoration(
                          color: _kPanel,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildTopBar(),
                            Expanded(child: _buildBody()),
                          ],
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
      _tituloFinal,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        height: 1.12,
      ),
    );
  }

  Widget _metaChip(String label, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent
            ? _kOrange.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? _kOrange : Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Row(
        children: [
          _tvIconButton(
            focusNode: _closeFocus,
            icon: Icons.close_rounded,
            onKey: _onCloseKey,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Text(
            'Servidores',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_fuente.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _fuente,
                style: const TextStyle(
                  color: _kOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kOrange,
                ),
              ),
            ),
          // Solo reload a la derecha (sin config)
          _tvIconButton(
            focusNode: _reloadFocus,
            icon: Icons.refresh_rounded,
            enabled: !_loading,
            onKey: _onReloadKey,
            onTap: _loading ? null : _reload,
          ),
        ],
      ),
    );
  }

  Widget _tvIconButton({
    required FocusNode focusNode,
    required IconData icon,
    required KeyEventResult Function(FocusNode, KeyEvent) onKey,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKey,
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: hasFocus
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2.2,
                ),
              ),
              child: Icon(
                icon,
                color: enabled
                    ? (hasFocus ? Colors.white : Colors.white70)
                    : Colors.white24,
                size: 24,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _servers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                color: _kOrange,
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Buscando servidores…',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (_error != null && _servers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _kAccent, size: 42),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded, color: _kOrange),
                label: const Text('Reintentar', style: TextStyle(color: _kOrange)),
              ),
            ],
          ),
        ),
      );
    }

    if (_servers.isEmpty && !_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No se encontraron servidores',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, color: _kOrange),
              label: const Text('Recargar', style: TextStyle(color: _kOrange)),
            ),
          ],
        ),
      );
    }

    final byLang = <String, List<Map<String, dynamic>>>{};
    for (final s in _servers) {
      final lang = _normalizeIdioma(s['idioma']?.toString());
      byLang.putIfAbsent(lang, () => []).add(s);
    }
    final langKeys = byLang.keys.toList()
      ..sort((a, b) {
        const order = ['es_MX', 'es_ES', 'en_US', 'ja_JP'];
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    _rebuildFlatList();
    if (_cardFocus.length != _flatList.length) {
      _resyncCardFocus();
    }

    final children = <Widget>[];
    var flatIndex = 0;

    for (final lang in langKeys) {
      final servers = byLang[lang]!;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Row(
            children: [
              _langFlag(lang, size: 22),
              const SizedBox(width: 10),
              Text(
                _idiomaLabel(lang),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${servers.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      for (final s in servers) {
        final i = flatIndex;
        flatIndex++;
        children.add(_serverCard(s, i));
      }
    }

    return ListView(
      controller: _listScroll,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      children: children,
    );
  }

  Widget _serverCard(Map<String, dynamic> s, int index) {
    final nombre = s['servidor_nombre']?.toString() ?? 'Servidor';
    final calidad = s['calidad']?.toString() ?? 'HD';
    final idioma = _normalizeIdioma(s['idioma']?.toString());
    final verificado = s['verificado'] == true;
    final resuelto = s['resolved_m3u8']?.toString();
    final esPlayer = verificado && resuelto != null && resuelto.isNotEmpty;
    final url = s['servidor_url']?.toString() ?? '';
    final isCurrent =
        widget.currentServidorUrl != null && widget.currentServidorUrl == url;

    while (_cardFocus.length <= index) {
      _cardFocus.add(FocusNode());
    }
    final focusNode = _cardFocus[index];

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (n, e) => _onCardKey(index, n, e),
      onFocusChange: (has) {
        if (has) {
          _lastCardIndex = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = focusNode.context;
            if (ctx != null) {
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 160),
                alignment: 0.35,
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => _openServer(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.only(bottom: 9),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: hasFocus
                    ? Colors.white.withValues(alpha: 0.18)
                    : (isCurrent
                        ? _kAccent.withValues(alpha: 0.22)
                        : _kCard),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : (esPlayer
                          ? const Color(0xFF22C55E).withValues(alpha: 0.45)
                          : (isCurrent
                              ? _kAccent.withValues(alpha: 0.8)
                              : Colors.white.withValues(alpha: 0.08))),
                  width: hasFocus || isCurrent ? 2.2 : 1,
                ),
              ),
              child: Row(
                children: [
                  _langFlag(idioma, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              _idiomaLabel(idioma),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '·',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                            Text(
                              calidad,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12.5,
                              ),
                            ),
                            if (esPlayer)
                              _badge(
                                'PLAYER',
                                const Color(0xFF22C55E),
                                Icons.play_circle_fill_rounded,
                              )
                            else
                              _badge(
                                'WEBVIEW',
                                const Color(0xFF3B82F6),
                                Icons.language_rounded,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.play_arrow_rounded,
                    color: esPlayer
                        ? const Color(0xFF22C55E)
                        : Colors.white.withValues(alpha: 0.35),
                    size: 28,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _badge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}