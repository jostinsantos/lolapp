import 'package:flutter/material.dart';
import '../../../../data/addons/stremio/stream_badge_repository.dart';

/// Corriente: packs de insignias / logotipos para la lista de streams.
class StreamCorrientePage extends StatefulWidget {
  const StreamCorrientePage({super.key});

  @override
  State<StreamCorrientePage> createState() => _StreamCorrientePageState();
}

class _StreamCorrientePageState extends State<StreamCorrientePage> {
  final _urlCtrl = TextEditingController();
  final _jsonCtrl = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    StreamBadgeRepository.instance.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _installUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final p = await StreamBadgeRepository.instance.installFromUrl(url);
      setState(() {
        _msg = 'Pack «${p.name}»: ${p.badges.length} insignias';
      });
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _installJson() async {
    final raw = _jsonCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final p = await StreamBadgeRepository.instance.installFromJson(raw);
      setState(() {
        _msg = 'Pack «${p.name}»: ${p.badges.length} insignias';
        _jsonCtrl.clear();
      });
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packs = StreamBadgeRepository.instance.packs;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Corriente', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Packs de insignias y logotipos que se muestran en la lista de '
            'servidores/streams (por nombre del proveedor). Igual que las '
            'badges de corriente en Nuvio.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 16),
          const Text('Desde URL',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://…/badges.json',
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
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _busy ? null : _installUrl,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Instalar'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Pegar JSON',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _jsonCtrl,
            maxLines: 6,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText:
                  '{ "id":"pack1", "name":"LATAM", "badges":[{ "match":"netflix", "logo":"https://…" }] }',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: const Color(0xFF1C1C1E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _busy ? null : _installJson,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
              ),
              child: const Text('Importar JSON'),
            ),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(_msg!,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const SizedBox(height: 22),
          Text(
            'Packs instalados (${packs.length})',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 10),
          if (packs.isEmpty)
            const Text('Ningún pack de corriente.',
                style: TextStyle(color: Colors.white38))
          else
            ...packs.map((p) {
              return Card(
                color: const Color(0xFF1C1C1E),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.sell, color: Color(0xFFF59E0B)),
                  title: Text(p.name,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${p.badges.length} insignias',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: p.enabled,
                        activeColor: const Color(0xFFF59E0B),
                        onChanged: (v) async {
                          await StreamBadgeRepository.instance
                              .setEnabled(p.id, v);
                          setState(() {});
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white54),
                        onPressed: () async {
                          await StreamBadgeRepository.instance.remove(p.id);
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
