import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../supabase/supabase_auth.dart';
import '../../../supabase/supabase_client.dart';

const _kAccent = Color(0xFFE50914);

/// Página de Login / Registro de CUENTA (móvil vertical).
/// Fondo negro puro, glass + blur, sin AppBar, logo desde assets/logo.png
class LoginRegisterPage extends StatefulWidget {
  final VoidCallback? onSuccess;
  final bool isTv;

  const LoginRegisterPage({
    super.key,
    this.onSuccess,
    this.isTv = false,
  });

  @override
  State<LoginRegisterPage> createState() => _LoginRegisterPageState();
}

class _LoginRegisterPageState extends State<LoginRegisterPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  final _emailFocus = FocusNode(debugLabel: 'login_email');
  final _passFocus = FocusNode(debugLabel: 'login_pass');
  final _pass2Focus = FocusNode(debugLabel: 'login_pass2');
  final _submitFocus = FocusNode(debugLabel: 'login_submit');
  final _toggleFocus = FocusNode(debugLabel: 'login_toggle');

  bool _isRegister = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _pass2Focus.dispose();
    _submitFocus.dispose();
    _toggleFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Completa todos los campos');
      return;
    }
    if (_isRegister && pass != _pass2Ctrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    await AppSupabase.init();

    final result = _isRegister
        ? await SupabaseAuth.signUp(email: email, password: pass)
        : await SupabaseAuth.signIn(email: email, password: pass);

    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.ok || !result.hasSession) {
      setState(() {
        _error = result.error ??
            (_isRegister
                ? 'No se pudo crear la cuenta'
                : 'Email o contraseña incorrectos');
      });
      return;
    }

    widget.onSuccess?.call();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Fondo negro puro con halo sutil
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.6),
                  radius: 1.2,
                  colors: [
                    Color(0xFF141418),
                    Color(0xFF050505),
                    Color(0xFF000000),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo
                      Center(
                        child: Image.asset(
                          'assets/logo.png',
                          height: 84,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Text(
                            'LOGO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Título
                      Text(
                        _isRegister ? 'Crear cuenta' : 'Iniciar sesión',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegister
                            ? 'Regístrate para guardar tus perfiles'
                            : 'Accede para continuar',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Email
                      _GlassField(
                        key: const ValueKey('email'),
                        controller: _emailCtrl,
                        focusNode: _emailFocus,
                        hint: 'Correo electrónico',
                        icon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _passFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),

                      // Password
                      _GlassField(
                        key: const ValueKey('pass'),
                        controller: _passCtrl,
                        focusNode: _passFocus,
                        hint: 'Contraseña',
                        icon: Icons.lock_outline,
                        obscure: _obscure,
                        textInputAction: _isRegister
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: (_) {
                          if (_isRegister) {
                            _pass2Focus.requestFocus();
                          } else {
                            _submit();
                          }
                        },
                        trailing: IconButton(
                          splashRadius: 18,
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white54,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),

                      // Confirmar password (solo registro)
                      if (_isRegister) ...[
                        const SizedBox(height: 14),
                        _GlassField(
                          key: const ValueKey('pass2'),
                          controller: _pass2Ctrl,
                          focusNode: _pass2Focus,
                          hint: 'Repetir contraseña',
                          icon: Icons.lock_outline,
                          obscure: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],

                      // Error
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.redAccent.withOpacity(0.10),
                            border: Border.all(
                              color: Colors.redAccent.withOpacity(0.45),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Botón principal
                      _GlassButton(
                        focusNode: _submitFocus,
                        label: _isRegister ? 'Crear cuenta' : 'Entrar',
                        primary: true,
                        loading: _loading,
                        onTap: _loading ? null : _submit,
                      ),

                      const SizedBox(height: 14),

                      // Toggle login/registro
                      _GlassButton(
                        focusNode: _toggleFocus,
                        label: _isRegister
                            ? '¿Ya tienes cuenta? Inicia sesión'
                            : '¿No tienes cuenta? Regístrate',
                        onTap: _loading
                            ? null
                            : () => setState(() {
                                  _isRegister = !_isRegister;
                                  _error = null;
                                }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Campo de texto con efecto glass + blur
// ============================================================
class _GlassField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  const _GlassField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  @override
  State<_GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<_GlassField> {
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused
              ? Colors.white
              : Colors.white.withOpacity(0.10),
          width: _focused ? 1.6 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: Colors.white.withOpacity(0.18),
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
                ? Colors.white.withOpacity(0.08)
                : Colors.white.withOpacity(0.035),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: _focused
                      ? Colors.white
                      : Colors.white.withOpacity(0.55),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    obscureText: widget.obscure,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    onSubmitted: widget.onSubmitted,
                    cursorColor: _kAccent,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Botón glass + blur
// ============================================================
class _GlassButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final FocusNode focusNode;
  final bool primary;
  final bool loading;

  const _GlassButton({
    required this.label,
    required this.onTap,
    required this.focusNode,
    this.primary = false,
    this.loading = false,
  });

  @override
  State<_GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<_GlassButton> {
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
    final accent = widget.primary ? _kAccent : Colors.white;
    final disabled = widget.onTap == null;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Focus(
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
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? Colors.white
                    : accent.withOpacity(widget.primary ? 0.55 : 0.14),
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
              borderRadius: BorderRadius.circular(13),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  color: _focused
                      ? Colors.white.withOpacity(0.12)
                      : (widget.primary
                          ? _kAccent.withOpacity(0.22)
                          : Colors.white.withOpacity(0.05)),
                  child: widget.loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.primary ? 15.5 : 13.5,
                            fontWeight: widget.primary
                                ? FontWeight.w800
                                : FontWeight.w600,
                            letterSpacing: 0.4,
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