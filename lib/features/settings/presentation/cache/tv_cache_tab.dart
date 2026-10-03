import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv_config_shared.dart';
/// Pestaña Caché — StatefulWidget independiente.
class CacheTab extends StatefulWidget {
  final VoidCallback onRequestTabFocus;

  const CacheTab({
    super.key,
    required this.onRequestTabFocus,
  });

  @override
  State<CacheTab> createState() => CacheTabState();
}

class CacheTabState extends State<CacheTab>
    with AutomaticKeepAliveClientMixin {
  late final FocusNode _btnCacheHist;
  late final FocusNode _btnCacheGuard;
  late final FocusNode _btnCacheFav;
  late final FocusNode _btnCacheServ;
  late final FocusNode _btnCacheTodo;

  FocusNode get firstFocusNode => _btnCacheHist;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _btnCacheHist = FocusNode(debugLabel: 'cfg_cache_hist');
    _btnCacheGuard = FocusNode(debugLabel: 'cfg_cache_guard');
    _btnCacheFav = FocusNode(debugLabel: 'cfg_cache_fav');
    _btnCacheServ = FocusNode(debugLabel: 'cfg_cache_serv');
    _btnCacheTodo = FocusNode(debugLabel: 'cfg_cache_todo');
  }

  @override
  void dispose() {
    _btnCacheHist.dispose();
    _btnCacheGuard.dispose();
    _btnCacheFav.dispose();
    _btnCacheServ.dispose();
    _btnCacheTodo.dispose();
    super.dispose();
  }

  Future<void> _clearByPrefix(List<String> prefixes, String msg) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) {
      return prefixes.any((p) => k.startsWith(p) || k == p);
    }).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: kConfigCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void requestFirstFocus() => _btnCacheHist.requestFocus();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('BORRAR DATOS', first: true),
        FocusActionCard(
          focusNode: _btnCacheHist,
          icon: Icons.history_rounded,
          label: 'Borrar historial',
          subtitle: 'Historial de reproducción',
          onTap: () => _clearByPrefix([
            'cachePlayer_',
            'cachePlayerRapido_',
            'historial_',
          ], 'Historial borrado'),
          onArrowUp: widget.onRequestTabFocus,
          onArrowDown: () => _btnCacheGuard.requestFocus(),
        ),
        const SizedBox(height: 10),
        FocusActionCard(
          focusNode: _btnCacheGuard,
          icon: Icons.bookmark_outline_rounded,
          label: 'Borrar guardados',
          subtitle: 'Lista de títulos guardados',
          onTap: () => _clearByPrefix([
            'guardados_items',
            'guardados_',
          ], 'Guardados borrados'),
          onArrowUp: () => _btnCacheHist.requestFocus(),
          onArrowDown: () => _btnCacheFav.requestFocus(),
        ),
        const SizedBox(height: 10),
        FocusActionCard(
          focusNode: _btnCacheFav,
          icon: Icons.favorite_outline_rounded,
          label: 'Borrar favoritos',
          subtitle: 'Lista de favoritos',
          onTap: () => _clearByPrefix(['favoritos_'], 'Favoritos borrados'),
          onArrowUp: () => _btnCacheGuard.requestFocus(),
          onArrowDown: () => _btnCacheServ.requestFocus(),
        ),
        const SizedBox(height: 10),
        FocusActionCard(
          focusNode: _btnCacheServ,
          icon: Icons.dns_rounded,
          label: 'Borrar caché de servidores',
          subtitle: 'Comprobaciones guardadas',
          onTap: () =>
              _clearByPrefix(['serv_cache_'], 'Caché de servidores borrada'),
          onArrowUp: () => _btnCacheFav.requestFocus(),
          onArrowDown: () => _btnCacheTodo.requestFocus(),
        ),
        const SizedBox(height: 10),
        FocusActionCard(
          focusNode: _btnCacheTodo,
          icon: Icons.delete_forever_rounded,
          label: 'Borrar todo',
          subtitle: 'Historial + guardados + servidores',
          onTap: () async {
            final ok = await confirmDialog(
              context: context,
              title: 'Borrar todo',
              body:
                  'Se eliminará historial, guardados, datos de reproducción y caché de servidores.\n\nLas configuraciones se conservan.',
              accent: Colors.redAccent,
              confirmLabel: 'Borrar todo',
            );
            if (ok != true) return;
            await _clearByPrefix([
              'cachePlayer_',
              'cachePlayerRapido_',
              'historial_',
              'guardados_items',
              'guardados_',
              'favoritos_',
              'serv_cache_',
            ], 'Caché completa borrada');
          },
          onArrowUp: () => _btnCacheServ.requestFocus(),
          onArrowDown: () {},
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
