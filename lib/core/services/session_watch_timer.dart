import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cuenta el tiempo de uso de la sesión. A las 4 horas muestra un aviso.
class SessionWatchTimer {
  SessionWatchTimer._();
  static final SessionWatchTimer instance = SessionWatchTimer._();

  static const Duration warnAfter = Duration(hours: 4);

  DateTime? _startedAt;
  Timer? _timer;
  bool _dialogShowing = false;
  BuildContext? _context;

  void start(BuildContext context) {
    _context = context;
    _startedAt ??= DateTime.now();
    _timer?.cancel();
    // Revisar cada minuto
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
    // Primera comprobación por si ya llevaba tiempo
    _check();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Duration get elapsed {
    if (_startedAt == null) return Duration.zero;
    return DateTime.now().difference(_startedAt!);
  }

  void _check() {
    if (_startedAt == null) return;
    if (elapsed < warnAfter) return;
    if (_dialogShowing) return;
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;
    _showWarning(ctx);
  }

  Future<void> _showWarning(BuildContext context) async {
    _dialogShowing = true;
    final hours = elapsed.inHours;
    final mins = elapsed.inMinutes % 60;
    final cont = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Descanso recomendado',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Llevas ${hours}h ${mins.toString().padLeft(2, '0')}min usando la app.\n'
          '¿Quieres seguir viendo contenido?',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Salir de la app'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar viendo',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    _dialogShowing = false;
    if (cont == true) {
      // Reinicia el contador otras 4 horas
      _startedAt = DateTime.now();
    } else if (cont == false) {
      SystemNavigator.pop();
    }
  }

  /// true si el usuario eligió continuar en el último diálogo (o aún no llegó a 4h)
  bool get shouldContinue => true;
}
