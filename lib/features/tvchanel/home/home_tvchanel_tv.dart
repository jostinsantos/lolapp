import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../config/m3u8_page_tv.dart';
import '../config/addon_chanel_tv.dart';
import '../data/tvchanel_repository.dart';
import '../models/tv_channel_models.dart';
import '../player/player_tvchaneltv.dart';

const _kAccent = Color(0xFFE50914);
const _kPanel = Color(0xFF121214);
const _kPanelAlt = Color(0xFF1A1A1E);
const _kFavKey = 'tvchanel_favorites_v1';

/// Home TV en Vivo — diseño 3 columnas (como referencia):
/// [ Categorías ] [ Lista de canales ] [ Player preview ]
/// - Cambiar canal en la lista → actualiza el preview en el home
/// - OK / Select sobre el player → pantalla completa
class HomeTvChanelTv extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const HomeTvChanelTv({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<HomeTvChanelTv> createState() => _HomeTvChanelTvState();
}

class _HomeTvChanelTvState extends State<HomeTvChanelTv> {
  final _repo = TvChanelRepository.instance;

  List<TvCategory> _categories = [];
  bool _loading = true;
  String? _error;

  /// Categoría virtual "ALL" + categorías reales
  int _catIndex = 0;
  int _chIndex = 0;
  List<TvChannel> _allChannels = [];
  Set<String> _favorites = {};

  // Preview player
  VideoPlayerController? _preview;
  TvChannel? _currentChannel;
  bool _previewReady = false;
  bool _previewError = false;
  int _previewGen = 0;

  // Foco: 0 = categorías, 1 = canales, 2 = player
  int _zone = 0;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'tvchanel_root');
  final FocusNode _catFocus = FocusNode(debugLabel: 'tvchanel_cats');
  final FocusNode _chFocus = FocusNode(debugLabel: 'tvchanel_chs');
  final FocusNode _playerFocus = FocusNode(debugLabel: 'tvchanel_player');
  final FocusNode _favBtnFocus = FocusNode(debugLabel: 'tvchanel_fav');
  final FocusNode _epgBtnFocus = FocusNode(debugLabel: 'tvchanel_epg');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'tvchanel_search');
  final FocusNode _m3uFocus = FocusNode(debugLabel: 'tvchanel_m3u');

  final ScrollController _catScroll = ScrollController();
  final ScrollController _chScroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  List<_CatItem> get _catItems {
    final items = <_CatItem>[
      _CatItem('ALL', _allChannels.length),
      _CatItem('Favorito', _favorites.length),
    ];
    for (final c in _categories) {
      items.add(_CatItem(c.name, c.channels.length));
    }
    return items;
  }

  List<TvChannel> get _visibleChannels {
    final cats = _catItems;
    if (_catIndex < 0 || _catIndex >= cats.length) return [];
    final name = cats[_catIndex].name;
    List<TvChannel> list;
    if (name == 'ALL') {
      list = List.from(_allChannels);
    } else if (name == 'Favorito') {
      list = _allChannels.where((c) => _favorites.contains(c.id)).toList();
    } else {
      final cat = _categories.firstWhere(
        (c) => c.name == name,
        orElse: () => const TvCategory(name: '', channels: []),
      );
      list = List.from(cat.channels);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadFavorites();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMainFocusNodeCreated?.call(_catFocus);
      _catFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _disposePreview();
    _rootFocus.dispose();
    _catFocus.dispose();
    _chFocus.dispose();
    _playerFocus.dispose();
    _favBtnFocus.dispose();
    _epgBtnFocus.dispose();
    _searchFocus.dispose();
    _m3uFocus.dispose();
    _catScroll.dispose();
    _chScroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kFavKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
        if (mounted) setState(() => _favorites = list);
      }
    } catch (_) {}
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFavKey, jsonEncode(_favorites.toList()));
  }

  void _toggleFavorite(TvChannel ch) {
    setState(() {
      if (_favorites.contains(ch.id)) {
        _favorites.remove(ch.id);
      } else {
        _favorites.add(ch.id);
      }
    });
    _saveFavorites();
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

      final all = <TvChannel>[];
      final seen = <String>{};
      for (final cat in categories) {
        for (final ch in cat.channels) {
          if (seen.add(ch.id)) all.add(ch);
        }
      }

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _allChannels = all;
        _loading = false;
        _catIndex = 0;
        _chIndex = 0;
      });

      if (all.isNotEmpty) {
        _selectChannel(all.first, playPreview: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _disposePreview() {
    final c = _preview;
    _preview = null;
    _previewReady = false;
    try {
      c?.pause();
      c?.dispose();
    } catch (_) {}
  }

  Future<void> _selectChannel(TvChannel ch, {bool playPreview = true}) async {
    if (_currentChannel?.id == ch.id && _previewReady) return;
    setState(() {
      _currentChannel = ch;
      _previewReady = false;
      _previewError = false;
    });
    if (!playPreview) return;

    final gen = ++_previewGen;
    _disposePreview();

    try {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(ch.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );
      await ctrl.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || gen != _previewGen) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setVolume(1.0);
      await ctrl.setLooping(true);
      await ctrl.play();
      if (!mounted || gen != _previewGen) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _preview = ctrl;
        _previewReady = true;
        _previewError = false;
      });
    } catch (_) {
      if (mounted && gen == _previewGen) {
        setState(() {
          _previewError = true;
          _previewReady = false;
        });
      }
    }
  }

  void _openFullscreen() {
    final ch = _currentChannel;
    if (ch == null) return;
    // Liberar preview por completo para que no compita con el player full
    _disposePreview();
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => PlayerTvChanelTv(
          channel: ch,
          categories: _categories.isEmpty
              ? [TvCategory(name: 'ALL', channels: _allChannels)]
              : _categories,
        ),
      ),
    )
        .then((_) {
      // Al volver, recrear preview del canal actual
      if (mounted && _currentChannel != null) {
        _selectChannel(_currentChannel!, playPreview: true);
      }
    });
  }

  void _goMenu() => widget.onRequestMenuFocus?.call();

  void _moveCat(int delta) {
    final items = _catItems;
    if (items.isEmpty) return;
    final next = (_catIndex + delta).clamp(0, items.length - 1);
    if (next == _catIndex) return;
    setState(() {
      _catIndex = next;
      _chIndex = 0;
    });
    _ensureCatVisible(next);
    final chs = _visibleChannels;
    if (chs.isNotEmpty) {
      _selectChannel(chs.first, playPreview: true);
    }
  }

  void _moveCh(int delta) {
    final chs = _visibleChannels;
    if (chs.isEmpty) return;
    final next = (_chIndex + delta).clamp(0, chs.length - 1);
    if (next == _chIndex) {
      // Al final de la lista, no hace nada
      return;
    }
    setState(() => _chIndex = next);
    _ensureChVisible(next);
    _selectChannel(chs[next], playPreview: true);
  }

  void _ensureCatVisible(int i) {
    if (!_catScroll.hasClients) return;
    const itemH = 36.0;
    final target = i * itemH;
    final view = _catScroll.position.viewportDimension;
    final offset = _catScroll.offset;
    if (target < offset) {
      _catScroll.animateTo(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } else if (target + itemH > offset + view) {
      _catScroll.animateTo(target + itemH - view,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void _ensureChVisible(int i) {
    if (!_chScroll.hasClients) return;
    const itemH = 38.0;
    final target = i * itemH;
    final view = _chScroll.position.viewportDimension;
    final offset = _chScroll.offset;
    if (target < offset) {
      _chScroll.animateTo(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } else if (target + itemH > offset + view) {
      _chScroll.animateTo(target + itemH - view,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Dejar que cada zona gestione; root solo para atrás al menú si nadie más
    return KeyEventResult.ignored;
  }

  KeyEventResult _onCatKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      // Primera categoría → menú (superior o lateral según shell)
      if (_catIndex <= 0) {
        _goMenu();
        return KeyEventResult.handled;
      }
      _moveCat(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveCat(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _zone = 1);
      _chFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      // Izquierda / menú lateral
      _goMenu();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      setState(() => _zone = 1);
      _chFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // Long-press / media no estándar → menú
    if (key == LogicalKeyboardKey.contextMenu) {
      _goMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onChKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveCh(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveCh(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _zone = 0);
      _catFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _zone = 2);
      _playerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      // OK en canal: pantalla completa
      _openFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onPlayerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _zone = 1);
      _chFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _favBtnFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _openFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: _onRootKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _kAccent),
              )
            : _error != null
                ? Center(
                    child: Text(
                      'Error: $_error',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                : Column(
                    children: [
                      _buildTopBar(),
                      Expanded(
                        child: Row(
                          children: [
                            // ── Columna categorías (más delgada) ──
                            SizedBox(
                              width: 150,
                              child: _buildCategoriesPanel(),
                            ),
                            Container(width: 1, color: Colors.white12),
                            // ── Columna canales (más delgada) ──
                            SizedBox(
                              width: 240,
                              child: _buildChannelsPanel(),
                            ),
                            Container(width: 1, color: Colors.white12),
                            // ── Player preview ──
                            Expanded(child: _buildPlayerPanel()),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xCC000000), Color(0x99000000)],
        ),
      ),
      child: Row(
        children: [
          const Text(
            'En vivo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Focus(
            focusNode: _m3uFocus,
            onKeyEvent: (n, e) {
              if (e is! KeyDownEvent) return KeyEventResult.ignored;
              if (e.logicalKey == LogicalKeyboardKey.select ||
                  e.logicalKey == LogicalKeyboardKey.enter) {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => M3u8PageTv(
                          onRequestMenuFocus: () =>
                              Navigator.of(context).maybePop(),
                        ),
                      ),
                    )
                    .then((_) => _load());
                return KeyEventResult.handled;
              }
              if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                _playerFocus.requestFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final has = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => M3u8PageTv(
                              onRequestMenuFocus: () =>
                                  Navigator.of(context).maybePop(),
                            ),
                          ),
                        )
                        .then((_) => _load());
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: has ? Colors.white12 : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: has ? Colors.white : Colors.transparent,
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.playlist_play,
                            color: Colors.white70, size: 18),
                        SizedBox(width: 6),
                        Text('Listas',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => AddonChanelTv(
                        onRequestMenuFocus: () =>
                            Navigator.of(context).maybePop(),
                      ),
                    ),
                  )
                  .then((_) => _load());
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.extension, color: Colors.white54, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesPanel() {
    final items = _catItems;
    return ColoredBox(
      color: _kPanel,
      child: Focus(
        focusNode: _catFocus,
        onKeyEvent: _onCatKey,
        child: Builder(
          builder: (context) {
            final zoneFocus = Focus.of(context).hasFocus;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 10, 10, 4),
                  child: Text(
                    'Categorías',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _catScroll,
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final selected = i == _catIndex;
                      final focused = zoneFocus && selected;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _catIndex = i;
                            _chIndex = 0;
                            _zone = 0;
                          });
                          final chs = _visibleChannels;
                          if (chs.isNotEmpty) {
                            _selectChannel(chs.first, playPreview: true);
                          }
                          _catFocus.requestFocus();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          color: focused
                              ? Colors.white.withValues(alpha: 0.12)
                              : (selected
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.transparent),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: focused || selected
                                        ? Colors.white
                                        : Colors.white60,
                                    fontSize: 13,
                                    fontWeight: focused || selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              Text(
                                '${item.count}',
                                style: TextStyle(
                                  color: focused
                                      ? Colors.white70
                                      : Colors.white30,
                                  fontSize: 12,
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
          },
        ),
      ),
    );
  }

  Widget _buildChannelsPanel() {
    final chs = _visibleChannels;
    return ColoredBox(
      color: _kPanelAlt,
      child: Focus(
        focusNode: _chFocus,
        onKeyEvent: _onChKey,
        child: Builder(
          builder: (context) {
            final zoneFocus = Focus.of(context).hasFocus;
            if (chs.isEmpty) {
              return const Center(
                child: Text(
                  'Sin canales',
                  style: TextStyle(color: Colors.white38),
                ),
              );
            }
            return ListView.builder(
              controller: _chScroll,
              itemCount: chs.length,
              itemBuilder: (_, i) {
                final ch = chs[i];
                final selected = i == _chIndex;
                final focused = zoneFocus && selected;
                final isFav = _favorites.contains(ch.id);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _chIndex = i;
                      _zone = 1;
                    });
                    _selectChannel(ch, playPreview: true);
                    _chFocus.requestFocus();
                  },
                  onDoubleTap: _openFullscreen,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    color: focused
                        ? Colors.white.withValues(alpha: 0.14)
                        : (selected
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.transparent),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: focused ? Colors.white70 : Colors.white30,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (ch.logo != null && ch.logo!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                ch.logo!,
                                width: 28,
                                height: 28,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.live_tv,
                                  color: Colors.white24,
                                  size: 22,
                                ),
                              ),
                            ),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.live_tv,
                                color: Colors.white24, size: 22),
                          ),
                        Expanded(
                          child: Text(
                            ch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: focused || selected
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 13,
                              fontWeight: focused
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (isFav)
                          const Icon(Icons.favorite,
                              color: Colors.pinkAccent, size: 16),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayerPanel() {
    final ch = _currentChannel;
    final isFav = ch != null && _favorites.contains(ch.id);

    return ColoredBox(
      color: const Color(0xFF0A0A0C),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Breadcrumb
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  _catItems.isNotEmpty
                      ? _catItems[_catIndex.clamp(0, _catItems.length - 1)].name
                      : 'ALL',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const Text('  >>  ',
                    style: TextStyle(color: Colors.white24, fontSize: 12)),
                Expanded(
                  child: Text(
                    ch?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // Video preview
          Expanded(
            child: Focus(
              focusNode: _playerFocus,
              onKeyEvent: _onPlayerKey,
              child: Builder(
                builder: (context) {
                  final hasFocus = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: _openFullscreen,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasFocus ? Colors.white : Colors.white12,
                          width: hasFocus ? 2.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_previewReady && _preview != null)
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _preview!.value.size.width,
                                height: _preview!.value.size.height,
                                child: VideoPlayer(_preview!),
                              ),
                            )
                          else
                            Container(
                              color: const Color(0xFF111118),
                              alignment: Alignment.center,
                              child: _previewError
                                  ? const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.error_outline,
                                            color: Colors.white38, size: 40),
                                        SizedBox(height: 8),
                                        Text('No se pudo cargar el stream',
                                            style: TextStyle(
                                                color: Colors.white38,
                                                fontSize: 13)),
                                      ],
                                    )
                                  : const CircularProgressIndicator(
                                      color: _kAccent, strokeWidth: 2),
                            ),
                          // Hint fullscreen
                          if (hasFocus)
                            Positioned(
                              bottom: 10,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'OK · Pantalla completa',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 11),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Info + acciones
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ch?.name ?? 'Sin canal',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isFav)
                      const Icon(Icons.favorite,
                          color: Colors.pinkAccent, size: 20),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ActionChip(
                      focusNode: _favBtnFocus,
                      icon: isFav ? Icons.favorite : Icons.favorite_border,
                      label: isFav ? 'En favoritos' : 'Agregar a los favoritos',
                      accent: isFav,
                      onTap: () {
                        if (ch != null) _toggleFavorite(ch);
                      },
                      onUp: () => _playerFocus.requestFocus(),
                      onRight: () => _epgBtnFocus.requestFocus(),
                      onLeft: () {
                        setState(() => _zone = 1);
                        _chFocus.requestFocus();
                      },
                    ),
                    const SizedBox(width: 10),
                    _ActionChip(
                      focusNode: _epgBtnFocus,
                      icon: Icons.schedule,
                      label: 'EPG',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('EPG próximamente'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      onUp: () => _playerFocus.requestFocus(),
                      onLeft: () => _favBtnFocus.requestFocus(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatItem {
  final String name;
  final int count;
  const _CatItem(this.name, this.count);
}

class _ActionChip extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _ActionChip({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
    this.onUp,
    this.onLeft,
    this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final key = e.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onUp?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          onRight?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final has = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: has
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: has ? Colors.white : Colors.white24,
                  width: has ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: accent ? Colors.pinkAccent : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: accent ? Colors.pinkAccent : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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
}
