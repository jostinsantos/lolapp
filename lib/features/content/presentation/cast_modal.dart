import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

class ModalActores extends StatefulWidget {
  final String? imdbId;
  final int? tmdbId;
  final String tipo;
  final Color accentColor;
  final FocusNode? returnFocus;

  const ModalActores({
    super.key,
    this.imdbId,
    this.tmdbId,
    required this.tipo,
    required this.accentColor,
    this.returnFocus,
  });

  static Future<void> show({
    required BuildContext context,
    String? imdbId,
    int? tmdbId,
    required String tipo,
    required Color accentColor,
    FocusNode? returnFocus,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: false,
      builder: (_) => ModalActores(
        imdbId: imdbId,
        tmdbId: tmdbId,
        tipo: tipo,
        accentColor: accentColor,
        returnFocus: returnFocus,
      ),
    );
  }

  @override
  State<ModalActores> createState() => _ModalActoresState();
}

class _ModalActoresState extends State<ModalActores> {
  static const String _tmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  List<Map<String, dynamic>> _cast = [];
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final List<FocusNode> _focusNodes = [];
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCast();
  }

  @override
  void dispose() {
    for (final n in _focusNodes) {
      n.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCast() async {
    try {
      int? tmdbId = widget.tmdbId;
      if (tmdbId == null && widget.imdbId != null && widget.imdbId!.isNotEmpty) {
        final findUri = Uri.https('api.themoviedb.org', '/3/find/${widget.imdbId}', {
          'api_key': _tmdbKey,
          'external_source': 'imdb_id',
        });
        final findRes = await http.get(findUri).timeout(const Duration(seconds: 8));
        if (findRes.statusCode == 200) {
          final data = jsonDecode(findRes.body);
          final results = widget.tipo == 'tv'
              ? (data['tv_results'] as List? ?? [])
              : (data['movie_results'] as List? ?? []);
          if (results.isNotEmpty) {
            tmdbId = results.first['id'] as int?;
          }
        }
      }

      if (tmdbId == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'No se encontró elenco';
          });
        }
        return;
      }

      final media = widget.tipo == 'tv' ? 'tv' : 'movie';
      final creditsUri = Uri.https(
        'api.themoviedb.org',
        '/3/$media/$tmdbId/credits',
        {'api_key': _tmdbKey},
      );
      final res = await http.get(creditsUri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Error al cargar elenco';
          });
        }
        return;
      }

      final data = jsonDecode(res.body);
      final cast = List<Map<String, dynamic>>.from(data['cast'] ?? []);
      final limited = cast.take(24).toList();

      if (!mounted) return;
      for (final n in _focusNodes) {
        n.dispose();
      }
      _focusNodes
        ..clear()
        ..addAll(List.generate(limited.length, (_) => FocusNode()));

      setState(() {
        _cast = limited;
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNodes.isNotEmpty) {
          _focusNodes[0].requestFocus();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sin conexión';
        });
      }
    }
  }

  String _profileUrl(dynamic path) {
    if (path == null) return '';
    final s = path.toString();
    if (s.startsWith('http')) return s;
    if (s.isEmpty || s == 'null') return '';
    return 'https://image.tmdb.org/t/p/w185$s';
  }

  void _move(int delta) {
    if (_cast.isEmpty) return;
    final next = (_focusedIndex + delta).clamp(0, _cast.length - 1);
    if (next == _focusedIndex) return;
    setState(() => _focusedIndex = next);
    _focusNodes[next].requestFocus();
    final itemW = 130.0;
    final offset = (next * itemW) - (MediaQuery.sizeOf(context).width / 2) + (itemW / 2);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _move(1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _move(-1);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Container(
          width: size.width * 0.88,
          height: size.height * 0.55,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      'Elenco',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFFFF6B00)),
                      )
                    : _error != null
                        ? Center(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.white54),
                            ),
                          )
                        : _cast.isEmpty
                            ? const Center(
                                child: Text(
                                  'Sin actores disponibles',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                itemCount: _cast.length,
                                itemBuilder: (ctx, i) {
                                  final c = _cast[i];
                                  final name = c['name']?.toString() ?? '';
                                  final character = c['character']?.toString() ?? '';
                                  final photo = _profileUrl(c['profile_path']);
                                  final hasFocus = _focusNodes.length > i && _focusNodes[i].hasFocus;

                                  return Focus(
                                    focusNode: _focusNodes.length > i ? _focusNodes[i] : null,
                                    onFocusChange: (has) {
                                      if (has) setState(() => _focusedIndex = i);
                                    },
                                    child: Container(
                                      width: 120,
                                      margin: const EdgeInsets.only(right: 14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: hasFocus ? Colors.white : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: photo.isNotEmpty
                                                  ? CachedNetworkImage(
                                                      imageUrl: photo,
                                                      fit: BoxFit.cover,
                                                      width: 120,
                                                      memCacheWidth: 240,
                                                      placeholder: (_, __) =>
                                                          const ColoredBox(color: Color(0xFF2C2C2E)),
                                                      errorWidget: (_, __, ___) => const ColoredBox(
                                                        color: Color(0xFF2C2C2E),
                                                        child: Icon(Icons.person, color: Colors.white38, size: 40),
                                                      ),
                                                    )
                                                  : const ColoredBox(
                                                      color: Color(0xFF2C2C2E),
                                                      child: Icon(Icons.person, color: Colors.white38, size: 40),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (character.isNotEmpty)
                                            Text(
                                              character,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11,
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}