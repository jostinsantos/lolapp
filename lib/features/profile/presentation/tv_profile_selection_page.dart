import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../supabase/supabase_auth.dart';
import '../../../supabase/supabase_client.dart';
import '../../../supabase/supabase_config.dart';
import '../../../supabase/supabase_profiles.dart';
import '../../auth/presentation/tv_login_register_page.dart';
import '../../../presentation/tv/tv_shell.dart' as tv;
import 'tv_edit_profile_page.dart';

class TvProfileSelectionPage extends StatefulWidget {
  final VoidCallback? onProfileSelected;
  final bool allowDismiss;

  const TvProfileSelectionPage({
    super.key,
    this.onProfileSelected,
    this.allowDismiss = false,
  });

  @override
  State<TvProfileSelectionPage> createState() => _TvProfileSelectionPageState();
}

class _TvProfileSelectionPageState extends State<TvProfileSelectionPage> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  String? _error;
  bool _editMode = false;

  static const _fallbackBackdrop =
      'https://static.crunchyroll.com/assets/wallpaper/1920x1080/crbrand_product_multipleprofilesbackgroundassets_4k-08.png';

  /// Backdrop del perfil enfocado
  String? _focusedBackdrop;

  final List<FocusNode> _profileFocus = [];
  final FocusNode _guestFocus = FocusNode(debugLabel: 'tv_guest');
  final FocusNode _loginFocus = FocusNode(debugLabel: 'tv_login');
  final FocusNode _manageFocus = FocusNode(debugLabel: 'tv_manage');
  final FocusNode _logoutFocus = FocusNode(debugLabel: 'tv_logout');
  final FocusNode _addFocus = FocusNode(debugLabel: 'tv_add');

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestInitialFocus();
    });
  }

  @override
  void dispose() {
    for (final n in _profileFocus) {
      n.dispose();
    }
    _guestFocus.dispose();
    _loginFocus.dispose();
    _manageFocus.dispose();
    _logoutFocus.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _syncProfileFocus(int count) {
    while (_profileFocus.length > count) {
      _profileFocus.removeLast().dispose();
    }
    while (_profileFocus.length < count) {
      _profileFocus.add(FocusNode(debugLabel: 'tv_profile_${_profileFocus.length}'));
    }
  }

  void _requestInitialFocus() {
    if (!mounted) return;
    FocusNode? target;
    if (_profiles.isNotEmpty && _profileFocus.isNotEmpty) {
      target = _profileFocus.first;
    } else if (SupabaseAuth.isLoggedIn) {
      target = _addFocus;
    } else {
      target = _guestFocus;
    }
    target.requestFocus();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await AppSupabase.init();

    if (!SupabaseAuth.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _profiles = [];
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _guestFocus.requestFocus();
      });
      return;
    }

    try {
      final list = await SupabaseProfiles.list();
      if (!mounted) return;
      _syncProfileFocus(list.length);
      setState(() {
        _profiles = list;
        _loading = false;
      });

      if (list.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _addFocus.requestFocus();
        });
      } else if (list.length == 1) {
        final only = list.first;
        final hasPin = (only['pin']?.toString() ?? '').isNotEmpty;
        if (!hasPin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _selectProfile(only);
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_profileFocus.isNotEmpty) {
              _profileFocus.first.requestFocus();
            } else {
              _addFocus.requestFocus();
            }
          });
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_profileFocus.isNotEmpty) {
            _profileFocus.first.requestFocus();
          } else {
            _addFocus.requestFocus();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar perfiles: $e';
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (SupabaseAuth.isLoggedIn) {
          _manageFocus.requestFocus();
        } else {
          _guestFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _onProfileTap(Map<String, dynamic> profile) async {
    if (_editMode) {
      await _openEdit(profile);
    } else {
      await _selectProfile(profile);
    }
  }

  Future<void> _openEdit(Map<String, dynamic> profile) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TvEditProfilePage(profile: profile),
      ),
    );
    if (result == true && mounted) {
      await _load();
    }
  }

  Future<void> _openCreate() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const TvEditProfilePage(),
      ),
    );
    if (result == true && mounted) {
      await _load();
      final id = await SupabaseConfig.getCurrentProfileId();
      if (id != null && mounted && _profiles.isNotEmpty) {
        final match = _profiles.firstWhere(
          (p) => p['id'].toString() == id,
          orElse: () => _profiles.first,
        );
        await _selectProfile(match);
      }
    }
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    final hasPin = (profile['pin']?.toString() ?? '').isNotEmpty;

    if (hasPin) {
      final pin = await _askPinTvModal();
      if (pin == null) return;
      final ok = await SupabaseProfiles.select(profile, pinInput: pin);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN incorrecto')),
          );
        }
        return;
      }
    } else {
      await SupabaseProfiles.select(profile);
    }

    await _finishSelection();
  }

  Future<void> _finishSelection() async {
    widget.onProfileSelected?.call();
    if (!mounted) return;
    if (widget.allowDismiss) {
      await _goToHome();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _goToHome() async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const tv.MainHome(),
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
      (_) => false,
    );
  }

  Future<String?> _askPinTvModal() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _TvPinDialog(),
    );
    return result;
  }

  Future<void> _enterAsGuest() async {
    await SupabaseConfig.setGuestMode();
    await _finishSelection();
  }

  Future<void> _goLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TvLoginRegisterPage(onSuccess: () {}),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  String get _backdropUrl {
    if (_focusedBackdrop != null && _focusedBackdrop!.isNotEmpty) {
      return _focusedBackdrop!;
    }
    for (final p in _profiles) {
      final bd = p['backdrop_url']?.toString();
      if (bd != null && bd.isNotEmpty) return bd;
    }
    return _fallbackBackdrop;
  }

  void _onProfileFocus(Map<String, dynamic>? profile) {
    final bd = profile?['backdrop_url']?.toString();
    final next = (bd != null && bd.isNotEmpty) ? bd : _fallbackBackdrop;
    if (_focusedBackdrop != next) {
      setState(() => _focusedBackdrop = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _backdropUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: Image.network(
              bg,
              key: ValueKey(bg),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.black),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.55),
                  Colors.black.withOpacity(0.85),
                  Colors.black,
                ],
              ),
            ),
          ),
          SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Column(
                    children: [
                      const SizedBox(height: 28),
                      Text(
                        _editMode ? 'Gestionar perfiles' : '¿Quién está viendo?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_editMode)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Selecciona un perfil para editarlo',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ...List.generate(_profiles.length, (i) {
                                  final p = _profiles[i];
                                  return _TvProfileCard(
                                    focusNode: _profileFocus[i],
                                    name: p['name']?.toString() ?? 'Usuario',
                                    avatarUrl: p['avatar_url']?.toString(),
                                    editMode: _editMode,
                                    onTap: () => _onProfileTap(p),
                                    onFocused: () => _onProfileFocus(p),
                                  );
                                }),
                                if (SupabaseAuth.isLoggedIn && _profiles.length < 5)
                                  _TvProfileCard(
                                    focusNode: _addFocus,
                                    name: _editMode ? 'Crear' : 'Añadir',
                                    isAdd: true,
                                    onTap: _openCreate,
                                    onFocused: () => _onProfileFocus(null),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!SupabaseAuth.isLoggedIn) ...[
                              _TvTextButton(
                                focusNode: _guestFocus,
                                icon: Icons.person_outline,
                                label: 'Entrar como invitado',
                                onTap: _enterAsGuest,
                              ),
                              const SizedBox(width: 20),
                              _TvTextButton(
                                focusNode: _loginFocus,
                                icon: Icons.login,
                                label: 'Iniciar sesión / Crear cuenta',
                                onTap: _goLogin,
                              ),
                            ],
                            if (SupabaseAuth.isLoggedIn) ...[
                              _TvTextButton(
                                focusNode: _guestFocus,
                                icon: Icons.person_outline,
                                label: 'Entrar como invitado',
                                onTap: _enterAsGuest,
                              ),
                              const SizedBox(width: 20),
                              _TvTextButton(
                                focusNode: _manageFocus,
                                icon: _editMode ? Icons.check : Icons.edit,
                                label: _editMode ? 'Listo' : 'Gestionar perfiles',
                                onTap: () {
                                  setState(() => _editMode = !_editMode);
                                },
                                highlighted: _editMode,
                              ),
                              const SizedBox(width: 20),
                              _TvTextButton(
                                focusNode: _logoutFocus,
                                icon: Icons.logout,
                                label: 'Cerrar sesión',
                                onTap: () async {
                                  await SupabaseAuth.signOut();
                                  _load();
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// Modal de PIN para TV: compacto, teclado numérico navegable.
/// Se cierra solo al completar los 6 dígitos.
/// La última tecla de la cuadrícula es "×" para cancelar
/// (mismo espacio que antes ocupaba el check).
/// ============================================================
class _TvPinDialog extends StatefulWidget {
  const _TvPinDialog();

  @override
  State<_TvPinDialog> createState() => _TvPinDialogState();
}

class _TvPinDialogState extends State<_TvPinDialog> {
  String _pin = '';
  static const int _maxLen = 6;

  static const List<String> _keys = [
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '⌫', '0', '×',
  ];

  late final List<FocusNode> _keyFocus;

  @override
  void initState() {
    super.initState();
    _keyFocus = List.generate(
      _keys.length,
      (i) => FocusNode(debugLabel: 'pin_key_$i'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyFocus[4].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final n in _keyFocus) {
      n.dispose();
    }
    super.dispose();
  }

  void _onKey(String k) {
    if (k == '×') {
      Navigator.pop(context);
      return;
    }
    if (k == '⌫') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
      return;
    }
    if (_pin.length >= _maxLen) return;
    setState(() => _pin += k);
    if (_pin.length == _maxLen) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) Navigator.pop(context, _pin);
      });
    }
  }

  void _moveFocus(int index, int dx, int dy) {
    final row = index ~/ 3;
    final col = index % 3;
    int nextRow = row;
    int nextCol = col;

    if (dy != 0) nextRow = (row + dy).clamp(0, 3);
    if (dx != 0) nextCol = (col + dx).clamp(0, 2);

    final next = nextRow * 3 + nextCol;
    if (next != index) {
      _keyFocus[next].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
      child: Container(
        width: 260,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PIN de seguridad',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Introduce el PIN para entrar a este perfil',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 10.5),
            ),
            const SizedBox(height: 12),

            _PinDisplay(pin: _pin, maxLen: _maxLen),
            const SizedBox(height: 12),

            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < 4; r++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var c = 0; c < 3; c++)
                          _PinKey(
                            keyLabel: _keys[r * 3 + c],
                            focusNode: _keyFocus[r * 3 + c],
                            onTap: () => _onKey(_keys[r * 3 + c]),
                            onArrow: (dx, dy) =>
                                _moveFocus(r * 3 + c, dx, dy),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PinDisplay extends StatelessWidget {
  final String pin;
  final int maxLen;

  const _PinDisplay({required this.pin, required this.maxLen});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxLen, (i) {
        final filled = i < pin.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 22,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: filled ? Colors.white : Colors.white24,
              width: filled ? 1.6 : 1.1,
            ),
          ),
          child: filled
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        );
      }),
    );
  }
}

/// Tecla del teclado numérico.
/// Foco: fondo blanco, letra negra. Sin foco: fondo sutil, letra blanca.
class _PinKey extends StatefulWidget {
  final String keyLabel;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final void Function(int dx, int dy) onArrow;

  const _PinKey({
    required this.keyLabel,
    required this.focusNode,
    required this.onTap,
    required this.onArrow,
  });

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  bool get _isBack => widget.keyLabel == '⌫';
  bool get _isClose => widget.keyLabel == '×';

  @override
  Widget build(BuildContext context) {
    final bg = _focused ? Colors.white : Colors.white.withOpacity(0.08);
    final fg = _focused
        ? Colors.black
        : (_isClose ? Colors.redAccent : Colors.white);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final k = event.logicalKey;
          if (k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowLeft) {
            widget.onArrow(-1, 0);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight) {
            widget.onArrow(1, 0);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowUp) {
            widget.onArrow(0, -1);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowDown) {
            widget.onArrow(0, 1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 44,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: _focused ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.25),
                        blurRadius: 8,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: _isBack
                ? Icon(Icons.backspace_outlined, color: fg, size: 17)
                : _isClose
                    ? Icon(Icons.close, color: fg, size: 19)
                    : Text(
                        widget.keyLabel,
                        style: TextStyle(
                          color: fg,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}

class _TvProfileCard extends StatefulWidget {
  final FocusNode focusNode;
  final String name;
  final String? avatarUrl;
  final bool isAdd;
  final bool isGuest;
  final bool editMode;
  final VoidCallback onTap;
  final VoidCallback? onFocused;

  const _TvProfileCard({
    required this.focusNode,
    required this.name,
    this.avatarUrl,
    this.isAdd = false,
    this.isGuest = false,
    this.editMode = false,
    required this.onTap,
    this.onFocused,
  });

  @override
  State<_TvProfileCard> createState() => _TvProfileCardState();
}

class _TvProfileCardState extends State<_TvProfileCard> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (!mounted) return;
    final has = widget.focusNode.hasFocus;
    setState(() => _focused = has);
    if (has) widget.onFocused?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onTap();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: _focused
                ? (Matrix4.identity()..scale(1.06))
                : Matrix4.identity(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(
                          color: _focused
                              ? Colors.white
                              : (widget.editMode && !widget.isAdd
                                  ? Colors.redAccent.withOpacity(0.6)
                                  : Colors.white24),
                          width: _focused ? 3 : 1.5,
                        ),
                        boxShadow: _focused
                            ? [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.35),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: widget.isAdd
                          ? const Icon(Icons.add, size: 40, color: Colors.white70)
                          : widget.isGuest
                              ? const Icon(Icons.person_outline,
                                  size: 40, color: Colors.white70)
                              : widget.avatarUrl != null &&
                                      widget.avatarUrl!.isNotEmpty
                                  ? Image.network(
                                      widget.avatarUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.person,
                                        size: 40,
                                        color: Colors.white70,
                                      ),
                                    )
                                  : const Icon(Icons.person,
                                      size: 40, color: Colors.white70),
                    ),
                    if (widget.editMode && !widget.isAdd && !widget.isGuest)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.edit,
                              color: Colors.white, size: 14),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.name,
                  style: TextStyle(
                    color: _focused ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: _focused ? FontWeight.w700 : FontWeight.w500,
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

class _TvTextButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  const _TvTextButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  State<_TvTextButton> createState() => _TvTextButtonState();
}

class _TvTextButtonState extends State<_TvTextButton> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.highlighted
        ? Colors.redAccent.withOpacity(0.85)
        : (_focused ? Colors.white.withOpacity(0.12) : Colors.transparent);
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : (widget.highlighted ? Colors.redAccent : Colors.transparent),
              width: 2,
            ),
            color: bg,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  color: _focused ? Colors.white : Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _focused ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: _focused ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}