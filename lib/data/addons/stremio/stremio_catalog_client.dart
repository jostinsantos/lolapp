import 'package:http/http.dart' as http;
import 'stremio_manifest_parser.dart';
import 'stremio_models.dart';
import 'stremio_url_builder.dart';

/// HTTP client del protocolo Stremio: manifest + catalog pages.
class StremioCatalogClient {
  StremioCatalogClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const _timeout = Duration(seconds: 18);
  static const _ua = 'LolPlusTV/1.0 (Stremio-compatible)';

  Future<StremioManifest> fetchManifest(String manifestUrl) async {
    final url = normalizeManifestUrl(manifestUrl);
    final res = await _http.get(
      Uri.parse(url),
      headers: {'User-Agent': _ua, 'Accept': 'application/json'},
    ).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Manifest HTTP ${res.statusCode}: $url');
    }
    return StremioManifestParser.parse(url, res.body);
  }

  Future<StremioCatalogPage> fetchCatalogPage({
    required String manifestUrl,
    required String type,
    required String catalogId,
    int? skip,
    String? search,
    String? genre,
    int? maxItems,
  }) async {
    final url = buildCatalogUrl(
      manifestUrl: manifestUrl,
      type: type,
      catalogId: catalogId,
      skip: skip,
      search: search,
      genre: genre,
    );
    final res = await _http.get(
      Uri.parse(url),
      headers: {'User-Agent': _ua, 'Accept': 'application/json'},
    ).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Catalog HTTP ${res.statusCode}: $url');
    }
    return StremioCatalogParser.parse(
      res.body,
      maxItems: maxItems,
      currentSkip: skip,
    );
  }
}
