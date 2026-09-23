import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tv_config_shared.dart';
import '../../../../supabase/supabase_client.dart';
import '../../../../supabase/supabase_config.dart';
import '../../../../supabase/supabase_admin.dart';
import '../../../profile/presentation/profile_selection_page.dart';

/// Pestaña Supabase para TV (misma estructura de foco que Caché/Player).
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

  Future<void> _generateCode() async {
    if (!SupabaseAdmin.isAdminConfigured) {
      setState(() {
        _status =
            'El admin de la app no configuró supabase_admin_constants.dart';
      });
      return;
    }

    _pollTimer?.cancel();
    setState(() {
      _status = 'Generando código...';
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

      // Guardar credenciales del usuario
      await SupabaseConfig.setCredentials(
        url: data['url']!,
        anonKey: data['anonKey']!,
      );
      await AppSupabase.reinit();

      // Borrar el código de la tabla admin
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
      _status = 'Supabase desactivado. La TV usa cache local.';
    });
  }


  Future<void> _showLoginPrefModal() async {
    final selected = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text(
            'Inicio de sesión de perfil',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.person_search,
                  color: _askEveryLaunch ? kConfigAccent : Colors.white54,
                ),
                title: const Text(
                  'Pedir perfil cada vez',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Al abrir siempre eliges quién está viendo',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: _askEveryLaunch
                    ? Icon(Icons.check_circle, color: kConfigAccent)
                    : null,
                onTap: () => Navigator.pop(ctx, true),
              ),
              ListTile(
                leading: Icon(
                  Icons.history,
                  color: !_askEveryLaunch ? kConfigAccent : Colors.white54,
                ),
                title: const Text(
                  'Recordar último perfil',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Entra directo con el último perfil',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: !_askEveryLaunch
                    ? Icon(Icons.check_circle, color: kConfigAccent)
                    : null,
                onTap: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
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
        child: Center(child: CircularProgressIndicator(color: kConfigAccent)),
      );
    }

    // SIN Expanded / Spacer → evita "unbounded height" en el shell de tabs
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('SUPABASE', first: true),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            _isActive
                ? 'Activo · Perfil: ${_userName ?? "—"}'
                : _hasCreds
                    ? 'Credenciales guardadas · Elige un perfil'
                    : 'No configurado · Cache local del dispositivo',
            style: TextStyle(
              color: _isActive
                  ? Colors.greenAccent
                  : _hasCreds
                      ? Colors.orangeAccent
                      : Colors.white54,
              fontSize: 13,
            ),
          ),
        ),

        if (_hasCreds || _isActive) ...[
          FocusActionCard(
            focusNode: _btnLoginPref,
            icon: Icons.manage_accounts_rounded,
            label: 'Inicio de sesión de perfil',
            subtitle: _askEveryLaunch
                ? 'Actual: Pedir perfil cada vez'
                : 'Actual: Recordar último perfil',
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

        // ── Credenciales ya guardadas ──────────────────────────────────────
        if (_hasCreds) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kConfigCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Credenciales guardadas',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'URL: ${_savedUrl ?? "—"}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Perfil: ${_userName ?? ( _isActive ? "—" : "sin elegir")}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],

        // ── Código en pantalla mientras se espera ──────────────────────────
        if (_code != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: kConfigCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF7B5CFF).withOpacity(0.5)),
            ),
            child: Column(
              children: [
                const Text(
                  'Código de vinculación',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Text(
                  _code!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 10,
                  ),
                ),
                if (_polling) ...[
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF7B5CFF),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Esperando al móvil...',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],

        // ── Botones ────────────────────────────────────────────────────────
        if (_isActive) ...[
          FocusActionCard(
            focusNode: _btnChange,
            icon: Icons.switch_account_rounded,
            label: 'Cambiar perfil',
            subtitle: _userName != null
                ? 'Actual: $_userName'
                : 'Elegir otro perfil',
            onTap: _changeProfile,
            onArrowUp: () => _btnLoginPref.requestFocus(),
            onArrowDown: () => _btnGenerate.requestFocus(),
          ),
          const SizedBox(height: 10),
          FocusActionCard(
            focusNode: _btnGenerate,
            icon: Icons.qr_code_rounded,
            label: 'Generar otro código',
            subtitle: 'Vincular otro móvil o actualizar credenciales',
            onTap: _generateCode,
            onArrowUp: () => _btnChange.requestFocus(),
            onArrowDown: () => _btnClear.requestFocus(),
          ),
          const SizedBox(height: 10),
          FocusActionCard(
            focusNode: _btnClear,
            icon: Icons.cloud_off_rounded,
            label: 'Desactivar Supabase',
            subtitle: 'Borra credenciales; el cache local no se toca',
            onTap: _clear,
            onArrowUp: () => _btnGenerate.requestFocus(),
            onArrowDown: () {},
          ),
        ] else if (_hasCreds) ...[
          FocusActionCard(
            focusNode: _btnProfiles,
            icon: Icons.person_rounded,
            label: 'Elegir perfil',
            subtitle: 'Activa la sincronización eligiendo un perfil',
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
            subtitle: 'El móvil enviará URL y ANON KEY con este código',
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
            subtitle:
                'Crea un código en el servidor admin para vincular desde el móvil',
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
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],

        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Sin Supabase la TV usa solo el cache del dispositivo. '
            'Al vincular, el móvil envía tu URL y ANON KEY; la TV las guarda '
            'y borra el código del servidor admin.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
