-- ============================================================
--  BJJ TRACKER — El observador sabe de qué Open Mat es  ·  bjj_35
-- ============================================================
--
--  LO QUE FALTABA. `bjj_34` hizo que dos Open Mats el mismo dia fueran dos
--  sesiones, pero solo por el camino de los rolls PROPIOS: el observador llama
--  a `sesion_del_dia` SIN quedada, y con nulo esa funcion encuentra la primera
--  sesion del dia. O sea que los rolls del segundo Open Mat caian en la sesion
--  del primero. Es el domingo de Felipe: dos Open Mats, los dos nogi, mismo
--  sitio.
--
--  ---------------------------------------------------------------------------
--  SE REEMPLAZA, NO SE SOBRECARGA
--  ---------------------------------------------------------------------------
--  Con las dos versiones de `p_par` vivas, un cuerpo con el conjunto de nombres
--  de hoy encajaria en las dos y PostgREST no sabria cual: contestaria
--  ambiguo. Asi que se TIRA la de `p_par` y se crea una sola con el parametro
--  nuevo por defecto.
--
--  EL PUENTE DE `p_grupo` NO SE TOCA. Su conjunto de nombres es distinto
--  —lleva `p_grupo` donde esta lleva `p_par`—, asi que no entra en la
--  ambiguedad. Se comprueba despues, no se supone: db/pruebas/observador-
--  quedada.sql llama a las dos formas.
--
--  Y LA COLA. Esta es la unica llamada que la cola serializa dentro de
--  IndexedDB. Un elemento encolado ANTES de esto lleva los diez nombres de
--  siempre; como `p_quedada` tiene default, ese conjunto sigue encajando y
--  entra con quedada nula — que es exactamente el comportamiento de hoy. O sea
--  que este cambio es compatible hacia atras por construccion, y eso tambien
--  se prueba.
--
--  ---------------------------------------------------------------------------
--  `espejar_roll` NO CAMBIA DE FIRMA
--  ---------------------------------------------------------------------------
--  No hace falta: ya carga la sesion del roll original, asi que la quedada la
--  LEE de ahi (`s.quedada_id`) en vez de recibirla. Una firma menos que tocar,
--  y ademas es mas correcto — el espejo va donde fue el original, siempre, sin
--  que nadie tenga que acordarse de pasarlo.
-- ============================================================

begin;

-- ---------------------------------------------------------- 1 · el espejo
--
-- Cirugia sobre la definicion viva: el cuerpo de una FUNCION se guarda
-- verbatim, asi que el reemplazo textual es exacto. Y si el texto no esta donde
-- se espera, el `raise` para en vez de dejarla sin cambiar.
do $bloque$
declare d text; nuevo text;
begin
  d := pg_get_functiondef('public.espejar_roll(uuid)'::regprocedure);
  nuevo := replace(d,
    'sesion_del_dia(r.oponente_id, s.fecha, r.modalidad, s.academia)',
    -- La quedada del espejo es la del original: el mismo combate no puede
    -- estar en dos Open Mats distintos.
    'sesion_del_dia(r.oponente_id, s.fecha, r.modalidad, s.academia, s.quedada_id)');
  if nuevo = d then
    raise exception 'NO ENCONTRE la llamada a sesion_del_dia en espejar_roll';
  end if;
  execute nuevo;
end $bloque$;

-- --------------------------------------------------- 2 · la RPC del observador
do $bloque$
declare d text; nuevo text;
begin
  d := pg_get_functiondef(
    'public.registrar_roll_observado(uuid,uuid,uuid,date,bjj_modalidad,smallint,bjj_posicion,bjj_rol,bjj_resultado_roll,jsonb)'::regprocedure);

  -- (a) el parametro nuevo, con default para que la cola vieja siga entrando
  nuevo := replace(d,
    'p_resultado bjj_resultado_roll, p_eventos jsonb)',
    'p_resultado bjj_resultado_roll, p_eventos jsonb, p_quedada uuid DEFAULT NULL)');
  if nuevo = d then
    raise exception 'NO ENCONTRE la firma de registrar_roll_observado';
  end if;

  -- (b) que llegue hasta la sesion
  d := nuevo;
  nuevo := replace(d,
    'sesion_del_dia(p_practicante_a, p_fecha, p_modalidad, v_academia)',
    'sesion_del_dia(p_practicante_a, p_fecha, p_modalidad, v_academia, p_quedada)');
  if nuevo = d then
    raise exception 'NO ENCONTRE la llamada a sesion_del_dia en registrar_roll_observado';
  end if;

  -- (c) las guardas de la quedada, justo despues de la comprobacion de que los
  --     dos practicantes existen. Es SECURITY DEFINER: sin esto, quien registra
  --     podria colgar el roll del Open Mat de otro gimnasio, o del domingo que
  --     viene.
  d := nuevo;
  nuevo := replace(d,
'  v_sesion_a := sesion_del_dia(',
'  if p_quedada is not null then
    declare q quedadas%rowtype;
    begin
      select * into q from quedadas where id = p_quedada;
      if not found then
        raise exception ''ese Open Mat no existe'' using errcode = ''no_data_found'';
      end if;
      if q.equipo_id is not null
         and q.equipo_id not in (select private.mis_equipos()) then
        raise exception ''ese Open Mat no es de un equipo tuyo''
          using errcode = ''insufficient_privilege'';
      end if;
      if q.fecha <> p_fecha then
        raise exception ''el roll es del % y el Open Mat del %: no cuadran'',
          p_fecha, q.fecha using errcode = ''check_violation'';
      end if;
    end;
  end if;

  v_sesion_a := sesion_del_dia(');
  if nuevo = d then
    raise exception 'NO ENCONTRE donde meter las guardas de la quedada';
  end if;

  -- SE REEMPLAZA: con las dos vivas, PostgREST no sabria cual coger.
  drop function public.registrar_roll_observado(
    uuid, uuid, uuid, date, bjj_modalidad, smallint,
    bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb);
  execute nuevo;
end $bloque$;

-- EL REVOKE, que es lo que se me olvido en bjj_34 y cazo el caso 27 de la
-- bateria. Postgres regala EXECUTE a PUBLIC en toda funcion nueva y `anon`
-- hereda de PUBLIC.
revoke all on function public.registrar_roll_observado(uuid, uuid, uuid, date,
  bjj_modalidad, smallint, bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb, uuid)
  from public, anon;
grant execute on function public.registrar_roll_observado(uuid, uuid, uuid, date,
  bjj_modalidad, smallint, bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb, uuid)
  to authenticated, service_role;

commit;
