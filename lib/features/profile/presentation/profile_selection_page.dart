import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../supabase/supabase_client.dart';
import '../../../supabase/supabase_config.dart';
import '../../../supabase/supabase_users.dart';
import '../../../presentation/mobile/mobile_shell.dart' as mobile;
import '../../../presentation/tv/tv_shell.dart' as tv;

const _kAccent = Color(0xFFE50914);

/// Pantalla de selección de perfiles (diseño Netflix).
/// Al elegir perfil SIEMPRE navega al home (no depende del Splash).
class ProfileSelectionPage extends StatefulWidget {
  final VoidCallback? onProfileSelected;
  final Widget Function()? buildHome;
  final bool allowDismiss;

  const ProfileSelectionPage({
    super.key,
    this.onProfileSelected,
    this.buildHome,
    this.allowDismiss = false,
  });

  @override
  State<ProfileSelectionPage> createState() => _ProfileSelectionPageState();
}

class _ProfileSelectionPageState extends State<ProfileSelectionPage> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  bool _creating = false;
  bool _busy = false;
  String? _currentId;
  final _nameCtrl = TextEditingController();

  static const _bgImages = [
    'https://image.tmdb.org/t/p/original/4kTINu9mv2YV1PqFqPGG1FZMnhi.jpg',
    'https://image.tmdb.org/t/p/original/yr1n2RzZHn1UYozrzvPzjcE60cP.jpg',
    'https://image.tmdb.org/t/p/original/cFXxKJzGrvjcmMJAReNekx0RVJb.jpg',
    'https://image.tmdb.org/t/p/original/viZqGq9TNvQ5uXSD4ahg2RpRONT.jpg',
    'https://image.tmdb.org/t/p/original/HxkNuj4kinoukZzr8IvtHAMTRo.jpg',
  ];
  int _bgIndex = 0;
  Timer? _bgTimer;

  final List<FocusNode> _profileNodes = [];
  late final FocusNode _createNode;
  late final FocusNode _guestNode;
  final FocusNode _dialogNameNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _createNode = FocusNode(debugLabel: 'profile_create');
    _guestNode = FocusNode(debugLabel: 'profile_guest');
    _load();
    _bgTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      setState(() => _bgIndex = (_bgIndex + 1) % _bgImages.length);
    });
  }

  @override
  void dispose() {
    _bgTimer?.cancel();
    _nameCtrl.dispose();
    for (final n in _profileNodes) {
      n.dispose();
    }
    _createNode.dispose();
    _guestNode.dispose();
    _dialogNameNode.dispose();
    super.dispose();
  }

  void _syncFocusNodes(int n) {
    while (_profileNodes.length < n) {
      _profileNodes.add(FocusNode(debugLabel: 'profile_${_profileNodes.length}'));
    }
    while (_profileNodes.length > n) {
      _profileNodes.removeLast().dispose();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await AppSupabase.init();
      final list = await SupabaseUsers.list();
      final current = await SupabaseConfig.getCurrentUserId();
      if (!mounted) return;
      _syncFocusNodes(list.length);
      setState(() {
        _profiles = list;
        _currentId = current;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profiles = [];
        _loading = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_profileNodes.isNotEmpty) {
        _profileNodes.first.requestFocus();
      } else {
        _createNode.requestFocus();
      }
    });
  }

  Future<Widget> _resolveHome() async {
    if (widget.buildHome != null) return widget.buildHome!();
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('app_mode') ?? 'mobile';
    if (mode == 'tv') return const tv.MainHome();
    return const mobile.MainHome();
  }

  Future<void> _enterApp() async {
    if (!mounted) return;

    if (widget.allowDismiss && widget.buildHome == null) {
      widget.onProfileSelected?.call();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    final home = await _resolveHome();
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => home,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
      (route) => false,
    );
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final id = profile['id']?.toString() ?? '';
      final name = profile['name']?.toString() ?? 'Usuario';
      if (id.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Perfil inválido (sin id)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _busy = false);
        return;
      }

      await SupabaseConfig.setCurrentUser(userId: id, userName: name);

      final ok = await SupabaseConfig.isLoggedIn();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo guardar la sesión del perfil'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _busy = false);
        return;
      }

      await _enterApp();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al entrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _continueAsGuest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SupabaseConfig.clearCurrentUser();
      await _enterApp();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _createProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _profiles.length >= 5) return;
    setState(() => _creating = true);
    final profile = await SupabaseUsers.create(name: name);
    if (!mounted) return;
    setState(() => _creating = false);
    if (profile != null) {
      _nameCtrl.clear();
      await _selectProfile(profile);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo crear el perfil. Revisa tablas SQL y conexión.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteProfile(Map<String, dynamic> profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Eliminar perfil', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Eliminar "${profile['name']}" y sus guardados en la nube?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await SupabaseUsers.delete(profile['id'].toString());
      await _load();
    }
  }

  // ── Tamaños adaptativos ────────────────────────────────────────────────

  double _circleRadius(Size size, {required bool isPortrait}) {
    final side = size.shortestSide;
    if (isPortrait) {
      // Más grandes en vertical
      if (side < 360) return 48;
      if (side < 420) return 56;
      if (side < 500) return 62;
      return 68;
    }
    // Landscape / TV (igual que antes)
    if (side < 400) return 42;
    if (side < 600) return 52;
    if (side < 900) return 62;
    return 72;
  }

  double _titleSize(Size size) {
    final side = size.shortestSide;
    if (side < 500) return 24;
    if (side < 800) return 30;
    return 36;
  }

  int _getCols(Size size, {required bool isPortrait}) {
    if (!isPortrait) return 5; // TV / landscape → igual que siempre
    // Vertical / móvil
    if (size.width > 480) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height * 1.15;
    final isPortrait = !isLandscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1200),
            child: Image.network(
              _bgImages[_bgIndex],
              key: ValueKey(_bgIndex),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => Container(color: Colors.black),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(color: Colors.black);
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.55),
                  Colors.black.withOpacity(0.75),
                  Colors.black.withOpacity(0.85),
                ],
              ),
            ),
          ),
          if (widget.allowDismiss)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 28),
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.35),
                  shape: const CircleBorder(),
                ),
              ),
            ),
          if (_busy)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: _kAccent),
              ),
            ),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _kAccent))
                : IgnorePointer(
                    ignoring: _busy,
                    child: Column(
                      children: [
                        SizedBox(height: isLandscape ? 20 : 28),
                        Text(
                          '¿Quién está viendo?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _titleSize(size),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.8),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Selecciona un perfil',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: size.shortestSide < 500 ? 13 : 15,
                          ),
                        ),
                        SizedBox(height: isLandscape ? 28 : 32),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isLandscape ? size.width * 0.9 : 420,
                              ),
                              child: _buildProfilesGrid(size, isPortrait: isPortrait),
                            ),
                          ),
                        ),
                        if (!widget.allowDismiss) ...[
                          const SizedBox(height: 8),
                          Focus(
                            focusNode: _guestNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }
                              final key = event.logicalKey;
                              if (key == LogicalKeyboardKey.arrowUp) {
                                if (_profileNodes.isNotEmpty) {
                                  _profileNodes.first.requestFocus();
                                } else {
                                  _createNode.requestFocus();
                                }
                                return KeyEventResult.handled;
                              }
                              if (key == LogicalKeyboardKey.enter ||
                                  key == LogicalKeyboardKey.select ||
                                  key == LogicalKeyboardKey.space) {
                                _continueAsGuest();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (ctx) {
                                final focused = Focus.of(ctx).hasFocus;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: TextButton(
                                    onPressed: _continueAsGuest,
                                    style: TextButton.styleFrom(
                                      foregroundColor: focused
                                          ? Colors.white
                                          : Colors.white54,
                                      backgroundColor: focused
                                          ? Colors.white.withOpacity(0.12)
                                          : Colors.transparent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        side: BorderSide(
                                          color: focused
                                              ? Colors.white60
                                              : Colors.white24,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'Entrar como invitado',
                                      style: TextStyle(
                                        fontSize: size.shortestSide < 500
                                            ? 13
                                            : 14,
                                        fontWeight: focused
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ] else
                          const SizedBox(height: 20),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilesGrid(Size size, {required bool isPortrait}) {
    final radius = _circleRadius(size, isPortrait: isPortrait);
    final canCreate = _profiles.length < 5;
    final items = <Widget>[];

    for (int i = 0; i < _profiles.length; i++) {
      items.add(_buildProfileCircle(_profiles[i], i, radius, size, isPortrait: isPortrait));
    }
    if (canCreate) {
      items.add(_buildCreateCircle(radius, size, isPortrait: isPortrait));
    }

    // ── Landscape / TV → Grid de 5 columnas (igual que siempre) ─────────
    if (!isPortrait) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 20,
          crossAxisSpacing: 16,
          childAspectRatio: 0.78,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      );
    }

    // ── Portrait / Móvil → Wrap centrado (2-3 por fila + último centrado) ─
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 22,
        children: items.map((w) {
          return SizedBox(
            width: radius * 2 + 12,
            child: w,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProfileCircle(
    Map<String, dynamic> profile,
    int index,
    double radius,
    Size size, {
    required bool isPortrait,
  }) {
    final name = profile['name']?.toString() ?? 'Usuario';
    final id = profile['id']?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final isCurrent = id == _currentId;
    final node = _profileNodes[index];
    final cols = _getCols(size, isPortrait: isPortrait);

    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.arrowRight) {
          final next = index + 1;
          if (next < _profiles.length) {
            _profileNodes[next].requestFocus();
          } else if (_profiles.length < 5) {
            _createNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (index > 0) _profileNodes[index - 1].requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          final below = index + cols;
          if (below < _profiles.length) {
            _profileNodes[below].requestFocus();
          } else if (below == _profiles.length && _profiles.length < 5) {
            _createNode.requestFocus();
          } else if (!widget.allowDismiss) {
            _guestNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          final above = index - cols;
          if (above >= 0) _profileNodes[above].requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.space) {
          _selectProfile(profile);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: () => _selectProfile(profile),
            onLongPress: () => _deleteProfile(profile),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: radius * 2,
                  height: radius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1a1a2e),
                    border: Border.all(
                      color: focused
                          ? Colors.white
                          : isCurrent
                              ? _kAccent
                              : Colors.white24,
                      width: focused ? 3.5 : (isCurrent ? 2.5 : 1.5),
                    ),
                    boxShadow: focused
                        ? [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.35),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: focused || isCurrent ? _kAccent : Colors.white70,
                      fontSize: radius * 0.78,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: focused ? Colors.white : Colors.white70,
                    fontSize: size.shortestSide < 500 ? 13 : 14,
                    fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (isCurrent)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Activo',
                      style: TextStyle(color: _kAccent, fontSize: 11),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCreateCircle(double radius, Size size, {required bool isPortrait}) {
    return Focus(
      focusNode: _createNode,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (_profileNodes.isNotEmpty) _profileNodes.last.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (!widget.allowDismiss) _guestNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.space) {
          _showCreateDialog();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: _showCreateDialog,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: radius * 2,
                  height: radius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.35),
                    border: Border.all(
                      color: focused ? Colors.white : Colors.white38,
                      width: focused ? 3.5 : 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    color: focused ? Colors.white : Colors.white54,
                    size: radius * 0.95,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Crear perfil',
                  style: TextStyle(
                    color: focused ? Colors.white : Colors.white54,
                    fontSize: size.shortestSide < 500 ? 13 : 14,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog() {
    if (_profiles.length >= 5) return;
    _nameCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14141f),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nuevo perfil', style: TextStyle(color: Colors.white)),
          content: TextField(
            focusNode: _dialogNameNode,
            controller: _nameCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            cursorColor: _kAccent,
            decoration: const InputDecoration(
              hintText: 'Nombre del perfil',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _kAccent),
              ),
            ),
            onSubmitted: (_) {
              Navigator.pop(ctx);
              _createProfile();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _createProfile();
              },
              child: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
                    )
                  : const Text('Crear', style: TextStyle(color: _kAccent)),
            ),
          ],
        );
      },
    );
  }
}