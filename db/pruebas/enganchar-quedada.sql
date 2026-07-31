-- ============================================================
--  PRUEBAS · La tuberia de la quedada   (bjj_33)
-- ============================================================
--
--    psql ... -f db/pruebas/enganchar-quedada.sql
--
--  Se monta su propio escenario y termina en ROLLBACK.
--
--  LA QUE MANDA ES LA ULTIMA. Los tres logros de ambito quedada —artista,
--  ambidiestro, notario— NO SE HAN DISPARADO NUNCA, para nadie, porque
--  `sesiones.quedada_id` no lo escribia nadie. Si despues de esto siguen a
--  cero, el enganche no esta bien hecho por mucho que la columna tenga valores.
--  Todo lo demas es fontaneria para llegar hasta ahi.
-- ============================================================

\set ON_ERROR_STOP on
begin;

do $$
declare
  v_eq     uuid;
  v_a      uuid; v_a_user uuid;
  v_b      uuid;
  v_q      uuid;
  v_ses_a  uuid; v_ses_b uuid;
  par      uuid;
  r        jsonb;
  n        int;
  v_datos  jsonb;
  i        int;
begin
  -- ---------------------------------------------------- escenario
  select id, user_id into v_a, v_a_user
    from practicantes where user_id is not null order by created_at limit 1;
  if v_a is null then
    raise notice 'AVISO  no hay ninguna ficha con cuenta: NO se ha probado NADA';
    return;
  end if;
  select id into v_b from practicantes
   where id <> v_a and usa_sistema order by created_at limit 1;
  if v_b is null then
    raise notice 'AVISO  hace falta un segundo practicante con cuenta: NO se ha probado NADA';
    return;
  end if;

  insert into equipos (nombre, slug, codigo_union)
  values ('Equipo tuberia', 'equipo-tuberia', 'TUB-999') returning id into v_eq;
  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo, estado)
  values (v_eq, v_a, 'admin', 'activo'), (v_eq, v_b, 'miembro', 'activo');

  insert into quedadas (equipo_id, titulo, fecha, modalidad, creado_por)
  values (v_eq, 'Open Mat de prueba', current_date, 'nogi', v_a) returning id into v_q;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_user)::text, true);

  -- ============================================ 1 · rolls observados de verdad
  -- Tres tecnicas DISTINTAS y de mecanicas distintas, para que ARTISTA pueda
  -- dispararse: pide tres mecanicas en la misma quedada.
  for i in 1..3 loop
    par := gen_random_uuid();
    r := registrar_roll_observado(
      par, v_a, v_b, current_date, 'nogi', 5::smallint, 'de_pie', 'neutral',
      'sumision_favor',
      jsonb_build_array(jsonb_build_object(
        'actor', 'yo', 'tipo', 'sumision', 'posicion', 'montada', 'rol', 'arriba',
        'objetivo', 'cuello', 'completado', true, 'segundo_roll', 40 + i,
        'tecnica_slug', (array['mata_leao', 'armbar', 'triangulo'])[i])));
    if (r->>'roll_b') is null then
      raise exception 'FALLO: el espejo no se creo (¿el segundo no tiene cuenta?)';
    end if;
  end loop;
  raise notice 'PASS  tres rolls observados registrados, con espejo';

  select s.id into v_ses_a from sesiones s
   where s.practicante_id = v_a and s.fecha = current_date order by s.created_at desc limit 1;
  select s.id into v_ses_b from sesiones s
   where s.practicante_id = v_b and s.fecha = current_date order by s.created_at desc limit 1;

  -- ============================================ 2 · la guarda de fecha
  begin
    perform enganchar_sesion_a_quedada(v_ses_a,
      (select id from quedadas where fecha <> current_date
          and equipo_id in (select private.mis_equipos()) limit 1));
    -- Si no habia ninguna de otro dia, se fabrica el caso.
    raise exception 'sin_caso';
  exception
    when check_violation then
      raise notice 'PASS  enganchar una sesion de otro dia falla: la guarda de fecha';
    when others then
      -- No habia quedada de otro dia a mano: se crea una y se reintenta.
      declare v_otra uuid;
      begin
        insert into quedadas (equipo_id, titulo, fecha, modalidad, creado_por)
        values (v_eq, 'De otro dia', current_date + 7, 'nogi', v_a) returning id into v_otra;
        begin
          perform enganchar_sesion_a_quedada(v_ses_a, v_otra);
          raise exception 'FALLO GRAVE: engancho una sesion a un Open Mat de otro dia';
        exception when check_violation then
          raise notice 'PASS  enganchar una sesion de otro dia falla: la guarda de fecha';
        end;
      end;
  end;

  -- ============================================ 3 · enganchar de verdad
  perform enganchar_sesion_a_quedada(v_ses_a, v_q);
  perform enganchar_sesion_a_quedada(v_ses_b, v_q);
  perform enganchar_sesion_a_quedada(v_ses_a, v_q);   -- idempotente
  select count(*) into n from sesiones where quedada_id = v_q;
  if n <> 2 then raise exception 'FALLO: % sesiones enganchadas, deberian ser 2', n; end if;
  raise notice 'PASS  las sesiones de los DOS jugadores quedan enganchadas, y es idempotente';

  -- ============================================ 4 · metricas, por primera vez
  select count(*) into n from private.metricas_quedada(v_q);
  if n = 0 then
    raise exception 'FALLO GRAVE: metricas_quedada sigue vacia con las sesiones enganchadas';
  end if;
  raise notice 'PASS  private.metricas_quedada devuelve % filas, por primera vez', n;

  -- ============================================ 5 · el informe, con numeros
  v_datos := cerrar_quedada(v_q);
  if jsonb_array_length(v_datos->'ranking') = 0 then
    raise exception 'FALLO: el informe sale con el ranking vacio';
  end if;
  if jsonb_array_length(v_datos->'titulos') = 0 then
    raise exception 'FALLO: el informe sale sin titulos';
  end if;
  raise notice 'PASS  el informe trae % en el ranking y % titulos, y % rolls',
    jsonb_array_length(v_datos->'ranking'), jsonb_array_length(v_datos->'titulos'),
    v_datos->>'rolls';

  -- ============================================ 6 · LA QUE MANDA
  select count(*) into n
    from v_logros_conseguidos v join logros l on l.clave = v.clave
   where l.ambito = 'quedada' and v.ref_id = v_q::text;
  if n = 0 then
    raise exception 'FALLO GRAVE: ningun logro de ambito quedada se ha disparado. '
      'La columna esta rellena pero el enganche no sirve de nada.';
  end if;
  raise notice 'PASS  ==> % logros de ambito quedada disparados. Es la primera vez.', n;

  -- ============================================ 7 · cerrar sin nada, falla
  declare v_vacia uuid;
  begin
    insert into quedadas (equipo_id, titulo, fecha, modalidad, creado_por)
    values (v_eq, 'Sin nadie', current_date, 'nogi', v_a) returning id into v_vacia;
    begin
      perform cerrar_quedada(v_vacia);
      raise exception 'FALLO GRAVE: cerro un Open Mat sin un solo roll';
    exception when check_violation then
      raise notice 'PASS  cerrar sin rolls enganchados falla, en vez de escribir un informe vacio';
    end;
  end;

  -- ============================================ 8 · desenganchar
  perform desenganchar_sesion(v_ses_a);
  select count(*) into n from sesiones where quedada_id = v_q;
  if n <> 1 then raise exception 'FALLO: desenganchar no funciono (% siguen)', n; end if;
  raise notice 'PASS  y se puede desenganchar, porque el automatico se equivocara';

  raise notice '######## LA TUBERIA DE LA QUEDADA: todo pasa ########';
end $$;

rollback;
