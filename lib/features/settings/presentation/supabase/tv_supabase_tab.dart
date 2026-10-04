import 'package:flutter/material.dart';
import '../account/account_settings_page.dart';
import '../../../../supabase/supabase_auth.dart';
import '../../../../supabase/supabase_config.dart';
import '../../../profile/presentation/profile_selection_page.dart';

/// Pestaña de cuenta / perfiles en Ajustes TV.
class TvSupabaseTab extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final VoidCallback? onRequestTabFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const TvSupabaseTab({
    super.key,
    this.onRequestMenuFocus,
    this.onRequestTabFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<TvSupabaseTab> createState() => TvSupabaseTabState();
}

class TvSupabaseTabState extends State<TvSupabaseTab>
    with AutomaticKeepAliveClientMixin {
  String _status = 'Cargando...';
  final _focus = FocusNode(debugLabel: 'tv_supabase_main');

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.onMainFocusNodeCreated?.call(_focus);
    _refresh();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final isGuest = await SupabaseConfig.isGuest();
    final name = await SupabaseConfig.getCurrentProfileName();
    if (!mounted) return;
    setState(() {
      if (SupabaseAuth.isLoggedIn) {
        _status = name != null ? 'Perfil: $name' : 'Cuenta activa';
      } else if (isGuest) {
        _status = 'Modo invitado';
      } else {
        _status = 'Sin sesión';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Focus(
      focusNode: _focus,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Cuenta y perfiles',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          _TvTile(
            icon: Icons.account_circle,
            title: 'Ajustes de cuenta',
            subtitle: 'Login, contraseña, vincular TV',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AccountSettingsPage(isTv: true),
                ),
              );
              _refresh();
            },
          ),
          const SizedBox(height: 12),
          _TvTile(
            icon: Icons.people,
            title: 'Elegir perfil',
            subtitle: 'Cambiar de perfil o entrar como invitado',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const ProfileSelectionPage(allowDismiss: true),
                ),
              );
              _refresh();
            },
          ),
        ],
      ),
    );
  }
}

class _TvTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TvTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
