import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/addon.dart';

/// Carga y analiza manifests JS (estilo Nuvio) y JSON (estilo Stremio).
/// Soporta paquetes de scrapers (manifest con "scrapers") y GitHub user/repo.
class AddonLoader {
  static const _uuid = Uuid();

  /// Descarga desde URL y detecta tipo.
  Future<AddonManifest> fromUrl(String url) async {
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('No se pudo descargar el addon (${res.statusCode})');
    }
    final body = res.body;
    final lower = url.toLowerCase();
    if (lower.endsWith('.json') || body.trimLeft().startsWith('{')) {
      // Si es un paquete con scrapers, no instalar como addon único
      final map = jsonDecode(body) as Map<String, dynamic>;
      if (map['scrapers'] is List) {
        throw Exception(
          'Esta URL es un paquete de fuentes. Usa "Añadir paquete" en la pestaña Fuentes.',
        );
      }
      var manifest =
          fromJsonString(body, sourceUrl: url, origin: AddonOrigin.url);

      // Descargar entry JS (index.js) si el manifest lo declara
      final entry = (map['entry'] ?? map['main'] ?? 'index.js').toString();
      if (entry.toLowerCase().endsWith('.js')) {
        try {
          final base = url.contains('/')
              ? url.substring(0, url.lastIndexOf('/') + 1)
              : url;
          final entryUrl = entry.startsWith('http') ? entry : '$base$entry';
          final jsRes = await http
              .get(Uri.parse(entryUrl))
              .timeout(const Duration(seconds: 20));
          if (jsRes.statusCode == 200 && jsRes.body.trim().isNotEmpty) {
            manifest = manifest.copyWith(
              rawCode: jsRes.body,
              sourceUrl: entryUrl,
            );
          }
        } catch (_) {}
      }
      return manifest;
    }
    return fromJsString(body, sourceUrl: url, origin: AddonOrigin.url);
  }

  /// Parsea texto pegado (JSON o JS).
  Future<AddonManifest> fromPasted(String text) async {
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) {
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      if (map['scrapers'] is List) {
        throw Exception(
          'Este JSON es un paquete de fuentes. Usa "Añadir paquete".',
        );
      }
      return fromJsonString(trimmed, origin: AddonOrigin.pasted);
    }
    return fromJsString(trimmed, origin: AddonOrigin.pasted);
  }

  // ── Paquetes estilo Nuvio ─────────────────────────────────

  /// Descarga y parsea un manifest de paquete (con lista "scrapers").
  Future<SourcePackage> fetchPackage(String manifestUrl) async {
    final res = await http
        .get(Uri.parse(manifestUrl))
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception('No se pudo descargar el paquete (${res.statusCode})');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (map['scrapers'] is! List) {
      throw Exception(
        'El JSON no es un paquete de scrapers (falta "scrapers").',
      );
    }
    final scrapers = (map['scrapers'] as List)
        .map((e) => PackageScraper.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return SourcePackage(
      manifestUrl: manifestUrl,
      name: map['name'] as String? ?? 'Repo',
      version: map['version'] as String? ?? '1.0.0',
      description: map['description'] as String?,
      author: map['author'] as String?,
      scrapers: scrapers,
      addedAt: DateTime.now(),
      lastRefreshed: DateTime.now(),
    );
  }

  /// Resuelve la URL del archivo JS de un scraper a partir del manifestUrl del paquete.
  String resolveScraperUrl(String packageManifestUrl, String filename) {
    final uri = Uri.parse(packageManifestUrl);
    final segments = List<String>.from(uri.pathSegments);
    if (segments.isNotEmpty && segments.last.toLowerCase().endsWith('.json')) {
      segments.removeLast();
    }
    final fileParts = filename.split('/');
    final base = uri.replace(pathSegments: [...segments, ...fileParts]);
    return base.toString();
  }

  /// Descarga e instala un scraper individual de un paquete Nuvio.
  Future<AddonManifest> installScraperFromPackage({
    required SourcePackage package,
    required PackageScraper scraper,
  }) async {
    final fileUrl = resolveScraperUrl(package.manifestUrl ?? '', scraper.filename);
    final res =
        await http.get(Uri.parse(fileUrl)).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception(
        'No se pudo descargar ${scraper.filename} (${res.statusCode})',
      );
    }
    final code = res.body;
    final exports = _detectExports(code);

    return AddonManifest(
      id: scraper.id,
      name: scraper.name,
      version: scraper.version,
      description: scraper.description.isNotEmpty
          ? scraper.description
          : 'Fuente desde ${package.name}',
      types: [AddonType.source],
      logo: scraper.logo,
      author: scraper.author ?? package.author,
      resources: const ['stream'],
      exports: exports.isEmpty ? const ['getStreams'] : exports,
      rawCode: code,
      sourceUrl: fileUrl,
      origin: AddonOrigin.package,
      enabled: scraper.enabled,
      packageUrl: package.manifestUrl ?? '',
      supportedTypes: scraper.supportedTypes,
      formats: scraper.formats,
      contentLanguage: scraper.contentLanguage,
      extra: {
        ...scraper.extra,
        'packageName': package.name,
        'packageVersion': package.version,
        'filename': scraper.filename,
        'hasSettings': scraper.hasSettings,
      },
      installedAt: DateTime.now(),
    );
  }

  // ── GitHub user/repo (catálogos y funciones, estilo Kino) ─

  /// Instala catálogo o función desde GitHub user/repo.
  /// Busca manifest.json o addon.json en la raíz (o path) del repo.
  /// Formato propio esperado:
  /// {
  ///   "id", "name", "version", "description", "type": "catalog"|"function",
  ///   "logo", "author",
  ///   "placements": ["player","contentPage",...],  // solo function
  ///   "requiredFields": ["tmdbId","type","season","episode"],
  ///   "entry": "index.js" | "main.js"
  /// }
  Future<AddonManifest> fromGitHub(
    String input, {
    required AddonType expectedType,
    List<FunctionPlacement>? placements,
    List<String>? requiredFields,
    FunctionKind? functionKind,
  }) async {
    final addr = GitHubAddress.parse(input);
    if (addr == null) {
      throw Exception(
        'Dirección inválida. Usa user/repo o user/repo/path[@branch]',
      );
    }

    // Descargar manifests en paralelo (máx ~8s total)
    Map<String, dynamic>? manifest;
    String? manifestFile;
    final manifestCandidates = ['manifest.json', 'addon.json', 'catalog.json', 'package.json'];
    final manifestFutures = manifestCandidates.map((file) async {
      try {
        final url = addr.rawUrl(file);
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && res.body.trimLeft().startsWith('{')) {
          return (file: file, data: jsonDecode(res.body) as Map<String, dynamic>);
        }
      } catch (_) {}
      return null;
    });
    final manifestResults = await Future.wait(manifestFutures);
    for (final r in manifestResults) {
      if (r == null) continue;
      // Preferir manifest.json / addon.json sobre package.json de monorepo
      if (manifest == null ||
          r.file == 'manifest.json' ||
          r.file == 'addon.json' ||
          r.file == 'catalog.json') {
        manifest = r.data;
        manifestFile = r.file;
        if (r.file == 'manifest.json' || r.file == 'addon.json') break;
      }
    }

    final entry = (manifest?['entry'] as String?) ??
        (manifest?['main'] as String?) ??
        (manifest?['filename'] as String?) ??
        'index.js';

    String? code;
    String? codeUrl;
    // Descargar entry + fallbacks en paralelo
    final codeFiles = <String>{
      if (entry.toLowerCase().endsWith('.js')) entry,
      'index.js',
      'main.js',
      'addon.js',
    }.toList();
    final codeFutures = codeFiles.map((f) async {
      try {
        final url = addr.rawUrl(f);
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          return (file: f, url: url, body: res.body);
        }
      } catch (_) {}
      return null;
    });
    final codeResults = await Future.wait(codeFutures);
    // Preferir el entry declarado
    for (final r in codeResults) {
      if (r == null) continue;
      if (r.file == entry) {
        code = r.body;
        codeUrl = r.url;
        break;
      }
    }
    if (code == null) {
      for (final r in codeResults) {
        if (r == null) continue;
        code = r.body;
        codeUrl = r.url;
        break;
      }
    }

    final id = (manifest?['id'] as String?) ??
        '${addr.owner}-${addr.repo}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]+'), '-');
    final name = (manifest?['name'] as String?) ?? '${addr.owner}/${addr.repo}';
    final version = (manifest?['version'] as String?) ?? '1.0.0';
    final description = (manifest?['description'] as String?) ??
        'Addon desde GitHub ${addr.canonical}';
    final logo = manifest?['logo'] as String?;
    final author = (manifest?['author'] as String?) ?? addr.owner;

    // El tipo pedido por la UI (Fuente/Catálogo) manda; el manifest solo refuerza.
    final typeStr = (manifest?['type'] as String?)?.toLowerCase() ?? '';
    final typesList = (manifest?['types'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        const <String>[];
    AddonType type = expectedType;
    // Solo cambiar si expectedType no era fuente/catálogo explícito de instalación
    // (siempre lo es desde App1). Preferir expectedType.
    if (expectedType == AddonType.source || expectedType == AddonType.catalog) {
      type = expectedType;
    } else if (typeStr.contains('catalog') || typesList.any((t) => t.contains('catalog'))) {
      type = AddonType.catalog;
    } else if (typeStr.contains('function') || typeStr.contains('subtitle')) {
      type = AddonType.function;
    } else if (typeStr.contains('source') || typeStr.contains('stream')) {
      type = AddonType.source;
    }

    List<FunctionPlacement> place = placements ?? [];
    if (place.isEmpty && manifest?['placements'] is List) {
      place = (manifest!['placements'] as List)
          .map((e) => FunctionPlacement.values.firstWhere(
                (p) => p.name == e.toString(),
                orElse: () => FunctionPlacement.player,
              ))
          .toList();
    }
    if (place.isEmpty && type == AddonType.function) {
      // Heurística por exports
      final exp = code != null ? _detectExports(code) : <String>[];
      if (exp.any((e) => e.toLowerCase().contains('sub'))) {
        place = [FunctionPlacement.player];
      } else {
        place = [FunctionPlacement.contentPage];
      }
    }

    final reqFields = requiredFields ??
        List<String>.from(manifest?['requiredFields'] ??
            manifest?['requires'] ??
            (type == AddonType.function
                ? ['tmdbId', 'type', 'title']
                : <String>[]));

    final exports = code != null ? _detectExports(code) : <String>[];
    final resources = <String>[];
    if (type == AddonType.catalog) {
      resources.addAll(['catalog', 'meta']);
    } else if (type == AddonType.source) {
      resources.add('stream');
    } else if (type == AddonType.function) {
      final kind = functionKind ?? FunctionKind.generic;
      switch (kind) {
        case FunctionKind.subtitles:
          resources.add('subtitles');
        case FunctionKind.rating:
          resources.add('rating');
        case FunctionKind.posterTags:
          resources.add('posterTags');
        case FunctionKind.top10:
          resources.add('top10');
        case FunctionKind.mainSlider:
          resources.add('mainSlider');
        case FunctionKind.generic:
          resources.add('function');
      }
    }

    // Inferir functionKind desde manifest si no vino por parámetro
    FunctionKind resolvedKind = functionKind ?? FunctionKind.generic;
    if (functionKind == null && type == AddonType.function) {
      final kindStr = (manifest?['functionKind'] ?? manifest?['kind'] ?? '')
          .toString()
          .toLowerCase();
      resolvedKind = FunctionKind.values.firstWhere(
        (k) => k.name.toLowerCase() == kindStr,
        orElse: () {
          if (kindStr.contains('sub')) return FunctionKind.subtitles;
          if (kindStr.contains('rating') || kindStr.contains('score')) {
            return FunctionKind.rating;
          }
          if (kindStr.contains('tag') || kindStr.contains('badge')) {
            return FunctionKind.posterTags;
          }
          if (kindStr.contains('top')) return FunctionKind.top10;
          if (kindStr.contains('slider') || kindStr.contains('hero')) {
            return FunctionKind.mainSlider;
          }
          final exp = exports.map((e) => e.toLowerCase()).toList();
          if (exp.any((e) => e.contains('sub'))) return FunctionKind.subtitles;
          if (exp.any((e) => e.contains('rating'))) return FunctionKind.rating;
          return FunctionKind.generic;
        },
      );
      // Si no hay placements y hay kind, usar el default del kind
      if (place.isEmpty) {
        place = [resolvedKind.defaultPlacement];
      }
    }

    final schema = <AddonConfigField>[];
    dynamic rawSchema = manifest?['configSchema'] ??
        (manifest?['config'] is Map ? manifest!['config']['fields'] : null) ??
        manifest?['settings'];
    // Archivo separado config.schema.json (solo campos de configuración)
    if (rawSchema == null) {
      for (final f in ['config.schema.json', 'config.json', 'settings.json']) {
        try {
          final res = await http
              .get(Uri.parse(addr.rawUrl(f)))
              .timeout(const Duration(seconds: 6));
          if (res.statusCode == 200 && res.body.trimLeft().startsWith('{')) {
            final cfg = jsonDecode(res.body) as Map<String, dynamic>;
            rawSchema = cfg['fields'] ?? cfg['configSchema'] ?? cfg;
            break;
          }
        } catch (_) {}
      }
    }
    if (rawSchema is List) {
      for (final e in rawSchema) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          schema.add(AddonConfigField(
            key: (m['key'] ?? m['name'] ?? m['id'] ?? '').toString(),
            label: (m['label'] ?? m['title'] ?? m['name'] ?? m['key'] ?? '').toString(),
            type: (m['type'] ?? 'string').toString(),
            defaultValue: m['default']?.toString() ?? m['defaultValue']?.toString(),
            description: m['description']?.toString() ?? m['hint']?.toString(),
            options: (m['options'] is List)
                ? (m['options'] as List)
                    .map((o) {
                      if (o is Map) {
                        return (o['value'] ?? o['label'] ?? o['name'] ?? o)
                            .toString();
                      }
                      return o.toString();
                    })
                    .where((s) => s.toString().isNotEmpty)
                    .map((s) => s.toString())
                    .toList()
                : null,
          ));
        }
      }
    }

    return AddonManifest(
      id: id,
      name: name,
      version: version,
      description: description,
      types: [type],
      logo: logo,
      author: author,
      configSchema: schema,
      resources: resources,
      exports: exports,
      rawCode: code ?? (manifest != null ? jsonEncode(manifest) : null),
      sourceUrl: codeUrl ?? addr.rawUrl(manifestFile ?? 'manifest.json'),
      origin: AddonOrigin.github,
      enabled: true,
      githubCanonical: addr.canonical,
      supportedTypes: List<String>.from(
        manifest?['supportedTypes'] ?? ['movie', 'tv'],
      ),
      placements: place,
      requiredFields: reqFields,
      functionKind: type == AddonType.function ? resolvedKind : FunctionKind.generic,
      // extra = capacidades + tipos de contenido + géneros (estilo Kino)
      // Nunca copiar "types":["catalog"] del addon aquí.
      extra: buildCatalogExtra(manifest, {
        'githubOwner': addr.owner,
        'githubRepo': addr.repo,
        'githubPath': addr.path,
        'githubRef': addr.ref,
      }),
      installedAt: DateTime.now(),
    );
  }

  /// Manifest JSON estilo Stremio / Nuvio (addon individual, no paquete).
  AddonManifest fromJsonString(
    String raw, {
    String? sourceUrl,
    AddonOrigin origin = AddonOrigin.pasted,
  }) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final id = (map['id'] as String?) ??
        (map['name'] as String?)?.toLowerCase().replaceAll(RegExp(r'\s+'), '-') ??
        _uuid.v4();

    final resources = <String>[];
    if (map['resources'] is List) {
      for (final r in map['resources'] as List) {
        if (r is String) {
          resources.add(r);
        } else if (r is Map && r['name'] != null) {
          resources.add(r['name'].toString());
        }
      }
    }

    final types = <AddonType>[];
    // type singular del manifest (function | catalog | source)
    final typeSingular = (map['type'] ?? '').toString().toLowerCase();
    if (typeSingular.contains('catalog')) types.add(AddonType.catalog);
    if (typeSingular.contains('function') || typeSingular.contains('subtitle')) {
      types.add(AddonType.function);
    }
    if (typeSingular.contains('source') || typeSingular.contains('stream')) {
      types.add(AddonType.source);
    }
    if (resources.contains('catalog') || resources.contains('meta')) {
      if (!types.contains(AddonType.catalog)) types.add(AddonType.catalog);
    }
    if (resources.contains('stream')) {
      if (!types.contains(AddonType.source)) types.add(AddonType.source);
    }
    if (resources.contains('subtitles') ||
        resources.contains('subtitle') ||
        resources.contains('home') ||
        resources.contains('mainSlider') ||
        resources.contains('top10')) {
      if (!types.contains(AddonType.function)) types.add(AddonType.function);
    }
    if (types.isEmpty && map['types'] is List) {
      for (final t in map['types'] as List) {
        final name = t.toString().toLowerCase();
        if (name.contains('catalog')) types.add(AddonType.catalog);
        if (name.contains('stream') || name.contains('source')) {
          types.add(AddonType.source);
        }
        if (name.contains('sub') || name.contains('function')) {
          types.add(AddonType.function);
        }
      }
    }
    if (types.isEmpty) types.add(AddonType.source);

    // functionKind: mainSlider | top10 | subtitles | …
    final kindStr =
        (map['functionKind'] ?? map['kind'] ?? '').toString().toLowerCase();
    final resolvedKind = FunctionKind.values.firstWhere(
      (k) => k.name.toLowerCase() == kindStr,
      orElse: () {
        final lid = id.toLowerCase();
        if (kindStr.contains('sub') || resources.any((r) => r.contains('sub'))) {
          return FunctionKind.subtitles;
        }
        if (kindStr.contains('top') || lid.contains('top10') || lid.contains('top-10')) {
          return FunctionKind.top10;
        }
        if (kindStr.contains('slider') ||
            kindStr.contains('hero') ||
            lid.contains('slider') ||
            lid.contains('hero')) {
          return FunctionKind.mainSlider;
        }
        if (kindStr.contains('tag') || kindStr.contains('badge')) {
          return FunctionKind.posterTags;
        }
        if (kindStr.contains('rating')) return FunctionKind.rating;
        return FunctionKind.generic;
      },
    );

    final placements = <FunctionPlacement>[];
    if (map['placements'] is List) {
      for (final p in map['placements'] as List) {
        placements.add(FunctionPlacement.values.firstWhere(
          (e) => e.name == p.toString(),
          orElse: () => resolvedKind.defaultPlacement,
        ));
      }
    }
    if (placements.isEmpty && types.contains(AddonType.function)) {
      placements.add(resolvedKind.defaultPlacement);
    }

    // configSchema
    final schema = <AddonConfigField>[];
    final rawSchema = map['configSchema'] ??
        (map['config'] is Map ? (map['config'] as Map)['fields'] : null) ??
        map['config_fields'];
    if (rawSchema is List) {
      for (final e in rawSchema) {
        if (e is Map) {
          schema.add(
            AddonConfigField.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }

    // rawCode solo si es JS real; no guardar el JSON del manifest como código
    String? rawCode;
    final entry = (map['entry'] ?? map['main'] ?? '').toString();
    if (entry.toLowerCase().endsWith('.js') && sourceUrl != null) {
      // se descarga en fromUrl si aplica; aquí no hay cuerpo JS
      rawCode = null;
    }

    return AddonManifest(
      id: id,
      name: map['name'] as String? ?? id,
      version: map['version'] as String? ?? '1.0.0',
      description: map['description'] as String? ?? '',
      types: types,
      logo: map['logo'] as String? ?? map['icon'] as String?,
      author: map['author'] as String?,
      resources: resources.isEmpty && types.contains(AddonType.function)
          ? [resolvedKind.name]
          : resources,
      exports: const [],
      rawCode: rawCode,
      sourceUrl: sourceUrl,
      origin: origin,
      enabled: true,
      supportedTypes: List<String>.from(map['supportedTypes'] ?? ['movie', 'tv']),
      formats: List<String>.from(map['formats'] ?? []),
      contentLanguage: List<String>.from(map['contentLanguage'] ?? []),
      configSchema: schema,
      placements: placements,
      requiredFields: List<String>.from(map['requiredFields'] ?? []),
      functionKind: types.contains(AddonType.function)
          ? resolvedKind
          : FunctionKind.generic,
      extra: buildCatalogExtra(map, const {}),
      installedAt: DateTime.now(),
    );
  }

  /// Analiza código JS (como cinecalidad.js) y detecta exports.
  AddonManifest fromJsString(
    String raw, {
    String? sourceUrl,
    AddonOrigin origin = AddonOrigin.pasted,
  }) {
    final exports = _detectExports(raw);
    final types = <AddonType>[];

    if (exports.any((e) =>
        e == 'catalog' ||
        e == 'getCatalog' ||
        e == 'meta' ||
        e == 'getMeta' ||
        e == 'search')) {
      types.add(AddonType.catalog);
    }
    if (exports.any((e) =>
        e == 'getStreams' ||
        e == 'stream' ||
        e == 'getStream' ||
        e == 'streams')) {
      types.add(AddonType.source);
    }
    if (exports.any((e) =>
        e == 'getSubtitles' ||
        e == 'subtitles' ||
        e == 'getSubtitle')) {
      types.add(AddonType.function);
    }
    if (types.isEmpty) {
      if (raw.contains('getStreams') || raw.contains('module.exports')) {
        types.add(AddonType.source);
      } else {
        types.add(AddonType.source);
      }
    }

    final nameGuess = _guessName(raw, sourceUrl) ?? 'Addon JS';
    final id = nameGuess
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    return AddonManifest(
      id: id.isEmpty ? _uuid.v4() : id,
      name: nameGuess,
      version: '1.0.0',
      description: 'Addon JavaScript (${exports.join(', ')})',
      types: types,
      resources: _resourcesFromExports(exports),
      exports: exports,
      rawCode: raw,
      sourceUrl: sourceUrl,
      origin: origin,
      enabled: true,
      installedAt: DateTime.now(),
    );
  }

  List<String> _detectExports(String code) {
    final found = <String>{};
    final lower = code;
    if (lower.contains('getStreams') ||
        lower.contains('exports.getStreams') ||
        RegExp(r'getStreams\s*[:=]').hasMatch(lower)) {
      found.add('getStreams');
    }
    if (lower.contains('getSubtitles') || lower.contains('subtitles')) {
      found.add('getSubtitles');
    }
    if ((lower.contains('catalog') || lower.contains('getCatalog')) &&
        !lower.contains('getStreams')) {
      found.add('catalog');
    }
    if (lower.contains('getMeta')) {
      found.add('getMeta');
    }
    if (found.isEmpty && lower.contains('module.exports')) {
      found.add('getStreams');
    }
    return found.toList();
  }

  List<String> _resourcesFromExports(List<String> exports) {
    final r = <String>[];
    if (exports.any((e) => e.contains('Stream') || e == 'stream')) {
      r.add('stream');
    }
    if (exports.any((e) => e.contains('catalog') || e.contains('Meta'))) {
      r.add('catalog');
      r.add('meta');
    }
    if (exports.any((e) => e.toLowerCase().contains('sub'))) {
      r.add('subtitles');
    }
    return r;
  }

  String? _guessName(String code, String? url) {
    if (url != null) {
      final seg = url.split('/').last.replaceAll(RegExp(r'\.(js|json)$'), '');
      if (seg.isNotEmpty) {
        return seg
            .split(RegExp(r'[-_]'))
            .map((w) => w.isEmpty
                ? ''
                : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
      }
    }
    final m = RegExp(r'\[([A-Za-z0-9]+)\]').firstMatch(code);
    if (m != null) return m.group(1);
    return null;
  }
}

/// Construye extra normalizado para catálogos/fuentes/funciones.
/// Incluye capabilities, mode, mediaKinds, hosts, tags, etc. (comunidad).
Map<String, dynamic> buildCatalogExtra(
  Map<String, dynamic>? manifest,
  Map<String, dynamic> base,
) {
  final out = <String, dynamic>{...base};
  if (manifest == null) return out;

  final nested = manifest['extra'] is Map
      ? Map<String, dynamic>.from(manifest['extra'] as Map)
      : <String, dynamic>{};

  // capabilities
  final caps = <String>[];
  final rawCaps = manifest['capabilities'] ?? nested['capabilities'];
  if (rawCaps is List) {
    for (final c in rawCaps) {
      final s = c.toString().trim().toLowerCase();
      if (s.isNotEmpty && !caps.contains(s)) caps.add(s);
    }
  }
  if (caps.isNotEmpty) out['capabilities'] = caps;

  // mode: vod | tv | both
  final mode = (manifest['mode'] ?? nested['mode'] ?? '').toString().trim();
  if (mode.isNotEmpty) {
    out['mode'] = mode.toLowerCase();
  } else if (caps.contains('channels') &&
      !caps.any((c) => c == 'search' || c == 'home' || c == 'discover')) {
    out['mode'] = 'tv';
  } else if (caps.contains('channels')) {
    out['mode'] = 'both';
  } else {
    out['mode'] = 'vod';
  }

  // Tipos de contenido (NO type del addon)
  final kinds = manifest['mediaKinds'] ??
      manifest['catalogTypes'] ??
      nested['types'] ??
      nested['mediaKinds'];
  if (kinds is List && kinds.isNotEmpty) {
    out['types'] = kinds;
    out['mediaKinds'] = kinds;
  }

  // Géneros
  final genres = manifest['genresByKind'] ??
      manifest['genresByType'] ??
      manifest['genres'] ??
      nested['genresByKind'] ??
      nested['genresByType'] ??
      nested['genres'];
  if (genres != null) {
    out['genres'] = genres;
    out['genresByType'] = genres;
    out['genresByKind'] = genres;
  }

  // Comunidad / seguridad / meta
  void putStr(String key, dynamic v) {
    if (v == null) return;
    final s = v.toString().trim();
    if (s.isNotEmpty) out[key] = s;
  }

  putStr('homepage', manifest['homepage'] ?? nested['homepage'] ?? manifest['homeUrl']);
  putStr('color', manifest['color'] ?? nested['color']);
  putStr('minAppVersion',
      manifest['minAppVersion'] ?? nested['minAppVersion'] ?? manifest['min_app_version']);
  putStr('ageRating', manifest['ageRating'] ?? nested['ageRating']);
  putStr('defaultCategory',
      manifest['defaultCategory'] ?? nested['defaultCategory']);
  putStr('updateUrl', manifest['updateUrl'] ?? nested['updateUrl']);
  putStr('provider', nested['provider'] ?? manifest['provider']);

  final apiV = manifest['apiVersion'] ?? nested['apiVersion'] ?? manifest['api_version'];
  if (apiV != null) out['apiVersion'] = int.tryParse('$apiV') ?? apiV;

  if (manifest['download'] == true || nested['download'] == true) {
    out['download'] = true;
    if (!caps.contains('download')) {
      caps.add('download');
      out['capabilities'] = List<String>.from(caps);
    }
  }
  if (manifest['nsfw'] == true || nested['nsfw'] == true) {
    out['nsfw'] = true;
  }
  if (manifest['discoverable'] != null) {
    out['discoverable'] = manifest['discoverable'];
  } else if (nested['discoverable'] != null) {
    out['discoverable'] = nested['discoverable'];
  }

  // tags
  final tags = <String>[];
  final rawTags = manifest['tags'] ?? nested['tags'];
  if (rawTags is List) {
    for (final t in rawTags) {
      final s = t.toString().trim();
      if (s.isNotEmpty && !tags.contains(s)) tags.add(s);
    }
  }
  if (tags.isNotEmpty) out['tags'] = tags;

  // hosts (lista de strings o {host, insecureHttp})
  final hosts = <dynamic>[];
  final rawHosts = manifest['hosts'] ?? nested['hosts'];
  if (rawHosts is List) {
    hosts.addAll(rawHosts);
  }
  if (hosts.isNotEmpty) out['hosts'] = hosts;

  for (final key in ['streamHosts', 'fetchHosts', 'liveStreamHosts']) {
    final v = manifest[key] ?? nested[key];
    if (v != null) out[key] = v;
  }

  // permissions
  final perms = <String>[];
  final rawPerms = manifest['permissions'] ?? nested['permissions'];
  if (rawPerms is List) {
    for (final p in rawPerms) {
      final s = p.toString().trim();
      if (s.isNotEmpty && !perms.contains(s)) perms.add(s);
    }
  }
  if (perms.isNotEmpty) out['permissions'] = perms;

  // catalogParams (objeto libre)
  final params = manifest['catalogParams'] ?? nested['catalogParams'];
  if (params is Map) out['catalogParams'] = Map<String, dynamic>.from(params);

  // Resto de extra anidado sin pisar keys críticas
  nested.forEach((k, v) {
    if (!out.containsKey(k) && k != 'types' && k != 'type' && v != null) {
      out[k] = v;
    }
  });

  return out;
}


class GitHubAddress {
  final String owner;
  final String repo;
  final String ref;
  final String path;

  const GitHubAddress({
    required this.owner,
    required this.repo,
    this.ref = 'main',
    this.path = '',
  });

  /// Alias
  String get user => owner;
  String get branch => ref;

  static GitHubAddress? parse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('http://') || s.startsWith('https://')) {
      final uri = Uri.tryParse(s);
      if (uri == null) return null;
      final host = uri.host.toLowerCase();
      final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
      if (host.contains('github.com') && segs.length >= 2) {
        final owner = segs[0];
        final repo = segs[1].replaceAll('.git', '');
        String ref = 'main';
        String path = '';
        if (segs.length >= 4 && (segs[2] == 'tree' || segs[2] == 'blob')) {
          ref = segs[3];
          if (segs.length > 4) path = segs.sublist(4).join('/');
        }
        return GitHubAddress(owner: owner, repo: repo, ref: ref, path: path);
      }
      if (host.contains('raw.githubusercontent.com') && segs.length >= 3) {
        final owner = segs[0];
        final repo = segs[1];
        final ref = segs[2];
        var basePath = segs.length > 3 ? segs.sublist(3).join('/') : '';
        if (basePath.contains('/')) {
          final parts = basePath.split('/');
          if (parts.last.contains('.')) {
            basePath = parts.sublist(0, parts.length - 1).join('/');
          }
        } else if (basePath.contains('.')) {
          basePath = '';
        }
        return GitHubAddress(
          owner: owner,
          repo: repo,
          ref: ref,
          path: basePath,
        );
      }
      return null;
    }

    var ref = 'main';
    if (s.contains('@')) {
      final at = s.split('@');
      s = at[0];
      if (at.length > 1 && at[1].isNotEmpty) {
        ref = at[1].split('/').first;
      }
    }
    final parts = s.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final owner = parts[0];
    final repo = parts[1].replaceAll('.git', '');
    final path = parts.length > 2 ? parts.sublist(2).join('/') : '';
    return GitHubAddress(owner: owner, repo: repo, ref: ref, path: path);
  }

  String rawUrl(String file) {
    final base = path.isEmpty ? '' : '$path/';
    final f = file.startsWith('/') ? file.substring(1) : file;
    return 'https://raw.githubusercontent.com/$owner/$repo/$ref/$base$f';
  }

  String get canonical =>
      path.isEmpty ? '$owner/$repo@$ref' : '$owner/$repo/$path@$ref';
}
