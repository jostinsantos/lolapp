import 'package:flutter/material.dart';

import '../config/m3u8_page.dart';
import '../config/addon_chanel.dart';
import '../data/tvchanel_repository.dart';
import '../models/tv_channel_models.dart';
import '../player/player_tvchanel.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF1C1C1E);

/// Home de TV en Vivo — móvil
class HomeTvChanel extends StatefulWidget {
  const HomeTvChanel({super.key});

  @override
  State<HomeTvChanel> createState() => _HomeTvChanelState();
}

class _HomeTvChanelState extends State<HomeTvChanel> {
  final _repo = TvChanelRepository.instance;
  List<TvCategory> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.getAllM3uCategories(),
        _repo.loadAddons(),
      ]);
      final m3uCats = results[0] as List<TvCategory>;
      final addons = results[1] as List<TvAddon>;

      final combined = <String, List<TvChannel>>{};
      for (final cat in m3uCats) {
        combined.putIfAbsent(cat.name, () => []).addAll(cat.channels);
      }
      for (final addon in addons) {
        for (final cat in addon.categories) {
          combined.putIfAbsent(cat.name, () => []).addAll(cat.channels);
        }
      }
      final categories = combined.entries
          .map((e) => TvCategory(name: e.key, channels: e.value))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openPlayer(TvChannel channel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerTvChanel(
          channel: channel,
          categories: _categories,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'TV en Vivo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Listas M3U8',
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const M3u8Page()),
                      );
                      _load();
                    },
                    icon: const Icon(Icons.playlist_play_rounded, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Addons',
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddonChanelPage()),
                      );
                      _load();
                    },
                    icon: const Icon(Icons.extension_rounded, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _kAccent))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.redAccent)),
                        )
                      : _categories.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.live_tv_rounded,
                                        size: 64,
                                        color: Colors.white.withValues(alpha: 0.25)),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No hay canales',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.55),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Añade listas M3U8 o instala addons de canales',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: _kAccent),
                                      onPressed: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) => const M3u8Page()),
                                        );
                                        _load();
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Añadir lista M3U8'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              color: _kAccent,
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 100),
                                itemCount: _categories.length,
                                itemBuilder: (_, i) {
                                  final cat = _categories[i];
                                  return _CategoryBlock(
                                    category: cat,
                                    onTap: _openPlayer,
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

class _CategoryBlock extends StatelessWidget {
  final TvCategory category;
  final ValueChanged<TvChannel> onTap;
  const _CategoryBlock({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              category.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: category.channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final ch = category.channels[i];
                return GestureDetector(
                  onTap: () => onTap(ch),
                  child: SizedBox(
                    width: 110,
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ch.logo != null &&
                                    ch.logo!.startsWith('http')
                                ? Image.network(
                                    ch.logo!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, __, ___) => _fb(),
                                  )
                                : _fb(),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
      ),
    );
  }

  Widget _fb() => Container(
        color: _kAccent.withValues(alpha: 0.12),
        child: const Center(
          child: Icon(Icons.live_tv_rounded, color: _kAccent, size: 32),
        ),
      );
}
