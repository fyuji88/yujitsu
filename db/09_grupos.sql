-- ============================================================
--  BJJ TRACKER — Grupos, miembros y roles   ·   FASE 1
--  Migracion bjj_14. Va despues de 01..08.
-- ============================================================
--
--  POR QUE UNA TABLA DE MIEMBROS Y NO UNA COLUMNA
--
--  Hasta aqui `academia` era texto libre en `practicantes` y en `sesiones`.
--  "Gullo", "gullo bjj" y "Gullo Jiu-Jitsu" son tres academias distintas y
--  nadie se entera. Y no habia forma de decir quien manda ni quien pertenece
--  a que.
--
--  La pertenencia va en su propia tabla porque la gente entrena en mas de un
--  sitio y **el rol es por grupo, no global**. Una columna en `practicantes`
--  obliga a rehacerlo entero en cuanto aparezca el segundo grupo.
--
--  Se llama `grupos` y no `gimnasios` porque no siempre es un gimnasio: el
--  open mat de los domingos en casa de alguien es la mitad del caso de uso.
--  En la interfaz la etiqueta puede ser "Gimnasio"; el esquema no miente.
-- ============================================================

create type bjj_rol_grupo      as enum ('admin', 'miembro');
create type bjj_estado_miembro as enum ('activo', 'baja');

create table grupos (
  id             uuid primary key default gen_random_uuid(),
  nombre         text not null,
  slug           text unique not null,
  ciudad         text,
  -- El admin lo dice en el vestuario. Se puede regenerar si se filtra.
  codigo_union   text unique not null,
  -- Ver fase 4: enciende los titulos negativos del informe. Apagado por
  -- defecto a proposito — un titulo negativo automatico le sienta mal a
  -- alguien tarde o temprano, y esa decision la toma un humano.
  modo_cachondeo boolean not null default false,
  creado_por     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now()
);

create table miembros_grupo (
  grupo_id       uuid not null references grupos(id) on delete cascade,
  practicante_id uuid not null references practicantes(id) on delete cascade,
  rol            bjj_rol_grupo not null default 'miembro',
  estado         bjj_estado_miembro not null default 'activo',
  created_at     timestamptz not null default now(),
  primary key (grupo_id, practicante_id)
);

create index miembros_practicante_idx on miembros_grupo (practicante_id)
  where estado = 'activo';

alter table sesiones add column grupo_id uuid references grupos(id) on delete set null;
create index sesiones_grupo_idx on sesiones (grupo_id);

comment on column sesiones.grupo_id is
  'De que grupo es la sesion. `academia` se queda de momento: se quita en otra '
  'migracion cuando este claro que nada la lee.';


-- ------------------------------------------------------------
-- 1. Helpers de pertenencia
--
--    Viven en `private` porque PostgREST solo publica `public`, y una funcion
--    SECURITY DEFINER expuesta en /rest/v1/rpc/ es un aviso del linter.
--
--    SON SECURITY DEFINER POR NECESIDAD, NO POR COMODIDAD: las politicas de
--    `miembros_grupo` los llaman, y si leyeran esa tabla con la RLS puesta se
--    entraria en recursion infinita — la politica preguntaria a la funcion,
--    que preguntaria a la tabla, que preguntaria a la politica. Siendo DEFINER
--    leen como el dueño, que se salta la RLS, y el ciclo se corta.
-- ------------------------------------------------------------
create or replace function private.mis_grupos()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select grupo_id from miembros_grupo
   where practicante_id = private.practicante_actual()
     and estado = 'activo'
$$;

create or replace function private.es_admin(p_grupo uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from miembros_grupo
     where grupo_id = p_grupo
       and practicante_id = private.practicante_actual()
       and rol = 'admin'
       and estado = 'activo')
$$;

/*
  Lo tuyo siempre es tuyo, aunque no compartas grupo con nadie. Sin esa
  primera condicion, alguien sin grupo dejaria de ver sus propios datos.
*/
create or replace function private.comparte_grupo(p_practicante uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_practicante = private.practicante_actual()
      or exists (
        select 1
          from miembros_grupo m1
          join miembros_grupo m2 on m2.grupo_id = m1.grupo_id
         where m1.practicante_id = private.practicante_actual()
           and m1.estado = 'activo'
           and m2.practicante_id = p_practicante
           and m2.estado = 'activo')
$$;

revoke all on function private.mis_grupos()            from public;
revoke all on function private.es_admin(uuid)          from public;
revoke all on function private.comparte_grupo(uuid)    from public;
grant execute on function private.mis_grupos()         to authenticated, service_role;
grant execute on function private.es_admin(uuid)       to authenticated, service_role;
grant execute on function private.comparte_grupo(uuid) to authenticated, service_role;


-- ------------------------------------------------------------
-- 2. RLS de las tablas nuevas
--
--    El modelo de permisos se queda deliberadamente pequeño: admin toca el
--    grupo y sus miembros, miembro solo mira. Cuanto menos hay que decidir,
--    menos superficie para un fallo de privacidad.
-- ------------------------------------------------------------
alter table grupos          enable row level security;
alter table miembros_grupo  enable row level security;

create policy grupos_lectura on grupos
  for select to authenticated
  using (id in (select private.mis_grupos()));

create policy grupos_admin on grupos
  for update to authenticated
  using (private.es_admin(id))
  with check (private.es_admin(id));

-- Crear un grupo lo puede hacer cualquiera: te haces admin del tuyo en la
-- misma llamada (ver crear_grupo mas abajo).
create policy grupos_alta on grupos
  for insert to authenticated
  with check (creado_por = auth.uid());

create policy miembros_lectura on miembros_grupo
  for select to authenticated
  using (grupo_id in (select private.mis_grupos()));

-- El alta manual de un contacto la hace el admin. Se comprueba AQUI y no en
-- el cliente: si la interfaz ofreciera el boton a un miembro, veria un error
-- en vez de un boton ausente, que es peor.
create policy miembros_alta_admin on miembros_grupo
  for insert to authenticated
  with check (private.es_admin(grupo_id));

create policy miembros_cambio_admin on miembros_grupo
  for update to authenticated
  using (private.es_admin(grupo_id))
  with check (private.es_admin(grupo_id));

create policy miembros_baja_admin on miembros_grupo
  for delete to authenticated
  using (private.es_admin(grupo_id));


-- ------------------------------------------------------------
-- 3. Las dos vias de alta
-- ------------------------------------------------------------

/* Codigo legible en voz alta: 'GULLO-7X4'. Sin I, O, 0 ni 1, que se
   confunden al dictarlos en un vestuario. */
create or replace function private.nuevo_codigo(p_nombre text)
returns text
language sql
volatile
set search_path = public
as $$
  select upper(regexp_replace(substring(coalesce(nullif(trim(p_nombre), ''), 'GRUPO')
                                        from 1 for 6), '[^a-zA-Z0-9]', '', 'g'))
    || '-' ||
    string_agg(substring('ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
                         from (floor(random() * 32) + 1)::int for 1), '')
    from generate_series(1, 3)
$$;

create or replace function unirse_con_codigo(p_codigo text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_grupo uuid;
  v_yo    uuid;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien se une no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  select id into v_grupo from grupos
   where upper(codigo_union) = upper(trim(p_codigo));
  if v_grupo is null then
    raise exception 'no hay ningun grupo con el codigo %', trim(p_codigo)
      using errcode = 'no_data_found';
  end if;

  -- Idempotente: la gente pulsa dos veces. Y si estabas de baja, volver a
  -- entrar te reactiva en vez de fallar.
  insert into miembros_grupo (grupo_id, practicante_id, rol, estado)
  values (v_grupo, v_yo, 'miembro', 'activo')
  on conflict (grupo_id, practicante_id)
  do update set estado = 'activo';

  return v_grupo;
end;
$$;

create or replace function regenerar_codigo(p_grupo uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_codigo text;
begin
  if not private.es_admin(p_grupo) then
    raise exception 'solo un admin del grupo puede regenerar el codigo'
      using errcode = 'insufficient_privilege';
  end if;
  loop
    select private.nuevo_codigo(nombre) into v_codigo from grupos where id = p_grupo;
    exit when not exists (select 1 from grupos where codigo_union = v_codigo);
  end loop;
  update grupos set codigo_union = v_codigo where id = p_grupo;
  return v_codigo;
end;
$$;

/* Crear un grupo y quedarte de admin, en una transaccion. Por separado se
   podria crear el grupo y morir antes de hacerte admin, y quedaria un grupo
   que nadie puede administrar. */
create or replace function crear_grupo(p_nombre text, p_ciudad text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_grupo  uuid;
  v_yo     uuid;
  v_slug   text;
  v_codigo text;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien crea el grupo no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;
  if coalesce(trim(p_nombre), '') = '' then
    raise exception 'el grupo necesita un nombre';
  end if;

  v_slug := regexp_replace(lower(trim(p_nombre)), '[^a-z0-9]+', '-', 'g');
  if exists (select 1 from grupos where slug = v_slug) then
    v_slug := v_slug || '-' || substring(gen_random_uuid()::text from 1 for 4);
  end if;

  loop
    v_codigo := private.nuevo_codigo(p_nombre);
    exit when not exists (select 1 from grupos where codigo_union = v_codigo);
  end loop;

  insert into grupos (nombre, slug, ciudad, codigo_union, creado_por)
  values (trim(p_nombre), v_slug, p_ciudad, v_codigo, auth.uid())
  returning id into v_grupo;

  insert into miembros_grupo (grupo_id, practicante_id, rol, estado)
  values (v_grupo, v_yo, 'admin', 'activo');

  return v_grupo;
end;
$$;

revoke all on function unirse_con_codigo(text)   from public, anon;
revoke all on function regenerar_codigo(uuid)    from public, anon;
revoke all on function crear_grupo(text, text)   from public, anon;
grant execute on function unirse_con_codigo(text) to authenticated;
grant execute on function regenerar_codigo(uuid)  to authenticated;
grant execute on function crear_grupo(text, text) to authenticated;


-- ------------------------------------------------------------
-- 4. MIGRACION DE LO QUE YA HAY  —  LA PARTE QUE PUEDE HACER DAÑO
--
--    Si se crean los grupos y luego se recorta la RLS sin migrar, todo lo que
--    hay desaparece de la aplicacion y va a parecer que se han borrado datos.
--    Por eso va en la misma transaccion que las tablas.
--
--    Se crea un grupo por cada texto de `academia` distinto que haya en
--    sesiones, y el resto cae en el grupo por defecto. Todos los practicantes
--    entran como miembros activos del grupo por defecto: sin eso, la gente sin
--    academia escrita se quedaria fuera y dejarian de verse rolls que hoy se
--    ven.
--
--    Admin del grupo por defecto: el practicante con cuenta mas antiguo. No se
--    escribe un nombre a mano para que la migracion valga igual en local que
--    en produccion.
-- ------------------------------------------------------------
do $$
declare
  v_defecto uuid;
  v_admin   uuid;
  v_user    uuid;
  v_nombre  text;
  r         record;
begin
  if not exists (select 1 from practicantes) then
    return;   -- base vacia: no hay nada que migrar
  end if;

  select p.id, p.user_id into v_admin, v_user
    from practicantes p
   where p.user_id is not null
   order by p.created_at
   limit 1;

  -- El nombre del grupo por defecto sale de la academia mas repetida.
  select trim(academia) into v_nombre
    from sesiones
   where nullif(trim(academia), '') is not null
   group by trim(academia)
   order by count(*) desc
   limit 1;
  v_nombre := coalesce(v_nombre, 'Mi grupo');

  insert into grupos (nombre, slug, codigo_union, creado_por)
  values (v_nombre,
          regexp_replace(lower(v_nombre), '[^a-z0-9]+', '-', 'g'),
          private.nuevo_codigo(v_nombre),
          v_user)
  returning id into v_defecto;

  -- Todos dentro, y el mas antiguo con cuenta como admin.
  insert into miembros_grupo (grupo_id, practicante_id, rol, estado)
  select v_defecto, p.id,
         case when p.id = v_admin then 'admin' else 'miembro' end::bjj_rol_grupo,
         'activo'
    from practicantes p
  on conflict do nothing;

  -- Un grupo por cada academia distinta que NO sea la de por defecto.
  for r in
    select distinct trim(academia) as nombre
      from sesiones
     where nullif(trim(academia), '') is not null
       and trim(academia) <> v_nombre
  loop
    insert into grupos (nombre, slug, codigo_union, creado_por)
    values (r.nombre,
            regexp_replace(lower(r.nombre), '[^a-z0-9]+', '-', 'g'),
            private.nuevo_codigo(r.nombre),
            v_user);
  end loop;

  update sesiones s
     set grupo_id = coalesce(
           (select g.id from grupos g where g.nombre = trim(s.academia)),
           v_defecto);
end $$;
