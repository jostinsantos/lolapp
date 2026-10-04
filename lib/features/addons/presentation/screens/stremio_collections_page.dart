import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../data/addons/addon_manager.dart';
import '../../../../data/addons/models/content.dart';
import '../../../../data/addons/stremio/stremio_collection_repository.dart';
import '../../../../data/addons/stremio/stremio_models.dart';
import '../../../content/presentation/content_page.dart';

/// Gestión de colecciones + apertura de su contenido (como Nuvio).
class StremioCollectionsPage extends StatefulWidget {
  const StremioCollectionsPage({super.key});

  @override
  State<StremioCollectionsPage> createState() => _StremioCollectionsPageState();
}

class _StremioCollectionsPageState extends State<StremioCollectionsPage> {
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
    super.dispose();
  }

  Future<void> _importJson() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        title: const Text('Importar colección',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText:
                '{ "id":"…", "title":"…", "sources":[{ "provider":"addon", "type":"movie", "catalogId":"…" }] }',
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
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importar',
                style: TextStyle(color: Color(0xFF22C55E))),
          ),
        ],
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (ok != true || !mounted) {
      ctrl.dispose();
      return;
    }
    final raw = ctrl.text.trim();
    ctrl.dispose();
    if (raw.isEmpty) return;
    try {
      final n = await AddonManager.instance.importStremioCollectionsJson(raw);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Importadas: $n')));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _fromCatalog() async {
    final targets =
        AddonManager.instance.stremioCatalogAddons.expand((a) {
      final m = a.manifest;
      if (m == null || !a.enabled) return <CatalogTarget>[];
      return m.catalogs.map((c) => CatalogTarget(
            manifestUrl: a.manifestUrl,
            type: c.type,
            catalogId: c.id,
            catalogName: c.name,
            addonName: m.name,
          ));
    }).toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Primero instala complementos con catálogos')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<CatalogTarget>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1F),
      builder: (ctx) => ListView(
        children: targets
            .map((t) => ListTile(
                  title: Text(t.catalogName ?? t.catalogId,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${t.addonName ?? ""} · ${t.type}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(ctx, t),
                ))
            .toList(),
      ),
    );
    if (chosen == null || !mounted) return;
    await AddonManager.instance.createCollectionFromCatalog(chosen);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = AddonManager.instance.stremioCollections;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title:
            const Text('Colecciones', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Desde catálogo',
            onPressed: _fromCatalog,
            icon: const Icon(Icons.add_box_outlined),
          ),
          IconButton(
            tooltip: 'Importar JSON',
            onPressed: _importJson,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.collections_bookmark_outlined,
                        color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Sin colecciones.\nImporta JSON estilo Nuvio o crea una desde un catálogo de complemento.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _importJson,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E)),
                      child: const Text('Importar JSON'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return Card(
                  color: const Color(0xFF1C1C1E),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.folder_special,
                        color: Color(0xFF22C55E)),
                    title: Text(c.title,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      '${c.sources.length} fuentes · Home: ${c.showOnHome ? "sí" : "no"}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white54),
                      onPressed: () async {
                        await AddonManager.instance
                            .removeStremioCollection(c.id);
                        setState(() {});
                      },
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StremioCollectionDetailPage(
                            collection: c,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// Contenido de una colección (grid), al abrirla.
class StremioCollectionDetailPage extends StatefulWidget {
  final StremioCollection collection;
  const StremioCollectionDetailPage({super.key, required this.collection});

  @override
  State<StremioCollectionDetailPage> createState() =>
      _StremioCollectionDetailPageState();
}

class _StremioCollectionDetailPageState
    extends State<StremioCollectionDetailPage> {
  List<ContentItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await StremioCollectionRepository.instance
          .resolveItems(widget.collection);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openItem(ContentItem item) {
    final tmdb = item.extra['tmdbId'];
    final id = tmdb is int
        ? tmdb
        : int.tryParse(item.id.split(':').last) ?? 0;
    final mediaType =
        item.type == ContentType.series ? 'tv' : 'movie';
    if (id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sin ID TMDB para «${item.title}»')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PageContenido(
          idcontenido: id,
          tmdbId: id,
          mediaType: mediaType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text(widget.collection.title,
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF22C55E)))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.white54)))
              : _items.isEmpty
                  ? const Center(
                      child: Text('Sin contenido en esta colección',
                          style: TextStyle(color: Colors.white54)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.67,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final it = _items[i];
                        return GestureDetector(
                          onTap: () => _openItem(it),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (it.poster != null &&
                                    it.poster!.isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: it.poster!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        Container(color: const Color(0xFF1a1a2e)),
                                  )
                                else
                                  Container(
                                    color: const Color(0xFF1a1a2e),
                                    alignment: Alignment.center,
                                    child: Text(
                                      it.title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 11),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    color: Colors.black54,
                                    child: Text(
                                      it.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11),
                                    ),
                                  ),
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
