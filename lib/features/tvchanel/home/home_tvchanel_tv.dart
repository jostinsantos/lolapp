import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/m3u8_page_tv.dart';
import '../config/addon_chanel_tv.dart';
import '../data/tvchanel_repository.dart';
import '../models/tv_channel_models.dart';
import '../player/player_tvchaneltv.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF1C1C1E);

/// Home de TV en Vivo (solo TV)
/// Accesible desde el menú lateral del home TV.
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
  final FocusNode _rootFocus = FocusNode(debugLabel: 'home_tvchanel_root');
  final ScrollController _verticalScroll = ScrollController();

  List<TvCategory> _categories = [];
  List<TvAddon> _addons = [];
  bool _loading = true;
  String? _error;

  // Foco
  final FocusNode _m3uBtnFocus = FocusNode(debugLabel: 'btn_m3u');
  final FocusNode _addonBtnFocus = FocusNode(debugLabel: 'btn_addon');
  final FocusNode _refreshFocus = FocusNode(debugLabel: 'btn_refresh');
  List<FocusNode> _catNodes = [];
  List<List<FocusNode>> _channelNodes = [];
  final List<GlobalKey> _catKeys = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMainFocusNodeCreated?.call(_rootFocus);
      _rootFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    _m3uBtnFocus.dispose();
    _addonBtnFocus.dispose();
    _refreshFocus.dispose();
    _verticalScroll.dispose();
    _disposeFocusNodes();
    super.dispose();
  }

  void _disposeFocusNodes() {
    for (final n in _catNodes) {
      n.dispose();
    }
    for (final row in _channelNodes) {
      for (final n in row) {
        n.dispose();
      }
    }
    _catNodes = [];
    _channelNodes = [];
    _catKeys.clear();
  }

  void _ensureCatVisible(int catIndex) {
    if (catIndex < 0 || catIndex >= _catKeys.length) return;
    final ctx = _catKeys[catIndex].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
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

      // Combinar categorías de addons
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

      _disposeFocusNodes();
      _catNodes = List.generate(
        categories.length,
        (i) => FocusNode(debugLabel: 'cat_$i'),
      );
      _channelNodes = categories
          .map((cat) => List.generate(
                cat.channels.length,
                (i) => FocusNode(debugLabel: 'ch_${cat.name}_$i'),
              ))
          .toList();
      _catKeys.addAll(
        List.generate(categories.length, (_) => GlobalKey()),
      );

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _addons = addons;
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
        builder: (_) => PlayerTvChanelTv(
          channel: channel,
          categories: _categories,
        ),
      ),
    );
  }

  void _goMenu() {
    widget.onRequestMenuFocus?.call();
  }

  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.arrowLeft) {
      _goMenu();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      _m3uBtnFocus.requestFocus();
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
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header + botones
                Row(
                  children: [
                    const Text(
                      'TV en Vivo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _TvHeaderButton(
                      focusNode: _m3uBtnFocus,
                      icon: Icons.playlist_play_rounded,
                      label: 'Listas M3U8',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => M3u8PageTv(
                              onRequestMenuFocus: () =>
                                  Navigator.of(context).maybePop(),
                            ),
                          ),
                        ).then((_) => _load());
                      },
                      onLeft: _goMenu,
                      onRight: () => _addonBtnFocus.requestFocus(),
                      onDown: () {
                        if (_catNodes.isNotEmpty) {
                          _catNodes.first.requestFocus();
                        }
                      },
                    ),
                    const SizedBox(width: 12),
                    _TvHeaderButton(
                      focusNode: _addonBtnFocus,
                      icon: Icons.extension_rounded,
                      label: 'Addons',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddonChanelTv(
                              onRequestMenuFocus: () =>
                                  Navigator.of(context).maybePop(),
                            ),
                          ),
                        ).then((_) => _load());
                      },
                      onLeft: () => _m3uBtnFocus.requestFocus(),
                      onRight: () => _refreshFocus.requestFocus(),
                      onDown: () {
                        if (_catNodes.isNotEmpty) {
                          _catNodes.first.requestFocus();
                        }
                      },
                    ),
                    const SizedBox(width: 12),
                    _TvHeaderButton(
                      focusNode: _refreshFocus,
                      icon: Icons.refresh_rounded,
                      label: 'Actualizar',
                      onTap: _load,
                      onLeft: () => _addonBtnFocus.requestFocus(),
                      onDown: () {
                        if (_catNodes.isNotEmpty) {
                          _catNodes.first.requestFocus();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: _kAccent),
                        )
                      : _error != null
                          ? Center(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            )
                          : _categories.isEmpty
                              ? _buildEmpty()
                              : ListView.builder(
                                  controller: _verticalScroll,
                                  itemCount: _categories.length,
                                  itemBuilder: (_, catIndex) {
                                    final cat = _categories[catIndex];
                                    final catKey = catIndex < _catKeys.length
                                        ? _catKeys[catIndex]
                                        : GlobalKey();
                                    return KeyedSubtree(
                                      key: catKey,
                                      child: _CategorySection(
                                        category: cat,
                                        catFocus: _catNodes[catIndex],
                                        channelFocuses:
                                            _channelNodes[catIndex],
                                        onChannelTap: _openPlayer,
                                        onFocused: () =>
                                            _ensureCatVisible(catIndex),
                                        onUp: () {
                                          if (catIndex > 0) {
                                            _catNodes[catIndex - 1]
                                                .requestFocus();
                                            _ensureCatVisible(catIndex - 1);
                                          } else {
                                            _m3uBtnFocus.requestFocus();
                                          }
                                        },
                                        onDown: () {
                                          if (catIndex <
                                              _catNodes.length - 1) {
                                            _catNodes[catIndex + 1]
                                                .requestFocus();
                                            _ensureCatVisible(catIndex + 1);
                                          }
                                        },
                                        onLeft: _goMenu,
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv_rounded,
              size: 64, color: Colors.white.withValues(alpha: 0.25)),
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
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Widgets auxiliares
// ─────────────────────────────────────────────

class _TvHeaderButton extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onDown;

  const _TvHeaderButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLeft,
    this.onRight,
    this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft && onLeft != null) {
          onLeft!();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight && onRight != null) {
          onRight!();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown && onDown != null) {
          onDown!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final hasFocus = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: hasFocus
                  ? _kAccent
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasFocus ? Colors.white : Colors.transparent,
                width: 2.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight:
                        hasFocus ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _CategorySection extends StatefulWidget {
  final TvCategory category;
  final FocusNode catFocus;
  final List<FocusNode> channelFocuses;
  final ValueChanged<TvChannel> onChannelTap;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback? onFocused;

  const _CategorySection({
    required this.category,
    required this.catFocus,
    required this.channelFocuses,
    required this.onChannelTap,
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    this.onFocused,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  final ScrollController _hScroll = ScrollController();
  final List<GlobalKey> _chKeys = [];

  @override
  void initState() {
    super.initState();
    _rebuildKeys();
    widget.catFocus.addListener(_onCatFocus);
    for (final n in widget.channelFocuses) {
      n.addListener(_onChannelFocus);
    }
  }

  @override
  void didUpdateWidget(covariant _CategorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelFocuses != widget.channelFocuses ||
        oldWidget.category.channels.length != widget.category.channels.length) {
      for (final n in oldWidget.channelFocuses) {
        n.removeListener(_onChannelFocus);
      }
      for (final n in widget.channelFocuses) {
        n.addListener(_onChannelFocus);
      }
      _rebuildKeys();
    }
    if (oldWidget.catFocus != widget.catFocus) {
      oldWidget.catFocus.removeListener(_onCatFocus);
      widget.catFocus.addListener(_onCatFocus);
    }
  }

  void _rebuildKeys() {
    _chKeys
      ..clear()
      ..addAll(
        List.generate(widget.category.channels.length, (_) => GlobalKey()),
      );
  }

  void _onCatFocus() {
    if (widget.catFocus.hasFocus) {
      widget.onFocused?.call();
    }
  }

  void _onChannelFocus() {
    for (var i = 0; i < widget.channelFocuses.length; i++) {
      if (widget.channelFocuses[i].hasFocus) {
        widget.onFocused?.call();
        _ensureChannelVisible(i);
        break;
      }
    }
  }

  void _ensureChannelVisible(int i) {
    if (i < 0 || i >= _chKeys.length) return;
    final ctx = _chKeys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
  }

  @override
  void dispose() {
    widget.catFocus.removeListener(_onCatFocus);
    for (final n in widget.channelFocuses) {
      n.removeListener(_onChannelFocus);
    }
    _hScroll.dispose();
    super.dispose();
  }

  bool _isValidLogoUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.trim().toLowerCase();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    // Formatos que suelen fallar el decoder de Flutter en Android
    if (u.endsWith('.svg') ||
        u.endsWith('.webp') ||
        u.endsWith('.gif') ||
        u.contains('data:image')) {
      return false;
    }
    return true;
  }

  Widget _logoFallback() {
    return Container(
      color: _kAccent.withValues(alpha: 0.12),
      child: const Center(
        child: Icon(Icons.live_tv_rounded, color: _kAccent, size: 36),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final channelFocuses = widget.channelFocuses;
    final catFocus = widget.catFocus;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            focusNode: catFocus,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.arrowUp) {
                widget.onUp();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowDown) {
                if (channelFocuses.isNotEmpty) {
                  channelFocuses.first.requestFocus();
                } else {
                  widget.onDown();
                }
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowLeft) {
                widget.onLeft();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(builder: (ctx) {
              final hasFocus = Focus.of(ctx).hasFocus;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  category.name,
                  style: TextStyle(
                    color: hasFocus ? _kAccent : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }),
          ),
          SizedBox(
            height: 130,
            child: ListView.separated(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              itemCount: category.channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                if (i >= category.channels.length ||
                    i >= channelFocuses.length) {
                  return const SizedBox.shrink();
                }
                final ch = category.channels[i];
                final node = channelFocuses[i];
                final key = i < _chKeys.length ? _chKeys[i] : GlobalKey();
                return KeyedSubtree(
                  key: key,
                  child: Focus(
                    focusNode: node,
                    onKeyEvent: (n, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final keyEvt = event.logicalKey;
                      if (keyEvt == LogicalKeyboardKey.select ||
                          keyEvt == LogicalKeyboardKey.enter) {
                        widget.onChannelTap(ch);
                        return KeyEventResult.handled;
                      }
                      if (keyEvt == LogicalKeyboardKey.arrowLeft) {
                        if (i > 0) {
                          channelFocuses[i - 1].requestFocus();
                        } else {
                          widget.onLeft();
                        }
                        return KeyEventResult.handled;
                      }
                      if (keyEvt == LogicalKeyboardKey.arrowRight) {
                        if (i < channelFocuses.length - 1) {
                          channelFocuses[i + 1].requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      if (keyEvt == LogicalKeyboardKey.arrowUp) {
                        catFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (keyEvt == LogicalKeyboardKey.arrowDown) {
                        widget.onDown();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(builder: (ctx) {
                      final hasFocus = Focus.of(ctx).hasFocus;
                      return GestureDetector(
                        onTap: () => widget.onChannelTap(ch),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 160,
                          decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  hasFocus ? Colors.white : Colors.white10,
                              width: hasFocus ? 2.4 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(13),
                                  ),
                                  child: _isValidLogoUrl(ch.logo)
                                      ? Image.network(
                                          ch.logo!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          gaplessPlayback: true,
                                          filterQuality: FilterQuality.low,
                                          errorBuilder: (_, __, ___) =>
                                              _logoFallback(),
                                          frameBuilder: (context, child,
                                              frame, wasSync) {
                                            if (frame == null) {
                                              return _logoFallback();
                                            }
                                            return child;
                                          },
                                        )
                                      : _logoFallback(),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Text(
                                  ch.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: hasFocus
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
