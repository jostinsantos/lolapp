import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../../../data/ai/ai_client.dart';
import '../../../data/ai/daily_ai_gate.dart';
import '../../../data/recommendations/user_taste_profile.dart';
import '../../../data/recommendations/daily_sections_generator.dart';
import '../../../data/recommendations/regional_top10.dart';

/// Notifica al home que el algoritmo/secciones cambiaron.
class HomeAlgorithmBus {
  HomeAlgorithmBus._();
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static void bump() => version.value++;
}

/// Primera apertura: galería infinita de pósters. El usuario elige gustos
/// y se genera el home personalizado al terminar.
class TasteOnboardingPage extends StatefulWidget {
  final VoidCallback onFinished;

  const TasteOnboardingPage({super.key, required this.onFinished});

  @override
  State<TasteOnboardingPage> createState() => _TasteOnboardingPageState();
}

class _TasteOnboardingPageState extends State<TasteOnboardingPage> {
  static const _tmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';

  final List<_PosterItem> _movies = [];
  final List<_PosterItem> _series = [];
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _saving = false;
  int _tab = 0;
  int _pageMovie = 1;
  int _pageTv = 1;
  bool _moreMovies = true;
  bool _moreTv = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    await Future.wait([
      _fetchPage('movie', 1),
      _fetchPage('tv', 1),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final isMovie = _tab == 0;
    if (isMovie && !_moreMovies) return;
    if (!isMovie && !_moreTv) return;
    setState(() => _loadingMore = true);
    if (isMovie) {
      _pageMovie++;
      await _fetchPage('movie', _pageMovie);
    } else {
      _pageTv++;
      await _fetchPage('tv', _pageTv);
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _fetchPage(String media, int page) async {
    try {
      // Mezcla popular + top_rated + trending para variedad y títulos conocidos
      final endpoints = [
        'https://api.themoviedb.org/3/$media/popular?api_key=$_tmdbKey&language=es-MX&page=$page',
        if (page <= 3)
          'https://api.themoviedb.org/3/trending/$media/week?api_key=$_tmdbKey&language=es-MX&page=$page',
      ];
      final seen = <int>{
        for (final e in (media == 'tv' ? _series : _movies)) e.tmdbId,
      };
      final batch = <_PosterItem>[];
      for (final url in endpoints) {
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map;
        final totalPages = (data['total_pages'] as num?)?.toInt() ?? 1;
        if (media == 'movie' && page >= totalPages) _moreMovies = false;
        if (media == 'tv' && page >= totalPages) _moreTv = false;
        for (final r in (data['results'] as List? ?? [])) {
          if (r is! Map) continue;
          final id = (r['id'] as num?)?.toInt();
          if (id == null || seen.contains(id)) continue;
          final poster = r['poster_path']?.toString();
          if (poster == null || poster.isEmpty) continue;
          final votes = (r['vote_count'] as num?)?.toInt() ?? 0;
          // Filtrar rarezas extremas en onboarding
          if (votes < 50) continue;
          seen.add(id);
          batch.add(_PosterItem(
            tmdbId: id,
            tipo: media == 'tv' ? 'tv' : 'movie',
            titulo: (r['title'] ?? r['name'] ?? '').toString(),
            posterUrl: 'https://image.tmdb.org/t/p/w342$poster',
          ));
        }
      }
      if (!mounted) return;
      setState(() {
        if (media == 'tv') {
          _series.addAll(batch);
        } else {
          _movies.addAll(batch);
        }
      });
    } catch (_) {
      if (media == 'movie') _moreMovies = false;
      if (media == 'tv') _moreTv = false;
    }
  }

  void _toggle(_PosterItem item) {
    final key = '${item.tipo}:${item.tmdbId}';
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  Future<void> _finish() async {
    if (_selected.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige al menos 3 títulos que te gusten')),
      );
      return;
    }
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

    // Cerrar onboarding YA; generar home en background (IA puede tardar).
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

  @override
  Widget build(BuildContext context) {
    final list = _tab == 0 ? _movies : _series;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '¿Qué te gusta?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Toca los pósters que te atraen. Desplázate para ver más. '
                'Con eso armamos tu home personalizado. Mínimo 3.',
                style:
                    TextStyle(color: Colors.white60, fontSize: 14, height: 1.35),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _chip('Películas', 0),
                  const SizedBox(width: 8),
                  _chip('Series', 1),
                  const Spacer(),
                  Text(
                    '${_selected.length} elegidas',
                    style:
                        const TextStyle(color: Colors.purpleAccent, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Colors.purpleAccent),
                    )
                  : GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.67,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: list.length + (_loadingMore ? 3 : 0),
                      itemBuilder: (_, i) {
                        if (i >= list.length) {
                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1a1a2e),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          );
                        }
                        final item = list[i];
                        final key = '${item.tipo}:${item.tmdbId}';
                        final sel = _selected.contains(key);
                        return GestureDetector(
                          onTap: () => _toggle(item),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: item.posterUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) =>
                                      Container(color: const Color(0xFF1a1a2e)),
                                  errorWidget: (_, __, ___) => Container(
                                    color: const Color(0xFF1a1a2e),
                                    child: const Icon(Icons.movie,
                                        color: Colors.white24),
                                  ),
                                ),
                              ),
                              if (sel)
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.purpleAccent,
                                      width: 3,
                                    ),
                                    color:
                                        Colors.purpleAccent.withOpacity(0.25),
                                  ),
                                  child: const Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(Icons.favorite,
                                          color: Colors.pinkAccent, size: 22),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ElevatedButton(
                onPressed: _saving ? null : _finish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Armando tu home…'),
                        ],
                      )
                    : Text(
                        _selected.length >= 3
                            ? 'Continuar (${_selected.length})'
                            : 'Elige al menos 3',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, int index) {
    final on = _tab == index;
    return GestureDetector(
      onTap: () {
        setState(() => _tab = index);
        // Precargar más si la lista está corta
        final list = index == 0 ? _movies : _series;
        if (list.length < 30) _loadMore();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? Colors.purpleAccent : const Color(0xFF1a1a2e),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PosterItem {
  final int tmdbId;
  final String tipo;
  final String titulo;
  final String posterUrl;

  const _PosterItem({
    required this.tmdbId,
    required this.tipo,
    required this.titulo,
    required this.posterUrl,
  });
}
