// ============================================================
// tv_text_input_dialog.dart
// Modal de entrada de texto con teclado en pantalla propio.
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _kAccent = Color(0xFFE50914);
const _kKeyColor = Color(0xFF2A2A38);

class TvTextInputDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String initialText;
  final bool numericOnly;
  final bool obscure;
  final int maxLength;

  const TvTextInputDialog({
    super.key,
    required this.title,
    this.hint,
    this.initialText = '',
    this.numericOnly = false,
    this.obscure = false,
    this.maxLength = 60,
  });

  @override
  State<TvTextInputDialog> createState() => _TvTextInputDialogState();
}

class _TvTextInputDialogState extends State<TvTextInputDialog> {
  late String _text;
  bool _showAccents = false;

  static const _rowsNormal = [
    ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
    ['h', 'i', 'j', 'k', 'l', 'm', 'n'],
    ['o', 'p', 'q', 'r', 's', 't', 'u'],
    ['v', 'w', 'x', 'y', 'z', 'ñ', '.'],
  ];

  static const _rowsNumeric = [
    ['1', '2', '3', '4', '5', '6', '7'],
    ['8', '9', '0', '-', '_', '.', '@'],
  ];

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
  }

  void _append(String c) {
    if (_text.length >= widget.maxLength) return;
    setState(() => _text += c);
  }

  void _backspace() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.substring(0, _text.length - 1));
  }

  void _clear() {
    setState(() => _text = '');
  }

  void _submit() {
    Navigator.pop(context, _text);
  }

  String get _display {
    if (widget.obscure) return '•' * _text.length;
    return _text;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.numericOnly ? _rowsNumeric : _rowsNormal;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: Container(
        width: widget.numericOnly ? 380 : 620,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            // Display
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24, width: 1.2),
              ),
              child: Text(
                _display.isEmpty ? (widget.hint ?? '') : _display,
                style: TextStyle(
                  color: _display.isEmpty ? Colors.white38 : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Teclado
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final c in row)
                          _Key(
                            label: c,
                            onTap: () => _append(c),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!widget.numericOnly)
                      _Key(
                        label: ' ',
                        icon: Icons.space_bar,
                        flex: 3,
                        onTap: () => _append(' '),
                      ),
                    if (!widget.numericOnly)
                      _Key(
                        label: '@',
                        onTap: () => _append('@'),
                      ),
                    _Key(
                      label: '⌫',
                      icon: Icons.backspace_outlined,
                      flex: 2,
                      onTap: _backspace,
                    ),
                    _Key(
                      label: 'Limpiar',
                      text: true,
                      flex: 2,
                      onTap: _clear,
                    ),
                    _Key(
                      label: 'OK',
                      primary: true,
                      flex: 2,
                      onTap: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final bool primary;
  final bool text;

  const _Key({
    required this.label,
    this.icon,
    required this.onTap,
    this.flex = 1,
    this.primary = false,
    this.text = false,
  });

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bg = _focused
        ? Colors.white
        : (widget.primary ? _kAccent : _kKeyColor);
    final fg = _focused
        ? Colors.black
        : (widget.primary ? Colors.white : Colors.white);

    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _focused ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: widget.icon != null
                  ? Icon(widget.icon, size: 16, color: fg)
                  : Text(
                      widget.label,
                      style: TextStyle(
                        color: fg,
                        fontSize: widget.text ? 12 : 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}