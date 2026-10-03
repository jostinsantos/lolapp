import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tvchanel_repository.dart';
import '../models/tv_channel_models.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF1C1C1E);

/// Gestión de listas M3U8 — versión TV (foco D-pad)
class M3u8PageTv extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;

  const M3u8PageTv({super.key, this.onRequestMenuFocus});

  @override
  State<M3u8PageTv> createState() => _M3u8PageTvState();
}

class _M3u8PageTvState extends State<M3u8PageTv> {
  final _repo = TvChanelRepository.instance;
  List<M3uPlaylist> _playlists = [];
  bool _loading = true;

  final FocusNode _rootFocus = FocusNode(debugLabel: 'm3u8_tv_root');
  final FocusNode _addFocus = FocusNode(debugLabel: 'm3u8_add');
  List<FocusNode> _itemNodes = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rootFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    _addFocus.dispose();
    for (final n in _itemNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _repo.getPlaylists();
    for (final n in _itemNodes) {
      n.dispose();
    }
    _itemNodes =
        List.generate(list.length, (i) => FocusNode(debugLabel: 'm3u_$i'));
    if (!mounted) return;
    setState(() {
      _playlists = list;
      _loading = false;
    });
  }

  Future<void> _addPlaylist() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _kCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Añadir lista M3U / M3U8',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nombre de la lista',
                  labelStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: _kAccent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'URL (.m3u o .m3u8)',
                  labelStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: _kAccent),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Añadir',
                style: TextStyle(
                    color: _kAccent, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final url = urlCtrl.text.trim();
    if (name.isEmpty || url.isEmpty) return;

    await _repo.addPlaylist(name: name, url: url);
    await _load();
    if (_itemNodes.isNotEmpty) {
      _itemNodes.last.requestFocus();
    }
  }

  Future<void> _toggle(M3uPlaylist p) async {
    await _repo.togglePlaylist(p.id, !p.enabled);
    await _load();
  }

  Future<void> _delete(M3uPlaylist p) async {
    await _repo.removePlaylist(p.id);
    await _load();
  }

  /// Modal de acciones (activar/desactivar + eliminar). Mismo patrón TV.
  Future<void> _showItemActions(M3uPlaylist p) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final focusToggle = FocusNode();
        final focusDelete = FocusNode();
        final focusCancel = FocusNode();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          focusToggle.requestFocus();
        });
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                p.enabled ? 'Lista activa' : 'Lista inactiva',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _M3uActionBtn(
                focusNode: focusToggle,
                label: p.enabled ? 'Desactivar' : 'Activar',
                icon: p.enabled ? Icons.pause_circle_outline : Icons.play_circle_outline,
                onTap: () => Navigator.pop(ctx, 'toggle'),
                onDown: () => focusDelete.requestFocus(),
                onUp: () {},
              ),
              const SizedBox(height: 8),
              _M3uActionBtn(
                focusNode: focusDelete,
                label: 'Eliminar',
                icon: Icons.delete_outline,
                danger: true,
                onTap: () => Navigator.pop(ctx, 'delete'),
                onUp: () => focusToggle.requestFocus(),
                onDown: () => focusCancel.requestFocus(),
              ),
              const SizedBox(height: 8),
              _M3uActionBtn(
                focusNode: focusCancel,
                label: 'Cancelar',
                icon: Icons.close,
                onTap: () => Navigator.pop(ctx),
                onUp: () => focusDelete.requestFocus(),
                onDown: () {},
              ),
            ],
          ),
        );
      },
    );
    if (action == 'toggle') {
      await _toggle(p);
    } else if (action == 'delete') {
      await _delete(p);
    }
  }

  void _goBack() {
    if (widget.onRequestMenuFocus != null) {
      widget.onRequestMenuFocus!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.browserBack) {
          _goBack();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowRight) {
          _addFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Listas M3U8',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Focus(
                      focusNode: _addFocus,
                      onKeyEvent: (n, e) {
                        if (e is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        final key = e.logicalKey;
                        if (key == LogicalKeyboardKey.select ||
                            key == LogicalKeyboardKey.enter) {
                          _addPlaylist();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowDown) {
                          if (_itemNodes.isNotEmpty) {
                            _itemNodes.first.requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowLeft ||
                            key == LogicalKeyboardKey.goBack) {
                          _goBack();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(builder: (ctx) {
                        final hasFocus = Focus.of(ctx).hasFocus;
                        return GestureDetector(
                          onTap: _addPlaylist,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(
                              color: hasFocus
                                  ? _kAccent
                                  : _kAccent.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasFocus
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2.2,
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.add_rounded,
                                    color: Colors.white, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Añadir lista',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: _kAccent),
                        )
                      : _playlists.isEmpty
                          ? Center(
                              child: Text(
                                'No hay listas.\nPulsa “Añadir lista” para agregar una.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.45),
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _playlists.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final p = _playlists[i];
                                final node = _itemNodes[i];
                                return Focus(
                                  focusNode: node,
                                  onKeyEvent: (n, event) {
                                    if (event is! KeyDownEvent) {
                                      return KeyEventResult.ignored;
                                    }
                                    final key = event.logicalKey;
                                    if (key == LogicalKeyboardKey.select ||
                                        key == LogicalKeyboardKey.enter) {
                                      _showItemActions(p);
                                      return KeyEventResult.handled;
                                    }
                                    if (key ==
                                        LogicalKeyboardKey.delete) {
                                      _showItemActions(p);
                                      return KeyEventResult.handled;
                                    }
                                    if (key ==
                                            LogicalKeyboardKey.arrowUp) {
                                      if (i > 0) {
                                        _itemNodes[i - 1].requestFocus();
                                      } else {
                                        _addFocus.requestFocus();
                                      }
                                      return KeyEventResult.handled;
                                    }
                                    if (key ==
                                        LogicalKeyboardKey.arrowDown) {
                                      if (i < _itemNodes.length - 1) {
                                        _itemNodes[i + 1].requestFocus();
                                      }
                                      return KeyEventResult.handled;
                                    }
                                    if (key ==
                                            LogicalKeyboardKey.arrowLeft ||
                                        key ==
                                            LogicalKeyboardKey.goBack) {
                                      _goBack();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: Builder(builder: (ctx) {
                                    final hasFocus =
                                        Focus.of(ctx).hasFocus;
                                    return GestureDetector(
                                      onTap: () => _showItemActions(p),
                                      onLongPress: () => _showItemActions(p),
                                      child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 140),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: _kCard,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                          color: hasFocus
                                              ? Colors.white
                                              : Colors.white10,
                                          width: hasFocus ? 2.2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.live_tv_rounded,
                                            color: p.enabled
                                                ? _kAccent
                                                : Colors.white38,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                              children: [
                                                Text(
                                                  p.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  p.url,
                                                  maxLines: 1,
                                                  overflow: TextOverflow
                                                      .ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.45),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: p.enabled
                                                  ? _kAccent.withValues(
                                                      alpha: 0.2)
                                                  : Colors.white12,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      8),
                                            ),
                                            child: Text(
                                              p.enabled
                                                  ? 'Activa'
                                                  : 'Inactiva',
                                              style: TextStyle(
                                                color: p.enabled
                                                    ? _kAccent
                                                    : Colors.white54,
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    );
                                  }),
                                );
                              },
                            ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'OK / Mantén OK = menú (activar·desactivar / eliminar)  ·  ↑↓ navegar',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _M3uActionBtn extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final bool danger;

  const _M3uActionBtn({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.onUp,
    required this.onDown,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp) {
          onUp();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown) {
          onDown();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final f = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: f
                  ? (danger
                      ? Colors.red.withValues(alpha: 0.25)
                      : _kAccent.withValues(alpha: 0.25))
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: f
                    ? (danger ? Colors.redAccent : Colors.white)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(children: [
              Icon(icon,
                  color: danger ? Colors.redAccent : Colors.white, size: 20),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                    color: danger ? Colors.redAccent : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  )),
            ]),
          ),
        );
      }),
    );
  }
}
