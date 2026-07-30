-- ============================================================
--  Los casos de src/lib/__fixtures__/puntos.json, en SQL.
--
--    psql ... -v ruta=/ruta/absoluta/a/src/lib/__fixtures__/puntos.json \
--             -f db/pruebas/puntos.sql
--
--  El mismo fichero lo ejecuta `npm run test:puntos` contra el calculo en
--  TypeScript. Si los dos no dan los mismos numeros, el marcador en vivo y el
--  del historico se han separado — que es un bug aunque los dos "funcionen".
--
--  Cada caso no se inserta a mano: se manda por `registrar_roll_observado()`,
--  igual que lo haria la app. Asi la misma prueba cubre la RPC, el espejo, el
--  orden de los eventos y la puntuacion, en vez de solo la ultima.
--
--  EL FIXTURE SE LEE EN EL CLIENTE, no en el servidor. Antes usaba
--  `pg_read_file`, que se ejecuta DENTRO de Postgres: con la base en la misma
--  maquina funciona y no se nota nada, pero en CI el servidor es un contenedor
--  que no ve el disco del runner, y el fichero "no existe". El backtick de psql
--  lo lee del lado de quien lanza el script, que es donde esta.
--
--  De paso deja de hacer falta ser superusuario para correr esto.
--
--  ¡OJO! ESTE SCRIPT ARRASA LA BASE. Hace `truncate practicantes cascade` para
--  montar su propio mundo, y con el cascade se lleva sesiones, rolls y eventos
--  — o sea, el juego de datos de demo entero. Si lo ejecutas, despues hay que
--  volver a sembrar:
--
--    psql ... -v confirmar=si -f db/pruebas/semilla-demo.sql
--
--  Se dice aqui porque el sintoma llega mucho despues y no se parece a la
--  causa: el recorrido del analisis empieza a fallar por numeros que no
--  cuadran, y uno se pone a mirar los predicados.
-- ============================================================
\set ON_ERROR_STOP on

\set contenido `cat :ruta`
create temp table fixture as select :'contenido'::jsonb as j;

truncate practicantes cascade;
delete from auth.users;

insert into auth.users (id, email)
  values ('11111111-1111-1111-1111-111111111111', 'coach@test');

insert into practicantes (id, nombre, usa_sistema) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Ana',   true),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'Bruno', true);

-- El claim del coach, para que private.practicante_actual() lo encuentre.
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', false);


\echo ''
\echo '=== Las guardias del diccionario son las que cree puntos.ts'
do $$
declare
  v_base text[];
  -- Copia de GUARDIAS_TODAS en src/lib/bjj.ts. Esta duplicada a proposito:
  -- es lo que hace que divergir de la base falle en vez de pasar en silencio.
  -- `libera()` depende de esto — una transicion a guardia reabre la secuencia.
  v_esperado text[] := array[
    'arana','cincuenta_cincuenta','collar_manga','de_la_riva','de_la_riva_inversa',
    'guardia_abierta','guardia_cerrada','guardia_sentada','lasso','mariposa',
    'media_guardia','single_leg_x','x_guard'
  ];
begin
  select array_agg(codigo::text order by codigo::text) into v_base
    from posiciones where es_guardia;
  if v_base is distinct from v_esperado then
    raise exception 'FALLO: las guardias de la base y las de bjj.ts no coinciden. base=%  bjj.ts=%',
      v_base, v_esperado;
  end if;
  raise notice 'PASS  las % guardias coinciden en la base y en bjj.ts', array_length(v_base, 1);
end $$;


\echo ''
\echo '=== Los casos del fixture, cada uno por la RPC del observador'
do $$
declare
  c        jsonb;
  v_grupo  uuid;
  v_res    jsonb;
  v_esp_a  int;
  v_esp_b  int;
  v_aa     int; v_ab int;   -- tanteo leido desde la fila de A
  v_ba     int; v_bb int;   -- tanteo leido desde la fila espejada de B
  v_n      int := 0;
begin
  for c in select jsonb_array_elements(j->'casos') from fixture loop
    v_n := v_n + 1;
    v_grupo := md5(c->>'nombre')::uuid;
    v_esp_a := (c->'esperado'->>'a')::int;
    v_esp_b := (c->'esperado'->>'b')::int;

    v_res := registrar_roll_observado(
      v_grupo,
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
      'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
      current_date, 'nogi', 6::smallint,
      'de_pie'::bjj_posicion, 'neutral'::bjj_rol,
      'no_registrado'::bjj_resultado_roll,
      c->'eventos');

    if v_res->>'roll_b' is null then
      raise exception 'FALLO [%]: no se espejo el roll', c->>'nombre';
    end if;

    select puntos_autor, puntos_oponente into v_aa, v_ab
      from v_puntos_roll where roll_id = (v_res->>'roll_a')::uuid;
    select puntos_autor, puntos_oponente into v_ba, v_bb
      from v_puntos_roll where roll_id = (v_res->>'roll_b')::uuid;

    if v_aa <> v_esp_a or v_ab <> v_esp_b then
      raise exception 'FALLO [%]: salio %-%, se esperaba %-%',
        c->>'nombre', v_aa, v_ab, v_esp_a, v_esp_b;
    end if;

    -- EL INVARIANTE DEL ESPEJO. Si esto falla, o el espejo o la puntuacion
    -- estan mal, y da igual cual: es un fallo.
    if v_ba <> v_esp_b or v_bb <> v_esp_a then
      raise exception 'FALLO [%]: el espejo dice %-%, y el reflejo de %-% es %-%',
        c->>'nombre', v_ba, v_bb, v_esp_a, v_esp_b, v_esp_b, v_esp_a;
    end if;

    raise notice 'PASS  %: %-% y el espejo %-%',
      c->>'nombre', v_aa, v_ab, v_ba, v_bb;
  end loop;

  raise notice 'PASS  % casos del fixture, con su espejo', v_n;
end $$;


\echo ''
\echo '=== El sello en segundos sobrevive, y el minuto se deriva de el'
do $$
declare v_mal int;
begin
  select count(*) into v_mal from eventos
   where segundo_roll is not null and minuto is distinct from least(60, segundo_roll / 60);
  if v_mal > 0 then
    raise exception 'FALLO: % eventos con el minuto mal derivado de los segundos', v_mal;
  end if;
  select count(*) into v_mal from eventos where segundo_roll is null;
  if v_mal > 0 then
    raise exception 'FALLO: % eventos sin sello en segundos', v_mal;
  end if;
  raise notice 'PASS  todos los eventos llevan segundo_roll y el minuto sale de el';
end $$;


\echo ''
\echo '=== Idempotencia despues de recrear la RPC'
do $$
declare
  v_grupo uuid := md5('todas_las_acciones_que_puntuan')::uuid;
  v_antes int; v_despues int; v_ev_antes int; v_ev_despues int;
begin
  select count(*) into v_antes from rolls where roll_grupo_id = v_grupo;
  select count(*) into v_ev_antes from eventos e
    join rolls r on r.id = e.roll_id where r.roll_grupo_id = v_grupo;

  perform registrar_roll_observado(
    v_grupo,
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
    current_date, 'nogi', 6::smallint,
    'de_pie'::bjj_posicion, 'neutral'::bjj_rol,
    'no_registrado'::bjj_resultado_roll,
    '[]'::jsonb);

  select count(*) into v_despues from rolls where roll_grupo_id = v_grupo;
  select count(*) into v_ev_despues from eventos e
    join rolls r on r.id = e.roll_id where r.roll_grupo_id = v_grupo;

  if v_despues <> v_antes or v_ev_despues <> v_ev_antes then
    raise exception 'FALLO: el reintento duplico (rolls % -> %, eventos % -> %)',
      v_antes, v_despues, v_ev_antes, v_ev_despues;
  end if;
  raise notice 'PASS  reintento reconocido: siguen % rolls y % eventos', v_despues, v_ev_despues;
end $$;


\echo ''
\echo '=== Un roll que empieza en guardia cerrada con A abajo'
do $$
declare
  v_grupo uuid := 'cccccccc-0000-0000-0000-00000000000c';
  v_res jsonb;
  v_pa record; v_pb record;
begin
  v_res := registrar_roll_observado(
    v_grupo,
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
    current_date, 'gi', 4::smallint,
    'guardia_cerrada'::bjj_posicion, 'abajo'::bjj_rol,
    'sin_sumision'::bjj_resultado_roll,
    '[{"actor":"yo","tipo":"barrida","posicion":"guardia_cerrada","rol":"abajo",
       "objetivo":"ninguno","completado":true,"segundo_roll":30}]'::jsonb);

  select posicion_inicio, rol_inicio into v_pa from rolls where id = (v_res->>'roll_a')::uuid;
  select posicion_inicio, rol_inicio into v_pb from rolls where id = (v_res->>'roll_b')::uuid;

  if v_pa.rol_inicio <> 'abajo' or v_pb.rol_inicio <> 'arriba' then
    raise exception 'FALLO: rol_inicio no se invirtio (A=%, B=%)', v_pa.rol_inicio, v_pb.rol_inicio;
  end if;
  if v_pa.posicion_inicio <> v_pb.posicion_inicio then
    raise exception 'FALLO: posicion_inicio deberia ser la misma para los dos (A=%, B=%)',
      v_pa.posicion_inicio, v_pb.posicion_inicio;
  end if;
  raise notice 'PASS  A empieza % %, B empieza % % — misma posicion, rol invertido',
    v_pa.posicion_inicio, v_pa.rol_inicio, v_pb.posicion_inicio, v_pb.rol_inicio;
end $$;


\echo ''
\echo '=== Las transiciones no ensucian los heatmaps ni fuertes/debiles'
do $$
declare v_n int;
begin
  select count(*) into v_n from v_heatmap_ofensivo where objetivo = 'ninguno';
  if v_n > 0 then raise exception 'FALLO: % filas basura en el heatmap ofensivo', v_n; end if;
  select count(*) into v_n from v_heatmap_defensivo where objetivo = 'ninguno';
  if v_n > 0 then raise exception 'FALLO: % filas basura en el heatmap defensivo', v_n; end if;
  raise notice 'PASS  los heatmaps siguen limpios (ya filtraban tipo = sumision)';

  select count(*) into v_n from v_eventos where tipo = 'transicion';
  if v_n = 0 then raise exception 'FALLO: no hay transiciones, la prueba no vale nada'; end if;
  raise notice 'PASS  hay % transiciones en los datos, asi que el filtro se esta ejerciendo', v_n;
end $$;

\echo ''
\echo '######## TODAS LAS PRUEBAS DE PUNTOS PASARON ########'
