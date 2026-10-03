import 'js_runtime.dart';

/// Puente fino: delega en JsAddonRuntime.callCatalogMethod
/// (misma API de promesas que getStreams).
class CatalogJsBridge {
  CatalogJsBridge._();
  static final CatalogJsBridge instance = CatalogJsBridge._();

  Future<dynamic> call({
    required String addonId,
    required String code,
    required String method,
    Map<String, dynamic> args = const {},
    Map<String, String> config = const {},
  }) {
    return JsAddonRuntime.instance.callCatalogMethod(
      addonId: addonId,
      code: code,
      method: method,
      args: args,
      config: config,
    );
  }
}
