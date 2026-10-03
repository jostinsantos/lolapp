import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../addons/presentation/screens/tv_addons_actuales_page.dart';
import '../../../addons/presentation/screens/tv_addons_comunidad_page.dart';
import '../../../addons/presentation/screens/tv_nuvio_packages_page.dart';

/// Pestaña TV: acceso a Addons actuales, Comunidad y Nuvio (páginas 100% TV).
class TvAddonsTab extends StatefulWidget {
  final VoidCallback? onRequestTabFocus;

  const TvAddonsTab({super.key, this.onRequestTabFocus});

  @override
  State<TvAddonsTab> createState() => TvAddonsTabState();
}

class TvAddonsTabState extends State<TvAddonsTab> {
  final _n1 = FocusNode(debugLabel: 'addons_actuales');
  final _n2 = FocusNode(debugLabel: 'addons_comunidad');
  final _n3 = FocusNode(debugLabel: 'addons_nuvio');

  @override
  void dispose() {
    _n1.dispose();
    _n2.dispose();
    _n3.dispose();
    super.dispose();
  }

  void focusFirst() {
    _n1.requestFocus();
  }

  void requestFirstFocus() {
    _n1.requestFocus();
  }

  void _open(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Addons',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Instala y gestiona fuentes y catálogos por Git (como App 2).',
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 14),
          ),
          const SizedBox(height: 24),
          _card(
            node: _n1,
            icon: Icons.extension_rounded,
            title: 'Addons actuales',
            subtitle: 'Ver, activar, actualizar o borrar los instalados',
            onTap: () => _open(const TvAddonsActualesPage()),
            onUp: widget.onRequestTabFocus,
            onDown: () => _n2.requestFocus(),
          ),
          const SizedBox(height: 12),
          _card(
            node: _n2,
            icon: Icons.public_rounded,
            title: 'Comunidad',
            subtitle: 'Descargar fuentes y catálogos desde GitHub (user/repo)',
            onTap: () => _open(const TvAddonsComunidadPage()),
            onUp: () => _n1.requestFocus(),
            onDown: () => _n3.requestFocus(),
          ),
          const SizedBox(height: 12),
          _card(
            node: _n3,
            icon: Icons.inventory_2_rounded,
            title: 'Addons Nuvio',
            subtitle: 'Manifest URL: cargar scrapers e instalar uno a uno o todos',
            onTap: () => _open(const TvNuvioPackagesPage()),
            onUp: () => _n2.requestFocus(),
            onDown: null,
          ),
        ],
      ),
    );
  }

  Widget _card({
    required FocusNode node,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    VoidCallback? onUp,
    VoidCallback? onDown,
  }) {
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp && onUp != null) {
          onUp();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown && onDown != null) {
          onDown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Material(
            color: focused ? const Color(0xFFE50914) : const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white70),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
