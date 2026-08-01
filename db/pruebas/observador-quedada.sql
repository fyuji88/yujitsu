-- ============================================================
--  PRUEBAS · El observador sabe de que Open Mat es   (bjj_35)
-- ============================================================
--
--    psql ... -f db/pruebas/observador-quedada.sql
--
--  Monta su escenario y termina en ROLLBACK.
--
--  EL ORDEN ES EL DE LOS RIESGOS, de mayor a menor:
--
--    1. Que la llamada de HOY deje de resolver. `registrar_roll_observado` es
--       lo unico que la cola serializa dentro de IndexedDB, y ahora tiene DOS
--       firmas vivas —esta y el puente de `p_grupo`—. Si un cuerpo encaja con
--       las dos, PostgREST contesta ambiguo y la cola se atasca en el movil de
--       alguien, no aqui. Se comprueba con la regla de PostgREST, no con la de
--       Postgres, que no son la misma.
--    2. Que con `p_quedada` nulo cambie algo. Es el 100% del trafico de hoy.
--    3. Ya despues, lo nuevo: dos Open Mats, dos sesiones, dos informes.
--    4. Y las guardas, que es una SECURITY DEFINER.
-- ============================================================

\set ON_ERROR_STOP on
begin;

-- ------------------------------------------------------------------
--  La regla de PostgREST, escrita tal cual: un cuerpo con ese conjunto de
--  claves encaja con una funcion si TODAS sus claves son parametros de la
--  funcion y TODOS los parametros sin default estan cubiertos.
--
--  No vale probarlo llamando desde SQL: Postgres resuelve por tipos ademas de
--  por nombres, asi que puede desempatar donde PostgREST no puede. Lo que
--  rompe la cola es la ambiguedad de PostgREST.
-- ------------------------------------------------------------------
create function pg_temp.candidatas(claves text[]) returns int language sql as $$
  select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'registrar_roll_observado'
     and p.proargnames @> claves
     and claves @> p.proargnames[1 : p.pronargs - p.pronargdefaults];
$$;

do $$
declare
  -- Los diez nombres de siempre: lo que lleva un elemento encolado ANTES del
  -- despliegue, y lo que manda el cliente de produccion ahora mismo.
  DIEZ  text[] := array['p_par','p_practicante_a','p_practicante_b','p_fecha',
                        'p_modalidad','p_duracion_min','p_posicion_inicio',
                        'p_rol_inicio','p_resultado','p_eventos'];
  ONCE  text[] := array['p_par','p_practicante_a','p_practicante_b','p_fecha',
                        'p_modalidad','p_duracion_min','p_posicion_inicio',
                        'p_rol_inicio','p_resultado','p_eventos','p_quedada'];
  -- El puente de bjj_28, para cualquiera que siguiera con el cliente viejo.
  PUENTE text[] := array['p_grupo','p_practicante_a','p_practicante_b','p_fecha',
                        'p_modalidad','p_duracion_min','p_posicion_inicio',
                        'p_rol_inicio','p_resultado','p_eventos'];
  n int;
begin
  n := pg_temp.candidatas(DIEZ);
  if n <> 1 then
    raise exception 'FALLO GRAVE: un cuerpo con los diez nombres de HOY encaja '
      'con % firmas. Con 0 la cola de todo el mundo se para; con 2 PostgREST '
      'contesta 300 (ambiguo) y tambien se para.', n;
  end if;
  raise notice 'PASS  la llamada de HOY (diez nombres) resuelve a UNA sola firma';

  n := pg_temp.candidatas(ONCE);
  if n <> 1 then
    raise exception 'FALLO: la llamada nueva (once nombres) encaja con % firmas', n;
  end if;
  raise notice 'PASS  la llamada nueva (once nombres) resuelve a UNA sola firma';

  n := pg_temp.candidatas(PUENTE);
  if n <> 1 then
    raise exception 'FALLO: EL PUENTE DE p_grupo ya no resuelve (% firmas). '
      'Es la condicion que Felipe puso por escrito.', n;
  end if;
  raise notice 'PASS  ==> EL PUENTE DE p_grupo SIGUE RESOLVIENDO, a UNA sola firma';

  -- Y que sean firmas DISTINTAS: si las tres cayeran en la misma, alguna de
  -- las tres comprobaciones de arriba estaria pasando por el motivo que no es.
  if (select count(distinct p.oid) from pg_proc p
        join pg_namespace nn on nn.oid = p.pronamespace
       where nn.nspname = 'public' and p.proname = 'registrar_roll_observado') <> 2 then
    raise exception 'FALLO: no hay exactamente dos firmas vivas';
  end if;
  raise notice 'PASS  y son dos firmas, la nueva y el puente: ni una de mas ni de menos';
end $$;

do $$
declare
  v_eq uuid; v_eq_ajeno uuid;
  v_a uuid; v_a_user uuid; v_b uuid;
  v_q1 uuid; v_q2 uuid; v_q_ayer uuid; v_q_ajena uuid;
  par uuid; r jsonb; n int; i int;
  s_sin uuid; s1 uuid; s2 uuid; s_b1 uuid;
  d1 jsonb; d2 jsonb;
  ev jsonb;
begin
  -- SE MONTA SUS PROPIAS CUENTAS, no las busca.
  --
  -- Las baterias que empiezan con `select ... from practicantes where user_id
  -- is not null` y avisan si no hay se saltan ENTERAS en CI, donde la base
  -- nace vacia: `enganchar-quedada.sql` y `sesion-por-quedada.sql` llevan
  -- tiempo en verde sin haber comprobado nada alli. Un aviso que nadie lee no
  -- es una red. Como todo esto vive dentro de la transaccion que acaba en
  -- `rollback`, crearlas no deja rastro.
  v_a_user := '35a10000-0000-0000-0000-0000000000a1';
  insert into auth.users (id, email) values
    (v_a_user, 'obs-q-a@test'), ('35b10000-0000-0000-0000-0000000000b1', 'obs-q-b@test');
  -- El trigger `bjj_08` crea una ficha por alta; se quitan y se ponen las
  -- nuestras, con la MISMA academia: entra en la clave de `sesion_del_dia`.
  delete from practicantes
   where user_id in (v_a_user, '35b10000-0000-0000-0000-0000000000b1');
  insert into practicantes (id, nombre, cinturon, academia, usa_sistema, user_id) values
    ('35000000-0000-4000-8000-0000000000a1', 'OBS-A', 'morada', 'Casa Felipe',
     true, v_a_user),
    ('35000000-0000-4000-8000-0000000000b1', 'OBS-B', 'azul', 'Casa Felipe',
     true, '35b10000-0000-0000-0000-0000000000b1');
  v_a := '35000000-0000-4000-8000-0000000000a1';
  v_b := '35000000-0000-4000-8000-0000000000b1';

  insert into equipos (nombre, slug, codigo_union)
  values ('Equipo bjj35', 'equipo-bjj35', 'B35-111') returning id into v_eq;
  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo, estado)
  values (v_eq, v_a, 'admin', 'activo'), (v_eq, v_b, 'miembro', 'activo');

  -- Un equipo del que NO eres miembro, para la guarda de pertenencia.
  insert into equipos (nombre, slug, codigo_union)
  values ('Equipo ajeno', 'equipo-ajeno-35', 'B35-222') returning id into v_eq_ajeno;

  insert into quedadas (equipo_id, titulo, fecha, hora_inicio, lugar, modalidad, creado_por)
  values (v_eq, 'Open mat 10h', current_date, '10:00', 'Casa Felipe', 'nogi', v_a)
  returning id into v_q1;
  insert into quedadas (equipo_id, titulo, fecha, hora_inicio, lugar, modalidad, creado_por)
  values (v_eq, 'Open mat 16h', current_date, '16:00', 'Casa Felipe', 'nogi', v_a)
  returning id into v_q2;
  insert into quedadas (equipo_id, titulo, fecha, hora_inicio, lugar, modalidad, creado_por)
  values (v_eq, 'El de ayer', current_date - 1, '10:00', 'Casa Felipe', 'nogi', v_a)
  returning id into v_q_ayer;
  insert into quedadas (equipo_id, titulo, fecha, hora_inicio, lugar, modalidad, creado_por)
  values (v_eq_ajeno, 'De otro gimnasio', current_date, '10:00', 'Otro sitio', 'nogi', v_a)
  returning id into v_q_ajena;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_a_user)::text, true);

  ev := jsonb_build_array(jsonb_build_object(
          'actor', 'yo', 'tipo', 'sumision', 'posicion', 'montada', 'rol', 'arriba',
          'objetivo', 'cuello', 'completado', true, 'segundo_roll', 40,
          'tecnica_slug', 'mata_leao'));

  -- ============================================ 1 · SIN QUEDADA, LO DE HOY
  -- Diez argumentos posicionales: exactamente la llamada del cliente que hay
  -- desplegado ahora mismo y la de cualquier elemento ya encolado.
  par := gen_random_uuid();
  r := registrar_roll_observado(
         par, v_a, v_b, current_date, 'nogi', 5::smallint, 'de_pie', 'neutral',
         'sumision_favor', ev);
  if (r->>'roll_b') is null then
    raise exception 'FALLO: la llamada de diez argumentos dejo de espejar';
  end if;
  select s.id into s_sin from rolls x join sesiones s on s.id = x.sesion_id
   where x.id = (r->>'roll_a')::uuid;
  if (select quedada_id from sesiones where id = s_sin) is not null then
    raise exception 'FALLO: sin quedada la sesion salio colgada de una';
  end if;
  raise notice 'PASS  la llamada de HOY (diez argumentos) funciona y deja la sesion suelta';

  -- Y repetirla es idempotente, que es de lo que vive la cola.
  r := registrar_roll_observado(
         par, v_a, v_b, current_date, 'nogi', 5::smallint, 'de_pie', 'neutral',
         'sumision_favor', ev);
  select count(*) into n from rolls where par_id = par;
  if n <> 2 then
    raise exception 'FALLO: reintentar duplico (% rolls, deberian ser 2)', n;
  end if;
  raise notice 'PASS  y reintentarla sigue siendo idempotente: 2 rolls, no 4';

  -- El puente, llamado de verdad y por nombre. Arriba se probo que resuelve;
  -- aqui, que ademas hace lo suyo.
  par := gen_random_uuid();
  r := registrar_roll_observado(
         p_grupo => par, p_practicante_a => v_a, p_practicante_b => v_b,
         p_fecha => current_date, p_modalidad => 'nogi', p_duracion_min => 5,
         p_posicion_inicio => 'de_pie', p_rol_inicio => 'neutral',
         p_resultado => 'sumision_favor', p_eventos => ev);
  if (r->>'roll_b') is null then
    raise exception 'FALLO: el puente de p_grupo dejo de espejar';
  end if;
  raise notice 'PASS  y el puente de p_grupo, llamado por nombre, tambien registra';

  -- ============================================ 2 · DOS OPEN MATS
  for i in 1..2 loop
    r := registrar_roll_observado(
           gen_random_uuid(), v_a, v_b, current_date, 'nogi', 5::smallint,
           'de_pie', 'neutral', 'sumision_favor',
           jsonb_build_array(jsonb_build_object(
             'actor', 'yo', 'tipo', 'sumision', 'posicion', 'montada',
             'rol', 'arriba', 'objetivo', 'cuello', 'completado', true,
             'segundo_roll', 40 + i,
             'tecnica_slug', (array['mata_leao','armbar'])[i])),
           p_quedada => v_q1);
  end loop;
  r := registrar_roll_observado(
         gen_random_uuid(), v_a, v_b, current_date, 'nogi', 5::smallint,
         'de_pie', 'neutral', 'sumision_contra',
         jsonb_build_array(jsonb_build_object(
           'actor', 'oponente', 'tipo', 'sumision', 'posicion', 'espalda',
           'rol', 'arriba', 'objetivo', 'cuello', 'completado', true,
           'segundo_roll', 55, 'tecnica_slug', 'triangulo')),
         p_quedada => v_q2);

  select s.id into s1 from rolls x join sesiones s on s.id = x.sesion_id
   where x.id = (r->>'roll_a')::uuid;   -- (la del segundo Open Mat)
  s2 := s1;
  select distinct s.id into s1 from rolls x join sesiones s on s.id = x.sesion_id
   where s.practicante_id = v_a and s.quedada_id = v_q1;
  if s1 is null or s2 is null or s1 = s2 then
    raise exception 'FALLO GRAVE: los dos Open Mats cayeron en la misma sesion. '
      'Es el bug que esta migracion viene a arreglar.';
  end if;
  if (select quedada_id from sesiones where id = s2) is distinct from v_q2 then
    raise exception 'FALLO: la sesion del segundo no quedo colgada de su Open Mat';
  end if;
  raise notice 'PASS  ==> dos Open Mats, DOS sesiones, cada una colgada de la suya';

  select count(*) into n from rolls x join sesiones s on s.id = x.sesion_id
   where s.quedada_id = v_q1 and s.practicante_id = v_a;
  if n <> 2 then raise exception 'FALLO: el de la manana tiene % rolls de A, deberian ser 2', n; end if;
  select count(*) into n from rolls x join sesiones s on s.id = x.sesion_id
   where s.quedada_id = v_q2 and s.practicante_id = v_a;
  if n <> 1 then raise exception 'FALLO: el de la tarde tiene % rolls de A, deberia ser 1', n; end if;
  raise notice 'PASS  cada Open Mat tiene SUS rolls: 2 y 1, sin mezclarse';

  -- ============================================ 3 · EL ESPEJO VA AL MISMO
  -- `espejar_roll` no recibe la quedada: la LEE de la sesion del original. Si
  -- eso no funcionara, el compañero acabaria con sus rolls en una sesion suelta
  -- y saldria sin puntos del informe.
  select s.id into s_b1 from rolls x join sesiones s on s.id = x.sesion_id
   where s.practicante_id = v_b and s.quedada_id = v_q1;
  if s_b1 is null then
    raise exception 'FALLO GRAVE: el espejo del compañero NO fue al Open Mat. '
      'Saldria del informe con cero rolls.';
  end if;
  select count(*) into n from sesiones
   where practicante_id = v_b and fecha = current_date and quedada_id is not null;
  if n <> 2 then
    raise exception 'FALLO: el compañero tiene % sesiones con Open Mat, deberian ser 2', n;
  end if;
  raise notice 'PASS  ==> el espejo del compañero va al MISMO Open Mat, sin que nadie se lo pase';

  -- ============================================ 4 · DOS INFORMES
  d1 := cerrar_quedada(v_q1);
  d2 := cerrar_quedada(v_q2);
  if (d1->>'rolls')::int <> 4 or (d2->>'rolls')::int <> 2 then
    raise exception 'FALLO GRAVE: los informes se mezclaron (% y %)',
      d1->>'rolls', d2->>'rolls';
  end if;
  raise notice 'PASS  ==> DOS informes: % rolls y %, contando los dos lados de cada combate',
    d1->>'rolls', d2->>'rolls';

  -- ============================================ 5 · LAS GUARDAS
  -- Es SECURITY DEFINER: se salta la RLS por diseño, asi que lo que no
  -- compruebe ella no lo comprueba nadie.
  begin
    perform registrar_roll_observado(
      gen_random_uuid(), v_a, v_b, current_date, 'nogi', 5::smallint,
      'de_pie', 'neutral', 'sumision_favor', ev,
      p_quedada => gen_random_uuid());
    raise exception 'FALLO: acepto un Open Mat que no existe';
  exception when no_data_found then
    raise notice 'PASS  rechaza un Open Mat que no existe';
  end;

  begin
    perform registrar_roll_observado(
      gen_random_uuid(), v_a, v_b, current_date, 'nogi', 5::smallint,
      'de_pie', 'neutral', 'sumision_favor', ev,
      p_quedada => v_q_ajena);
    raise exception 'FALLO GRAVE: colgo el roll del Open Mat de un equipo ajeno';
  exception when insufficient_privilege then
    raise notice 'PASS  rechaza el Open Mat de un equipo que no es tuyo';
  end;

  begin
    perform registrar_roll_observado(
      gen_random_uuid(), v_a, v_b, current_date, 'nogi', 5::smallint,
      'de_pie', 'neutral', 'sumision_favor', ev,
      p_quedada => v_q_ayer);
    raise exception 'FALLO: colgo un roll de hoy del Open Mat de ayer';
  exception when check_violation then
    raise notice 'PASS  rechaza colgar el roll de un Open Mat de otro dia';
  end;

  -- Y que ninguna de las tres dejara nada a medias: son tres llamadas que
  -- fallaron DESPUES de crear practicantes/tecnicas pero antes de la sesion.
  select count(*) into n from sesiones
   where practicante_id = v_a and fecha = current_date;
  if n <> 3 then
    raise exception 'FALLO: quedaron % sesiones de A hoy, deberian ser 3 '
      '(la suelta y las dos de los Open Mats)', n;
  end if;
  raise notice 'PASS  y las tres rechazadas no dejaron sesiones huerfanas: siguen siendo 3';

  raise notice '######## EL OBSERVADOR Y EL OPEN MAT: todo pasa ########';
end $$;

rollback;
