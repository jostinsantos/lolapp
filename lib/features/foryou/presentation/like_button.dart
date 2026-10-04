import 'package:flutter/material.dart';
import '../../../data/recommendations/user_taste_profile.dart';

/// Botón "Me gusta este contenido" — refuerza el perfil de gustos.
class LikeContentButton extends StatefulWidget {
  final int tmdbId;
  final String title;
  final String mediaType; // movie | tv
  final List<String> genres;
  final List<String> keywords;

  const LikeContentButton({
    super.key,
    required this.tmdbId,
    required this.title,
    required this.mediaType,
    this.genres = const [],
    this.keywords = const [],
  });

  @override
  State<LikeContentButton> createState() => _LikeContentButtonState();
}

class _LikeContentButtonState extends State<LikeContentButton> {
  bool _liked = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final p = await UserTasteProfile.load();
    if (mounted) {
      setState(() {
        _liked = p.isLiked(widget.tmdbId);
        _loading = false;
      });
    }
  }

  Future<void> _toggle() async {
    final p = await UserTasteProfile.load();
    if (_liked) {
      await p.unlikeContent(widget.tmdbId);
    } else {
      await p.likeContent(
        tmdbId: widget.tmdbId,
        title: widget.title,
        type: widget.mediaType,
        genres: widget.genres,
        keywords: widget.keywords,
      );
    }
    if (mounted) {
      setState(() => _liked = !_liked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _liked
                ? '👍 Me gusta: lo tendré en cuenta para recomendarte'
                : 'Quitado de Me gusta',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(width: 40, height: 40);
    return IconButton(
      tooltip: _liked ? 'Quitar Me gusta' : 'Me gusta este contenido',
      onPressed: _toggle,
      icon: Icon(
        _liked ? Icons.favorite : Icons.favorite_border,
        color: _liked ? Colors.pinkAccent : Colors.white70,
      ),
    );
  }
}
