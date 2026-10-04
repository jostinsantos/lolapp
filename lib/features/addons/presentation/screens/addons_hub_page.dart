import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../data/addons/addon_manager.dart';
import '../../../../data/addons/models/addon.dart';
import 'nuvio_packages_page.dart';
import 'nuvio_extensions_hub_page.dart';
import '../../../../data/addons/services/community_service.dart';
import 'tv_addons_actuales_page.dart';
import 'tv_addons_comunidad_page.dart';
import 'tv_nuvio_packages_page.dart';

/// Hub de addons: 2 opciones — Addons actuales | Comunidad (Git).
/// No altera el resto de la UI de la app; se integra en Configuración.
class AddonsHubPage extends StatefulWidget {
  const AddonsHubPage({super.key, this.isTv = false});
  final bool isTv;

  @override
  State<AddonsHubPage> createState() => _AddonsHubPageState();
}

class _AddonsHubPageState extends State<AddonsHubPage> {
  bool _torrentMkv = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _torrentMkv = p.getBool('torrent_mkv_enabled') ?? false;
        });
      }
    });
  }

  Future<void> _setTorrentMkv(bool v) async {
    setState(() => _torrentMkv = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('torrent_mkv_enabled', v);
  }

  @override
  Widget build(BuildContext context) {
    final isTv = widget.isTv;
    if (isTv) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        // TV: sin AppBar — el foco y D-pad recorren toda la página
        body: SafeArea(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              children: [
                const Text(
                  'Addons',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Gestiona fuentes y catálogos con el mando',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                _tile(
                  context,
                  icon: Icons.extension_rounded,
                  title: 'Addons actuales',
                  subtitle:
                      'Fuentes y catálogos instalados. Activar, actualizar o borrar.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TvAddonsActualesPage(),
                    ),
                  ),
                  isTv: true,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                _tile(
                  context,
                  icon: Icons.public_rounded,
                  title: 'Comunidad',
                  subtitle:
                      'Instalar fuentes y catálogos desde GitHub (user/repo).',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TvAddonsComunidadPage(),
                    ),
                  ),
                  isTv: true,
                ),
                const SizedBox(height: 12),
                _tile(
                  context,
                  icon: Icons.inventory_2_rounded,
                  title: 'Extensiones Nuvio',
                  subtitle:
                      'Corriente · Complementos · Plugins · Colecciones (separados).',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const NuvioExtensionsHubPage(isTv: true),
                    ),
                  ),
                  isTv: true,
                ),
                const SizedBox(height: 28),
                _TvTorrentSwitch(
                  value: _torrentMkv,
                  onChanged: _setTorrentMkv,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Móvil: AppBar + sin foco D-pad ───────────────────────────────────
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: widget.isTv ? null : AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Addons', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tile(
            context,
            icon: Icons.extension_rounded,
            title: 'Addons actuales',
            subtitle:
                'Fuentes y catálogos instalados. Activar, actualizar o borrar.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AddonsActualesPage(isTv: false),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _tile(
            context,
            icon: Icons.public_rounded,
            title: 'Comunidad',
            subtitle:
                'Instalar fuentes y catálogos desde GitHub (user/repo).',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AddonsComunidadPage(isTv: false),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _tile(
            context,
            icon: Icons.inventory_2_rounded,
            title: 'Extensiones Nuvio',
            subtitle:
                'Corriente · Complementos · Plugins · Colecciones (separados).',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const NuvioExtensionsHubPage(isTv: false),
              ),
            ),
          ),
          const SizedBox(height: 28),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Archivos magnet (torrent) y MKV',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _torrentMkv
                  ? 'Habilitado: se intentará reproducir magnets y MKV'
                  : 'Deshabilitado (experimental). Puedes activarlo cuando quieras.',
              style:
                  TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
            ),
            value: _torrentMkv,
            activeColor: const Color(0xFFE50914),
            onChanged: _setTorrentMkv,
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isTv = false,
    bool autofocus = false,
  }) {
    if (!isTv) {
      return Material(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFE50914), size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white54),
              ],
            ),
          ),
        ),
      );
    }

    // TV: foco blanco, navegable con D-pad
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: focused
                    ? const Color(0xFF2A2A30)
                    : const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused ? Colors.white : Colors.transparent,
                  width: focused ? 2.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFFE50914), size: 30),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white54),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Switch con foco TV (borde blanco)
class _TvTorrentSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _TvTorrentSwitch({required this.value, required this.onChanged});

  @override
  State<_TvTorrentSwitch> createState() => _TvTorrentSwitchState();
}

class _TvTorrentSwitchState extends State<_TvTorrentSwitch> {
  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.space) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? Colors.white : Colors.transparent,
                width: focused ? 2.5 : 1,
              ),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Archivos magnet (torrent) y MKV',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                widget.value
                    ? 'Habilitado: se intentará reproducir magnets y MKV'
                    : 'Deshabilitado (experimental).',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 12),
              ),
              value: widget.value,
              activeColor: const Color(0xFFE50914),
              onChanged: widget.onChanged,
            ),
          );
        },
      ),
    );
  }
}

class AddonsActualesPage extends StatefulWidget {
  const AddonsActualesPage({super.key, this.isTv = false});
  final bool isTv;

  @override
  State<AddonsActualesPage> createState() => _AddonsActualesPageState();
}

class _AddonsActualesPageState extends State<AddonsActualesPage> {
  @override
  void initState() {
    super.initState();
    AddonManager.instance.init().then((_) {
      if (mounted) setState(() {});
    });
    AddonManager.instance.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AddonManager.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mgr = AddonManager.instance;
    final list = mgr.addons;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: widget.isTv ? null : AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Addons actuales', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar todos',
            onPressed: () async {
              await mgr.updateAll();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Addons actualizados')),
                );
              }
            },
          ),
        ],
      ),
      body: mgr.loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : list.isEmpty
              ? const Center(
                  child: Text(
                    'No hay addons instalados.\nVe a Comunidad para añadir por Git.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final a = list[i];
                    final typeLabel = a.isSource
                        ? 'Fuente'
                        : a.isCatalog
                            ? 'Catálogo'
                            : 'Función';
                    return Material(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        title: Text(a.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '$typeLabel · v${a.version}${a.enabled ? '' : ' · desactivado'}',
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: a.enabled,
                              activeColor: const Color(0xFFE50914),
                              onChanged: (v) => mgr.setEnabled(a.id, v),
                            ),
                            IconButton(
                              icon: const Icon(Icons.system_update_alt,
                                  color: Colors.white70),
                              onPressed: () async {
                                final ok = await mgr.updateAddon(a.id);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Actualizado'
                                          : 'No se pudo actualizar'),
                                    ),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    title: const Text('Eliminar addon',
                                        style: TextStyle(color: Colors.white)),
                                    content: Text(
                                      '¿Quitar «${a.name}»?',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Eliminar',
                                            style: TextStyle(color: Colors.redAccent)),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) await mgr.uninstall(a.id);
                              },
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


class AddonsComunidadPage extends StatefulWidget {
  const AddonsComunidadPage({super.key, this.isTv = false});
  final bool isTv;

  @override
  State<AddonsComunidadPage> createState() => _AddonsComunidadPageState();
}

class _AddonsComunidadPageState extends State<AddonsComunidadPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _svc = CommunityService();
  final _repoCtrl = TextEditingController();

  List<CommunityAddonItem> _sources = [];
  List<CommunityAddonItem> _catalogs = [];
  bool _loading = true;
  String? _error;
  final Set<String> _installing = {};
  String? _manualMsg;
  bool _manualBusy = false;
  AddonType _manualType = AddonType.source;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _repoCtrl.dispose();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        // Al menos seeds
        _sources = _svc.recommended(type: 'source');
        _catalogs = _svc.recommended(type: 'catalog');
      });
    }
  }

  Future<void> _installItem(CommunityAddonItem item) async {
    if (_installing.contains(item.repo)) return;
    // Igual que manual: solo owner/repo en el mismo installFromGitHub
    final repo = item.repo.trim();
    setState(() {
      _installing.add(item.repo);
      _repoCtrl.text = repo;
      _manualType =
          item.type == 'catalog' ? AddonType.catalog : AddonType.source;
    });
    try {
      final m = await AddonManager.instance.installFromGitHub(
        repoOrUrl: repo,
        type: _manualType,
      );
      await AddonManager.instance.reload();
      if (!mounted) return;
      setState(() {
        _manualMsg = 'Instalado: ${m.name} (${m.id})';
        _repoCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Instalado: ${m.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _manualMsg = 'Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _installing.remove(item.repo));
    }
  }

  Future<void> _installManual() async {
    final input = _repoCtrl.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _manualBusy = true;
      _manualMsg = null;
    });
    try {
      final m = await AddonManager.instance.installFromGitHub(
        repoOrUrl: input,
        type: _manualType,
      );
      setState(() {
        _manualMsg = 'Instalado: ${m.name} (${m.id})';
        _repoCtrl.clear();
      });
    } catch (e) {
      setState(() => _manualMsg = 'Error: $e');
    } finally {
      setState(() => _manualBusy = false);
    }
  }

  bool _isInstalled(String repo) {
    final r = repo.toLowerCase();
    for (final a in AddonManager.instance.addons) {
      final gh = (a.githubCanonical ?? '').toLowerCase();
      final pkg = (a.packageUrl ?? '').toLowerCase();
      if (gh.contains(r) || pkg.contains(r) || a.id.toLowerCase().contains(r.split('/').last)) {
        return true;
      }
    }
    return false;
  }


  Future<void> _showManualAddModalTv() async {
    final ctrl = TextEditingController(text: _repoCtrl.text);
    AddonType type = _manualType;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1F),
              title: const Text('Instalar addon',
                  style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'owner/repo o URL de manifest',
                      hintStyle:
                          TextStyle(color: Colors.white.withOpacity(0.3)),
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
                        onSelected: (_) =>
                            setLocal(() => type = AddonType.source),
                        selectedColor: const Color(0xFFE50914),
                        labelStyle: TextStyle(
                          color: type == AddonType.source
                              ? Colors.white
                              : Colors.white70,
                        ),
                        backgroundColor: const Color(0xFF1C1C1E),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Catálogo'),
                        selected: type == AddonType.catalog,
                        onSelected: (_) =>
                            setLocal(() => type = AddonType.catalog),
                        selectedColor: const Color(0xFFE50914),
                        labelStyle: TextStyle(
                          color: type == AddonType.catalog
                              ? Colors.white
                              : Colors.white70,
                        ),
                        backgroundColor: const Color(0xFF1C1C1E),
                      ),
                    ],
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
                  child: const Text('Instalar',
                      style: TextStyle(color: Color(0xFFE50914))),
                ),
              ],
            );
          },
        );
      },
    );
    try {
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {}
    if (ok == true && mounted) {
      _repoCtrl.text = ctrl.text.trim();
      setState(() => _manualType = type);
      await _installManual();
    }
    final c = ctrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        c.dispose();
      } catch (_) {}
    });
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Comunidad', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFE50914),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Fuentes'),
            Tab(text: 'Catálogos'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Instalar manual por user/repo
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.isTv) ...[
                  TextField(
                    controller: _repoCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'owner/repo o URL de manifest',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Fuente'),
                        selected: _manualType == AddonType.source,
                        onSelected: (_) =>
                            setState(() => _manualType = AddonType.source),
                        selectedColor: const Color(0xFFE50914),
                        labelStyle: TextStyle(
                          color: _manualType == AddonType.source
                              ? Colors.white
                              : Colors.white70,
                        ),
                        backgroundColor: const Color(0xFF1C1C1E),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Catálogo'),
                        selected: _manualType == AddonType.catalog,
                        onSelected: (_) =>
                            setState(() => _manualType = AddonType.catalog),
                        selectedColor: const Color(0xFFE50914),
                        labelStyle: TextStyle(
                          color: _manualType == AddonType.catalog
                              ? Colors.white
                              : Colors.white70,
                        ),
                        backgroundColor: const Color(0xFF1C1C1E),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                        ),
                        onPressed: _manualBusy ? null : _installManual,
                        child: _manualBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Instalar',
                                style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ] else ...[
                  // TV: botón Agregar abre modal (evita teclado bloqueando foco D-pad)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _manualBusy ? null : _showManualAddModalTv,
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: Text(
                      _manualBusy ? 'Instalando…' : 'Agregar manualmente',
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ],
                if (_manualMsg != null) ...[
                  const SizedBox(height: 6),
                  Text(_manualMsg!,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 20),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFE50914)))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _list(_sources),
                      _list(_catalogs),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<CommunityAddonItem> items) {
    if (_error != null && items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center),
        ),
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No hay addons en la comunidad.\nInstala manualmente con owner/repo.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = items[i];
        final installed = _isInstalled(item.repo);
        final busy = _installing.contains(item.repo);
        return Material(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF2A2A2C),
              backgroundImage:
                  item.logo != null ? NetworkImage(item.logo!) : null,
              child: item.logo == null
                  ? Icon(
                      item.type == 'catalog'
                          ? Icons.library_books_rounded
                          : Icons.play_circle_outline_rounded,
                      color: Colors.white70,
                    )
                  : null,
            ),
            title: Text(item.name,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            subtitle: Text(
              [
                if (item.description.isNotEmpty) item.description,
                item.repo,
                if (item.stars > 0) '★ ${item.stars}',
              ].join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            isThreeLine: true,
            trailing: installed
                ? const Chip(
                    label: Text('Instalado',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                    backgroundColor: Color(0xFF16A34A),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )
                : TextButton(
                    onPressed: busy ? null : () => _installItem(item),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Instalar'),
                  ),
          ),
        );
      },
    );
  }
}
