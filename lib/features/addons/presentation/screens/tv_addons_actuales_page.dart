import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/addons/addon_manager.dart';
import '../../../../data/addons/models/addon.dart';

/// Página TV dedicada: Addons instalados (foco D-pad, sin AppBar móvil).
class TvAddonsActualesPage extends StatefulWidget {
  const TvAddonsActualesPage({super.key});

  @override
  State<TvAddonsActualesPage> createState() => _TvAddonsActualesPageState();
}

class _TvAddonsActualesPageState extends State<TvAddonsActualesPage> {
  final FocusNode _rootFocus = FocusNode(debugLabel: 'tv_addons_actuales_root');
  final FocusNode _refreshFocus = FocusNode(debugLabel: 'tv_addons_refresh');
  List<FocusNode> _itemNodes = [];
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    AddonManager.instance.init().then((_) {
      if (mounted) {
        _rebuildNodes();
        setState(() {});
      }
    });
    AddonManager.instance.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rootFocus.requestFocus();
    });
  }

  void _onChange() {
    if (!mounted) return;
    _rebuildNodes();
    setState(() {});
  }

  void _rebuildNodes() {
    for (final n in _itemNodes) {
      n.dispose();
    }
    final list = AddonManager.instance.addons;
    _itemNodes = List.generate(
      list.length,
      (i) => FocusNode(debugLabel: 'addon_$i'),
    );
  }

  @override
  void dispose() {
    AddonManager.instance.removeListener(_onChange);
    _rootFocus.dispose();
    _refreshFocus.dispose();
    _scrollCtrl.dispose();
    for (final n in _itemNodes) {
      n.dispose();
    }
    super.dispose();
  }


  void _scrollToFocused(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = node.context;
      if (ctx == null) return;
      try {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.25,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    });
  }

  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && _itemNodes.isNotEmpty) {
      _itemNodes.first.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _confirmDelete(AddonManifest a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final yes = FocusNode();
        final no = FocusNode();
        WidgetsBinding.instance.addPostFrameCallback((_) => no.requestFocus());
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '¿Eliminar «${a.name}»?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Focus(
                        focusNode: no,
                        onKeyEvent: (n, e) {
                          if (e is! KeyDownEvent) return KeyEventResult.ignored;
                          if (e.logicalKey == LogicalKeyboardKey.select ||
                              e.logicalKey == LogicalKeyboardKey.enter) {
                            Navigator.pop(ctx, false);
                            return KeyEventResult.handled;
                          }
                          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                            yes.requestFocus();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(builder: (c) {
                          final f = Focus.of(c).hasFocus;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: f
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: f
                                    ? Colors.white54
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text('Cancelar',
                                style: TextStyle(color: Colors.white70)),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Focus(
                        focusNode: yes,
                        onKeyEvent: (n, e) {
                          if (e is! KeyDownEvent) return KeyEventResult.ignored;
                          if (e.logicalKey == LogicalKeyboardKey.select ||
                              e.logicalKey == LogicalKeyboardKey.enter) {
                            Navigator.pop(ctx, true);
                            return KeyEventResult.handled;
                          }
                          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                            no.requestFocus();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(builder: (c) {
                          final f = Focus.of(c).hasFocus;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: f
                                  ? const Color(0xFFE50914)
                                  : const Color(0xFFE50914)
                                      .withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: f ? Colors.white : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text('Eliminar',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok == true) {
      await AddonManager.instance.uninstall(a.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr = AddonManager.instance;
    final list = mgr.addons;

    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: _onRootKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Addons',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Focus(
                      focusNode: _refreshFocus,
                      onKeyEvent: (n, e) {
                        if (e is! KeyDownEvent) return KeyEventResult.ignored;
                        if (e.logicalKey == LogicalKeyboardKey.select ||
                            e.logicalKey == LogicalKeyboardKey.enter) {
                          mgr.updateAll();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowDown &&
                            _itemNodes.isNotEmpty) {
                          _itemNodes.first.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(builder: (c) {
                        final f = Focus.of(c).hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: f
                                ? const Color(0xFFE50914)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: f ? Colors.white : Colors.transparent,
                              width: 2.2,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text('Actualizar',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: mgr.loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFE50914)))
                      : list.isEmpty
                          ? const Center(
                              child: Text(
                                'No hay addons instalados.\nVe a Comunidad para añadir.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 16),
                              ),
                            )
                          : ListView.separated(
                              controller: _scrollCtrl,
                              itemCount: list.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final a = list[i];
                                final node = i < _itemNodes.length
                                    ? _itemNodes[i]
                                    : FocusNode();
                                final typeLabel = a.isSource
                                    ? 'Fuente'
                                    : a.isCatalog
                                        ? 'Catálogo'
                                        : 'Función';
                                return Focus(
                                  focusNode: node,
                                  onFocusChange: (has) {
                                    if (has) _scrollToFocused(node);
                                  },
                                  onKeyEvent: (n, e) {
                                    if (e is! KeyDownEvent) {
                                      return KeyEventResult.ignored;
                                    }
                                    final key = e.logicalKey;
                                    if (key == LogicalKeyboardKey.select ||
                                        key == LogicalKeyboardKey.enter) {
                                      mgr.setEnabled(a.id, !a.enabled);
                                      return KeyEventResult.handled;
                                    }
                                    if (key == LogicalKeyboardKey.arrowUp) {
                                      if (i == 0) {
                                        _refreshFocus.requestFocus();
                                      } else {
                                        _itemNodes[i - 1].requestFocus();
                                      }
                                      return KeyEventResult.handled;
                                    }
                                    if (key == LogicalKeyboardKey.arrowDown) {
                                      if (i + 1 < _itemNodes.length) {
                                        _itemNodes[i + 1].requestFocus();
                                      }
                                      return KeyEventResult.handled;
                                    }
                                    if (key == LogicalKeyboardKey.delete ||
                                        key == LogicalKeyboardKey.backspace) {
                                      _confirmDelete(a);
                                      return KeyEventResult.handled;
                                    }
                                    if (key == LogicalKeyboardKey.goBack ||
                                        key == LogicalKeyboardKey.escape) {
                                      Navigator.of(context).maybePop();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: Builder(builder: (c) {
                                    final f = Focus.of(c).hasFocus;
                                    return AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 120),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: f
                                            ? const Color(0xFF2A2A2E)
                                            : const Color(0xFF1C1C1E),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: f
                                              ? Colors.white
                                              : Colors.transparent,
                                          width: 2.2,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            a.isSource
                                                ? Icons.source_rounded
                                                : a.isCatalog
                                                    ? Icons.grid_view_rounded
                                                    : Icons.extension_rounded,
                                            color: a.enabled
                                                ? const Color(0xFFE50914)
                                                : Colors.white38,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  a.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$typeLabel · v${a.version}${a.enabled ? '' : ' · desactivado'}',
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.5),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch(
                                            value: a.enabled,
                                            activeColor:
                                                const Color(0xFFE50914),
                                            onChanged: (v) =>
                                                mgr.setEnabled(a.id, v),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
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
}
