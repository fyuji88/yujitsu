-- ============================================================
--  BJJ TRACKER — La tuberia que faltaba   ·   Migracion bjj_33
-- ============================================================
--
--  EL DIAGNOSTICO, medido y no supuesto: 0 de 71 sesiones tienen `quedada_id`.
--  Ninguna. Nunca.
--
--  Y de esa columna cuelga TODO el bloque de la quedada:
--
--      private.metricas_quedada  ->  from rolls r join sesiones s on ...
--                                     where s.quedada_id = p_quedada
--
--  Ese join devuelve cero filas siempre, asi que el informe sale vacio, el
--  ranking sale vacio, los titulos salen vacios, y los TRES logros de ambito
--  quedada —artista, ambidiestro, notario— no se han disparado nunca, para
--  nadie. (El encargo decia cuatro; son tres.)
--
--  El informe no estaba roto: estaba desconectado. Y la nota de CAMBIOS que
--  decia "aun no tienen datos reales" diagnosticaba mal — no faltaban datos,
--  faltaba la tuberia.
--
--  DONDE VA EL ENLACE. En `sesiones.quedada_id`, no en el roll: un roll llega a
--  su Open Mat por eventos -> rolls -> sesiones. Eso esta bien modelado y no se
--  toca. Lo que falta es ESCRIBIRLO.
--
--  POR QUE UNA RPC APARTE Y NO UN PARAMETRO MAS EN
--  `registrar_roll_observado`: esa funcion ya tiene DOS firmas por el puente de
--  `p_grupo`, y es la unica llamada que la cola de salida serializa dentro de
--  IndexedDB. Una tercera firma es pedir el mismo problema otra vez.
-- ============================================================

begin;

create function public.enganchar_sesion_a_quedada(p_sesion uuid, p_quedada uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_yo      uuid;
  s         sesiones%rowtype;
  q         quedadas%rowtype;
  v_registro boolean;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien engancha no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  select * into s from sesiones where id = p_sesion;
  if not found then
    raise exception 'esa sesion no existe' using errcode = 'no_data_found';
  end if;
  select * into q from quedadas where id = p_quedada;
  if not found then
    raise exception 'ese Open Mat no existe' using errcode = 'no_data_found';
  end if;

  -- 1 · QUIEN. El dueño de la sesion, o quien registro sus rolls —que en modo
  --     observador es otra persona y es justo quien esta delante del movil.
  v_registro := exists (select 1 from rolls r
                         where r.sesion_id = p_sesion and r.registrado_por = v_yo);
  if s.practicante_id <> v_yo and not v_registro then
    raise exception 'solo el dueño de la sesion o quien registro sus rolls pueden engancharla'
      using errcode = 'insufficient_privilege';
  end if;

  -- 2 · DE QUE EQUIPO. La quedada tiene que ser de un equipo tuyo. Sin esto,
  --     cualquiera colgaria su entreno del Open Mat de otro gimnasio y le
  --     ensuciaria el informe.
  if q.equipo_id is not null and q.equipo_id not in (select private.mis_equipos()) then
    raise exception 'ese Open Mat no es de un equipo tuyo'
      using errcode = 'insufficient_privilege';
  end if;

  -- 3 · LA FECHA, que es la guarda que mas veces va a salvar el dato. Impide
  --     enganchar el entreno del martes al Open Mat del domingo, que es el
  --     error facil de cometer desde la pantalla de "enganchar las de hoy" y el
  --     que nadie detectaria despues.
  if s.fecha <> q.fecha then
    raise exception 'la sesion es del % y el Open Mat del %: no cuadran',
      s.fecha, q.fecha using errcode = 'check_violation';
  end if;

  -- Idempotente: engancharla dos veces no rompe nada ni cuenta doble.
  update sesiones set quedada_id = p_quedada where id = p_sesion;
end;
$$;

comment on function public.enganchar_sesion_a_quedada(uuid, uuid) is
  'Cuelga una sesion de un Open Mat, que es de donde salen el informe, el '
  'ranking, los titulos y los logros de ambito quedada. Comprueba quien, de que '
  'equipo y que las fechas cuadran — esta ultima es la que impide enganchar el '
  'entreno del martes al Open Mat del domingo.';

revoke all on function public.enganchar_sesion_a_quedada(uuid, uuid) from public, anon;
grant execute on function public.enganchar_sesion_a_quedada(uuid, uuid)
  to authenticated, service_role;

-- DESENGANCHAR HACE FALTA, y no es un extra: el enganche automatico se va a
-- equivocar alguna vez —dos Open Mats el mismo dia, o entrenaste por tu cuenta
-- y ademas fuiste— y sin esto no habria forma de arreglarlo desde la app.
create function public.desenganchar_sesion(p_sesion uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare v_yo uuid; s sesiones%rowtype; v_registro boolean;
begin
  v_yo := private.practicante_actual();
  select * into s from sesiones where id = p_sesion;
  if not found then
    raise exception 'esa sesion no existe' using errcode = 'no_data_found';
  end if;
  v_registro := exists (select 1 from rolls r
                         where r.sesion_id = p_sesion and r.registrado_por = v_yo);
  if s.practicante_id <> v_yo and not v_registro then
    raise exception 'solo el dueño de la sesion o quien registro sus rolls pueden desengancharla'
      using errcode = 'insufficient_privilege';
  end if;
  update sesiones set quedada_id = null where id = p_sesion;
end;
$$;

revoke all on function public.desenganchar_sesion(uuid) from public, anon;
grant execute on function public.desenganchar_sesion(uuid) to authenticated, service_role;

-- ------------------------------------------------------- enganchar las del dia
--
-- UNA FUNCION, DOS USOS, y por eso existe:
--
--   - EN MODO OBSERVADOR se llama una vez y engancha las sesiones de los dos
--     jugadores de cada roll que has registrado esa tarde. La alternativa era
--     un parametro mas en `registrar_roll_observado`, que ya tiene DOS firmas
--     por el puente de `p_grupo` y es lo unico que la cola serializa. Una
--     tercera firma es pedir el mismo problema otra vez.
--   - HACIA ATRAS, desde la pantalla del Open Mat, cuando alguien se olvido.
--     Poder arreglarlo al dia siguiente es la diferencia entre tener informe y
--     tener un agujero.
--
-- Engancha lo que puedes enganchar, y nada mas:
--   (a) tus propias sesiones;
--   (b) las sesiones cuyos rolls registraste tu —el caso del observador—;
--   (c) si eres ADMIN de ese equipo, las de quien esta APUNTADO a esa quedada.
--       Acotado a proposito: apuntarse es haber dicho que vas.
create function public.enganchar_del_dia(p_quedada uuid)
returns int language plpgsql security definer
set search_path = public as $$
declare
  v_yo    uuid;
  q       quedadas%rowtype;
  v_admin boolean;
  n       int;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien engancha no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  select * into q from quedadas where id = p_quedada;
  if not found then
    raise exception 'ese Open Mat no existe' using errcode = 'no_data_found';
  end if;
  if q.equipo_id is not null and q.equipo_id not in (select private.mis_equipos()) then
    raise exception 'ese Open Mat no es de un equipo tuyo'
      using errcode = 'insufficient_privilege';
  end if;

  v_admin := private.es_admin(q.equipo_id);

  update sesiones s
     set quedada_id = p_quedada
   where s.fecha = q.fecha                     -- la guarda de fecha, tambien aqui
     and s.quedada_id is distinct from p_quedada
     and (
       s.practicante_id = v_yo
       or exists (select 1 from rolls r
                   where r.sesion_id = s.id and r.registrado_por = v_yo)
       or (v_admin and exists (select 1 from inscripciones i
                                where i.quedada_id = p_quedada
                                  and i.practicante_id = s.practicante_id
                                  and i.estado = 'apuntado'))
     );

  get diagnostics n = row_count;
  return n;
end;
$$;

comment on function public.enganchar_del_dia(uuid) is
  'Engancha a un Open Mat las sesiones de SU MISMO DIA que puedes enganchar: '
  'las tuyas, las cuyos rolls registraste tu, y —si eres admin— las de quien '
  'esta apuntado. La usan el modo observador y el arreglo hacia atras.';

revoke all on function public.enganchar_del_dia(uuid) from public, anon;
grant execute on function public.enganchar_del_dia(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------- el alcance
--
-- Cerrar es de una sola direccion, asi que antes hay que poder ver QUE se va a
-- incluir. Mismo principio que en la fusion de tecnicas: una accion que no se
-- deshace enseña lo que va a hacer antes de hacerlo.
create function public.alcance_quedada(p_quedada uuid)
returns jsonb language sql stable security definer
set search_path = public as $$
  select jsonb_build_object(
    'rolls',    (select count(*) from rolls r
                   join sesiones s on s.id = r.sesion_id
                  where s.quedada_id = p_quedada),
    'personas', (select count(distinct s.practicante_id) from sesiones s
                  where s.quedada_id = p_quedada),
    'sesiones', (select count(*) from sesiones s where s.quedada_id = p_quedada)
  )
  where exists (select 1 from quedadas q
                 where q.id = p_quedada
                   and q.equipo_id in (select private.mis_equipos()))
$$;

comment on function public.alcance_quedada(uuid) is
  'Que se va a incluir si se cierra este Open Mat: rolls, personas y sesiones. '
  'Se enseña ANTES de cerrar, porque cerrar no se deshace.';

revoke all on function public.alcance_quedada(uuid) from public, anon;
grant execute on function public.alcance_quedada(uuid) to authenticated, service_role;

commit;

-- ============================================================
--  cerrar_quedada NO CIERRA SI NO HAY NADA QUE CONTAR
-- ============================================================
--
--  Hay TRES informes en produccion generados con cero rolls. La funcion cerro,
--  escribio el informe y puso `estado = 'cerrada'` sin una sola advertencia. Y
--  cerrar es de una sola direccion.
--
--  Un informe vacio parece que la app esta rota, cuando lo que falta es un
--  campo. Asi que ahora se planta y dice que hacer.
--
--  Se hace por cirugia sobre la definicion viva y no pegando la funcion entera:
--  el cuerpo de una FUNCION se guarda verbatim, asi que el reemplazo textual es
--  exacto. Y si el texto no esta donde se espera, el `raise` para en vez de
--  dejarla sin cambiar — que es como se recrea una vista sin el cambio y nadie
--  se entera.
-- ============================================================

begin;

do $bloque$
declare d text; nuevo text;
begin
  d := pg_get_functiondef('public.cerrar_quedada(uuid, boolean)'::regprocedure);

  -- El anclaje es SOLO la linea, sin el comentario de despues: la copia de
  -- produccion vino por MCP y alli los comentarios se recortaron, asi que un
  -- anclaje que incluyera "-- Congelado" fallaba contra produccion y funcionaba
  -- en local. Lo bueno de que el bloque tenga `raise` es que eso salio como un
  -- error ruidoso y no como una funcion recreada sin el cambio.
  nuevo := replace(d,
'  v_yo := private.practicante_actual();
',
'  v_yo := private.practicante_actual();

  -- SIN ROLLS NO SE CIERRA. Cerrar es de una sola direccion, y un informe vacio
  -- parece que la app esta rota cuando lo que falta es enganchar las sesiones.
  -- El mensaje dice que pasa Y que hacer: sin lo segundo, esto seria un muro.
  if not exists (select 1 from rolls r
                   join sesiones s on s.id = r.sesion_id
                  where s.quedada_id = p_quedada) then
    raise exception ''no hay sesiones enganchadas a este Open Mat, asi que el informe saldria vacio. Engancha las sesiones del dia desde la pantalla del Open Mat y vuelve a cerrarlo''
      using errcode = ''check_violation'';
  end if;
');

  if nuevo = d then
    raise exception 'NO ENCONTRE donde meter la guarda: cerrar_quedada no es la que esperaba';
  end if;

  execute nuevo;
end $bloque$;

commit;
