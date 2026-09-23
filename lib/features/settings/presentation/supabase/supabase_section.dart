import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../supabase/supabase_client.dart';
import '../../../../supabase/supabase_config.dart';
import '../../../../supabase/supabase_admin.dart';
import '../../../profile/presentation/profile_selection_page.dart';

const _kAccent = Color(0xFFE50914);

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
      _setStatus('URL y ANON KEY son obligatorios', Colors.red);
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
        _hasCreds = true; // guardado en prefs aunque init falle
      });

      if (ok) {
        final loggedIn = await SupabaseConfig.isLoggedIn();
        if (!loggedIn) {
          _setStatus(
            'Credenciales guardadas. Elige un perfil para activar Supabase.',
            Colors.green,
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
                    'Perfil activado. Tus guardados se sincronizarán en la nube.',
                    Colors.green,
                  );
                },
              ),
            ),
          );
          await _load();
        } else {
          _setStatus('Credenciales actualizadas. Supabase activo.', Colors.green);
          setState(() => _isActive = true);
        }
      } else {
        // Guardado OK; init puede fallar si las tablas aún no existen
        _setStatus(
          'Credenciales guardadas. Si falla la conexión, revisa URL/KEY o crea las tablas SQL.',
          Colors.orange,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _setStatus(
        'Credenciales guardadas. Reinicia la app si no se activa.',
        Colors.orange,
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
      ok ? Colors.green : Colors.red,
    );
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Desactivar Supabase', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Se eliminarán las credenciales y la sesión. '
          'Tus guardados LOCALES (cache) NO se borran. '
          'La app volverá a usar solo el cache del dispositivo.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar', style: TextStyle(color: Colors.red)),
          ),
        ],
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
    _setStatus(
      'Supabase desactivado. La app usa de nuevo el cache local.',
      Colors.orange,
    );
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
        'El admin de la app no ha configurado el servidor de vinculación.',
        Colors.red,
      );
      return;
    }

    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      _setStatus('Código inválido', Colors.red);
      return;
    }
    final url = await SupabaseConfig.getUrl();
    final key = await SupabaseConfig.getAnonKey();
    if (url == null || key == null) {
      _setStatus('Primero configura TU URL y ANON KEY personales arriba', Colors.red);
      return;
    }

    setState(() => _saving = true);
    // Escribe en el proyecto ADMIN de la app (no en el del usuario)
    final ok = await SupabaseAdmin.linkCodeWithCredentials(
      code: code,
      supabaseUrl: url,
      supabaseAnonKey: key,
    );
    setState(() => _saving = false);

    _setStatus(
      ok
          ? 'Código vinculado. La TV recibirá tus credenciales en unos segundos.'
          : 'No se pudo vincular. Verifica el código (y que el admin tenga la tabla tv_link).',
      ok ? Colors.green : Colors.red,
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Estructura de tablas SQL',
          style: TextStyle(color: Colors.white),
        ),
        content: const SingleChildScrollView(
          child: SelectableText(
            sql,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: sql));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SQL copiado al portapapeles')),
              );
            },
            child: const Text('Copiar SQL', style: TextStyle(color: _kAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }


  Future<void> _showProfileLoginModal() async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Elige cómo entra la app cuando Supabase está activo',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.person_search,
                    color: _askEveryLaunch ? _kAccent : Colors.white54,
                  ),
                  title: const Text(
                    'Pedir perfil cada vez',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Al abrir siempre eliges quién está viendo',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: _askEveryLaunch
                      ? const Icon(Icons.check_circle, color: _kAccent)
                      : null,
                  onTap: () => Navigator.pop(ctx, true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.history,
                    color: !_askEveryLaunch ? _kAccent : Colors.white54,
                  ),
                  title: const Text(
                    'Recordar último perfil',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Entra directo con el último perfil usado',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: !_askEveryLaunch
                      ? const Icon(Icons.check_circle, color: _kAccent)
                      : null,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Supabase (opcional)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isActive
                ? 'Activo · Perfil: ${_currentUser ?? "—"}'
                : _hasCreds
                    ? 'Credenciales guardadas · Falta elegir perfil'
                    : 'No configurado · La app usa cache local',
            style: TextStyle(
              color: _isActive
                  ? Colors.greenAccent
                  : _hasCreds
                      ? Colors.orangeAccent
                      : Colors.white38,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Si no configuras nada, la app funciona exactamente igual que antes '
            '(guardados e historial en el dispositivo). Supabase solo se activa '
            'cuando pegas tu URL + ANON KEY y eliges un perfil.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // Inicio de sesión de perfil (modal)
          if (_isActive || _hasCreds) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.manage_accounts, color: _kAccent),
              title: const Text(
                'Inicio de sesión de perfil',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: Text(
                _askEveryLaunch
                    ? 'Actual: Pedir perfil cada vez'
                    : 'Actual: Recordar último perfil',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: _showProfileLoginModal,
            ),
          ],

          const SizedBox(height: 12),

          // Botón cambiar perfil (solo si ya hay conexión activa)
          if (_isActive) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _changeProfile,
                icon: const Icon(Icons.switch_account, color: _kAccent),
                label: Text(
                  'Cambiar perfil (${_currentUser ?? "..."})',
                  style: const TextStyle(color: Colors.white),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // URL
          _label('TU_SUPABASE_URL'),
          TextField(
            controller: _urlCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco('https://xxxx.supabase.co'),
          ),
          const SizedBox(height: 12),

          // ANON KEY
          _label('TU_SUPABASE_ANON_KEY'),
          TextField(
            controller: _keyCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'),
            obscureText: true,
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveAndTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
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
                      : Text(_hasCreds ? 'Actualizar credenciales' : 'Activar Supabase'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _testing ? null : _testConnection,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                child: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Probar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _showSqlStructure,
                child: const Text(
                  'Ver estructura SQL de tablas',
                  style: TextStyle(color: _kAccent, fontSize: 13),
                ),
              ),
              const Spacer(),
              if (_hasCreds)
                TextButton(
                  onPressed: _clear,
                  child: const Text(
                    'Desactivar Supabase',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
            ],
          ),

          if (_statusMsg != null) ...[
            const SizedBox(height: 8),
            Text(_statusMsg!, style: TextStyle(color: _statusColor, fontSize: 13)),
          ],

          const Divider(color: Colors.white12, height: 32),

          // Vincular TV
          const Text(
            'Vincular TV por código',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'En la TV genera un código. Escríbelo aquí para enviar tus credenciales. '
            'La TV pasará a usar tu proyecto Supabase y sus perfiles.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: _inputDeco('000000').copyWith(counterText: ''),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _linkCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B5CFF),
                foregroundColor: Colors.white,
              ),
              child: const Text('Vincular código a este dispositivo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF1a1a2e),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
}
