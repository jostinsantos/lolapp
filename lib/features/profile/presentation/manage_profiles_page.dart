import 'package:flutter/material.dart';
import '../../../supabase/supabase_profiles.dart';
import 'edit_profile_page.dart';
import '../../../supabase/supabase_config.dart';

/// Página para gestionar (crear / editar / eliminar) los perfiles de la cuenta.
class ManageProfilesPage extends StatefulWidget {
  const ManageProfilesPage({super.key});

  @override
  State<ManageProfilesPage> createState() => _ManageProfilesPageState();
}

class _ManageProfilesPageState extends State<ManageProfilesPage> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await SupabaseProfiles.list();
    if (!mounted) return;
    setState(() {
      _profiles = list;
      _loading = false;
    });
  }

  Future<void> _createOrEdit({Map<String, dynamic>? profile}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(profile: profile),
      ),
    );
    if (result == true && mounted) {
      await _load();
      // Si acabamos de crear (no editar) y hay perfil en sesión, volver atrás
      if (profile == null) {
        final id = await SupabaseConfig.getCurrentProfileId();
        if (id != null && mounted) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Eliminar perfil', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Seguro que quieres eliminar "${profile['name']}"?\nSe borrarán su historial, guardados y likes.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await SupabaseProfiles.delete(profile['id'].toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Perfil eliminado' : 'Error al eliminar')),
      );
      if (ok) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Gestionar perfiles'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._profiles.map((p) => Card(
                      color: Colors.white.withOpacity(0.06),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: (p['avatar_url'] != null &&
                                  p['avatar_url'].toString().isNotEmpty)
                              ? NetworkImage(p['avatar_url'].toString())
                              : null,
                          child: (p['avatar_url'] == null ||
                                  p['avatar_url'].toString().isEmpty)
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(
                          p['name']?.toString() ?? 'Usuario',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          (p['pin'] != null && p['pin'].toString().isNotEmpty)
                              ? 'Con PIN de seguridad'
                              : 'Sin PIN',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white70),
                              onPressed: () => _createOrEdit(profile: p),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _delete(p),
                            ),
                          ],
                        ),
                      ),
                    )),
                if (_profiles.length < 5) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _createOrEdit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear nuevo perfil'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
                if (_profiles.length >= 5)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Has alcanzado el máximo de 5 perfiles.',
                      style: TextStyle(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}
