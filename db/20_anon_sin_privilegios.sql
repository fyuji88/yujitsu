-- ============================================================
--  BJJ TRACKER — `anon` sin privilegios   ·   Migracion bjj_25
-- ============================================================
--
--  EL ARREGLO NO ES EL BARRIDO, ES EL DEFECTO.
--
--  `pg_default_acl` concedia a `anon` los privilegios completos sobre TODA
--  tabla nueva del esquema `public`, y por partida doble: una entrada para las
--  que crea `postgres` y otra para las que crea `supabase_admin`. Revocar las
--  31 de hoy no arregla nada — la proxima migracion vuelve a abrir el agujero
--  sin que nadie lo note.
--
--  EL ESCENARIO QUE HAY QUE EVITAR no es el de hoy. Hoy ninguna politica de
--  escritura le aplica a `anon`, asi que el `grant` no le sirve de nada. Es
--  este otro: alguien crea una tabla y se olvida de `enable row level
--  security`. Con el grant puesto, esa tabla NACE legible y escribible por
--  cualquiera con la clave publica, que va dentro del bundle que sirve Vercel.
--  Una linea de despiste y es una brecha. Sin el grant, ese mismo despiste no
--  basta: hacen falta dos errores en vez de uno.
--
--  ESTADO OBJETIVO: `anon` no tiene NINGUN privilegio sobre tablas ni vistas, y
--  solo `EXECUTE` explicito sobre las funciones que sirvan flujos de antes del
--  login.
--
--  ¿Y CUALES SON ESOS FLUJOS? Ninguno, comprobado antes de revocar: las tres
--  pantallas que se ven sin sesion —`/login`, `/auth/callback` y
--  `/auth/reset`— usan EXCLUSIVAMENTE `supabase().auth.*`, que habla con
--  GoTrue y no con PostgREST. Cero consultas a tablas y cero llamadas a
--  funciones antes de entrar. El enlace del invitado tampoco cuenta: la
--  pantalla de quedadas va dentro de `<Marco>`, que exige sesion.
--
--  Si algun dia hace falta algo antes del login, la puerta es una funcion
--  SECURITY DEFINER estrecha con `grant execute to anon`, nunca una tabla.
--
--  A `authenticated` NO SE LE TOCA NADA: ahi manda la RLS, y funciona.
-- ============================================================

-- ------------------------------------------------------------
-- 1 · Lo que ya existe
-- ------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

-- Y ADEMAS a `PUBLIC`, o lo anterior no sirve de nada para las funciones.
--
-- Postgres concede `EXECUTE` a `PUBLIC` en toda funcion nueva, y `anon` es
-- parte de `PUBLIC`: revocarle a `anon` deja el permiso heredado intacto. Se
-- ve en el `proacl`, donde el grantee vacio es PUBLIC:
--
--   {=X/postgres, postgres=X/postgres, authenticated=X/postgres, ...}
--    ^ este
--
-- Es la misma trampa que obligo a mirar `PUBLIC` en la bateria de RLS. Aqui
-- costo siete funciones que `anon` seguia pudiendo llamar despues del revoke.
--
-- Se comprobo antes de hacerlo que las 17 funciones de `public` son todas
-- nuestras y ninguna viene de una extension, asi que no se rompe nada de
-- terceros. `authenticated` y `service_role` tienen concesion EXPLICITA y no
-- se enteran.
revoke all on all functions in schema public from public;

-- `usage` sobre el esquema se queda: sin el, PostgREST devuelve un error feo
-- en vez de un 401 limpio, y ademas hara falta el dia que se conceda un
-- `execute` puntual.
grant usage on schema public to anon;

-- ------------------------------------------------------------
-- 2 · Y lo que venga
--
-- Las dos mitades. La de `supabase_admin` es la que se suele olvidar, y es
-- justo la que aplica cuando una migracion se ejecuta desde el panel o desde
-- la API de Supabase en vez de con `psql` como `postgres`.
-- ------------------------------------------------------------
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on functions from anon;
alter default privileges in schema public revoke execute on functions from public;

-- La de `supabase_admin` va condicionada porque ese rol solo existe en
-- Supabase: en un Postgres pelado —el local y el del CI— no esta, y sin el
-- `if` la migracion entera se cae ahi. Que las migraciones apliquen limpias
-- desde cero en un Postgres cualquiera es justo lo que va a comprobar el CI.
-- Y ADEMAS puede no dejarnos: en Supabase gestionado, `postgres` NO es miembro
-- de `supabase_admin`, asi que cambiar sus privilegios por defecto da
-- "permission denied to change default privileges". Se intenta y, si no se
-- puede, se dice y se sigue — en vez de tumbar la migracion entera por una
-- parte que ademas casi nunca aplica.
--
-- ¿Cuanto importa que no se pueda? Poco, y conviene saber por que: esa entrada
-- solo actua cuando `supabase_admin` CREA una tabla en `public`, y nuestras
-- migraciones se aplican como `postgres` — con `psql`, con la CLI o desde el
-- editor del panel. Las tablas de la app las crea `postgres`, y esa mitad si
-- queda cerrada. La otra la usa el propio Supabase para sus cosas.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    raise notice 'No hay rol supabase_admin (Postgres pelado): nada que hacer.';
    return;
  end if;
  execute 'alter default privileges for role supabase_admin in schema public '
          'revoke all on tables from anon';
  execute 'alter default privileges for role supabase_admin in schema public '
          'revoke all on sequences from anon';
  execute 'alter default privileges for role supabase_admin in schema public '
          'revoke all on functions from anon';
  execute 'alter default privileges for role supabase_admin in schema public '
          'revoke execute on functions from public';
  raise notice 'Cerrada tambien la mitad de supabase_admin.';
exception when insufficient_privilege then
  raise notice
    'SIN PERMISO para tocar los privilegios por defecto de supabase_admin. '
    'Queda cerrada la mitad de `postgres`, que es la que aplica a las '
    'migraciones de la app. Para cerrar la otra hace falta el rol supabase_admin, '
    'que en el plan gestionado no tenemos.';
end $$;

-- ------------------------------------------------------------
-- 3 · Lo que `anon` SI necesita: nada, de momento
--
-- Se deja el hueco escrito para que quien lo necesite sepa donde ponerlo y con
-- que forma:
--
--   grant execute on function public.<lo_que_sea>(...) to anon;
--
-- Y que sea SECURITY DEFINER y devuelva lo justo. Cambiar una lectura general
-- por una funcion estrecha y con proposito es el patron; abrir una tabla "un
-- momentito" no lo es.
-- ------------------------------------------------------------
