import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../data/addons/addon_manager.dart';
import '../../../../data/addons/models/addon.dart';
import '../../../../data/addons/services/community_service.dart';

/// Pantalla completa de primer arranque: tienda de fuentes Comunidad + Instalar todas.
/// En TV: diseño compacto + foco con mando (D-pad / OK).
class AddonsOnboardingPage extends StatefulWidget {
  const AddonsOnboardingPage({super.key});

  static const prefKey = 'addons_onboarding_done_v1';

  static Future<bool> shouldShow() async {
    final p = await SharedPreferences.getInstance();
    return !(p.getBool(prefKey) ?? false);
  }

  static Future<void> markDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey, true);
  }

  @override
  State<AddonsOnboardingPage> createState() => _AddonsOnboardingPageState();
}

class _AddonsOnboardingPageState extends State<AddonsOnboardingPage> {
  final _community = CommunityService();
  List<CommunityAddonItem> _list = [];
  bool _loading = true;
  bool _installing = false;
  String? _status;
  final Set<String> _done = {};
  final Set<String> _failed = {};

  bool get _isTv {
    final s = MediaQuery.sizeOf(context);
    return s.shortestSide >= 600 || s.aspectRatio > 1.4;
  }

  final _installAllFocus = FocusNode(debugLabel: 'onb_install_all');
  final _skipFocus = FocusNode(debugLabel: 'onb_skip');
  final List<FocusNode> _itemFocus = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _installAllFocus.dispose();
    _skipFocus.dispose();
    for (final n in _itemFocus) {
      n.dispose();
    }
    super.dispose();
  }

  void _syncItemFocus(int count) {
    while (_itemFocus.length > count) {
      _itemFocus.removeLast().dispose();
    }
    while (_itemFocus.length < count) {
      _itemFocus.add(FocusNode(debugLabel: 'onb_item_${_itemFocus.length}'));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final r = await _community.fetchAll();
      setState(() {
        _list = r.sources;
        _loading = false;
      });
      _syncItemFocus(_list.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_list.isNotEmpty && _itemFocus.isNotEmpty) {
          _itemFocus.first.requestFocus();
        } else {
          _installAllFocus.requestFocus();
        }
      });
    } catch (e) {
      setState(() {
        _list = _community.recommended(type: 'source');
        _loading = false;
        _status = 'No se pudo cargar la tienda: $e';
      });
      _syncItemFocus(_list.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _installAllFocus.requestFocus();
      });
    }
  }

  Future<void> _installOne(CommunityAddonItem item) async {
    try {
      await AddonManager.instance.installFromGitHub(
        repoOrUrl: item.repo,
        type: AddonType.source,
      );
      _done.add(item.repo);
      _failed.remove(item.repo);
    } catch (e) {
      _failed.add(item.repo);
      debugPrint('[Onboarding] ${item.repo}: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _installAll() async {
    if (_list.isEmpty || _installing) return;
    setState(() {
      _installing = true;
      _status = 'Instalando 0/${_list.length}…';
    });
    var i = 0;
    for (final item in _list) {
      i++;
      if (!mounted) return;
      setState(() => _status = 'Instalando $i/${_list.length}: ${item.name}');
      await _installOne(item);
    }
    await AddonManager.instance.reload();
    if (!mounted) return;
    setState(() {
      _installing = false;
      _status =
          'Listo: ${_done.length} instaladas'
          '${_failed.isNotEmpty ? ', ${_failed.length} fallos' : ''}';
    });
    _skipFocus.requestFocus();
  }

  Future<void> _finish() async {
    await AddonsOnboardingPage.markDone();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tv = _isTv;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: tv ? _buildTv() : _buildMobile(),
        ),
      ),
    );
  }

  // ─── Móvil (sin cambios de diseño) ───────────────────────────────────
  Widget _buildMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Instala tus primeras fuentes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Elige addons de la comunidad (Git) para reproducir contenido. '
                'Puedes instalar todas de una vez o una por una.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              _status!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        Expanded(child: _buildList(compact: false)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: (_installing || _list.isEmpty) ? null : _installAll,
                  child: Text(
                    _installing
                        ? 'Instalando…'
                        : 'Instalar todas (${_list.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _installing ? null : _finish,
                child: Text(
                  _done.isEmpty ? 'Saltar por ahora' : 'Continuar',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── TV: header compacto + foco D-pad ────────────────────────────────
  Widget _buildTv() {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header compacto (no ocupa media pantalla)
            Row(
              children: [
                Container(
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Instala tus primeras fuentes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Addons de comunidad · usa el mando para navegar',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_status != null)
                  Flexible(
                    child: Text(
                      _status!,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildList(compact: true)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _TvFocusButton(
                    focusNode: _installAllFocus,
                    label: _installing
                        ? 'Instalando…'
                        : 'Instalar todas (${_list.length})',
                    primary: true,
                    enabled: !_installing && _list.isNotEmpty,
                    onPressed: _installAll,
                    onDown: () => _skipFocus.requestFocus(),
                    onUp: () {
                      if (_itemFocus.isNotEmpty) {
                        _itemFocus.last.requestFocus();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _TvFocusButton(
                    focusNode: _skipFocus,
                    label: _done.isEmpty ? 'Saltar' : 'Continuar',
                    primary: false,
                    enabled: !_installing,
                    onPressed: _finish,
                    onUp: () => _installAllFocus.requestFocus(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList({required bool compact}) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      );
    }
    if (_list.isEmpty) {
      return const Center(
        child: Text(
          'No hay fuentes en la comunidad por ahora.\nPuedes saltar e instalarlas después en Ajustes → Addons.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    if (compact) {
      // Grid TV: 2 columnas, filas focuseables
      return GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 10,
          childAspectRatio: 4.2,
        ),
        itemCount: _list.length,
        itemBuilder: (_, i) => _buildTvItem(i),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildMobileItem(_list[i]),
    );
  }

  Widget _buildMobileItem(CommunityAddonItem item) {
    final ok = _done.contains(item.repo);
    final fail = _failed.contains(item.repo);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: const Color(0xFF1C1C1E),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE50914).withOpacity(0.2),
        backgroundImage:
            item.logo != null ? NetworkImage(item.logo!) : null,
        child: item.logo == null
            ? const Icon(Icons.extension, color: Colors.white70)
            : null,
      ),
      title: Text(
        item.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        item.repo +
            (item.description.isNotEmpty ? '\n${item.description}' : ''),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
      ),
      isThreeLine: item.description.isNotEmpty,
      trailing: ok
          ? const Icon(Icons.check_circle, color: Color(0xFF16A34A))
          : fail
              ? const Icon(Icons.error_outline, color: Colors.orange)
              : TextButton(
                  onPressed: _installing ? null : () => _installOne(item),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Instalar'),
                ),
    );
  }

  Widget _buildTvItem(int i) {
    final item = _list[i];
    final ok = _done.contains(item.repo);
    final fail = _failed.contains(item.repo);
    final node = i < _itemFocus.length ? _itemFocus[i] : null;

    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          if (!_installing && !ok) _installOne(item);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          // última fila → botones
          final lastRowStart = _list.length - (_list.length % 2 == 0 ? 2 : 1);
          if (i >= lastRowStart) {
            _installAllFocus.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: focused
                  ? const Color(0xFF2A2A2E)
                  : const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused
                    ? const Color(0xFFE50914)
                    : Colors.white.withOpacity(0.06),
                width: focused ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFE50914).withOpacity(0.2),
                  backgroundImage:
                      item.logo != null ? NetworkImage(item.logo!) : null,
                  child: item.logo == null
                      ? const Icon(Icons.extension,
                          color: Colors.white70, size: 16)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              focused ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        item.repo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ok)
                  const Icon(Icons.check_circle,
                      color: Color(0xFF16A34A), size: 20)
                else if (fail)
                  const Icon(Icons.error_outline,
                      color: Colors.orange, size: 20)
                else
                  Text(
                    focused ? 'OK' : 'Instalar',
                    style: TextStyle(
                      color: focused
                          ? const Color(0xFFE50914)
                          : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvFocusButton extends StatelessWidget {
  const _TvFocusButton({
    required this.focusNode,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.enabled = true,
    this.onUp,
    this.onDown,
  });

  final FocusNode focusNode;
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool enabled;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if ((key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.space) &&
            enabled) {
          onPressed();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp && onUp != null) {
          onUp!();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown && onDown != null) {
          onDown!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary
                  ? (focused
                      ? const Color(0xFFFF1A1A)
                      : const Color(0xFFE50914))
                  : (focused
                      ? const Color(0xFF2A2A2E)
                      : const Color(0xFF1C1C1E)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused
                    ? Colors.white
                    : Colors.white.withOpacity(0.08),
                width: focused ? 2 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          );
        },
      ),
    );
  }
}
