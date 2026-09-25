import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_config_shared.dart';
import 'content/tv_content_tab.dart';
import 'updates/tv_updates_tab.dart';
import 'sources/tv_sources_tab.dart';
import 'appearance/tv_appearance_tab.dart';
import 'cache/tv_cache_tab.dart';
import 'player/tv_player_tab.dart';
enum _ConfigTab {
  contenido,
  actualizaciones,
  fuentes,
  apariencia,
  cache,
  player,
}

/// Página de configuración (shell de tabs).
/// Cada pestaña es un widget independiente con su propio estado.
class ConfigPage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const ConfigPage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<ConfigPage> createState() => ConfigPageState();
}

class ConfigPageState extends State<ConfigPage>
    with AutomaticKeepAliveClientMixin {
  _ConfigTab _tab = _ConfigTab.contenido;
  bool _movingFocusToContent = false;
  String _menuPosition = 'top';

  late final List<FocusNode> _tabNodes;
  final ScrollController _scroll = ScrollController();

  final GlobalKey<ContenidoTabState> _contenidoKey = GlobalKey();
  final GlobalKey<ActualizacionesTabState> _actualizacionesKey = GlobalKey();
  final GlobalKey<FuentesTabState> _fuentesKey = GlobalKey();
  final GlobalKey<AparienciaTabState> _aparienciaKey = GlobalKey();
  final GlobalKey<CacheTabState> _cacheKey = GlobalKey();
  final GlobalKey<PlayerTabState> _playerKey = GlobalKey();

  static const _tabLabels = [
    'Contenido',
    'Actualizaciones',
    'Fuentes',
    'Apariencia',
    'Caché',
    'Player',
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabNodes = List.generate(
      _tabLabels.length,
      (i) => FocusNode(debugLabel: 'cfg_tab_$i'),
    );
    MenuPositionPref.get().then((v) {
      if (mounted) setState(() => _menuPosition = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMainFocusNodeCreated?.call(_tabNodes[0]);
    });
  }

  @override
  void dispose() {
    for (final n in _tabNodes) {
      n.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void refresh() {
    _actualizacionesKey.currentState?.refresh();
  }

  void _focusCurrentTab() {
    final i = _tab.index;
    if (i >= 0 && i < _tabNodes.length) {
      _tabNodes[i].requestFocus();
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _selectTab(int index, {bool focusContent = false}) {
    final tab =
        _ConfigTab.values[index.clamp(0, _ConfigTab.values.length - 1)];
    final changed = _tab != tab;
    if (changed) {
      setState(() => _tab = tab);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    if (focusContent) {
      _enterTabContent(tab, afterRebuild: changed);
    }
  }

  void _enterTabContent(_ConfigTab tab, {bool afterRebuild = false}) {
    Future<void> focusWhenReady() async {
      final waits = afterRebuild ? 3 : 1;
      for (var i = 0; i < waits; i++) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      if (!mounted || _tab != tab) return;

      final state = _stateFor(tab);
      if (state != null) {
        state.requestFirstFocus();
        _movingFocusToContent = false;
      }
    }

    if (_tab != tab) {
      setState(() => _tab = tab);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    focusWhenReady();
  }

  dynamic _stateFor(_ConfigTab tab) {
    switch (tab) {
      case _ConfigTab.contenido:
        return _contenidoKey.currentState;
      case _ConfigTab.actualizaciones:
        return _actualizacionesKey.currentState;
      case _ConfigTab.fuentes:
        return _fuentesKey.currentState;
      case _ConfigTab.apariencia:
        return _aparienciaKey.currentState;
      case _ConfigTab.cache:
        return _cacheKey.currentState;
      case _ConfigTab.player:
        return _playerKey.currentState;
    }
  }

  Widget _buildBody() {
    switch (_tab) {
      case _ConfigTab.contenido:
        return ContenidoTab(
          key: _contenidoKey,
          onRequestTabFocus: _focusCurrentTab,
        );
      case _ConfigTab.actualizaciones:
        return ActualizacionesTab(
          key: _actualizacionesKey,
          onRequestTabFocus: _focusCurrentTab,
        );
      case _ConfigTab.fuentes:
        return FuentesTab(
          key: _fuentesKey,
          onRequestTabFocus: _focusCurrentTab,
        );
      case _ConfigTab.apariencia:
        return AparienciaTab(
          key: _aparienciaKey,
          onRequestTabFocus: _focusCurrentTab,
          onMenuPositionChanged: (v) {
            if (mounted) setState(() => _menuPosition = v);
          },
        );
      case _ConfigTab.cache:
        return CacheTab(
          key: _cacheKey,
          onRequestTabFocus: _focusCurrentTab,
        );
      case _ConfigTab.player:
        return PlayerTab(
          key: _playerKey,
          onRequestTabFocus: _focusCurrentTab,
        );
    }
  }

  Widget _buildTopTabs() {
    return Container(
      color: const Color(0xFF121214),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: List.generate(_tabLabels.length, (i) {
          final selected = _tab.index == i;
          final tabEnum = _ConfigTab.values[i];
          return Expanded(
            child: Focus(
              focusNode: _tabNodes[i],
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (i < _tabNodes.length - 1) {
                    _selectTab(i + 1);
                    _tabNodes[i + 1].requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  if (i > 0) {
                    _selectTab(i - 1);
                    _tabNodes[i - 1].requestFocus();
                  }
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  _movingFocusToContent = true;
                  final needRebuild = _tab != tabEnum;
                  if (needRebuild) {
                    setState(() => _tab = tabEnum);
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  }
                  _enterTabContent(tabEnum, afterRebuild: needRebuild);
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  widget.onRequestMenuFocus?.call();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              onFocusChange: (hasFocus) {
                if (!hasFocus) return;
                if (_movingFocusToContent) {
                  _movingFocusToContent = false;
                  return;
                }
                _selectTab(i);
              },
              child: Builder(
                builder: (context) {
                  final hasFocus = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: () {
                      _movingFocusToContent = true;
                      _selectTab(i, focusContent: true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: hasFocus
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: selected || hasFocus
                                ? kConfigAccent
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        _tabLabels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected || hasFocus
                              ? Colors.white
                              : Colors.white60,
                          fontSize: 14,
                          fontWeight: selected || hasFocus
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topPad = _menuPosition == 'top' ? 56.0 : 8.0;
    return Scaffold(
      backgroundColor: kConfigBg,
      body: Padding(
        padding: EdgeInsets.only(top: topPad),
        child: Column(
          children: [
            _buildTopTabs(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
