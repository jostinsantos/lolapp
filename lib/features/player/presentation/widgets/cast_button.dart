import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dart_cast/dart_cast.dart';

import 'cast_manager.dart';
import 'cast_screen.dart';

// =============================================================================
// Botón Cast – abre modal de dispositivos o controles si ya está conectado
// =============================================================================

class CastButton extends StatefulWidget {
  final String videoUrl;
  final Map<String, String> headers;
  final String title;
  final Color accentColor;
  final String? backdropUrl;
  final double? introStartSec;
  final double? introEndSec;
  final double? outroStartSec;
  final double? outroEndSec;
  final VoidCallback? onCastStarted;
  final VoidCallback? onCastStopped;

  /// Si true, al conectar navega a [CastScreen] en lugar de solo pausar el player.
  final bool openCastScreenOnConnect;

  const CastButton({
    super.key,
    required this.videoUrl,
    this.headers = const {},
    this.title = '',
    this.accentColor = const Color(0xFFFF6B00),
    this.backdropUrl,
    this.introStartSec,
    this.introEndSec,
    this.outroStartSec,
    this.outroEndSec,
    this.onCastStarted,
    this.onCastStopped,
    this.openCastScreenOnConnect = true,
  });

  @override
  State<CastButton> createState() => _CastButtonState();
}

class _CastButtonState extends State<CastButton> {
  bool _isConnecting = false;
  StreamSubscription? _connSub;

  bool get _isConnected => CastManager().isConnected;

  @override
  void initState() {
    super.initState();
    _connSub = CastManager().connectedStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    // NO desconectamos aquí: el Cast sigue vivo al salir del reproductor.
    super.dispose();
  }

  Future<void> _openCastModal() async {
    if (widget.videoUrl.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay video activo para castear'),
            backgroundColor: Color(0xFF1A1A1A),
          ),
        );
      }
      return;
    }

    if (_isConnected) {
      await _showConnectedModal();
      return;
    }

    await _showDeviceModal();
  }

  Future<void> _showDeviceModal() async {
    final nav = Navigator.of(context);

    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (ctx) => _CastDeviceDialog(
        accentColor: widget.accentColor,
        videoUrl: widget.videoUrl,
        headers: widget.headers,
        title: widget.title,
        backdropUrl: widget.backdropUrl ?? '',
        introStartSec: widget.introStartSec,
        introEndSec: widget.introEndSec,
        outroStartSec: widget.outroStartSec,
        outroEndSec: widget.outroEndSec,
        onConnected: (service, session) async {
          // Registrar sesión en CastManager
          await CastManager().connect(
            service: service,
            session: session,
            title: widget.title,
            videoUrl: widget.videoUrl,
            headers: widget.headers,
            backdropUrl: widget.backdropUrl ?? '',
            introStart: widget.introStartSec,
            introEnd: widget.introEndSec,
            outroStart: widget.outroStartSec,
            outroEnd: widget.outroEndSec,
          );
        },
        onError: (msg) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: Colors.red[800],
              ),
            );
          }
        },
      ),
    );

    // result == true → se conectó y el dialog ya se cerró solo
    if (result == true && mounted) {
      if (mounted) setState(() {}); // actualiza icono a "conectado"
      widget.onCastStarted?.call();

      if (widget.openCastScreenOnConnect) {
        // REEMPLAZAR el player por CastScreen (sin volver al player al atrás)
        await nav.pushReplacement(
          MaterialPageRoute(
            builder: (_) => CastScreen(
              title: widget.title,
              backdropUrl: widget.backdropUrl,
              accentColor: widget.accentColor,
            ),
          ),
        );
      }
    }
  }

  Future<void> _showConnectedModal() async {
    final session = CastManager().session;
    if (session == null) return;

    // Opción A: ir directo a la pantalla de Cast (reemplaza el player)
    if (widget.openCastScreenOnConnect) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CastScreen(
            title: widget.title.isNotEmpty
                ? widget.title
                : CastManager().currentTitle,
            backdropUrl: widget.backdropUrl ?? CastManager().backdropUrl,
            accentColor: widget.accentColor,
          ),
        ),
      );
      if (mounted) setState(() {});
      return;
    }

    // Opción B: modal compacto de controles
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _CastControlsDialog(
        session: session,
        accentColor: widget.accentColor,
        title: widget.title.isNotEmpty
            ? widget.title
            : CastManager().currentTitle,
        onDisconnect: () async {
          await CastManager().disconnect();
          if (mounted) setState(() {});
          widget.onCastStopped?.call();
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onOpenFullScreen: () {
          Navigator.pop(ctx);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CastScreen(
                title: widget.title.isNotEmpty
                    ? widget.title
                    : CastManager().currentTitle,
                backdropUrl:
                    widget.backdropUrl ?? CastManager().backdropUrl,
                accentColor: widget.accentColor,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isConnecting ? null : _openCastModal,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isConnected
                ? widget.accentColor.withValues(alpha: 0.18)
                : Colors.transparent,
          ),
          child: Icon(
            _isConnected
                ? Icons.cast_connected_rounded
                : Icons.cast_rounded,
            color: _isConnected ? widget.accentColor : Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Modal: lista de dispositivos
// =============================================================================

class _CastDeviceDialog extends StatefulWidget {
  final Color accentColor;
  final String videoUrl;
  final Map<String, String> headers;
  final String title;
  final String backdropUrl;
  final double? introStartSec;
  final double? introEndSec;
  final double? outroStartSec;
  final double? outroEndSec;
  final Future<void> Function(CastService service, CastSession session)
      onConnected;
  final void Function(String message) onError;

  const _CastDeviceDialog({
    required this.accentColor,
    required this.videoUrl,
    required this.headers,
    required this.title,
    required this.backdropUrl,
    this.introStartSec,
    this.introEndSec,
    this.outroStartSec,
    this.outroEndSec,
    required this.onConnected,
    required this.onError,
  });

  @override
  State<_CastDeviceDialog> createState() => _CastDeviceDialogState();
}

class _CastDeviceDialogState extends State<_CastDeviceDialog> {
  late final CastService _castService;
  List<CastDevice> _devices = [];
  bool _discovering = true;
  String? _connectingId;
  StreamSubscription? _discoverySub;

  @override
  void initState() {
    super.initState();
    _castService = CastService(
      discoveryProviders: [
        ChromecastDiscoveryProvider(),
      ],
      sessionFactory: (device) {
        switch (device.protocol) {
          case CastProtocol.chromecast:
            return ChromecastSession(device: device);
          default:
            throw UnsupportedError(
              'Protocolo no soportado: ${device.protocol}',
            );
        }
      },
    );
    _startDiscovery();
  }

  void _startDiscovery() {
    setState(() {
      _discovering = true;
      _devices = [];
      _connectingId = null;
    });
    _discoverySub?.cancel();
    _discoverySub = _castService.startDiscovery().listen(
      (devices) {
        if (!mounted) return;
        setState(() {
          _devices = devices;
          _discovering = false;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _discovering = false);
        widget.onError('Error buscando dispositivos: $e');
      },
    );

    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && _discovering) {
        setState(() => _discovering = false);
      }
    });
  }

  Future<void> _connectAndCast(CastDevice device) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = device.id);

    try {
      final session = await _castService.connect(device);

      final mediaType = widget.videoUrl.toLowerCase().contains('.m3u8')
          ? CastMediaType.hls
          : CastMediaType.mp4;

      await session.loadMedia(CastMedia(
        url: widget.videoUrl,
        type: mediaType,
        title: widget.title.isNotEmpty ? widget.title : 'Video',
        httpHeaders: widget.headers,
      ));

      if (!mounted) return;

      // Guardar sesión en CastManager
      await widget.onConnected(_castService, session);

      if (!mounted) return;
      // Cerrar dialog con true → el botón Cast abre CastScreen solo
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _connectingId = null);
        widget.onError('No se pudo conectar: $e');
      }
    }
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    // NO dispose del CastService: lo gestiona CastManager
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.72;

    return Dialog(
      backgroundColor: const Color(0xFF141418),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.cast_rounded,
                      color: widget.accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transmitir a TV',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Misma red Wi-Fi que el Chromecast',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_discovering)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: widget.accentColor,
                        ),
                      ),
                    )
                  else
                    IconButton(
                      onPressed: _startDiscovery,
                      tooltip: 'Buscar de nuevo',
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            Flexible(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_discovering && _devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: widget.accentColor,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Buscando dispositivos...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (!_discovering && _devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.tv_off_rounded,
                color: Colors.grey[600],
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No se encontraron dispositivos',
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Asegurate de estar en la misma red Wi-Fi\nque tu TV o Chromecast',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _startDiscovery,
              icon: Icon(Icons.refresh_rounded, color: widget.accentColor),
              label: Text(
                'Buscar de nuevo',
                style: TextStyle(
                  color: widget.accentColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final device = _devices[index];
        final isConnecting = _connectingId == device.id;
        final busy = _connectingId != null;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? null : () => _connectAndCast(device),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: isConnecting
                    ? widget.accentColor.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isConnecting
                      ? widget.accentColor.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isConnecting
                          ? widget.accentColor.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.tv_rounded,
                      color: isConnecting
                          ? widget.accentColor
                          : Colors.white70,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      device.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isConnecting)
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: widget.accentColor,
                      ),
                    )
                  else
                    Icon(
                      Icons.cast_rounded,
                      color: widget.accentColor.withValues(alpha: 0.9),
                      size: 22,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Modal compacto de controles (alternativa a CastScreen)
// =============================================================================

class _CastControlsDialog extends StatefulWidget {
  final CastSession session;
  final Color accentColor;
  final String title;
  final VoidCallback onDisconnect;
  final VoidCallback? onOpenFullScreen;

  const _CastControlsDialog({
    required this.session,
    required this.accentColor,
    required this.title,
    required this.onDisconnect,
    this.onOpenFullScreen,
  });

  @override
  State<_CastControlsDialog> createState() => _CastControlsDialogState();
}

class _CastControlsDialogState extends State<_CastControlsDialog> {
  bool _isPlaying = true;
  Duration _position = Duration.zero;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;

  @override
  void initState() {
    super.initState();
    _isPlaying = CastManager().isPlaying;
    _position = CastManager().position;

    _stateSub = CastManager().playingStream.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
    });
    _posSub = CastManager().positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    await CastManager().togglePlay();
  }

  Future<void> _seekRelative(int seconds) async {
    await CastManager().seekRelative(seconds);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141418),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.cast_connected_rounded,
                      color: widget.accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title.isNotEmpty
                              ? widget.title
                              : 'Reproduciendo en TV',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'En TV · ${_fmt(_position)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                      size: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ctrlBtn(
                    icon: Icons.replay_10_rounded,
                    label: '-10s',
                    onTap: () => _seekRelative(-10),
                  ),
                  _ctrlBtn(
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    label: _isPlaying ? 'Pausa' : 'Play',
                    filled: true,
                    onTap: _togglePlay,
                  ),
                  _ctrlBtn(
                    icon: Icons.forward_10_rounded,
                    label: '+10s',
                    onTap: () => _seekRelative(10),
                  ),
                ],
              ),
              if (widget.onOpenFullScreen != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: widget.onOpenFullScreen,
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    color: widget.accentColor,
                    size: 18,
                  ),
                  label: Text(
                    'Abrir pantalla de transmisión',
                    style: TextStyle(
                      color: widget.accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onDisconnect,
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: const Text('Detener y desconectar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.7),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ctrlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? widget.accentColor.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.08),
                  border: filled
                      ? Border.all(
                          color: widget.accentColor.withValues(alpha: 0.5),
                        )
                      : null,
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}