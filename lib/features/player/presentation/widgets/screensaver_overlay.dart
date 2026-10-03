import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ScreensaverOverlay extends StatelessWidget {
  final String? backdropUrl;
  final String? logoUrl;
  final String title;
  final String? episodeLabel;
  final String Function(String?, {String size}) optimizeTmdbUrl;

  const ScreensaverOverlay({
    super.key,
    this.backdropUrl,
    this.logoUrl,
    required this.title,
    this.episodeLabel,
    required this.optimizeTmdbUrl,
  });

  /// Ancho máximo que puede ocupar el logo (evita que se estire por toda la pantalla)
  static const double _maxLogoWidth = 320;
  static const double _maxLogoWidthEpisode = 260;

  @override
  Widget build(BuildContext context) {
    final backdrop = optimizeTmdbUrl(backdropUrl, size: 'w780');
    final logo = optimizeTmdbUrl(logoUrl, size: 'w300');
    final isEpisode = episodeLabel != null && episodeLabel!.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop.isNotEmpty)
          CachedNetworkImage(
            imageUrl: backdrop,
            fit: BoxFit.cover,
            memCacheWidth: 960,
            placeholder: (_, __) => const ColoredBox(color: Colors.black),
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
          )
        else
          const ColoredBox(color: Colors.black),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black,
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25, 0.55, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          left: 36,
          bottom: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Siempre: "Continuar viendo"
                Text(
                  'Continuar viendo',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                // Logo o título (siempre a la izquierda)
                _buildLogo(
                  logo: logo,
                  title: title,
                  maxWidth: isEpisode ? _maxLogoWidthEpisode : _maxLogoWidth,
                  height: isEpisode ? 56 : 64,
                  textSize: isEpisode ? 24 : 28,
                ),
                // Capítulo / episodio (si existe)
                if (isEpisode) ...[
                  const SizedBox(height: 8),
                  Text(
                    episodeLabel!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Construye el logo con ancho máximo y altura fija, sin deformar.
  /// Siempre alineado a la izquierda. Si falla o no hay logo, muestra el título.
  Widget _buildLogo({
    required String logo,
    required String title,
    required double maxWidth,
    required double height,
    required double textSize,
  }) {
    final fallback = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.left,
      style: TextStyle(
        color: Colors.white,
        fontSize: textSize,
        fontWeight: FontWeight.w800,
      ),
    );

    if (logo.isEmpty) return fallback;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: height,
        ),
        child: CachedNetworkImage(
          imageUrl: logo,
          height: height,
          width: maxWidth,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          memCacheHeight: (height * 2).round(),
          placeholder: (_, __) => SizedBox(
            height: height,
            width: maxWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: fallback,
            ),
          ),
          errorWidget: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}