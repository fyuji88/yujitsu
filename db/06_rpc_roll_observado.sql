-- ============================================================
--  BJJ TRACKER — La puerta de escritura del modo observador
--  Migracion bjj_09. Va despues de 01..05 (bjj_01 .. bjj_08).
-- ============================================================
--
--  POR QUE ESTO NO SE PUEDE HACER SOLO CON FRONTEND
--
--  La RLS dice que cada uno escribe lo suyo:
--    sesiones_propias   practicante_id = private.practicante_actual()
--    rolls_propios      la sesion del roll es tuya
--    eventos_propios    el roll del evento es tuyo
--
--  Un observador escribe datos de OTRAS DOS personas. Autenticado como el
--  coach, cualquier insert directo revienta:
--    42501: new row violates row-level security policy for table "sesiones"
--
--  Asi que hace falta una puerta unica y controlada. Esta funcion es esa
--  puerta: hace la escritura entera en una transaccion y deja constancia de
--  quien la hizo en `registrado_por`.
--
--
--  MODELO DE CONFIANZA — LEER ANTES DE ABRIR ESTO A MAS GENTE
--
--  Al ser SECURITY DEFINER, la funcion se salta la RLS por diseño. Eso
--  significa que **cualquier usuario autenticado puede meter rolls en el
--  historial de cualquier practicante**. No hay comprobacion de que el
--  observador conozca de nada a los dos que registra.
--
--  Para dos amigos y su coach es aceptable, y lo es por dos razones
--  concretas, no por optimismo:
--    1. El peor caso es que alguien te ensucie el heatmap. No hay lectura
--       de datos ajenos: la funcion solo escribe.
--    2. El dueño puede deshacerlo. El roll cae en una sesion suya, y
--       `rolls_propios` le deja borrarlo; los eventos se van detras por
--       `on delete cascade`. Verificado en la migracion, no supuesto.
--
--  El dia que entre gente de la academia esto se queda corto y hay que
--  exigir que A y B esten en el roster del observador. Anotado como
--  restriccion pendiente en docs/02-backlog.md.
-- ============================================================


-- ------------------------------------------------------------
-- registrar_roll_observado
--   Un roll fisico -> hasta dos filas en `rolls`, unidas por p_grupo.
--   Devuelve {roll_a, roll_b, creado}. `roll_b` es null cuando B no tiene
--   cuenta (no hay a quien espejarselo). `creado` distingue el alta real
--   de un reintento reconocido, que le sirve al cliente para no cantar
--   dos veces "guardado".
-- ------------------------------------------------------------
create or replace function registrar_roll_observado(
  p_grupo         uuid,
  p_practicante_a uuid,
  p_practicante_b uuid,
  p_fecha         date,
  p_modalidad     bjj_modalidad,
  p_duracion_min  smallint,
  p_resultado     bjj_resultado_roll,   -- desde el punto de vista de A
  p_eventos       jsonb                 -- [{actor,tipo,posicion,rol,objetivo,tecnica_slug,completado,minuto}]
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

  -- Serializa los reintentos del mismo roll. La cola de salida es secuencial,
  -- asi que en la practica no hay concurrencia; el lock cierra el hueco
  -- teorico entre el select de idempotencia y el insert.
  perform pg_advisory_xact_lock(hashtextextended(p_grupo::text, 0));

  -- ---------------------------------------------------------
  -- IDEMPOTENCIA — esto no es opcional
  -- La cola reintenta los envios que no sabe si llegaron. Sin esta
  -- comprobacion, volver del gimnasio sin cobertura duplica el roll. El
  -- id de grupo lo genera el cliente, asi que el reintento trae el mismo
  -- y lo reconocemos aqui.
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

  -- El observador registra a gente que quiza no ha abierto sesion hoy.
  v_sesion_a := sesion_del_dia(p_practicante_a, p_fecha, p_modalidad, v_academia);

  select coalesce(max(orden), 0) + 1 into v_orden
    from rolls where sesion_id = v_sesion_a;

  insert into rolls (sesion_id, oponente_id, orden, modalidad, duracion_min,
                     posicion_inicio, rol_inicio, resultado,
                     registrado_por, origen, roll_grupo_id)
  values (v_sesion_a, p_practicante_b, v_orden, p_modalidad, p_duracion_min,
          'de_pie', 'neutral', coalesce(p_resultado, 'no_registrado'),
          v_observador, 'observador', p_grupo)
  returning id into v_roll_a;

  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       tecnica_id, completado, minuto, created_at)
  select v_roll_a,
         (e->>'actor')::bjj_actor,
         (e->>'tipo')::bjj_tipo_evento,
         (e->>'posicion')::bjj_posicion,
         (e->>'rol')::bjj_rol,
         coalesce(nullif(e->>'objetivo', ''), 'ninguno')::bjj_objetivo,
         t.id,
         coalesce((e->>'completado')::boolean, true),
         -- El crono del observador puede quedarse corriendo si se olvida
         -- cerrar el roll, y `minuto` esta acotado a 60 por check. Recortar
         -- es mejor que perder el roll entero por el ultimo evento.
         case when e->>'minuto' is null then null
              else least(greatest((e->>'minuto')::smallint, 0::smallint), 60::smallint)
         end,
         -- clock_timestamp() avanza dentro de la sentencia (now() no):
         -- conserva el orden en que ocurrieron los eventos.
         clock_timestamp()
    from jsonb_array_elements(coalesce(p_eventos, '[]'::jsonb)) with ordinality as a(e, ord)
    -- La tecnica llega por slug y se resuelve aqui. Si no esta en el
    -- diccionario, el evento entra igual con tecnica_id null y sigue
    -- alimentando el heatmap por posicion y objetivo. Tirar el evento
    -- entero por un nombre que no conocemos seria peor.
    left join tecnicas t on t.slug = nullif(e->>'tecnica_slug', '')
   order by ord;

  -- El espejo a B. espejar_roll ya comprueba `usa_sistema` y devuelve null
  -- si B no tiene cuenta. Solo cambia `actor`: `posicion` y `rol` describen
  -- al actor, que es la misma persona fisica en las dos filas. `resultado` y
  -- `rol_inicio` si se invierten, porque esos describen al dueño del roll.
  v_roll_b := espejar_roll(v_roll_a);

  return jsonb_build_object('roll_a', v_roll_a, 'roll_b', v_roll_b, 'creado', true);
end;
$$;

comment on function registrar_roll_observado(uuid, uuid, uuid, date, bjj_modalidad,
                                             smallint, bjj_resultado_roll, jsonb) is
  'Modo observador: escribe el roll de otros dos. SECURITY DEFINER a proposito — '
  'ver el modelo de confianza al principio de db/06_rpc_roll_observado.sql.';

-- Solo usuarios con sesion iniciada. `anon` no entra aqui: seria escritura
-- anonima en el historial de cualquiera.
revoke all on function registrar_roll_observado(uuid, uuid, uuid, date, bjj_modalidad,
                                                smallint, bjj_resultado_roll, jsonb)
  from public, anon;
grant execute on function registrar_roll_observado(uuid, uuid, uuid, date, bjj_modalidad,
                                                   smallint, bjj_resultado_roll, jsonb)
  to authenticated;
