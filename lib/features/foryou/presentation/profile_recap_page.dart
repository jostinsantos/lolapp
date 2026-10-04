import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/recommendations/user_taste_profile.dart';
import '../../../data/recommendations/history_signals.dart';
import '../../content/presentation/content_page.dart';

/// Perfil estilo Spotify: recap de lo visto, me gusta, stats.
/// 100% local — 0 usos de IA.
class ProfileRecapPage extends StatefulWidget {
  const ProfileRecapPage({super.key});

  @override
  State<ProfileRecapPage> createState() => _ProfileRecapPageState();
}

class _ProfileRecapPageState extends State<ProfileRecapPage> {
  bool _loading = true;
  UserTasteProfile? _profile;
  List<_WatchStat> _topTitles = [];
  List<_WatchStat> _topSeries = [];
  int _totalMinutes = 0;
  int _totalTitles = 0;
  int _finishedCount = 0;
  Map<String, int> _genreCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await UserTasteProfile.load();
    final raw = await HistorySignals.loadRawHistory();

    final byTitle = <String, _WatchStat>{};
    var minutes = 0;
    var finished = 0;
    final genres = <String, int>{};

    for (final f in raw) {
      final id = (f['tmdb_id'] as num?)?.toInt() ??
          (f['idcontenido'] as num?)?.toInt() ??
          0;
      final title =
          (f['titulo'] ?? f['title'] ?? f['name'] ?? 'Sin título').toString();
      final tipo = (f['media_type'] ?? f['type'] ?? 'movie')
          .toString()
          .toLowerCase();
      final isTv = tipo.contains('tv') || tipo.contains('serie');
      final seg = (f['segundo'] as num?)?.toInt() ?? 0;
      final dur = (f['duracion'] as num?)?.toInt() ?? 0;
      minutes += (seg / 60).round();
      final key = '$id-${isTv ? 'tv' : 'movie'}';
      final prev = byTitle[key];
      final secs = (prev?.seconds ?? 0) + seg;
      byTitle[key] = _WatchStat(
        tmdbId: id,
        title: title,
        tipo: isTv ? 'tv' : 'movie',
        seconds: secs,
        plays: (prev?.plays ?? 0) + 1,
      );
      if (f['watched'] == true ||
          f['terminado'] == true ||
          (dur > 0 && seg / dur >= 0.9)) {
        finished++;
      }
      if (f['genres'] is List) {
        for (final g in f['genres'] as List) {
          final n = g.toString();
          genres[n] = (genres[n] ?? 0) + 1;
        }
      }
    }

    // sumar géneros del perfil
    profile.genreWeights.forEach((k, v) {
      genres[k] = (genres[k] ?? 0) + v.round();
    });

    final sorted = byTitle.values.toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));

    if (mounted) {
      setState(() {
        _profile = profile;
        _topTitles = sorted.take(10).toList();
        _topSeries =
            sorted.where((e) => e.tipo == 'tv').take(5).toList();
        _totalMinutes = minutes;
        _totalTitles = byTitle.length;
        _finishedCount = finished;
        _genreCounts = genres;
        _loading = false;
      });
    }
  }

  String _fmtMin(int m) {
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final r = m % 60;
    if (h < 24) return '${h}h ${r}m';
    return '${h ~/ 24}d ${h % 24}h';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Tu perfil', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.purpleAccent),
            )
          : RefreshIndicator(
              color: Colors.purpleAccent,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _heroStats(),
                  const SizedBox(height: 20),
                  _sectionTitle('Tus géneros top'),
                  _genreChips(),
                  const SizedBox(height: 20),
                  _sectionTitle('Más tiempo viendo'),
                  ..._topTitles.map(_titleRow),
                  if (_topSeries.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionTitle('Series que más has visto'),
                    ..._topSeries.map(_titleRow),
                  ],
                  if ((_profile?.likes.isNotEmpty) ?? false) ...[
                    const SizedBox(height: 20),
                    _sectionTitle('Me gusta'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _profile!.likes.entries.map((e) {
                        final v = e.value;
                        return ActionChip(
                          label: Text(
                            (v['title'] ?? '').toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          backgroundColor: const Color(0xFF2a2a4a),
                          onPressed: () {
                            final id = int.tryParse(e.key) ?? 0;
                            if (id <= 0) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PageContenido(
                                  idcontenido: id,
                                  tmdbId: id,
                                  mediaType: (v['type'] ?? 'movie').toString(),
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Todo se calcula en tu dispositivo con el historial y los Me gusta. '
                    'No usa IA ni envía datos a servidores.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _heroStats() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4C1D95), Color(0xFF1a1a2e)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu recap',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statBox('Tiempo', _fmtMin(_totalMinutes)),
              _statBox('Títulos', '$_totalTitles'),
              _statBox('Terminados', '$_finishedCount'),
              _statBox('Me gusta', '${_profile?.likes.length ?? 0}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _genreChips() {
    final entries = _genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const Text(
        'Aún no hay datos de géneros. Mira algo o dale Me gusta.',
        style: TextStyle(color: Colors.white38, fontSize: 13),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.take(12).map((e) {
        return Chip(
          label: Text(
            '${e.key}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          backgroundColor: const Color(0xFF2a2a4a),
          side: BorderSide.none,
        );
      }).toList(),
    );
  }

  Widget _titleRow(_WatchStat s) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: s.tmdbId > 0
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PageContenido(
                    idcontenido: s.tmdbId,
                    tmdbId: s.tmdbId,
                    mediaType: s.tipo,
                  ),
                ),
              );
            }
          : null,
      title: Text(
        s.title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${s.tipo == 'tv' ? 'Serie' : 'Película'} · ${_fmtMin(s.seconds ~/ 60)} · ${s.plays} veces',
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
    );
  }
}

class _WatchStat {
  final int tmdbId;
  final String title;
  final String tipo;
  final int seconds;
  final int plays;

  const _WatchStat({
    required this.tmdbId,
    required this.title,
    required this.tipo,
    required this.seconds,
    required this.plays,
  });
}
