import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/addons/services/community_service.dart';
import '../data/tvchanel_repository.dart';
import '../models/tv_channel_models.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF1C1C1E);

/// Addons de canales — móvil (comunidad lol-tvchanel + GitHub manual)
class AddonChanelPage extends StatefulWidget {
  const AddonChanelPage({super.key});
  @override
  State<AddonChanelPage> createState() => _AddonChanelPageState();
}

class _AddonChanelPageState extends State<AddonChanelPage> {
  final _repo = TvChanelRepository.instance;
  final _community = CommunityService();
  List<TvAddon> _installed = [];
  List<CommunityAddonItem> _communityList = [];
  bool _loading = true;
  final Set<String> _installing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final inst = await _repo.loadAddons();
      final com = await _community.fetchTvChanelAddons();
      if (!mounted) return;
      setState(() {
        _installed = inst;
        _communityList = com;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isInstalled(String repo) {
    final key = repo.toLowerCase().split('/').last;
    return _installed.any((a) =>
        a.manifest.id.toLowerCase().contains(key) ||
        a.folderPath.toLowerCase().contains(key));
  }

  Future<void> _install(String ownerRepo) async {
    setState(() => _installing.add(ownerRepo));
    try {
      await _repo.installFromGithub(ownerRepo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Instalado: $ownerRepo'),
        backgroundColor: Colors.green.shade700,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red.shade800,
      ));
    } finally {
      if (mounted) setState(() => _installing.remove(ownerRepo));
    }
  }

  void _manual() {
    final o = TextEditingController();
    final r = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('GitHub manual',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: o,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Owner', labelStyle: TextStyle(color: Colors.white54)),
            ),
            TextField(
              controller: r,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Repo', labelStyle: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final a = o.text.trim();
              final b = r.text.trim();
              if (a.isEmpty || b.isEmpty) return;
              Navigator.pop(ctx);
              _install('$a/$b');
            },
            child: const Text('Instalar', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Addons de Canales', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _manual, icon: const Icon(Icons.add_box_rounded)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Instalados (${_installed.length})',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                if (_installed.isEmpty)
                  Text('Ninguno', style: TextStyle(color: Colors.white.withValues(alpha: 0.4)))
                else
                  ..._installed.map((a) {
                    final logo = a.manifest.logoPath;
                    return Card(
                      color: _kCard,
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 40, height: 40,
                            child: logo.startsWith('http')
                                ? Image.network(logo, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.tv, color: _kAccent))
                                : (logo.isNotEmpty && !logo.endsWith('.nologo')
                                    ? Image.file(File(logo), fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.tv, color: _kAccent))
                                    : const Icon(Icons.tv, color: _kAccent)),
                          ),
                        ),
                        title: Text(a.manifest.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text('${a.totalChannels} canales',
                            style: const TextStyle(color: Colors.white54)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () async {
                            await _repo.deleteAddon(a.folderPath);
                            await _load();
                          },
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 24),
                const Text('Comunidad (lol-tvchanel)',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                if (_communityList.isEmpty)
                  Text(
                    'No hay repos públicos. Usa GitHub manual o publica con topic lol-tvchanel.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  )
                else
                  ..._communityList.map((item) {
                    final installed = _isInstalled(item.repo);
                    final busy = _installing.contains(item.repo);
                    return Card(
                      color: _kCard,
                      child: ListTile(
                        title: Text(item.name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(item.repo,
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: busy
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent))
                            : installed
                                ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                                : TextButton(
                                    onPressed: () => _install(item.repo),
                                    child: const Text('Instalar',
                                        style: TextStyle(color: _kAccent)),
                                  ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
