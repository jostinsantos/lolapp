// ============================================================
// tv_edit_profile_page.dart
// Crear / editar perfil. Fondo negro, botones glass.
// Reutilizable en TV (horizontal) y móvil (vertical) sin
// afectar a la experiencia TV.
// ============================================================
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../supabase/supabase_profiles.dart';
import '../../../supabase/supabase_auth.dart';
import 'tv_picker_page.dart';

const _kAccent = Color(0xFFE50914);

class TvEditProfilePage extends StatefulWidget {
  final Map<String, dynamic>? profile;

  const TvEditProfilePage({super.key, this.profile});

  @override
  State<TvEditProfilePage> createState() => _TvEditProfilePageState();
}

class _TvEditProfilePageState extends State<TvEditProfilePage> {
  late String _name;
  late String _avatarUrl;
  late String _backdropUrl;
  late String _pin;

  bool _loading = false;

  bool get isEdit => widget.profile != null;

  final FocusNode _nameFocus = FocusNode(debugLabel: 'edit_name');
  final FocusNode _avatarFocus = FocusNode(debugLabel: 'edit_avatar');
  final FocusNode _backdropFocus = FocusNode(debugLabel: 'edit_backdrop');
  final FocusNode _pinFocus = FocusNode(debugLabel: 'edit_pin');
  final FocusNode _deleteFocus = FocusNode(debugLabel: 'edit_delete');
  final FocusNode _saveFocus = FocusNode(debugLabel: 'edit_save');

  final ScrollController _scroll = ScrollController();
  final GlobalKey _nameKey = GlobalKey();
  final GlobalKey _avatarKey = GlobalKey();
  final GlobalKey _backdropKey = GlobalKey();
  final GlobalKey _pinKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _name = widget.profile?['name']?.toString() ?? '';
    _avatarUrl = widget.profile?['avatar_url']?.toString() ?? '';
    _backdropUrl = widget.profile?['backdrop_url']?.toString() ?? '';
    _pin = widget.profile?['pin']?.toString() ?? '';

    _nameFocus.addListener(_onNameFocus);
    _avatarFocus.addListener(_onAvatarFocus);
    _backdropFocus.addListener(_onBackdropFocus);
    _pinFocus.addListener(_onPinFocus);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onNameFocus);
    _avatarFocus.removeListener(_onAvatarFocus);
    _backdropFocus.removeListener(_onBackdropFocus);
    _pinFocus.removeListener(_onPinFocus);

    _nameFocus.dispose();
    _avatarFocus.dispose();
    _backdropFocus.dispose();
    _pinFocus.dispose();
    _deleteFocus.dispose();
    _saveFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onNameFocus() {
    if (_nameFocus.hasFocus) _ensureVisible(_nameKey);
  }

  void _onAvatarFocus() {
    if (_avatarFocus.hasFocus) _ensureVisible(_avatarKey);
  }

  void _onBackdropFocus() {
    if (_backdropFocus.hasFocus) _ensureVisible(_backdropKey);
  }

  void _onPinFocus() {
    if (_pinFocus.hasFocus) _ensureVisible(_pinKey);
  }

  void _ensureVisible(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _focusSave() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
    _saveFocus.requestFocus();
  }

  Future<void> _editName() async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(
        title: 'Nombre del perfil',
        hint: 'Escribe un nombre',
        initialText: _name,
        maxLength: 30,
      ),
    );
    if (res != null) setState(() => _name = res);
  }

  Future<void> _editPin() async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _PinSetupDialog(initialPin: _pin),
    );
    if (res != null) setState(() => _pin = res);
  }

  Future<void> _pickAvatar() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TvPickerPage(
          mode: TvPickerMode.avatar,
          initial: _avatarUrl,
        ),
      ),
    );
    if (res != null) setState(() => _avatarUrl = res);
  }

  Future<void> _pickBackdrop() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TvPickerPage(
          mode: TvPickerMode.backdrop,
          initial: _backdropUrl,
        ),
      ),
    );
    if (res != null) setState(() => _backdropUrl = res);
  }

  Future<void> _save() async {
    final name = _name.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre es obligatorio')),
      );
      return;
    }

    setState(() => _loading = true);

    bool ok;
    Map<String, dynamic>? createdProfile;
    if (isEdit) {
      ok = await SupabaseProfiles.update(
        id: widget.profile!['id'].toString(),
        name: name,
        avatarUrl: _avatarUrl.trim().isEmpty ? null : _avatarUrl.trim(),
        backdropUrl: _backdropUrl.trim().isEmpty ? null : _backdropUrl.trim(),
        pin: _pin.trim(),
      );
    } else {
      createdProfile = await SupabaseProfiles.create(
        name: name,
        avatarUrl: _avatarUrl.trim().isEmpty ? null : _avatarUrl.trim(),
        backdropUrl: _backdropUrl.trim().isEmpty ? null : _backdropUrl.trim(),
        pin: _pin.trim().isEmpty ? null : _pin.trim(),
      );
      ok = createdProfile != null;
      if (createdProfile != null) {
        await SupabaseProfiles.select(createdProfile);
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SupabaseAuth.isLoggedIn
                ? 'Error al guardar. ¿Máximo 5 perfiles o sin sesión?'
                : 'Debes iniciar sesión para crear un perfil',
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    if (!isEdit) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cancelF = FocusNode();
        final okF = FocusNode();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => cancelF.requestFocus());
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Eliminar perfil',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
          content: Text(
            '¿Seguro que quieres eliminar "$_name"?\nSe borrarán su historial, guardados y likes.',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              focusNode: cancelF,
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              focusNode: okF,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    final ok =
        await SupabaseProfiles.delete(widget.profile!['id'].toString());
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al eliminar')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vertical =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final hPad = vertical ? 20.0 : 56.0;
    final vPad = vertical ? 14.0 : 22.0;
    final avatarSize = vertical ? 90.0 : 120.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.5),
                  radius: 1.2,
                  colors: [
                    Color(0xFF1A1A22),
                    Color(0xFF0A0A0F),
                    Color(0xFF000000),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Perfil',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: vertical ? 20 : 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      if (isEdit)
                        _HeaderAction(
                          focusNode: _deleteFocus,
                          label: 'Eliminar',
                          icon: Icons.delete_outline,
                          danger: true,
                          iconOnly: vertical,
                          onTap: _loading ? null : _delete,
                          onArrowDown: () {
                            _nameFocus.requestFocus();
                          },
                        ),
                      const SizedBox(width: 12),
                      _HeaderAction(
                        focusNode: _saveFocus,
                        label: _loading ? 'Guardando...' : 'Guardar',
                        icon: Icons.check,
                        primary: true,
                        iconOnly: vertical,
                        onTap: _loading ? null : _save,
                        onArrowDown: () {
                          _nameFocus.requestFocus();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: vertical ? 520 : 560,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: _AvatarPreview(
                                  url: _avatarUrl,
                                  size: avatarSize,
                                ),
                              ),
                              const SizedBox(height: 28),
                              KeyedSubtree(
                                key: _nameKey,
                                child: _FieldRow(
                                  label: 'Nombre',
                                  value: _name.isEmpty
                                      ? 'Sin nombre'
                                      : _name,
                                  icon: Icons.person_outline,
                                  focusNode: _nameFocus,
                                  onTap: _editName,
                                  onArrowUp: _focusSave,
                                ),
                              ),
                              const SizedBox(height: 12),
                              KeyedSubtree(
                                key: _avatarKey,
                                child: _FieldRow(
                                  label: 'Avatar',
                                  value: _avatarUrl.isEmpty
                                      ? 'Sin avatar'
                                      : 'Seleccionado',
                                  icon: Icons.image_outlined,
                                  focusNode: _avatarFocus,
                                  onTap: _pickAvatar,
                                  thumbnail: _avatarUrl.isNotEmpty
                                      ? _avatarUrl
                                      : null,
                                  circularThumb: true,
                                  onArrowUp: () =>
                                      _nameFocus.requestFocus(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              KeyedSubtree(
                                key: _backdropKey,
                                child: _FieldRow(
                                  label: 'Fondo',
                                  value: _backdropUrl.isEmpty
                                      ? 'Sin fondo'
                                      : 'Seleccionado',
                                  icon: Icons.wallpaper_outlined,
                                  focusNode: _backdropFocus,
                                  onTap: _pickBackdrop,
                                  thumbnail: _backdropUrl.isNotEmpty
                                      ? _backdropUrl
                                      : null,
                                  onArrowUp: () =>
                                      _avatarFocus.requestFocus(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              KeyedSubtree(
                                key: _pinKey,
                                child: _FieldRow(
                                  label: 'PIN de seguridad',
                                  value: _pin.isEmpty
                                      ? 'Sin PIN'
                                      : '•' * _pin.length,
                                  icon: Icons.lock_outline,
                                  focusNode: _pinFocus,
                                  onTap: _editPin,
                                  onArrowUp: () =>
                                      _backdropFocus.requestFocus(),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// AvatarPreview
// ============================================================
class _AvatarPreview extends StatelessWidget {
  final String url;
  final double size;

  const _AvatarPreview({required this.url, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 20,
      height: size + 20,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.06),
                blurRadius: 30,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 20,
                spreadRadius: -4,
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.white.withOpacity(0.04),
                alignment: Alignment.center,
                child: url.isEmpty
                    ? Icon(
                        Icons.person,
                        size: size * 0.45,
                        color: Colors.white54,
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.person,
                          size: size * 0.45,
                          color: Colors.white54,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FieldRow
// ============================================================
class _FieldRow extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final String? thumbnail;
  final bool circularThumb;
  final VoidCallback? onArrowUp;

  const _FieldRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.focusNode,
    required this.onTap,
    this.thumbnail,
    this.circularThumb = false,
    this.onArrowUp,
  });

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
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
    return Focus(
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
        if (k == LogicalKeyboardKey.arrowUp && widget.onArrowUp != null) {
          widget.onArrowUp!.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : Colors.white.withOpacity(0.08),
              width: _focused ? 1.8 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.22),
                      blurRadius: 18,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: _focused
                    ? Colors.white.withOpacity(0.10)
                    : Colors.white.withOpacity(0.035),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    _Thumb(
                      thumbnail: widget.thumbnail,
                      icon: widget.icon,
                      circular: widget.circularThumb,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.42),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _focused
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.85),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _focused
                          ? Colors.white
                          : Colors.white.withOpacity(0.35),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? thumbnail;
  final IconData icon;
  final bool circular;

  const _Thumb({
    required this.thumbnail,
    required this.icon,
    required this.circular,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1,
        ),
        image: thumbnail != null
            ? DecorationImage(
                image: NetworkImage(thumbnail!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: thumbnail == null
          ? Icon(icon, color: Colors.white70, size: 20)
          : null,
    );
  }
}

// ============================================================
// HeaderAction
// ============================================================
class _HeaderAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final FocusNode focusNode;
  final VoidCallback? onArrowDown;
  final bool iconOnly;

  const _HeaderAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.focusNode,
    this.primary = false,
    this.danger = false,
    this.onArrowDown,
    this.iconOnly = false,
  });

  @override
  State<_HeaderAction> createState() => _HeaderActionState();
}

class _HeaderActionState extends State<_HeaderAction> {
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
    Color accentBase() {
      if (widget.primary) return _kAccent;
      if (widget.danger) return Colors.redAccent;
      return Colors.white;
    }

    final accent = accentBase();

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.space) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown &&
            widget.onArrowDown != null) {
          widget.onArrowDown!.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : accent.withOpacity(
                      widget.primary || widget.danger ? 0.55 : 0.14),
              width: _focused ? 1.8 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.35),
                      blurRadius: 16,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: _focused
                    ? Colors.white.withOpacity(0.10)
                    : (widget.primary
                        ? _kAccent.withOpacity(0.20)
                        : (widget.danger
                            ? Colors.redAccent.withOpacity(0.15)
                            : Colors.white.withOpacity(0.045))),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.iconOnly ? 10 : 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: 17,
                      color: _focused
                          ? Colors.white
                          : (widget.primary || widget.danger
                              ? accent
                              : Colors.white70),
                    ),
                    if (!widget.iconOnly) ...[
                      const SizedBox(width: 7),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: _focused
                              ? Colors.white
                              : (widget.primary || widget.danger
                                  ? Colors.white
                                  : Colors.white70),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MODAL DE TEXTO
// ============================================================
class _TextInputDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String initialText;
  final int maxLength;

  const _TextInputDialog({
    required this.title,
    this.hint,
    this.initialText = '',
    this.maxLength = 60,
  });

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late String _text;

  static const _rowsNormal = [
    ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
    ['h', 'i', 'j', 'k', 'l', 'm', 'n'],
    ['o', 'p', 'q', 'r', 's', 't', 'u'],
    ['v', 'w', 'x', 'y', 'z', 'ñ', '.'],
  ];

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
  }

  void _append(String c) {
    if (_text.length >= widget.maxLength) return;
    setState(() => _text += c);
  }

  void _backspace() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.substring(0, _text.length - 1));
  }

  void _clear() => setState(() => _text = '');

  void _submit() => Navigator.pop(context, _text);

  @override
  Widget build(BuildContext context) {
    final vertical =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: vertical ? 16 : 60,
        vertical: 40,
      ),
      child: Container(
        width: vertical ? double.infinity : 620,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withOpacity(0.14),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.7),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: Colors.black.withOpacity(0.72),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.14),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _text.isEmpty ? (widget.hint ?? '') : _text,
                      style: TextStyle(
                        color: _text.isEmpty
                            ? Colors.white38
                            : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final row in _rowsNormal)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final c in row)
                                _GlassKey(
                                  label: c,
                                  onTap: () => _append(c),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _GlassKey(
                            label: ' ',
                            icon: Icons.space_bar,
                            flex: 3,
                            onTap: () => _append(' '),
                          ),
                          _GlassKey(label: '@', onTap: () => _append('@')),
                          _GlassKey(
                            label: '⌫',
                            icon: Icons.backspace_outlined,
                            flex: 2,
                            onTap: _backspace,
                          ),
                          _GlassKey(
                            label: 'Limpiar',
                            text: true,
                            flex: 2,
                            onTap: _clear,
                          ),
                          _GlassKey(
                            label: 'OK',
                            primary: true,
                            flex: 2,
                            onTap: _submit,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassKey extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final bool primary;
  final bool text;

  const _GlassKey({
    required this.label,
    this.icon,
    required this.onTap,
    this.flex = 1,
    this.primary = false,
    this.text = false,
  });

  @override
  State<_GlassKey> createState() => _GlassKeyState();
}

class _GlassKeyState extends State<_GlassKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fg = _focused ? Colors.black : Colors.white;

    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _focused
                      ? Colors.white
                      : Colors.white.withOpacity(0.10),
                  width: _focused ? 1.6 : 1,
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.35),
                          blurRadius: 14,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    color: _focused
                        ? Colors.white
                        : (widget.primary
                            ? _kAccent.withOpacity(0.65)
                            : Colors.white.withOpacity(0.05)),
                    child: widget.icon != null
                        ? Icon(widget.icon, size: 17, color: fg)
                        : Text(
                            widget.label,
                            style: TextStyle(
                              color: fg,
                              fontSize: widget.text ? 12 : 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MODAL DE PIN
// ============================================================
class _PinSetupDialog extends StatefulWidget {
  final String initialPin;

  const _PinSetupDialog({this.initialPin = ''});

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  late String _pin;
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
    _pin = widget.initialPin;
    _keyFocus = List.generate(
      _keys.length,
      (i) => FocusNode(debugLabel: 'pin_setup_$i'),
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
  }

  void _moveFocus(int index, int dx, int dy) {
    final row = index ~/ 3;
    final col = index % 3;
    int nextRow = row;
    int nextCol = col;
    if (dy != 0) nextRow = (row + dy).clamp(0, 3);
    if (dx != 0) nextCol = (col + dx).clamp(0, 2);
    final next = nextRow * 3 + nextCol;
    if (next != index) _keyFocus[next].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final vertical =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: vertical ? 40 : 100,
        vertical: 60,
      ),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withOpacity(0.14),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.7),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: Colors.black.withOpacity(0.72),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PIN DE SEGURIDAD',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Se muestra para que lo verifiques',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 10.5),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.14),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _pin.isEmpty ? '—' : _pin,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var r = 0; r < 4; r++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var c = 0; c < 3; c++)
                                _GlassPinKey(
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _GlassAction(
                          label: 'Limpiar',
                          onTap: () => setState(() => _pin = ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _GlassAction(
                          label: 'Guardar',
                          primary: true,
                          onTap: () => Navigator.pop(context, _pin),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPinKey extends StatefulWidget {
  final String keyLabel;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final void Function(int dx, int dy) onArrow;

  const _GlassPinKey({
    required this.keyLabel,
    required this.focusNode,
    required this.onTap,
    required this.onArrow,
  });

  @override
  State<_GlassPinKey> createState() => _GlassPinKeyState();
}

class _GlassPinKeyState extends State<_GlassPinKey> {
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
          child: Container(
            width: 48,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused
                    ? Colors.white
                    : Colors.white.withOpacity(0.10),
                width: _focused ? 1.6 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.35),
                        blurRadius: 14,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  alignment: Alignment.center,
                  color: _focused
                      ? Colors.white
                      : Colors.white.withOpacity(0.05),
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
          ),
        ),
      ),
    );
  }
}

class _GlassAction extends StatefulWidget {
  final String label;
  final bool primary;
  final bool danger;
  final VoidCallback onTap;

  const _GlassAction({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  @override
  State<_GlassAction> createState() => _GlassActionState();
}

class _GlassActionState extends State<_GlassAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.primary
        ? _kAccent
        : (widget.danger ? Colors.redAccent : Colors.white);
    final fg = _focused ? Colors.black : Colors.white;

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : accent.withOpacity(
                      widget.primary || widget.danger ? 0.55 : 0.14),
              width: _focused ? 1.8 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.35),
                      blurRadius: 14,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                alignment: Alignment.center,
                color: _focused
                    ? Colors.white
                    : (widget.primary
                        ? _kAccent.withOpacity(0.22)
                        : (widget.danger
                            ? Colors.redAccent.withOpacity(0.18)
                            : Colors.white.withOpacity(0.05))),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}