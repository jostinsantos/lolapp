import 'package:flutter/material.dart';
import '../../../../data/addons/addon_manager.dart';

/// Complementos Stremio/Nuvio: catálogo, meta, stream, subtítulos, TMDB…
class StremioComplementosPage extends StatefulWidget {
  const StremioComplementosPage({super.key});

  @override
  State<StremioComplementosPage> createState() =>
      _StremioComplementosPageState();
}

class _StremioComplementosPageState extends State<StremioComplementosPage> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    AddonManager.instance.init().then((_) {
      if (mounted) setState(() {});
    });
    AddonManager.instance.addListener(_on);
  }

  void _on() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AddonManager.instance.removeListener(_on);
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final a = await AddonManager.instance.addStremioCatalog(url);
      final n = a.manifest?.catalogs.length ?? 0;
      final res = a.manifest?.resources.map((r) => r.name).join(', ') ?? '';
      setState(() {
        _msg =
            '«${a.displayName}» instalado · $n catálogos · resources: $res';
      });
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = AddonManager.instance.stremioCatalogAddons;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Complementos', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Addons del protocolo Stremio (los mismos que Nuvio): catálogos, '
            'meta, streams, subtítulos, etc. Pega la URL del manifest.json.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://…/manifest.json',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: const Color(0xFF1C1C1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _busy ? null : _install,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Instalar'),
              ),
            ],
          ),
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(_msg!,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const SizedBox(height: 22),
          Text(
            'Instalados (${list.length})',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 10),
          if (list.isEmpty)
            const Text('Ningún complemento aún.',
                style: TextStyle(color: Colors.white38))
          else
            ...list.map((a) {
              final n = a.manifest?.catalogs.length ?? 0;
              final res = a.manifest?.resources
                      .map((r) => r.name)
                      .toSet()
                      .join(', ') ??
                  '';
              return Card(
                color: const Color(0xFF1C1C1E),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(a.displayName,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    a.errorMessage ??
                        '$n catálogos · $res\n${a.manifestUrl}',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: a.enabled,
                        activeColor: const Color(0xFF8B5CF6),
                        onChanged: (v) async {
                          await AddonManager.instance
                              .setStremioCatalogEnabled(a.manifestUrl, v);
                          setState(() {});
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white54),
                        onPressed: () async {
                          await AddonManager.instance
                              .removeStremioCatalog(a.manifestUrl);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
