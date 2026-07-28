# Esquema

Copia de lo que está desplegado en Supabase (proyecto `idzlxkxeadrcolcnmoeo`),
para poder leerlo y probarlo sin entrar al panel.

Migraciones aplicadas en producción, en orden:

| Versión | Nombre | Fichero aquí |
|---|---|---|
| 20260728131027 | bjj_01_esquema_base | `01_esquema_base.sql` |
| 20260728131121 | bjj_02_seed_diccionario | `02_seed_diccionario.sql` |
| 20260728131158 | bjj_03_vistas_analisis | `03_vistas_analisis.sql` |
| 20260728131232 | bjj_04_modo_observador | `04_modo_observador.sql` |
| 20260728131329 | bjj_05_sacar_helper_de_la_api | incluido en `01` |
| 20260728131447 | bjj_06_fk_diferidas_al_borrar | incluido en `01` |
| 20260728133654 | bjj_07_alta_de_companeros | incluido en `01` |
| 20260728134345 | bjj_08_ficha_al_registrarse | `05_ficha_al_registrarse.sql` |
| 20260728232708 | bjj_09_rpc_roll_observado | `06_rpc_roll_observado.sql` |

Las migraciones 05 a 07 fueron correcciones que aquí ya están integradas en
`01_esquema_base.sql`, para que ejecutar estos ficheros de cero sobre una base
limpia deje el mismo estado que hay en producción.

`99_datos_demo_opcional.sql` son 3 meses de entrenamientos simulados (41
sesiones, 180 rolls, 679 eventos). Sirve para ver los heatmaps con volumen antes
de tener datos reales. Se borra con `truncate practicantes cascade;`.

## Probar un cambio antes de aplicarlo

Nunca contra producción directamente. Con la CLI de Supabase:

```bash
supabase start                     # Postgres local en Docker
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" -f db/01_esquema_base.sql
```

**Si no hay Docker** — en un portátil de empresa lo normal es que no lo haya, y
que el instalador de Postgres pida admin — sirven los binarios sueltos, que se
descomprimen y ya está, sin instalar nada en el sistema:

```bash
# https://get.enterprisedb.com/postgresql/postgresql-17.6-1-windows-x64-binaries.zip
initdb -D ./pgdata -U postgres -A trust --encoding=UTF8 --locale=C
postgres -D ./pgdata -p 55432 -c listen_addresses=127.0.0.1 &
createdb -h 127.0.0.1 -p 55432 -U postgres bjj
```

Luego los ficheros en orden: `01`, `02`, `03`, `04`, `05`, `06`.

### El apaño de `auth`, y por qué el obvio no vale

El esquema necesita `auth.users` y `auth.uid()`. La versión corta —
`create function auth.uid() ... select null::uuid` — deja cargar el esquema,
pero **no sirve para probar la RLS**: con `auth.uid()` siempre a null, toda
política deniega y todos los tests "pasan" por el motivo equivocado.

Para probar la RLS de verdad hace falta el `auth.uid()` real, que lee el claim
que inyecta PostgREST:

```sql
create role anon          nologin noinherit;
create role authenticated nologin noinherit;
create role service_role  nologin noinherit bypassrls;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

grant usage on schema auth, public to anon, authenticated, service_role;
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
```

Con eso, cada test se pone en la piel de un usuario concreto:

```sql
begin;
  select set_config('request.jwt.claims', '{"sub":"<uuid del usuario>"}', true);
  set local role authenticated;
  -- ... aqui la comprobacion ...
rollback;
```

Sin el `set local role`, la sesión sigue siendo superusuario y **se salta la RLS
entera**: es el error que hace que un test de permisos verde no signifique nada.
