import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ======================================================
// MODELO
// ======================================================
class HlsQuality {
  final String url;
  final String label;
  final int? width;
  final int? height;
  final int bandwidth;
  final bool isAuto;

  const HlsQuality({
    required this.url,
    required this.label,
    this.width,
    this.height,
    this.bandwidth = 0,
    this.isAuto = false,
  });

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HlsQuality &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          label == other.label;

  @override
  int get hashCode => Object.hash(url, label);
}

// ======================================================
// PARSER HLS (sin dependencias extra)
// ======================================================
class HlsQualityParser {
  /// Extrae las variantes de un master playlist HLS.
  /// Devuelve lista ordenada de mayor a menor resolución + opción Auto.
  static Future<List<HlsQuality>> parse(String masterUrl) async {
    try {
      final response = await http
          .get(Uri.parse(masterUrl))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final body = utf8.decode(response.bodyBytes);
      final lines = body.replaceAll('\r\n', '\n').split('\n');
      final baseUri = Uri.parse(masterUrl);
      final qualities = <HlsQuality>[];

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

        final resolutionMatch =
            RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
        final bandwidthMatch =
            RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final averageBandwidthMatch =
            RegExp(r'AVERAGE-BANDWIDTH=(\d+)').firstMatch(line);

        // La URL de la variante está en la siguiente línea no-comentario
        String? variantUrl;
        for (int j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isEmpty) continue;
          if (next.startsWith('#')) continue;
          variantUrl = next;
          break;
        }
        if (variantUrl == null) continue;

        final fullUrl = baseUri.resolve(variantUrl).toString();
        final width = resolutionMatch != null
            ? int.tryParse(resolutionMatch.group(1)!)
            : null;
        final height = resolutionMatch != null
            ? int.tryParse(resolutionMatch.group(2)!)
            : null;
        final bandwidth = bandwidthMatch != null
            ? int.tryParse(bandwidthMatch.group(1)!) ?? 0
            : (averageBandwidthMatch != null
                ? int.tryParse(averageBandwidthMatch.group(1)!) ?? 0
                : 0);

        String label;
        if (height != null && height > 0) {
          label = '${height}p';
        } else if (bandwidth > 0) {
          final kbps = (bandwidth / 1000).round();
          label = kbps >= 1000
              ? '${(kbps / 1000).toStringAsFixed(1)} Mbps'
              : '$kbps kbps';
        } else {
          label = 'Calidad ${qualities.length + 1}';
        }

        // Evitar duplicados por misma URL
        if (qualities.any((q) => q.url == fullUrl)) continue;

        qualities.add(HlsQuality(
          url: fullUrl,
          label: label,
          width: width,
          height: height,
          bandwidth: bandwidth,
        ));
      }

      // Ordenar de mayor a menor (por height, luego por bandwidth)
      qualities.sort((a, b) {
        final hA = a.height ?? 0;
        final hB = b.height ?? 0;
        if (hA != hB) return hB.compareTo(hA);
        return b.bandwidth.compareTo(a.bandwidth);
      });

      // Siempre añadir "Auto" al principio (usa el master original)
      return [
        HlsQuality(
          url: masterUrl,
          label: 'Auto',
          isAuto: true,
          bandwidth: 0,
        ),
        ...qualities,
      ];
    } catch (e) {
      debugPrint('HlsQualityParser error: $e');
      return [];
    }
  }
}

// ======================================================
// BOTÓN PARA LA BARRA DE ACCIONES DEL PLAYER
// ======================================================
class QualityActionButton extends StatelessWidget {
  final FocusNode focusNode;
  final String currentLabel;
  final VoidCallback onTap;
  final Color accentColor;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final bool Function(KeyEvent)? isBackKey;
  final VoidCallback? onBack;

  const QualityActionButton({
    super.key,
    required this.focusNode,
    required this.currentLabel,
    required this.onTap,
    this.accentColor = const Color(0xFFFF6B00),
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
    this.isBackKey,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final hasFocus = focusNode.hasFocus;

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isBackKey != null && isBackKey!(event)) {
          onBack?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onArrowRight?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onArrowLeft?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onArrowUp?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onArrowDown?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: hasFocus
                ? Colors.white
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: hasFocus ? Colors.white : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.high_quality_rounded,
                size: 18,
                color: hasFocus ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                currentLabel,
                style: TextStyle(
                  color: hasFocus ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================
// MODAL DE SELECCIÓN DE CALIDAD (estilo TV)
// ======================================================
class HlsQualitySelectorModal extends StatefulWidget {
  final String masterUrl;
  final String? currentQualityUrl;
  final String? currentQualityLabel;
  final ValueChanged<HlsQuality> onSelected;
  final Color accentColor;

  const HlsQualitySelectorModal({
    super.key,
    required this.masterUrl,
    this.currentQualityUrl,
    this.currentQualityLabel,
    required this.onSelected,
    this.accentColor = const Color(0xFFFF6B00),
  });

  /// Helper para abrir el modal fácilmente desde el player
  static Future<HlsQuality?> show(
    BuildContext context, {
    required String masterUrl,
    String? currentQualityUrl,
    String? currentQualityLabel,
    Color accentColor = const Color(0xFFFF6B00),
  }) {
    return showDialog<HlsQuality>(
      context: context,
      barrierDismissible: true,
      // Importante para Android TV / mando: el diálogo debe poder tomar el foco
      useRootNavigator: true,
      builder: (dialogContext) => HlsQualitySelectorModal(
        masterUrl: masterUrl,
        currentQualityUrl: currentQualityUrl,
        currentQualityLabel: currentQualityLabel,
        accentColor: accentColor,
        onSelected: (q) {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop(q);
          }
        },
      ),
    );
  }

  @override
  State<HlsQualitySelectorModal> createState() =>
      _HlsQualitySelectorModalState();
}

class _HlsQualitySelectorModalState extends State<HlsQualitySelectorModal> {
  bool _loading = true;
  String? _error;
  List<HlsQuality> _qualities = [];
  final List<FocusNode> _focusNodes = [];
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  // Altura aproximada de cada ítem (padding + contenido + margin)
  static const double _itemExtent = 64.0;

  @override
  void initState() {
    super.initState();
    _loadQualities();
  }

  @override
  void dispose() {
    for (final n in _focusNodes) {
      n.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    if (index < 0 || index >= _qualities.length) return;

    final max = _scrollController.position.maxScrollExtent;
    // Centrar el ítem en el viewport visible
    final viewport = _scrollController.position.viewportDimension;
    final target = (index * _itemExtent) - (viewport / 2) + (_itemExtent / 2);

    _scrollController.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadQualities() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final list = await HlsQualityParser.parse(widget.masterUrl);

    if (!mounted) return;

    if (list.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No se encontraron calidades';
      });
      return;
    }

    // Marcar la calidad actual
    int currentIdx = 0;
    if (widget.currentQualityUrl != null) {
      final idx = list.indexWhere((q) => q.url == widget.currentQualityUrl);
      if (idx >= 0) currentIdx = idx;
    } else if (widget.currentQualityLabel != null) {
      final idx =
          list.indexWhere((q) => q.label == widget.currentQualityLabel);
      if (idx >= 0) currentIdx = idx;
    }

    // Crear focus nodes
    for (final n in _focusNodes) {
      n.dispose();
    }
    _focusNodes
      ..clear()
      ..addAll(List.generate(list.length, (_) => FocusNode()));

    setState(() {
      _qualities = list;
      _selectedIndex = currentIdx;
      _loading = false;
    });

    // Pedir foco al item actual y hacer scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNodes.isNotEmpty) {
        final safeIdx = _selectedIndex.clamp(0, _focusNodes.length - 1);
        _focusNodes[safeIdx].requestFocus();
        _scrollToIndex(safeIdx);
      }
    });
  }

  void _select(int index) {
    if (index < 0 || index >= _qualities.length) return;
    final quality = _qualities[index];
    widget.onSelected(quality);
  }

  KeyEventResult _handleItemKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < _focusNodes.length - 1) {
        final next = index + 1;
        _focusNodes[next].requestFocus();
        _scrollToIndex(next);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        final prev = index - 1;
        _focusNodes[prev].requestFocus();
        _scrollToIndex(prev);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _select(index);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // Si ningún item tiene foco aún, capturamos las teclas aquí
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (_focusNodes.isEmpty) {
              if (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack ||
                  event.logicalKey == LogicalKeyboardKey.browserBack) {
                Navigator.of(context).pop();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }
            // Si nadie del listado tiene foco, dárselo al seleccionado
            final anyFocused = _focusNodes.any((n) => n.hasFocus);
            if (!anyFocused) {
              final safe = _selectedIndex.clamp(0, _focusNodes.length - 1);
              _focusNodes[safe].requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                  child: Row(
                    children: [
                      Icon(Icons.high_quality_rounded,
                          color: widget.accentColor, size: 26),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Calidad de video',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white54, size: 22),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),

                // Contenido
                Flexible(
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF6B00),
                              strokeWidth: 3,
                            ),
                          ),
                        )
                      : _error != null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 40, horizontal: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: Colors.redAccent, size: 40),
                                  const SizedBox(height: 12),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 14),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  TextButton(
                                    onPressed: _loadQualities,
                                    child: Text(
                                      'Reintentar',
                                      style:
                                          TextStyle(color: widget.accentColor),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              itemCount: _qualities.length,
                              itemBuilder: (context, index) {
                                final q = _qualities[index];
                                final isCurrent = index == _selectedIndex;
                                final hasFocus = _focusNodes.length > index &&
                                    _focusNodes[index].hasFocus;

                                return Focus(
                                  focusNode: _focusNodes.length > index
                                      ? _focusNodes[index]
                                      : null,
                                  onKeyEvent: (node, event) =>
                                      _handleItemKey(index, event),
                                  onFocusChange: (hasFocus) {
                                    if (hasFocus) _scrollToIndex(index);
                                  },
                                  child: Builder(
                                    builder: (ctx) {
                                      final focused = Focus.of(ctx).hasFocus;
                                      return GestureDetector(
                                        onTap: () => _select(index),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 150),
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 14),
                                          decoration: BoxDecoration(
                                            color: focused
                                                ? Colors.white
                                                : isCurrent
                                                    ? widget.accentColor
                                                        .withValues(alpha: 0.18)
                                                    : Colors.white.withValues(
                                                        alpha: 0.05),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: focused
                                                  ? Colors.white
                                                  : isCurrent
                                                      ? widget.accentColor
                                                      : Colors.transparent,
                                              width: 1.8,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                q.isAuto
                                                    ? Icons
                                                        .auto_awesome_rounded
                                                    : Icons.hd_rounded,
                                                size: 22,
                                                color: focused
                                                    ? Colors.black
                                                    : isCurrent
                                                        ? widget.accentColor
                                                        : Colors.white70,
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Text(
                                                  q.label,
                                                  style: TextStyle(
                                                    color: focused
                                                        ? Colors.black
                                                        : Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: isCurrent ||
                                                            focused
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              if (!q.isAuto &&
                                                  q.bandwidth > 0)
                                                Text(
                                                  q.bandwidth >= 1000000
                                                      ? '${(q.bandwidth / 1000000).toStringAsFixed(1)} Mbps'
                                                      : '${(q.bandwidth / 1000).round()} kbps',
                                                  style: TextStyle(
                                                    color: focused
                                                        ? Colors.black54
                                                        : Colors.white38,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              if (isCurrent) ...[
                                                const SizedBox(width: 10),
                                                Icon(
                                                  Icons.check_circle_rounded,
                                                  size: 20,
                                                  color: focused
                                                      ? Colors.black
                                                      : widget.accentColor,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                ),

                // Footer
                if (!_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text(
                      '↑↓ navegar   ·   OK seleccionar   ·   Atrás cerrar',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================
// HELPER PARA CAMBIAR CALIDAD EN EL PLAYER
// (opcional, puedes usarlo desde el PlayerScreen)
// ======================================================
/// Resultado del cambio de calidad (para que el player sepa qué hacer)
class QualitySwitchResult {
  final HlsQuality quality;
  final Duration positionAtSwitch;

  const QualitySwitchResult({
    required this.quality,
    required this.positionAtSwitch,
  });
}