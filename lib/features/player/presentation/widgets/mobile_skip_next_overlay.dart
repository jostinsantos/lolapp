import 'dart:async';
import 'package:flutter/material.dart';

/// Botón "Omitir intro" / "Siguiente" estilo Nuvio (móvil).
/// Tras auto-hide el padre marca autoHidden y NO reabre desde el listener.
/// Solo reabre al mostrar controles.
class MobileSkipNextButton extends StatefulWidget {
  final bool visible;
  final bool controlsVisible;
  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onAutoHide;
  final int autoHideMs;
  final bool primary;

  const MobileSkipNextButton({
    super.key,
    required this.visible,
    required this.controlsVisible,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    required this.onAutoHide,
    this.autoHideMs = 15000,
    this.primary = false,
  });

  @override
  State<MobileSkipNextButton> createState() => _MobileSkipNextButtonState();
}

class _MobileSkipNextButtonState extends State<MobileSkipNextButton> {
  Timer? _timer;
  double _progress = 1.0;
  DateTime? _startedAt;
  bool _autoHideFired = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _startOrResume();
  }

  @override
  void didUpdateWidget(covariant MobileSkipNextButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _autoHideFired = false;
      _progress = 1.0;
      _startOrResume();
      return;
    }
    if (!widget.visible && oldWidget.visible) {
      _stop();
      return;
    }
    if (!widget.visible) return;
    if (widget.controlsVisible && !oldWidget.controlsVisible) {
      _pause();
    } else if (!widget.controlsVisible && oldWidget.controlsVisible) {
      _resume();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startOrResume() {
    _timer?.cancel();
    _startedAt = DateTime.now().subtract(
      Duration(milliseconds: ((1.0 - _progress) * widget.autoHideMs).round()),
    );
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !widget.visible) {
        _stop();
        return;
      }
      if (widget.controlsVisible) return;
      final started = _startedAt;
      if (started == null) return;
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final left = (widget.autoHideMs - elapsed).clamp(0, widget.autoHideMs);
      final p = left / widget.autoHideMs;
      if ((p - _progress).abs() > 0.008 || p <= 0) {
        setState(() => _progress = p);
      }
      if (elapsed >= widget.autoHideMs) {
        _stop();
        if (!_autoHideFired) {
          _autoHideFired = true;
          widget.onAutoHide();
        }
      }
    });
  }

  void _pause() {
    if (_startedAt == null) return;
    final elapsed = DateTime.now().difference(_startedAt!).inMilliseconds;
    final left = (widget.autoHideMs - elapsed).clamp(0, widget.autoHideMs);
    _progress = left / widget.autoHideMs;
    _startedAt = null;
  }

  void _resume() {
    if (!widget.visible || _startedAt != null || _autoHideFired) return;
    _startOrResume();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: widget.visible ? 1.0 : 0.85,
      duration: Duration(milliseconds: widget.visible ? 280 : 180),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1.0 : 0.0,
        duration: Duration(milliseconds: widget.visible ? 280 : 180),
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
              decoration: BoxDecoration(
                color: widget.primary
                    ? widget.accentColor
                    : const Color(0xE61E1E1E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.primary
                      ? widget.accentColor
                      : Colors.white.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(9),
                      bottomRight: Radius.circular(9),
                    ),
                    child: LinearProgressIndicator(
                      value: _progress.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(
                        widget.primary
                            ? Colors.white.withValues(alpha: 0.9)
                            : widget.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}