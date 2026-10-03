# Sistema de Addons (fuentes + catalogos) — integrado desde App 2

## Que se hizo

1. Nucleo de App 2 copiado a data/addons/:
   - models/addon.dart, content.dart, kino_package.dart, app_package.dart
   - services/addon_loader.dart, source_service.dart, catalog_service.dart
   - services/js_runtime.dart (flutter_js), catalog_js_bridge.dart
   - services/storage_service.dart, tmdb_service.dart

2. AddonManager (data/addons/addon_manager.dart):
   - Instalar desde GitHub (user/repo) o URL de manifest
   - Listar / activar / desactivar / actualizar / borrar
   - Solo fuentes y catalogos

3. Adapter (data/addons/addon_source_adapter.dart):
   - Convierte StreamItem de los addons al mapa del modal de servidores
   - Campos: servidor_url, idioma, calidad, fuente, etc.

4. MainFuentes / source_aggregator:
   - Tras fuentes nativas, tambien scrapea fuentes addon instaladas
   - UI del modal no cambia

5. Config UI nueva:
   - features/addons/presentation/screens/addons_hub_page.dart
   - Al entrar: Addons actuales | Comunidad
   - Comunidad = instalar por Git (user/repo)
   - Actuales = ver, activar, actualizar, borrar

6. main.dart: await AddonManager.instance.init() al arrancar

## Dependencias en pubspec.yaml

flutter_js, uuid, equatable, http, shared_preferences

Assets JS (si App 2 los tenia):
  assets/js/crypto-js.bundle.js
  assets/js/cheerio.bundle.js

## Enlazar en Configuracion

Navigator.push(context, MaterialPageRoute(
  builder: (_) => const AddonsHubPage(isTv: false),
));

## Catalogos

AddonManager.instance.catalogAddons
AddonManager.instance.catalogs.getHomeRows(...)

## Extractores

Siguen por compatibilidad. Si no hay nativas activas, el modal usa solo addons.
