import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../content/presentation/tv_content_page.dart';
import '../../player/presentation/tv/tv_player_page.dart';
import '../../content/presentation/tv_content_options_modal.dart';
import '../../../supabase/supabase_data.dart';

const _kAccentColor = Color(0xFFFF6B00);
const _kBg = Color(0xFF0A0A0A);
const _kSurface = Color(0xFF161618);
const _kBorder = Color(0xFF26262A);

/// Resuelve path relativo de TMDB o URL ya completa.
String resolveTmdbImage(dynamic value, {String size = 'w500'}) {
  if (value == null) return '';
  String s = value.toString().trim();
  if (s.isEmpty || s == 'null' || s == 'undefined') return '';

  if (s.startsWith('http://') || s.startsWith('https://')) {
    return s.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');
  }

  final match = RegExp(r'https?:\\?/\\?/[^\s,"\]\\]+').firstMatch(s);
  if (match != null) {
    return match.group(0)!.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');
  }

  if (s.startsWith('[')) {
    try {
      final cleaned =
          s.replaceAll(r'\/', '/').replaceAll("'", '"').replaceAll('""', '"');
      final list = jsonDecode(cleaned);
      if (list is List && list.isNotEmpty) {
        return resolveTmdbImage(list.first, size: size);
      }
    } catch (_) {}
    return '';
  }

  final path = s.startsWith('/') ? s : '/$s';
  return 'https://image.tmdb.org/t/p/$size$path';
}

/// Normaliza tipo a 'tv' o 'movie'
String normalizeMediaType(dynamic raw) {
  final t = (raw ?? '').toString().toLowerCase().trim();
  if (t == 'tv' || t == 'serie' || t == 'series' || t == 'show') return 'tv';
  return 'movie';
}

String mediaTypeLabel(dynamic raw) {
  return normalizeMediaType(raw) == 'tv' ? 'Serie' : 'Película';
}

String posterFromItem(Map<String, dynamic> item, {String size = 'w500'}) {
  final candidates = [
    item['poster'],
    item['poster_path'],
    item['posterUrl'],
    item['backdrop'],
    item['backdrop_path'],
    item['backdropUrl'],
  ];
  for (final c in candidates) {
    final url = resolveTmdbImage(c, size: size);
    if (url.isNotEmpty) return url;
  }
  return '';
}

String backdropFromItem(Map<String, dynamic> item) {
  final candidates = [
    item['backdrop'],
    item['backdrop_path'],
    item['backdropUrl'],
    item['poster'],
    item['poster_path'],
    item['posterUrl'],
  ];
  for (final c in candidates) {
    final url = resolveTmdbImage(c, size: 'w780');
    if (url.isNotEmpty) return url;
  }
  return '';
}

class GuardadosPage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const GuardadosPage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<GuardadosPage> createState() => GuardadosPageState();
}

class GuardadosPageState extends State<GuardadosPage>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _historial = [];
  List<Map<String, dynamic>> _guardados = [];
  bool _loading = true;

  final List<FocusNode> _historialNodes = [];
  final List<FocusNode> _guardadosNodes = [];

  final FocusNode _rootFocus = FocusNode(debugLabel: 'guardados_root');

  final ScrollController _mainScroll = ScrollController();
  final ScrollController _historialScroll = ScrollController();
  final ScrollController _guardadosScroll = ScrollController();

  final GlobalKey _historialSectionKey = GlobalKey();
  final GlobalKey _guardadosSectionKey = GlobalKey();

  int _lastHistIndex = 0;
  int _lastGuardIndex = 0;

  bool _ignoreSelectUntil = false;
  Timer? _ignoreSelectTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    GuardadosBus.version.addListener(_onExternalChange);
    HistorialBus.version.addListener(_onExternalChange);
    _load();
  }

  void _onExternalChange() {
    if (!mounted) return;
    _load(silent: true);
  }

  @override
  void dispose() {
    _ignoreSelectTimer?.cancel();
    GuardadosBus.version.removeListener(_onExternalChange);
    HistorialBus.version.removeListener(_onExternalChange);
    for (final n in _historialNodes) {
      n.dispose();
    }
    for (final n in _guardadosNodes) {
      n.dispose();
    }
    _rootFocus.dispose();
    _mainScroll.dispose();
    _historialScroll.dispose();
    _guardadosScroll.dispose();
    super.dispose();
  }

  void refresh() => _load(silent: true);

  void _armIgnoreSelect({int ms = 400}) {
    _ignoreSelectUntil = true;
    _ignoreSelectTimer?.cancel();
    _ignoreSelectTimer = Timer(Duration(milliseconds: ms), () {
      _ignoreSelectUntil = false;
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);

    final historial = await _loadHistorial();
    final guardados = await GuardadosCache.getAll();

    if (!mounted) return;

    for (final n in _historialNodes) {
      n.dispose();
    }
    for (final n in _guardadosNodes) {
      n.dispose();
    }
    _historialNodes.clear();
    _guardadosNodes.clear();

    _historialNodes.addAll(
      List.generate(historial.length, (i) => FocusNode(debugLabel: 'hist_$i')),
    );
    _guardadosNodes.addAll(
      List.generate(guardados.length, (i) => FocusNode(debugLabel: 'guard_$i')),
    );

    if (_historialNodes.isNotEmpty) {
      _lastHistIndex = _lastHistIndex.clamp(0, _historialNodes.length - 1);
    } else {
      _lastHistIndex = 0;
    }
    if (_guardadosNodes.isNotEmpty) {
      _lastGuardIndex = _lastGuardIndex.clamp(0, _guardadosNodes.length - 1);
    } else {
      _lastGuardIndex = 0;
    }

    setState(() {
      _historial = historial;
      _guardados = guardados;
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onMainFocusNodeCreated?.call(_rootFocus);

      if (!silent) {
        _focusFirstContentItem();
      }
    });
  }

  void _focusFirstContentItem() {
    _armIgnoreSelect();

    if (_historialNodes.isNotEmpty) {
      final i = _lastHistIndex.clamp(0, _historialNodes.length - 1);
      _historialNodes[i].requestFocus();
      _scrollHorizontal(_historialScroll, i, 280);
      _ensureSectionVisible(_historialSectionKey);
    } else if (_guardadosNodes.isNotEmpty) {
      final i = _lastGuardIndex.clamp(0, _guardadosNodes.length - 1);
      _guardadosNodes[i].requestFocus();
      _scrollHorizontal(_guardadosScroll, i, 145);
      _ensureSectionVisible(_guardadosSectionKey);
    } else {
      _rootFocus.requestFocus();
    }
  }

  /// Historial desde Supabase (logueado) o cache local (invitado).
  Future<List<Map<String, dynamic>>> _loadHistorial() async {
    try {
      final list = await SupabaseData.getHistorial();
      final result = <Map<String, dynamic>>[];

      for (final raw in list) {
        final data = Map<String, dynamic>.from(raw);
        final tmdbId = data['tmdb_id'] ?? data['idcontenido'] ?? 0;
        final id = tmdbId is int ? tmdbId : int.tryParse('$tmdbId') ?? 0;
        if (id <= 0) continue;

        final segundo = data['progress_seconds'] as int? ??
            data['segundo'] as int? ??
            0;
        if (segundo < 5) continue;

        final tipo = (data['tipo'] ?? 'movie').toString().toLowerCase();
        final isTv = tipo.contains('tv') || tipo.contains('serie');
        int? season = data['season'] is int
            ? data['season'] as int
            : int.tryParse('${data['season'] ?? data['temporada'] ?? ''}');
        int? episode = data['episode'] is int
            ? data['episode'] as int
            : int.tryParse('${data['episode'] ?? data['capitulo'] ?? ''}');
        if (!isTv || season == 0) season = null;
        if (!isTv || episode == 0) episode = null;

        // Poster: URL completa de Supabase o path relativo → full URL
        String poster = '';
        for (final key in [
          'poster',
          'poster_path',
          'posterUrl',
          'backdrop',
          'backdrop_path',
        ]) {
          final v = data[key]?.toString() ?? '';
          if (v.isEmpty) continue;
          if (v.startsWith('http://') || v.startsWith('https://')) {
            poster = v;
            break;
          }
          if (v.startsWith('/')) {
            poster = 'https://image.tmdb.org/t/p/w500$v';
            break;
          }
          if (v.contains('.') && !v.contains(' ')) {
            poster =
                'https://image.tmdb.org/t/p/w500/${v.startsWith('/') ? v.substring(1) : v}';
            break;
          }
        }

        result.add({
          ...data,
          'idcontenido': id,
          'tmdb_id': id,
          'segundo': segundo,
          'progress_seconds': segundo,
          'temporada': season,
          'capitulo': episode,
          'tipo': tipo,
          'titulo': data['titulo']?.toString() ??
              data['title']?.toString() ??
              '',
          'poster': poster,
          'backdrop': data['backdrop']?.toString() ?? poster,
          'duration': data['duration_seconds'] ?? data['duration'],
          'timestamp': data['updated_at']?.toString() ??
              data['created_at']?.toString() ??
              data['timestamp']?.toString() ??
              '',
        });
      }

      result.sort((a, b) {
        final ta = a['timestamp']?.toString() ?? '';
        final tb = b['timestamp']?.toString() ?? '';
        return tb.compareTo(ta);
      });
      return result;
    } catch (e) {
      debugPrint('[GuardadosTV] _loadHistorial error: $e');
      return [];
    }
  }

  void _openHistorial(Map<String, dynamic> item) {
    if (_ignoreSelectUntil) return;

    final rawId = item['idcontenido'] ?? item['tmdb_id'] ?? 0;
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    if (id <= 0) return;

    final temporada = item['temporada'] is int
        ? item['temporada'] as int
        : int.tryParse('${item['temporada'] ?? ''}');
    final capitulo = item['capitulo'] is int
        ? item['capitulo'] as int
        : int.tryParse('${item['capitulo'] ?? ''}');
    final tmdbId = item['tmdb_id'] is int
        ? item['tmdb_id'] as int
        : int.tryParse('${item['tmdb_id'] ?? id}') ?? id;
    final tipo = normalizeMediaType(
      item['tipo'] ?? item['media_type'] ?? item['type'],
    );
    final titulo =
        item['titulo']?.toString() ?? item['title']?.toString() ?? 'Sin título';
    final videoUrl = item['videoUrl']?.toString() ?? '';

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              videoUrl: videoUrl,
              idcontenido: id,
              tmdbId: tmdbId,
              temporada: temporada,
              capitulo: capitulo,
              tipo: tipo,
              titulo: titulo,
              servidorUrl: item['servidorUrl']?.toString(),
              servidorNombre: item['servidorNombre']?.toString(),
              idioma: item['idioma']?.toString(),
              idServidor: item['idServidor'] as int?,
              fuentesServidor: item['fuentesServidor']?.toString(),
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            _armIgnoreSelect(ms: 500);
            _load(silent: true);
            HistorialBus.bump();
          }
        });
  }

  void _openGuardado(Map<String, dynamic> item) {
    if (_ignoreSelectUntil) return;

    final id = item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;

    final tmdbId = item['tmdb_id'] as int? ?? id;
    final mediaType = normalizeMediaType(
      item['media_type'] ?? item['type'] ?? item['tipo'],
    );

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PageContenido(
              idcontenido: id,
              tmdbId: tmdbId,
              mediaType: mediaType,
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            _armIgnoreSelect(ms: 500);
            _load(silent: true);
          }
        });
  }

  void _openOpcionesFromHistorial(Map<String, dynamic> item) {
    if (_ignoreSelectUntil) return;

    final id = item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;
    final tmdbId = item['tmdb_id'] as int? ?? id;
    final tipo = normalizeMediaType(
      item['tipo'] ?? item['media_type'] ?? item['type'],
    );

    showContenidoOpcionesModal(
      context,
      tmdbId: tmdbId,
      tipo: tipo,
      idcontenido: id,
      titulo: item['titulo']?.toString() ?? item['title']?.toString(),
      posterUrl: posterFromItem(item),
      backdropUrl: backdropFromItem(item),
      logoUrl: item['logo']?.toString() ?? item['logo_path']?.toString(),
    ).then((_) {
      if (mounted) {
        _armIgnoreSelect(ms: 400);
        _load(silent: true);
      }
    });
  }

  void _openOpcionesFromGuardado(Map<String, dynamic> item) {
    if (_ignoreSelectUntil) return;

    final id = item['idcontenido'] as int? ?? 0;
    if (id <= 0) return;
    final tmdbId = item['tmdb_id'] as int? ?? id;
    final tipo = normalizeMediaType(
      item['media_type'] ?? item['type'] ?? item['tipo'],
    );

    showContenidoOpcionesModal(
      context,
      tmdbId: tmdbId,
      tipo: tipo,
      idcontenido: id,
      titulo: item['title']?.toString() ?? item['titulo']?.toString(),
      posterUrl: posterFromItem(item),
      backdropUrl: backdropFromItem(item),
    ).then((_) {
      if (mounted) {
        _armIgnoreSelect(ms: 400);
        _load(silent: true);
      }
    });
  }

  void _goMenu() {
    widget.onRequestMenuFocus?.call();
  }

  void _ensureSectionVisible(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.12,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _scrollHorizontal(ScrollController c, int index, double itemWidth) {
    if (!c.hasClients) return;
    final offset = (index * (itemWidth + 14)) -
        (MediaQuery.sizeOf(context).width / 2) +
        (itemWidth / 2);
    c.animateTo(
      offset.clamp(0.0, c.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _moveFocus(int section, int index, int dx, int dy) {
    // ── Flecha izquierda en el primer item de cualquier sección → menú ──
    if (dx < 0 && index <= 0) {
      _goMenu();
      return;
    }

    // ── Flecha arriba ───────────────────────────────────────────────────
    if (dy < 0) {
      if (section == 0) {
        // Ya estamos en la fila superior → ir al menú
        _goMenu();
        return;
      }
      if (section == 1) {
        // Si hay historial subir a historial; si no, ir al menú
        if (_historialNodes.isNotEmpty) {
          final i = _lastHistIndex.clamp(0, _historialNodes.length - 1);
          _armIgnoreSelect(ms: 200);
          _historialNodes[i].requestFocus();
          _scrollHorizontal(_historialScroll, i, 280);
          _ensureSectionVisible(_historialSectionKey);
        } else {
          _goMenu();
        }
        return;
      }
    }

    // ── Sección 0: Continuar viendo ─────────────────────────────────────
    if (section == 0) {
      final nodes = _historialNodes;

      if (dy > 0) {
        if (_guardadosNodes.isNotEmpty) {
          final i = _lastGuardIndex.clamp(0, _guardadosNodes.length - 1);
          _armIgnoreSelect(ms: 200);
          _guardadosNodes[i].requestFocus();
          _scrollHorizontal(_guardadosScroll, i, 145);
          _ensureSectionVisible(_guardadosSectionKey);
        } else {
          _goMenu();
        }
        return;
      }

      if (nodes.isEmpty) return;
      final newIndex = (index + dx).clamp(0, nodes.length - 1);
      if (newIndex != index) {
        _lastHistIndex = newIndex;
        _armIgnoreSelect(ms: 150);
        nodes[newIndex].requestFocus();
        _scrollHorizontal(_historialScroll, newIndex, 280);
        _ensureSectionVisible(_historialSectionKey);
      }
      return;
    }

    // ── Sección 1: Mi lista ─────────────────────────────────────────────
    if (section == 1) {
      final nodes = _guardadosNodes;

      if (dy > 0) {
        // No hay nada más abajo → al menú
        _goMenu();
        return;
      }

      if (nodes.isEmpty) return;
      final newIndex = (index + dx).clamp(0, nodes.length - 1);
      if (newIndex != index) {
        _lastGuardIndex = newIndex;
        _armIgnoreSelect(ms: 150);
        nodes[newIndex].requestFocus();
        _scrollHorizontal(_guardadosScroll, newIndex, 145);
        _ensureSectionVisible(_guardadosSectionKey);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Focus(
      focusNode: _rootFocus,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _goMenu();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          _focusFirstContentItem();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      onFocusChange: (has) {
        if (!has) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_rootFocus.hasFocus) return;

          final anyItem = _historialNodes.any((n) => n.hasFocus) ||
              _guardadosNodes.any((n) => n.hasFocus);
          if (!anyItem) {
            _focusFirstContentItem();
          }
        });
      },
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _kAccentColor),
                )
              : CustomScrollView(
                  controller: _mainScroll,
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),

                    if (_historial.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        key: _historialSectionKey,
                        child: _SectionHeader(
                          title: 'Continuar viendo',
                          count: _historial.length,
                          icon: Icons.history_rounded,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 170,
                          child: ListView.builder(
                            controller: _historialScroll,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            itemCount: _historial.length,
                            itemBuilder: (context, index) {
                              final item = _historial[index];
                              final tipo = normalizeMediaType(
                                item['tipo'] ??
                                    item['media_type'] ??
                                    item['type'],
                              );
                              final image = backdropFromItem(item).isNotEmpty
                                  ? backdropFromItem(item)
                                  : posterFromItem(item, size: 'w780');

                              return _HistorialBanner(
                                focusNode: _historialNodes[index],
                                title: item['titulo']?.toString() ??
                                    item['title']?.toString() ??
                                    'Sin título',
                                image: image,
                                tipo: tipo,
                                temporada: item['temporada'],
                                capitulo: item['capitulo'],
                                segundo: item['segundo'] as int? ?? 0,
                                ignoreSelect: () => _ignoreSelectUntil,
                                onTap: () => _openHistorial(item),
                                onLongPress: () =>
                                    _openOpcionesFromHistorial(item),
                                onArrow: (dx, dy) =>
                                    _moveFocus(0, index, dx, dy),
                              );
                            },
                          ),
                        ),
                      ),
                    ],

                    SliverToBoxAdapter(
                      key: _guardadosSectionKey,
                      child: _SectionHeader(
                        title: 'Mi lista',
                        count: _guardados.length,
                        icon: Icons.bookmark_rounded,
                      ),
                    ),

                    if (_guardados.isEmpty)
                      SliverToBoxAdapter(child: _buildEmptyGuardados())
                    else
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 240,
                          child: ListView.builder(
                            controller: _guardadosScroll,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            itemCount: _guardados.length,
                            itemBuilder: (context, index) {
                              final item = _guardados[index];
                              final title = item['title']?.toString() ??
                                  item['titulo']?.toString() ??
                                  '';
                              final poster = posterFromItem(item);
                              final type = normalizeMediaType(
                                item['media_type'] ??
                                    item['type'] ??
                                    item['tipo'],
                              );
                              final rating = item['vote_average'];
                              final ratingValue = rating is num
                                  ? rating.toDouble()
                                  : double.tryParse('$rating') ?? 0;

                              return _GuardadoCard(
                                focusNode: _guardadosNodes[index],
                                title: title,
                                poster: poster,
                                type: type,
                                rating: ratingValue,
                                ignoreSelect: () => _ignoreSelectUntil,
                                onTap: () => _openGuardado(item),
                                onLongPress: () =>
                                    _openOpcionesFromGuardado(item),
                                onArrow: (dx, dy) =>
                                    _moveFocus(1, index, dx, dy),
                              );
                            },
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 48)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyGuardados() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 52,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'Aún no has guardado nada',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        children: [
          Icon(icon, color: _kAccentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Banner historial ────────────────────────────────────────────────────────

class _HistorialBanner extends StatefulWidget {
  final FocusNode focusNode;
  final String title;
  final String image;
  final String tipo;
  final dynamic temporada;
  final dynamic capitulo;
  final int segundo;
  final bool Function() ignoreSelect;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(int dx, int dy) onArrow;

  const _HistorialBanner({
    required this.focusNode,
    required this.title,
    required this.image,
    required this.tipo,
    this.temporada,
    this.capitulo,
    required this.segundo,
    required this.ignoreSelect,
    required this.onTap,
    this.onLongPress,
    required this.onArrow,
  });

  @override
  State<_HistorialBanner> createState() => _HistorialBannerState();
}

class _HistorialBannerState extends State<_HistorialBanner> {
  Timer? _holdTimer;
  bool _longFired = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (widget.ignoreSelect()) return;
    _holdTimer?.cancel();
    _longFired = false;
    if (widget.onLongPress == null) return;
    _holdTimer = Timer(const Duration(milliseconds: 550), () {
      if (widget.ignoreSelect()) return;
      _longFired = true;
      widget.onLongPress?.call();
    });
  }

  void _endHold({required bool fromKeyUp}) {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (fromKeyUp && !_longFired && !widget.ignoreSelect()) {
      widget.onTap();
    }
    _longFired = false;
  }

  String get _timeLabel {
    final total = widget.segundo;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  String get _meta {
    if (widget.tipo == 'tv' &&
        widget.temporada != null &&
        widget.capitulo != null) {
      return 'T${widget.temporada.toString().padLeft(2, '0')}E${widget.capitulo.toString().padLeft(2, '0')}';
    }
    return widget.tipo == 'tv' ? 'Serie' : 'Película';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (event is KeyDownEvent) {
            widget.onArrow(0, -1);
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (event is KeyDownEvent) {
            widget.onArrow(0, 1);
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (event is KeyDownEvent) {
            widget.onArrow(-1, 0);
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (event is KeyDownEvent) {
            widget.onArrow(1, 0);
            return KeyEventResult.handled;
          }
        }

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (widget.ignoreSelect()) {
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent) {
            _startHold();
            return KeyEventResult.handled;
          }
          if (event is KeyUpEvent) {
            _endHold(fromKeyUp: true);
            return KeyEventResult.handled;
          }
        }

        if (event is KeyDownEvent &&
            widget.onLongPress != null &&
            !widget.ignoreSelect() &&
            (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                event.logicalKey == LogicalKeyboardKey.mediaPlay)) {
          widget.onLongPress!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              if (!widget.ignoreSelect()) widget.onTap();
            },
            onLongPress: widget.onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 280,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: _kAccentColor.withValues(alpha: 0.4),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.image.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.image,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            memCacheHeight: 240,
                            placeholder: (_, __) =>
                                Container(color: Colors.grey[900]),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[900],
                              child: const Icon(
                                Icons.movie,
                                color: Colors.white24,
                                size: 40,
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.grey[900],
                            child: const Icon(
                              Icons.movie,
                              color: Colors.white24,
                              size: 40,
                            ),
                          ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.9),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _meta,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 3.5,
                        color: Colors.white.withValues(alpha: 0.2),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (widget.segundo / 4200).clamp(0.06, 1.0),
                          child: Container(color: _kAccentColor),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _timeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (hasFocus)
                      Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _kAccentColor.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Card guardado ───────────────────────────────────────────────────────────

class _GuardadoCard extends StatefulWidget {
  final FocusNode focusNode;
  final String title;
  final String poster;
  final String type;
  final double rating;
  final bool Function() ignoreSelect;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(int dx, int dy) onArrow;

  const _GuardadoCard({
    required this.focusNode,
    required this.title,
    required this.poster,
    required this.type,
    required this.rating,
    required this.ignoreSelect,
    required this.onTap,
    this.onLongPress,
    required this.onArrow,
  });

  @override
  State<_GuardadoCard> createState() => _GuardadoCardState();
}

class _GuardadoCardState extends State<_GuardadoCard> {
  Timer? _holdTimer;
  bool _longFired = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (widget.ignoreSelect()) return;
    _holdTimer?.cancel();
    _longFired = false;
    if (widget.onLongPress == null) return;
    _holdTimer = Timer(const Duration(milliseconds: 550), () {
      if (widget.ignoreSelect()) return;
      _longFired = true;
      widget.onLongPress?.call();
    });
  }

  void _endHold({required bool fromKeyUp}) {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (fromKeyUp && !_longFired && !widget.ignoreSelect()) {
      widget.onTap();
    }
    _longFired = false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (event is KeyDownEvent) {
            widget.onArrow(0, -1);
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (event is KeyDownEvent) {
            widget.onArrow(0, 1);
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (event is KeyDownEvent) {
            widget.onArrow(-1, 0);
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (event is KeyDownEvent) {
            widget.onArrow(1, 0);
            return KeyEventResult.handled;
          }
        }

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (widget.ignoreSelect()) {
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent) {
            _startHold();
            return KeyEventResult.handled;
          }
          if (event is KeyUpEvent) {
            _endHold(fromKeyUp: true);
            return KeyEventResult.handled;
          }
        }

        if (event is KeyDownEvent &&
            widget.onLongPress != null &&
            !widget.ignoreSelect() &&
            (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                event.logicalKey == LogicalKeyboardKey.mediaPlay)) {
          widget.onLongPress!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              if (!widget.ignoreSelect()) widget.onTap();
            },
            onLongPress: widget.onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 145,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.poster,
                            fit: BoxFit.cover,
                            memCacheWidth: 220,
                            memCacheHeight: 330,
                            placeholder: (_, __) =>
                                Container(color: Colors.grey[900]),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[900],
                              child: const Icon(
                                Icons.movie,
                                color: Colors.white24,
                                size: 40,
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.grey[900],
                            child: const Icon(
                              Icons.movie,
                              color: Colors.white24,
                              size: 40,
                            ),
                          ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 26, 8, 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.88),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  mediaTypeLabel(widget.type),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                ),
                                if (widget.rating > 0) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    widget.rating.toStringAsFixed(1),
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}