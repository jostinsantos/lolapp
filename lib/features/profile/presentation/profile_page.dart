import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../supabase/supabase_config.dart';
import 'profile_selection_page.dart';

const _kAccentColor = Color(0xFFE50914);
const _kBgColor = Colors.black;

class PerfilPage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const PerfilPage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<PerfilPage> createState() => PerfilPageState();
}

class PerfilPageState extends State<PerfilPage>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;

  int _totalSeconds = 0;
  int _moviesWatched = 0;
  int _episodesWatched = 0;
  int _sessionsCount = 0;

  String _deviceOs = '';
  String _deviceVersion = '';
  String _screenInfo = '';

  bool _supabaseActive = false;
  String? _supabaseUserName;

  // 0-2 stats, 3 dispositivo — fijos, nunca se recrean
  late final List<FocusNode> _nodes;
  bool _reportedMainNode = false;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _statsKey = GlobalKey();
  final GlobalKey _deviceKey = GlobalKey();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _nodes = List.generate(4, (i) => FocusNode(debugLabel: 'perfil_$i'));
    _load();
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void refresh() => _load();

  Future<void> _load() async {
    final isFirst = _loading;
    if (isFirst) setState(() => _loading = true);

    final stats = await _loadStats();
    if (!mounted) return;
    final device = _readDeviceInfo();

    final supabaseActive = await SupabaseConfig.isSupabaseActive();
    final supabaseName = await SupabaseConfig.getCurrentUserName();

    if (!mounted) return;
    setState(() {
      _totalSeconds = stats.totalSeconds;
      _moviesWatched = stats.movies;
      _episodesWatched = stats.episodes;
      _sessionsCount = stats.sessions;
      _deviceOs = device.os;
      _deviceVersion = device.version;
      _screenInfo = device.screen;
      _supabaseActive = supabaseActive;
      _supabaseUserName = supabaseName;
      _loading = false;
    });

    if (!_reportedMainNode) {
      _reportedMainNode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onMainFocusNodeCreated?.call(_nodes[0]);
      });
    }
  }

  Future<_WatchStats> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((k) => k.startsWith('cachePlayer_')).toList();

    int totalSeconds = 0;
    int movies = 0;
    int episodes = 0;
    int sessions = 0;

    for (final key in keys) {
      try {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final data = Map<String, dynamic>.from(jsonDecode(raw));
        final segundo = data['segundo'] as int? ?? 0;
        if (segundo < 8) continue;

        totalSeconds += segundo;
        sessions++;
        final tipo = (data['tipo']?.toString() ?? 'movie').toLowerCase();
        if (tipo == 'tv') {
          episodes++;
        } else {
          movies++;
        }
      } catch (_) {}
    }

    return _WatchStats(
      totalSeconds: totalSeconds,
      movies: movies,
      episodes: episodes,
      sessions: sessions,
    );
  }

  _DeviceInfo _readDeviceInfo() {
    String os;
    String version;
    if (kIsWeb) {
      os = 'Web';
      version = 'Browser';
    } else {
      try {
        os = Platform.operatingSystem;
        version = Platform.operatingSystemVersion;
      } catch (_) {
        os = 'Desconocido';
        version = '—';
      }
    }
    if (os.isNotEmpty) {
      os = '${os[0].toUpperCase()}${os.substring(1)}';
    }
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screen =
        '${size.width.toInt()} × ${size.height.toInt()}  ·  dpr ${dpr.toStringAsFixed(1)}';
    return _DeviceInfo(os: os, version: version, screen: screen);
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0h 00m';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }

  void _ensureVisible(GlobalKey key, {double alignment = 0.15}) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: alignment,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _move(int index, int dx, int dy) {
    int next = index;

    if (dy < 0) {
      // ↑ desde dispositivo → vuelve a stats
      if (index == 3) {
        next = 0;
      } else {
        // ↑ desde stats → menú superior
        widget.onRequestMenuFocus?.call();
        return;
      }
    } else if (dx != 0 && index <= 2) {
      next = (index + dx).clamp(0, 2);
    } else if (dy > 0 && index <= 2) {
      next = 3;
    } else if (dy > 0 && index == 3) {
      return;
    }

    if (next == index) return;

    _nodes[next].requestFocus();

    // La cámara sigue el foco: stats debajo del menú fijo, device más abajo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next <= 2) {
        // Alinea la sección de actividad bajo el menú (no la tapa)
        _ensureVisible(_statsKey, alignment: 0.12);
      } else {
        _ensureVisible(_deviceKey, alignment: 0.25);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Scaffold(
        backgroundColor: _kBgColor,
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 80)),

            if (_supabaseActive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a1a2e),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kAccentColor.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cloud_done_rounded,
                                  color: _kAccentColor, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Supabase activo',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _supabaseUserName ?? 'Perfil',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ProfileSelectionPage(
                                        allowDismiss: true,
                                        onProfileSelected: () {
                                          Navigator.of(context).pop();
                                          refresh();
                                        },
                                      ),
                                    ),
                                  );
                                  refresh();
                                },
                                child: const Text(
                                  'Cambiar perfil',
                                  style: TextStyle(color: _kAccentColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            SliverToBoxAdapter(
              key: _statsKey,
              child: const _SectionLabel(
                title: 'Actividad de visionado',
                icon: Icons.play_circle_outline_rounded,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        focusNode: _nodes[0],
                        icon: Icons.schedule_rounded,
                        label: 'Tiempo total',
                        value: _formatDuration(_totalSeconds),
                        subtitle: _sessionsCount > 0
                            ? '$_sessionsCount sesiones'
                            : 'Sin sesiones',
                        onArrow: (dx, dy) => _move(0, dx, dy),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _StatCard(
                        focusNode: _nodes[1],
                        icon: Icons.movie_rounded,
                        label: 'Películas',
                        value: '$_moviesWatched',
                        subtitle: _moviesWatched == 1 ? 'vista' : 'vistas',
                        onArrow: (dx, dy) => _move(1, dx, dy),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _StatCard(
                        focusNode: _nodes[2],
                        icon: Icons.tv_rounded,
                        label: 'Capítulos',
                        value: '$_episodesWatched',
                        subtitle: _episodesWatched == 1 ? 'visto' : 'vistos',
                        onArrow: (dx, dy) => _move(2, dx, dy),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: _SectionLabel(
                title: 'Este dispositivo',
                icon: Icons.devices_rounded,
              ),
            ),
            SliverToBoxAdapter(
              key: _deviceKey,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 24),
                child: _DeviceCard(
                  focusNode: _nodes[3],
                  os: _deviceOs,
                  version: _deviceVersion,
                  screen: _screenInfo,
                  onArrow: (dx, dy) => _move(3, dx, dy),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }
}

class _WatchStats {
  final int totalSeconds;
  final int movies;
  final int episodes;
  final int sessions;
  const _WatchStats({
    required this.totalSeconds,
    required this.movies,
    required this.episodes,
    required this.sessions,
  });
}

class _DeviceInfo {
  final String os;
  final String version;
  final String screen;
  const _DeviceInfo({
    required this.os,
    required this.version,
    required this.screen,
  });
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionLabel({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 12),
      child: Row(
        children: [
          Icon(icon, color: _kAccentColor, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Foco = solo borde blanco + glow suave (como posters Home/Movie). Sin cambiar fondo.
class _StatCard extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final void Function(int dx, int dy) onArrow;

  const _StatCard({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.onArrow,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onArrow(0, -1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onArrow(0, 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onArrow(-1, 0);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onArrow(1, 0);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 140,
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasFocus ? Colors.white : Colors.transparent,
                width: 2.2,
              ),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.18),
                        blurRadius: 10,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white54, size: 22),
                const Spacer(),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final FocusNode focusNode;
  final String os;
  final String version;
  final String screen;
  final void Function(int dx, int dy) onArrow;

  const _DeviceCard({
    required this.focusNode,
    required this.os,
    required this.version,
    required this.screen,
    required this.onArrow,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onArrow(0, -1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onArrow(0, 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onArrow(-1, 0);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onArrow(1, 0);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasFocus ? Colors.white : Colors.transparent,
                width: 2.2,
              ),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.18),
                        blurRadius: 10,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.tv_rounded,
                    color: Colors.white54,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        os,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        version,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        screen,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}