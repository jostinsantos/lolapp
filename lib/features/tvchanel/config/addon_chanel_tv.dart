import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/addons/services/community_service.dart';
import '../data/tvchanel_repository.dart';
import '../models/tv_channel_models.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF1C1C1E);

/// Addons de Canales TV — solo comunidad (topic lol-tvchanel) + manual GitHub.
/// Navegación D-pad: ↑↓ entre ítems, ← atrás, OK/Select acción, long-press menú.
class AddonChanelTv extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  const AddonChanelTv({super.key, this.onRequestMenuFocus});
  @override
  State<AddonChanelTv> createState() => _AddonChanelTvState();
}

class _AddonChanelTvState extends State<AddonChanelTv> {
  final _repo = TvChanelRepository.instance;
  final _community = CommunityService();

  List<TvAddon> _installed = [];
  List<CommunityAddonItem> _communityList = [];
  bool _loading = true;
  bool _loadingCommunity = true;
  final Set<String> _installing = {};

  // 0 = header buttons, 1 = instalados, 2 = comunidad
  int _section = 0;
  int _headerIndex = 0; // 0 manual, 1 refresh

  final FocusNode _rootFocus = FocusNode(debugLabel: 'addon_tv_root');
  final FocusNode _manualFocus = FocusNode(debugLabel: 'addon_tv_manual');
  final FocusNode _refreshFocus = FocusNode(debugLabel: 'addon_tv_refresh');
  List<FocusNode> _installedNodes = [];
  List<FocusNode> _communityNodes = [];
  final ScrollController _instScroll = ScrollController();
  final ScrollController _comScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadAll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _manualFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    _manualFocus.dispose();
    _refreshFocus.dispose();
    _instScroll.dispose();
    _comScroll.dispose();
    for (final n in [..._installedNodes, ..._communityNodes]) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final installed = await _repo.loadAddons();
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _loading = false;
      });
      _rebuildInstalledNodes();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    _loadCommunity();
  }

  Future<void> _loadCommunity() async {
    setState(() => _loadingCommunity = true);
    try {
      final list = await _community.fetchTvChanelAddons();
      if (!mounted) return;
      setState(() {
        _communityList = list;
        _loadingCommunity = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _communityList = [];
        _loadingCommunity = false;
      });
    }
    _rebuildCommunityNodes();
  }

  void _rebuildInstalledNodes() {
    for (final n in _installedNodes) {
      n.dispose();
    }
    _installedNodes = List.generate(
      _installed.length,
      (i) => FocusNode(debugLabel: 'tv_inst_$i'),
    );
  }

  void _rebuildCommunityNodes() {
    for (final n in _communityNodes) {
      n.dispose();
    }
    _communityNodes = List.generate(
      _communityList.length,
      (i) => FocusNode(debugLabel: 'tv_com_$i'),
    );
  }

  bool _isInstalled(String repo) {
    final key = repo.toLowerCase().split('/').last;
    return _installed.any((a) =>
        a.manifest.id.toLowerCase().contains(key) ||
        a.folderPath.toLowerCase().contains(key));
  }

  Future<void> _installRepo(String ownerRepo) async {
    final key = ownerRepo.trim();
    if (key.isEmpty) return;
    setState(() => _installing.add(key));
    try {
      await _repo.installFromGithub(key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Addon instalado: $key'),
        backgroundColor: Colors.green.shade700,
      ));
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red.shade800,
      ));
    } finally {
      if (mounted) setState(() => _installing.remove(key));
    }
  }

  Future<void> _showInstalledActions(TvAddon addon) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => _ActionModal(
        title: addon.manifest.name,
        subtitle: '${addon.totalChannels} canales · v${addon.manifest.version}',
        actions: const [
          _ActionItem(id: 'delete', label: 'Eliminar', icon: Icons.delete_outline, danger: true),
        ],
      ),
    );
    if (action == 'delete') {
      await _repo.deleteAddon(addon.folderPath);
      await _loadAll();
      if (_manualFocus.canRequestFocus) _manualFocus.requestFocus();
    }
  }

  Future<void> _showCommunityActions(CommunityAddonItem item) async {
    final installed = _isInstalled(item.repo);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => _ActionModal(
        title: item.name,
        subtitle: item.repo,
        actions: [
          if (!installed)
            const _ActionItem(id: 'install', label: 'Instalar', icon: Icons.download_rounded)
          else
            const _ActionItem(id: 'reinstall', label: 'Reinstalar', icon: Icons.refresh_rounded),
        ],
      ),
    );
    if (action == 'install' || action == 'reinstall') {
      await _installRepo(item.repo);
    }
  }

  void _openManualModal() {
    final ownerCtrl = TextEditingController();
    final repoCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Instalar desde GitHub',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Topic: lol-tvchanel\nEjemplo: owner / repo',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ownerCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDeco('Owner', 'usuario'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: repoCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDeco('Repositorio', 'mi-addon'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
            onPressed: () {
              final o = ownerCtrl.text.trim();
              final r = repoCtrl.text.trim();
              if (o.isEmpty || r.isEmpty) return;
              Navigator.pop(ctx);
              _installRepo('$o/$r');
            },
            child: const Text('Instalar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).whenComplete(() {
      ownerCtrl.dispose();
      repoCtrl.dispose();
    });
  }

  InputDecoration _fieldDeco(String label, String hint) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _kAccent)),
      );

  void _goBack() {
    widget.onRequestMenuFocus?.call();
    Navigator.of(context).maybePop();
  }

  void _ensureVisible(FocusNode node, ScrollController? scroll) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: 0.3,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.goBack ||
            e.logicalKey == LogicalKeyboardKey.escape) {
          _goBack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E12),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Addons de Canales',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _HeaderBtn(
                      focusNode: _manualFocus,
                      icon: Icons.add_box_rounded,
                      label: 'GitHub manual',
                      onTap: _openManualModal,
                      onKeyExtra: (key) {
                        if (key == LogicalKeyboardKey.arrowRight) {
                          _refreshFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowDown) {
                          if (_installedNodes.isNotEmpty) {
                            _installedNodes.first.requestFocus();
                            _ensureVisible(_installedNodes.first, _instScroll);
                          } else if (_communityNodes.isNotEmpty) {
                            _communityNodes.first.requestFocus();
                            _ensureVisible(_communityNodes.first, _comScroll);
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
                    ),
                    const SizedBox(width: 10),
                    _HeaderBtn(
                      focusNode: _refreshFocus,
                      icon: Icons.refresh_rounded,
                      label: 'Actualizar',
                      onTap: _loadAll,
                      onKeyExtra: (key) {
                        if (key == LogicalKeyboardKey.arrowLeft) {
                          _manualFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowDown) {
                          if (_communityNodes.isNotEmpty) {
                            _communityNodes.first.requestFocus();
                            _ensureVisible(_communityNodes.first, _comScroll);
                          } else if (_installedNodes.isNotEmpty) {
                            _installedNodes.first.requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Topic: lol-tvchanel  ·  OK = acción  ·  Mantén OK = menú  ·  ↑↓ navegar',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: _kAccent))
                      : Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Instalados (${_installed.length})',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: _installed.isEmpty
                                        ? Center(child: Text('Ningún addon instalado',
                                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4))))
                                        : ListView.separated(
                                            controller: _instScroll,
                                            itemCount: _installed.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                                            itemBuilder: (_, i) {
                                              final a = _installed[i];
                                              final node = i < _installedNodes.length
                                                  ? _installedNodes[i]
                                                  : FocusNode();
                                              return _NavCard(
                                                focusNode: node,
                                                onSelect: () => _showInstalledActions(a),
                                                onLong: () => _showInstalledActions(a),
                                                onUp: () {
                                                  if (i > 0) {
                                                    _installedNodes[i - 1].requestFocus();
                                                    _ensureVisible(_installedNodes[i - 1], _instScroll);
                                                  } else {
                                                    _manualFocus.requestFocus();
                                                  }
                                                },
                                                onDown: () {
                                                  if (i < _installedNodes.length - 1) {
                                                    _installedNodes[i + 1].requestFocus();
                                                    _ensureVisible(_installedNodes[i + 1], _instScroll);
                                                  }
                                                },
                                                onLeft: _goBack,
                                                onRight: () {
                                                  if (_communityNodes.isNotEmpty) {
                                                    final j = i.clamp(0, _communityNodes.length - 1);
                                                    _communityNodes[j].requestFocus();
                                                    _ensureVisible(_communityNodes[j], _comScroll);
                                                  }
                                                },
                                                child: _InstalledRow(addon: a),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Comunidad (lol-tvchanel)',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: _loadingCommunity
                                        ? const Center(child: CircularProgressIndicator(color: _kAccent))
                                        : _communityList.isEmpty
                                            ? Center(
                                                child: Text(
                                                  'No hay addons en la comunidad.\nUsa “GitHub manual” o publica un repo con topic lol-tvchanel.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                                                ),
                                              )
                                            : ListView.separated(
                                                controller: _comScroll,
                                                itemCount: _communityList.length,
                                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                                itemBuilder: (_, i) {
                                                  final item = _communityList[i];
                                                  final node = i < _communityNodes.length
                                                      ? _communityNodes[i]
                                                      : FocusNode();
                                                  final installed = _isInstalled(item.repo);
                                                  final busy = _installing.contains(item.repo);
                                                  return _NavCard(
                                                    focusNode: node,
                                                    onSelect: () {
                                                      if (busy) return;
                                                      if (installed) {
                                                        _showCommunityActions(item);
                                                      } else {
                                                        _installRepo(item.repo);
                                                      }
                                                    },
                                                    onLong: () => _showCommunityActions(item),
                                                    onUp: () {
                                                      if (i > 0) {
                                                        _communityNodes[i - 1].requestFocus();
                                                        _ensureVisible(_communityNodes[i - 1], _comScroll);
                                                      } else {
                                                        _refreshFocus.requestFocus();
                                                      }
                                                    },
                                                    onDown: () {
                                                      if (i < _communityNodes.length - 1) {
                                                        _communityNodes[i + 1].requestFocus();
                                                        _ensureVisible(_communityNodes[i + 1], _comScroll);
                                                      }
                                                    },
                                                    onLeft: () {
                                                      if (_installedNodes.isNotEmpty) {
                                                        final j = i.clamp(0, _installedNodes.length - 1);
                                                        _installedNodes[j].requestFocus();
                                                        _ensureVisible(_installedNodes[j], _instScroll);
                                                      } else {
                                                        _goBack();
                                                      }
                                                    },
                                                    child: _CommunityRow(
                                                      item: item,
                                                      installed: installed,
                                                      installing: busy,
                                                    ),
                                                  );
                                                },
                                              ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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

// ─── widgets ───────────────────────────────────────────────

class _HeaderBtn extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final KeyEventResult Function(LogicalKeyboardKey key)? onKeyExtra;

  const _HeaderBtn({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onKeyExtra,
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
        return onKeyExtra?.call(k) ?? KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final f = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: f ? _kAccent : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
      }),
    );
  }
}

/// Card con foco D-pad + long press para menú
class _NavCard extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback onLong;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final Widget child;

  const _NavCard({
    required this.focusNode,
    required this.onSelect,
    required this.onLong,
    required this.onUp,
    required this.onDown,
    this.onLeft,
    this.onRight,
    required this.child,
  });

  @override
  State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
  DateTime? _keyDownAt;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (n, e) {
        final k = e.logicalKey;
        if (e is KeyDownEvent) {
          if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
            _keyDownAt = DateTime.now();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowUp) {
            widget.onUp();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowDown) {
            widget.onDown();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
            widget.onLeft?.call();
            return KeyEventResult.handled;
          }
        }
        if (e is KeyUpEvent) {
          if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
            final start = _keyDownAt;
            _keyDownAt = null;
            if (start != null) {
              final ms = DateTime.now().difference(start).inMilliseconds;
              if (ms >= 450) {
                widget.onLong();
              } else {
                widget.onSelect();
              }
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final f = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: widget.onSelect,
          onLongPress: widget.onLong,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: f ? Colors.white : Colors.white10,
                width: f ? 2.4 : 1,
              ),
            ),
            child: widget.child,
          ),
        );
      }),
    );
  }
}

class _InstalledRow extends StatelessWidget {
  final TvAddon addon;
  const _InstalledRow({required this.addon});

  @override
  Widget build(BuildContext context) {
    final logo = addon.manifest.logoPath;
    final isUrl = logo.startsWith('http');
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44, height: 44,
          child: isUrl
              ? Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _icon())
              : (logo.isNotEmpty && !logo.endsWith('.nologo')
                  ? Image.file(File(logo), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _icon())
                  : _icon()),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(addon.manifest.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          Text('${addon.totalChannels} canales · v${addon.manifest.version}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
        ]),
      ),
      Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.35)),
    ]);
  }

  Widget _icon() => Container(
        color: _kAccent.withValues(alpha: 0.15),
        child: const Icon(Icons.live_tv, color: _kAccent),
      );
}

class _CommunityRow extends StatelessWidget {
  final CommunityAddonItem item;
  final bool installed;
  final bool installing;
  const _CommunityRow({required this.item, required this.installed, required this.installing});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: _kAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.tv, color: _kAccent),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          Text(item.repo, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          if (item.description.isNotEmpty)
            Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
        ]),
      ),
      if (installing)
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent))
      else if (installed)
        const Icon(Icons.check_circle, color: Colors.greenAccent)
      else
        Icon(Icons.download_rounded, color: Colors.white.withValues(alpha: 0.5)),
    ]);
  }
}

class _ActionItem {
  final String id;
  final String label;
  final IconData icon;
  final bool danger;
  const _ActionItem({required this.id, required this.label, required this.icon, this.danger = false});
}

class _ActionModal extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<_ActionItem> actions;
  const _ActionModal({required this.title, this.subtitle, required this.actions});

  @override
  State<_ActionModal> createState() => _ActionModalState();
}

class _ActionModalState extends State<_ActionModal> {
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _nodes = List.generate(widget.actions.length + 1, (i) => FocusNode(debugLabel: 'act_$i'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_nodes.isNotEmpty) _nodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(widget.subtitle!,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          ],
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.actions.length; i++) ...[
            _modalBtn(
              node: _nodes[i],
              label: widget.actions[i].label,
              icon: widget.actions[i].icon,
              danger: widget.actions[i].danger,
              onTap: () => Navigator.pop(context, widget.actions[i].id),
              onUp: () {
                if (i > 0) _nodes[i - 1].requestFocus();
              },
              onDown: () {
                if (i < _nodes.length - 1) _nodes[i + 1].requestFocus();
              },
            ),
            const SizedBox(height: 8),
          ],
          _modalBtn(
            node: _nodes.last,
            label: 'Cancelar',
            icon: Icons.close,
            onTap: () => Navigator.pop(context),
            onUp: () {
              if (_nodes.length > 1) _nodes[_nodes.length - 2].requestFocus();
            },
            onDown: () {},
          ),
        ],
      ),
    );
  }

  Widget _modalBtn({
    required FocusNode node,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required VoidCallback onUp,
    required VoidCallback onDown,
    bool danger = false,
  }) {
    return Focus(
      focusNode: node,
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
                  ? (danger ? Colors.red.withValues(alpha: 0.25) : _kAccent.withValues(alpha: 0.25))
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: f ? (danger ? Colors.redAccent : Colors.white) : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(children: [
              Icon(icon, color: danger ? Colors.redAccent : Colors.white, size: 20),
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
