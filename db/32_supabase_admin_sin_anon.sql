-- ============================================================
--  BJJ TRACKER — La otra mitad: supabase_admin   ·   Migracion bjj_37
-- ============================================================
--
--  ESTA MIGRACION ESTA HECHA PARA FALLAR EN PRODUCCION, y no es un descuido:
--  es lo que se pidio. `bjj_25` intento cerrar esta mitad y, al no poder, se
--  limito a un `raise notice`. Un aviso dentro de una migracion no lo lee
--  nadie: el `psql` dice `NOTICE`, la migracion dice que fue bien, y el
--  agujero sigue ahi. Prefiero que pare y se vea.
--
--  QUE ES EL AGUJERO. `pg_default_acl` tiene una entrada de `supabase_admin`
--  para el esquema `public` que da privilegios completos a `anon` sobre toda
--  TABLA nueva. La entrada de `postgres` ya esta limpia —nuestras migraciones
--  corren como `postgres`—, pero lo que se crea desde el panel puede acabar
--  siendo de `supabase_admin`, y esa tabla nace legible por cualquiera con la
--  clave publica, que va dentro del bundle que sirve Vercel.
--
--  Hoy no hay ninguna tabla asi: es una trampa para el futuro, no una brecha
--  abierta. Por eso no bloquea nada mas — vive en su propio fichero para que
--  el arreglo de `bjj_36` pueda aplicarse aunque esta se plante.
--
--  POR QUE FALLA. `alter default privileges for role supabase_admin` exige ser
--  ese rol o ser miembro suyo, y `postgres` no lo es en un proyecto Supabase.
--  Comprobado contra produccion: `insufficient_privilege`.
--
--  QUE HAY QUE HACER, Felipe: entrar en el panel de Supabase, SQL Editor, y
--  pegar esto tal cual —alli la consulta corre con mas privilegios que los que
--  tiene el pooler—:
--
--      alter default privileges for role supabase_admin in schema public
--        revoke all on tables from anon;
--      alter default privileges for role supabase_admin in schema public
--        revoke all on sequences from anon;
--      alter default privileges for role supabase_admin in schema public
--        revoke all on functions from anon;
--
--  Y despues volver a aplicar este fichero: si quedo cerrado, pasa en silencio.
--
--  EN LOCAL Y EN CI NO HAY `supabase_admin`, asi que no hace nada y CI sigue
--  verde. Eso es a proposito: no quiero que el CI se ponga rojo por algo que
--  solo se puede arreglar desde un panel al que el CI no entra.
-- ============================================================

begin;

do $$
declare abierto text;
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    raise notice '(no existe supabase_admin: esto es un Postgres pelado, nada que cerrar)';
    return;
  end if;

  -- Se intenta. Si se puede, estupendo y no hay nada que contar.
  begin
    execute 'alter default privileges for role supabase_admin in schema public '
            'revoke all on tables from anon';
    execute 'alter default privileges for role supabase_admin in schema public '
            'revoke all on sequences from anon';
    execute 'alter default privileges for role supabase_admin in schema public '
            'revoke all on functions from anon';
  exception when insufficient_privilege then
    -- Se traga aqui a proposito: el fallo util no es "no pude intentarlo",
    -- es "sigue abierto", y eso se comprueba abajo. Asi, el dia que Felipe lo
    -- cierre desde el panel, este fichero pasa sin tocar nada.
    null;
  end;

  -- LO QUE MANDA ES EL ESTADO, no si el intento fue posible.
  select string_agg(distinct d.defaclobjtype::text, ', ')
    into abierto
    from pg_default_acl d, aclexplode(d.defaclacl) a
   where d.defaclrole = 'supabase_admin'::regrole
     and d.defaclnamespace = 'public'::regnamespace
     and a.grantee = 'anon'::regrole;

  if abierto is not null then
    raise exception
      'SIGUE ABIERTO: supabase_admin le regala privilegios a anon sobre todo '
      'objeto nuevo de public (tipos: %). No lo puedo cerrar desde aqui. '
      'Esta en la cabecera de db/32 el SQL para pegar en el panel.', abierto
      using errcode = 'insufficient_privilege';
  end if;

  raise notice 'OK  supabase_admin ya no le da nada a anon';
end $$;

commit;
