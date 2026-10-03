import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/sources.dart';
import '../../../features/settings/presentation/tv_config_shared.dart';
const String kPrefSeleccionarServidores = 'seleccionar_servidores';
const String kPrefIdiomaAudio = 'idioma_audio_predeterminado';

/// true si ya eligió modo auto/manual al menos una vez
Future<bool> hasPlaybackSetup() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(kPrefSeleccionarServidores) != null;
}

/// Modal de configuración inicial (sin header/footer).
/// Devuelve true si guardó, false si cerró sin guardar.
Future<bool> showPlaybackSetupModal(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (ctx) => const _PlaybackSetupDialog(),
  );
  return result == true;
}

class _PlaybackSetupDialog extends StatefulWidget {
  const _PlaybackSetupDialog();

  @override
  State<_PlaybackSetupDialog> createState() => _PlaybackSetupDialogState();
}

class _PlaybackSetupDialogState extends State<_PlaybackSetupDialog> {
  String _modo = 'auto';
  String _idioma = 'latino';
  final Map<String, bool> _sources = {};

  late final FocusNode _modoAuto;
  late final FocusNode _modoManual;
  late final FocusNode _lat;
  late final FocusNode _cas;
  late final FocusNode _sub;
  late final FocusNode _guardar;
  late final List<FocusNode> _sourceNodes;

  final _scroll = ScrollController();
  final _scrollViewKey = GlobalKey();

  // Keys para cada elemento enfocable (para ensureVisible)
  final _modoAutoKey = GlobalKey();
  final _modoManualKey = GlobalKey();
  final _latKey = GlobalKey();
  final _casKey = GlobalKey();
  final _subKey = GlobalKey();
  final _guardarKey = GlobalKey();
  final List<GlobalKey> _sourceKeys = [];

  @override
  void initState() {
    super.initState();
    _modoAuto = FocusNode(debugLabel: 'setup_modo_auto');
    _modoManual = FocusNode(debugLabel: 'setup_modo_manual');
    _lat = FocusNode(debugLabel: 'setup_lat');
    _cas = FocusNode(debugLabel: 'setup_cas');
    _sub = FocusNode(debugLabel: 'setup_sub');
    _guardar = FocusNode(debugLabel: 'setup_guardar');

    for (final s in kRegisteredSources) {
      _sources[s.id] = true;
      _sourceKeys.add(GlobalKey());
    }

    _sourceNodes = List.generate(
      kRegisteredSources.length,
      (i) => FocusNode(debugLabel: 'setup_src_$i'),
    );

    // Escuchar cambios de foco para hacer scroll automático
    for (final node in _allFocusNodes) {
      node.addListener(_onFocusChange);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _modoAuto.requestFocus();
    });
  }

  List<FocusNode> get _allFocusNodes => [
        _modoAuto,
        _modoManual,
        _lat,
        _cas,
        _sub,
        _guardar,
        ..._sourceNodes,
      ];

  void _onFocusChange() {
    if (!mounted) return;
    // Buscar qué nodo tiene el foco actualmente
    FocusNode? focused;
    for (final n in _allFocusNodes) {
      if (n.hasFocus) {
        focused = n;
        break;
      }
    }
    if (focused == null) return;

    final key = _keyForNode(focused);
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.5, // centra el elemento en la vista
      );
    }
  }

  GlobalKey? _keyForNode(FocusNode node) {
    if (node == _modoAuto) return _modoAutoKey;
    if (node == _modoManual) return _modoManualKey;
    if (node == _lat) return _latKey;
    if (node == _cas) return _casKey;
    if (node == _sub) return _subKey;
    if (node == _guardar) return _guardarKey;
    final idx = _sourceNodes.indexOf(node);
    if (idx >= 0 && idx < _sourceKeys.length) return _sourceKeys[idx];
    return null;
  }

  @override
  void dispose() {
    for (final node in _allFocusNodes) {
      node.removeListener(_onFocusChange);
    }
    _modoAuto.dispose();
    _modoManual.dispose();
    _lat.dispose();
    _cas.dispose();
    _sub.dispose();
    _guardar.dispose();
    for (final n in _sourceNodes) {
      n.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _saveAndClose() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefSeleccionarServidores, _modo);
    await prefs.setString(kPrefIdiomaAudio, _idioma);
    await prefs.setBool('verificar_servidores', true);
    await prefs.setBool('un_servidor_por_idioma', false);
    await prefs.setBool('mostrar_servidores_player', true);

    if (_modo == 'manual') {
      for (final s in kRegisteredSources) {
        await prefs.setBool(s.prefsKey, _sources[s.id] ?? true);
      }
    } else {
      for (final s in kRegisteredSources) {
        await prefs.setBool(s.prefsKey, true);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _onBack() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final ok = FocusNode();
        final cancel = FocusNode();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          cancel.requestFocus();
        });
        return AlertDialog(
          backgroundColor: kConfigCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: const Text(
            'Debes configurar el modo de reproducción para ver contenido.\n\n'
            'Puedes hacerlo después en Configuración → Fuentes.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            Focus(
              focusNode: cancel,
              onKeyEvent: (n, e) {
                if (e is! KeyDownEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                  ok.requestFocus();
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.select ||
                    e.logicalKey == LogicalKeyboardKey.enter) {
                  Navigator.pop(ctx);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Seguir configurando',
                    style: TextStyle(color: Colors.white70)),
              ),
            ),
            Focus(
              focusNode: ok,
              onKeyEvent: (n, e) {
                if (e is! KeyDownEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  cancel.requestFocus();
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.select ||
                    e.logicalKey == LogicalKeyboardKey.enter) {
                  Navigator.pop(ctx);
                  Navigator.of(context).pop(false);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pop(false);
                },
                child: const Text(
                  'Cerrar',
                  style: TextStyle(color: kConfigAccent),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip({
    required GlobalKey anchorKey,
    required FocusNode node,
    required bool selected,
    required String label,
    IconData? icon,
    required VoidCallback onTap,
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
  }) {
    return Focus(
      focusNode: node,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp && onUp != null) {
          onUp();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown && onDown != null) {
          onDown();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowLeft && onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowRight && onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              node.requestFocus();
              onTap();
            },
            child: AnimatedContainer(
              key: anchorKey,
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? kConfigAccent.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : (selected
                          ? kConfigAccent
                          : Colors.white.withValues(alpha: 0.1)),
                  width: hasFocus ? 2.2 : 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
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

  @override
  Widget build(BuildContext context) {
    final sources = kRegisteredSources;
    final isManual = _modo == 'manual';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Dialog(
        backgroundColor: const Color(0xFF141418),
        insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Configura la reproducción',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Elige cómo se resuelven los servidores e idioma preferido.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: _scrollViewKey,
                      controller: _scroll,
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MODO',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _chip(
                                anchorKey: _modoAutoKey,
                                node: _modoAuto,
                                selected: _modo == 'auto',
                                label: 'Automático',
                                icon: Icons.bolt_rounded,
                                onTap: () => setState(() => _modo = 'auto'),
                                onDown: () => _lat.requestFocus(),
                                onRight: () => _modoManual.requestFocus(),
                              ),
                              const SizedBox(width: 10),
                              _chip(
                                anchorKey: _modoManualKey,
                                node: _modoManual,
                                selected: _modo == 'manual',
                                label: 'Manual',
                                icon: Icons.list_alt_rounded,
                                onTap: () => setState(() => _modo = 'manual'),
                                onDown: () => _cas.requestFocus(),
                                onLeft: () => _modoAuto.requestFocus(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'IDIOMA DE AUDIO',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _chip(
                                anchorKey: _latKey,
                                node: _lat,
                                selected: _idioma == 'latino',
                                label: 'Latino',
                                onTap: () =>
                                    setState(() => _idioma = 'latino'),
                                onUp: () => _modoAuto.requestFocus(),
                                onDown: () {
                                  if (isManual && _sourceNodes.isNotEmpty) {
                                    _sourceNodes.first.requestFocus();
                                  } else {
                                    _guardar.requestFocus();
                                  }
                                },
                                onRight: () => _cas.requestFocus(),
                              ),
                              const SizedBox(width: 10),
                              _chip(
                                anchorKey: _casKey,
                                node: _cas,
                                selected: _idioma == 'castellano',
                                label: 'Castellano',
                                onTap: () =>
                                    setState(() => _idioma = 'castellano'),
                                onUp: () => _modoAuto.requestFocus(),
                                onDown: () {
                                  if (isManual && _sourceNodes.isNotEmpty) {
                                    _sourceNodes.first.requestFocus();
                                  } else {
                                    _guardar.requestFocus();
                                  }
                                },
                                onLeft: () => _lat.requestFocus(),
                                onRight: () => _sub.requestFocus(),
                              ),
                              const SizedBox(width: 10),
                              _chip(
                                anchorKey: _subKey,
                                node: _sub,
                                selected: _idioma == 'subtitulado',
                                label: 'Subtitulado',
                                onTap: () =>
                                    setState(() => _idioma = 'subtitulado'),
                                onUp: () => _modoManual.requestFocus(),
                                onDown: () {
                                  if (isManual && _sourceNodes.isNotEmpty) {
                                    _sourceNodes.first.requestFocus();
                                  } else {
                                    _guardar.requestFocus();
                                  }
                                },
                                onLeft: () => _cas.requestFocus(),
                              ),
                            ],
                          ),
                          if (isManual) ...[
                            const SizedBox(height: 16),
                            Text(
                              'FUENTES ACTIVAS',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...List.generate(sources.length, (i) {
                              final s = sources[i];
                              final on = _sources[s.id] ?? true;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Focus(
                                  focusNode: _sourceNodes[i],
                                  onKeyEvent: (n, e) {
                                    if (e is! KeyDownEvent) {
                                      return KeyEventResult.ignored;
                                    }
                                    final k = e.logicalKey;
                                    if (k == LogicalKeyboardKey.select ||
                                        k == LogicalKeyboardKey.enter) {
                                      setState(
                                        () => _sources[s.id] = !on,
                                      );
                                      return KeyEventResult.handled;
                                    }
                                    if (k == LogicalKeyboardKey.arrowUp) {
                                      if (i == 0) {
                                        _lat.requestFocus();
                                      } else {
                                        _sourceNodes[i - 1].requestFocus();
                                      }
                                      return KeyEventResult.handled;
                                    }
                                    if (k == LogicalKeyboardKey.arrowDown) {
                                      if (i < _sourceNodes.length - 1) {
                                        _sourceNodes[i + 1].requestFocus();
                                      } else {
                                        _guardar.requestFocus();
                                      }
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: Builder(
                                    builder: (context) {
                                      final hasFocus =
                                          Focus.of(context).hasFocus;
                                      return GestureDetector(
                                        onTap: () {
                                          _sourceNodes[i].requestFocus();
                                          setState(
                                            () => _sources[s.id] = !on,
                                          );
                                        },
                                        child: AnimatedContainer(
                                          key: _sourceKeys[i],
                                          duration: const Duration(
                                              milliseconds: 140),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kConfigCard,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: hasFocus
                                                  ? Colors.white
                                                  : Colors.white
                                                      .withValues(alpha: 0.08),
                                              width: hasFocus ? 2 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                s.icon,
                                                color: s.badgeColor,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  s.label,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                on
                                                    ? Icons.check_box_rounded
                                                    : Icons
                                                        .check_box_outline_blank_rounded,
                                                color: on
                                                    ? kConfigAccent
                                                    : Colors.white38,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            }),
                          ],
                          // Espacio al final para que el último item pueda centrarse
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Focus(
                  focusNode: _guardar,
                  onKeyEvent: (n, e) {
                    if (e is! KeyDownEvent) return KeyEventResult.ignored;
                    final k = e.logicalKey;
                    if (k == LogicalKeyboardKey.select ||
                        k == LogicalKeyboardKey.enter) {
                      _saveAndClose();
                      return KeyEventResult.handled;
                    }
                    if (k == LogicalKeyboardKey.arrowUp) {
                      if (isManual && _sourceNodes.isNotEmpty) {
                        _sourceNodes.last.requestFocus();
                      } else {
                        _lat.requestFocus();
                      }
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final hasFocus = Focus.of(context).hasFocus;
                      return SizedBox(
                        key: _guardarKey,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _saveAndClose,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kConfigAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: hasFocus
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: const Text(
                            'Guardar y continuar',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
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