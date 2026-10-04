import 'package:flutter/material.dart';
import '../../../../data/addons/addon_manager.dart';
import '../../../../data/addons/stremio/stream_badge_repository.dart';
import '../../../../data/addons/stremio/stremio_collection_repository.dart';
import 'nuvio_packages_page.dart';
import 'stremio_complementos_page.dart';
import 'stremio_collections_page.dart';
import 'stream_corriente_page.dart';

/// Hub de extensiones estilo Nuvio — 4 tipos separados:
/// 1. Corriente  → insignias / logotipos en la lista de streams
/// 2. Complementos → addons Stremio (catálogo, meta, subtítulos, TMDB…)
/// 3. Plugins → paquetes JS de fuentes de streaming
/// 4. Colecciones → filas en Home + página de contenido
class NuvioExtensionsHubPage extends StatefulWidget {
  const NuvioExtensionsHubPage({super.key, this.isTv = false});
  final bool isTv;

  @override
  State<NuvioExtensionsHubPage> createState() => _NuvioExtensionsHubPageState();
}

class _NuvioExtensionsHubPageState extends State<NuvioExtensionsHubPage> {
  @override
  void initState() {
    super.initState();
    AddonManager.instance.init().then((_) {
      StreamBadgeRepository.instance.init();
      StremioCollectionRepository.instance.init();
      if (mounted) setState(() {});
    });
    AddonManager.instance.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AddonManager.instance.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plugins = AddonManager.instance.packages.length;
    final complementos = AddonManager.instance.stremioCatalogAddons.length;
    final colecciones = AddonManager.instance.stremioCollections.length;
    final corriente = StreamBadgeRepository.instance.packs.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: widget.isTv
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF0A0A0A),
              title: const Text('Extensiones Nuvio',
                  style: TextStyle(color: Colors.white)),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (widget.isTv) ...[
            const Text(
              'Extensiones Nuvio',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Cuatro tipos separados, como en Nuvio',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
          ],
          _CategoryTile(
            icon: Icons.sell_outlined,
            color: const Color(0xFFF59E0B),
            title: 'Corriente',
            subtitle:
                'Insignias y logotipos en la lista de streams (badges).',
            countLabel: corriente == 0 ? 'Sin packs' : '$corriente packs',
            onTap: () => _open(const StreamCorrientePage()),
          ),
          const SizedBox(height: 12),
          _CategoryTile(
            icon: Icons.extension_outlined,
            color: const Color(0xFF8B5CF6),
            title: 'Complementos',
            subtitle:
                'Addons Stremio: catálogos, TMDB, OpenSubtitles, meta…',
            countLabel:
                complementos == 0 ? 'Ninguno' : '$complementos instalados',
            onTap: () => _open(const StremioComplementosPage()),
          ),
          const SizedBox(height: 12),
          _CategoryTile(
            icon: Icons.playlist_play_rounded,
            color: const Color(0xFFE50914),
            title: 'Plugins',
            subtitle:
                'Paquetes JS de fuentes de streaming (scrapers Nuvio).',
            countLabel: plugins == 0 ? 'Ninguno' : '$plugins paquetes',
            onTap: () => _open(NuvioPackagesPage(isTv: widget.isTv)),
          ),
          const SizedBox(height: 12),
          _CategoryTile(
            icon: Icons.collections_bookmark_outlined,
            color: const Color(0xFF22C55E),
            title: 'Colecciones',
            subtitle:
                'Se muestran en el Home. Al abrirlas ves todo su contenido.',
            countLabel:
                colecciones == 0 ? 'Ninguna' : '$colecciones colecciones',
            onTap: () => _open(const StremioCollectionsPage()),
          ),
          const SizedBox(height: 24),
          Text(
            'Cada tipo se instala y gestiona por separado. '
            'Los plugins no se mezclan con los complementos Stremio.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  void _open(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) {
      if (mounted) setState(() {});
    });
  }
}

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String countLabel;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.countLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141416),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      countLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.white.withOpacity(0.35)),
            ],
          ),
        ),
      ),
    );
  }
}
