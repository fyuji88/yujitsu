-- ============================================================
--  BJJ TRACKER — Quedadas e inscripciones   ·   FASE 3
--  Migracion bjj_16. Va despues de 09 y 10.
-- ============================================================
--
--  EL NOMBRE
--  `eventos` esta cogido: es la tabla central del modelo, cada accion de cada
--  roll. Los open mats se llaman `quedadas`. No lo cambies.
--
--  LA JERARQUIA
--  Un grupo organiza quedadas. Una quedada agrupa sesiones, que ya existen y
--  ya contienen los rolls. El informe, el feed y el ranking son derivados: no
--  hay ni una tabla mas para calcularlos.
-- ============================================================

create type bjj_estado_quedada     as enum ('abierta', 'cerrada', 'cancelada');
create type bjj_estado_inscripcion as enum ('apuntado', 'lista_espera', 'cancelado');

create table quedadas (
  id               uuid primary key default gen_random_uuid(),
  grupo_id         uuid not null references grupos(id) on delete cascade,
  titulo           text not null,
  fecha            date not null,
  hora_inicio      time,
  duracion_min     smallint check (duracion_min between 0 and 600),
  lugar            text,
  plazas_max       smallint check (plazas_max > 0),   -- null = sin limite
  modalidad        bjj_modalidad not null default 'nogi',
  admite_externos  boolean not null default true,
  -- Enlace para compartir. Ver el modelo de privacidad mas abajo.
  token_invitacion text unique not null default replace(gen_random_uuid()::text, '-', ''),
  notas            text,
  estado           bjj_estado_quedada not null default 'abierta',
  creado_por       uuid references practicantes(id) on delete set null,
  created_at       timestamptz not null default now()
);

create index quedadas_grupo_fecha_idx on quedadas (grupo_id, fecha desc);

create table inscripciones (
  id             uuid primary key default gen_random_uuid(),
  quedada_id     uuid not null references quedadas(id) on delete cascade,
  practicante_id uuid not null references practicantes(id) on delete cascade,
  estado         bjj_estado_inscripcion not null default 'apuntado',
  orden          smallint,          -- posicion en la lista de espera
  es_externo     boolean not null default false,
  created_at     timestamptz not null default now(),
  unique (quedada_id, practicante_id)
);

create index inscripciones_quedada_idx on inscripciones (quedada_id, estado);

alter table sesiones
  add column quedada_id uuid references quedadas(id) on delete set null;
create index sesiones_quedada_idx on sesiones (quedada_id);

comment on column sesiones.quedada_id is
  'A nivel de SESION, no de roll: todos los rolls de esa tarde en ese sitio son '
  'de esa quedada. Preguntarlo una vez en vez de en cada roll son cuatro toques '
  'menos por tarde, y se puede corregir desde el resumen.';


-- ============================================================
--  LOS EXTERNOS — DONDE SE COLA UN FALLO DE PRIVACIDAD
-- ============================================================
--
--  El open mat de los domingos es 90 % gente del grupo y 10 % de otros
--  gimnasios. Una quedada tiene que admitir a alguien que NO es miembro, sin
--  por eso darle acceso al grupo entero.
--
--  La decision de diseño que lo garantiza: **un externo nunca recibe permiso
--  de lectura sobre `quedadas`**. La RLS de esa tabla es solo para miembros.
--  El externo pasa siempre por dos funciones SECURITY DEFINER que devuelven
--  exactamente una quedada —la de su token— y nada mas:
--
--    quedada_por_token(token)   ->  esa quedada, para poder verla
--    apuntarse_a_quedada(id, token) -> apuntarse a esa quedada
--
--  Asi no hay ninguna politica que "casi" acierte. Si el externo consulta
--  /rest/v1/quedadas directamente, recibe cero filas, no la suya. Y del feed
--  del grupo y de los rolls de los demas no ve nada, porque bjj_15 ya los
--  recorto a quien comparte grupo.
--
--  Lo que SI comparte: los rolls que el externo registre en esa quedada son
--  visibles para el grupo, porque la quedada es del grupo. Eso es intencionado.
-- ============================================================

alter table quedadas      enable row level security;
alter table inscripciones enable row level security;

create policy quedadas_lectura_grupo on quedadas
  for select to authenticated
  using (grupo_id in (select private.mis_grupos()));

create policy quedadas_admin on quedadas
  for all to authenticated
  using (private.es_admin(grupo_id))
  with check (private.es_admin(grupo_id));

-- Las inscripciones se ven si ves la quedada, y la tuya siempre.
create policy inscripciones_lectura on inscripciones
  for select to authenticated
  using (
    practicante_id = private.practicante_actual()
    or quedada_id in (select id from quedadas where grupo_id in (select private.mis_grupos()))
  );

-- Apuntarse y borrarse pasa por las funciones, que controlan las plazas. Aqui
-- solo se deja al admin tocar a mano la lista.
create policy inscripciones_admin on inscripciones
  for all to authenticated
  using (quedada_id in (select id from quedadas where private.es_admin(grupo_id)))
  with check (quedada_id in (select id from quedadas where private.es_admin(grupo_id)));


-- ------------------------------------------------------------
-- La quedada de un token, y solo esa.
-- ------------------------------------------------------------
create or replace function quedada_por_token(p_token text)
returns table (
  id uuid, titulo text, fecha date, hora_inicio time, duracion_min smallint,
  lugar text, plazas_max smallint, modalidad bjj_modalidad,
  estado bjj_estado_quedada, grupo text, apuntados bigint, libres int
)
language sql
stable
security definer
set search_path = public
as $$
  select q.id, q.titulo, q.fecha, q.hora_inicio, q.duracion_min,
         q.lugar, q.plazas_max, q.modalidad, q.estado, g.nombre,
         count(i.id) filter (where i.estado = 'apuntado'),
         case when q.plazas_max is null then null
              else q.plazas_max - count(i.id) filter (where i.estado = 'apuntado')::int
         end
    from quedadas q
    join grupos g on g.id = q.grupo_id
    left join inscripciones i on i.quedada_id = q.id
   where q.token_invitacion = p_token
     and q.admite_externos
   group by q.id, g.nombre
$$;


-- ------------------------------------------------------------
-- LAS PLAZAS SE CONTROLAN AQUI, NUNCA EN EL CLIENTE
--
--   Dos personas dandole a "apuntarme" a la vez con una plaza libre es el caso
--   clasico, y el cliente no puede resolverlo: los dos leen "queda una" antes
--   de que ninguno escriba. El advisory lock serializa por quedada — el mismo
--   patron que usa registrar_roll_observado.
-- ------------------------------------------------------------
create or replace function apuntarse_a_quedada(p_quedada uuid, p_token text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo        uuid;
  q           quedadas%rowtype;
  v_miembro   boolean;
  v_externo   boolean := false;
  v_ins       inscripciones%rowtype;
  v_apuntados int;
  v_estado    bjj_estado_inscripcion;
  v_orden     smallint;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien se apunta no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_quedada::text, 0));

  select * into q from quedadas where id = p_quedada;
  if not found then
    raise exception 'esa quedada no existe' using errcode = 'no_data_found';
  end if;
  if q.estado <> 'abierta' then
    raise exception 'la quedada esta %', q.estado using errcode = 'check_violation';
  end if;

  v_miembro := q.grupo_id in (select private.mis_grupos());
  if not v_miembro then
    -- Sin ser miembro solo se entra con el token, y solo si la quedada los
    -- admite. El token no abre nada mas que esta quedada.
    if not q.admite_externos or p_token is null
       or p_token <> q.token_invitacion then
      raise exception 'esta quedada no admite invitados o el enlace no vale'
        using errcode = 'insufficient_privilege';
    end if;
    v_externo := true;
  end if;

  -- Idempotente: apuntarse dos veces no crea dos filas ni te manda a la lista.
  select * into v_ins from inscripciones
   where quedada_id = p_quedada and practicante_id = v_yo;
  if found and v_ins.estado in ('apuntado', 'lista_espera') then
    return jsonb_build_object('estado', v_ins.estado, 'orden', v_ins.orden,
                              'es_externo', v_ins.es_externo, 'creado', false);
  end if;

  select count(*) into v_apuntados from inscripciones
   where quedada_id = p_quedada and estado = 'apuntado';

  if q.plazas_max is null or v_apuntados < q.plazas_max then
    v_estado := 'apuntado';
    v_orden  := null;
  else
    v_estado := 'lista_espera';
    select coalesce(max(orden), 0) + 1 into v_orden from inscripciones
     where quedada_id = p_quedada and estado = 'lista_espera';
  end if;

  insert into inscripciones (quedada_id, practicante_id, estado, orden, es_externo)
  values (p_quedada, v_yo, v_estado, v_orden, v_externo)
  on conflict (quedada_id, practicante_id)
  do update set estado = excluded.estado, orden = excluded.orden,
                es_externo = excluded.es_externo;

  return jsonb_build_object('estado', v_estado, 'orden', v_orden,
                            'es_externo', v_externo, 'creado', true);
end;
$$;


-- ------------------------------------------------------------
-- Borrarse, y que suba el primero de la lista en la misma transaccion.
--
--   Si la promocion se hiciera fuera, entre el borrado y la subida hay una
--   ventana en la que la plaza esta libre y nadie la tiene.
-- ------------------------------------------------------------
create or replace function cancelar_inscripcion(p_quedada uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo        uuid;
  v_ins       inscripciones%rowtype;
  v_promovido uuid;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'no hay ficha de practicante' using errcode = 'insufficient_privilege';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_quedada::text, 0));

  select * into v_ins from inscripciones
   where quedada_id = p_quedada and practicante_id = v_yo;
  if not found or v_ins.estado = 'cancelado' then
    return jsonb_build_object('cancelado', false, 'promovido', null);
  end if;

  update inscripciones set estado = 'cancelado', orden = null
   where id = v_ins.id;

  -- Solo se libera plaza si quien se va estaba dentro, no en la lista.
  if v_ins.estado = 'apuntado' then
    update inscripciones set estado = 'apuntado', orden = null
     where id = (select id from inscripciones
                  where quedada_id = p_quedada and estado = 'lista_espera'
                  order by orden, created_at
                  limit 1)
    returning practicante_id into v_promovido;
  end if;

  return jsonb_build_object('cancelado', true, 'promovido', v_promovido);
end;
$$;

revoke all on function quedada_por_token(text)            from public, anon;
revoke all on function apuntarse_a_quedada(uuid, text)    from public, anon;
revoke all on function cancelar_inscripcion(uuid)         from public, anon;
grant execute on function quedada_por_token(text)         to authenticated;
grant execute on function apuntarse_a_quedada(uuid, text) to authenticated;
grant execute on function cancelar_inscripcion(uuid)      to authenticated;


-- ------------------------------------------------------------
-- La quedada de hoy en la que estas apuntado, para preseleccionarla al
-- registrar. En el caso normal son cero toques.
-- ------------------------------------------------------------
create or replace view v_mi_quedada_hoy with (security_invoker = on) as
select q.*, i.estado as mi_estado
  from quedadas q
  join inscripciones i on i.quedada_id = q.id
 where i.practicante_id = private.practicante_actual()
   and i.estado = 'apuntado'
   and q.fecha = current_date
   and q.estado = 'abierta';
