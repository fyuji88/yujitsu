-- ============================================================
--  BJJ TRACKER — `transicion` y el marcador estilo IBJJF
--  Migraciones bjj_10 y bjj_11. Van despues de 01..06.
-- ============================================================
--
--  ESTE FICHERO SON DOS MIGRACIONES, NO UNA
--
--  `alter type ... add value` deja añadir el valor dentro de una transaccion,
--  pero NO deja usarlo en esa misma transaccion. Todo lo que menciona
--  'transicion' —la vista de puntos, el filtro de los heatmaps— tiene que ir
--  despues del commit, o Postgres contesta:
--    unsafe use of new value "transicion" of enum type bjj_tipo_evento
--
--  Con psql da igual, porque cada sentencia va en su propia transaccion. Pero
--  el aplicador de migraciones de Supabase envuelve el fichero entero, asi que
--  alli hay que mandarlo en dos: bjj_10 (la PARTE 1) y bjj_11 (la PARTE 2).
--
--
--  POR QUE `transicion` Y NO DOS TIPOS NUEVOS
--
--  De las seis acciones que puntuan en IBJJF, el vocabulario cubria cuatro:
--  derribo, barrida, pase_guardia y toma_espalda. Faltaban montada (4) y
--  rodilla en barriga (2), a las que se llega cambiando de posicion — y la app
--  cambiaba la posicion sin escribir nada. Sin esto el marcador se dejaria 6 de
--  los puntos posibles y seria falso en la mayoria de los rolls.
--
--  `transicion` en vez de `monta` y `rodilla_barriga` porque el bloque
--  siguiente es el tiempo de dominio tipo posesion, y eso necesita TODOS los
--  cambios de posicion, tambien los que no puntuan: norte-sur, kesa gatame,
--  tortuga, scramble. Dos tipos nuevos cerrarian el marcador y dejarian la
--  posesion igual de bloqueada.
--
--
--  LA REGLA DE LECTURA DE `transicion` — LA UNICA EXCEPCION DEL ESQUEMA
--
--  En todos los demas tipos, `posicion` es DESDE DONDE se hizo la accion. En
--  una transicion es EL DESTINO: donde acaba el actor. Existe porque lo que
--  interesa de una transicion es donde te deja.
--
--  Consecuencia inmediata: cualquier vista que agrupe por posicion y objetivo
--  tiene que excluir las transiciones, o se llena de filas con
--  objetivo = 'ninguno' que no significan nada.
-- ============================================================


-- ============================================================
--  PARTE 1  ·  bjj_10_transicion_y_segundos
--  Solo vocabulario y columna. Nada de aqui usa el valor nuevo.
-- ============================================================

alter type bjj_tipo_evento add value if not exists 'transicion';

alter table eventos
  add column if not exists segundo_roll smallint
  check (segundo_roll between 0 and 3600);

comment on column eventos.segundo_roll is
  'Segundo del roll en que ocurrio, del cronometro del observador. Se sella en '
  'segundos y no en minutos porque el cronometro ya esta corriendo y la '
  'precision sale gratis: el analisis de posesion la necesita, y un dato que no '
  'capturas no lo recuperas despues. `minuto` se deriva de aqui.';


-- ============================================================
--  PARTE 2  ·  bjj_11_marcador_ibjjf
--  A partir de aqui ya se puede nombrar 'transicion'.
-- ============================================================


-- ------------------------------------------------------------
-- 1. El espejo tiene que conservar el ORDEN de los eventos
--
--    Esto no es cosmetico. El marcador depende del orden: una posicion solo
--    vuelve a puntuar si el rival ha salido antes. Hasta ahora el espejo
--    copiaba los eventos sin `created_at`, asi que las filas de B nacian todas
--    con el mismo now() y su orden quedaba indefinido — y el tanteo de B podia
--    no ser el reflejo del de A.
--
--    Se copian `created_at` y `segundo_roll` del original. No es inventar una
--    fecha: son literalmente los mismos eventos fisicos.
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

  -- `rol_inicio` SI se invierte: describe al dueño del roll, que cambia. Si A
  -- empieza en guardia cerrada abajo, B empieza en guardia cerrada arriba.
  -- `posicion_inicio` NO: es fisica y es la misma para los dos.
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

  -- El espejo: solo cambia `actor`. posicion y rol describen al actor, que es
  -- la misma persona fisica en ambas filas.
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       tecnica_id, completado, minuto, segundo_roll, notas,
                       created_at)
  select v_nuevo,
         case actor when 'yo' then 'oponente'::bjj_actor else 'yo'::bjj_actor end,
         tipo, posicion, rol, objetivo, tecnica_id, completado, minuto,
         segundo_roll, notas,
         created_at              -- conserva el orden; ver el comentario de arriba
    from eventos
   where roll_id = p_roll_id
   order by created_at, segundo_roll nulls first, id;

  return v_nuevo;
end;
$$;


-- ------------------------------------------------------------
-- 2. La RPC del observador, ahora con posicion de salida
--
--    Añadir parametros NO es un `create or replace`: seria una sobrecarga
--    nueva, y con dos firmas PostgREST no sabe cual llamar. Hay que tirar la
--    vieja. Y los permisos no se heredan: el revoke y el grant se vuelven a
--    aplicar sobre la firma nueva.
-- ------------------------------------------------------------
drop function if exists registrar_roll_observado(
  uuid, uuid, uuid, date, bjj_modalidad, smallint, bjj_resultado_roll, jsonb);

create or replace function registrar_roll_observado(
  p_grupo           uuid,
  p_practicante_a   uuid,
  p_practicante_b   uuid,
  p_fecha           date,
  p_modalidad       bjj_modalidad,
  p_duracion_min    smallint,
  p_posicion_inicio bjj_posicion,        -- fisica: la misma para los dos
  p_rol_inicio      bjj_rol,             -- describe a A; al espejar se invierte
  p_resultado       bjj_resultado_roll,  -- desde el punto de vista de A
  p_eventos         jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
  perform pg_advisory_xact_lock(hashtextextended(p_grupo::text, 0));

  -- ---------------------------------------------------------
  -- IDEMPOTENCIA — esto no es opcional
  -- La cola reintenta los envios que no sabe si llegaron. Sin esta
  -- comprobacion, volver del gimnasio sin cobertura duplica el roll.
  -- ---------------------------------------------------------
  select r.id into v_roll_a
    from rolls r
    join sesiones s on s.id = r.sesion_id
   where r.roll_grupo_id = p_grupo
     and s.practicante_id = p_practicante_a
   limit 1;

  if v_roll_a is not null then
    select r.id into v_roll_b
      from rolls r
      join sesiones s on s.id = r.sesion_id
     where r.roll_grupo_id = p_grupo
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

  select coalesce(max(orden), 0) + 1 into v_orden
    from rolls where sesion_id = v_sesion_a;

  insert into rolls (sesion_id, oponente_id, orden, modalidad, duracion_min,
                     posicion_inicio, rol_inicio, resultado,
                     registrado_por, origen, roll_grupo_id)
  values (v_sesion_a, p_practicante_b, v_orden, p_modalidad, p_duracion_min,
          coalesce(p_posicion_inicio, 'de_pie'), coalesce(p_rol_inicio, 'neutral'),
          coalesce(p_resultado, 'no_registrado'),
          v_observador, 'observador', p_grupo)
  returning id into v_roll_a;

  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       tecnica_id, completado, segundo_roll, minuto, created_at)
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
         clock_timestamp()
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

comment on function registrar_roll_observado(uuid, uuid, uuid, date, bjj_modalidad,
                                             smallint, bjj_posicion, bjj_rol,
                                             bjj_resultado_roll, jsonb) is
  'Modo observador: escribe el roll de otros dos. SECURITY DEFINER a proposito — '
  'ver el modelo de confianza al principio de db/06_rpc_roll_observado.sql.';

revoke all on function registrar_roll_observado(uuid, uuid, uuid, date, bjj_modalidad,
                                                smallint, bjj_posicion, bjj_rol,
                                                bjj_resultado_roll, jsonb)
  from public, anon;
grant execute on function registrar_roll_observado(uuid, uuid, uuid, date, bjj_modalidad,
                                                   smallint, bjj_posicion, bjj_rol,
                                                   bjj_resultado_roll, jsonb)
  to authenticated;


-- ------------------------------------------------------------
-- 3. Las reglas de puntuacion, declarativas
--
--    Este es el gemelo de la tabla REGLAS de src/lib/puntos.ts. El calculo
--    existe dos veces —aqui para el historico, alli para el marcador en vivo—
--    y los dos leen los mismos casos de prueba, src/lib/__fixtures__/puntos.json.
--    Si cambias una regla en un sitio y no en el otro, el fixture lo caza.
--
--    Todo lo que no esta aqui vale cero: cien_kilos (control lateral) ya lo
--    cubren los 3 del pase, y tampoco puntuan norte_sur, kesa_gatame, tortuga,
--    scramble, escape ni sumision.
--
--    Los 3 segundos de estabilizacion del reglamento NO se implementan a
--    proposito: el observador pulsa cuando la posicion ya esta hecha, y el dedo
--    humano es la estabilizacion.
-- ------------------------------------------------------------
create or replace function regla_punto(p_tipo bjj_tipo_evento, p_posicion bjj_posicion)
returns table (clave text, puntos smallint, etiqueta text)
language sql
immutable
set search_path = public
as $$
  select r.clave, r.puntos, r.etiqueta
    from (values
      ('derribo',            2::smallint, 'derribo', 'derribo'::bjj_tipo_evento, null::bjj_posicion),
      ('barrida',            2,           'barrida', 'barrida',                  null),
      ('pase',               3,           'paso',    'pase_guardia',             null),
      ('espalda',            4,           'espalda', 'toma_espalda',             null),
      ('montada',            4,           'montada', 'transicion',               'montada'),
      ('rodilla_en_barriga', 2,           'rodilla', 'transicion',               'rodilla_en_barriga')
    ) as r(clave, puntos, etiqueta, tipo, posicion)
   where r.tipo = p_tipo
     and (r.posicion is null or r.posicion = p_posicion)
   limit 1
$$;


-- ------------------------------------------------------------
-- 4. El tanteo de un roll
--
--    Lo que hace que esto no sea un `sum()`: una posicion puntua UNA VEZ POR
--    SECUENCIA. El reglamento no premia acumular la misma posicion. Montar,
--    bajar a cien kilos y volver a montar sin que el rival haga nada son 4
--    puntos, no 8. La secuencia se cierra —y el conjunto se vacia— cuando el
--    rival hace algo que significa que ha salido: escape, barrida, o una
--    transicion que le deja en guardia.
--
--    Los puntos NO se guardan en ninguna columna: son una funcion de los
--    eventos, igual que el heatmap. Si mañana se corrige un evento mal
--    registrado, el marcador se corrige solo.
-- ------------------------------------------------------------
create or replace function puntos_roll(p_roll_id uuid)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  ev         record;
  v_a        smallint := 0;
  v_b        smallint := 0;
  v_set_yo   text[] := '{}';
  v_set_op   text[] := '{}';
  v_desglose jsonb  := '[]'::jsonb;
  v_clave    text;
  v_puntos   smallint;
  v_etiqueta text;
  v_i        int := 0;
begin
  for ev in
    select e.actor, e.tipo, e.posicion, coalesce(p.es_guardia, false) as es_guardia
      from eventos e
      join posiciones p on p.codigo = e.posicion
     where e.roll_id = p_roll_id
     -- El orden importa para la regla de arriba. `created_at` lo pone
     -- clock_timestamp() en la RPC del observador, asi que es fiable.
     order by e.created_at, e.segundo_roll nulls first, e.id
  loop
    select clave, puntos, etiqueta into v_clave, v_puntos, v_etiqueta
      from regla_punto(ev.tipo, ev.posicion);

    if v_clave is not null then
      if ev.actor = 'yo' and not (v_clave = any(v_set_yo)) then
        v_set_yo := v_set_yo || v_clave;
        v_a := v_a + v_puntos;
        v_desglose := v_desglose || jsonb_build_object(
          'indice', v_i, 'actor', 'yo', 'clave', v_clave,
          'puntos', v_puntos, 'etiqueta', v_etiqueta);
      elsif ev.actor = 'oponente' and not (v_clave = any(v_set_op)) then
        v_set_op := v_set_op || v_clave;
        v_b := v_b + v_puntos;
        v_desglose := v_desglose || jsonb_build_object(
          'indice', v_i, 'actor', 'oponente', 'clave', v_clave,
          'puntos', v_puntos, 'etiqueta', v_etiqueta);
      end if;
    end if;

    -- Primero se puntua y despues se cierra: una barrida puntua para quien la
    -- hace Y le reabre la secuencia al rival.
    if ev.tipo in ('escape', 'barrida')
       or (ev.tipo = 'transicion' and ev.es_guardia) then
      if ev.actor = 'yo' then v_set_op := '{}'; else v_set_yo := '{}'; end if;
    end if;

    v_i := v_i + 1;
  end loop;

  return jsonb_build_object('a', v_a, 'b', v_b, 'desglose', v_desglose);
end;
$$;


create or replace view v_puntos_roll with (security_invoker = on) as
select r.id                        as roll_id,
       r.practicante_id            as autor_id,
       r.oponente_id,
       s.fecha,
       r.roll_grupo_id,
       r.origen,
       (p.j->>'a')::smallint       as puntos_autor,
       (p.j->>'b')::smallint       as puntos_oponente,
       p.j->'desglose'             as desglose
  from v_rolls_unicos r
  join sesiones s on s.id = r.sesion_id
  cross join lateral puntos_roll(r.id) as p(j);

comment on view v_puntos_roll is
  'Marcador estilo IBJJF de cada roll, derivado de los eventos. No hay columna '
  '`puntos` en ninguna tabla a proposito: si se corrige un evento, esto se '
  'corrige solo. El gemelo en vivo es src/lib/puntos.ts.';


-- ------------------------------------------------------------
-- 5. Las transiciones fuera de las vistas que no las quieren
--
--    Los dos heatmaps ya estaban a salvo: filtran `tipo = 'sumision'`, que es
--    mas estrecho que excluir las transiciones. Comprobado, no supuesto — se
--    deja escrito para que nadie añada un filtro redundante creyendo que falta.
--
--    v_fuertes_debiles SI estaba expuesta: no filtra por tipo, asi que al
--    aparecer las transiciones empezaria a contarlas como acciones a favor o en
--    contra, e inflaria a quien mas se mueve. Mide saldo de ataque y defensa, y
--    una transicion no es ninguna de las dos.
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
where tipo <> 'transicion'
group by autor_id, posicion, posicion_nombre, posicion_grupo;
