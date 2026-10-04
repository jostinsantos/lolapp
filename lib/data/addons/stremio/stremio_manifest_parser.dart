import 'dart:convert';
import 'stremio_models.dart';
import 'stremio_url_builder.dart';

/// Parsea manifest.json del protocolo Stremio (compatible Nuvio).
class StremioManifestParser {
  static StremioManifest parse(String manifestUrl, String payload) {
    final root = jsonDecode(payload) as Map<String, dynamic>;
    final defaultTypes =
        (root['types'] as List? ?? []).map((e) => e.toString()).toList();
    final defaultPrefixes =
        (root['idPrefixes'] as List? ?? []).map((e) => e.toString()).toList();

    final id = (root['id'] ?? '').toString();
    final name = (root['name'] ?? '').toString();
    final version = (root['version'] ?? '0').toString();
    if (id.isEmpty || name.isEmpty) {
      throw FormatException('Manifest inválido: faltan id o name');
    }

    return StremioManifest(
      id: id,
      name: name,
      description: (root['description'] ?? '').toString(),
      version: version,
      logoUrl: _resolveLogo(manifestUrl, root['logo']?.toString()),
      resources: _parseResources(root['resources'], defaultTypes, defaultPrefixes),
      types: defaultTypes,
      idPrefixes: defaultPrefixes,
      catalogs: _parseCatalogs(root['catalogs']),
      behaviorHints: _parseHints(root['behaviorHints']),
      transportUrl: manifestUrl,
    );
  }

  static List<StremioResource> _parseResources(
    dynamic raw,
    List<String> defaultTypes,
    List<String> defaultPrefixes,
  ) {
    if (raw is! List) return [];
    final out = <StremioResource>[];
    for (final r in raw) {
      if (r is String) {
        out.add(StremioResource(
          name: r,
          types: defaultTypes,
          idPrefixes: defaultPrefixes,
        ));
      } else if (r is Map) {
        final m = Map<String, dynamic>.from(r);
        final n = (m['name'] ?? '').toString();
        if (n.isEmpty) continue;
        final types = (m['types'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final prefixes = (m['idPrefixes'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        out.add(StremioResource(
          name: n,
          types: types.isEmpty ? defaultTypes : types,
          idPrefixes: prefixes.isEmpty ? defaultPrefixes : prefixes,
        ));
      }
    }
    return out;
  }

  static List<StremioCatalog> _parseCatalogs(dynamic raw) {
    if (raw is! List) return [];
    final out = <StremioCatalog>[];
    for (final c in raw) {
      if (c is! Map) continue;
      final m = Map<String, dynamic>.from(c);
      final type = (m['type'] ?? '').toString();
      final id = (m['id'] ?? '').toString();
      if (type.isEmpty || id.isEmpty) continue;
      final name = (m['name'] ?? id).toString();
      final extras = <StremioExtra>[];
      final extraRaw = m['extra'];
      if (extraRaw is List) {
        for (final e in extraRaw) {
          if (e is! Map) continue;
          final em = Map<String, dynamic>.from(e);
          final en = (em['name'] ?? '').toString();
          if (en.isEmpty) continue;
          extras.add(StremioExtra(
            name: en,
            isRequired: em['isRequired'] == true,
            options: (em['options'] as List? ?? [])
                .map((x) => x.toString())
                .toList(),
            optionsLimit: (em['optionsLimit'] as num?)?.toInt(),
          ));
        }
      }
      // Compat: extraSupported / extraRequired (formato antiguo Stremio)
      final supported = m['extraSupported'] as List?;
      if (supported != null) {
        for (final s in supported) {
          final n = s.toString();
          if (n.isEmpty || extras.any((e) => e.name == n)) continue;
          extras.add(StremioExtra(name: n));
        }
      }
      out.add(StremioCatalog(type: type, id: id, name: name, extra: extras));
    }
    return out;
  }

  static StremioBehaviorHints _parseHints(dynamic raw) {
    if (raw is! Map) return const StremioBehaviorHints();
    final m = Map<String, dynamic>.from(raw);
    return StremioBehaviorHints(
      configurable: m['configurable'] == true,
      configurationRequired: m['configurationRequired'] == true,
      adult: m['adult'] == true,
      p2p: m['p2p'] == true,
    );
  }

  static String? _resolveLogo(String manifestUrl, String? logo) {
    if (logo == null || logo.isEmpty) return null;
    if (logo.startsWith('http://') || logo.startsWith('https://')) return logo;
    final base = stremioTransportBaseUrl(manifestUrl);
    if (logo.startsWith('/')) return '$base$logo';
    return '$base/$logo';
  }
}

/// Parsea respuesta de /catalog/{type}/{id}.json
class StremioCatalogParser {
  static StremioCatalogPage parse(String payload, {int? maxItems, int? currentSkip}) {
    final root = jsonDecode(payload) as Map<String, dynamic>;
    final metas = root['metas'] as List? ?? [];
    final items = <StremioMeta>[];
    final seen = <String>{};

    for (final e in metas) {
      if (maxItems != null && items.length >= maxItems) break;
      if (e is! Map) continue;
      final meta = StremioMeta.fromJson(Map<String, dynamic>.from(e));
      if (meta.id.isEmpty || meta.name.isEmpty) continue;
      final key = '${meta.type}:${meta.id}';
      if (!seen.add(key)) continue;
      items.add(meta);
    }

    // Heurística paginación: si trajo muchos ítems, permitir skip
    int? nextSkip;
    if (metas.length >= 20) {
      final base = currentSkip ?? 0;
      nextSkip = base + metas.length;
    }

    return StremioCatalogPage(
      items: items,
      rawCount: metas.length,
      nextSkip: nextSkip,
    );
  }
}
