import 'package:flutter/material.dart';
import '../../../supabase/supabase_profiles.dart';
import '../../../supabase/supabase_auth.dart';

/// Crear o editar un perfil: nombre, avatar, backdrop, PIN.
class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic>? profile; // null = crear

  const EditProfilePage({super.key, this.profile});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _avatarCtrl;
  late final TextEditingController _backdropCtrl;
  late final TextEditingController _pinCtrl;
  bool _loading = false;
  bool _obscurePin = true;

  bool get isEdit => widget.profile != null;

  // Avatares predefinidos (puedes ampliar la lista)
  static const _presetAvatars = [
    'https://api.dicebear.com/7.x/avataaars/png?seed=1',
    'https://api.dicebear.com/7.x/avataaars/png?seed=2',
    'https://api.dicebear.com/7.x/avataaars/png?seed=3',
    'https://api.dicebear.com/7.x/avataaars/png?seed=4',
    'https://api.dicebear.com/7.x/avataaars/png?seed=5',
    'https://api.dicebear.com/7.x/avataaars/png?seed=6',
    'https://api.dicebear.com/7.x/avataaars/png?seed=7',
    'https://api.dicebear.com/7.x/avataaars/png?seed=8',
  ];

  // Backdrops predefinidos (TMDB)
  static const _presetBackdrops = [
    'https://image.tmdb.org/t/p/original/4kTINu9mv2YV1PqFqPGG1FZMnhi.jpg',
    'https://image.tmdb.org/t/p/original/yr1n2RzZHn1UYozrzvPzjcE60cP.jpg',
    'https://image.tmdb.org/t/p/original/cFXxKJzGrvjcmMJAReNekx0RVJb.jpg',
    'https://image.tmdb.org/t/p/original/viZqGq9TNvQ5uXSD4ahg2RpRONT.jpg',
    'https://image.tmdb.org/t/p/original/HxkNuj4kinoukZzr8IvtHAMTRo.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile?['name']?.toString() ?? '');
    _avatarCtrl = TextEditingController(text: widget.profile?['avatar_url']?.toString() ?? '');
    _backdropCtrl = TextEditingController(text: widget.profile?['backdrop_url']?.toString() ?? '');
    _pinCtrl = TextEditingController(text: widget.profile?['pin']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _avatarCtrl.dispose();
    _backdropCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
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
        avatarUrl: _avatarCtrl.text.trim().isEmpty ? null : _avatarCtrl.text.trim(),
        backdropUrl: _backdropCtrl.text.trim().isEmpty ? null : _backdropCtrl.text.trim(),
        pin: _pinCtrl.text.trim(),
      );
    } else {
      createdProfile = await SupabaseProfiles.create(
        name: name,
        avatarUrl: _avatarCtrl.text.trim().isEmpty ? null : _avatarCtrl.text.trim(),
        backdropUrl: _backdropCtrl.text.trim().isEmpty ? null : _backdropCtrl.text.trim(),
        pin: _pinCtrl.text.trim().isEmpty ? null : _pinCtrl.text.trim(),
      );
      ok = createdProfile != null;
      // Auto-seleccionar el perfil recién creado
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(isEdit ? 'Editar perfil' : 'Crear perfil'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview avatar
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _avatarCtrl.text.isNotEmpty
                    ? NetworkImage(_avatarCtrl.text)
                    : null,
                child: _avatarCtrl.text.isEmpty
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
            const SizedBox(height: 24),

            // Nombre
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _deco('Nombre del perfil'),
            ),
            const SizedBox(height: 20),

            // Avatar URL
            const Text('Avatar', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _avatarCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: _deco('URL del avatar (opcional)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _presetAvatars.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final url = _presetAvatars[i];
                  final selected = _avatarCtrl.text == url;
                  return GestureDetector(
                    onTap: () => setState(() => _avatarCtrl.text = url),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? Colors.redAccent : Colors.white24,
                          width: selected ? 2 : 1,
                        ),
                        image: DecorationImage(
                          image: NetworkImage(url),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Backdrop
            const Text('Fondo (backdrop)', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _backdropCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: _deco('URL del fondo (opcional)'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _presetBackdrops.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final url = _presetBackdrops[i];
                  final selected = _backdropCtrl.text == url;
                  return GestureDetector(
                    onTap: () => setState(() => _backdropCtrl.text = url),
                    child: Container(
                      width: 120,
                      height: 68,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? Colors.redAccent : Colors.white24,
                          width: selected ? 2 : 1,
                        ),
                        image: DecorationImage(
                          image: NetworkImage(url),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // PIN
            const Text('PIN de seguridad (opcional)', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _pinCtrl,
              obscureText: _obscurePin,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white),
              decoration: _deco('4-6 dígitos').copyWith(
                counterText: '',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePin ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white54,
                  ),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Si pones un PIN, se pedirá cada vez que se seleccione este perfil.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _deco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }
}
