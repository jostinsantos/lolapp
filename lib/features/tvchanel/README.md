# TV Channels (TV en Vivo)

Módulo completo para listas M3U8 y addons de canales en vivo.

## Estructura

```
lib/features/tvchanel/
├── models/
│   └── tv_channel_models.dart
├── data/
│   ├── m3u_parser.dart
│   └── tvchanel_repository.dart
├── config/
│   ├── m3u8_page.dart          (stub móvil)
│   ├── m3u8_page_tv.dart       ✅ TV
│   ├── addon_chanel.dart       (stub móvil)
│   └── addon_chanel_tv.dart    ✅ TV
├── home/
│   ├── home_tvchanel.dart      (stub móvil)
│   └── home_tvchanel_tv.dart   ✅ TV
└── player/
    ├── player_tvchanel.dart
    └── player_tvchaneltv.dart  ✅ TV
```

## Integración en el Home TV

En tu menú lateral de TV (o donde navegues las secciones), añade una entrada:

```dart
// Ejemplo de navegación
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => HomeTvChanelTv(
      onRequestMenuFocus: () {
        // Devuelve el foco al menú lateral
        yourMenuFocusNode.requestFocus();
      },
      onMainFocusNodeCreated: (node) {
        // Opcional: guardar el focus node principal
      },
    ),
  ),
);
```

Import:

```dart
import 'package:tu_app/features/tvchanel/home/home_tvchanel_tv.dart';
```

## Listas M3U8

El usuario puede añadir varias listas desde **Listas M3U8**.
Se guardan en SharedPreferences y se parsean automáticamente.

## Addons de Canales

Los addons son **solo para canales** (diferentes a los addons de fuentes).

### Estructura obligatoria de un addon

```
Documents/tvchanel_addons/
└── mi_addon/
    ├── manifest.json     ← obligatorio
    ├── index.json        ← obligatorio
    ├── config.json       ← opcional
    └── logo.png          ← obligatorio (también acepta .jpg / .jpeg)
```

### Ejemplo de `manifest.json`

```json
{
  "id": "mi.addon.canales",
  "name": "Mis Canales",
  "version": "1.0.0",
  "description": "Lista personal de canales",
  "author": "Usuario"
}
```

### Ejemplo de `index.json`

```json
{
  "categories": [
    {
      "name": "Noticias",
      "channels": [
        {
          "id": "cnn",
          "name": "CNN",
          "url": "https://ejemplo.com/cnn.m3u8",
          "logo": "https://ejemplo.com/cnn.png",
          "group": "Noticias",
          "country": "US",
          "language": "en"
        }
      ]
    },
    {
      "name": "Deportes",
      "channels": [
        {
          "id": "espn",
          "name": "ESPN",
          "url": "https://ejemplo.com/espn.m3u8",
          "logo": "https://ejemplo.com/espn.png",
          "group": "Deportes"
        }
      ]
    }
  ]
}
```

También se acepta formato plano:

```json
{
  "channels": [
    {
      "name": "Canal 1",
      "url": "https://...",
      "logo": "https://..."
    }
  ]
}
```

## Dependencias necesarias

Asegúrate de tener en `pubspec.yaml`:

```yaml
dependencies:
  http: ^1.2.0
  path_provider: ^2.1.0
  shared_preferences: ^2.2.0
  uuid: ^4.0.0
  video_player: ^2.8.0
  wakelock_plus: ^1.1.0
```

## Notas

- En TV siempre se fuerza orientación landscape.
- El player de canal es **live** (sin seek / sin barra de progreso).
- Los addons sin `logo.png` / `logo.jpg` se ignoran.
- Las listas M3U8 se pueden activar/desactivar individualmente.
```
