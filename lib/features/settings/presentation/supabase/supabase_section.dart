import 'package:flutter/material.dart';
import '../account/account_settings_page.dart';
import '../../../../supabase/supabase_auth.dart';
import '../../../../supabase/supabase_config.dart';
import '../../../profile/presentation/profile_selection_page.dart';
import '../../../profile/presentation/manage_profiles_page.dart';

/// Sección de cuenta / perfiles en Ajustes (móvil).
/// Reemplaza la antigua configuración de URL+KEY del usuario.
class SupabaseSection extends StatefulWidget {
  const SupabaseSection({super.key});

  @override
  State<SupabaseSection> createState() => _SupabaseSectionState();
}

class _SupabaseSectionState extends State<SupabaseSection> {
  String _status = 'Cargando...';

  @override
  void initState() {
    super.initState();
    _refresh();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.account_circle, color: Colors.white70),
          title: const Text('Cuenta', style: TextStyle(color: Colors.white)),
          subtitle: Text(_status, style: const TextStyle(color: Colors.white54)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
            );
            _refresh();
          },
        ),
        ListTile(
          leading: const Icon(Icons.people, color: Colors.white70),
          title: const Text('Perfiles', style: TextStyle(color: Colors.white)),
          subtitle: const Text(
            'Elegir o gestionar perfiles',
            style: TextStyle(color: Colors.white54),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProfileSelectionPage(allowDismiss: true),
              ),
            );
            _refresh();
          },
        ),
        if (SupabaseAuth.isLoggedIn)
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.white70),
            title: const Text(
              'Gestionar perfiles',
              style: TextStyle(color: Colors.white),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageProfilesPage()),
              );
              _refresh();
            },
          ),
      ],
    );
  }
}
