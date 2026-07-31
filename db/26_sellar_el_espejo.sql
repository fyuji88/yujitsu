-- ============================================================
--  BJJ TRACKER — Sellar los eventos espejo   ·   Migracion bjj_31
-- ============================================================
--
--  EL PROBLEMA, y el diagnostico bueno no era mio. Los dos rolls de un combate
--  observado comparten `par_id`, pero sus EVENTOS no comparten nada. Asi que si
--  A precisa su kimura a tarikoplata, la copia de B sigue diciendo kimura: el
--  mismo hecho fisico acaba con dos tecnicas distintas segun a quien mires, y
--  se degrada con cada precision.
--
--  Yo lo habia cerrado como "descartado" porque emparejar por `created_at` es
--  fragil —en los datos sembrados todos los eventos de un roll comparten
--  sello—. Pero eso era la solucion mala, no el problema: lo que falta es el
--  ENLACE. Se añade.
--
--  ---------------------------------------------------------------------------
--  EL RELLENO HACIA ATRAS, Y POR QUE ES SEGURO
--  ---------------------------------------------------------------------------
--  `espejar_roll()` inserta los eventos del espejo LEYENDO los del original
--  `order by created_at, segundo_roll nulls first, id`. O sea que el n-esimo
--  evento de A es el n-esimo de B. Se empareja POR POSICION, no por sello.
--
--  Comprobado antes de escribir nada, sobre produccion: 99 pares con dos rolls,
--  los 99 con el mismo numero de eventos, ninguno descuadrado. (Y 58 rolls con
--  `par_id` sin pareja: son los del compañero sin cuenta, que no se espeja.
--  Esos no necesitan sello, y tenerlo no molesta.)
--
--  EL ORDEN NO PUEDE USAR `id`: el espejo tiene ids nuevos, asi que ordenar
--  cada lado por el suyo daria ordenes distintos. Se ordena por lo que el
--  espejo COPIA tal cual —created_at, segundo_roll, tipo, posicion, rol,
--  objetivo, tecnica_id, completado— y nunca por `actor`, que es lo unico que
--  se invierte.
--
--  Si aun asi quedan dos eventos empatados en todo eso, son indistinguibles en
--  todo lo que a `precisar` le importa: emparejarlos al reves da el mismo
--  resultado. La ambiguedad que queda es inofensiva por construccion.
--
--  El sello se deriva de (par_id, posicion) con md5, asi que es DETERMINISTA:
--  volver a correr el relleno da los mismos valores y no duplica nada.
-- ============================================================

begin;

alter table eventos add column par_evento_id uuid;

comment on column eventos.par_evento_id is
  'El identificador que comparten los dos eventos espejo del mismo hecho '
  'fisico, uno en el roll de cada practicante. Es a los eventos lo que par_id '
  'es a los rolls, y es lo que permite que precisar una tecnica se propague al '
  'compañero en vez de dejar el mismo hecho con dos nombres distintos.';

create index eventos_par_evento_idx on eventos (par_evento_id)
  where par_evento_id is not null;

-- ---------------------------------------------------------------- el relleno
update eventos e
   set par_evento_id = md5(o.par_id::text || ':' || o.n)::uuid
  from (
    select e2.id, r.par_id,
           row_number() over (
             partition by e2.roll_id
             order by e2.created_at, e2.segundo_roll nulls first,
                      e2.tipo, e2.posicion, e2.rol, e2.objetivo,
                      e2.tecnica_id nulls first, e2.completado) as n
      from eventos e2
      join rolls r on r.id = e2.roll_id
     where r.par_id is not null
  ) o
 where o.id = e.id;

-- Que el relleno haya hecho lo que dice: en cada par con dos rolls, cada sello
-- tiene que aparecer EXACTAMENTE dos veces. Si no, algo se emparejo mal y es
-- mejor enterarse aqui que dentro de tres meses con dos numeros que no cuadran.
do $$
declare v_mal int; v_pares int;
begin
  select count(*) into v_pares from (
    select par_id from rolls where par_id is not null
     group by par_id having count(distinct id) = 2) z;

  select count(*) into v_mal from (
    select e.par_evento_id
      from eventos e
      join rolls r on r.id = e.roll_id
     where r.par_id in (select par_id from rolls
                         where par_id is not null
                         group by par_id having count(distinct id) = 2)
     group by e.par_evento_id
    having count(*) <> 2
  ) z;
  if v_mal > 0 then
    raise exception 'El relleno dejo % sellos que no aparecen exactamente dos veces', v_mal;
  end if;
  -- Y DICE CUANTOS. Sin el numero, esta comprobacion pasa en vacio: la primera
  -- vez que se corrio, en una base sin ningun par espejo, dijo que todo estaba
  -- bien sin haber mirado nada. Una comprobacion que no puede fallar no es una
  -- comprobacion.
  if v_pares = 0 then
    raise notice 'AVISO  no hay ningun par espejo en esta base: el relleno NO se ha comprobado';
  else
    raise notice 'Relleno comprobado sobre % pares espejo: cada sello aparece exactamente dos veces', v_pares;
  end if;
end $$;

commit;

-- ============================================================
--  Y las tres funciones que tienen que saber del sello
-- ============================================================

begin;

-- `espejar_roll`: copia el sello del original en vez de dejarlo nulo. Es el
-- unico cambio; todo lo demas es igual que en bjj_29.
create or replace function public.espejar_roll(p_roll_id uuid)
returns uuid language plpgsql
set search_path = public as $$
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
             where r2.par_id = r.par_id
               and s2.practicante_id = r.oponente_id) then
    return null;
  end if;

  v_resultado := case r.resultado
                   when 'sumision_favor'  then 'sumision_contra'
                   when 'sumision_contra' then 'sumision_favor'
                   else r.resultado
                 end;

  -- `rol_inicio` SI se invierte: describe al dueño del roll, que cambia. Si A
  -- empieza en guardia cerrada abajo, B empieza en guardia cerrada arriba.
  -- `posicion_inicio` NO: es fisica y es la misma para los dos.
  v_rol_inicio := case r.rol_inicio
                    when 'arriba' then 'abajo'
                    when 'abajo'  then 'arriba'
                    else 'neutral'
                  end;

  v_sesion := sesion_del_dia(r.oponente_id, s.fecha, r.modalidad, s.academia);

  insert into rolls (sesion_id, oponente_id, orden_en_sesion, modalidad, duracion_min,
                     posicion_inicio, rol_inicio, resultado, intensidad, notas,
                     registrado_por, origen, par_id)
  values (v_sesion, s.practicante_id, r.orden_en_sesion, r.modalidad, r.duracion_min,
          r.posicion_inicio, v_rol_inicio, v_resultado, r.intensidad, r.notas,
          r.registrado_por, r.origen, r.par_id)
  returning id into v_nuevo;

  -- El espejo: solo cambia `actor`. posicion y rol describen al actor, que es
  -- la misma persona fisica en ambas filas. Y `par_evento_id` se COPIA: es lo
  -- que hace que los dos eventos sepan que son el mismo hecho.
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       tecnica_id, completado, minuto, segundo_roll, notas,
                       created_at, par_evento_id)
  select v_nuevo,
         case actor when 'yo' then 'oponente'::bjj_actor else 'yo'::bjj_actor end,
         tipo, posicion, rol, objetivo, tecnica_id, completado, minuto,
         segundo_roll, notas,
         created_at,             -- conserva el orden; ver el comentario de arriba
         par_evento_id
    from eventos
   where roll_id = p_roll_id
   order by created_at, segundo_roll nulls first, id;

  return v_nuevo;
end;
$$;

-- `precisar_tecnica`: propaga al espejo. Es el punto entero de esta migracion.
create or replace function public.precisar_tecnica(p_evento_id uuid, p_tecnica_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_yo        uuid;
  v_actual    uuid;
  v_duenyo    uuid;
  v_registro  uuid;
  v_par       uuid;
  v_mec_vieja uuid;
  v_mec_nueva uuid;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien precisa no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  select e.tecnica_id, e.par_evento_id, s.practicante_id, r.registrado_por
    into v_actual, v_par, v_duenyo, v_registro
    from eventos e
    join rolls r    on r.id = e.roll_id
    join sesiones s on s.id = r.sesion_id
   where e.id = p_evento_id;
  if not found then
    raise exception 'ese evento no existe' using errcode = 'no_data_found';
  end if;

  if v_yo <> v_duenyo and v_yo is distinct from v_registro then
    raise exception 'solo el practicante del roll o quien lo registro pueden precisar'
      using errcode = 'insufficient_privilege';
  end if;

  if v_actual is null then
    raise exception 'ese evento no tiene tecnica, asi que no hay nada que precisar'
      using errcode = 'check_violation';
  end if;

  select mecanica_id into v_mec_vieja from tecnicas where id = v_actual;
  select mecanica_id into v_mec_nueva from tecnicas where id = p_tecnica_id;
  if v_mec_nueva is null then
    raise exception 'esa tecnica no existe' using errcode = 'no_data_found';
  end if;
  if v_mec_nueva is distinct from v_mec_vieja then
    raise exception 'precisar solo baja dentro de la misma mecanica; cambiar de mecanica es corregir'
      using errcode = 'check_violation';
  end if;

  -- LOS DOS A LA VEZ. Es un solo hecho fisico: dejar el del compañero diciendo
  -- "kimura" mientras el tuyo dice "tarikoplata" es peor que no precisar, y
  -- ademas empeora cada vez que alguien precisa algo.
  --
  -- Escribir en el evento de otro es deliberado y es el mismo modelo de
  -- confianza que ya tiene `registrar_roll_observado()`, que directamente le
  -- CREA las filas. Por eso es SECURITY DEFINER.
  update eventos
     set tecnica_id            = p_tecnica_id,
         tecnica_precisada_por = v_yo,
         tecnica_precisada_en  = now()
   where id = p_evento_id
      or (v_par is not null and par_evento_id = v_par);
end;
$$;

comment on function public.precisar_tecnica(uuid, uuid) is
  'Baja la tecnica de un evento de la mecanica madre a una de sus variantes, Y '
  'la de su espejo: es un solo hecho fisico. Solo el practicante del roll o '
  'quien lo registro, y solo dentro de la misma mecanica. Es SECURITY DEFINER '
  'porque no hay RLS por columna: una politica de update sobre eventos dejaria '
  'reescribir tambien el marcador.';

commit;

-- ---------- registrar_roll_observado: sella cada evento al crearlo
begin;

create or replace function public.registrar_roll_observado(
  p_par uuid, p_practicante_a uuid, p_practicante_b uuid, p_fecha date,
  p_modalidad bjj_modalidad, p_duracion_min smallint, p_posicion_inicio bjj_posicion,
  p_rol_inicio bjj_rol, p_resultado bjj_resultado_roll, p_eventos jsonb)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_observador uuid;
  v_sesion_a   uuid;
  v_roll_a     uuid;
  v_roll_b     uuid;
  v_academia   text;
  v_orden      smallint;
begin
  -- Quien pulsa los botones. Sin ficha no se registra nada: `registrado_por`
  -- es lo unico que permite auditar quien metio un roll ajeno.
  v_observador := private.practicante_actual();
  if v_observador is null then
    raise exception 'quien registra no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  if p_practicante_a is null or p_practicante_b is null then
    raise exception 'hacen falta los dos practicantes';
  end if;
  if p_practicante_a = p_practicante_b then
    raise exception 'un roll necesita dos personas distintas';
  end if;

  -- Serializa los reintentos del mismo roll.
  perform pg_advisory_xact_lock(hashtextextended(p_par::text, 0));

  -- ---------------------------------------------------------
  -- IDEMPOTENCIA — esto no es opcional
  -- La cola reintenta los envios que no sabe si llegaron. Sin esta
  -- comprobacion, volver del gimnasio sin cobertura duplica el roll.
  -- ---------------------------------------------------------
  select r.id into v_roll_a
    from rolls r
    join sesiones s on s.id = r.sesion_id
   where r.par_id = p_par
     and s.practicante_id = p_practicante_a
   limit 1;

  if v_roll_a is not null then
    select r.id into v_roll_b
      from rolls r
      join sesiones s on s.id = r.sesion_id
     where r.par_id = p_par
       and s.practicante_id = p_practicante_b
     limit 1;
    return jsonb_build_object('roll_a', v_roll_a, 'roll_b', v_roll_b, 'creado', false);
  end if;

  select academia into v_academia from practicantes where id = p_practicante_a;
  if not found then
    raise exception 'el practicante % no existe', p_practicante_a;
  end if;
  if not exists (select 1 from practicantes where id = p_practicante_b) then
    raise exception 'el practicante % no existe', p_practicante_b;
  end if;

  v_sesion_a := sesion_del_dia(p_practicante_a, p_fecha, p_modalidad, v_academia);

  select coalesce(max(orden_en_sesion), 0) + 1 into v_orden
    from rolls where sesion_id = v_sesion_a;

  insert into rolls (sesion_id, oponente_id, orden_en_sesion, modalidad, duracion_min,
                     posicion_inicio, rol_inicio, resultado,
                     registrado_por, origen, par_id)
  values (v_sesion_a, p_practicante_b, v_orden, p_modalidad, p_duracion_min,
          coalesce(p_posicion_inicio, 'de_pie'), coalesce(p_rol_inicio, 'neutral'),
          coalesce(p_resultado, 'no_registrado'),
          v_observador, 'observador', p_par)
  returning id into v_roll_a;

  -- `par_evento_id` se genera AQUI, uno por evento, y `espejar_roll()` lo
  -- copia. Es lo que hace que los dos eventos del mismo hecho fisico se
  -- reconozcan, y por tanto lo que permite que precisar se propague.
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       tecnica_id, completado, segundo_roll, minuto, created_at,
                       par_evento_id)
  select v_roll_a,
         (x.e->>'actor')::bjj_actor,
         (x.e->>'tipo')::bjj_tipo_evento,
         (x.e->>'posicion')::bjj_posicion,
         (x.e->>'rol')::bjj_rol,
         coalesce(nullif(x.e->>'objetivo', ''), 'ninguno')::bjj_objetivo,
         t.id,
         coalesce((x.e->>'completado')::boolean, true),
         x.seg,
         -- `minuto` se deriva de los segundos y se queda por compatibilidad.
         case when x.seg is not null then least(60, x.seg / 60)::smallint
              else x.min end,
         -- clock_timestamp() avanza dentro de la sentencia (now() no):
         -- conserva el orden en que ocurrieron los eventos.
         clock_timestamp(),
         gen_random_uuid()
    from (
      select e, ord,
             -- Ojo con greatest/least: ignoran los NULL, asi que
             -- greatest(null, 0) devuelve 0. Sin este case, un evento sin
             -- sello acabaria diciendo que paso en el segundo 0.
             case when e->>'segundo_roll' is null then null
                  else least(greatest((e->>'segundo_roll')::int, 0), 3600)::smallint
             end as seg,
             case when e->>'minuto' is null then null
                  else least(greatest((e->>'minuto')::int, 0), 60)::smallint
             end as min
        from jsonb_array_elements(coalesce(p_eventos, '[]'::jsonb))
             with ordinality as a(e, ord)
    ) x
    -- La tecnica llega por slug. Si no esta en el diccionario, el evento entra
    -- igual con tecnica_id null y sigue alimentando el heatmap.
    left join tecnicas t on t.slug = nullif(x.e->>'tecnica_slug', '')
   order by x.ord;

  v_roll_b := espejar_roll(v_roll_a);

  return jsonb_build_object('roll_a', v_roll_a, 'roll_b', v_roll_b, 'creado', true);
end;
$$;

commit;
