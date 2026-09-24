import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tv_config_shared.dart';
import '../../../../supabase/supabase_client.dart';
import '../../../../supabase/supabase_config.dart';
import '../../../../supabase/supabase_admin.dart';
import '../../../profile/presentation/profile_selection_page.dart';

/// Pestaña Supabase para TV (foco D-pad + confirmación a pantalla completa).
class TvSupabaseTab extends StatefulWidget {
  final VoidCallback onRequestTabFocus;

  const TvSupabaseTab({
    super.key,
    required this.onRequestTabFocus,
  });

  @override
  State<TvSupabaseTab> createState() => TvSupabaseTabState();
}

class TvSupabaseTabState extends State<TvSupabaseTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  bool _hasCreds = false;
  bool _isActive = false;
  String? _userName;
  String? _savedUrl;
  String? _code;
  String? _status;
  bool _polling = false;
  bool _askEveryLaunch = true;
  Timer? _pollTimer;

  late final FocusNode _btnGenerate;
  late final FocusNode _btnChange;
  late final FocusNode _btnClear;
  late final FocusNode _btnProfiles;
  late final FocusNode _btnLoginPref;

  FocusNode get firstFocusNode {
    if (_hasCreds || _isActive) return _btnLoginPref;
    return _btnGenerate;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _btnGenerate = FocusNode(debugLabel: 'cfg_sb_generate');
    _btnChange = FocusNode(debugLabel: 'cfg_sb_change');
    _btnClear = FocusNode(debugLabel: 'cfg_sb_clear');
    _btnProfiles = FocusNode(debugLabel: 'cfg_sb_profiles');
    _btnLoginPref = FocusNode(debugLabel: 'cfg_sb_login_pref');
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _btnGenerate.dispose();
    _btnChange.dispose();
    _btnClear.dispose();
    _btnProfiles.dispose();
    _btnLoginPref.dispose();
    super.dispose();
  }

  void requestFirstFocus() {
    firstFocusNode.requestFocus();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final has = await SupabaseConfig.hasCredentials();
    final active = await SupabaseConfig.isSupabaseActive();
    final name = await SupabaseConfig.getCurrentUserName();
    final url = await SupabaseConfig.getUrl();
    final askEvery = await SupabaseConfig.getAskProfileEveryLaunch();
    if (!mounted) return;
    setState(() {
      _hasCreds = has;
      _isActive = active;
      _userName = name;
      _savedUrl = url;
      _askEveryLaunch = askEvery;
      _loading = false;
    });
  }

  // ── Confirmación a pantalla completa (no la tapan las tabs) ─────────────
  Future<bool> _confirmFullScreen({
    required String title,
    required String message,
    String acceptLabel = 'Aceptar',
    String cancelLabel = 'Cancelar',
  }) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      barrierLabel: 'Confirmación',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim, secondary) {
        return _TvConfirmFullScreen(
          title: title,
          message: message,
          acceptLabel: acceptLabel,
          cancelLabel: cancelLabel,
          onAccept: () => Navigator.of(ctx).pop(true),
          onCancel: () => Navigator.of(ctx).pop(false),
        );
      },
    );
    return result == true;
  }

  /// Generar código: si ya hay sesión/creds → confirmar, borrar TODO y empezar de cero.
  Future<void> _generateCode() async {
    if (!SupabaseAdmin.isAdminConfigured) {
      setState(() {
        _status =
            'El admin de la app no configuró supabase_admin_constants.dart';
      });
      return;
    }

    // Si ya hay algo vinculado, pedir confirmación y limpiar todo
    if (_hasCreds || _isActive || _code != null) {
      final ok = await _confirmFullScreen(
        title: 'Generar otro código',
        message:
            'Se eliminarán las credenciales de Supabase, el perfil activo '
            'y cualquier código en espera. Empezarás de cero.\n\n'
            'El caché local de la TV (progreso, descargas) no se toca.',
        acceptLabel: 'Borrar y generar',
        cancelLabel: 'Cancelar',
      );
      if (!ok || !mounted) return;

      _pollTimer?.cancel();
      await SupabaseConfig.clearCredentials();
      await AppSupabase.reinit();
      if (!mounted) return;
      setState(() {
        _hasCreds = false;
        _isActive = false;
        _userName = null;
        _savedUrl = null;
        _code = null;
        _polling = false;
        _status = null;
      });
    }

    _pollTimer?.cancel();
    setState(() {
      _status = 'Generando código…';
      _polling = false;
      _code = null;
    });

    final code = await SupabaseAdmin.createLinkCode();
    if (!mounted) return;

    if (code == null) {
      setState(() {
        _status = 'No se pudo generar el código. Revisa el proyecto admin.';
      });
      return;
    }

    setState(() {
      _code = code;
      _status =
          'En el móvil: Ajustes → Supabase → escribe este código → Vincular.';
      _polling = true;
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_code == null || !mounted) return;
      final data = await SupabaseAdmin.checkLinkCode(_code!);
      if (data == null) return;

      final codeUsed = _code!;
      _pollTimer?.cancel();

      await SupabaseConfig.setCredentials(
        url: data['url']!,
        anonKey: data['anonKey']!,
      );
      await AppSupabase.reinit();
      await SupabaseAdmin.deleteCode(codeUsed);

      if (!mounted) return;
      setState(() {
        _polling = false;
        _code = null;
        _hasCreds = true;
        _savedUrl = data['url'];
        _status = 'Vinculado. Elige un perfil para sincronizar.';
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileSelectionPage(
            allowDismiss: false,
            onProfileSelected: () {
              Navigator.of(context).pop();
              _load();
            },
          ),
        ),
      );
      await _load();
    });
  }

  Future<void> _changeProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileSelectionPage(
          allowDismiss: true,
          onProfileSelected: () {
            Navigator.of(context).pop();
            _load();
          },
        ),
      ),
    );
    await _load();
  }

  Future<void> _openProfiles() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileSelectionPage(
          allowDismiss: true,
          onProfileSelected: () {
            Navigator.of(context).pop();
            _load();
          },
        ),
      ),
    );
    await _load();
  }

  Future<void> _clear() async {
    final ok = await _confirmFullScreen(
      title: 'Desactivar Supabase',
      message:
          'Se borrarán las credenciales y el perfil activo. '
          'La TV volverá a usar solo el caché local.',
      acceptLabel: 'Desactivar',
      cancelLabel: 'Cancelar',
    );
    if (!ok || !mounted) return;

    _pollTimer?.cancel();
    await SupabaseConfig.clearCredentials();
    await AppSupabase.reinit();
    if (!mounted) return;
    setState(() {
      _hasCreds = false;
      _isActive = false;
      _userName = null;
      _savedUrl = null;
      _code = null;
      _polling = false;
      _status = 'Supabase desactivado. La TV usa caché local.';
    });
  }

  Future<void> _showLoginPrefModal() async {
    final selected = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      barrierLabel: 'Preferencia de perfil',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim, secondary) {
        return _TvLoginPrefFullScreen(
          askEveryLaunch: _askEveryLaunch,
          onSelect: (v) => Navigator.of(ctx).pop(v),
          onCancel: () => Navigator.of(ctx).pop(),
        );
      },
    );
    if (selected == null || !mounted) return;
    await SupabaseConfig.setAskProfileEveryLaunch(selected);
    setState(() => _askEveryLaunch = selected);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(color: kConfigAccent),
        ),
      );
    }

    final stateLabel = _isActive
        ? 'Activo · ${_userName ?? "—"}'
        : _hasCreds
            ? 'Credenciales guardadas · Elige un perfil'
            : 'No configurado · Caché local';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('SUPABASE', first: true),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Text(
            stateLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        ),

        // Preferencia de login
        if (_hasCreds || _isActive) ...[
          FocusActionCard(
            focusNode: _btnLoginPref,
            icon: Icons.manage_accounts_rounded,
            label: 'Inicio de sesión de perfil',
            subtitle: _askEveryLaunch
                ? 'Pedir perfil cada vez'
                : 'Recordar último perfil',
            onTap: _showLoginPrefModal,
            onArrowUp: widget.onRequestTabFocus,
            onArrowDown: () {
              if (_isActive) {
                _btnChange.requestFocus();
              } else if (_hasCreds) {
                _btnProfiles.requestFocus();
              } else {
                _btnGenerate.requestFocus();
              }
            },
          ),
          const SizedBox(height: 10),
        ],

        // Resumen credenciales (monocromo)
        if (_hasCreds) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kConfigCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credenciales',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'URL  ${_savedUrl ?? "—"}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Perfil  ${_userName ?? (_isActive ? "—" : "sin elegir")}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Código grande mientras espera
        if (_code != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: kConfigCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                Text(
                  'Código de vinculación',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _code!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 12,
                  ),
                ),
                if (_polling) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Esperando al móvil…',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],

        // Acciones
        if (_isActive) ...[
          FocusActionCard(
            focusNode: _btnChange,
            icon: Icons.switch_account_rounded,
            label: 'Cambiar perfil',
            subtitle:
                _userName != null ? 'Actual: $_userName' : 'Elegir otro perfil',
            onTap: _changeProfile,
            onArrowUp: () => _btnLoginPref.requestFocus(),
            onArrowDown: () => _btnGenerate.requestFocus(),
          ),
          const SizedBox(height: 10),
          FocusActionCard(
            focusNode: _btnGenerate,
            icon: Icons.qr_code_rounded,
            label: 'Generar otro código',
            subtitle: 'Borra la sesión actual y vincula de nuevo',
            onTap: _generateCode,
            onArrowUp: () => _btnChange.requestFocus(),
            onArrowDown: () => _btnClear.requestFocus(),
          ),
          const SizedBox(height: 10),
          FocusActionCard(
            focusNode: _btnClear,
            icon: Icons.cloud_off_rounded,
            label: 'Desactivar Supabase',
            subtitle: 'Borra credenciales; el caché local no se toca',
            onTap: _clear,
            onArrowUp: () => _btnGenerate.requestFocus(),
            onArrowDown: () {},
          ),
        ] else if (_hasCreds) ...[
          FocusActionCard(
            focusNode: _btnProfiles,
            icon: Icons.person_rounded,
            label: 'Elegir perfil',
            subtitle: 'Activa la sincronización',
            onTap: _openProfiles,
            onArrowUp: () => _btnLoginPref.requestFocus(),
            onArrowDown: () => _btnGenerate.requestFocus(),
          ),
          const SizedBox(height: 10),
          FocusActionCard(
            focusNode: _btnGenerate,
            icon: Icons.qr_code_rounded,
            label: _code == null
                ? 'Generar código de vinculación'
                : 'Generar otro código',
            subtitle: 'Borra credenciales y empieza de cero',
            onTap: _generateCode,
            onArrowUp: () => _btnProfiles.requestFocus(),
            onArrowDown: () => _btnClear.requestFocus(),
          ),
          const SizedBox(height: 10),
          FocusActionCard(
            focusNode: _btnClear,
            icon: Icons.cloud_off_rounded,
            label: 'Desactivar Supabase',
            subtitle: 'Borra credenciales guardadas',
            onTap: _clear,
            onArrowUp: () => _btnGenerate.requestFocus(),
            onArrowDown: () {},
          ),
        ] else ...[
          FocusActionCard(
            focusNode: _btnGenerate,
            icon: Icons.qr_code_rounded,
            label: _code == null
                ? 'Generar código de vinculación'
                : 'Generar otro código',
            subtitle: 'Código en el servidor admin para vincular desde el móvil',
            onTap: _generateCode,
            onArrowUp: widget.onRequestTabFocus,
            onArrowDown: () {},
          ),
        ],

        if (_status != null) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _status!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Sin Supabase la TV usa solo el caché del dispositivo. '
            'Al vincular, el móvil envía URL y ANON KEY; la TV las guarda '
            'y borra el código del servidor admin.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.28),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Confirmación a pantalla completa + foco Aceptar / Cancelar
// ═══════════════════════════════════════════════════════════════════════════

class _TvConfirmFullScreen extends StatefulWidget {
  final String title;
  final String message;
  final String acceptLabel;
  final String cancelLabel;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const _TvConfirmFullScreen({
    required this.title,
    required this.message,
    required this.acceptLabel,
    required this.cancelLabel,
    required this.onAccept,
    required this.onCancel,
  });

  @override
  State<_TvConfirmFullScreen> createState() => _TvConfirmFullScreenState();
}

class _TvConfirmFullScreenState extends State<_TvConfirmFullScreen> {
  late final FocusNode _accept;
  late final FocusNode _cancel;

  @override
  void initState() {
    super.initState();
    _accept = FocusNode(debugLabel: 'confirm_accept');
    _cancel = FocusNode(debugLabel: 'confirm_cancel');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cancel.requestFocus(); // por defecto Cancelar (seguro)
    });
  }

  @override
  void dispose() {
    _accept.dispose();
    _cancel.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e, {required bool isAccept}) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;

    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      if (isAccept) {
        _cancel.requestFocus();
      } else {
        _accept.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space) {
      if (isAccept) {
        widget.onAccept();
      } else {
        widget.onCancel();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Focus(
                          focusNode: _cancel,
                          onKeyEvent: (n, e) =>
                              _onKey(n, e, isAccept: false),
                          child: Builder(
                            builder: (ctx) {
                              final focused = Focus.of(ctx).hasFocus;
                              return _ConfirmBtn(
                                label: widget.cancelLabel,
                                focused: focused,
                                primary: false,
                                onTap: widget.onCancel,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Focus(
                          focusNode: _accept,
                          onKeyEvent: (n, e) =>
                              _onKey(n, e, isAccept: true),
                          child: Builder(
                            builder: (ctx) {
                              final focused = Focus.of(ctx).hasFocus;
                              return _ConfirmBtn(
                                label: widget.acceptLabel,
                                focused: focused,
                                primary: true,
                                onTap: widget.onAccept,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '← →  cambiar   ·   OK  confirmar   ·   Atrás  cancelar',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.28),
                      fontSize: 11,
                    ),
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

class _ConfirmBtn extends StatelessWidget {
  final String label;
  final bool focused;
  final bool primary;
  final VoidCallback onTap;

  const _ConfirmBtn({
    required this.label,
    required this.focused,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = focused
        ? Colors.white
        : Colors.white.withValues(alpha: primary ? 0.12 : 0.06);
    final fg = focused ? Colors.black : Colors.white.withValues(alpha: 0.85);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.12),
              width: focused ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Preferencia de perfil a pantalla completa
// ═══════════════════════════════════════════════════════════════════════════

class _TvLoginPrefFullScreen extends StatefulWidget {
  final bool askEveryLaunch;
  final ValueChanged<bool> onSelect;
  final VoidCallback onCancel;

  const _TvLoginPrefFullScreen({
    required this.askEveryLaunch,
    required this.onSelect,
    required this.onCancel,
  });

  @override
  State<_TvLoginPrefFullScreen> createState() => _TvLoginPrefFullScreenState();
}

class _TvLoginPrefFullScreenState extends State<_TvLoginPrefFullScreen> {
  late final FocusNode _every;
  late final FocusNode _remember;

  @override
  void initState() {
    super.initState();
    _every = FocusNode(debugLabel: 'pref_every');
    _remember = FocusNode(debugLabel: 'pref_remember');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.askEveryLaunch) {
        _every.requestFocus();
      } else {
        _remember.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _every.dispose();
    _remember.dispose();
    super.dispose();
  }

  KeyEventResult _key(
    FocusNode node,
    KeyEvent e, {
    required bool isEvery,
  }) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      if (isEvery) {
        _remember.requestFocus();
      } else {
        _every.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space) {
      widget.onSelect(isEvery);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Inicio de sesión de perfil',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Focus(
                    focusNode: _every,
                    onKeyEvent: (n, e) => _key(n, e, isEvery: true),
                    child: Builder(
                      builder: (ctx) {
                        final f = Focus.of(ctx).hasFocus;
                        return _PrefTile(
                          focused: f,
                          selected: widget.askEveryLaunch,
                          icon: Icons.person_search_rounded,
                          title: 'Pedir perfil cada vez',
                          subtitle: 'Al abrir siempre eliges quién mira',
                          onTap: () => widget.onSelect(true),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Focus(
                    focusNode: _remember,
                    onKeyEvent: (n, e) => _key(n, e, isEvery: false),
                    child: Builder(
                      builder: (ctx) {
                        final f = Focus.of(ctx).hasFocus;
                        return _PrefTile(
                          focused: f,
                          selected: !widget.askEveryLaunch,
                          icon: Icons.history_rounded,
                          title: 'Recordar último perfil',
                          subtitle: 'Entra directo con el último perfil',
                          onTap: () => widget.onSelect(false),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '↑ ↓  cambiar   ·   OK  elegir   ·   Atrás  cerrar',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.28),
                      fontSize: 11,
                    ),
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

class _PrefTile extends StatelessWidget {
  final bool focused;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PrefTile({
    required this.focused,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: focused
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.08),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: Colors.white.withValues(alpha: focused ? 0.95 : 0.55),
                size: 26,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: focused ? 1 : 0.85,
                        ),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}