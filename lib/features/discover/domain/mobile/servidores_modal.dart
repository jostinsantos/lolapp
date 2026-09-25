import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../data/aggregators/main_fuentes_servidores.dart';
import 'extractor.dart';
import 'player_screen.dart';
const kAccentColor = Color(0xFFE50914);
const kOrange = Color(0xFFFF6B00);
const kCardBg = Color(0xFF1C1C1E);
const kBg = Color(0xFF0A0A0A);
const kSurface = Color(0xFF141416);
const kBorder = Color(0xFF2A2A2E);

class ServidoresModal extends StatefulWidget {
  final int tmdbId;
  final int? idcontenido;
  final String tipo;
  final int? temporada;
  final int? capitulo;
  final String fuente;
  final String tituloContenido;
  final String? titulo;
  final String? tituloOverride;
  final String? backdropUrl;
  final String? logoUrl;
  final bool fromPlayer;
  final bool esSiguienteCapitulo;

  const ServidoresModal({
    super.key,
    required this.tmdbId,
    this.idcontenido,
    required this.tipo,
    this.fuente = '',
    String? tituloContenido,
    this.titulo,
    this.temporada,
    this.capitulo,
    this.tituloOverride,
    this.backdropUrl,
    this.logoUrl,
    this.fromPlayer = false,
    this.esSiguienteCapitulo = false,
  }) : tituloContenido = tituloContenido ?? titulo ?? '';

  static Future<void> show(
    BuildContext context, {
    required int tmdbId,
    int? idcontenido,
    required String tipo,
    String fuente = '',
    String? tituloContenido,
    String? titulo,
    int? temporada,
    int? capitulo,
    String? tituloOverride,
    String? backdropUrl,
    String? logoUrl,
    bool fromPlayer = false,
    bool esSiguienteCapitulo = false,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (_) => ServidoresModal(
        tmdbId: tmdbId,
        idcontenido: idcontenido ?? tmdbId,
        tipo: tipo,
        fuente: fuente,
        tituloContenido: tituloContenido,
        titulo: titulo,
        temporada: temporada,
        capitulo: capitulo,
        tituloOverride: tituloOverride,
        backdropUrl: backdropUrl,
        logoUrl: logoUrl,
        fromPlayer: fromPlayer,
        esSiguienteCapitulo: esSiguienteCapitulo,
      ),
    );
  }

  @override
  State<ServidoresModal> createState() => _ServidoresModalState();
}

class _ServidoresModalState extends State<ServidoresModal> {
  final List<Map<String, dynamic>> _servers = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;
  String? _headerBackdrop;
  String? _headerLogo;
  String _headerTitle = '';
  bool _fromCache = false;

  int get _resolvedId =>
      widget.tmdbId > 0 ? widget.tmdbId : (widget.idcontenido ?? 0);

  bool get _isMovie {
    final t = widget.tipo.toLowerCase();
    return t == 'movie' || t == 'pelicula' || t == 'película';
  }

  String get _fuente => widget.fuente.trim();

  String get _cacheKey {
    final s = widget.temporada ?? 0;
    final e = widget.capitulo ?? 0;
    return 'servidores_cache_${_resolvedId}_${widget.tipo}_${_fuente}_T${s}_C$e';
  }

  String get _tituloHeader {
    if (widget.tituloOverride != null && widget.tituloOverride!.isNotEmpty) {
      return widget.tituloOverride!;
    }
    if (_headerTitle.isNotEmpty) return _headerTitle;
    if (_isMovie || widget.temporada == null || widget.capitulo == null) {
      return widget.tituloContenido.isNotEmpty
          ? widget.tituloContenido
          : 'Servidores';
    }
    final s = widget.temporada!.toString().padLeft(2, '0');
    final e = widget.capitulo!.toString().padLeft(2, '0');
    return 'S${s}E$e';
  }

  String? get _seasonEp {
    if (_isMovie || widget.temporada == null) return null;
    final s = widget.temporada!.toString().padLeft(2, '0');
    final e = (widget.capitulo ?? 1).toString().padLeft(2, '0');
    return 'T$s · E$e';
  }

  String get _tituloFinal => widget.tituloContenido.isNotEmpty
      ? widget.tituloContenido
      : _headerTitle;

  @override
  void initState() {
    super.initState();
    _headerBackdrop = widget.backdropUrl;
    _headerLogo = widget.logoUrl;
    _headerTitle = widget.tituloContenido;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_fuente.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Fuente no soportada. Pasa la fuente desde Derivar → Modal → Extractor → Player.';
        });
      }
      return;
    }
    final cached = await _loadCache();
    if (cached != null && cached.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _servers
          ..clear()
          ..addAll(cached);
        _loading = false;
        _fromCache = true;
        _error = null;
      });
      return;
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

  void _start({bool force = false}) {
    if (_fuente.isEmpty) {
      setState(() {
        _loading = false;
        _error =
            'Fuente no soportada. Pasa la fuente desde Derivar → Modal → Extractor → Player.';
      });
      return;
    }

    _sub?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
      if (force) _servers.clear();
    });

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
        final resuelto = event.resolvedM3u8 ?? s['resolved_m3u8']?.toString();
        if (resuelto != null && resuelto.isNotEmpty) {
          s['resolved_m3u8'] = resuelto;
          s['verificado'] = true;
        }
        setState(() => _servers.add(s));
      }

      if (event.isDone) {
        setState(() => _loading = false);
        _saveCache();
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

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _openServer(Map<String, dynamic> s) {
    final embedUrl = s['servidor_url']?.toString() ?? '';
    final resuelto = s['resolved_m3u8']?.toString() ?? '';
    final verificado = s['verificado'] == true;
    final nombre = s['servidor_nombre']?.toString() ?? 'Servidor';
    final idioma = s['idioma']?.toString();
    final esPlayer = verificado && resuelto.isNotEmpty;

    if (embedUrl.isEmpty && resuelto.isEmpty) return;

    Navigator.of(context).pop();

    if (esPlayer) {
      _goToPlayer(videoUrl: resuelto, idioma: idioma);
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

    if (widget.fromPlayer) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  void _goToExtractor({
    required String servidorUrl,
    required String servidorNombre,
    String? idioma,
  }) {
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
        fuente: _fuente,
      ),
    );

    if (widget.fromPlayer) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
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
    if (c.startsWith('en')) return 'en_US';
    if (c.startsWith('pt')) return 'pt_BR';
    if (c.startsWith('fr')) return 'fr_FR';
    return c;
  }

  String _idiomaLabel(String code) {
    try {
      return MainFuentesServidores.idiomaLabel(code);
    } catch (_) {
      return code;
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

  Widget _langFlag(String code, {double size = 42}) {
    final url = _flagUrl(code);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? ColoredBox(
              color: Colors.white.withValues(alpha: 0.08),
              child: const Icon(Icons.language, size: 16, color: Colors.white54),
            )
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: (size * 2).round(),
              memCacheHeight: (size * 2).round(),
              errorWidget: (_, __, ___) => ColoredBox(
                color: Colors.white.withValues(alpha: 0.08),
                child: Center(
                  child: Text(
                    _idiomaLabel(code).isNotEmpty
                        ? _idiomaLabel(code).substring(0, 1)
                        : '?',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isPortrait = size.height > size.width;
    final maxH = isPortrait ? size.height * 0.92 : size.height * 0.88;
    final hasBackdrop =
        _headerBackdrop != null && _headerBackdrop!.isNotEmpty;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(hasBackdrop, isPortrait),
            if (_loading && _servers.isEmpty)
              Expanded(child: _LoadingBody(isPortrait: isPortrait))
            else if (_error != null && _servers.isEmpty)
              Expanded(child: _ErrorBody(error: _error!, onRetry: _reload))
            else if (_servers.isEmpty && !_loading)
              Expanded(child: _EmptyBody(onReload: _reload))
            else
              Expanded(child: _buildList(isPortrait)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool hasBackdrop, bool isPortrait) {
    final players = _servers
        .where((s) =>
            s['verificado'] == true &&
            (s['resolved_m3u8']?.toString().isNotEmpty ?? false))
        .length;
    final webviews = _servers.length - players;
    final headerH = isPortrait ? 168.0 : 150.0;

    return SizedBox(
      height: headerH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasBackdrop)
            CachedNetworkImage(
              imageUrl: _headerBackdrop!,
              fit: BoxFit.cover,
              memCacheWidth: 1000,
              errorWidget: (_, __, ___) => const ColoredBox(color: kBg),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1208), Color(0xFF0A0A0A)],
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.78),
                  kBg,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, isPortrait ? 10 : 8, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: isPortrait ? 40 : 44,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: (_headerLogo != null && _headerLogo!.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: _headerLogo!,
                                  height: isPortrait ? 36 : 42,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.centerLeft,
                                  memCacheHeight: 88,
                                  errorWidget: (_, __, ___) =>
                                      _titleFallback(isPortrait),
                                )
                              : _titleFallback(isPortrait),
                        ),
                      ),
                    ),
                    _iconBtn(Icons.refresh_rounded, onTap: _loading ? null : _reload),
                    const SizedBox(width: 4),
                    _iconBtn(Icons.close_rounded, onTap: () => Navigator.pop(context)),
                  ],
                ),
                if (_seasonEp != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _seasonEp!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('${_servers.length} servidor${_servers.length == 1 ? '' : 'es'}',
                          icon: Icons.dns_rounded),
                      const SizedBox(width: 6),
                      if (_fuente.isNotEmpty) ...[
                        _chip(_fuente, color: kOrange, icon: Icons.source_rounded),
                        const SizedBox(width: 6),
                      ],
                      if (_fromCache) ...[
                        _chip('Caché', color: const Color(0xFF22C55E), icon: Icons.bolt_rounded),
                        const SizedBox(width: 6),
                      ],
                      if (widget.fromPlayer) ...[
                        _chip(widget.esSiguienteCapitulo ? 'Siguiente' : 'Player', color: kOrange),
                        const SizedBox(width: 6),
                      ],
                      if (_loading)
                        _chip('Buscando…', color: kOrange, icon: Icons.sync)
                      else if (_servers.isNotEmpty)
                        _chip('$players player · $webviews web'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, {VoidCallback? onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.white38 : Colors.white),
        ),
      ),
    );
  }

  Widget _titleFallback(bool isPortrait) {
    return Text(
      _tituloHeader,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: isPortrait ? 17 : 20,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
    );
  }

  Widget _chip(String text, {Color? color, IconData? icon}) {
    final c = color ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.22), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: c.withValues(alpha: 0.95),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool isPortrait) {
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

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(isPortrait ? 12 : 14, 4, isPortrait ? 12 : 14, 28),
      itemCount: langKeys.length,
      itemBuilder: (_, i) {
        final lang = langKeys[i];
        final servers = byLang[lang]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
              child: Row(
                children: [
                  _langFlag(lang, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _idiomaLabel(lang),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${servers.length}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...servers.map((s) => _serverTile(s, isPortrait)),
          ],
        );
      },
    );
  }

  Widget _serverTile(Map<String, dynamic> s, bool isPortrait) {
    final nombre = s['servidor_nombre']?.toString() ?? 'Servidor';
    final calidad = s['calidad']?.toString() ?? 'HD';
    final idioma = _normalizeIdioma(s['idioma']?.toString());
    final verificado = s['verificado'] == true;
    final resuelto = s['resolved_m3u8']?.toString();
    final esPlayer = verificado && resuelto != null && resuelto.isNotEmpty;
    final flagSize = isPortrait ? 40.0 : 44.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openServer(s),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: esPlayer
                    ? const Color(0xFF22C55E).withValues(alpha: 0.35)
                    : kBorder,
                width: 1,
              ),
            ),
            padding: EdgeInsets.fromLTRB(isPortrait ? 10 : 12, 11, isPortrait ? 8 : 10, 11),
            child: Row(
              children: [
                _langFlag(idioma, size: flagSize),
                SizedBox(width: isPortrait ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isPortrait ? 14 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            _idiomaLabel(idioma),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text('·', style: TextStyle(color: Colors.white.withValues(alpha: 0.25))),
                          Text(
                            calidad,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11.5,
                            ),
                          ),
                          if (esPlayer)
                            _badge('PLAYER', const Color(0xFF22C55E), Icons.play_circle_fill_rounded)
                          else
                            _badge('WEBVIEW', const Color(0xFF3B82F6), Icons.language_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.play_arrow_rounded,
                  color: esPlayer ? const Color(0xFF22C55E) : Colors.white.withValues(alpha: 0.35),
                  size: 26,
                ),
              ],
            ),
          ),
        ),
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
          Icon(icon, size: 11, color: color),
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

class _LoadingBody extends StatelessWidget {
  final bool isPortrait;
  const _LoadingBody({this.isPortrait = true});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(color: kOrange, strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            'Buscando servidores…',
            style: TextStyle(color: Colors.white70, fontSize: isPortrait ? 14 : 15),
          ),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  final VoidCallback onReload;
  const _EmptyBody({required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(height: 14),
            const Text('No se encontraron servidores', style: TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Recargar'),
              style: TextButton.styleFrom(foregroundColor: kOrange),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: kAccentColor, size: 48),
            const SizedBox(height: 14),
            Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(backgroundColor: kAccentColor, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}