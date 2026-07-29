-- ============================================================
--  BJJ TRACKER — El informe de la quedada   ·   FASE 4
--  Migracion bjj_18. Va despues de 11 (quedadas) y 12 (feed).
-- ============================================================
--
--  TODO DERIVADO: el informe es una consulta sobre `eventos` filtrando por
--  `sesiones.quedada_id`. Cero tablas nuevas para calcularlo.
--
--  PERO CONGELADO, NO VIVO. Si el informe se recalculara, alguien que corrige
--  un roll el martes cambiaria el informe del domingo que ya se compartio. Se
--  calcula una vez al cerrar la quedada y se guarda el jsonb.
-- ============================================================

create table if not exists quedada_informes (
  quedada_id   uuid primary key references quedadas(id) on delete cascade,
  datos        jsonb not null,
  generado_por uuid references practicantes(id) on delete set null,
  generado_at  timestamptz not null default now()
);

alter table quedada_informes enable row level security;

drop policy if exists informes_lectura on quedada_informes;
create policy informes_lectura on quedada_informes
  for select to authenticated
  using (quedada_id in (select id from quedadas
                         where grupo_id in (select private.mis_grupos())));

comment on table quedada_informes is
  'El informe congelado al cerrar la quedada. Se guarda en vez de recalcularse '
  'para que corregir un roll el martes no cambie el informe del domingo que ya '
  'se compartio.';


-- ------------------------------------------------------------
-- Los titulos
--
--  LA REGLA IMPORTA MAS QUE LA LISTA: cada persona se lleva EXACTAMENTE UN
--  titulo y nadie se queda sin uno.
--
--  Se asignan por mayor desviacion respecto a la media del grupo esa tarde
--  —se normaliza cada metrica y se ordena por |z|—, de forma voraz, sin
--  repetir persona ni titulo. Con umbrales fijos, los tres mismos se lo
--  llevarian todo cada domingo y el resto dejaria de abrir el informe.
--
--  `mayor` dice si destacar es tener mas o menos de esa metrica.
--  `minimo` es el volumen por debajo del cual el titulo no se otorga: un
--  ratio de finalizacion con 2 intentos no significa nada.
-- ------------------------------------------------------------
create or replace function private.titulos_disponibles(p_cachondeo boolean)
returns table (titulo text, metrica text, mayor boolean, minimo int, explica text)
language sql
immutable
set search_path = public
as $$
  select * from (values
    ('IMPASABLE',         'pases_encajados', false, 0, 'menos pases de guardia encajados por roll'),
    ('EL RODILLO',        'pases_hechos',    true,  1, 'mas pases de guardia completados'),
    ('EL FRANCOTIRADOR',  'ratio_sub',       true,  5, 'mejor proporcion de sumisiones que entran'),
    ('EL PULPO',          'intentos_sub',    true,  1, 'mas intentos de sumision, salgan o no'),
    ('HOUDINI',           'escapes',         true,  1, 'mas escapes desde posiciones dominantes'),
    ('EL MOCHILERO',      'espaldas',        true,  1, 'mas espaldas tomadas'),
    ('PRIMERA SANGRE',    'sub_rapida',      false, 1, 'la sumision mas rapida de la tarde'),
    ('EL PROFESOR',       'companeros',      true,  2, 'rodo con mas companeros distintos'),
    ('CINTURON INVISIBLE','cinturon_arriba', true,  1, 'finalizo a alguien de cinturon superior'),
    ('PIERNAS DE ACERO',  'piernas',         true,  1, 'mas ataques a las piernas'),
    ('LA MAQUINA',        'rolls',           true,  2, 'mas rolls registrados'),
    ('DIPLOMATICO',       'sin_sumision',    true,  1, 'mas rolls terminados sin sumision'),
    -- Detras de grupos.modo_cachondeo, apagado por defecto: en un gimnasio
    -- real un titulo negativo automatico le sienta mal a alguien tarde o
    -- temprano, y esa decision la toma un humano.
    ('EL ANCLA',          'eventos_por_roll', false, 2, 'menos cosas pasaron en sus rolls'),
    ('PEAJE',             'pases_encajados',  true,  1, 'mas veces le pasaron la guardia')
  ) as t(titulo, metrica, mayor, minimo, explica)
  where p_cachondeo or t.titulo not in ('EL ANCLA', 'PEAJE')
$$;


-- ------------------------------------------------------------
-- Las metricas de cada asistente en esa quedada
-- ------------------------------------------------------------
create or replace function private.metricas_quedada(p_quedada uuid)
returns table (practicante_id uuid, nombre text, metrica text, valor numeric)
language sql
stable
set search_path = public
as $$
  with rolls_q as (
    select r.id, s.practicante_id, r.oponente_id, r.resultado
      from rolls r
      join sesiones s on s.id = r.sesion_id
     where s.quedada_id = p_quedada
  ),
  ev as (
    select rq.practicante_id, e.*
      from eventos e join rolls_q rq on rq.id = e.roll_id
  ),
  base as (
    select rq.practicante_id, count(*)::numeric as rolls
      from rolls_q rq group by rq.practicante_id
  )
  select b.practicante_id, p.nombre, m.metrica, m.valor
    from base b
    join practicantes p on p.id = b.practicante_id
    cross join lateral (values
      ('rolls', b.rolls),
      ('pases_encajados',
        (select count(*) from ev where ev.practicante_id = b.practicante_id
           and actor = 'oponente' and tipo = 'pase_guardia' and completado)::numeric
        / greatest(b.rolls, 1)),
      ('pases_hechos',
        (select count(*) from ev where ev.practicante_id = b.practicante_id
           and actor = 'yo' and tipo = 'pase_guardia' and completado)::numeric),
      ('intentos_sub',
        (select count(*) from ev where ev.practicante_id = b.practicante_id
           and actor = 'yo' and tipo = 'sumision')::numeric),
      ('ratio_sub',
        coalesce((select count(*) filter (where completado)::numeric
                    / nullif(count(*), 0)
                    from ev where ev.practicante_id = b.practicante_id
                     and actor = 'yo' and tipo = 'sumision'), 0)),
      ('escapes',
        (select count(*) from ev where ev.practicante_id = b.practicante_id
           and actor = 'yo' and tipo = 'escape'
           and posicion in ('montada','espalda','cien_kilos','norte_sur',
                            'kesa_gatame','rodilla_en_barriga'))::numeric),
      ('espaldas',
        (select count(*) from ev where ev.practicante_id = b.practicante_id
           and actor = 'yo' and tipo = 'toma_espalda' and completado)::numeric),
      ('piernas',
        (select count(*) from ev where ev.practicante_id = b.practicante_id
           and actor = 'yo' and tipo = 'sumision' and completado
           and objetivo in ('rodilla','tobillo_pie','pantorrilla'))::numeric),
      -- Menos es mejor, y quien no finalizo no entra: se le da un valor alto.
      ('sub_rapida',
        coalesce((select min(segundo_roll) from ev
                   where ev.practicante_id = b.practicante_id
                     and actor = 'yo' and tipo = 'sumision' and completado
                     and segundo_roll is not null)::numeric, 99999)),
      ('companeros',
        (select count(distinct rq2.oponente_id) from rolls_q rq2
          where rq2.practicante_id = b.practicante_id
            and rq2.oponente_id is not null)::numeric),
      ('sin_sumision',
        (select count(*) from rolls_q rq3
          where rq3.practicante_id = b.practicante_id
            and rq3.resultado = 'sin_sumision')::numeric),
      ('eventos_por_roll',
        (select count(*) from ev where ev.practicante_id = b.practicante_id)::numeric
        / greatest(b.rolls, 1)),
      -- Finalizo a alguien de cinturon mas alto que el suyo.
      ('cinturon_arriba',
        (select count(*) from rolls_q rq4
           join practicantes rival on rival.id = rq4.oponente_id
          where rq4.practicante_id = b.practicante_id
            and rq4.resultado = 'sumision_favor'
            and array_position(array['blanca','azul','morada','marron','negra'],
                               rival.cinturon::text)
              > array_position(array['blanca','azul','morada','marron','negra'],
                               p.cinturon::text))::numeric)
    ) as m(metrica, valor)
$$;


-- ------------------------------------------------------------
-- Cerrar la quedada: calcular, congelar y publicar
-- ------------------------------------------------------------
create or replace function cerrar_quedada(p_quedada uuid, p_regenerar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  q          quedadas%rowtype;
  v_yo       uuid;
  v_datos    jsonb;
  v_rank     jsonb;
  v_titulos  jsonb := '[]'::jsonb;
  v_asignado jsonb;
  fila       record;
  usados_p   uuid[] := '{}';
  usados_t   text[] := '{}';
begin
  select * into q from quedadas where id = p_quedada;
  if not found then
    raise exception 'esa quedada no existe' using errcode = 'no_data_found';
  end if;
  if not private.es_admin(q.grupo_id) then
    raise exception 'solo un admin del grupo puede cerrar la quedada'
      using errcode = 'insufficient_privilege';
  end if;
  v_yo := private.practicante_actual();

  -- Congelado: volver a llamar NO recalcula salvo que se pida a proposito.
  if exists (select 1 from quedada_informes where quedada_id = p_quedada)
     and not p_regenerar then
    select datos into v_datos from quedada_informes where quedada_id = p_quedada;
    return v_datos;
  end if;

  -- RANKING por puntos estimados por roll. Es mas honesto que contar
  -- sumisiones: premia a quien domina aunque no finalice, que es justo lo que
  -- se queria medir. Minimo 2 rolls para entrar.
  select coalesce(jsonb_agg(x order by x.media desc), '[]'::jsonb) into v_rank
    from (
      select p.id, p.nombre, p.cinturon::text as cinturon,
             count(*)                                   as rolls,
             round(avg(v.puntos_autor - v.puntos_oponente), 2) as media,
             sum(v.puntos_autor)                        as favor,
             sum(v.puntos_oponente)                     as contra
        from v_puntos_roll v
        join sesiones s on s.id = (select r2.sesion_id from rolls r2 where r2.id = v.roll_id)
        join practicantes p on p.id = v.autor_id
       where s.quedada_id = p_quedada
       group by p.id, p.nombre, p.cinturon
      having count(*) >= 2
    ) x;

  -- TITULOS. Se ordenan todas las parejas (persona, titulo) por cuanto se
  -- desvia esa persona de la media del grupo en esa metrica, y se van
  -- repartiendo sin repetir ni persona ni titulo.
  for fila in
    with m as (select * from private.metricas_quedada(p_quedada)),
    stats as (
      select metrica, avg(valor) as media, coalesce(stddev_pop(valor), 0) as desv
        from m group by metrica
    ),
    z as (
      select m.practicante_id, m.nombre, t.titulo, t.explica, m.valor,
             case when s.desv = 0 then 0
                  else (m.valor - s.media) / s.desv end
             * case when t.mayor then 1 else -1 end as z
        from m
        join stats s on s.metrica = m.metrica
        join private.titulos_disponibles(q.grupo_id in
              (select id from grupos where modo_cachondeo)) t on t.metrica = m.metrica
        join (select practicante_id, valor as rolls from m where metrica = 'rolls') rr
          on rr.practicante_id = m.practicante_id
       -- El umbral de volumen: un ratio con dos intentos no dice nada.
       where m.valor >= t.minimo or t.mayor = false
    )
    select * from z where z > 0 order by z desc, titulo
  loop
    if fila.practicante_id = any(usados_p) or fila.titulo = any(usados_t) then
      continue;
    end if;
    usados_p := usados_p || fila.practicante_id;
    usados_t := usados_t || fila.titulo;
    v_titulos := v_titulos || jsonb_build_object(
      'titulo', fila.titulo, 'practicante_id', fila.practicante_id,
      'quien', fila.nombre, 'porque', fila.explica,
      'valor', round(fila.valor, 2), 'z', round(fila.z, 2));
  end loop;

  -- NADIE SE QUEDA SIN UNO. Si hay mas gente que titulos repartidos, a los que
  -- quedan se les da el titulo que mejor les pegue de los que sobran.
  for fila in
    select distinct m.practicante_id, m.nombre
      from private.metricas_quedada(p_quedada) m
     where not (m.practicante_id = any(usados_p))
  loop
    select jsonb_build_object('titulo', titulo, 'explica', explica) into v_asignado
      from private.titulos_disponibles(false)
     where not (titulo = any(usados_t))
     limit 1;
    exit when v_asignado is null;
    usados_p := usados_p || fila.practicante_id;
    usados_t := usados_t || (v_asignado->>'titulo');
    v_titulos := v_titulos || jsonb_build_object(
      'titulo', v_asignado->>'titulo', 'practicante_id', fila.practicante_id,
      'quien', fila.nombre, 'porque', v_asignado->>'explica', 'valor', null, 'z', 0);
  end loop;

  v_datos := jsonb_build_object(
    'quedada', jsonb_build_object('titulo', q.titulo, 'fecha', q.fecha,
                                  'lugar', q.lugar, 'modalidad', q.modalidad),
    'asistentes', (select count(distinct s.practicante_id)
                     from sesiones s where s.quedada_id = p_quedada),
    'rolls', (select count(*) from rolls r
                join sesiones s on s.id = r.sesion_id
               where s.quedada_id = p_quedada),
    'ranking', v_rank,
    'titulos', v_titulos,
    'generado', now()
  );

  insert into quedada_informes (quedada_id, datos, generado_por)
  values (p_quedada, v_datos, v_yo)
  on conflict (quedada_id)
  do update set datos = excluded.datos, generado_por = excluded.generado_por,
                generado_at = now();

  update quedadas set estado = 'cerrada' where id = p_quedada;

  return v_datos;
end;
$$;

revoke all on function cerrar_quedada(uuid, boolean) from public, anon;
grant execute on function cerrar_quedada(uuid, boolean) to authenticated;


-- ------------------------------------------------------------
-- Y el informe entra en el feed. Esta rama faltaba en bjj_17 porque la tabla
-- todavia no existia; ahora si.
-- ------------------------------------------------------------
create or replace view v_feed with (security_invoker = on) as

-- Los alias de la PRIMERA rama son los nombres de columna de la vista. Al
-- recrearla hay que repetirlos, o Postgres entiende que se le esta cambiando
-- el nombre a una columna y se niega.
select s.grupo_id,
       'sesion'::text as tipo,
       s.id           as referencia_id,
       s.practicante_id,
       s.created_at   as cuando,
       jsonb_build_object(
         'fecha', s.fecha, 'modalidad', s.modalidad,
         'rolls', (select count(*) from rolls r where r.sesion_id = s.id),
         'quedada', (select q.titulo from quedadas q where q.id = s.quedada_id)) as datos
  from sesiones s
 where s.grupo_id is not null
   and exists (select 1 from rolls r where r.sesion_id = s.id)

union all

select s.grupo_id, 'posicion', primera.evento_id, s.practicante_id, primera.cuando,
       jsonb_build_object('posicion', primera.posicion, 'nombre', pos.nombre)
  from (
    select distinct on (s2.practicante_id, e2.posicion)
           s2.practicante_id, e2.posicion, e2.id as evento_id,
           e2.created_at as cuando, r2.sesion_id
      from eventos e2
      join rolls r2    on r2.id = e2.roll_id
      join sesiones s2 on s2.id = r2.sesion_id
     where e2.actor = 'yo'
     order by s2.practicante_id, e2.posicion, e2.created_at
  ) primera
  join sesiones s     on s.id = primera.sesion_id
  join posiciones pos on pos.codigo = primera.posicion
 where s.grupo_id is not null

union all

select g.id, 'reto', rp.id, rp.practicante_id, rp.created_at,
       jsonb_build_object('reto', re.nombre, 'progreso', rp.progreso)
  from reto_participaciones rp
  join retos re on re.id = rp.reto_id
  join miembros_grupo m on m.practicante_id = rp.practicante_id and m.estado = 'activo'
  join grupos g on g.id = m.grupo_id
 where rp.completado

union all

select q.grupo_id, 'quedada', q.id, q.creado_por, q.created_at,
       jsonb_build_object('titulo', q.titulo, 'fecha', q.fecha,
                          'lugar', q.lugar, 'plazas', q.plazas_max)
  from quedadas q
 where q.estado <> 'cancelada'

union all

select q.grupo_id, 'inscripcion', i.id, i.practicante_id, i.created_at,
       jsonb_build_object('titulo', q.titulo, 'fecha', q.fecha,
                          'externo', i.es_externo)
  from inscripciones i
  join quedadas q on q.id = i.quedada_id
 where i.estado = 'apuntado'

union all

select m.grupo_id, 'miembro', m.grupo_id, m.practicante_id, m.created_at,
       jsonb_build_object('rol', m.rol)
  from miembros_grupo m
 where m.estado = 'activo'

union all

select q.grupo_id, 'informe', inf.quedada_id, inf.generado_por, inf.generado_at,
       jsonb_build_object('titulo', q.titulo, 'fecha', q.fecha,
                          'titulos', jsonb_array_length(inf.datos->'titulos'))
  from quedada_informes inf
  join quedadas q on q.id = inf.quedada_id;
