import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config_shared.dart';
class PlayerSection {
  final VoidCallback refresh;
  
  // Configuraciones del player
  final bool subsAlInicio;
  final SubSize subSize;
  final SubHeight subHeight;
  final bool idmDownloadEnabled;
  final bool miniPlayerEnabled;

  // Callbacks
  final ValueChanged<bool> onSubsChanged;
  final ValueChanged<SubSize> onSubSizeChanged;
  final ValueChanged<SubHeight> onSubHeightChanged;
  final ValueChanged<bool> onIdmChanged;
  final ValueChanged<bool> onMiniPlayerChanged;

  PlayerSection({
    required this.refresh,
    required this.subsAlInicio,
    required this.subSize,
    required this.subHeight,
    required this.idmDownloadEnabled,
    required this.onSubsChanged,
    required this.onSubSizeChanged,
    required this.onSubHeightChanged,
    required this.onIdmChanged,
    required this.onMiniPlayerChanged,
    required this.miniPlayerEnabled,
  });

  List<Widget> build() {
    return [
      _sectionHeader('MINI-PLAYER'),
      _buildToggleCard(
        title: 'Mini-player al minimizar',
        subtitleOn: 'Al minimizar sigue reproduciendo abajo',
        subtitleOff: 'Al salir se detiene la reproducción',
        enabled: miniPlayerEnabled,
        icon: Icons.picture_in_picture_alt_rounded,
        onChanged: (v) {
          onMiniPlayerChanged(v);
          refresh();
        },
      ),
      const SizedBox(height: 16),
      _sectionHeader('SUBTÍTULOS'),
      _buildToggleCard(
        title: 'Subtítulos al iniciar',
        subtitleOn: 'Se activan automáticamente',
        subtitleOff: 'Desactivados al iniciar',
        enabled: subsAlInicio,
        onChanged: (v) {
          onSubsChanged(v);
          refresh();
        },
        icon: Icons.closed_caption_rounded,
      ),
      _buildSubSizeSelector(),
      _buildSubHeightSelector(),
      _SubtitleStyleToggles(refresh: refresh),
      
      _sectionHeader('CONTROLES'),
      _buildToggleCard(
        title: 'Descarga por IDM',
        subtitleOn: 'Botón de descarga visible',
        subtitleOff: 'Botón de descarga oculto',
        enabled: idmDownloadEnabled,
        onChanged: (v) {
          onIdmChanged(v);
          refresh();
        },
        icon: Icons.download_rounded,
        accent: const Color(0xFF06B6D4),
      ),
    ];
  }

  // SELECTOR DE TAMAÑO DE SUBTÍTULOS
  Widget _buildSubSizeSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tamaño de subtítulos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: SubSize.values.map((s) {
              final isSel = subSize == s;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () {
                      onSubSizeChanged(s);
                      refresh();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSel
                            ? kAccentColor.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSel ? kAccentColor : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isSel)
                            Icon(
                              Icons.check_circle_rounded,
                              color: kAccentColor,
                              size: 14,
                            ),
                          if (isSel) const SizedBox(width: 4),
                          Text(
                            s.label,
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // Vista previa del tamaño
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Vista previa',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: kAccentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Subtítulo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: subSize.size * 0.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // SELECTOR DE ALTURA DE SUBTÍTULOS
  Widget _buildSubHeightSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Altura de subtítulos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: SubHeight.values.map((h) {
              final isSel = subHeight == h;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () {
                      onSubHeightChanged(h);
                      refresh();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSel
                            ? kAccentColor.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSel ? kAccentColor : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isSel)
                            Icon(
                              Icons.check_circle_rounded,
                              color: kAccentColor,
                              size: 14,
                            ),
                          if (isSel) const SizedBox(width: 4),
                          Text(
                            h.label,
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // Vista previa de la altura
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Vista previa',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.only(
                    bottom: subHeight.bottomPadding * 0.08,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Subtítulo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitleOn,
    required String subtitleOff,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    Color accent = kAccentColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: enabled ? accent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: enabled ? accent : Colors.white70, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled ? subtitleOn : subtitleOff,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: accent,
              activeTrackColor: accent.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}


/// Toggles de estilo de subtítulos (fondo, contorno, color de fuente).
class _SubtitleStyleToggles extends StatefulWidget {
  final VoidCallback refresh;
  const _SubtitleStyleToggles({required this.refresh});

  @override
  State<_SubtitleStyleToggles> createState() => _SubtitleStyleTogglesState();
}

class _SubtitleStyleTogglesState extends State<_SubtitleStyleToggles> {
  bool _fondo = false;
  bool _contorno = true;
  String _colorHex = '#FFFFFF';
  bool _loaded = false;

  static const _colors = <(String, String)>[
    ('#FFFFFF', 'Blanco'),
    ('#FFE566', 'Amarillo'),
    ('#7CFF7C', 'Verde'),
    ('#7CD0FF', 'Azul'),
    ('#FF9E7C', 'Naranja'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _fondo = prefs.getBool('subtitulo_fondo') ?? false;
      _contorno = prefs.getBool('subtitulo_contorno') ?? true;
      _colorHex = prefs.getString('subtitulo_color') ?? '#FFFFFF';
      _loaded = true;
    });
  }

  Future<void> _setFondo(bool v) async {
    setState(() => _fondo = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitulo_fondo', v);
    widget.refresh();
  }

  Future<void> _setContorno(bool v) async {
    setState(() => _contorno = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitulo_contorno', v);
    widget.refresh();
  }

  Future<void> _setColor(String hex) async {
    setState(() => _colorHex = hex);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subtitulo_color', hex);
    widget.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Column(
      children: [
        _toggle(
          title: 'Fondo de subtítulos',
          subtitleOn: 'Caja semitransparente detrás del texto',
          subtitleOff: 'Sin fondo',
          enabled: _fondo,
          icon: Icons.rectangle_rounded,
          onChanged: _setFondo,
        ),
        _toggle(
          title: 'Contorno de subtítulos',
          subtitleOn: 'Borde negro alrededor del texto',
          subtitleOff: 'Sin contorno',
          enabled: _contorno,
          icon: Icons.border_style_rounded,
          onChanged: _setContorno,
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: kCardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.format_color_text_rounded,
                      color: kAccentColor, size: 22),
                  const SizedBox(width: 12),
                  const Text(
                    'Color de fuente',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _colors.map((c) {
                  final hex = c.$1;
                  final label = c.$2;
                  final selected =
                      _colorHex.toUpperCase() == hex.toUpperCase();
                  final color = Color(
                      int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
                  return GestureDetector(
                    onTap: () => _setColor(hex),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? kAccentColor.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? kAccentColor : Colors.white24,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggle({
    required String title,
    required String subtitleOn,
    required String subtitleOff,
    required bool enabled,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: enabled ? kAccentColor : Colors.white38),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          enabled ? subtitleOn : subtitleOff,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
          ),
        ),
        trailing: Switch(
          value: enabled,
          activeColor: kAccentColor,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
