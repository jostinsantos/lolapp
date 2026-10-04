import 'package:flutter/material.dart';
import '../../../../supabase/supabase_auth.dart';
import '../../../../supabase/supabase_client.dart';
import '../../../../supabase/supabase_tv_link.dart';
import '../../../auth/presentation/login_register_page.dart';

/// Ajustes de CUENTA: email, cambiar pass, vincular TV, cerrar sesión.
class AccountSettingsPage extends StatefulWidget {
  final bool isTv;

  const AccountSettingsPage({super.key, this.isTv = false});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _passCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _tvCode;
  bool _polling = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final pass = _passCtrl.text;
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mínimo 6 caracteres')),
      );
      return;
    }
    setState(() => _loading = true);
    final ok = await SupabaseAuth.updatePassword(pass);
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Contraseña actualizada' : 'Error al cambiar')),
    );
    if (ok) _passCtrl.clear();
  }

  Future<void> _linkTvCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El código debe tener 6 dígitos')),
      );
      return;
    }
    setState(() => _loading = true);
    final ok = await SupabaseTvLink.linkCode(code);
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '¡TV vinculada correctamente!'
            : 'Código inválido o expirado'),
      ),
    );
    if (ok) _codeCtrl.clear();
  }

  Future<void> _generateTvCode() async {
    setState(() {
      _loading = true;
      _tvCode = null;
    });
    final code = await SupabaseTvLink.createCode();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _tvCode = code;
      _polling = code != null;
    });

    // Polling automático
    if (code != null) {
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted || !_polling) break;
        final accountId = await SupabaseTvLink.pollCode(code);
        if (accountId != null) {
          if (mounted) {
            setState(() => _polling = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('¡Dispositivo vinculado!')),
            );
          }
          break;
        }
      }
      if (mounted) setState(() => _polling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = SupabaseAuth.currentEmail ?? '—';
    final created = SupabaseAuth.accountCreatedAt;
    final createdStr = created != null
        ? '${created.day}/${created.month}/${created.year}'
        : '—';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Cuenta'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Info de la cuenta
          if (SupabaseAuth.isLoggedIn) ...[
            _sectionTitle('Información de la cuenta'),
            _infoTile(Icons.email, 'Correo', email),
            _infoTile(Icons.calendar_today, 'Fecha de creación', createdStr),
            const SizedBox(height: 24),

            // Cambiar contraseña
            _sectionTitle('Cambiar contraseña'),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _deco('Nueva contraseña'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _changePassword,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Actualizar contraseña'),
            ),
            const SizedBox(height: 32),

            // Vincular TV (desde móvil)
            if (!widget.isTv) ...[
              _sectionTitle('Vincular TV'),
              const Text(
                'En la TV genera un código e introdúcelo aquí.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
                textAlign: TextAlign.center,
                decoration: _deco('Código de 6 dígitos').copyWith(counterText: ''),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loading ? null : _linkTvCode,
                icon: const Icon(Icons.tv),
                label: const Text('Vincular TV'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              ),
              const SizedBox(height: 32),
            ],

            // Generar código (desde TV)
            if (widget.isTv) ...[
              _sectionTitle('Vincular con móvil'),
              const Text(
                'Genera un código y escríbelo en la app del móvil.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (_tvCode != null)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _tvCode!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 12,
                        ),
                      ),
                      if (_polling)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Esperando vinculación...',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _loading ? null : _generateTvCode,
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Generar código'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                  ),
                ),
              const SizedBox(height: 32),
            ],

            // Cerrar sesión
            OutlinedButton.icon(
              onPressed: () async {
                await SupabaseAuth.signOut();
                if (mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text('Cerrar sesión', style: TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ] else ...[
            // No logueado
            const SizedBox(height: 40),
            const Center(
              child: Icon(Icons.account_circle, size: 80, color: Colors.white38),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'No has iniciado sesión',
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginRegisterPage()),
                );
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Iniciar sesión / Crear cuenta'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.white54),
      title: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      subtitle: Text(value, style: const TextStyle(color: Colors.white, fontSize: 15)),
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
