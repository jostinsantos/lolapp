import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VerDespuesList extends StatelessWidget {
  final List<dynamic> items;
  final List<FocusNode> focusNodes;
  final ScrollController scrollController;
  final Map<String, int> progressMap;
  final Color accentColor;
  final String Function(String?, {String size}) optimizeTmdbUrl;
  final void Function(int? idcontenido) onSelect;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowLeft;
  final VoidCallback onArrowRight;
  final bool Function(KeyEvent) isBackKey;
  final VoidCallback onBack;
  final double completedThreshold;
  final int estimatedDurationSec;

  const VerDespuesList({
    super.key,
    required this.items,
    required this.focusNodes,
    required this.scrollController,
    required this.progressMap,
    required this.accentColor,
    required this.optimizeTmdbUrl,
    required this.onSelect,
    required this.onArrowUp,
    required this.onArrowLeft,
    required this.onArrowRight,
    required this.isBackKey,
    required this.onBack,
    this.completedThreshold = 0.50,
    this.estimatedDurationSec = 5400,
  });

  void _scrollTo(BuildContext context, int index) {
    if (!scrollController.hasClients) return;
    const itemWidth = 202.0;
    final offset = (index * itemWidth) -
        (MediaQuery.sizeOf(context).width / 2) +
        (itemWidth / 2);
    scrollController.animateTo(
      offset.clamp(0.0, scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _moveHorizontal(BuildContext context, int fromIndex, int dx) {
    if (items.isEmpty) return;
    final next = (fromIndex + dx).clamp(0, items.length - 1);
    if (next == fromIndex) return;
    if (next < focusNodes.length) {
      focusNodes[next].requestFocus();
      _scrollTo(context, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Ver a continuación',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final rec = items[i];
              final rawPoster =
                  (rec['backdrop'] ?? rec['poster'] ?? rec['poster_path'])
                      ?.toString();
              final poster = optimizeTmdbUrl(rawPoster, size: 'w500');
              final titulo = (rec['titulo'] ?? rec['title'] ?? '').toString();
              final idRaw = rec['idcontenido'] ?? rec['tmdb_id'];
              final id = idRaw is int ? idRaw : int.tryParse('$idRaw');
              final node = i < focusNodes.length ? focusNodes[i] : null;
              final progressSec = progressMap['id_$id'];
              final hasProgress = progressSec != null && progressSec > 5;
              final ratio = hasProgress
                  ? (progressSec! / estimatedDurationSec).clamp(0.0, 1.0)
                  : 0.0;

              return Focus(
                focusNode: node,
                onFocusChange: (has) {
                  if (has) _scrollTo(ctx, i);
                },
                onKeyEvent: (n, e) {
                  if (e is! KeyDownEvent) return KeyEventResult.ignored;
                  if (isBackKey(e)) {
                    onBack();
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                    onArrowUp();
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _moveHorizontal(ctx, i, -1);
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _moveHorizontal(ctx, i, 1);
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.select ||
                      e.logicalKey == LogicalKeyboardKey.enter) {
                    onSelect(id);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () => onSelect(id),
                      child: Container(
                        width: 190,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                hasFocus ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (poster.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: poster,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 380,
                                  fadeInDuration:
                                      const Duration(milliseconds: 150),
                                  placeholder: (_, __) =>
                                      ColoredBox(color: Colors.grey[900]!),
                                  errorWidget: (_, __, ___) =>
                                      ColoredBox(color: Colors.grey[900]!),
                                )
                              else
                                ColoredBox(color: Colors.grey[900]!),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 6, 8, 6),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Color(0xE6000000),
                                      ],
                                    ),
                                  ),
                                  child: Text(
                                    titulo,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              if (hasProgress)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    backgroundColor: Colors.white24,
                                    valueColor:
                                        AlwaysStoppedAnimation(accentColor),
                                    minHeight: 3,
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
            },
          ),
        ),
      ],
    );
  }
}