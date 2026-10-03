import 'package:flutter/material.dart';
import '../../../../data/addons/addon_manager.dart';
import '../../../../data/addons/models/addon.dart';

/// Sección Nuvio: pegar URL de manifest.json y cargar scrapers para instalar.
class NuvioPackagesPage extends StatefulWidget {
  const NuvioPackagesPage({super.key, this.isTv = false});
  final bool isTv;

  @override
  State<NuvioPackagesPage> createState() => _NuvioPackagesPageState();
}

class _NuvioPackagesPageState extends State<NuvioPackagesPage> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  String? _msg;
  String? _progress;
  SourcePackage? _preview; // paquete recién cargado (sin guardar aún opcional)

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
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadManifest() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _msg = null;
      _progress = 'Descargando manifest…';
    });
    try {
      final pkg = await AddonManager.instance.addNuvioPackage(url);
      setState(() {
        _preview = pkg;
        _msg =
            'Paquete «${pkg.name}»: ${pkg.scrapers.length} fuentes cargadas';
        _progress = null;
      });
    } catch (e) {
      setState(() {
        _msg = 'Error: $e';
        _progress = null;
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _installOne(SourcePackage pkg, PackageScraper s) async {
    setState(() {
      _busy = true;
      _progress = 'Instalando ${s.name}…';
    });
    try {
      final m = await AddonManager.instance.installNuvioScraper(pkg, s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Instalado: ${m.name}')),
      );
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

  Future<void> _installAll(SourcePackage pkg) async {
    setState(() {
      _busy = true;
      _progress = 'Instalando todas (${pkg.scrapers.length})…';
    });
    try {
      final r = await AddonManager.instance.installAllNuvioScrapers(pkg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Listo: ${r.ok} ok, ${r.fail} fallos')),
      );
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

  Future<void> _removePackage(SourcePackage pkg) async {
    final url = pkg.manifestUrl ?? '';
    if (url.isEmpty) return;
    await AddonManager.instance.removeNuvioPackage(url);
    if (_preview?.manifestUrl == url) {
      setState(() => _preview = null);
    }
  }

  Future<void> _refreshPackage(SourcePackage pkg) async {
    final url = pkg.manifestUrl ?? '';
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _progress = 'Actualizando paquete…';
    });
    try {
      await AddonManager.instance.refreshNuvioPackage(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }


  Future<void> _showAddModalTv() async {
    final ctrl = TextEditingController(text: _urlCtrl.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        title: const Text('URL del manifest', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'https://…/manifest.json',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
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
            child: const Text('Cargar', style: TextStyle(color: Color(0xFFE50914))),
          ),
        ],
      ),
    );
    // Evita '_dependents.isEmpty' al cerrar: quitar foco del TextField antes de dispose
    try {
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {}
    if (ok == true && mounted) {
      _urlCtrl.text = ctrl.text.trim();
      await _loadManifest();
    }
    // dispose del controller en el siguiente frame (después de que el dialog se desmonte)
    final c = ctrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.dispose();
    });
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = AddonManager.instance.packages;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: widget.isTv
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF0A0A0A),
              title: const Text('Addons Nuvio', style: TextStyle(color: Colors.white)),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Pega la URL del manifest.json de un paquete Nuvio (lista "scrapers"). '
            'Luego instala uno a uno o todos.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (!widget.isTv) ...[
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://…/manifest.json',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _busy ? null : _loadManifest,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_download_rounded, color: Colors.white),
                label: Text(
                  _busy ? (_progress ?? 'Cargando…') : 'Cargar paquete',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ] else ...[
            // TV: botón Agregar abre modal con input (evita teclado bloqueando foco)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _busy ? null : _showAddModalTv,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: Text(
                  _busy ? (_progress ?? 'Cargando…') : 'Agregar paquete (manual)',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ],
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(_msg!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          const Text(
            'Paquetes guardados',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (packages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Ningún paquete Nuvio cargado aún.',
                style: TextStyle(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...packages.map(_buildPackageCard),
        ],
      ),
    );
  }

  Widget _buildPackageCard(SourcePackage pkg) {
    final installedCount = pkg.scrapers
        .where((s) => AddonManager.instance.isNuvioScraperInstalled(s.id))
        .length;

    return Card(
      color: const Color(0xFF1C1C1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white54,
        title: Text(
          pkg.name,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          '${pkg.scrapers.length} fuentes · $installedCount instaladas'
          '${pkg.author != null ? ' · ${pkg.author}' : ''}',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
        ),
        children: [
          if (pkg.description != null && pkg.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  pkg.description!,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55), fontSize: 12),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _installAll(pkg),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Instalar todas'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFFE50914),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar manifest',
                onPressed: _busy ? null : () => _refreshPackage(pkg),
                icon: const Icon(Icons.refresh, color: Colors.white70),
              ),
              IconButton(
                tooltip: 'Quitar paquete',
                onPressed: _busy ? null : () => _removePackage(pkg),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
          const Divider(color: Colors.white12),
          ...pkg.scrapers.map((s) {
            final installed =
                AddonManager.instance.isNuvioScraperInstalled(s.id);
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(s.name,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text(
                s.description.isNotEmpty
                    ? s.description
                    : (s.filename.isNotEmpty ? s.filename : s.id),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.45), fontSize: 11),
              ),
              trailing: installed
                  ? const Chip(
                      label: Text('OK',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: Color(0xFF16A34A),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    )
                  : TextButton(
                      onPressed: _busy ? null : () => _installOne(pkg, s),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Instalar', style: TextStyle(fontSize: 12)),
                    ),
            );
          }),
        ],
      ),
    );
  }
}
