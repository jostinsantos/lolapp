import '../models/tv_channel_models.dart';

/// Parser de listas M3U / M3U8 (ExtM3U)
class M3uParser {
  /// Parsea el contenido de una lista M3U y devuelve canales.
  static List<TvChannel> parse(String content, {String? sourceName}) {
    final lines = content.split('\n');
    final channels = <TvChannel>[];

    String? currentName;
    String? currentLogo;
    String? currentGroup;
    String? currentCountry;
    String? currentLanguage;
    final extra = <String, String>{};

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        // Reset
        currentName = null;
        currentLogo = null;
        currentGroup = null;
        currentCountry = null;
        currentLanguage = null;
        extra.clear();

        // Ejemplo:
        // #EXTINF:-1 tvg-id="..." tvg-logo="..." group-title="News",CNN
        final commaIdx = line.lastIndexOf(',');
        if (commaIdx != -1 && commaIdx < line.length - 1) {
          currentName = line.substring(commaIdx + 1).trim();
        }

        final attrsPart =
            commaIdx != -1 ? line.substring(0, commaIdx) : line;

        currentLogo = _extractAttr(attrsPart, 'tvg-logo') ??
            _extractAttr(attrsPart, 'logo');
        currentGroup = _extractAttr(attrsPart, 'group-title') ??
            _extractAttr(attrsPart, 'group');
        currentCountry = _extractAttr(attrsPart, 'tvg-country') ??
            _extractAttr(attrsPart, 'country');
        currentLanguage = _extractAttr(attrsPart, 'tvg-language') ??
            _extractAttr(attrsPart, 'language');

        final tvgId = _extractAttr(attrsPart, 'tvg-id');
        if (tvgId != null) extra['tvg-id'] = tvgId;
      } else if (!line.startsWith('#')) {
        // URL del stream
        final url = line.trim();
        if (url.isEmpty) continue;

        final name = (currentName?.isNotEmpty == true)
            ? currentName!
            : 'Canal ${channels.length + 1}';

        final id = '${sourceName ?? 'm3u'}_${url.hashCode.abs()}';

        channels.add(TvChannel(
          id: id,
          name: name,
          url: url,
          logo: currentLogo,
          group: currentGroup ?? sourceName ?? 'General',
          country: currentCountry,
          language: currentLanguage,
          extra: extra.isEmpty ? null : Map<String, dynamic>.from(extra),
        ));

        // Reset para el siguiente
        currentName = null;
        currentLogo = null;
        currentGroup = null;
      }
    }

    return channels;
  }

  /// Agrupa canales por categoría (group)
  static List<TvCategory> groupByCategory(List<TvChannel> channels) {
    final map = <String, List<TvChannel>>{};
    for (final ch in channels) {
      final key = (ch.group?.trim().isNotEmpty == true)
          ? ch.group!.trim()
          : 'General';
      map.putIfAbsent(key, () => []).add(ch);
    }

    final categories = map.entries
        .map((e) => TvCategory(name: e.key, channels: e.value))
        .toList();

    // Ordenar: General al final, resto alfabético
    categories.sort((a, b) {
      if (a.name == 'General') return 1;
      if (b.name == 'General') return -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return categories;
  }

  static String? _extractAttr(String line, String key) {
    // Busca key="value" o key='value'
    final re = RegExp(
      '$key\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    );
    final m = re.firstMatch(line);
    if (m != null) return m.group(1);

    final re2 = RegExp(
      "$key\\s*=\\s*'([^']*)'",
      caseSensitive: false,
    );
    final m2 = re2.firstMatch(line);
    return m2?.group(1);
  }
}
