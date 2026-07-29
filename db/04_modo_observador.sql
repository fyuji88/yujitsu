-- ============================================================
--  BJJ TRACKER — Modo observador (el coach registra el roll en vivo)
--  Migración sobre 01/02/03. No rompe nada de lo ya guardado.
-- ============================================================
--
--  IDEA CLAVE
--  Un roll fisico es UNO, pero genera datos para DOS practicantes.
--  Cuando el coach lo registra, guardamos las dos filas y las unimos
--  con `roll_grupo_id`. La segunda es la primera con `actor` invertido.
--
--  Y solo `actor` se invierte: `posicion` y `rol` describen al ACTOR,
--  que sigue siendo la misma persona fisica. Si Felipe somete desde
--  montada arriba, en el roll de Pablo eso es exactamente el mismo
--  evento con actor='oponente'. Ese detalle es lo que hace que el
--  espejado sea un cambio de un solo campo y no una reinterpretacion.
-- ============================================================


-- ------------------------------------------------------------
-- 1. De donde viene el dato
-- ------------------------------------------------------------
create type bjj_origen_roll as enum (
  'propio',      -- lo registro el propio practicante
  'observador'   -- lo registro un tercero mirando (coach, companero)
);

alter table rolls
  add column registrado_por uuid references practicantes(id) on delete set null,
  add column origen         bjj_origen_roll not null default 'propio',
  add column roll_grupo_id  uuid not null default gen_random_uuid();

comment on column rolls.roll_grupo_id is
  'Une las filas que describen el MISMO roll fisico visto desde cada lado.';
comment on column rolls.registrado_por is
  'Quien pulso los botones. Distinto del practicante cuando origen = observador.';

create index rolls_grupo_idx on rolls (roll_grupo_id);


-- ------------------------------------------------------------
-- 2. Sesion contenedora: el coach registra rolls de gente que
--    quiza no ha abierto sesion hoy. Se crea al vuelo.
-- ------------------------------------------------------------
create or replace function sesion_del_dia(
  p_practicante uuid,
  p_fecha       date,
  p_modalidad   bjj_modalidad default 'gi',
  p_academia    text default null
) returns uuid
language plpgsql
set search_path = public
as $$
declare v_id uuid;
begin
  select id into v_id
    from sesiones
   where practicante_id = p_practicante
     and fecha = p_fecha
     and modalidad = p_modalidad
   order by created_at
   limit 1;

  if v_id is null then
    insert into sesiones (practicante_id, fecha, modalidad, tipo, academia, notas)
    values (p_practicante, p_fecha, p_modalidad, 'sparring', p_academia,
            'Sesion creada automaticamente desde el modo observador')
    returning id into v_id;
  end if;

  return v_id;
end;
$$;


-- ------------------------------------------------------------
-- 3. Espejar un roll al compañero
--    Devuelve el id del roll creado, o null si el oponente no usa
--    el sistema (entonces no hay a quien espejarselo).
-- ------------------------------------------------------------
create or replace function espejar_roll(p_roll_id uuid)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  r            rolls%rowtype;
  s            sesiones%rowtype;
  v_sesion     uuid;
  v_nuevo      uuid;
  v_resultado  bjj_resultado_roll;
  v_rol_inicio bjj_rol;
begin
  select * into r from rolls where id = p_roll_id;
  if not found then raise exception 'roll % no existe', p_roll_id; end if;
  if r.oponente_id is null then return null; end if;

  select * into s from sesiones where id = r.sesion_id;

  -- solo se espeja a quien tiene cuenta
  if not (select usa_sistema from practicantes where id = r.oponente_id) then
    return null;
  end if;

  -- no espejar dos veces el mismo roll fisico
  if exists (select 1 from rolls r2
              join sesiones s2 on s2.id = r2.sesion_id
             where r2.roll_grupo_id = r.roll_grupo_id
               and s2.practicante_id = r.oponente_id) then
    return null;
  end if;

  v_resultado := case r.resultado
                   when 'sumision_favor'  then 'sumision_contra'
                   when 'sumision_contra' then 'sumision_favor'
                   else r.resultado
                 end;

  -- rol_inicio SI se invierte: describe al dueño del roll, que cambia
  v_rol_inicio := case r.rol_inicio
                    when 'arriba' then 'abajo'
                    when 'abajo'  then 'arriba'
                    else 'neutral'
                  end;

  v_sesion := sesion_del_dia(r.oponente_id, s.fecha, r.modalidad, s.academia);

  insert into rolls (sesion_id, oponente_id, orden, modalidad, duracion_min,
                     posicion_inicio, rol_inicio, resultado, intensidad, notas,
                     registrado_por, origen, roll_grupo_id)
  values (v_sesion, s.practicante_id, r.orden, r.modalidad, r.duracion_min,
          r.posicion_inicio, v_rol_inicio, v_resultado, r.intensidad, r.notas,
          r.registrado_por, r.origen, r.roll_grupo_id)
  returning id into v_nuevo;

  -- el espejo: solo cambia `actor`. posicion y rol describen al actor,
  -- que es la misma persona fisica en ambas filas.
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       tecnica_id, completado, minuto, notas)
  select v_nuevo,
         case actor when 'yo' then 'oponente'::bjj_actor else 'yo'::bjj_actor end,
         tipo, posicion, rol, objetivo, tecnica_id, completado, minuto, notas
    from eventos
   where roll_id = p_roll_id;

  return v_nuevo;
end;
$$;


-- ------------------------------------------------------------
-- 4. Deduplicacion
--    Si el coach registro el roll Y ademas Felipe lo registro solo,
--    hay dos filas del mismo roll fisico en la misma sesion-persona.
--    Regla: gana el observador (ve lo que tu no ves: tu propia espalda).
-- ------------------------------------------------------------
create or replace view v_rolls_unicos with (security_invoker = on) as
select distinct on (s.practicante_id, r.roll_grupo_id) r.*, s.practicante_id
  from rolls r
  join sesiones s on s.id = r.sesion_id
 order by s.practicante_id, r.roll_grupo_id,
          (r.origen = 'observador') desc,   -- el observador tiene prioridad
          r.created_at;

comment on view v_rolls_unicos is
  'Una fila por practicante y roll fisico. Prefiere el registro del observador.';


-- ------------------------------------------------------------
-- 5. v_eventos pasa a apoyarse en la vista deduplicada
--    (mismas columnas que en 03-analytics.sql: todo lo de arriba sigue igual)
-- ------------------------------------------------------------
create or replace view v_eventos with (security_invoker = on) as
select
  e.id                as evento_id,
  r.practicante_id    as autor_id,
  r.oponente_id       as oponente_id,
  s.fecha,
  s.modalidad         as modalidad_sesion,
  r.id                as roll_id,
  r.resultado         as resultado_roll,
  r.autovaloracion,
  e.actor,
  case when e.actor = 'yo' then r.practicante_id else r.oponente_id end as ejecutor_id,
  e.tipo,
  e.posicion,
  p.nombre            as posicion_nombre,
  p.grupo             as posicion_grupo,
  p.es_guardia,
  e.rol,
  e.objetivo,
  e.completado,
  t.slug              as tecnica_slug,
  t.nombre            as tecnica_nombre
from eventos e
join v_rolls_unicos r on r.id = e.roll_id
join sesiones       s on s.id = r.sesion_id
join posiciones     p on p.codigo = e.posicion
left join tecnicas  t on t.id = e.tecnica_id;


-- ------------------------------------------------------------
-- 6. Calidad del dato: cuanto de lo que tienes lo vio alguien de fuera
-- ------------------------------------------------------------
create or replace view v_cobertura_observador with (security_invoker = on) as
select practicante_id                                            as autor_id,
       count(*)                                                  as rolls,
       count(*) filter (where origen = 'observador')             as observados,
       round(100.0 * count(*) filter (where origen = 'observador')
             / nullif(count(*), 0), 1)                           as pct_observado
  from v_rolls_unicos
 group by practicante_id;
