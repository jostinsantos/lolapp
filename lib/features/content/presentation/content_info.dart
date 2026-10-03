import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ModalInformacion extends StatelessWidget {
  final Map<String, dynamic>? apiData;
  final String tituloContenido;
  final String? tituloCapitulo;
  final String? capituloFmt;
  final String tipo;
  final Color accentColor;
  final String Function(String?, {String size}) optimizeTmdbUrl;

  const ModalInformacion({
    super.key,
    required this.apiData,
    required this.tituloContenido,
    this.tituloCapitulo,
    this.capituloFmt,
    required this.tipo,
    required this.accentColor,
    required this.optimizeTmdbUrl,
  });

  static Future<void> show({
    required BuildContext context,
    required Map<String, dynamic>? apiData,
    required String tituloContenido,
    String? tituloCapitulo,
    String? capituloFmt,
    required String tipo,
    required Color accentColor,
    required String Function(String?, {String size}) optimizeTmdbUrl,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => ModalInformacion(
        apiData: apiData,
        tituloContenido: tituloContenido,
        tituloCapitulo: tituloCapitulo,
        capituloFmt: capituloFmt,
        tipo: tipo,
        accentColor: accentColor,
        optimizeTmdbUrl: optimizeTmdbUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final data = apiData ?? {};
    final overview = (data['overview'] ?? data['sinopsis'] ?? 'Sin descripción disponible.').toString();
    final calificacion = data['calificacion'] ?? data['vote_average'];
    final fecha = data['fecha_salida']?.toString() ?? data['release_date']?.toString() ?? '';
    final year = fecha.length >= 4 ? fecha.substring(0, 4) : '';
    final imdbId = (data['imdb_id'] ?? '').toString();
    final poster = optimizeTmdbUrl(
      (data['poster'] ?? data['poster_path'])?.toString(),
      size: 'w500',
    );
    final logo = optimizeTmdbUrl(
      (data['logo'] ?? data['logo_path'])?.toString(),
      size: 'w500',
    );
    final backdrop = optimizeTmdbUrl(
      (data['backdrop'] ?? data['backdrop_path'])?.toString(),
      size: 'w780',
    );
    final genres = data['genres'] ?? data['generos'];
    final List<String> genreNames = [];
    if (genres is List) {
      for (final g in genres) {
        if (g is String && g.isNotEmpty) {
          genreNames.add(g);
        } else if (g is Map && g['name'] != null) {
          genreNames.add(g['name'].toString());
        }
      }
    }
    final runtime = data['runtime'] ?? data['duracion'];
    final director = data['director']?.toString();
    final idioma = (data['idioma'] ?? data['original_language'] ?? data['language'] ?? 'es')
        .toString()
        .toUpperCase();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.08,
        vertical: size.height * 0.06,
      ),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.goBack ||
                event.logicalKey == LogicalKeyboardKey.browserBack) {
              Navigator.pop(context);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: size.width * 0.84,
            height: size.height * 0.88,
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E0E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Fondo con backdrop difuminado
                if (backdrop.isNotEmpty)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.22,
                      child: CachedNetworkImage(
                        imageUrl: backdrop,
                        fit: BoxFit.cover,
                        memCacheWidth: 900,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                // Gradiente para legibilidad
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0E0E0E).withValues(alpha: 0.92),
                          const Color(0xFF0E0E0E).withValues(alpha: 0.97),
                          const Color(0xFF0A0A0A),
                        ],
                      ),
                    ),
                  ),
                ),

                // Contenido principal
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Poster lateral
                    if (poster.isNotEmpty)
                      SizedBox(
                        width: size.width * 0.24,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: poster,
                              fit: BoxFit.cover,
                              memCacheWidth: 480,
                              placeholder: (_, __) => const ColoredBox(color: Color(0xFF161616)),
                              errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF161616)),
                            ),
                            // Degradado sutil en el borde derecho del poster
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              width: 28,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.transparent,
                                      const Color(0xFF0E0E0E).withValues(alpha: 0.7),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Info
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 28, 28, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: logo/título + botón cerrar
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (logo.isNotEmpty)
                                        CachedNetworkImage(
                                          imageUrl: logo,
                                          height: 52,
                                          fit: BoxFit.contain,
                                          alignment: Alignment.centerLeft,
                                          memCacheHeight: 110,
                                          errorWidget: (_, __, ___) => Text(
                                            tituloContenido,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w800,
                                              height: 1.15,
                                            ),
                                          ),
                                        )
                                      else
                                        Text(
                                          tituloContenido,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            height: 1.15,
                                          ),
                                        ),
                                      if (tituloCapitulo != null || capituloFmt != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          [
                                            if (capituloFmt != null) capituloFmt,
                                            if (tituloCapitulo != null) tituloCapitulo,
                                          ].whereType<String>().join(' · '),
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.55),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Botón cerrar (recibe el foco automáticamente)
                                _CloseButton(accentColor: accentColor),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // Chips
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (year.isNotEmpty) _chip(year),
                                if (runtime != null) _chip('$runtime min'),
                                _chip(idioma),
                                _chip(tipo == 'tv' ? 'Serie' : 'Película'),
                                ...genreNames.take(5).map(_chip),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Ratings
                            Row(
                              children: [
                                if (calificacion != null)
                                  _ratingBadge(
                                    icon: Icons.star_rounded,
                                    label: (calificacion is num)
                                        ? calificacion.toStringAsFixed(1)
                                        : '$calificacion',
                                    source: 'TMDB',
                                    color: const Color(0xFF01D277),
                                  ),
                                if (data['imdb_rating'] != null || data['vote_imdb'] != null) ...[
                                  const SizedBox(width: 12),
                                  _ratingBadge(
                                    icon: Icons.movie_filter_rounded,
                                    label: '${data['imdb_rating'] ?? data['vote_imdb']}',
                                    source: 'IMDb',
                                    color: const Color(0xFFF5C518),
                                  ),
                                ],
                                if (imdbId.isNotEmpty) ...[
                                  const SizedBox(width: 14),
                                  Text(
                                    imdbId,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.35),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            if (director != null && director.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Director  ',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.4),
                                        fontSize: 13,
                                      ),
                                    ),
                                    TextSpan(
                                      text: director,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 22),

                            // Sinopsis
                            Text(
                              'Sinopsis',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Text(
                                  overview,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.62),
                                    height: 1.55,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _ratingBadge({
    required IconData icon,
    required String label,
    required String source,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            source,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de cerrar con foco prioritario y estilo premium
class _CloseButton extends StatefulWidget {
  final Color accentColor;
  const _CloseButton({required this.accentColor});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  final FocusNode _node = FocusNode();

  @override
  void initState() {
    super.initState();
    // Asegura que el foco quede en la X al abrir el modal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.requestFocus();
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.18),
                  width: 1.5,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.close_rounded,
                size: 22,
                color: hasFocus ? Colors.black : Colors.white.withValues(alpha: 0.85),
              ),
            ),
          );
        },
      ),
    );
  }
}