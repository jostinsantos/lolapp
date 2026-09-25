import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const Color kConfigAccent = Color(0xFFFF6B00);
const Color kConfigBg = Color(0xFF0A0A0A);
const Color kConfigCard = Color(0xFF1C1C1E);

class MenuPositionPref {
  static const key = 'menu_position';

  static Future<String> get() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(key) ?? 'top';
  }

  static Future<void> set(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
    version.value++;
  }

  static final ValueNotifier<int> version = ValueNotifier(0);
}

enum IdiomaPred {
  latino('es_MX', 'Español Latino'),
  castellano('es_ES', 'Español Castellano'),
  subtitulado('sub', 'Subtitulado en español');

  final String code;
  final String label;
  const IdiomaPred(this.code, this.label);
}

enum SubSize {
  pequeno(16.0, 'Pequeño'),
  mediano(22.0, 'Mediano'),
  grande(28.0, 'Grande');

  final double size;
  final String label;
  const SubSize(this.size, this.label);
}

Future<void> saveBool(String key, bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(key, value);
}

Future<void> saveString(String key, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
}

Future<void> openExternalUrl(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.parse(url);
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(uri);
    }
  } catch (e) {
    debugPrint('Error abriendo enlace: $e');
  }
}

void _scrollIntoView(FocusNode focusNode, {double alignment = 0.25}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = focusNode.context;
    if (ctx == null || !ctx.mounted) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: alignment,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  });
}

Future<bool?> confirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required Color accent,
  String confirmLabel = 'Activar',
}) {
  final focusCancel = FocusNode();
  final focusConfirm = FocusNode();
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusConfirm.requestFocus();
      });
      return AlertDialog(
        backgroundColor: kConfigCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          Focus(
            focusNode: focusCancel,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                focusConfirm.requestFocus();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter) {
                Navigator.pop(context, false);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancelar',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
          ),
          Focus(
            focusNode: focusConfirm,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                focusCancel.requestFocus();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter) {
                Navigator.pop(context, true);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(confirmLabel),
            ),
          ),
        ],
      );
    },
  ).whenComplete(() {
    focusCancel.dispose();
    focusConfirm.dispose();
  });
}

Widget sectionTitle(String text, {bool first = false}) {
  return Padding(
    padding: EdgeInsets.fromLTRB(4, first ? 0 : 12, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class SourceToggleCard extends StatelessWidget {
  final String title;
  final String subtitleEnabled;
  final String subtitleDisabled;
  final bool enabled;
  final bool loading;
  final IconData icon;
  final Color accentColor;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;
  final VoidCallback? onArrowLeft;

  const SourceToggleCard({
    super.key,
    required this.title,
    required this.subtitleEnabled,
    required this.subtitleDisabled,
    required this.enabled,
    required this.loading,
    required this.icon,
    required this.accentColor,
    required this.focusNode,
    required this.onTap,
    required this.onArrowUp,
    required this.onArrowDown,
    this.onArrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onArrowLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) _scrollIntoView(focusNode);
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              focusNode.requestFocus();
              onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: kConfigCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.08),
                  width: hasFocus ? 2.5 : 1.5,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: enabled
                          ? accentColor.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      icon,
                      color: enabled ? accentColor : Colors.white70,
                      size: 22,
                    ),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          loading
                              ? 'Cargando...'
                              : (enabled ? subtitleEnabled : subtitleDisabled),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 52,
                    height: 30,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: enabled
                          ? accentColor
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                    child: Align(
                      alignment:
                          enabled ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
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

class FocusActionCard extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;
  final VoidCallback? onArrowLeft;

  const FocusActionCard({
    super.key,
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    required this.onArrowUp,
    required this.onArrowDown,
    this.onArrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onArrowLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) _scrollIntoView(focusNode);
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              focusNode.requestFocus();
              onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: kConfigCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.08),
                  width: hasFocus ? 2.5 : 1.5,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: kConfigAccent.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: Colors.white70, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 22,
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

class IdiomaSelectorCard extends StatelessWidget {
  final FocusNode focusNode;
  final IdiomaPred selected;
  final ValueChanged<IdiomaPred> onSelect;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;
  final VoidCallback? onArrowLeft;

  const IdiomaSelectorCard({
    super.key,
    required this.focusNode,
    required this.selected,
    required this.onSelect,
    required this.onArrowUp,
    required this.onArrowDown,
    this.onArrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          // Primera opción: ← vuelve a tabs si hay callback
          final idx = IdiomaPred.values.indexOf(selected);
          if (idx <= 0 && onArrowLeft != null) {
            onArrowLeft!();
            return KeyEventResult.handled;
          }
          final next = (idx - 1 + IdiomaPred.values.length) %
              IdiomaPred.values.length;
          onSelect(IdiomaPred.values[next]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          final idx = IdiomaPred.values.indexOf(selected);
          onSelect(IdiomaPred.values[(idx + 1) % IdiomaPred.values.length]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          final idx = IdiomaPred.values.indexOf(selected);
          onSelect(IdiomaPred.values[(idx + 1) % IdiomaPred.values.length]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) _scrollIntoView(focusNode);
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: kConfigCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.08),
                width: hasFocus ? 2.5 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.translate_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Elegir idioma',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: IdiomaPred.values.map((idioma) {
                    final isSel = selected == idioma;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => onSelect(idioma),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? kConfigAccent.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                    isSel ? kConfigAccent : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              idioma.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.white70,
                                fontSize: 12,
                                fontWeight: isSel
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SubSizeSelectorCard extends StatelessWidget {
  final FocusNode focusNode;
  final SubSize selected;
  final ValueChanged<SubSize> onSelect;
  final VoidCallback onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowLeft;

  const SubSizeSelectorCard({
    super.key,
    required this.focusNode,
    required this.selected,
    required this.onSelect,
    required this.onArrowUp,
    this.onArrowDown,
    this.onArrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          final idx = SubSize.values.indexOf(selected);
          if (idx <= 0 && onArrowLeft != null) {
            onArrowLeft!();
            return KeyEventResult.handled;
          }
          final next =
              (idx - 1 + SubSize.values.length) % SubSize.values.length;
          onSelect(SubSize.values[next]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          final idx = SubSize.values.indexOf(selected);
          onSelect(SubSize.values[(idx + 1) % SubSize.values.length]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          final idx = SubSize.values.indexOf(selected);
          onSelect(SubSize.values[(idx + 1) % SubSize.values.length]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) _scrollIntoView(focusNode);
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: kConfigCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.08),
                width: hasFocus ? 2.5 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.format_size_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Tamaño de subtítulos',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: SubSize.values.map((s) {
                    final isSel = selected == s;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => onSelect(s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? kConfigAccent.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                    isSel ? kConfigAccent : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              s.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.white70,
                                fontSize: 13,
                                fontWeight: isSel
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MenuPositionCard extends StatelessWidget {
  final FocusNode focusNode;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;
  final VoidCallback? onArrowLeft;

  const MenuPositionCard({
    super.key,
    required this.focusNode,
    required this.selected,
    required this.onSelect,
    required this.onArrowUp,
    required this.onArrowDown,
    this.onArrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (selected == 'top' && onArrowLeft != null) {
            onArrowLeft!();
          } else {
            onSelect('top');
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onSelect(selected == 'top' ? 'side' : 'top');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) _scrollIntoView(focusNode);
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: kConfigCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.08),
                width: hasFocus ? 2.5 : 1.5,
              ),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: kConfigAccent.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.menu_open_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Posición del menú',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Superior (arriba) o lateral (izquierda)',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _chip(
                        'Superior',
                        Icons.horizontal_rule_rounded,
                        'top',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _chip(
                        'Lateral',
                        Icons.view_sidebar_rounded,
                        'side',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, IconData icon, String value) {
    final isSel = selected == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSel
              ? kConfigAccent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? kConfigAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSel ? Colors.white : Colors.white70),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSel ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VerticalOffsetCard extends StatelessWidget {
  final FocusNode focusNode;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onArrowUp;
  final VoidCallback? onArrowLeftToTabs;

  const VerticalOffsetCard({
    super.key,
    required this.focusNode,
    required this.value,
    required this.onChanged,
    required this.onArrowUp,
    this.onArrowLeftToTabs,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          // En el mínimo, ← puede volver a tabs
          if (value <= -80 && onArrowLeftToTabs != null) {
            onArrowLeftToTabs!();
          } else {
            onChanged((value - 5).clamp(-80.0, 80.0));
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          onChanged((value + 5).clamp(-80.0, 80.0));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onChanged(0);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) _scrollIntoView(focusNode, alignment: 0.3);
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          final label = value == 0
              ? 'Centrado'
              : (value > 0 ? '+${value.round()} px' : '${value.round()} px');
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: kConfigCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.08),
                width: hasFocus ? 2.5 : 1.5,
              ),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: kConfigAccent.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.swap_vert_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Desplazamiento vertical',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '← → ajusta · OK resetea · $label',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: hasFocus ? kConfigAccent : Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: hasFocus ? 10 : 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    activeTrackColor: kConfigAccent,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                    thumbColor: hasFocus ? Colors.white : kConfigAccent,
                    overlayColor: kConfigAccent.withValues(alpha: 0.25),
                  ),
                  child: Slider(
                    value: value.clamp(-80.0, 80.0),
                    min: -80,
                    max: 80,
                    divisions: 32,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}