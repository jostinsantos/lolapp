import 'package:flutter/material.dart';
import '../config_shared.dart';
class DescargasSection extends StatelessWidget {
  final bool enableDownloads;
  final bool showDownloadButtonMain;
  final bool autoDirectDownload;
  final IdiomaPred downloadLanguage;

  /// Cantidad máxima de descargas simultáneas (1–5)
  final int maxConcurrentDownloads;

  final ValueChanged<bool> onEnableDownloadsChanged;
  final ValueChanged<bool> onShowDownloadButtonMainChanged;
  final ValueChanged<bool> onAutoDirectDownloadChanged;
  final ValueChanged<IdiomaPred> onDownloadLanguageChanged;
  final ValueChanged<int> onMaxConcurrentDownloadsChanged;

  const DescargasSection({
    super.key,
    required this.enableDownloads,
    required this.showDownloadButtonMain,
    required this.autoDirectDownload,
    required this.downloadLanguage,
    required this.maxConcurrentDownloads,
    required this.onEnableDownloadsChanged,
    required this.onShowDownloadButtonMainChanged,
    required this.onAutoDirectDownloadChanged,
    required this.onDownloadLanguageChanged,
    required this.onMaxConcurrentDownloadsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final concurrent = maxConcurrentDownloads.clamp(1, 5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Habilitar descargas
        _SwitchTile(
          title: 'Habilitar descargas',
          subtitle:
              'Activa o desactiva por completo el sistema de descargas de la app',
          value: enableDownloads,
          onChanged: onEnableDownloadsChanged,
        ),
        const SizedBox(height: 10),

        // 2. Botón en menú principal
        _SwitchTile(
          title: 'Botón de descarga en menú principal',
          subtitle:
              'Muestra el botón de descargas en la barra / menú principal',
          value: showDownloadButtonMain,
          enabled: enableDownloads,
          onChanged: onShowDownloadButtonMainChanged,
        ),
        const SizedBox(height: 10),

        // 3. Descarga directa automática
        _SwitchTile(
          title: 'Descarga directa automática',
          subtitle:
              'Si hay un enlace directo disponible, inicia la descarga sin preguntar',
          value: autoDirectDownload,
          enabled: enableDownloads,
          onChanged: onAutoDirectDownloadChanged,
        ),
        const SizedBox(height: 16),

        // 4. Cantidad de descargas a la vez
        Opacity(
          opacity: enableDownloads ? 1 : 0.45,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: kCardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Descargas a la vez',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$concurrent',
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Máximo de descargas simultáneas (1–5). Más hilos = más uso de red y CPU.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF22C55E),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                    thumbColor: const Color(0xFF22C55E),
                    overlayColor:
                        const Color(0xFF22C55E).withValues(alpha: 0.2),
                    valueIndicatorColor: const Color(0xFF22C55E),
                    trackHeight: 3.5,
                  ),
                  child: Slider(
                    value: concurrent.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$concurrent',
                    onChanged: enableDownloads
                        ? (v) => onMaxConcurrentDownloadsChanged(v.round())
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (i) {
                      final n = i + 1;
                      final selected = n == concurrent;
                      return Text(
                        '$n',
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFF22C55E)
                              : Colors.white.withValues(alpha: 0.35),
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 5. Idioma principal de descarga
        Text(
          'Idioma principal de descarga',
          style: TextStyle(
            color: Colors.white.withValues(alpha: enableDownloads ? 0.95 : 0.4),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Se priorizará este idioma al buscar enlaces de descarga',
          style: TextStyle(
            color: Colors.white.withValues(alpha: enableDownloads ? 0.55 : 0.3),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),

        ...IdiomaPred.values.map((idioma) {
          final selected = downloadLanguage == idioma;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enableDownloads
                    ? () => onDownloadLanguageChanged(idioma)
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                        : kCardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF22C55E).withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: selected
                            ? const Color(0xFF22C55E)
                            : Colors.white.withValues(
                                alpha: enableDownloads ? 0.4 : 0.25,
                              ),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          idioma.label,
                          style: TextStyle(
                            color: enableDownloads
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeColor: const Color(0xFF22C55E),
        title: Text(
          title,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.4),
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: enabled ? 0.55 : 0.3),
            fontSize: 13,
            height: 1.3,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
    );
  }
}