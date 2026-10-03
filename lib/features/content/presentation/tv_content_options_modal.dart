import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_content_page.dart';
import '../../player/presentation/tv/tv_player_page.dart';
/// ─────────────────────────────────────────────────────────────────────────────
/// Modal independiente de opciones de contenido.
///
/// Uso desde cualquier parte de la app:
/// ```dart
/// showContenidoOpcionesModal(
///   context,
///   tmdbId: 12345,
///   tipo: 'movie', // o 'tv'
///   // opcionales:
///   idcontenido: 12345,
///   titulo: 'Título',
///   posterUrl: 'https://...',
///   backdropUrl: 'https://...',
/// );
/// ```
///
/// - Revisa cache de historial (`cachePlayer_*`).
/// - Si hay progreso → "Reanudar" + tiempo restante aproximado.
/// - Si es TV y hay temporada/capítulo en cache → los pasa al player.
/// - Toggle de Mi lista vía [GuardadosCache].
/// ─────────────────────────────────────────────────────────────────────────────

const _kAccent = Color(0xFFFF6B00);
const _kSurface = Color(0xFF161618);
const _kBorder = Color(0xFF26262A);
const _kBg = Color(0xFF0A0A0A);

Future<T?> showContenidoOpcionesModal<T>(
  BuildContext context, {
  required int tmdbId,
  required String tipo,
  int? idcontenido,
  String? titulo,
  String? posterUrl,
  String? backdropUrl,
  String? logoUrl,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => ContenidoOpcionesModal(
      tmdbId: tmdbId,
      tipo: tipo.toLowerCase() == 'tv' ? 'tv' : 'movie',
      idcontenido: idcontenido ?? tmdbId,
      titulo: titulo,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      logoUrl: logoUrl,
    ),
  );
}

class ContenidoOpcionesModal extends StatefulWidget {
  final int tmdbId;
  final String tipo;
  final int idcontenido;
  final String? titulo;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;

  const ContenidoOpcionesModal({
    super.key,
    required this.tmdbId,
    required this.tipo,
    required this.idcontenido,
    this.titulo,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
  });

  @override
  State<ContenidoOpcionesModal> createState() => _ContenidoOpcionesModalState();
}

class _ContenidoOpcionesModalState extends State<ContenidoOpcionesModal> {
  bool _loading = true;
  bool _isSaved = false;
  Map<String, dynamic>? _history;

  String _titulo = '';
  String _poster = '';
  String _backdrop = '';

  final FocusNode _playNode = FocusNode(debugLabel: 'opt_play');
  final FocusNode _infoNode = FocusNode(debugLabel: 'opt_info');
  final FocusNode _saveNode = FocusNode(debugLabel: 'opt_save');

  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _nodes = [_playNode, _infoNode, _saveNode];
    _titulo = widget.titulo?.trim().isNotEmpty == true
        ? widget.titulo!
        : 'Sin título';
    _poster = widget.posterUrl ?? '';
    _backdrop = widget.backdropUrl ?? '';
    _load();
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final hist = await _findHistory();
    final saved = await _checkSaved();

    // Completar título/poster desde historial o lista si no vinieron
    if (hist != null) {
      if (_titulo == 'Sin título') {
        _titulo = hist['titulo']?.toString() ??
            hist['title']?.toString() ??
            _titulo;
      }
      if (_poster.isEmpty) {
        _poster = hist['poster']?.toString() ??
            hist['poster_path']?.toString() ??
            '';
      }
      if (_backdrop.isEmpty) {
        _backdrop = hist['backdrop']?.toString() ??
            hist['backdrop_path']?.toString() ??
            _poster;
      }
    }

    if (_titulo == 'Sin título' || _poster.isEmpty) {
      try {
        final all = await GuardadosCache.getAll();
        final match = all.cast<Map?>().firstWhere(
          (e) {
            if (e == null) return false;
            final id = e['idcontenido'] ?? e['tmdb_id'] ?? e['idtmdb'];
            return id == widget.idcontenido || id == widget.tmdbId;
          },
          orElse: () => null,
        );
        if (match != null) {
          if (_titulo == 'Sin título') {
            _titulo = match['title']?.toString() ??
                match['titulo']?.toString() ??
                _titulo;
          }
          if (_poster.isEmpty) {
            _poster = match['poster_path']?.toString() ??
                match['poster']?.toString() ??
                '';
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _history = hist;
      _isSaved = saved;
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playNode.requestFocus();
    });
  }

  /// Busca el historial más reciente para este contenido.
  Future<Map<String, dynamic>?> _findHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('cachePlayer_'));

      Map<String, dynamic>? best;
      String bestTs = '';

      for (final key in keys) {
        // Filtrar por id: cachePlayer_{id} o cachePlayer_{id}_T{n}_C{n}
        final rest = key.replaceFirst('cachePlayer_', '');
        if (!(rest == '${widget.idcontenido}' ||
            rest.startsWith('${widget.idcontenido}_') ||
            rest == '${widget.tmdbId}' ||
            rest.startsWith('${widget.tmdbId}_'))) {
          continue;
        }

        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final data = Map<String, dynamic>.from(jsonDecode(raw));
          final segundo = data['segundo'] as int? ?? 0;
          if (segundo < 5) continue;

          final ts = data['timestamp']?.toString() ?? '';
          if (best == null || ts.compareTo(bestTs) > 0) {
            best = data;
            bestTs = ts;
          }
        } catch (_) {}
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _checkSaved() async {
    try {
      final all = await GuardadosCache.getAll();
      for (final e in all) {
        final id = e['idcontenido'] ?? e['tmdb_id'] ?? e['idtmdb'];
        if (id == widget.idcontenido || id == widget.tmdbId) return true;
      }
    } catch (_) {}
    return false;
  }

  bool get _hasProgress {
    final s = _history?['segundo'] as int? ?? 0;
    return s >= 8;
  }

  String get _progressLabel {
    if (!_hasProgress) return '';
    final segundo = _history!['segundo'] as int? ?? 0;
    final m = segundo ~/ 60;
    final s = segundo % 60;
    final time =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    // Tiempo restante aproximado si hay duración
    final duration = _history!['duration'] as int? ?? 0;
    if (duration > 0 && segundo < duration) {
      final left = duration - segundo;
      final lm = left ~/ 60;
      final ls = left % 60;
      return 'Reanudar · quedan ${lm}m ${ls.toString().padLeft(2, '0')}s';
    }
    return 'Reanudar desde $time';
  }

  String get _episodeMeta {
    if (widget.tipo != 'tv' || _history == null) return '';
    final t = _history!['temporada'];
    final c = _history!['capitulo'];
    if (t == null || c == null) return '';
    return 'T${t.toString().padLeft(2, '0')}E${c.toString().padLeft(2, '0')}';
  }

  void _openPlayer() {
    final hist = _history;
    int? temporada;
    int? capitulo;

    if (widget.tipo == 'tv' && hist != null) {
      temporada = hist['temporada'] as int?;
      capitulo = hist['capitulo'] as int?;
    }

    final videoUrl = hist?['videoUrl']?.toString() ?? '';

    Navigator.of(context).pop(); // cierra modal
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoUrl: videoUrl,
          idcontenido: widget.idcontenido,
          tmdbId: widget.tmdbId,
          temporada: temporada,
          capitulo: capitulo,
          tipo: widget.tipo,
          titulo: _titulo,
          servidorUrl: hist?['servidorUrl']?.toString(),
          servidorNombre: hist?['servidorNombre']?.toString(),
          idioma: hist?['idioma']?.toString(),
          idServidor: hist?['idServidor'] as int?,
          fuentesServidor: hist?['fuentesServidor']?.toString(),
        ),
      ),
    );
  }

  void _openInfo() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PageContenido(
          idcontenido: widget.idcontenido,
          tmdbId: widget.tmdbId,
          mediaType: widget.tipo,
        ),
      ),
    );
  }

  Future<void> _toggleSave() async {
    try {
      final item = <String, dynamic>{
        'idcontenido': widget.idcontenido,
        'tmdb_id': widget.tmdbId,
        'media_type': widget.tipo,
        'type': widget.tipo,
        'title': _titulo,
        'poster_path': _poster,
        'backdrop_path': _backdrop.isNotEmpty ? _backdrop : _poster,
        'addedAt': DateTime.now().toIso8601String(),
      };

      final nowSaved = await GuardadosCache.toggle(item);
      if (mounted) {
        setState(() => _isSaved = nowSaved);
      }
    } catch (e) {
      debugPrint('Error toggle save: $e');
    }
  }

  void _moveFocus(int current, int dx) {
    final next = (current + dx).clamp(0, _nodes.length - 1);
    if (next != current) _nodes[next].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: FocusScope(
        autofocus: true,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: _loading
              ? const SizedBox(
                  height: 180,
                  child: Center(
                    child: CircularProgressIndicator(color: _kAccent),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const Divider(height: 1, color: _kBorder),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        children: [
                          _OptionTile(
                            focusNode: _playNode,
                            icon: _hasProgress
                                ? Icons.play_circle_filled_rounded
                                : Icons.play_arrow_rounded,
                            label: _hasProgress ? 'Reanudar' : 'Ver ahora',
                            subtitle: _hasProgress
                                ? [
                                    if (_episodeMeta.isNotEmpty) _episodeMeta,
                                    _progressLabel,
                                  ].where((e) => e.isNotEmpty).join(' · ')
                                : (widget.tipo == 'tv'
                                    ? 'Reproducir serie'
                                    : 'Reproducir película'),
                            accent: true,
                            onTap: _openPlayer,
                            onArrow: (dx) => _moveFocus(0, dx),
                          ),
                          const SizedBox(height: 8),
                          _OptionTile(
                            focusNode: _infoNode,
                            icon: Icons.info_outline_rounded,
                            label: 'Más información',
                            subtitle: 'Ficha, reparto y detalles',
                            onTap: _openInfo,
                            onArrow: (dx) => _moveFocus(1, dx),
                          ),
                          const SizedBox(height: 8),
                          _OptionTile(
                            focusNode: _saveNode,
                            icon: _isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            label: _isSaved
                                ? 'Quitar de Mi lista'
                                : 'Guardar en Mi lista',
                            subtitle: _isSaved
                                ? 'Eliminar de tus guardados'
                                : 'Añadir a tus guardados',
                            onTap: _toggleSave,
                            onArrow: (dx) => _moveFocus(2, dx),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final image = _backdrop.isNotEmpty
        ? _backdrop
        : (_poster.isNotEmpty ? _poster : '');

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SizedBox(
        height: 140,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image.isNotEmpty)
              CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                memCacheWidth: 640,
                placeholder: (_, __) => Container(color: _kBg),
                errorWidget: (_, __, ___) => Container(color: _kBg),
              )
            else
              Container(color: _kBg),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_poster.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: _poster,
                        width: 56,
                        height: 84,
                        fit: BoxFit.cover,
                        memCacheWidth: 112,
                        errorWidget: (_, __, ___) => Container(
                          width: 56,
                          height: 84,
                          color: Colors.grey[850],
                        ),
                      ),
                    ),
                  if (_poster.isNotEmpty) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.tipo == 'tv' ? 'Serie' : 'Película',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool accent;
  final bool compact;
  final VoidCallback onTap;
  final void Function(int dx) onArrow;

  const _OptionTile({
    required this.focusNode,
    required this.icon,
    required this.label,
    this.subtitle,
    this.accent = false,
    this.compact = false,
    required this.onTap,
    required this.onArrow,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onArrow(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onArrow(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: compact ? 12 : 14,
              ),
              decoration: BoxDecoration(
                color: hasFocus
                    ? (accent
                        ? _kAccent.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.1))
                    : (accent
                        ? _kAccent.withValues(alpha: 0.12)
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent
                          ? _kAccent.withValues(alpha: hasFocus ? 0.9 : 0.75)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: accent || hasFocus
                          ? Colors.white
                          : Colors.white70,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight:
                                hasFocus ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasFocus)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                      size: 22,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}