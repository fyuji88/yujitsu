-- ============================================================
--  Lo que Supabase trae de fábrica y un Postgres pelado no
--
--    psql "$CI" -f db/ci/00_bootstrap.sql
--
--  Es lo mínimo para poder aplicar `db/*.sql` desde cero en un Postgres
--  cualquiera —el del CI, o uno local recién creado— y correr las pruebas.
--  **No se aplica nunca a producción**: allí todo esto ya existe, y creado por
--  Supabase, no por nosotros.
--
--  Va en un fichero del repositorio y no incrustado en el YAML del CI a
--  propósito: así se puede reproducir a mano lo que hace el CI, que es la
--  única forma de depurar un fallo de CI sin volverse loco.
--
--  FIDELIDAD, NO ATAJO. La primera versión de esto creó `auth.users` con solo
--  `id` y `email`, y el trigger `bjj_08` reventó pidiendo
--  `raw_user_meta_data`. Un bootstrap que se parece pero no cuadra hace fallar
--  las pruebas por el motivo equivocado, que es peor que no tenerlo.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- Los tres roles de Supabase
--
-- `anon` es el de la clave pública que va en el bundle; `authenticated`, el de
-- quien ha entrado; `service_role` se salta la RLS y no lo usa la app.
-- ------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;

-- Los privilegios por defecto TAL Y COMO LOS DEJA SUPABASE, con el agujero
-- incluido. No se corrigen aquí: los corrige `db/20_anon_sin_privilegios.sql`,
-- que es la migración que hay que probar. Si el bootstrap ya viniera limpio,
-- el CI daría verde sin haber comprobado nada.
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

-- ------------------------------------------------------------
-- El esquema `auth`
--
-- Solo lo que tocan las migraciones: la tabla de usuarios con las columnas que
-- lee el trigger `bjj_08`, y `auth.uid()`, que es de lo que cuelga media RLS.
-- ------------------------------------------------------------
create schema if not exists auth;

create table if not exists auth.users (
  id                  uuid primary key,
  email               text,
  raw_user_meta_data  jsonb not null default '{}',
  created_at          timestamptz not null default now()
);

create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', 'anon')
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant select on auth.users to authenticated, service_role;

-- El historial de migraciones, que en Supabase crea su CLI. Aquí solo hace
-- falta para que exista si algo lo consulta.
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text primary key,
  name    text
);
