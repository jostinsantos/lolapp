import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CapitulosTemporadas extends StatelessWidget {
  final List<dynamic> temporadas;
  final int selectedSeasonIndex;
  final List<FocusNode> seasonFocusNodes;
  final List<FocusNode> episodeFocusNodes;
  final ScrollController seasonScrollController;
  final ScrollController episodeScrollController;
  final Map<String, int> episodeProgress;
  final int? currentTemporada;
  final int? currentCapitulo;
  final Color accentColor;
  final String Function(String?, {String size}) optimizeTmdbUrl;
  final void Function(int index) onSeasonSelected;
  final void Function({required int temporada, required int capitulo}) onEpisodeSelected;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;
  final VoidCallback onArrowLeft;
  final VoidCallback onArrowRight;
  final bool Function(KeyEvent) isBackKey;
  final VoidCallback onBack;
  final int Function() getFocusEpisodeIndex;

  const CapitulosTemporadas({
    super.key,
    required this.temporadas,
    required this.selectedSeasonIndex,
    required this.seasonFocusNodes,
    required this.episodeFocusNodes,
    required this.seasonScrollController,
    required this.episodeScrollController,
    required this.episodeProgress,
    this.currentTemporada,
    this.currentCapitulo,
    required this.accentColor,
    required this.optimizeTmdbUrl,
    required this.onSeasonSelected,
    required this.onEpisodeSelected,
    required this.onArrowUp,
    required this.onArrowDown,
    required this.onArrowLeft,
    required this.onArrowRight,
    required this.isBackKey,
    required this.onBack,
    required this.getFocusEpisodeIndex,
  });

  @override
  Widget build(BuildContext context) {
    if (temporadas.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView.builder(
            controller: seasonScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: temporadas.length,
            itemBuilder: (ctx, i) {
              final temp = temporadas[i];
              final isSelected = i == selectedSeasonIndex;
              final hasFocus =
                  seasonFocusNodes.length > i && seasonFocusNodes[i].hasFocus;
              return Focus(
                focusNode: seasonFocusNodes.length > i ? seasonFocusNodes[i] : null,
                onKeyEvent: (n, e) {
                  if (e is KeyDownEvent) {
                    if (isBackKey(e)) {
                      onBack();
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                      onArrowDown();
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                      onArrowUp();
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      onArrowLeft();
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                      onArrowRight();
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.select ||
                        e.logicalKey == LogicalKeyboardKey.enter) {
                      onSeasonSelected(i);
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  onTap: () => onSeasonSelected(i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.transparent
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: hasFocus
                            ? Colors.white
                            : isSelected
                                ? accentColor
                                : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      temp['nombre'] ?? 'Temporada ${temp['numero']}',
                      style: TextStyle(
                        color: isSelected ? accentColor : Colors.white70,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 105,
          child: _buildEpisodesList(context),
        ),
      ],
    );
  }

  Widget _buildEpisodesList(BuildContext context) {
    final caps = temporadas[selectedSeasonIndex]['capitulos'] as List? ?? [];
    return ListView.builder(
      controller: episodeScrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: caps.length,
      itemBuilder: (ctx, i) {
        final cap = caps[i];
        final isActual = cap['actual'] == true;
        final num = cap['numero'];
        final titulo = cap['titulo'] ?? 'Episodio $num';
        final backdrop = optimizeTmdbUrl(cap['backdrop']?.toString(), size: 'w300');
        final seasonNum = temporadas[selectedSeasonIndex]['numero'];
        final hasFocus =
            episodeFocusNodes.length > i && episodeFocusNodes[i].hasFocus;
        final progressKey = 'T${seasonNum}_C$num';
        final progressSec = episodeProgress[progressKey];
        final hasProgress = progressSec != null && progressSec > 5;

        return Focus(
          focusNode: episodeFocusNodes.length > i ? episodeFocusNodes[i] : null,
          onKeyEvent: (n, e) {
            if (e is KeyDownEvent) {
              if (isBackKey(e)) {
                onBack();
                return KeyEventResult.handled;
              }
              if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                onArrowUp();
                return KeyEventResult.handled;
              }
              if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                onArrowLeft();
                return KeyEventResult.handled;
              }
              if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                onArrowRight();
                return KeyEventResult.handled;
              }
              if (e.logicalKey == LogicalKeyboardKey.select ||
                  e.logicalKey == LogicalKeyboardKey.enter) {
                onEpisodeSelected(temporada: seasonNum, capitulo: num);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: () => onEpisodeSelected(temporada: seasonNum, capitulo: num),
            child: Container(
              width: 155,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : isActual
                          ? accentColor
                          : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (backdrop.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: backdrop,
                        fit: BoxFit.cover,
                        memCacheWidth: 310,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, __) => ColoredBox(color: Colors.grey[900]!),
                        errorWidget: (_, __, ___) => ColoredBox(color: Colors.grey[900]!),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xD9000000)],
                        ),
                      ),
                    ),
                    if (isActual)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Icon(
                          Icons.play_circle_fill,
                          color: accentColor,
                          size: 22,
                        ),
                      ),
                    Positioned(
                      bottom: 6,
                      left: 8,
                      right: 8,
                      child: Text(
                        '$num: $titulo',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (hasProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: (progressSec / 2700).clamp(0.0, 1.0),
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation(accentColor),
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}