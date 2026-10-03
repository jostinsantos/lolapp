import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/addons/addon_manager.dart';
import '../../../../data/addons/models/addon.dart';
import '../../../../data/addons/services/community_service.dart';

/// Página TV dedicada: Comunidad (fuentes/catálogos desde Git).
class TvAddonsComunidadPage extends StatefulWidget {
  const TvAddonsComunidadPage({super.key});

  @override
  State<TvAddonsComunidadPage> createState() => _TvAddonsComunidadPageState();
}

class _TvAddonsComunidadPageState extends State<TvAddonsComunidadPage> {
  final _svc = CommunityService();
  final FocusNode _rootFocus = FocusNode(debugLabel: 'tv_comunidad_root');
  final FocusNode _manualFocus = FocusNode(debugLabel: 'tv_comunidad_manual');
  final FocusNode _tabSources = FocusNode(debugLabel: 'tab_sources');
  final FocusNode _tabCatalogs = FocusNode(debugLabel: 'tab_catalogs');

  List<CommunityAddonItem> _sources = [];
  List<CommunityAddonItem> _catalogs = [];
  bool _loading = true;
  String? _error;
  final Set<String> _installing = {};
  int _tab = 0; // 0 = fuentes, 1 = catálogos
  List<FocusNode> _itemNodes = [];
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rootFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    _manualFocus.dispose();
    _tabSources.dispose();
    _tabCatalogs.dispose();
    _scrollCtrl.dispose();
    for (final n in _itemNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _svc.fetchAll();
      if (!mounted) return;
      setState(() {
        _sources = r.sources;
        _catalogs = r.catalogs;
        _loading = false;
      });
      _rebuildItemNodes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _sources = _svc.recommended(type: 'source');
        _catalogs = _svc.recommended(type: 'catalog');
      });
      _rebuildItemNodes();
    }
  }

  void _rebuildItemNodes() {
    for (final n in _itemNodes) {
      n.dispose();
    }
    final list = _tab == 0 ? _sources : _catalogs;
    _itemNodes = List.generate(
      list.length,
      (i) => FocusNode(debugLabel: 'com_item_$i'),
    );
  }

  List<CommunityAddonItem> get _currentList =>
      _tab == 0 ? _sources : _catalogs;


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

  Future<void> _installItem(CommunityAddonItem item) async {
    if (_installing.contains(item.repo)) return;
    setState(() => _installing.add(item.repo));
    try {
      final type =
          item.type == 'catalog' ? AddonType.catalog : AddonType.source;
      final m = await AddonManager.instance.installFromGitHub(
        repoOrUrl: item.repo.trim(),
        type: type,
      );
      await AddonManager.instance.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Instalado: ${m.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _installing.remove(item.repo));
    }
  }

  Future<void> _showManualInstall() async {
    final ctrl = TextEditingController();
    AddonType type = AddonType.source;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return Dialog(
            backgroundColor: const Color(0xFF1A1A1F),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Instalar manual (owner/repo)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'usuario/repositorio',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Fuente'),
                        selected: type == AddonType.source,
                        selectedColor: const Color(0xFFE50914),
                        labelStyle: TextStyle(
                          color: type == AddonType.source
                              ? Colors.white
                              : Colors.white70,
                        ),
                        onSelected: (_) =>
                            setLocal(() => type = AddonType.source),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Catálogo'),
                        selected: type == AddonType.catalog,
                        selectedColor: const Color(0xFFE50914),
                        labelStyle: TextStyle(
                          color: type == AddonType.catalog
                              ? Colors.white
                              : Colors.white70,
                        ),
                        onSelected: (_) =>
                            setLocal(() => type = AddonType.catalog),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar',
                              style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Instalar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    try {
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {}
    if (ok == true && mounted) {
      final input = ctrl.text.trim();
      if (input.isNotEmpty) {
        setState(() => _installing.add(input));
        try {
          final m = await AddonManager.instance.installFromGitHub(
            repoOrUrl: input,
            type: type,
          );
          await AddonManager.instance.reload();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Instalado: ${m.name}')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        } finally {
          if (mounted) setState(() => _installing.remove(input));
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  }

  void _switchTab(int t) {
    if (_tab == t) return;
    setState(() {
      _tab = t;
      _rebuildItemNodes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _currentList;

    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.goBack ||
            e.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comunidad',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                // Tabs + manual
                Row(
                  children: [
                    _tabChip(
                      focus: _tabSources,
                      label: 'Fuentes',
                      selected: _tab == 0,
                      onSelect: () => _switchTab(0),
                      onRight: () => _tabCatalogs.requestFocus(),
                      onDown: () {
                        if (_itemNodes.isNotEmpty) {
                          _itemNodes.first.requestFocus();
                        } else {
                          _manualFocus.requestFocus();
                        }
                      },
                    ),
                    const SizedBox(width: 10),
                    _tabChip(
                      focus: _tabCatalogs,
                      label: 'Catálogos',
                      selected: _tab == 1,
                      onSelect: () => _switchTab(1),
                      onLeft: () => _tabSources.requestFocus(),
                      onRight: () => _manualFocus.requestFocus(),
                      onDown: () {
                        if (_itemNodes.isNotEmpty) {
                          _itemNodes.first.requestFocus();
                        } else {
                          _manualFocus.requestFocus();
                        }
                      },
                    ),
                    const Spacer(),
                    Focus(
                      focusNode: _manualFocus,
                      onKeyEvent: (n, e) {
                        if (e is! KeyDownEvent) return KeyEventResult.ignored;
                        if (e.logicalKey == LogicalKeyboardKey.select ||
                            e.logicalKey == LogicalKeyboardKey.enter) {
                          _showManualInstall();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          _tabCatalogs.requestFocus();
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
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: f
                                ? const Color(0xFFE50914)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: f ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text('Manual',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFE50914)))
                      : list.isEmpty
                          ? Center(
                              child: Text(
                                _error ??
                                    'No hay elementos en la comunidad por ahora.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 15),
                              ),
                            )
                          : ListView.separated(
                              controller: _scrollCtrl,
                              itemCount: list.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final item = list[i];
                                final node = i < _itemNodes.length
                                    ? _itemNodes[i]
                                    : FocusNode();
                                final installing =
                                    _installing.contains(item.repo);
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
                                      if (!installing) _installItem(item);
                                      return KeyEventResult.handled;
                                    }
                                    if (key == LogicalKeyboardKey.arrowUp) {
                                      if (i == 0) {
                                        _tabSources.requestFocus();
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
                                            _tab == 0
                                                ? Icons.source_rounded
                                                : Icons.grid_view_rounded,
                                            color: const Color(0xFFE50914),
                                            size: 26,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.repo,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.5),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (installing)
                                            const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFFE50914),
                                              ),
                                            )
                                          else
                                            const Icon(
                                              Icons.download_rounded,
                                              color: Colors.white54,
                                              size: 22,
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

  Widget _tabChip({
    required FocusNode focus,
    required String label,
    required bool selected,
    required VoidCallback onSelect,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onDown,
  }) {
    return Focus(
      focusNode: focus,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter) {
          onSelect();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowLeft && onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowRight && onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown && onDown != null) {
          onDown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (c) {
        final f = Focus.of(c).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE50914)
                : (f
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: f && !selected ? Colors.white54 : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: selected || f ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        );
      }),
    );
  }
}
