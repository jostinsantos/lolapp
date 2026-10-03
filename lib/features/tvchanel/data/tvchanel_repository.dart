import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/tv_channel_models.dart';
import 'm3u_parser.dart';

const _kM3uPrefsKey = 'tvchanel_m3u_playlists';

/// Repositorio central de TV Channels (listas M3U + addons locales)
class TvChanelRepository {
  TvChanelRepository._();
  static final TvChanelRepository instance = TvChanelRepository._();

  // ─────────────────────────────────────────────
  //  M3U Playlists
  // ─────────────────────────────────────────────

  Future<List<M3uPlaylist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kM3uPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => M3uPlaylist.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePlaylists(List<M3uPlaylist> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kM3uPrefsKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<M3uPlaylist> addPlaylist({
    required String name,
    required String url,
  }) async {
    final list = await getPlaylists();
    final item = M3uPlaylist(
      id: const Uuid().v4(),
      name: name.trim(),
      url: url.trim(),
      addedAt: DateTime.now(),
    );
    list.add(item);
    await savePlaylists(list);
    return item;
  }

  Future<void> removePlaylist(String id) async {
    final list = await getPlaylists();
    list.removeWhere((e) => e.id == id);
    await savePlaylists(list);
  }

  Future<void> togglePlaylist(String id, bool enabled) async {
    final list = await getPlaylists();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(enabled: enabled);
    await savePlaylists(list);
  }

  /// Descarga y parsea una lista M3U remota
  Future<List<TvChannel>> fetchM3uChannels(M3uPlaylist playlist) async {
    final response = await http.get(
      Uri.parse(playlist.url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': '*/*',
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    return M3uParser.parse(
      response.body,
      sourceName: playlist.name,
    );
  }

  /// Todas las categorías de todas las listas M3U habilitadas
  Future<List<TvCategory>> getAllM3uCategories() async {
    final playlists = await getPlaylists();
    final enabled = playlists.where((p) => p.enabled).toList();
    final allChannels = <TvChannel>[];

    for (final p in enabled) {
      try {
        final channels = await fetchM3uChannels(p);
        allChannels.addAll(channels);
      } catch (_) {
        // Si una lista falla, continuamos con las demás
      }
    }

    return M3uParser.groupByCategory(allChannels);
  }

  // ─────────────────────────────────────────────
  //  Addons locales
  // ─────────────────────────────────────────────

  Future<Directory> getAddonsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/tvchanel_addons');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Carga todos los addons válidos (requieren logo + manifest + index)
  Future<List<TvAddon>> loadAddons() async {
    final base = await getAddonsDirectory();
    final result = <TvAddon>[];

    await for (final entity in base.list()) {
      if (entity is! Directory) continue;

      final manifestFile = File('${entity.path}/manifest.json');
      final indexFile = File('${entity.path}/index.json');
      final configFile = File('${entity.path}/config.json');
      final logoPng = File('${entity.path}/logo.png');
      final logoJpg = File('${entity.path}/logo.jpg');
      final logoJpeg = File('${entity.path}/logo.jpeg');

      if (!await manifestFile.exists()) {
        continue;
      }

      String? logoPath;
      if (await logoPng.exists()) {
        logoPath = logoPng.path;
      } else if (await logoJpg.exists()) {
        logoPath = logoJpg.path;
      } else if (await logoJpeg.exists()) {
        logoPath = logoJpeg.path;
      } else {
        // logo remoto se permite vía manifest.logo (URL)
        logoPath = '${entity.path}/.nologo';
      }

      try {
        final manifestJson = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;

        Map<String, dynamic>? config;
        if (await configFile.exists()) {
          try {
            config = jsonDecode(await configFile.readAsString())
                as Map<String, dynamic>;
          } catch (_) {}
        }

        // Logo local o URL en manifest
        final remoteLogo = (manifestJson['logo'] ?? manifestJson['icon'])
            ?.toString();
        if (logoPath.endsWith('.nologo')) {
          if (remoteLogo == null || remoteLogo.isEmpty) continue;
          logoPath = remoteLogo; // URL
        }

        final manifest =
            TvAddonManifest.fromJson(manifestJson, logoPath);

        final categories = <TvCategory>[];

        // 1) m3u_url en config o manifest → descargar y parsear en vivo
        final m3uUrl = (config?['m3u_url'] ??
                config?['m3u'] ??
                manifestJson['m3u_url'] ??
                manifestJson['m3u'])
            ?.toString();
        if (m3uUrl != null && m3uUrl.startsWith('http')) {
          try {
            final channels = await _fetchRemoteM3u(
              m3uUrl,
              sourceName: manifest.name,
            );
            categories.addAll(M3uParser.groupByCategory(channels));
          } catch (_) {
            // si falla, intentamos index.json
          }
        }

        // 2) index.json estático
        if (categories.isEmpty && await indexFile.exists()) {
          final indexJson =
              jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
          final cats = indexJson['categories'] as List? ?? [];
          for (final c in cats) {
            if (c is! Map) continue;
            categories.add(
              TvCategory.fromJson(Map<String, dynamic>.from(c)),
            );
          }
          if (categories.isEmpty && indexJson['channels'] is List) {
            final channels = (indexJson['channels'] as List)
                .map((e) =>
                    TvChannel.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
            categories.add(TvCategory(name: 'General', channels: channels));
          }
        }

        if (categories.isEmpty) continue;

        result.add(TvAddon(
          manifest: manifest,
          categories: categories,
          folderPath: entity.path,
          config: config,
        ));
      } catch (_) {
        // Addon inválido → se ignora
      }
    }

    result.sort(
      (a, b) => a.manifest.name.toLowerCase().compareTo(
            b.manifest.name.toLowerCase(),
          ),
    );
    return result;
  }


  Future<List<TvChannel>> _fetchRemoteM3u(String url, {String? sourceName}) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': '*/*',
      },
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return M3uParser.parse(response.body, sourceName: sourceName);
  }

  /// Instala addon desde GitHub owner/repo (misma lógica que fuentes).
  /// Busca manifest.json + index.json/logo en la raíz del repo.
  Future<TvAddon> installFromGithub(String ownerRepo, {String branch = 'main'}) async {
    final parts = ownerRepo.trim().replaceAll(RegExp(r'^https?://github.com/'), '').split('/');
    if (parts.length < 2) {
      throw Exception('Usa owner/repo (ej: loladdons/argentina-live)');
    }
    final owner = parts[0];
    final repo = parts[1];
    final pathPrefix = parts.length > 2 ? parts.sublist(2).join('/') : '';

    String raw(String file) {
      final p = pathPrefix.isEmpty ? file : '$pathPrefix/$file';
      return 'https://raw.githubusercontent.com/$owner/$repo/$branch/$p';
    }

    Future<http.Response> get(String url) => http
        .get(Uri.parse(url), headers: {
          'User-Agent': 'LolApp-TvChanel/1.0',
          'Accept': '*/*',
        })
        .timeout(const Duration(seconds: 20));

    // manifest.json obligatorio
    final manRes = await get(raw('manifest.json'));
    if (manRes.statusCode != 200) {
      // intentar master
      final manRes2 = await get(
        'https://raw.githubusercontent.com/$owner/$repo/master/${pathPrefix.isEmpty ? '' : '$pathPrefix/'}manifest.json',
      );
      if (manRes2.statusCode != 200) {
        throw Exception('No se encontró manifest.json en $owner/$repo');
      }
      branch = 'master';
    }
    final manResFinal = manRes.statusCode == 200
        ? manRes
        : await get(raw('manifest.json'));
    final manifestJson =
        jsonDecode(manResFinal.body) as Map<String, dynamic>;

    final id = (manifestJson['id'] ?? '$owner-$repo')
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-');

    final base = await getAddonsDirectory();
    final folder = Directory('${base.path}/$id');
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    await folder.create(recursive: true);

    await File('${folder.path}/manifest.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(manifestJson));

    // index.json (opcional si hay m3u_url)
    try {
      final idxRes = await get(raw('index.json'));
      if (idxRes.statusCode == 200) {
        await File('${folder.path}/index.json').writeAsString(idxRes.body);
      }
    } catch (_) {}

    // config.json
    try {
      final cfgRes = await get(raw('config.json'));
      if (cfgRes.statusCode == 200) {
        await File('${folder.path}/config.json').writeAsString(cfgRes.body);
      }
    } catch (_) {}

    // Si manifest trae m3u_url y no hay config, crear config
    final m3u = (manifestJson['m3u_url'] ?? manifestJson['m3u'])?.toString();
    final cfgFile = File('${folder.path}/config.json');
    if (m3u != null && m3u.startsWith('http') && !await cfgFile.exists()) {
      await cfgFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({'m3u_url': m3u}),
      );
    }

    // logo.png / jpg o URL
    bool logoOk = false;
    for (final name in ['logo.png', 'logo.jpg', 'logo.jpeg', 'icon.png']) {
      try {
        final r = await get(raw(name));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          final outName = name.startsWith('icon') ? 'logo.png' : name;
          await File('${folder.path}/$outName').writeAsBytes(r.bodyBytes);
          logoOk = true;
          break;
        }
      } catch (_) {}
    }
    if (!logoOk) {
      final logoUrl = (manifestJson['logo'] ?? manifestJson['icon'])?.toString();
      if (logoUrl != null && logoUrl.startsWith('http')) {
        try {
          final r = await get(logoUrl);
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            final ext = logoUrl.toLowerCase().contains('.jpg') ? 'jpg' : 'png';
            await File('${folder.path}/logo.$ext').writeAsBytes(r.bodyBytes);
            logoOk = true;
          }
        } catch (_) {}
      }
    }
    // Si no hay logo local, dejamos URL en manifest (loadAddons lo acepta)

    // Recargar
    final addons = await loadAddons();
    final found = addons.where((a) => a.manifest.id == id || a.folderPath.endsWith('/$id'));
    if (found.isEmpty) {
      // Puede que m3u falle temporalmente; devolvemos stub
      return TvAddon(
        manifest: TvAddonManifest.fromJson(
          manifestJson,
          logoOk ? '${folder.path}/logo.png' : (manifestJson['logo']?.toString() ?? ''),
        ),
        categories: const [],
        folderPath: folder.path,
        config: m3u != null ? {'m3u_url': m3u} : null,
      );
    }
    return found.first;
  }

  Future<void> deleteAddon(String folderPath) async {
    final dir = Directory(folderPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Crea un addon de ejemplo (útil para testing)
  Future<void> createExampleAddon() async {
    final base = await getAddonsDirectory();
    final folder = Directory('${base.path}/ejemplo_canales');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    // manifest.json
    await File('${folder.path}/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'id': 'ejemplo.canales',
        'name': 'Ejemplo Canales',
        'version': '1.0.0',
        'description': 'Addon de ejemplo con canales de prueba',
        'author': 'Usuario',
      }),
    );

    // index.json
    await File('${folder.path}/index.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'categories': [
          {
            'name': 'Noticias',
            'channels': [
              {
                'id': 'ch1',
                'name': 'Canal Demo 1',
                'url': 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
                'logo':
                    'https://via.placeholder.com/200x200.png?text=Demo1',
                'group': 'Noticias',
              },
            ],
          },
          {
            'name': 'Deportes',
            'channels': [
              {
                'id': 'ch2',
                'name': 'Canal Demo 2',
                'url':
                    'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
                'logo':
                    'https://via.placeholder.com/200x200.png?text=Demo2',
                'group': 'Deportes',
              },
            ],
          },
        ],
      }),
    );

    // config.json
    await File('${folder.path}/config.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'default_category': 'Noticias',
      }),
    );

    // Nota: el usuario debe poner logo.png manualmente.
    // Aquí solo dejamos un placeholder de texto.
    await File('${folder.path}/README.txt').writeAsString(
      'Coloca aquí un archivo logo.png o logo.jpg (obligatorio para que el addon se cargue).\n',
    );
  }
}
