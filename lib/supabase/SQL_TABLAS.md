# Tablas Supabase – lolplustv

Hay **dos tipos** de proyecto:

---

## A) Proyecto ADMIN de la app (lo configura el desarrollador)

Solo se usa para la tabla `tv_link` (vincular TV con código).

**Dónde poner las credenciales:** archivo de la app  
`lib/supabase/supabase_admin_constants.dart`

```dart
const String kAdminSupabaseUrl = 'https://TU_PROYECTO_ADMIN.supabase.co';
const String kAdminSupabaseAnonKey = 'eyJ...';
```

**SQL a ejecutar en el proyecto ADMIN:**

```sql
create table if not exists public.tv_link (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  supabase_url text,
  supabase_anon_key text,
  used boolean default false,
  created_at timestamptz default now(),
  expires_at timestamptz default (now() + interval '15 minutes')
);

create index if not exists idx_tv_link_code on public.tv_link (code);

alter table public.tv_link enable row level security;

create policy "all tv_link"
  on public.tv_link
  for all
  using (true)
  with check (true);
```

Los usuarios **no** ponen estos datos. Solo el admin de la app.

---

## B) Proyecto del USUARIO (cada uno el suyo)

El usuario crea su proyecto en supabase.com y pega URL + anon key en  
**Ajustes → Supabase** de la app.

**SQL a ejecutar en el proyecto del USUARIO:**

```sql
-- Perfiles
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  avatar_url text,
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;
create policy "all profiles" on public.profiles for all using (true) with check (true);

-- Guardados
create table if not exists public.guardados (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  idcontenido integer not null,
  poster text,
  titulo text not null,
  tipo text not null,
  created_at timestamptz default now(),
  unique (user_id, idcontenido)
);

alter table public.guardados enable row level security;
create policy "all guardados" on public.guardados for all using (true) with check (true);
```

---

## Flujo TV link

1. Admin ya dejó configurado `supabase_admin_constants.dart` + tabla `tv_link`.
2. Usuario en móvil: Ajustes → Supabase → su URL + KEY → elige perfil.
3. TV: Configuración → Supabase → Generar código.
4. Móvil: escribe el código → Vincular (se guarda en el proyecto ADMIN).
5. TV hace polling, recibe URL+KEY del usuario y las guarda localmente.
6. TV pide elegir perfil (en el proyecto del usuario).
