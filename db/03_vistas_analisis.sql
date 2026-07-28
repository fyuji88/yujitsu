-- ============================================================
--  BJJ TRACKER — Vistas de analisis
--  Todo sale de la tabla `eventos`. Ejecutar despues de 01 y 02.
-- ============================================================

-- ------------------------------------------------------------
-- VISTA BASE: eventos enriquecidos
-- Resuelve actor -> persona real, y trae posicion/tecnica legibles.
-- Todas las demas vistas se apoyan en esta.
-- ------------------------------------------------------------
create or replace view v_eventos with (security_invoker = on) as
select
  e.id                as evento_id,
  s.practicante_id    as autor_id,          -- quien loguea
  r.oponente_id       as oponente_id,
  s.fecha,
  s.modalidad         as modalidad_sesion,
  r.id                as roll_id,
  r.resultado         as resultado_roll,
  r.autovaloracion,
  e.actor,
  -- persona que ejecuto el evento
  case when e.actor = 'yo' then s.practicante_id else r.oponente_id end as ejecutor_id,
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
join rolls      r on r.id = e.roll_id
join sesiones   s on s.id = r.sesion_id
join posiciones p on p.codigo = e.posicion
left join tecnicas t on t.id = e.tecnica_id;


-- ------------------------------------------------------------
-- HEATMAP OFENSIVO — desde donde ataco y a que articulacion
--   filas    = posicion
--   columnas = objetivo
-- ------------------------------------------------------------
create or replace view v_heatmap_ofensivo with (security_invoker = on) as
select
  autor_id,
  posicion,
  posicion_nombre,
  rol,
  objetivo,
  count(*) filter (where completado)       as finalizadas,
  count(*) filter (where not completado)   as intentos_fallados,
  count(*)                                 as total,
  round(
    100.0 * count(*) filter (where completado) / nullif(count(*),0)
  , 1)                                     as tasa_exito_pct
from v_eventos
where actor = 'yo' and tipo = 'sumision'
group by autor_id, posicion, posicion_nombre, rol, objetivo;


-- ------------------------------------------------------------
-- HEATMAP DEFENSIVO — donde me pillan a mi
-- (mismo corte, pero eventos del oponente)
-- ------------------------------------------------------------
create or replace view v_heatmap_defensivo with (security_invoker = on) as
select
  autor_id,
  posicion,
  posicion_nombre,
  rol,
  objetivo,
  count(*) filter (where completado)     as recibidas,
  count(*) filter (where not completado) as escapadas,
  count(*)                               as total
from v_eventos
where actor = 'oponente' and tipo = 'sumision'
group by autor_id, posicion, posicion_nombre, rol, objetivo;


-- ------------------------------------------------------------
-- RENDIMIENTO POR GUARDIA — que guardia me funciona
-- Positivo: barridas y tomas de espalda desde abajo.
-- Negativo: que me pasen esa guardia.
-- ------------------------------------------------------------
create or replace view v_guardias with (security_invoker = on) as
select
  autor_id,
  posicion,
  posicion_nombre,
  count(*) filter (
    where actor = 'yo' and rol = 'abajo'
      and tipo in ('barrida','toma_espalda','sumision') and completado
  ) as acciones_favor,
  count(*) filter (
    where actor = 'oponente' and rol = 'arriba'
      and tipo in ('pase_guardia','sumision') and completado
  ) as acciones_contra,
  count(*) filter (
    where actor = 'yo' and rol = 'abajo'
      and tipo in ('barrida','toma_espalda','sumision') and completado
  )
  - count(*) filter (
    where actor = 'oponente' and rol = 'arriba'
      and tipo in ('pase_guardia','sumision') and completado
  ) as saldo
from v_eventos
where es_guardia
group by autor_id, posicion, posicion_nombre;


-- ------------------------------------------------------------
-- FUERTES / DEBILES — saldo ataque vs defensa por posicion
-- ------------------------------------------------------------
create or replace view v_fuertes_debiles with (security_invoker = on) as
select
  autor_id,
  posicion,
  posicion_nombre,
  posicion_grupo,
  count(*) filter (where actor = 'yo'       and completado) as a_favor,
  count(*) filter (where actor = 'oponente' and completado) as en_contra,
  round(
    100.0 * count(*) filter (where actor = 'yo' and completado)
          / nullif(count(*) filter (where completado), 0)
  , 1) as dominio_pct
from v_eventos
group by autor_id, posicion, posicion_nombre, posicion_grupo;


-- ------------------------------------------------------------
-- HEAD-TO-HEAD — estadisticas contra cada oponente
-- ------------------------------------------------------------
create or replace view v_h2h with (security_invoker = on) as
select
  s.practicante_id                       as autor_id,
  r.oponente_id,
  pr.nombre                              as oponente_nombre,
  pr.cinturon                            as oponente_cinturon,
  pr.usa_sistema,
  count(distinct r.id)                   as rolls,
  count(*) filter (where e.actor = 'yo'       and e.tipo = 'sumision' and e.completado) as sub_a_favor,
  count(*) filter (where e.actor = 'oponente' and e.tipo = 'sumision' and e.completado) as sub_en_contra,
  count(*) filter (where e.actor = 'yo'       and e.tipo = 'barrida'      and e.completado) as barridas_favor,
  count(*) filter (where e.actor = 'yo'       and e.tipo = 'pase_guardia' and e.completado) as pases_favor,
  max(s.fecha)                           as ultimo_roll
from rolls r
join sesiones s on s.id = r.sesion_id
left join eventos e on e.roll_id = r.id
left join practicantes pr on pr.id = r.oponente_id
group by s.practicante_id, r.oponente_id, pr.nombre, pr.cinturon, pr.usa_sistema;


-- ------------------------------------------------------------
-- EVOLUCION TEMPORAL — series por semana
-- ------------------------------------------------------------
create or replace view v_evolucion_semanal with (security_invoker = on) as
select
  autor_id,
  date_trunc('week', fecha)::date as semana,
  count(distinct roll_id)                                                   as rolls,
  count(*) filter (where actor = 'yo'       and tipo = 'sumision' and completado) as sub_a_favor,
  count(*) filter (where actor = 'oponente' and tipo = 'sumision' and completado) as sub_en_contra,
  count(*) filter (where actor = 'yo'       and tipo = 'barrida'      and completado) as barridas,
  count(*) filter (where actor = 'yo'       and tipo = 'pase_guardia' and completado) as pases
from v_eventos
group by autor_id, date_trunc('week', fecha);


-- ------------------------------------------------------------
-- RETOS — progreso auto-calculado desde la regla jsonb
-- ------------------------------------------------------------
create or replace function progreso_reto(p_reto_id uuid, p_practicante_id uuid)
returns integer
language sql
stable
as $$
  select count(*)::int
  from v_eventos v
  join retos re on re.id = p_reto_id
  where v.autor_id = p_practicante_id
    and v.actor = 'yo'
    and v.completado
    and v.fecha between re.fecha_inicio and re.fecha_fin
    and (re.regla->>'objetivo' is null or v.objetivo::text  = re.regla->>'objetivo')
    and (re.regla->>'posicion' is null or v.posicion::text  = re.regla->>'posicion')
    and (re.regla->>'rol'      is null or v.rol::text       = re.regla->>'rol')
    and (re.regla->>'tipo'     is null or v.tipo::text      = re.regla->>'tipo')
    and (re.regla->>'tecnica'  is null or v.tecnica_slug    = re.regla->>'tecnica');
$$;

-- Ejemplos de reglas de reto:
--   "Solo sumisiones de hombro"     -> {"objetivo":"hombro","tipo":"sumision"}
--   "Juega siempre De la Riva"      -> {"posicion":"de_la_riva","rol":"abajo"}
--   "5 barridas esta semana"        -> {"tipo":"barrida"}            (objetivo_cantidad = 5)
--   "3 mata leao"                   -> {"tecnica":"mata_leao"}       (objetivo_cantidad = 3)
