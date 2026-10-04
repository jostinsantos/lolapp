import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/ai/ai_client.dart';
import '../../../data/recommendations/daily_sections_generator.dart';
import '../../../data/recommendations/regional_top10.dart';
import '../../content/presentation/content_page.dart' as mobile;
import '../../content/presentation/tv_content_page.dart' as tv;
import 'taste_onboarding_page.dart';

/// Home IA: Top 10 + secciones personalizadas.
/// Móvil: pósters. TV: backdrops (mismo estilo que el resto del home TV).
class ForYouSection extends StatefulWidget {
  final bool isTv;
  const ForYouSection({super.key, this.isTv = false});

  @override
  State<ForYouSection> createState() => _ForYouSectionState();
}

class _ForYouSectionState extends State<ForYouSection> {
  late final DailySectionsGenerator _sectionsGen;
  late final RegionalTop10Service _top10;

  List<HomeSection> _sections = [];
  List<Top10Item> _topMovies = [];
  List<Top10Item> _topSeries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sectionsGen = DailySectionsGenerator(ai: AiClient());
    _top10 = RegionalTop10Service(ai: AiClient());
    HomeAlgorithmBus.version.addListener(_onAlgoBump);
    _load();
  }

  void _onAlgoBump() => _load();

  @override
  void dispose() {
    HomeAlgorithmBus.version.removeListener(_onAlgoBump);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cachedSections = await _sectionsGen.loadCached();
    final tops = await _top10.load();
    if (mounted) {
      setState(() {
        _sections = cachedSections;
        _topMovies = tops.$1;
        _topSeries = tops.$2;
        _loading = false;
      });
    }
    final fresh = await _sectionsGen.getSections();
    final tops2 = await _top10.load();
    if (mounted) {
      setState(() {
        _sections = fresh;
        _topMovies = tops2.$1;
        _topSeries = tops2.$2;
      });
    }
  }

  void _open({required int id, required String tipo}) {
    if (widget.isTv) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => tv.PageContenido(
            idcontenido: id,
            tmdbId: id,
            mediaType: tipo,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => mobile.PageContenido(
            idcontenido: id,
            tmdbId: id,
            mediaType: tipo,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading &&
        _sections.isEmpty &&
        _topMovies.isEmpty &&
        _topSeries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.purpleAccent,
            ),
          ),
        ),
      );
    }

    if (widget.isTv) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_topMovies.isNotEmpty)
            _tvRow(
              title: 'Top 10 películas hoy',
              items: [
                for (final e in _topMovies)
                  _TvCard(
                    id: e.tmdbId,
                    tipo: e.tipo,
                    titulo: e.titulo,
                    image: e.backdropUrl ?? e.posterUrl,
                  ),
              ],
            ),
          if (_topSeries.isNotEmpty)
            _tvRow(
              title: 'Top 10 series hoy',
              items: [
                for (final e in _topSeries)
                  _TvCard(
                    id: e.tmdbId,
                    tipo: e.tipo,
                    titulo: e.titulo,
                    image: e.backdropUrl ?? e.posterUrl,
                  ),
              ],
            ),
          for (final sec in _sections)
            if (sec.items.isNotEmpty)
              _tvRow(
                title: sec.title,
                items: [
                  for (final e in sec.items)
                    _TvCard(
                      id: e.tmdbId,
                      tipo: e.tipo,
                      titulo: e.titulo,
                      image: e.backdropUrl ?? e.posterUrl,
                      subtitle: e.porque,
                    ),
                ],
              ),
        ],
      );
    }

    // ── Móvil: pósters ──
    const cardW = 120.0;
    const cardH = 180.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_topMovies.isNotEmpty)
          _mobilePosterRow(
            title: 'Top 10 películas hoy',
            items: _topMovies
                .map((e) => (
                      e.tmdbId,
                      e.tipo,
                      e.titulo,
                      e.posterUrl,
                      null as String?,
                    ))
                .toList(),
            cardW: cardW,
            cardH: cardH,
            numbered: true,
          ),
        if (_topSeries.isNotEmpty)
          _mobilePosterRow(
            title: 'Top 10 series hoy',
            items: _topSeries
                .map((e) => (
                      e.tmdbId,
                      e.tipo,
                      e.titulo,
                      e.posterUrl,
                      null as String?,
                    ))
                .toList(),
            cardW: cardW,
            cardH: cardH,
            numbered: true,
          ),
        for (final sec in _sections)
          if (sec.items.isNotEmpty)
            _mobilePosterRow(
              title: sec.title,
              items: sec.items
                  .map((e) => (
                        e.tmdbId,
                        e.tipo,
                        e.titulo,
                        e.posterUrl,
                        e.porque,
                      ))
                  .toList(),
              cardW: cardW,
              cardH: cardH,
              numbered: false,
            ),
      ],
    );
  }

  /// Fila TV: tarjetas horizontales 210×118 (mismo ratio que home TV).
  Widget _tvRow({required String title, required List<_TvCard> items}) {
    const cardW = 210.0;
    const cardH = 118.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 12, 16, 10),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: cardH + 8,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 48),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final item = items[i];
                return GestureDetector(
                  onTap: () => _open(id: item.id, tipo: item.tipo),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: cardW,
                      height: cardH,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (item.image != null)
                            CachedNetworkImage(
                              imageUrl: item.image!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  const ColoredBox(color: Color(0xFF1a1a2e)),
                              errorWidget: (_, __, ___) =>
                                  const ColoredBox(color: Color(0xFF1a1a2e)),
                            )
                          else
                            const ColoredBox(color: Color(0xFF1a1a2e)),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0xCC000000),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 8,
                            child: Text(
                              item.titulo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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

  Widget _mobilePosterRow({
    required String title,
    required List<(int, String, String, String?, String?)> items,
    required double cardW,
    required double cardH,
    required bool numbered,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: cardH + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final (id, tipo, titulo, poster, porque) = items[i];
              return GestureDetector(
                onTap: () => _open(id: id, tipo: tipo),
                child: SizedBox(
                  width: numbered ? cardW + 12 : cardW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: poster != null
                            ? CachedNetworkImage(
                                imageUrl: poster,
                                width: cardW,
                                height: cardH,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: cardW,
                                height: cardH,
                                color: const Color(0xFF1a1a2e),
                              ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        numbered ? '${i + 1}. $titulo' : titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (porque != null && porque.isNotEmpty)
                        Text(
                          porque,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TvCard {
  final int id;
  final String tipo;
  final String titulo;
  final String? image;
  final String? subtitle;
  const _TvCard({
    required this.id,
    required this.tipo,
    required this.titulo,
    this.image,
    this.subtitle,
  });
}
