# lolplustv – Sistema Central de Cuentas y Perfiles

## Qué cambia

- **Ya no** cada usuario crea su propio proyecto Supabase.
- Todo va a **TU** proyecto central (plan Free).
- Una **cuenta** (email + password) puede tener **hasta 5 perfiles**.
- Cada perfil tiene: nombre, avatar, backdrop, PIN de seguridad, settings (JSON).
- Historial guarda: tmdb_id, poster, tipo, **segundo exacto**, temporada y capítulo (si es serie).
- Guardados y Likes solo: tmdb_id, poster, tipo.
- Se puede entrar como **Invitado** (todo en cache local).
- TV se vincula con código de 6 dígitos desde el móvil.

---

## Paso 1 – Crear las tablas

1. Entra en [supabase.com](https://supabase.com) → tu proyecto.
2. Ve a **SQL Editor**.
3. Copia y pega el contenido de `sql/01_tablas_completas.sql`.
4. Ejecuta (Run).

---

## Paso 2 – Configurar las credenciales en la app

Abre el archivo:

```
lib/supabase/supabase_constants.dart
```

Y cambia solo estas dos líneas:

```dart
const String kSupabaseUrl = 'https://TU_PROYECTO.supabase.co';
const String kSupabaseAnonKey = 'eyJ...tu_anon_key...';
```

(Las encuentras en Supabase → Settings → API)

---

## Paso 3 – Dependencias

Asegúrate de tener en `pubspec.yaml`:

```yaml
dependencies:
  supabase_flutter: ^2.5.0   # o la versión que uses
  shared_preferences: ^2.2.0
```

Luego:

```bash
flutter pub get
```

---

## Paso 4 – Sustituir archivos en tu proyecto

Copia la carpeta `lib/supabase/` completa sobre tu `lib/supabase/` antigua.

Copia las páginas nuevas:

```
lib/features/auth/presentation/login_register_page.dart
lib/features/profile/presentation/profile_selection_page.dart
lib/features/profile/presentation/manage_profiles_page.dart
lib/features/profile/presentation/edit_profile_page.dart
lib/features/settings/presentation/account/account_settings_page.dart
```

---

## Paso 5 – Integrar en el arranque de la app

En `main.dart` o donde inicialices:

```dart
import 'package:tu_app/supabase/supabase_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSupabase.init();
  runApp(MyApp());
}
```

Cuando el usuario abra la app (o en el splash), muestra:

```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(builder: (_) => const ProfileSelectionPage()),
);
```

---

## Estructura de datos

### Cuenta (auth.users de Supabase)
| Campo        | Descripción              |
|-------------|--------------------------|
| id          | UUID                     |
| email       | Correo                   |
| password    | (manejado por Auth)      |
| created_at  | Fecha de creación        |

### Perfil (tabla profiles)
| Campo         | Descripción                          |
|--------------|--------------------------------------|
| id           | UUID                                 |
| account_id   | FK a auth.users                      |
| name         | Nombre del perfil                    |
| avatar_url   | URL del avatar                       |
| backdrop_url | Fondo de la pantalla de perfiles     |
| pin          | PIN de seguridad (opcional)          |
| settings     | JSON blob de ajustes del perfil      |
| created_at   | Fecha de creación                    |

### Historial
| Campo             | Descripción                          |
|------------------|--------------------------------------|
| tmdb_id          | ID de TMDB                           |
| poster           | URL del póster                       |
| tipo             | 'movie' o 'tv'                       |
| progress_seconds | Segundo exacto donde se quedó        |
| season           | Temporada (solo series)              |
| episode          | Capítulo (solo series)               |

### Guardados / Likes
| Campo    | Descripción     |
|---------|-----------------|
| tmdb_id | ID de TMDB      |
| poster  | URL del póster  |
| tipo    | 'movie' o 'tv'  |

---

## Flujo TV

1. En la **TV** → Ajustes de cuenta → Generar código.
2. En el **móvil** (logueado) → Ajustes de cuenta → introducir el código → Vincular.
3. La TV detecta la vinculación automáticamente.

---

## Modo invitado

Si el usuario elige "Invitado" en la pantalla de perfiles:
- No necesita cuenta.
- Historial, guardados y likes se guardan solo en SharedPreferences (cache local).
- Al crear cuenta después, no se migran automáticamente (puedes añadir migración si quieres).

---

## Notas

- El límite de 5 perfiles se aplica con un trigger en la base de datos.
- RLS protege que un usuario solo vea sus propios datos.
- El código de TV expira en 15 minutos.
