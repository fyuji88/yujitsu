-- ============================================================
--  PRUEBAS · El invariante del espejo   (bjj_38)
-- ============================================================
--
--    psql ... -f db/pruebas/espejo.sql
--
--  EL INVARIANTE, en una linea: ningun roll con `origen = 'observador'` puede
--  existir sin su pareja. Un combate son dos filas con el mismo `par_id`.
--
--  POR QUE ESTO ES LO QUE MAS IMPORTA de toda la tanda. El fallo no era que el
--  espejo se rompiera: era que se rompia EN SILENCIO. `espejar_roll()` volvia
--  `null` y `registrar_roll_observado` devolvia `creado: true` igual, asi que
--  la pantalla decia que todo habia ido bien mientras se perdia la mitad de
--  cada roll. Estuvo asi diez dias repartidos entre junio y agosto y solo se
--  vio cuando alguien miro el informe y encontro una fila donde esperaba tres.
--  Un arreglo sin esta comprobacion es el mismo fallo esperando a volver.
--
--  ---------------------------------------------------------------------------
--  LA FECHA DE CORTE
--  ---------------------------------------------------------------------------
--  Hay 63 rolls huerfanos anteriores a hoy y NO se borran ni se maquillan: se
--  ignoran explicitamente, con fecha y con motivo escrito. La comprobacion es
--  ESTRICTA a partir del corte. Lo contrario —bajar el liston hasta que el
--  historico pase— es meter el problema debajo de la alfombra, y ademas taparia
--  el siguiente.
--
--  Se corta por `created_at` y no por `sesiones.fecha`: lo que se quiere fijar
--  es «lo que esta app escriba a partir de ahora», y hay rolls con fecha de
--  junio escritos en agosto (datos sembrados con fecha hacia atras). Cortar por
--  la fecha del entreno dejaria fuera del invariante cualquier registro nuevo
--  con fecha vieja, que es justo lo que un observador hace al recuperar una
--  tarde que se le olvido.
-- ============================================================

\set ON_ERROR_STOP on

do $$
declare
  -- LA FECHA DE CORTE: el dia en que se aplico `bjj_38`. Lo de antes es
  -- historia conocida y se ignora en voz alta; a partir de aqui es estricto.
  -- Va aqui dentro y no en un `\set`: psql no interpola sus variables dentro
  -- de un bloque con comillas de dolar, y el error que da no lo dice.
  corte  timestamptz := '2026-08-02';
  malos  int;
  quien  text;
  viejos int;
  sin_op int;
begin
  -- ============================================ 1 · EL INVARIANTE
  select count(*), string_agg(distinct par_id::text, ', ')
    into malos, quien
    from (
      select r.par_id
        from rolls r
       where r.origen = 'observador'
         and r.oponente_id is not null
         and r.created_at >= corte
       group by r.par_id
      having count(*) <> 2
    ) x;

  if malos > 0 then
    raise exception 'EL ESPEJO ESTA ROTO: % par(es) de roll observado sin sus dos '
      'lados, creados a partir de %. par_id: %. '
      'Un roll observado tiene que dejar DOS rolls, uno en la sesion de cada uno.',
      malos, corte::date, left(quien, 300);
  end if;
  raise notice 'PASS  ==> ningun roll observado desde % se ha quedado sin pareja', corte::date;

  -- ============================================ 2 · LO QUE SE IGNORA, EN VOZ ALTA
  select count(*) into viejos
    from (select r.par_id from rolls r
           where r.origen = 'observador' and r.oponente_id is not null
             and r.created_at < corte
           group by r.par_id having count(*) <> 2) y;
  raise notice 'AVISO se ignoran % pares huerfanos ANTERIORES a %: son los de la '
    'guarda de usa_sistema, y se pueden reconstruir porque el par_id y los '
    'eventos estan. No se borran ni se maquillan.', viejos, corte::date;

  -- Los rolls sin oponente quedan fuera del invariante a proposito —no hay a
  -- quien espejar— pero se cuentan, porque tampoco deberian existir.
  select count(*) into sin_op from rolls
   where origen = 'observador' and oponente_id is null;
  if sin_op > 0 then
    raise notice 'AVISO % roll(es) observado(s) sin oponente. No entran en el '
      'invariante porque no hay a quien espejar, pero registrar un roll '
      'observado sin rival no deberia poder hacerse.', sin_op;
  end if;
end $$;


-- ============================================================
--  3 · Y QUE SIGA CUMPLIENDOSE: un roll observado de verdad, ahora.
--
--  El invariante de arriba mira lo que ya hay. Este bloque escribe uno nuevo,
--  con el oponente SIN `usa_sistema` —que es exactamente el caso que fallaba— y
--  comprueba el liston entero. Termina en rollback.
-- ============================================================
begin;

do $$
declare
  a uuid; au uuid; b uuid; eq uuid; q uuid; par uuid; r jsonb; ra uuid; rb uuid;
  n int;
begin
  -- Cuentas propias, para no depender de lo que haya en la base. Ver
  -- db/pruebas/observador-quedada.sql: las baterias que buscan practicantes
  -- existentes se saltan enteras en CI y llevan tiempo dando verde sin mirar.
  au := '38a10000-0000-0000-0000-0000000000a1';
  insert into auth.users (id, email) values
    (au, 'espejo-a@test'), ('38b10000-0000-0000-0000-0000000000b1', 'espejo-b@test');
  delete from practicantes
   where user_id in (au, '38b10000-0000-0000-0000-0000000000b1');
  insert into practicantes (id, nombre, cinturon, academia, usa_sistema, user_id) values
    ('38000000-0000-4000-8000-0000000000a1', 'ESP-A', 'morada', 'Sitio', true, au),
    -- EL CASO QUE FALLABA: el companero no usa la app. Antes de bjj_38 esto
    -- bastaba para que no se le guardara nada.
    ('38000000-0000-4000-8000-0000000000b1', 'ESP-B', 'azul', 'Sitio', false,
     '38b10000-0000-0000-0000-0000000000b1');
  a := '38000000-0000-4000-8000-0000000000a1';
  b := '38000000-0000-4000-8000-0000000000b1';

  insert into equipos (nombre, slug, codigo_union)
  values ('Equipo espejo', 'equipo-espejo-38', 'ESP-381') returning id into eq;
  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo, estado)
  values (eq, a, 'admin', 'activo'), (eq, b, 'miembro', 'activo');
  insert into quedadas (equipo_id, titulo, fecha, hora_inicio, lugar, modalidad, creado_por)
  values (eq, 'Open mat del espejo', current_date, '10:00', 'Sitio', 'nogi', a)
  returning id into q;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', au)::text, true);

  par := gen_random_uuid();
  r := registrar_roll_observado(
         par, a, b, current_date, 'nogi', 5::smallint, 'de_pie', 'arriba',
         'sumision_favor',
         jsonb_build_array(
           jsonb_build_object('actor', 'yo', 'tipo', 'sumision', 'posicion', 'montada',
             'rol', 'arriba', 'objetivo', 'cuello', 'completado', true,
             'segundo_roll', 40, 'tecnica_slug', 'mata_leao'),
           jsonb_build_object('actor', 'oponente', 'tipo', 'escape', 'posicion', 'montada',
             'rol', 'abajo', 'objetivo', 'ninguno', 'completado', true,
             'segundo_roll', 20, 'tecnica_slug', null)),
         q);
  ra := (r->>'roll_a')::uuid;
  rb := (r->>'roll_b')::uuid;

  if rb is null then
    raise exception 'FALLO GRAVE: no se creo el roll espejo. Es el fallo de bjj_38 '
      'otra vez: el companero no tiene usa_sistema y se le pierde su mitad.';
  end if;
  raise notice 'PASS  con el companero SIN usa_sistema, el espejo se crea igual';

  -- (1) dos rolls
  select count(*) into n from rolls where par_id = par;
  if n <> 2 then raise exception 'FALLO: % rolls del par, deberian ser 2', n; end if;
  raise notice 'PASS  dos rolls, uno por jugador';

  -- (2) dos sesiones, las dos del mismo Open Mat
  select count(*) into n from sesiones where quedada_id = q;
  if n <> 2 then raise exception 'FALLO: % sesiones colgadas del Open Mat, deberian ser 2', n; end if;
  select count(distinct practicante_id) into n from sesiones where quedada_id = q;
  if n <> 2 then raise exception 'FALLO: las 2 sesiones son de % personas', n; end if;
  raise notice 'PASS  dos sesiones, una de cada uno, las dos en el mismo Open Mat';

  -- (3) eventos duplicados, con par_evento_id compartido
  select count(*) into n from eventos where roll_id = rb;
  if n <> 2 then raise exception 'FALLO: el espejo tiene % eventos, deberian ser 2', n; end if;
  select count(*) into n from (
    select par_evento_id from eventos where roll_id in (ra, rb)
     group by par_evento_id having count(*) = 2) t;
  if n <> 2 then
    raise exception 'FALLO: % parejas de eventos con par_evento_id compartido, deberian ser 2. '
      'Sin ese enlace, precisar una tecnica no llega al espejo.', n;
  end if;
  raise notice 'PASS  los eventos van duplicados y emparejados por par_evento_id';

  -- (4) se invierte lo que se tiene que invertir
  if (select resultado from rolls where id = rb) <> 'sumision_contra' then
    raise exception 'FALLO: el resultado del espejo no se invirtio';
  end if;
  if (select rol_inicio from rolls where id = rb) <> 'abajo' then
    raise exception 'FALLO: el rol_inicio del espejo no se invirtio';
  end if;
  if (select string_agg(actor::text, ',' order by segundo_roll) from eventos where roll_id = rb)
     <> 'yo,oponente' then
    raise exception 'FALLO: los actores del espejo no se invirtieron';
  end if;
  raise notice 'PASS  se invierten resultado, rol_inicio y el actor de cada evento';

  -- (5) y NADA MAS. `posicion` y `rol` describen a la misma persona fisica en
  -- las dos filas: invertirlos es el error clasico de este espejo.
  if (select string_agg(posicion::text, ',' order by segundo_roll) from eventos where roll_id = ra)
     <> (select string_agg(posicion::text, ',' order by segundo_roll) from eventos where roll_id = rb)
  then raise exception 'FALLO: se invirtio la POSICION, que es fisica y no cambia'; end if;
  if (select string_agg(rol::text, ',' order by segundo_roll) from eventos where roll_id = ra)
     <> (select string_agg(rol::text, ',' order by segundo_roll) from eventos where roll_id = rb)
  then raise exception 'FALLO: se invirtio el ROL del evento, que describe al actor del evento'; end if;
  raise notice 'PASS  y NO se invierten posicion ni rol: describen a la misma persona';

  -- (6) idempotencia, que es de lo que vive la cola
  perform registrar_roll_observado(
    par, a, b, current_date, 'nogi', 5::smallint, 'de_pie', 'arriba', 'sumision_favor',
    jsonb_build_array(jsonb_build_object('actor', 'yo', 'tipo', 'sumision',
      'posicion', 'montada', 'rol', 'arriba', 'objetivo', 'cuello',
      'completado', true, 'segundo_roll', 40, 'tecnica_slug', 'mata_leao')), q);
  select count(*) into n from rolls where par_id = par;
  if n <> 2 then raise exception 'FALLO: reintentar dejo % rolls, deberian seguir siendo 2', n; end if;
  raise notice 'PASS  reintentar la misma llamada sigue dejando dos rolls';

  raise notice '######## EL ESPEJO: todo pasa ########';
end $$;

rollback;
