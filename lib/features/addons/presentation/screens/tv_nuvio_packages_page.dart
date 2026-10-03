import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/addons/addon_manager.dart';
import '../../../../data/addons/models/addon.dart';

/// Paquete Nuvio precargado (catálogo oficial).
class _NuvioRepo {
  final String name;
  final String author;
  final String manifestUrl;
  final List<String> langs;

  const _NuvioRepo({
    required this.name,
    required this.author,
    required this.manifestUrl,
    required this.langs,
  });
}

const _kRepos = <_NuvioRepo>[
  _NuvioRepo(
    name: 'D3adlyRocket',
    author: 'D3adlyRocket',
    manifestUrl:
        'https://raw.githubusercontent.com/D3adlyRocket/All-in-One-Nuvio/refs/heads/main/manifest.json',
    langs: ['en', 'hi'],
  ),
  _NuvioRepo(
    name: 'Yoru',
    author: 'yoruix',
    manifestUrl:
        'https://raw.githubusercontent.com/yoruix/nuvio-providers/refs/heads/main/manifest.json',
    langs: ['en'],
  ),
  _NuvioRepo(
    name: 'Phisher',
    author: 'phisher98',
    manifestUrl:
        'https://raw.githubusercontent.com/phisher98/phisher-nuvio-providers/refs/heads/main/manifest.json',
    langs: ['en'],
  ),
  _NuvioRepo(
    name: 'Michat88',
    author: 'michat88',
    manifestUrl:
        'https://raw.githubusercontent.com/michat88/nuvio-providers/refs/heads/main/manifest.json',
    langs: ['en', 'id'],
  ),
  _NuvioRepo(
    name: 'Spidey',
    author: 'Abinanthankv',
    manifestUrl:
        'https://raw.githubusercontent.com/Abinanthankv/NuvioRepo/refs/heads/master/manifest.json',
    langs: ['ta', 'en'],
  ),
  _NuvioRepo(
    name: 'Nvmindl',
    author: 'nvmindl',
    manifestUrl:
        'https://raw.githubusercontent.com/nvmindl/nuvio-providers/refs/heads/main/manifest.json',
    langs: ['ar', 'en', 'ja'],
  ),
  _NuvioRepo(
    name: 'Saimuelbr',
    author: 'saimuelbr',
    manifestUrl:
        'https://raw.githubusercontent.com/saimuelbr/saimuel-nuvio-repo/refs/heads/main/manifest.json',
    langs: ['pt'],
  ),
  _NuvioRepo(
    name: 'Easystreams',
    author: 'realbestia1',
    manifestUrl:
        'https://raw.githubusercontent.com/realbestia1/nuvio-providers-it/refs/heads/main/manifest.json',
    langs: ['it'],
  ),
  _NuvioRepo(
    name: 'Gowaru',
    author: 'Gowaru',
    manifestUrl:
        'https://raw.githubusercontent.com/Gowaru/gowaru-nuvio-providers/refs/heads/main/manifest.json',
    langs: ['fr'],
  ),
  _NuvioRepo(
    name: 'MoonCrown',
    author: 'mooncrown04',
    manifestUrl:
        'https://raw.githubusercontent.com/mooncrown04/nuviotr/refs/heads/main/manifest.json',
    langs: ['tr'],
  ),
  _NuvioRepo(
    name: 'KennethJYS',
    author: 'KennethJYS',
    manifestUrl:
        'https://raw.githubusercontent.com/KennethJYS/Nuvio-Providers-Latino/refs/heads/main/manifest.json',
    langs: ['es'],
  ),
  _NuvioRepo(
    name: 'Iamtoxiic',
    author: 'iamtoxiic',
    manifestUrl:
        'https://raw.githubusercontent.com/saimuelbr/saimuel-nuvio-repo/refs/heads/main/manifest.json',
    langs: ['fr'],
  ),
];

/// Página TV: lista de manifests Nuvio.
/// Select → carga y abre modal con plugins.
/// Cada fila: Descargar + Borrar. Si ya está: badge Instalado.
class TvNuvioPackagesPage extends StatefulWidget {
  const TvNuvioPackagesPage({super.key});

  @override
  State<TvNuvioPackagesPage> createState() => _TvNuvioPackagesPageState();
}

class _TvNuvioPackagesPageState extends State<TvNuvioPackagesPage> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  String? _progress;
  String? _langFilter;

  final FocusNode _rootFocus = FocusNode(debugLabel: 'tv_nuvio_root');
  final FocusNode _filterFocus = FocusNode(debugLabel: 'tv_nuvio_filter');
  final FocusNode _addFocus = FocusNode(debugLabel: 'tv_nuvio_add');
  final ScrollController _scrollCtrl = ScrollController();
  List<FocusNode> _repoNodes = [];

  List<_NuvioRepo> get _filteredRepos {
    if (_langFilter == null || _langFilter!.isEmpty) return _kRepos;
    final lang = _langFilter!.toLowerCase();
    return _kRepos
        .where((r) => r.langs.any((l) => l.toLowerCase() == lang))
        .toList();
  }

  Set<String> get _allLangs {
    final s = <String>{};
    for (final r in _kRepos) {
      s.addAll(r.langs.map((e) => e.toLowerCase()));
    }
    return s;
  }

  /// Busca paquete instalado por URL o nombre.
  SourcePackage? _findInstalled(_NuvioRepo r) {
    final pkgs = AddonManager.instance.packages;
    for (final p in pkgs) {
      try {
        final url = (p as dynamic).url?.toString() ??
            (p as dynamic).manifestUrl?.toString() ??
            '';
        if (url.isNotEmpty &&
            (url == r.manifestUrl || url.contains(r.author))) {
          return p;
        }
      } catch (_) {}
      if (p.name.toLowerCase() == r.name.toLowerCase() ||
          p.name.toLowerCase().contains(r.author.toLowerCase())) {
        return p;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    AddonManager.instance.init().then((_) {
      if (mounted) setState(() {});
    });
    AddonManager.instance.addListener(_onChange);
    _rebuildRepoNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filterFocus.requestFocus();
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AddonManager.instance.removeListener(_onChange);
    _urlCtrl.dispose();
    _rootFocus.dispose();
    _filterFocus.dispose();
    _addFocus.dispose();
    _scrollCtrl.dispose();
    for (final n in _repoNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _rebuildRepoNodes() {
    for (final n in _repoNodes) {
      n.dispose();
    }
    final list = _filteredRepos;
    _repoNodes = List.generate(
      list.length,
      (i) => FocusNode(debugLabel: 'repo_$i'),
    );
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

  Future<void> _openManifestModal(_NuvioRepo repo) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 'Cargando ${repo.name}…';
    });
    try {
      final pkg = await AddonManager.instance.addNuvioPackage(repo.manifestUrl);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
      });
      await _showPluginsModal(pkg, repo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _showPluginsModal(SourcePackage pkg, _NuvioRepo repo) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return _PluginsModal(
          pkg: pkg,
          repoName: repo.name,
          onChanged: () {
            if (mounted) setState(() {});
          },
        );
      },
    );
    // Tras cerrar modal, devolver foco a la lista
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final repos = _filteredRepos;
      final idx = repos.indexWhere((r) => r.manifestUrl == repo.manifestUrl);
      if (idx >= 0 && idx < _repoNodes.length) {
        _repoNodes[idx].requestFocus();
      } else {
        _filterFocus.requestFocus();
      }
    });
  }

  Future<void> _deletePackage(_NuvioRepo repo) async {
    final installed = _findInstalled(repo);
    if (installed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No está instalado')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final yes = FocusNode();
        final no = FocusNode();
        WidgetsBinding.instance.addPostFrameCallback((_) => no.requestFocus());
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1F),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '¿Borrar «${installed.name}»?',
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
                          if (e is! KeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
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
                                color:
                                    f ? Colors.white : Colors.transparent,
                                width: 2.2,
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
                          if (e is! KeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
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
                                color:
                                    f ? Colors.white : Colors.transparent,
                                width: 2.2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text('Borrar',
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
    if (ok == true && mounted) {
      try {
        // Intentar API de borrar paquete si existe
        final mgr = AddonManager.instance;
        try {
          await (mgr as dynamic).removeNuvioPackage(installed);
        } catch (_) {
          try {
            await (mgr as dynamic).deletePackage(installed);
          } catch (_) {
            try {
              await (mgr as dynamic).removePackage(installed.name);
            } catch (e) {
              debugPrint('No remove API: $e');
            }
          }
        }
        await mgr.reload();
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eliminado: ${installed.name}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al borrar: $e')),
          );
        }
      }
    }
  }

  Future<void> _showAddModal() async {
    final ctrl = TextEditingController(text: _urlCtrl.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        title: const Text('URL del manifest',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'https://…/manifest.json',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: const Color(0xFF1C1C1E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cargar',
                style: TextStyle(color: Color(0xFFE50914))),
          ),
        ],
      ),
    );
    try {
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {}
    if (ok == true && mounted) {
      final url = ctrl.text.trim();
      _urlCtrl.text = url;
      if (url.isEmpty) return;
      setState(() {
        _busy = true;
        _progress = 'Cargando…';
      });
      try {
        final pkg = await AddonManager.instance.addNuvioPackage(url);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _progress = null;
        });
        await _showPluginsModal(
          pkg,
          _NuvioRepo(
            name: pkg.name,
            author: pkg.name,
            manifestUrl: url,
            langs: const [],
          ),
        );
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  }

  Future<void> _showLangFilter() async {
    final langs = _allLangs.toList()..sort();
    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final nodes = List.generate(
          langs.length + 1,
          (i) => FocusNode(debugLabel: 'lang_$i'),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          nodes.first.requestFocus();
        });
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1F),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Filtrar por idioma',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _langTile(
                          focus: nodes[0],
                          label: 'Todos',
                          selected: _langFilter == null,
                          onTap: () => Navigator.pop(ctx, null),
                          onDown: () {
                            if (nodes.length > 1) nodes[1].requestFocus();
                          },
                        ),
                        ...List.generate(langs.length, (i) {
                          final lang = langs[i];
                          return _langTile(
                            focus: nodes[i + 1],
                            label: lang.toUpperCase(),
                            selected: _langFilter == lang,
                            onTap: () => Navigator.pop(ctx, lang),
                            onUp: () => nodes[i].requestFocus(),
                            onDown: i + 1 < langs.length
                                ? () => nodes[i + 2].requestFocus()
                                : null,
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() {
      _langFilter = selected;
      _rebuildRepoNodes();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filterFocus.requestFocus();
    });
  }

  Widget _langTile({
    required FocusNode focus,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onUp,
    VoidCallback? onDown,
  }) {
    return Focus(
      focusNode: focus,
      onFocusChange: (has) {
        if (has) _scrollToFocused(focus);
      },
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowUp && onUp != null) {
          onUp();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown && onDown != null) {
          onDown();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.goBack ||
            e.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (c) {
        final f = Focus.of(c).hasFocus;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFE50914).withValues(alpha: 0.25)
                  : (f
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: f ? Colors.white : Colors.transparent,
                width: 2.2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight:
                          f || selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check, color: Color(0xFFE50914), size: 20),
              ],
            ),
          ),
        );
      }),
    );
  }

  BoxDecoration _focusBox({required bool focused}) {
    return BoxDecoration(
      color: focused ? const Color(0xFF2A2A2E) : const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: focused ? Colors.white : Colors.transparent,
        width: 2.2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repos = _filteredRepos;

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
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Addons Nuvio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Focus(
                      focusNode: _filterFocus,
                      onKeyEvent: (n, e) {
                        if (e is! KeyDownEvent) return KeyEventResult.ignored;
                        if (e.logicalKey == LogicalKeyboardKey.select ||
                            e.logicalKey == LogicalKeyboardKey.enter) {
                          _showLangFilter();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                          _addFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (_repoNodes.isNotEmpty) {
                            _repoNodes.first.requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(builder: (c) {
                        final f = Focus.of(c).hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.filter_list,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _langFilter == null
                                    ? 'Idioma'
                                    : _langFilter!.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    Focus(
                      focusNode: _addFocus,
                      onKeyEvent: (n, e) {
                        if (e is! KeyDownEvent) return KeyEventResult.ignored;
                        if (e.logicalKey == LogicalKeyboardKey.select ||
                            e.logicalKey == LogicalKeyboardKey.enter) {
                          if (!_busy) _showAddModal();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          _filterFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (_repoNodes.isNotEmpty) {
                            _repoNodes.first.requestFocus();
                          }
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
                              width: 2.2,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_link,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text('URL',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                if (_progress != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFE50914),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(_progress!,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    itemCount: repos.length,
                    itemBuilder: (context, i) {
                      final r = repos[i];
                      final node = i < _repoNodes.length
                          ? _repoNodes[i]
                          : FocusNode();
                      final installed = _findInstalled(r);
                      final isInstalled = installed != null;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Focus(
                          focusNode: node,
                          onFocusChange: (has) {
                            if (has) _scrollToFocused(node);
                          },
                          onKeyEvent: (n, e) {
                            if (e is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final key = e.logicalKey;
                            // Select / Enter → abrir modal (descargar / ver plugins)
                            if (key == LogicalKeyboardKey.select ||
                                key == LogicalKeyboardKey.enter) {
                              if (!_busy) _openManifestModal(r);
                              return KeyEventResult.handled;
                            }
                            // Delete → borrar si instalado
                            if (key == LogicalKeyboardKey.delete ||
                                key == LogicalKeyboardKey.backspace) {
                              if (isInstalled) _deletePackage(r);
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowUp) {
                              if (i == 0) {
                                _filterFocus.requestFocus();
                              } else {
                                _repoNodes[i - 1].requestFocus();
                              }
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowDown) {
                              if (i + 1 < _repoNodes.length) {
                                _repoNodes[i + 1].requestFocus();
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
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: _focusBox(focused: f),
                              child: Row(
                                children: [
                                  Icon(
                                    isInstalled
                                        ? Icons.check_circle_rounded
                                        : Icons.inventory_2_rounded,
                                    color: isInstalled
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFFE50914),
                                    size: 26,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                r.name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isInstalled) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF4CAF50)
                                                      .withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'Instalado',
                                                  style: TextStyle(
                                                    color: Color(0xFF4CAF50),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${r.author} · ${r.langs.join(', ').toUpperCase()}',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.5),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Botón Descargar
                                  GestureDetector(
                                    onTap: _busy
                                        ? null
                                        : () => _openManifestModal(r),
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE50914)
                                            .withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.download_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  // Botón Borrar
                                  GestureDetector(
                                    onTap: isInstalled
                                        ? () => _deletePackage(r)
                                        : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isInstalled
                                            ? Colors.white
                                                .withValues(alpha: 0.12)
                                            : Colors.white
                                                .withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        color: isInstalled
                                            ? Colors.white70
                                            : Colors.white24,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
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
          ),
        ),
      ),
    );
  }
}

/// Modal con todos los plugins/scrapers del manifest.
/// Atrás cierra. Select instala uno. Botón instalar todas.
class _PluginsModal extends StatefulWidget {
  final SourcePackage pkg;
  final String repoName;
  final VoidCallback onChanged;

  const _PluginsModal({
    required this.pkg,
    required this.repoName,
    required this.onChanged,
  });

  @override
  State<_PluginsModal> createState() => _PluginsModalState();
}

class _PluginsModalState extends State<_PluginsModal> {
  bool _busy = false;
  String? _progress;
  late final FocusNode _closeFocus;
  late final FocusNode _allFocus;
  late final List<FocusNode> _nodes;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _closeFocus = FocusNode(debugLabel: 'modal_close');
    _allFocus = FocusNode(debugLabel: 'modal_all');
    _nodes = List.generate(
      widget.pkg.scrapers.length,
      (i) => FocusNode(debugLabel: 'pl_$i'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _allFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _closeFocus.dispose();
    _allFocus.dispose();
    _scroll.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _scrollTo(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = node.context;
      if (ctx == null) return;
      try {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    });
  }

  Future<void> _installOne(PackageScraper s) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 'Instalando ${s.name}…';
    });
    try {
      final m =
          await AddonManager.instance.installNuvioScraper(widget.pkg, s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Instalado: ${m.name}')),
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error ${s.name}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _installAll() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 'Instalando todas (${widget.pkg.scrapers.length})…';
    });
    try {
      final r =
          await AddonManager.instance.installAllNuvioScrapers(widget.pkg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Listo: ${r.ok} ok, ${r.fail} fallos')),
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scrapers = widget.pkg.scrapers;

    return Focus(
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.goBack ||
            e.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: const Color(0xFF141416),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.pkg.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Focus(
                      focusNode: _allFocus,
                      onKeyEvent: (n, e) {
                        if (e is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.select ||
                            e.logicalKey == LogicalKeyboardKey.enter) {
                          _installAll();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowDown &&
                            _nodes.isNotEmpty) {
                          _nodes.first.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                          _closeFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(builder: (c) {
                        final f = Focus.of(c).hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: f
                                ? const Color(0xFFE50914)
                                : const Color(0xFFE50914)
                                    .withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: f ? Colors.white : Colors.transparent,
                              width: 2.2,
                            ),
                          ),
                          child: const Text(
                            'Instalar todas',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                    ),
                    Focus(
                      focusNode: _closeFocus,
                      onKeyEvent: (n, e) {
                        if (e is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.select ||
                            e.logicalKey == LogicalKeyboardKey.enter) {
                          Navigator.pop(context);
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          _allFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowDown &&
                            _nodes.isNotEmpty) {
                          _nodes.first.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(builder: (c) {
                        final f = Focus.of(c).hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: f
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: f ? Colors.white : Colors.transparent,
                              width: 2.2,
                            ),
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white70, size: 20),
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${scrapers.length} plugins · Atrás para cerrar',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
                if (_progress != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFE50914),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _progress!,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: scrapers.length,
                    itemBuilder: (context, i) {
                      final s = scrapers[i];
                      final node = _nodes[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Focus(
                          focusNode: node,
                          onFocusChange: (has) {
                            if (has) _scrollTo(node);
                          },
                          onKeyEvent: (n, e) {
                            if (e is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final key = e.logicalKey;
                            if (key == LogicalKeyboardKey.select ||
                                key == LogicalKeyboardKey.enter) {
                              _installOne(s);
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowUp) {
                              if (i == 0) {
                                _allFocus.requestFocus();
                              } else {
                                _nodes[i - 1].requestFocus();
                              }
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowDown) {
                              if (i + 1 < _nodes.length) {
                                _nodes[i + 1].requestFocus();
                              }
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.goBack ||
                                key == LogicalKeyboardKey.escape) {
                              Navigator.pop(context);
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Builder(builder: (c) {
                            final f = Focus.of(c).hasFocus;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: f
                                    ? const Color(0xFF2A2A2E)
                                    : const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: f
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      s.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.download_rounded,
                                    color: f
                                        ? const Color(0xFFE50914)
                                        : Colors.white38,
                                    size: 20,
                                  ),
                                ],
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
          ),
        ),
      ),
    );
  }
}