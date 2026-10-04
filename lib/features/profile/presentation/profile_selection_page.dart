import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../supabase/supabase_auth.dart';
import '../../../supabase/supabase_client.dart';
import '../../../supabase/supabase_config.dart';
import '../../../supabase/supabase_profiles.dart';
import '../../auth/presentation/login_register_page.dart';
import '../../../presentation/mobile/mobile_shell.dart' as mobile;
import '../../../presentation/tv/tv_shell.dart' as tv;
// ⚠️ Ajusta esta ruta a la ubicación real del editor de perfil
import 'tv_edit_profile_page.dart';

/// Pantalla de elegir perfil (estilo Netflix).
/// Muestra los perfiles de la cuenta + opción invitado + crear perfil.
/// En móvil usa cuadrícula 2 columnas (último impar centrado).
/// Permite modo edición: al tocar un perfil se abre el editor directamente.
class ProfileSelectionPage extends StatefulWidget {
  final VoidCallback? onProfileSelected;
  final bool allowDismiss;

  const ProfileSelectionPage({
    super.key,
    this.onProfileSelected,
    this.allowDismiss = false,
  });

  @override
  State<ProfileSelectionPage> createState() => _ProfileSelectionPageState();
}

class _ProfileSelectionPageState extends State<ProfileSelectionPage> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  String? _error;
  bool _editMode = false;

  // Fallback cuando no hay perfil o no tiene backdrop
  static const _fallbackBackdrop =
      'https://static.crunchyroll.com/assets/wallpaper/360x115/crbrand_product_multipleprofilesbackgroundassets_4k-08.png';

  /// Backdrop del perfil sobre el que se pasa el mouse / se enfoca
  String? _hoveredBackdrop;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
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
      return;
    }

    try {
      final list = await SupabaseProfiles.list();
      if (!mounted) return;
      setState(() {
        _profiles = list;
        _loading = false;
      });

      // Si está logueado y no tiene perfiles → abrir crear perfil
      if (list.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openEditor();
        });
      } else if (list.length == 1 && !_editMode) {
        // Un solo perfil → auto-seleccionar (salvo que tenga PIN)
        final only = list.first;
        final hasPin = (only['pin']?.toString() ?? '').isNotEmpty;
        if (!hasPin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _selectProfile(only);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar perfiles: $e';
        _loading = false;
      });
    }
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    final hasPin = (profile['pin']?.toString() ?? '').isNotEmpty;

    if (hasPin) {
      final pin = await _askPin();
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

  /// Abre el editor de perfil directamente (crear si no se pasa perfil,
  /// editar si se pasa uno existente).
  Future<void> _openEditor({Map<String, dynamic>? profile}) async {
    final isCreating = profile == null;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TvEditProfilePage(profile: profile),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      // Si acabamos de crear un perfil, ya se auto-seleccionó dentro del editor.
      if (isCreating) {
        final id = await SupabaseConfig.getCurrentProfileId();
        if (id != null && mounted) {
          await _finishSelection();
          return;
        }
      }
      // Si editamos, recargamos la lista.
      await _load();
    }
  }

  /// Alterna modo edición.
  void _toggleEditMode() {
    setState(() => _editMode = !_editMode);
  }

  /// Tap sobre un perfil: en modo edición abre el editor, si no selecciona.
  Future<void> _onProfileTap(Map<String, dynamic> profile) async {
    if (_editMode) {
      await _openEditor(profile: profile);
    } else {
      await _selectProfile(profile);
    }
  }

  /// Tras elegir perfil (o invitado): callback + salir.
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
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('app_mode') ?? 'mobile';
    final Widget home =
        mode == 'tv' ? const tv.MainHome() : const mobile.MainHome();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => home,
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
      (_) => false,
    );
  }

  Future<String?> _askPin() async {
    final ctrl = TextEditingController();
    final pinFocus = FocusNode();
    final okFocus = FocusNode();
    final cancelFocus = FocusNode();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          pinFocus.requestFocus();
        });
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'PIN de seguridad',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Introduce el PIN para entrar a este perfil',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                focusNode: pinFocus,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  letterSpacing: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '••••',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    letterSpacing: 12,
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
          actions: [
            TextButton(
              focusNode: cancelFocus,
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              focusNode: okFocus,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Entrar'),
            ),
          ],
        );
      },
    );

    pinFocus.dispose();
    okFocus.dispose();
    cancelFocus.dispose();
    ctrl.dispose();
    return result;
  }

  Future<void> _enterAsGuest() async {
    await SupabaseConfig.setGuestMode();
    await _finishSelection();
  }

  Future<void> _goLogin() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginRegisterPage()),
    );
    if (ok == true && mounted) {
      await SupabaseConfig.clearGuestMode();
      await _load();
    }
  }

  String get _backdropUrl {
    if (_hoveredBackdrop != null && _hoveredBackdrop!.isNotEmpty) {
      return _hoveredBackdrop!;
    }
    // Si no hay hover, usar el del primer perfil con backdrop, o el fallback
    for (final p in _profiles) {
      final bd = p['backdrop_url']?.toString();
      if (bd != null && bd.isNotEmpty) return bd;
    }
    return _fallbackBackdrop;
  }

  void _onProfileHover(Map<String, dynamic>? profile) {
    final bd = profile?['backdrop_url']?.toString();
    final next = (bd != null && bd.isNotEmpty) ? bd : _fallbackBackdrop;
    if (_hoveredBackdrop != next) {
      setState(() => _hoveredBackdrop = next);
    }
  }

  // ------------------------------------------------------------
  // Construcción de la cuadrícula 2 columnas (último impar centrado)
  // ------------------------------------------------------------
  Widget _buildProfilesGrid() {
    final items = <Widget>[];

    // 1) Perfiles existentes (solo si hay sesión y perfiles)
    for (final p in _profiles) {
      items.add(_ProfileCard(
        name: p['name']?.toString() ?? 'Usuario',
        avatarUrl: p['avatar_url']?.toString(),
        isEditMode: _editMode,
        onTap: () => _onProfileTap(p),
        onHover: (hovering) => _onProfileHover(hovering ? p : null),
      ));
    }

    // 2) Botón "Añadir" (solo si logueado y < 5)
    if (SupabaseAuth.isLoggedIn && _profiles.length < 5) {
      items.add(_ProfileCard(
        name: 'Añadir',
        isAdd: true,
        onTap: () => _openEditor(),
        onHover: (hovering) {
          if (hovering) _onProfileHover(null);
        },
      ));
    }

    // 3) Invitado SOLO si NO hay perfiles (para no duplicar el botón de abajo)
    if (_profiles.isEmpty) {
      items.add(_ProfileCard(
        name: 'Invitado',
        isGuest: true,
        onTap: _enterAsGuest,
        onHover: (hovering) {
          if (hovering) _onProfileHover(null);
        },
      ));
    }

    const crossAxisCount = 2;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += crossAxisCount) {
      final slice = items.sublist(
        i,
        (i + crossAxisCount).clamp(0, items.length),
      );

      if (slice.length == 1 && items.length > 1) {
        // Última fila impar → centrada
        rows.add(Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [slice.first],
        ));
      } else {
        rows.add(Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: slice
              .map((w) => Expanded(child: Center(child: w)))
              .toList(),
        ));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop de fondo
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: Image.network(
              _backdropUrl,
              key: ValueKey(_backdropUrl),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => Container(color: Colors.black),
            ),
          ),
          // Overlay oscuro
          Container(color: Colors.black.withOpacity(0.65)),

          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      const SizedBox(height: 40),
                      const Text(
                        '¿Quién está viendo?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_editMode)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Toca un perfil para editarlo',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: _buildProfilesGrid(),
                            ),
                          ),
                        ),
                      ),
                      // Bloque inferior: modo edición + invitado + sesión
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Fila: Editar perfiles + Invitado (mismo bloque)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (SupabaseAuth.isLoggedIn)
                                  TextButton.icon(
                                    onPressed: _toggleEditMode,
                                    icon: Icon(
                                      _editMode
                                          ? Icons.check
                                          : Icons.edit_outlined,
                                      color: _editMode
                                          ? Colors.redAccent
                                          : Colors.white70,
                                    ),
                                    label: Text(
                                      _editMode ? 'Listo' : 'Editar perfiles',
                                      style: TextStyle(
                                        color: _editMode
                                            ? Colors.redAccent
                                            : Colors.white70,
                                      ),
                                    ),
                                  ),
                                if (SupabaseAuth.isLoggedIn)
                                  const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: _enterAsGuest,
                                  icon: const Icon(
                                    Icons.person_outline,
                                    color: Colors.white70,
                                  ),
                                  label: const Text(
                                    'Invitado',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                            // Acciones de sesión
                            if (!SupabaseAuth.isLoggedIn)
                              TextButton.icon(
                                onPressed: _goLogin,
                                icon: const Icon(
                                  Icons.login,
                                  color: Colors.white70,
                                ),
                                label: const Text(
                                  'Iniciar sesión / Crear cuenta',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            if (SupabaseAuth.isLoggedIn)
                              TextButton.icon(
                                onPressed: () async {
                                  await SupabaseAuth.signOut();
                                  _load();
                                },
                                icon: const Icon(
                                  Icons.logout,
                                  color: Colors.white54,
                                ),
                                label: const Text(
                                  'Cerrar sesión',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
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

// ============================================================
// Tarjeta de perfil (avatar circular + overlay de edición)
// ============================================================
class _ProfileCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool isAdd;
  final bool isGuest;
  final bool isEditMode;
  final VoidCallback onTap;
  final ValueChanged<bool>? onHover;

  const _ProfileCard({
    required this.name,
    this.avatarUrl,
    this.isAdd = false,
    this.isGuest = false,
    this.isEditMode = false,
    required this.onTap,
    this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final editable = isEditMode && !isAdd && !isGuest;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: MouseRegion(
        onEnter: (_) => onHover?.call(true),
        onExit: (_) => onHover?.call(false),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(80),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                // Avatar circular
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                    border: Border.all(
                      color: editable
                          ? Colors.redAccent
                          : Colors.white.withOpacity(0.25),
                      width: editable ? 2.4 : 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _avatarContent(),
                ),
                // Overlay de lápiz en modo edición
                if (editable)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.45),
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _avatarContent() {
    if (isAdd) {
      return const Icon(Icons.add, size: 46, color: Colors.white70);
    }
    if (isGuest) {
      return const Icon(
        Icons.person_outline,
        size: 46,
        color: Colors.white70,
      );
    }
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Image.network(
        avatarUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.person,
          size: 46,
          color: Colors.white70,
        ),
      );
    }
    return const Icon(Icons.person, size: 46, color: Colors.white70);
  }
}