import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../content/presentation/content_page.dart';
import '../../player/presentation/player_page.dart';
// Ajusta la ruta del modal según donde lo hayas guardado
import '../../content/presentation/content_options_modal.dart'; // ← el modal móvil que hicimos

const _kAccentColor = Color(0xFFE50914);
const _kCardBg = Color(0xFF1a1a2e);

class GuardadosPage extends StatefulWidget {
  const GuardadosPage({super.key});

  @override
  State<GuardadosPage> createState() => GuardadosPageState();
}

class GuardadosPageState extends State<GuardadosPage>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _historial = [];
  List<Map<String, dynamic>> _guardados = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    GuardadosBus.version.addListener(_onExternalChange);
    _load();
  }

  void _onExternalChange() {
    if (!mounted) return;
    _load();
  }

  @override
  void dispose() {
    GuardadosBus.version.removeListener(_onExternalChange);
    super.dispose();
  }

  void refresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);

    final historial = await _loadHistorial();
    final guardados = await GuardadosCache.getAll();

    if (!mounted) return;

    setState(() {
      _historial = historial;
      _guardados = guardados;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _loadHistorial() async {
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
        final data = Map<String, dynamic>.from(jsonDecode(raw));
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
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1) CONTINUAR VIENDO → abre DIRECTAMENTE el Player
  // ─────────────────────────────────────────────────────────────────────────
  void _openHistorial(Map<String, dynamic> item) {
    final id = item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;

    final temporada = item['temporada'] as int?;
    final capitulo = item['capitulo'] as int?;
    final tipo = (item['tipo'] ?? 'movie').toString().toLowerCase();
    final titulo = item['titulo']?.toString() ?? '';
    final videoUrl = item['videoUrl']?.toString() ?? '';
    final idioma = item['idioma']?.toString();

    Navigator.of(context)
        .push(
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
        )
        .then((_) => _load());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2) MI LISTA → abre la ficha (PageContenido)
  // ─────────────────────────────────────────────────────────────────────────
  void _openGuardado(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ??
        item['idtmdb'] as int? ??
        item['idcontenido'] as int? ??
        0;

    final tipo = (item['tipo'] ?? item['type'] ?? item['media_type'] ?? 'movie')
        .toString()
        .toLowerCase();

    if (id <= 0) return;

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PageContenido(
              idcontenido: id,
              tmdbId: id,
              mediaType: tipo,
            ),
          ),
        )
        .then((_) => _load());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LONG PRESS → abre el modal de opciones nuevo
  // ─────────────────────────────────────────────────────────────────────────
  void _showOpcionesModal(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ??
        item['idtmdb'] as int? ??
        item['idcontenido'] as int? ??
        0;

    if (id <= 0) return;

    final tipo = (item['tipo'] ?? item['type'] ?? item['media_type'] ?? 'movie')
        .toString()
        .toLowerCase();

    final titulo = item['titulo']?.toString() ??
        item['title']?.toString() ??
        'Sin título';

    String poster = item['poster']?.toString() ??
        item['poster_path']?.toString() ??
        '';

    // Normalizar poster TMDB si viene relativo
    if (poster.isNotEmpty && !poster.startsWith('http')) {
      poster = 'https://image.tmdb.org/t/p/w500$poster';
    }

    String backdrop = item['backdrop']?.toString() ??
        item['backdrop_path']?.toString() ??
        '';

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
      // Recargar por si se quitó de la lista
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bottomPad = MediaQuery.paddingOf(context).bottom + 72;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _kAccentColor),
              )
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // ── Continuar viendo ────────────────────────────────────
                  if (_historial.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: _SectionHeader(
                        title: 'Continuar viendo',
                        icon: Icons.history_rounded,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 150,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          itemCount: _historial.length,
                          itemBuilder: (context, index) {
                            final item = _historial[index];
                            return _HistorialBanner(
                              title: item['titulo']?.toString() ?? 'Sin título',
                              image: (item['backdrop']?.toString().isNotEmpty == true)
                                  ? item['backdrop'].toString()
                                  : (item['poster']?.toString() ?? ''),
                              tipo: item['tipo']?.toString() ?? 'movie',
                              temporada: item['temporada'],
                              capitulo: item['capitulo'],
                              segundo: item['segundo'] as int? ?? 0,
                              onTap: () => _openHistorial(item),          // ← player directo
                              onLongPress: () => _showOpcionesModal(item), // ← modal opciones
                            );
                          },
                        ),
                      ),
                    ),
                  ],

                  // ── Mi lista ────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Mi lista',
                      icon: Icons.bookmark_rounded,
                      count: _guardados.length,
                    ),
                  ),

                  if (_guardados.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(0, 48, 0, bottomPad),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.bookmark_border_rounded,
                                size: 52,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Aún no has guardado nada',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 10,
                          childAspectRatio: 120 / 180,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = _guardados[index];
                            return _PosterCard(
                              item: item,
                              onTap: () => _openGuardado(item),
                              onLongPress: () => _showOpcionesModal(item), // ← long press
                            );
                          },
                          childCount: _guardados.length,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ─── Header de sección ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int? count;

  const _SectionHeader({required this.title, required this.icon, this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          Icon(icon, color: _kAccentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Banner de Continuar viendo ─────────────────────────────────────────────

class _HistorialBanner extends StatelessWidget {
  final String title;
  final String image;
  final String tipo;
  final dynamic temporada;
  final dynamic capitulo;
  final int segundo;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _HistorialBanner({
    required this.title,
    required this.image,
    required this.tipo,
    this.temporada,
    this.capitulo,
    required this.segundo,
    required this.onTap,
    this.onLongPress,
  });

  String get _timeLabel {
    final m = segundo ~/ 60;
    final s = segundo % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _meta {
    if (tipo == 'tv' && temporada != null && capitulo != null) {
      return 'T${temporada.toString().padLeft(2, '0')}E${capitulo.toString().padLeft(2, '0')}';
    }
    return tipo == 'tv' ? 'Serie' : 'Película';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              image.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: const Color(0xFF1a1a1a)),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF1a1a1a),
                        child: const Icon(
                          Icons.movie,
                          color: Colors.white24,
                          size: 36,
                        ),
                      ),
                    )
                  : Container(
                      color: const Color(0xFF1a1a1a),
                      child: const Icon(
                        Icons.movie,
                        color: Colors.white24,
                        size: 36,
                      ),
                    ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _meta,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  color: Colors.white.withValues(alpha: 0.2),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (segundo / 4200).clamp(0.06, 1.0),
                    child: Container(color: _kAccentColor),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    _timeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

// ─── Poster de Mi lista ─────────────────────────────────────────────────────

class _PosterCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PosterCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
  });

  static const double _w = 120;
  static const double _h = 180;

  String get _poster {
    final p = item['poster_path']?.toString() ?? '';
    if (p.isEmpty || p == 'null') return '';
    if (p.startsWith('http')) return p;
    return 'https://image.tmdb.org/t/p/w500$p';
  }

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
              color: _kCardBg,
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
                    width: double.infinity,
                    height: double.infinity,
                    memCacheWidth: (_w * dpr).round(),
                    memCacheHeight: (_h * dpr).round(),
                    fadeInDuration: const Duration(milliseconds: 100),
                    placeholder: (_, __) => const ColoredBox(color: _kCardBg),
                    errorWidget: (_, __, ___) => const ColoredBox(
                      color: _kCardBg,
                      child: Icon(Icons.movie, color: Colors.white24, size: 28),
                    ),
                  )
                : const ColoredBox(
                    color: _kCardBg,
                    child: Icon(Icons.movie, color: Colors.white24, size: 28),
                  ),
          ),
          // Rating
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _kAccentColor.withValues(alpha: 0.5),
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
          // Año
          if (_year.isNotEmpty)
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