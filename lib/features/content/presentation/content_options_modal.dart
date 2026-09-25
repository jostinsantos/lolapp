import 'dart:convert';
import 'dart:ui'; // para ImageFilter.blur

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content_page.dart';
import '../../player/presentation/player_page.dart';
// ─────────────────────────────────────────────────────────────────────────────
// Modal de opciones – móvil (diseño de la captura + blur)
// ─────────────────────────────────────────────────────────────────────────────

const _kAccent = Color(0xFFFF6B00);
const _kButtonBg = Color(0xFF2C2C2E);
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
    barrierColor: Colors.transparent, // el blur lo controlamos nosotros
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

  @override
  void initState() {
    super.initState();
    _titulo = widget.titulo?.trim().isNotEmpty == true
        ? widget.titulo!
        : 'Sin título';
    _poster = widget.posterUrl ?? '';
    _backdrop = widget.backdropUrl ?? '';
    _load();
  }

  Future<void> _load() async {
    final hist = await _findHistory();
    final saved = await _checkSaved();

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
  }

  Future<Map<String, dynamic>?> _findHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('cachePlayer_'));

      Map<String, dynamic>? best;
      String bestTs = '';

      for (final key in keys) {
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

    Navigator.of(context).pop();

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
          idioma: hist?['idioma']?.toString(),
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
        'idtmdb': widget.tmdbId,
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

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Fondo con blur elegante ─────────────────────────────────────
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: Colors.black.withValues(alpha: 0.45), // poco opaco
              ),
            ),
          ),

          // ── Contenido centrado ──────────────────────────────────────────
          Center(
            child: _loading
                ? const CircularProgressIndicator(color: _kAccent)
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Poster
                        _buildPoster(),
                        const SizedBox(height: 18),

                        // Título
                        Text(
                          _titulo,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.tipo == 'tv' ? 'Serie' : 'Película',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Menú de acciones (más estrecho)
                        _buildButtons(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoster() {
    return Container(
      width: 170,
      height: 255,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _poster.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: _poster,
                fit: BoxFit.cover,
                memCacheWidth: 340,
                placeholder: (_, __) => Container(color: _kBg),
                errorWidget: (_, __, ___) => Container(
                  color: _kBg,
                  child: const Icon(Icons.movie, color: Colors.white24, size: 44),
                ),
              )
            : Container(
                color: _kBg,
                child: const Icon(Icons.movie, color: Colors.white24, size: 44),
              ),
      ),
    );
  }

  Widget _buildButtons() {
    // Ancho más estrecho, centrado (estilo de la captura)
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _kButtonBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            // 1. Reproducir / Reanudar
            _MobileOption(
              icon: _hasProgress
                  ? Icons.play_circle_filled_rounded
                  : Icons.play_arrow_rounded,
              label: _hasProgress ? 'Reanudar' : 'Reproducir',
              subtitle: _hasProgress
                  ? [
                      if (_episodeMeta.isNotEmpty) _episodeMeta,
                      _progressLabel,
                    ].where((e) => e.isNotEmpty).join(' · ')
                  : null,
              onTap: _openPlayer,
              isFirst: true,
            ),
            const Divider(
              height: 1,
              color: Color(0xFF3A3A3C),
              indent: 16,
              endIndent: 16,
            ),

            // 2. Más información
            _MobileOption(
              icon: Icons.info_outline_rounded,
              label: 'Más información',
              onTap: _openInfo,
            ),
            const Divider(
              height: 1,
              color: Color(0xFF3A3A3C),
              indent: 16,
              endIndent: 16,
            ),

            // 3. Añadir / Quitar
            _MobileOption(
              icon: _isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: _isSaved
                  ? 'Quitar de Mi lista'
                  : 'Añadir a la biblioteca',
              isDestructive: _isSaved,
              onTap: _toggleSave,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón individual (estilo captura)
// ─────────────────────────────────────────────────────────────────────────────

class _MobileOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool isFirst;
  final bool isLast;

  const _MobileOption({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.isDestructive = false,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(14) : Radius.zero,
          bottom: isLast ? const Radius.circular(14) : Radius.zero,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isDestructive
                            ? const Color(0xFFFF453A)
                            : Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                icon,
                size: 22,
                color: isDestructive
                    ? const Color(0xFFFF453A)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}