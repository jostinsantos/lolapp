import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../tvchanel/config/m3u8_page_tv.dart';
import '../../../tvchanel/config/addon_chanel_tv.dart';
import '../tv_config_shared.dart';

/// Tab de configuración de TV Channels (listas M3U8 + addons de canales)
class TvChanelTab extends StatefulWidget {
  final VoidCallback? onRequestTabFocus;

  const TvChanelTab({
    super.key,
    this.onRequestTabFocus,
  });

  @override
  State<TvChanelTab> createState() => TvChanelTabState();
}

class TvChanelTabState extends State<TvChanelTab> {
  final FocusNode _m3uFocus = FocusNode(debugLabel: 'cfg_tv_m3u');
  final FocusNode _addonFocus = FocusNode(debugLabel: 'cfg_tv_addon');

  @override
  void dispose() {
    _m3uFocus.dispose();
    _addonFocus.dispose();
    super.dispose();
  }

  /// Llamado desde ConfigPage para enfocar el primer elemento
  void requestFirstFocus() {
    _m3uFocus.requestFocus();
  }

  void _openM3u() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => M3u8PageTv(
          onRequestMenuFocus: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  void _openAddons() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddonChanelTv(
          onRequestMenuFocus: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TV en Vivo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Gestiona listas M3U8 y addons de canales en vivo.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),

        // ── Listas M3U8 ──────────────────────────────────────
        _ConfigCard(
          focusNode: _m3uFocus,
          icon: Icons.playlist_play_rounded,
          title: 'Listas M3U8',
          subtitle: 'Añadir, activar o eliminar listas de canales',
          onTap: _openM3u,
          onUp: () => widget.onRequestTabFocus?.call(),
          onDown: () => _addonFocus.requestFocus(),
          onLeft: () => widget.onRequestTabFocus?.call(),
        ),
        const SizedBox(height: 12),

        // ── Addons de canales ────────────────────────────────
        _ConfigCard(
          focusNode: _addonFocus,
          icon: Icons.extension_rounded,
          title: 'Addons de Canales',
          subtitle: 'Addons locales (manifest + index + logo)',
          onTap: _openAddons,
          onUp: () => _m3uFocus.requestFocus(),
          onDown: null,
          onLeft: () => widget.onRequestTabFocus?.call(),
        ),
      ],
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;

  const _ConfigCard({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onUp,
    this.onDown,
    this.onLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
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
        if (key == LogicalKeyboardKey.arrowLeft && onLeft != null) {
          onLeft!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: hasFocus
                    ? kConfigAccent.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.white10,
                  width: hasFocus ? 2.2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kConfigAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: kConfigAccent, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight:
                                hasFocus ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: hasFocus ? Colors.white : Colors.white38,
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