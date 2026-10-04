import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../supabase/supabase_auth.dart';
import '../../../supabase/supabase_client.dart';

const _kAccent = Color(0xFFE50914);
const _kKeyColor = Color(0xFF2A2A38);

/// Login / Registro para TV.
/// Teclado en pantalla a la izquierda (con @ para el correo),
/// formulario a la derecha y navegación completa por D-pad.
class TvLoginRegisterPage extends StatefulWidget {
  final VoidCallback? onSuccess;

  const TvLoginRegisterPage({
    super.key,
    this.onSuccess,
  });

  @override
  State<TvLoginRegisterPage> createState() => _TvLoginRegisterPageState();
}

class _TvLoginRegisterPageState extends State<TvLoginRegisterPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  bool _isRegister = false;
  bool _loading = false;
  bool _obscure = true;
  bool _showAccents = false;
  String? _error;

  /// Campo actualmente activo para el teclado en pantalla:
  /// 0 = email, 1 = pass, 2 = pass2 (solo registro).
  int _activeField = 0;

  /// Cuando es true, el campo activo recibe foco y se abre el
  /// teclado del sistema (Android TV).
  bool _sysKeyboard = false;

  final FocusNode _aKeyFocusNode = FocusNode(debugLabel: 'tv_kb_a');
  final FocusNode _emailFocus = FocusNode(debugLabel: 'tv_email');
  final FocusNode _passFocus = FocusNode(debugLabel: 'tv_pass');
  final FocusNode _pass2Focus = FocusNode(debugLabel: 'tv_pass2');
  final FocusNode _submitFocus = FocusNode(debugLabel: 'tv_submit');
  final FocusNode _modeFocus = FocusNode(debugLabel: 'tv_mode');
  final FocusNode _sysKbFocus = FocusNode(debugLabel: 'tv_sys_kb');

  TextEditingController get _activeCtrl {
    switch (_activeField) {
      case 0:
        return _emailCtrl;
      case 1:
        return _passCtrl;
      default:
        return _pass2Ctrl;
    }
  }

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(_onFocusChanged);
    _passFocus.addListener(_onFocusChanged);
    _pass2Focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _aKeyFocusNode.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _pass2Focus.dispose();
    _submitFocus.dispose();
    _modeFocus.dispose();
    _sysKbFocus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_emailFocus.hasFocus) {
      setState(() => _activeField = 0);
    } else if (_passFocus.hasFocus) {
      setState(() => _activeField = 1);
    } else if (_pass2Focus.hasFocus) {
      setState(() => _activeField = 2);
    }
  }

  // ── Teclado en pantalla ─────────────────────────────────────────────────

  void _onKey(String c) {
    final ctrl = _activeCtrl;
    final text = ctrl.text;
    ctrl.value = TextEditingValue(
      text: text + c,
      selection: TextSelection.collapsed(offset: text.length + c.length),
    );
    setState(() => _error = null);
  }

  void _onBackspace() {
    final ctrl = _activeCtrl;
    final text = ctrl.text;
    if (text.isEmpty) return;
    ctrl.value = TextEditingValue(
      text: text.substring(0, text.length - 1),
      selection: TextSelection.collapsed(offset: text.length - 1),
    );
  }

  void _onClear() {
    _activeCtrl.clear();
  }

  void _toggleAccents() {
    setState(() => _showAccents = !_showAccents);
  }

  // ── Teclado del sistema (Android TV) ────────────────────────────────────

  Future<void> _openSystemKeyboard() async {
    setState(() => _sysKeyboard = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    switch (_activeField) {
      case 0:
        _emailFocus.requestFocus();
        break;
      case 1:
        _passFocus.requestFocus();
        break;
      default:
        _pass2Focus.requestFocus();
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _closeSystemKeyboard() {
    if (!_sysKeyboard) return;
    setState(() => _sysKeyboard = false);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    _closeSystemKeyboard();
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

  void _toggleMode() {
    setState(() {
      _isRegister = !_isRegister;
      _error = null;
      if (!_isRegister) _pass2Ctrl.clear();
    });
    // Al cambiar de modo, mandamos foco al teclado de la izquierda.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _aKeyFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Columna izquierda: teclado en pantalla ────────────────
            SizedBox(
              width: 250,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Escribe con el mando',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SystemKeyboardButton(
                      focusNode: _sysKbFocus,
                      onTap: _openSystemKeyboard,
                    ),
                    const SizedBox(height: 8),
                    _Keyboard(
                      showAccents: _showAccents,
                      onKey: _onKey,
                      onBackspace: _onBackspace,
                      onClear: _onClear,
                      onToggleAccents: _toggleAccents,
                      aKeyFocusNode: _aKeyFocusNode,
                    ),
                    const SizedBox(height: 10),
                    // Toggle Login / Registro DEBAJO del teclado
                    _FocusAction(
                      focusNode: _modeFocus,
                      onActivate: _loading ? null : _toggleMode,
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _kKeyColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _isRegister
                              ? '¿Ya tienes cuenta? Entrar'
                              : '¿No tienes cuenta? Registrarse',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ─── Columna derecha: formulario ───────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 40, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isRegister ? 'Crear cuenta' : 'Iniciar sesión',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Usa el mando para moverte entre campos y el teclado de la izquierda para escribir.',
                      style: TextStyle(color: Colors.white38, fontSize: 12.5),
                    ),
                    const SizedBox(height: 20),

                    // Email
                    _FieldLabel(
                      text: 'Email',
                      active: _activeField == 0,
                    ),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _emailCtrl,
                      focusNode: _emailFocus,
                      hint: 'tucorreo@ejemplo.com',
                      obscure: false,
                      enabled: _sysKeyboard,
                      keyboardType: TextInputType.emailAddress,
                      onArrowDown: () => _passFocus.requestFocus(),
                      onArrowLeft: () => _aKeyFocusNode.requestFocus(),
                    ),
                    const SizedBox(height: 16),

                    // Contraseña
                    _FieldLabel(
                      text: 'Contraseña',
                      active: _activeField == 1,
                    ),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _passCtrl,
                      focusNode: _passFocus,
                      hint: '••••••••',
                      obscure: _obscure,
                      enabled: _sysKeyboard,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                      keyboardType: TextInputType.visiblePassword,
                      onArrowDown: () {
                        if (_isRegister) {
                          _pass2Focus.requestFocus();
                        } else {
                          _submitFocus.requestFocus();
                        }
                      },
                      onArrowUp: () => _emailFocus.requestFocus(),
                      onArrowLeft: () => _aKeyFocusNode.requestFocus(),
                    ),

                    if (_isRegister) ...[
                      const SizedBox(height: 16),
                      _FieldLabel(
                        text: 'Repetir contraseña',
                        active: _activeField == 2,
                      ),
                      const SizedBox(height: 6),
                      _Field(
                        controller: _pass2Ctrl,
                        focusNode: _pass2Focus,
                        hint: '••••••••',
                        obscure: _obscure,
                        enabled: _sysKeyboard,
                        keyboardType: TextInputType.visiblePassword,
                        onArrowDown: () => _submitFocus.requestFocus(),
                        onArrowUp: () => _passFocus.requestFocus(),
                        onArrowLeft: () => _aKeyFocusNode.requestFocus(),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.redAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),

                    // Botón Entrar / Crear
                    _FocusAction(
                      focusNode: _submitFocus,
                      onActivate: _loading ? null : _submit,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isRegister ? 'Crear cuenta' : 'Entrar',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón que abre el teclado del sistema (Android TV).
class _SystemKeyboardButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _SystemKeyboardButton({
    required this.focusNode,
    required this.onTap,
  });

  @override
  State<_SystemKeyboardButton> createState() =>
      _SystemKeyboardButtonState();
}

class _SystemKeyboardButtonState extends State<_SystemKeyboardButton> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hasFocus ? Colors.white : _kKeyColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hasFocus ? _kAccent : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.keyboard_alt_outlined,
                size: 16,
                color: _hasFocus ? Colors.black : Colors.white70,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Teclado del TV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _hasFocus ? Colors.black : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Teclado en pantalla compacto con @, ., espacio, borrar y acentos.
class _Keyboard extends StatelessWidget {
  final bool showAccents;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onToggleAccents;
  final FocusNode aKeyFocusNode;

  const _Keyboard({
    required this.showAccents,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onToggleAccents,
    required this.aKeyFocusNode,
  });

  static const _rowsNormal = [
    ['a', 'b', 'c', 'd', 'e'],
    ['f', 'g', 'h', 'i', 'j'],
    ['k', 'l', 'm', 'n', 'o'],
    ['p', 'q', 'r', 's', 't'],
    ['u', 'v', 'w', 'x', 'y'],
  ];

  static const _rowsAccents = [
    ['á', 'é', 'í', 'ó', 'ú'],
    ['ü', 'ñ', 'Á', 'É', 'Í'],
    ['Ó', 'Ú', 'Ü', '¿', '¡'],
    ['1', '2', '3', '4', '5'],
    ['6', '7', '8', '9', '0'],
  ];

  @override
  Widget build(BuildContext context) {
    final rows = showAccents ? _rowsAccents : _rowsNormal;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final char in row) ...[
                    _KeyButton(
                      label: char,
                      onTap: () => onKey(char),
                      focusNode: (!showAccents && char == 'a')
                          ? aKeyFocusNode
                          : null,
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          // Fila: z ñ (solo modo normal) + @ + . + espacio
          if (!showAccents)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  _KeyButton(label: 'z', onTap: () => onKey('z')),
                  const SizedBox(width: 4),
                  _KeyButton(label: 'ñ', onTap: () => onKey('ñ')),
                  const SizedBox(width: 4),
                  _KeyButton(label: '@', onTap: () => onKey('@')),
                  const SizedBox(width: 4),
                  _KeyButton(label: '.', onTap: () => onKey('.')),
                  const SizedBox(width: 4),
                  _KeyButton(
                    label: ' ',
                    icon: Icons.space_bar,
                    onTap: () => onKey(' '),
                    flex: 2,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  _KeyButton(label: '@', onTap: () => onKey('@')),
                  const SizedBox(width: 4),
                  _KeyButton(label: '.', onTap: () => onKey('.')),
                  const SizedBox(width: 4),
                  _KeyButton(label: '_', onTap: () => onKey('_')),
                  const SizedBox(width: 4),
                  _KeyButton(label: '-', onTap: () => onKey('-')),
                  const SizedBox(width: 4),
                  _KeyButton(
                    label: ' ',
                    icon: Icons.space_bar,
                    onTap: () => onKey(' '),
                    flex: 2,
                  ),
                ],
              ),
            ),
          Row(
            children: [
              _KeyButton(
                icon: Icons.backspace_outlined,
                onTap: onBackspace,
              ),
              const SizedBox(width: 4),
              _KeyButton(icon: Icons.close, onTap: onClear),
              const SizedBox(width: 4),
              Expanded(
                child: _AccentToggleKey(
                  isActive: showAccents,
                  onTap: onToggleAccents,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final FocusNode? focusNode;

  const _KeyButton({
    this.label,
    this.icon,
    required this.onTap,
    this.flex = 1,
    this.focusNode,
  });

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: widget.flex,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _hasFocus = f),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 32,
            decoration: BoxDecoration(
              color: _hasFocus ? Colors.white : _kKeyColor,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _hasFocus ? _kAccent : Colors.transparent,
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: widget.icon != null
                ? Icon(
                    widget.icon,
                    size: 16,
                    color: _hasFocus ? Colors.black : Colors.white70,
                  )
                : Text(
                    widget.label ?? '',
                    style: TextStyle(
                      color: _hasFocus ? Colors.black : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AccentToggleKey extends StatefulWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _AccentToggleKey({
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_AccentToggleKey> createState() => _AccentToggleKeyState();
}

class _AccentToggleKeyState extends State<_AccentToggleKey> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          decoration: BoxDecoration(
            color: widget.isActive
                ? (_hasFocus ? _kAccent : _kAccent.withValues(alpha: 0.9))
                : (_hasFocus ? Colors.white : _kKeyColor),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _hasFocus
                  ? (widget.isActive ? Colors.white : _kAccent)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.isActive ? 'ABC' : 'ÁÉÍ',
            style: TextStyle(
              color: widget.isActive
                  ? Colors.white
                  : (_hasFocus ? Colors.black : Colors.white),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta encima de cada campo, marcada cuando ese campo es el activo.
class _FieldLabel extends StatelessWidget {
  final String text;
  final bool active;

  const _FieldLabel({required this.text, required this.active});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: active ? Colors.white : Colors.white54,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// Campo de texto estilizado para TV.
/// El borde blanco de foco se dibuja a partir del FocusNode del TextField,
/// SIN envolverlo en otro Focus. Captura flechas para navegar entre campos.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool obscure;
  final bool enabled;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;

  const _Field({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.obscure,
    required this.enabled,
    this.suffix,
    this.keyboardType,
    this.onArrowUp,
    this.onArrowDown,
    this.onArrowLeft,
    this.onArrowRight,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: focused ? Colors.white : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Focus(
            // Focus exterior SOLO para capturar flechas cuando el
            // TextField interno tiene el foco. No comparte el FocusNode
            // con el TextField, así que no hay conflicto.
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final k = event.logicalKey;
              if (k == LogicalKeyboardKey.arrowDown) {
                onArrowDown?.call();
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.arrowUp) {
                onArrowUp?.call();
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.arrowLeft) {
                onArrowLeft?.call();
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.arrowRight) {
                onArrowRight?.call();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscure,
              enabled: true,
              readOnly: !enabled,
              showCursor: enabled,
              keyboardType: keyboardType,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              cursorColor: _kAccent,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    const TextStyle(color: Colors.white30, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: suffix,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Wrapper para botones que necesitan reaccionar al OK del mando.
class _FocusAction extends StatelessWidget {
  final FocusNode focusNode;
  final VoidCallback? onActivate;
  final Widget child;

  const _FocusAction({
    required this.focusNode,
    required this.onActivate,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          onActivate?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: child,
          );
        },
      ),
    );
  }
}