import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Página placeholder para el botón "TV" del menú lateral.
/// Se implementará más adelante; por ahora solo muestra un mensaje con foco.
class TvPlaceholderPage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const TvPlaceholderPage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<TvPlaceholderPage> createState() => _TvPlaceholderPageState();
}

class _TvPlaceholderPageState extends State<TvPlaceholderPage> {
  final FocusNode _rootFocus = FocusNode(debugLabel: 'tv_placeholder_root');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMainFocusNodeCreated?.call(_rootFocus);
      _rootFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.backspace) {
          widget.onRequestMenuFocus?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tv_rounded,
                size: 72,
                color: Colors.white.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 20),
              const Text(
                'TV',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Esta sección se implementará pronto.\nPulsa Atrás o ← para volver al menú.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
