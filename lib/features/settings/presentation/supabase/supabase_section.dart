import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../supabase/supabase_client.dart';
import '../../../../supabase/supabase_config.dart';
import '../../../../supabase/supabase_admin.dart';
import '../../../profile/presentation/profile_selection_page.dart';

const _kAccent = Color(0xFFE50914);
const _kCard = Color(0xFF16161A);
const _kBgField = Color(0xFF1C1C22);
const _kBorder = Color(0x22FFFFFF);

class SupabaseSection extends StatefulWidget {
  const SupabaseSection({super.key});

  @override
  State<SupabaseSection> createState() => _SupabaseSectionState();
}

class _SupabaseSectionState extends State<SupabaseSection> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _hasCreds = false;
  bool _isActive = false;
  bool _askEveryLaunch = false;
  bool _obscureKey = true;
  String? _currentUser;
  String? _statusMsg;
  Color _statusColor = Colors.white54;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final url = await SupabaseConfig.getUrl();
    final key = await SupabaseConfig.getAnonKey();
    final user = await SupabaseConfig.getCurrentUserName();
    final has = await SupabaseConfig.hasCredentials();
    final active = await SupabaseConfig.isSupabaseActive();
    final askEvery = await SupabaseConfig.getAskProfileEveryLaunch();

    if (!mounted) return;
    setState(() {
      _urlCtrl.text = url ?? '';
      _keyCtrl.text = key ?? '';
      _currentUser = user;
      _hasCreds = has;
      _isActive = active;
      _askEveryLaunch = askEvery;
      _loading = false;
    });
  }

  Future<void> _saveAndTest() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      _setStatus('URL y ANON KEY son obligatorios', Colors.redAccent);
      return;
    }

    setState(() {
      _saving = true;
      _statusMsg = null;
    });

    try {
      await SupabaseConfig.setCredentials(url: url, anonKey: key);
      final ok = await AppSupabase.reinit();

      if (!mounted) return;
      setState(() {
        _saving = false;
        _hasCreds = true;
      });

      if (ok) {
        final loggedIn = await SupabaseConfig.isLoggedIn();
        if (!loggedIn) {
          _setStatus(
            'Credenciales guardadas. Elige un perfil.',
            const Color(0xFF4ADE80),
          );
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProfileSelectionPage(
                allowDismiss: false,
                onProfileSelected: () {
                  Navigator.of(context).pop();
                  _load();
                  _setStatus(
                    'Perfil activado. Guardados en la nube.',
                    const Color(0xFF4ADE80),
                  );
                },
              ),
            ),
          );
          await _load();
        } else {
          _setStatus('Credenciales actualizadas.', const Color(0xFF4ADE80));
          setState(() => _isActive = true);
        }
      } else {
        _setStatus(
          'Guardado. Si falla la conexión, revisa URL/KEY o tablas SQL.',
          Colors.orangeAccent,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _setStatus(
        'Guardado. Reinicia la app si no se activa.',
        Colors.orangeAccent,
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _statusMsg = null;
    });
    final ok = await AppSupabase.testConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    _setStatus(
      ok ? 'Conexión OK' : 'Falló la conexión. Revisa URL, KEY y tablas.',
      ok ? const Color(0xFF4ADE80) : Colors.redAccent,
    );
  }

  Future<void> _clear() async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Desactivar Supabase',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Se eliminan credenciales y sesión. '
                'Los guardados locales no se borran.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Desactivar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;

    await SupabaseConfig.clearCredentials();
    await AppSupabase.reinit();
    _urlCtrl.clear();
    _keyCtrl.clear();
    setState(() {
      _hasCreds = false;
      _isActive = false;
      _currentUser = null;
    });
    _setStatus('Supabase desactivado. Caché local activo.', Colors.orangeAccent);
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

  Future<void> _linkCode() async {
    if (!SupabaseAdmin.isAdminConfigured) {
      _setStatus(
        'El admin no configuró el servidor de vinculación.',
        Colors.redAccent,
      );
      return;
    }

    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      _setStatus('Código inválido', Colors.redAccent);
      return;
    }
    final url = await SupabaseConfig.getUrl();
    final key = await SupabaseConfig.getAnonKey();
    if (url == null || key == null) {
      _setStatus('Primero configura tu URL y ANON KEY', Colors.redAccent);
      return;
    }

    setState(() => _saving = true);
    final ok = await SupabaseAdmin.linkCodeWithCredentials(
      code: code,
      supabaseUrl: url,
      supabaseAnonKey: key,
    );
    setState(() => _saving = false);

    _setStatus(
      ok
          ? 'Código vinculado. La TV recibirá tus credenciales.'
          : 'No se pudo vincular. Verifica el código.',
      ok ? const Color(0xFF4ADE80) : Colors.redAccent,
    );
  }

  void _setStatus(String msg, Color color) {
    setState(() {
      _statusMsg = msg;
      _statusColor = color;
    });
  }

  void _showSqlStructure() {
    const sql = '''-- 1. Perfiles
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  avatar_url text,
  created_at timestamptz default now()
);

-- 2. Guardados
create table if not exists public.guardados (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  idcontenido integer not null,
  poster text,
  titulo text not null,
  tipo text not null,
  created_at timestamptz default now(),
  unique (user_id, idcontenido)
);

-- 3. Vinculación TV
create table if not exists public.tv_link (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  supabase_url text,
  supabase_anon_key text,
  used boolean default false,
  created_at timestamptz default now(),
  expires_at timestamptz default (now() + interval '15 minutes')
);

alter table public.profiles enable row level security;
create policy "all profiles" on public.profiles for all using (true) with check (true);

alter table public.guardados enable row level security;
create policy "all guardados" on public.guardados for all using (true) with check (true);

alter table public.tv_link enable row level security;
create policy "all tv_link" on public.tv_link for all using (true) with check (true);''';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scroll) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Estructura SQL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: sql));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('SQL copiado'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copiar'),
                    style: TextButton.styleFrom(foregroundColor: _kAccent),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                child: const SelectableText(
                  sql,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProfileLoginModal() async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Inicio de sesión de perfil',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cómo entra la app cuando Supabase está activo',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                _prefTile(
                  selected: _askEveryLaunch,
                  icon: Icons.person_search_rounded,
                  title: 'Pedir perfil cada vez',
                  subtitle: 'Al abrir siempre eliges quién mira',
                  onTap: () => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 8),
                _prefTile(
                  selected: !_askEveryLaunch,
                  icon: Icons.history_rounded,
                  title: 'Recordar último perfil',
                  subtitle: 'Entra directo con el último usado',
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    await SupabaseConfig.setAskProfileEveryLaunch(selected);
    setState(() => _askEveryLaunch = selected);
  }

  Widget _prefTile({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? _kAccent.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? _kAccent : Colors.white54,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                const Icon(Icons.check_circle_rounded, color: _kAccent, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }

    // Column (no ListView): esta sección ya vive dentro del scroll de Ajustes.
    // ListView anidado → "Vertical viewport was given unbounded height".
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
        // ── Header estado ────────────────────────────────────────────
        _StatusHeader(
          isActive: _isActive,
          hasCreds: _hasCreds,
          userName: _currentUser,
        ),
        const SizedBox(height: 20),

        // ── Cuenta / perfil ──────────────────────────────────────────
        if (_isActive || _hasCreds) ...[
          _SectionCard(
            title: 'Cuenta',
            children: [
              _ActionRow(
                icon: Icons.manage_accounts_rounded,
                title: 'Inicio de sesión',
                subtitle: _askEveryLaunch
                    ? 'Pedir perfil cada vez'
                    : 'Recordar último perfil',
                onTap: _showProfileLoginModal,
              ),
              if (_isActive) ...[
                const SizedBox(height: 4),
                Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
                const SizedBox(height: 4),
                _ActionRow(
                  icon: Icons.switch_account_rounded,
                  title: 'Cambiar perfil',
                  subtitle: _currentUser ?? 'Elegir otro',
                  onTap: _changeProfile,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ],

        // ── Credenciales ─────────────────────────────────────────────
        _SectionCard(
          title: 'Credenciales',
          subtitle: 'Tu proyecto Supabase personal',
          children: [
            _fieldLabel('URL del proyecto'),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              keyboardType: TextInputType.url,
              decoration: _deco('https://xxxx.supabase.co'),
            ),
            const SizedBox(height: 14),
            _fieldLabel('Anon key'),
            TextField(
              controller: _keyCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              obscureText: _obscureKey,
              decoration: _deco('eyJhbGciOiJIUzI1NiIs…').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveAndTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _hasCreds ? 'Actualizar' : 'Activar',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testing ? null : _testConnection,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Probar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: _showSqlStructure,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white54,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text(
                    'Ver SQL',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const Spacer(),
                if (_hasCreds)
                  TextButton(
                    onPressed: _clear,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: const Text(
                      'Desactivar',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
            if (_statusMsg != null) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _statusColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  _statusMsg!,
                  style: TextStyle(color: _statusColor, fontSize: 12.5),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 16),

        // ── Vincular TV ──────────────────────────────────────────────
        _SectionCard(
          title: 'Vincular TV',
          subtitle: 'Escribe el código que muestra la TV',
          children: [
            TextField(
              controller: _codeCtrl,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                letterSpacing: 10,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _deco('000000').copyWith(
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _linkCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: const Text(
                  'Vincular a este dispositivo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La TV pasará a usar tu proyecto y perfiles.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
              ),
            ),
          ],
        ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.2),
          fontSize: 13,
        ),
        filled: true,
        fillColor: _kBgField,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kAccent.withValues(alpha: 0.5)),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Piezas de UI
// ═══════════════════════════════════════════════════════════════════════════

class _StatusHeader extends StatelessWidget {
  final bool isActive;
  final bool hasCreds;
  final String? userName;

  const _StatusHeader({
    required this.isActive,
    required this.hasCreds,
    this.userName,
  });

  @override
  Widget build(BuildContext context) {
    final Color dot;
    final String label;
    final String hint;

    if (isActive) {
      dot = const Color(0xFF4ADE80);
      label = 'Activo';
      hint = userName != null ? 'Perfil · $userName' : 'Sincronización en la nube';
    } else if (hasCreds) {
      dot = Colors.orangeAccent;
      label = 'Credenciales guardadas';
      hint = 'Falta elegir un perfil';
    } else {
      dot = Colors.white38;
      label = 'No configurado';
      hint = 'La app usa solo el caché del dispositivo';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dot.withValues(alpha: 0.45),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
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

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white70, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
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
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}