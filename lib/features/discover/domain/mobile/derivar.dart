// lib/servicios/derivar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../data/models/scraper/detalle_model.dart';
import '../../../../data/scrapers/base/detalle_scraper.dart';
import 'servidores_modal.dart';
import '../../../content/presentation/content_page.dart'; // ← PageContenido

const kAccentColor = Color(0xFFE50914);
const kBgColor = Colors.black;
const kCardBg = Color(0xFF1a1a2e);
const kPurpleSeason = Color(0xFFC026FF);

class DerivarPage extends StatefulWidget {
  final String servicio;
  final String url;
  final String titulo;
  final String tipo;

  const DerivarPage({
    super.key,
    required this.servicio,
    required this.url,
    required this.titulo,
    required this.tipo,
  });

  @override
  State<DerivarPage> createState() => _DerivarPageState();
}

class _DerivarPageState extends State<DerivarPage> {
  bool _loading = true;
  String? _error;
  DetalleContenido? _data;
  int _selectedSeasonIndex = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _load();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await DetalleScraper.fetch(
      servicio: widget.servicio,
      url: widget.url,
      titulo: widget.titulo,
      tipo: widget.tipo,
    );

    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _error = res.error ?? 'Error al cargar';
        _loading = false;
      });
      return;
    }

    setState(() {
      _data = res;
      _loading = false;
      _selectedSeasonIndex = 0;
    });
  }

  bool get _isMovie {
    final t = (_data?.tipo ?? widget.tipo).toLowerCase();
    return t == 'movie' || t == 'pelicula' || t == 'película';
  }

  bool get _usaUrlCapitulo {
    final s = widget.servicio.trim().toLowerCase().replaceAll(' ', '');
    return s == 'animejk' ||
        s == 'jkanime' ||
        s == 'jk' ||
        (_data?.servicio.toLowerCase() == 'animejk');
  }

  /// ¿Hay TMDB ID válido para abrir PageContenido?
  bool get _canOpenContent {
    final id = _data?.tmdbId ?? 0;
    return id > 0;
  }

  List<DetalleTemporada> get _temporadas => _data?.temporadas ?? [];

  List<DetalleCapitulo> get _currentEpisodes {
    if (_temporadas.isEmpty) return [];
    final idx = _selectedSeasonIndex.clamp(0, _temporadas.length - 1);
    return _temporadas[idx].episodios;
  }

  void _openContent() {
    final id = _data?.tmdbId ?? 0;
    if (id <= 0) return;

    final tipo = (_data?.tipo ?? widget.tipo).toLowerCase();
    final mediaType = (tipo == 'tv' || tipo == 'serie' || tipo == 'series')
        ? 'tv'
        : 'movie';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PageContenido(
          idcontenido: id,
          tmdbId: id,
          mediaType: mediaType,
        ),
      ),
    );
  }

  void _openServersModal({DetalleCapitulo? cap}) {
    if (_usaUrlCapitulo) {
      final episodeUrl =
          (cap?.url.isNotEmpty == true) ? cap!.url : widget.url;
      if (episodeUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay URL para buscar servidores'),
            backgroundColor: kCardBg,
          ),
        );
        return;
      }
      ServidoresModal.show(
        context,
        tmdbId: _data?.tmdbId ?? 0,
        tipo: _data?.tipo ?? widget.tipo,
        fuente: widget.servicio,
        tituloContenido: _data?.titulo ?? widget.titulo,
        temporada: _isMovie ? null : (cap?.temporada ?? 1),
        capitulo: _isMovie ? null : (cap?.numero ?? 1),
      );
      return;
    }

    final tmdbId = _data?.tmdbId ?? 0;
    if (tmdbId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay TMDB ID para buscar servidores'),
          backgroundColor: kCardBg,
        ),
      );
      return;
    }

    ServidoresModal.show(
      context,
      tmdbId: tmdbId,
      tipo: _data?.tipo ?? widget.tipo,
      fuente: widget.servicio,
      tituloContenido: _data?.titulo ?? widget.titulo,
      temporada: _isMovie ? null : (cap?.temporada ?? 1),
      capitulo: _isMovie ? null : (cap?.numero ?? 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kBgColor,
        body: Center(
          child: CircularProgressIndicator(
            color: kAccentColor,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_error != null || _data == null) {
      return Scaffold(
        backgroundColor: kBgColor,
        appBar: AppBar(
          backgroundColor: kBgColor,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Error',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
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

    final data = _data!;
    final size = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final bgImage = (data.backdrop?.isNotEmpty == true)
        ? data.backdrop!
        : (data.poster ?? '');

    return Scaffold(
      backgroundColor: kBgColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: size.height * 0.62,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bgImage.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: bgImage,
                      fit: BoxFit.cover,
                      memCacheWidth:
                          (size.width * 1.2).round().clamp(400, 720),
                      placeholder: (_, __) =>
                          Container(color: Colors.black),
                      errorWidget: (_, __, ___) =>
                          Container(color: Colors.black),
                    )
                  else
                    Container(color: Colors.black),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.4),
                          Colors.black.withValues(alpha: 0.85),
                          Colors.black,
                        ],
                        stops: const [0.0, 0.35, 0.7, 1.0],
                      ),
                    ),
                  ),

                  // ── Botones superiores (atrás + abrir ficha) ────────────
                  Positioned(
                    top: topPad + 4,
                    left: 8,
                    right: 8,
                    child: Row(
                      children: [
                        // Atrás
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.45),
                          ),
                        ),
                        const Spacer(),
                        // Abrir en PageContenido (solo si hay tmdbId)
                        if (_canOpenContent)
                          IconButton(
                            tooltip: 'Ver ficha completa',
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              color: Colors.white,
                            ),
                            onPressed: _openContent,
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Colors.black.withValues(alpha: 0.45),
                            ),
                          ),
                      ],
                    ),
                  ),

                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 28,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (data.logo != null && data.logo!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: data.logo!,
                            height: 64,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) =>
                                _titleText(data.titulo),
                          )
                        else
                          _titleText(data.titulo),
                        const SizedBox(height: 10),
                        if (data.generos.isNotEmpty)
                          Text(
                            data.generos.take(4).join('  •  '),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: () {
                            if (_isMovie) {
                              _openServersModal();
                            } else if (_currentEpisodes.isNotEmpty) {
                              _openServersModal(cap: _currentEpisodes.first);
                            } else {
                              _openServersModal();
                            }
                          },
                          child: Container(
                            width: 200,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 28,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Ver ahora',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (data.anio != null)
                              Text(
                                data.anio!,
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                              ),
                            if (data.rating != null && data.rating! > 0) ...[
                              Text(
                                '  •  ',
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                              const Icon(
                                Icons.star_rounded,
                                color: Colors.amber,
                                size: 16,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                data.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            Text(
                              '  •  ${data.servicio.isNotEmpty ? data.servicio : widget.servicio}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
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

          // ── Contenido ───────────────────────────────────────────────────
          // Extra (status, studios…) si viene de AnimeJK
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data.extra != null) ...[
                    _buildExtraChips(data.extra!),
                    const SizedBox(height: 16),
                  ],
                  if (data.sinopsis != null && data.sinopsis!.isNotEmpty) ...[
                    const Text(
                      'Sinopsis',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.sinopsis!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                  if (!_isMovie && _temporadas.isNotEmpty) ...[
                    const Text(
                      'Temporadas y Episodios',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _temporadas.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final t = _temporadas[i];
                          final selected = i == _selectedSeasonIndex;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedSeasonIndex = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? kPurpleSeason
                                    : const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                t.nombre,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._currentEpisodes.map((ep) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openServersModal(cap: ep),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  if (ep.imagen != null &&
                                      ep.imagen!.isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: CachedNetworkImage(
                                        imageUrl: ep.imagen!,
                                        width: 100,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            Container(
                                          width: 100,
                                          height: 56,
                                          color: const Color(0xFF2C2C2E),
                                          child: const Icon(
                                            Icons.movie,
                                            color: Colors.white24,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 100,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2C2C2E),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'E${ep.numero}',
                                          style: const TextStyle(
                                            color: kAccentColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'E${ep.numero.toString().padLeft(2, '0')} · ${ep.titulo}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (ep.airDate != null)
                                          Text(
                                            ep.airDate!,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.45),
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.white54,
                                    size: 28,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraChips(Map<String, dynamic> extra) {
    final chips = <String>[];
    void add(String? v) {
      if (v != null && v.toString().trim().isNotEmpty) {
        chips.add(v.toString().trim());
      }
    }

    add(extra['status']?.toString());
    add(extra['episodes_count']?.toString().isNotEmpty == true
        ? '${extra['episodes_count']} eps'
        : null);
    add(extra['duration']?.toString());
    add(extra['quality']?.toString());
    add(extra['season']?.toString());

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips
          .map(
            (c) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                c,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _titleText(String title) {
    return Text(
      title,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}