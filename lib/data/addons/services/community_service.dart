import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Item de comunidad (repo GitHub) listo para instalar.
class CommunityAddonItem {
  final String id;
  final String repo; // owner/repo
  final String name;
  final String description;
  final String? author;
  final int stars;
  final String? logo;
  final String type; // source | catalog

  const CommunityAddonItem({
    required this.id,
    required this.repo,
    required this.name,
    this.description = '',
    this.author,
    this.stars = 0,
    this.logo,
    this.type = 'source',
  });
}

/// Busca addons públicos en GitHub por topic.
/// Fuentes:  https://github.com/topics/lol-addon-fuentes
/// Catálogos: https://github.com/topics/lol-addon-catalogos
class CommunityService {
  /// Topics oficiales (los que usa tu ecosistema).
  static const topicSource = 'lol-addon-fuentes';
  static const topicCatalog = 'lol-addon-catalogos';

  /// Topics alternativos por si hay repos etiquetados con el nombre en inglés.
  static const topicSourceAlt = ['lol-addon-source', 'lol-addon-fuente'];
  static const topicCatalogAlt = ['lol-addon-catalog', 'lol-addon-catalogo'];

  /// Seeds opcionales (aparecen aunque GitHub falle o rate-limit).
  static const recommendedSeed = <Map<String, dynamic>>[
    {
      'id': 'allpeliculasse',
      'repo': 'loladdons/allpeliculasse',
      'name': 'AllPeliculasSE',
      'description': 'Fuente AllPeliculas (topic lol-addon-fuentes).',
      'type': 'source',
    },
  ];

  Future<http.Response> _get(String url) {
    return http
        .get(
          Uri.parse(url),
          headers: {
            'Accept': 'application/vnd.github+json, application/json, */*',
            'User-Agent': 'LolApp1-Addons/1.0',
          },
        )
        .timeout(const Duration(seconds: 15));
  }

  List<CommunityAddonItem> recommended({String? type}) {
    return recommendedSeed
        .where((e) => type == null || e['type'] == type)
        .map((e) => CommunityAddonItem(
              id: e['id'] as String,
              repo: e['repo'] as String,
              name: e['name'] as String,
              description: (e['description'] ?? '') as String,
              type: (e['type'] ?? 'source') as String,
            ))
        .toList();
  }

  Future<List<CommunityAddonItem>> fetchByTopic(
    String topic, {
    String type = 'source',
  }) async {
    final url = 'https://api.github.com/search/repositories'
        '?q=topic:$topic+fork:false'
        '&sort=stars&order=desc&per_page=30';
    try {
      final res = await _get(url);
      if (res.statusCode != 200) {
        debugPrint('[Community] topic:$topic status ${res.statusCode}');
        return [];
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = <CommunityAddonItem>[];
      for (final raw in (body['items'] as List? ?? [])) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final full = (item['full_name'] ?? '').toString();
        if (full.isEmpty) continue;
        final ownerMap = item['owner'] as Map?;
        final owner =
            ownerMap?['login']?.toString() ?? full.split('/').first;
        final avatar = ownerMap?['avatar_url']?.toString();
        items.add(CommunityAddonItem(
          id: full.replaceAll('/', '-').toLowerCase(),
          repo: full,
          name: (item['name'] ?? full).toString(),
          description: (item['description'] ?? '').toString(),
          author: owner,
          stars: int.tryParse('${item['stargazers_count'] ?? 0}') ?? 0,
          logo: (avatar != null && avatar.isNotEmpty) ? avatar : null,
          type: type,
        ));
      }
      debugPrint('[Community] topic:$topic → ${items.length} repos');
      return items;
    } catch (e) {
      debugPrint('[Community] topic:$topic: $e');
      return [];
    }
  }

  Future<List<CommunityAddonItem>> _fetchTopics(
    List<String> topics, {
    required String type,
  }) async {
    final out = <CommunityAddonItem>[];
    final seen = <String>{};
    for (final t in topics) {
      final list = await fetchByTopic(t, type: type);
      for (final a in list) {
        if (seen.add(a.repo.toLowerCase())) out.add(a);
      }
    }
    return out;
  }

  Future<({List<CommunityAddonItem> sources, List<CommunityAddonItem> catalogs})>
      fetchAll() async {
    final results = await Future.wait([
      _fetchTopics([topicSource, ...topicSourceAlt], type: 'source'),
      _fetchTopics([topicCatalog, ...topicCatalogAlt], type: 'catalog'),
    ]);
    final sources = _merge(recommended(type: 'source'), results[0]);
    final catalogs = _merge(recommended(type: 'catalog'), results[1]);
    return (sources: sources, catalogs: catalogs);
  }

  List<CommunityAddonItem> _merge(
    List<CommunityAddonItem> seed,
    List<CommunityAddonItem> remote,
  ) {
    final seen = <String>{};
    final out = <CommunityAddonItem>[];
    for (final a in [...seed, ...remote]) {
      final key = a.repo.toLowerCase();
      if (seen.add(key)) out.add(a);
    }
    return out;
  }

  // ── TV Channels (topic oficial: lol-tvchanel) ──

  static const topicTvChanel = 'lol-tvchanel';
  static const topicTvChanelAlt = [
    'lol_tvchanel',
    'lol-addon-tvchanel',
    'lol-addon-tv-channels',
  ];

  /// Sin seeds por defecto: solo repos de la comunidad (topic lol-tvchanel).
  List<CommunityAddonItem> recommendedTv() => const [];

  Future<List<CommunityAddonItem>> fetchTvChanelAddons() async {
    try {
      return await _fetchTopics(
        [topicTvChanel, ...topicTvChanelAlt],
        type: 'tvchanel',
      );
    } catch (e) {
      debugPrint('[Community] fetchTvChanelAddons: $e');
      return const [];
    }
  }
}
