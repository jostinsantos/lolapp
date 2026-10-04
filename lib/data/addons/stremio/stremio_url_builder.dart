/// Construcción de URLs del protocolo Stremio (igual que Nuvio AddonTransportUrls).

String stremioTransportBaseUrl(String manifestUrl) {
  final noQuery = manifestUrl.split('?').first;
  if (noQuery.endsWith('/manifest.json')) {
    return noQuery.substring(0, noQuery.length - '/manifest.json'.length);
  }
  if (noQuery.endsWith('manifest.json')) {
    return noQuery.substring(0, noQuery.length - 'manifest.json'.length);
  }
  // Si el usuario pegó solo la base del addon
  return noQuery.endsWith('/') ? noQuery.substring(0, noQuery.length - 1) : noQuery;
}

String _encodePathSegment(String id) {
  final bytes = id.codeUnits;
  final sb = StringBuffer();
  for (final b in bytes) {
    final c = String.fromCharCode(b);
    final ok = (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
        c == '-' ||
        c == '_' ||
        c == '.' ||
        c == '~';
    if (ok) {
      sb.write(c);
    } else {
      sb.write('%');
      sb.write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return sb.toString();
}

/// resource: catalog | meta | stream | subtitles
/// type: movie | series | ...
/// id: id del catálogo o del meta
/// extraPath: ej. "skip=100" o "search=batman" o "genre=Action"
String buildStremioResourceUrl({
  required String manifestUrl,
  required String resource,
  required String type,
  required String id,
  String? extraPathSegment,
}) {
  final base = stremioTransportBaseUrl(manifestUrl);
  final encodedId = _encodePathSegment(id);
  final query = manifestUrl.contains('?')
      ? '?${manifestUrl.substring(manifestUrl.indexOf('?') + 1)}'
      : '';

  final path = (extraPathSegment == null || extraPathSegment.isEmpty)
      ? '$base/$resource/$type/$encodedId.json'
      : '$base/$resource/$type/$encodedId/$extraPathSegment.json';

  return path + query;
}

String buildCatalogUrl({
  required String manifestUrl,
  required String type,
  required String catalogId,
  int? skip,
  String? search,
  String? genre,
}) {
  final extras = <String>[];
  if (search != null && search.trim().isNotEmpty) {
    extras.add('search=${Uri.encodeComponent(search.trim())}');
  }
  if (genre != null && genre.trim().isNotEmpty) {
    extras.add('genre=${Uri.encodeComponent(genre.trim())}');
  }
  if (skip != null && skip > 0) {
    extras.add('skip=$skip');
  }
  final extraSeg = extras.isEmpty ? null : extras.join('&');
  return buildStremioResourceUrl(
    manifestUrl: manifestUrl,
    resource: 'catalog',
    type: type,
    id: catalogId,
    extraPathSegment: extraSeg,
  );
}

String normalizeManifestUrl(String input) {
  var u = input.trim();
  if (u.isEmpty) return u;
  if (!u.startsWith('http://') && !u.startsWith('https://')) {
    u = 'https://$u';
  }
  // Si no termina en manifest.json, añadir
  final noQ = u.split('?').first;
  if (!noQ.endsWith('manifest.json') && !noQ.endsWith('.json')) {
    u = noQ.endsWith('/') ? '${noQ}manifest.json' : '$noQ/manifest.json';
    if (input.contains('?')) {
      u = '$u?${input.split('?').last}';
    }
  }
  return u;
}
