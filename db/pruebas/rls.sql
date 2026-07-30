-- ============================================================
--  RLS · la bateria completa
--
--    psql "postgresql://postgres@127.0.0.1:55432/bjj" -f db/pruebas/rls.sql
--
--  POR QUE ESTO EXISTE. En esta app la RLS es TODO el perimetro de seguridad.
--  No hay servidor propio: el navegador habla directo con Postgres con una
--  clave que es publica por diseño, y lo unico que separa los datos de una
--  persona de los de otra son las politicas. Van veintiuna migraciones, varias
--  han tocado la lectura (bjj_13, bjj_15) y la escritura por terceros
--  (bjj_09), y hasta hoy no habia una sola prueba automatica de que sigan
--  haciendo lo que creemos.
--
--  COMO SE PRUEBA DE VERDAD. Como `postgres` o con la clave de servicio la RLS
--  se salta entera y TODO pasaria siempre — un test asi no prueba nada, solo
--  da tranquilidad falsa. Hay que ponerse el rol y el claim:
--
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"...","role":"authenticated"}';
--
--  NO DEJA RASTRO. Todo vive dentro de una transaccion que termina en
--  `rollback`, asi que se puede correr mil veces seguidas. El escenario se
--  monta dentro de esa misma transaccion.
--
--  SOLO CONTRA EL POSTGRES LOCAL. Nunca contra produccion — ver db/README.md.
--
--  UNA COSA SOBRE LOS FALLOS. Si un caso falla, no "arregles" la politica para
--  que pase: puede que el test tenga razon y la politica este mal. Un fallo
--  aqui es informacion, no una tarea de limpieza.
-- ============================================================
\set ON_ERROR_STOP on

begin;

-- El marcador.
--
-- Tabla NORMAL y no temporal, aunque suene al reves: los casos se apuntan
-- desde bloques que corren como `authenticated` o como `anon`, y a un
-- `pg_temp` ajeno no se le pueden dar permisos. Como todo esto vive dentro de
-- una transaccion que acaba en `rollback`, la tabla desaparece igual.
drop table if exists rls_res;
create table rls_res (
  n serial, familia text, caso text, ok boolean, detalle text
);
grant all on rls_res to authenticated, anon;
grant usage, select on sequence rls_res_n_seq to authenticated, anon;

-- ------------------------------------------------------------
-- Ayudantes
--
-- `pr_es()` cambia de identidad y `pr_admin()` vuelve. Van como funciones para
-- que cada caso quepa en una linea y se lea la INTENCION, no la fontaneria.
-- ------------------------------------------------------------
create or replace function pr_es(p_user uuid) returns void
language plpgsql as $$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
end $$;

create or replace function pr_anon() returns void
language plpgsql as $$
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
end $$;

create or replace function pr_admin() returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

/** Apunta un caso. `p_ok` ya viene resuelto por quien llama. */
create or replace function pr_caso(p_familia text, p_caso text, p_ok boolean,
                                   p_detalle text default '')
returns void language sql as $$
  insert into rls_res (familia, caso, ok, detalle)
  values (p_familia, p_caso, coalesce(p_ok, false), p_detalle);
$$;

/**
 * Cuenta filas visibles de una tabla o vista con un filtro.
 *
 * Va por `execute` porque el nombre de la vista es un parametro: la gracia de
 * la prueba de lectura es recorrer TODAS las vistas con el mismo caso, y sin
 * esto habria que copiar el bloque una vez por vista — que es justo como se
 * acaba olvidando una.
 */
create or replace function pr_cuantas(p_rel text, p_donde text)
returns bigint language plpgsql as $$
declare n bigint;
begin
  execute format('select count(*) from %I where %s', p_rel, p_donde) into n;
  return n;
end $$;

-- ============================================================
--  EL ESCENARIO
--
--  Dos grupos que no se conocen de nada, con gente y rolls en los dos. Se
--  monta como `postgres` a proposito: aqui la RLS estorba, y lo que se prueba
--  viene despues.
-- ============================================================
do $$
declare
  ua uuid := 'aaaa1111-0000-0000-0000-00000000a001';   -- A1, grupo A
  ub uuid := 'aaaa1111-0000-0000-0000-00000000a002';   -- A2, grupo A
  uc uuid := 'bbbb1111-0000-0000-0000-00000000b001';   -- B1, grupo B
  ud uuid := 'bbbb1111-0000-0000-0000-00000000b002';   -- B2, grupo B
  ue uuid := 'eeee1111-0000-0000-0000-00000000e001';   -- E, invitado externo
begin
  insert into auth.users (id, email) values
    (ua, 'rls-a1@test'), (ub, 'rls-a2@test'),
    (uc, 'rls-b1@test'), (ud, 'rls-b2@test'), (ue, 'rls-ext@test');

  -- El trigger `bjj_08` crea una ficha por cada alta. Se borran y se ponen las
  -- nuestras, con nombres que se reconocen al leer un fallo.
  delete from practicantes where user_id in (ua, ub, uc, ud, ue);

  insert into practicantes (id, nombre, cinturon, academia, usa_sistema, user_id) values
    ('a0000000-0000-4000-8000-000000000001', 'RLS-A1', 'azul',   'RLS', true, ua),
    ('a0000000-0000-4000-8000-000000000002', 'RLS-A2', 'morada', 'RLS', true, ub),
    ('b0000000-0000-4000-8000-000000000001', 'RLS-B1', 'marron', 'RLS', true, uc),
    ('b0000000-0000-4000-8000-000000000002', 'RLS-B2', 'negra',  'RLS', true, ud),
    ('e0000000-0000-4000-8000-000000000001', 'RLS-Ext','blanca', 'RLS', true, ue);

  -- Dos contactos sin cuenta: uno creado por A1 y otro por A2. Es lo que
  -- distingue "puedo editar lo que di de alta" de "puedo editar lo de todos".
  insert into practicantes (id, nombre, cinturon, academia, usa_sistema, creado_por) values
    ('c0000000-0000-4000-8000-000000000001', 'RLS-Contacto-de-A1', 'blanca', 'RLS', false, ua),
    ('c0000000-0000-4000-8000-000000000002', 'RLS-Contacto-de-A2', 'blanca', 'RLS', false, ub);

  insert into grupos (id, nombre, slug, codigo_union) values
    ('a0000000-0000-4000-9000-00000000000a', 'RLS Tatami A', 'rls-tatami-a', 'RLSAAA-001'),
    ('b0000000-0000-4000-9000-00000000000b', 'RLS Tatami B', 'rls-tatami-b', 'RLSBBB-002');

  insert into miembros_grupo (grupo_id, practicante_id, rol) values
    ('a0000000-0000-4000-9000-00000000000a', 'a0000000-0000-4000-8000-000000000001', 'admin'),
    ('a0000000-0000-4000-9000-00000000000a', 'a0000000-0000-4000-8000-000000000002', 'miembro'),
    ('a0000000-0000-4000-9000-00000000000a', 'c0000000-0000-4000-8000-000000000001', 'miembro'),
    ('a0000000-0000-4000-9000-00000000000a', 'c0000000-0000-4000-8000-000000000002', 'miembro'),
    ('b0000000-0000-4000-9000-00000000000b', 'b0000000-0000-4000-8000-000000000001', 'admin'),
    ('b0000000-0000-4000-9000-00000000000b', 'b0000000-0000-4000-8000-000000000002', 'miembro');

  -- Un roll con eventos para A1, A2 y B1. Con sumision completada, para que
  -- las vistas de heatmap y head-to-head tengan de que tirar.
  insert into sesiones (id, practicante_id, fecha, modalidad, tipo, grupo_id) values
    ('a0000000-0000-4000-a000-000000000001', 'a0000000-0000-4000-8000-000000000001',
     current_date, 'gi', 'sparring', 'a0000000-0000-4000-9000-00000000000a'),
    ('a0000000-0000-4000-a000-000000000002', 'a0000000-0000-4000-8000-000000000002',
     current_date, 'gi', 'sparring', 'a0000000-0000-4000-9000-00000000000a'),
    ('b0000000-0000-4000-a000-000000000001', 'b0000000-0000-4000-8000-000000000001',
     current_date, 'gi', 'sparring', 'b0000000-0000-4000-9000-00000000000b');

  insert into rolls (id, sesion_id, oponente_id, orden, modalidad, posicion_inicio,
                     rol_inicio, resultado, origen) values
    ('a0000000-0000-4000-b000-000000000001', 'a0000000-0000-4000-a000-000000000001',
     'a0000000-0000-4000-8000-000000000002', 1, 'gi', 'de_pie', 'neutral',
     'sumision_favor', 'propio'),
    ('a0000000-0000-4000-b000-000000000002', 'a0000000-0000-4000-a000-000000000002',
     'a0000000-0000-4000-8000-000000000001', 1, 'gi', 'de_pie', 'neutral',
     'sumision_contra', 'propio'),
    ('b0000000-0000-4000-b000-000000000001', 'b0000000-0000-4000-a000-000000000001',
     'b0000000-0000-4000-8000-000000000002', 1, 'gi', 'de_pie', 'neutral',
     'sumision_favor', 'propio');

  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, completado,
                       segundo_roll, tecnica_id)
  select r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 90,
         (select id from tecnicas where slug = 'mata_leao')
    from unnest(array['a0000000-0000-4000-b000-000000000001'::uuid,
                      'a0000000-0000-4000-b000-000000000002'::uuid,
                      'b0000000-0000-4000-b000-000000000001'::uuid]) r;

  -- Una quedada del grupo A con UNA plaza, y el externo apuntado.
  insert into quedadas (id, grupo_id, titulo, fecha, lugar, plazas_max,
                        admite_externos, creado_por) values
    ('a0000000-0000-4000-c000-000000000001', 'a0000000-0000-4000-9000-00000000000a',
     'RLS Open Mat', current_date + 1, 'RLS', 1, true,
     'a0000000-0000-4000-8000-000000000001');
  insert into inscripciones (quedada_id, practicante_id, estado, es_externo) values
    ('a0000000-0000-4000-c000-000000000001', 'e0000000-0000-4000-8000-000000000001',
     'apuntado', true);

  -- El token se guarda AHORA, mientras somos postgres. Leerlo despues, ya
  -- metidos en la piel del invitado, devuelve null —porque justamente no puede
  -- leer `quedadas`— y la funcion se llamaria con null: el caso fallaria por el
  -- test y no por el producto. Me paso al escribirlo.
  perform set_config('rls.token',
    (select token_invitacion from quedadas
      where id = 'a0000000-0000-4000-c000-000000000001'), true);
end $$;

-- Ids que se repiten en todo el fichero. Se dejan como constantes de psql para
-- que los casos se lean y no haya que descifrar uuids.
\set A1   '''a0000000-0000-4000-8000-000000000001'''
\set A2   '''a0000000-0000-4000-8000-000000000002'''
\set B1   '''b0000000-0000-4000-8000-000000000001'''
\set CA1  '''c0000000-0000-4000-8000-000000000001'''
\set CA2  '''c0000000-0000-4000-8000-000000000002'''
\set EXT  '''e0000000-0000-4000-8000-000000000001'''
\set UA1  '''aaaa1111-0000-0000-0000-00000000a001'''
\set UB1  '''bbbb1111-0000-0000-0000-00000000b001'''
\set UEXT '''eeee1111-0000-0000-0000-00000000e001'''
\set SESA1 '''a0000000-0000-4000-a000-000000000001'''
\set SESA2 '''a0000000-0000-4000-a000-000000000002'''
\set ROLLA1 '''a0000000-0000-4000-b000-000000000001'''
\set ROLLA2 '''a0000000-0000-4000-b000-000000000002'''
\set GRUPOA '''a0000000-0000-4000-9000-00000000000a'''
\set QUEDADA '''a0000000-0000-4000-c000-000000000001'''

-- ============================================================
--  1 · LECTURA
-- ============================================================
select pr_es(:UA1);

select pr_caso('lectura', 'A1 ve sus propias sesiones',
  (select count(*) from sesiones where practicante_id = :A1) > 0);
select pr_caso('lectura', 'A1 ve sus propios rolls',
  (select count(*) from rolls where sesion_id = :SESA1) > 0);
select pr_caso('lectura', 'A1 ve sus propios eventos',
  (select count(*) from eventos where roll_id = :ROLLA1) > 0);

-- Lo que hace posible el selector de practicante del analisis.
select pr_caso('lectura', 'A1 ve las sesiones de A2, del mismo grupo',
  (select count(*) from sesiones where practicante_id = :A2) > 0);
select pr_caso('lectura', 'A1 ve los rolls de A2',
  (select count(*) from rolls where sesion_id = :SESA2) > 0);
select pr_caso('lectura', 'A1 ve los eventos de A2',
  (select count(*) from eventos where roll_id = :ROLLA2) > 0);

-- Y la frontera. Cero, no "pocos".
select pr_caso('lectura', 'A1 NO ve sesiones del grupo B',
  (select count(*) from sesiones where practicante_id = :B1) = 0,
  (select count(*)::text || ' filas' from sesiones where practicante_id = :B1));
select pr_caso('lectura', 'A1 NO ve rolls del grupo B',
  (select count(*) from rolls r join sesiones s on s.id = r.sesion_id
    where s.practicante_id = :B1) = 0);
select pr_caso('lectura', 'A1 NO ve eventos del grupo B',
  (select count(*) from eventos e join rolls r on r.id = e.roll_id
    join sesiones s on s.id = r.sesion_id where s.practicante_id = :B1) = 0);

-- LAS VISTAS. Es por donde se escapa esto si a alguna le falta
-- `security_invoker`: la tabla queda tapada y la vista la enseña igual.
select pr_caso('lectura', 'A1 NO ve al grupo B por v_eventos',
  (select count(*) from v_eventos where autor_id = :B1) = 0,
  (select count(*)::text || ' filas' from v_eventos where autor_id = :B1));
select pr_caso('lectura', 'A1 NO ve al grupo B por v_heatmap_ofensivo',
  (select count(*) from v_heatmap_ofensivo where autor_id = :B1) = 0);
select pr_caso('lectura', 'A1 NO ve al grupo B por v_h2h',
  (select count(*) from v_h2h where autor_id = :B1) = 0);
select pr_caso('lectura', 'A1 NO ve al grupo B por v_puntos_roll',
  (select count(*) from v_puntos_roll where autor_id = :B1) = 0);
select pr_caso('lectura', 'A1 NO ve al grupo B por v_feed',
  (select count(*) from v_feed where grupo_id = 'b0000000-0000-4000-9000-00000000000b') = 0);
select pr_caso('lectura', 'A1 NO ve al grupo B por v_logros_practicante',
  (select count(*) from v_logros_practicante where practicante_id = :B1) = 0);

-- El catalogo si es de todos: sin el no hay vocabulario ni coleccion.
select pr_caso('lectura', 'un autenticado lee el catalogo de posiciones',
  (select count(*) from posiciones) > 0);
select pr_caso('lectura', 'un autenticado lee el catalogo de tecnicas',
  (select count(*) from tecnicas) > 0);

select pr_admin();

-- ---------- anon: la puerta de la calle ----------
select pr_anon();
select pr_caso('lectura', 'anon NO ve sesiones',
  (select count(*) from sesiones) = 0,
  (select count(*)::text || ' filas' from sesiones));
select pr_caso('lectura', 'anon NO ve rolls', (select count(*) from rolls) = 0);
select pr_caso('lectura', 'anon NO ve eventos', (select count(*) from eventos) = 0);
select pr_caso('lectura', 'anon NO ve practicantes', (select count(*) from practicantes) = 0);
select pr_caso('lectura', 'anon NO ve grupos', (select count(*) from grupos) = 0);
select pr_admin();

-- ============================================================
--  2 · ESCRITURA
--
--  Ojo al criterio, que no es el mismo para todo: un INSERT que rompe el
--  `with check` LANZA 42501, pero un UPDATE o un DELETE que no casa con el
--  `using` simplemente afecta a CERO filas, sin error. Confundirlos es la
--  forma facil de escribir un test que siempre pasa.
-- ============================================================
select pr_es(:UA1);

do $$
declare n int;
begin
  -- Insertar lo mio: tiene que dejarme.
  begin
    insert into sesiones (practicante_id, fecha, modalidad, tipo)
    values ('a0000000-0000-4000-8000-000000000001', current_date, 'gi', 'sparring');
    perform pr_caso('escritura', 'A1 inserta una sesion suya', true);
  exception when others then
    perform pr_caso('escritura', 'A1 inserta una sesion suya', false, sqlerrm);
  end;

  -- A nombre de otro: no.
  begin
    insert into sesiones (practicante_id, fecha, modalidad, tipo)
    values ('a0000000-0000-4000-8000-000000000002', current_date, 'gi', 'sparring');
    perform pr_caso('escritura', 'A1 NO inserta una sesion a nombre de A2', false,
                    'la dejo pasar');
  exception when insufficient_privilege then
    perform pr_caso('escritura', 'A1 NO inserta una sesion a nombre de A2', true);
  end;

  -- Borrar lo mio.
  delete from rolls where id = 'a0000000-0000-4000-b000-000000000001';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 borra un roll suyo', n = 1, n || ' filas');

  -- ---------- EL CASO MAS IMPORTANTE DE TODA LA BATERIA ----------
  -- `bjj_13` y `bjj_15` abrieron la LECTURA a los del grupo. Si de paso se
  -- hubiera colado la escritura, cualquiera podria editar o borrar los rolls
  -- de un compañero y la app estaria rota sin que nadie lo notara: no da
  -- error, simplemente desaparecen datos ajenos.
  update sesiones set notas = 'tocado por A1'
   where practicante_id = 'a0000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO edita las sesiones de A2 (mismo grupo)',
                  n = 0, n || ' filas tocadas');

  delete from rolls where sesion_id = 'a0000000-0000-4000-a000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO borra los rolls de A2 (mismo grupo)',
                  n = 0, n || ' filas borradas');

  delete from eventos where roll_id = 'a0000000-0000-4000-b000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO borra los eventos de A2 (mismo grupo)',
                  n = 0, n || ' filas borradas');

  update rolls set notas = 'tocado por A1'
   where sesion_id = 'a0000000-0000-4000-a000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO edita los rolls de A2 (mismo grupo)',
                  n = 0, n || ' filas tocadas');

  -- ---------- Fichas ----------
  update practicantes set apodo = 'yo mismo'
   where id = 'a0000000-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 edita su propia ficha', n = 1, n || ' filas');

  update practicantes set apodo = 'mi contacto'
   where id = 'c0000000-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 edita el contacto que dio de alta', n = 1, n || ' filas');

  update practicantes set apodo = 'no deberia'
   where id = 'a0000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO edita la ficha de A2, que tiene cuenta',
                  n = 0, n || ' filas tocadas');

  update practicantes set apodo = 'no deberia'
   where id = 'c0000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO edita el contacto que dio de alta A2',
                  n = 0, n || ' filas tocadas');
end $$;

select pr_admin();

-- ============================================================
--  3 · LAS FUNCIONES QUE SE SALTAN LA RLS A PROPOSITO
--
--  `registrar_roll_observado` es SECURITY DEFINER porque tiene que serlo: la
--  RLS impide que un tercero escriba las sesiones de otros, y el modo
--  observador consiste exactamente en eso. Lo que hay que comprobar es que la
--  puerta tenga cerradura.
-- ============================================================
select pr_es(:UA1);

do $$
declare v jsonb; n int;
begin
  -- Funciona para un autenticado con ficha.
  begin
    v := registrar_roll_observado(
      '11111111-2222-3333-4444-555555555555'::uuid,
      'a0000000-0000-4000-8000-000000000001'::uuid,
      'a0000000-0000-4000-8000-000000000002'::uuid,
      current_date, 'gi', 6::smallint, 'de_pie', 'neutral', 'sumision_favor',
      '[{"actor":"yo","tipo":"sumision","posicion":"montada","rol":"arriba",
         "objetivo":"cuello","tecnica_slug":"mata_leao","completado":true,
         "segundo_roll":80}]'::jsonb);
    perform pr_caso('rpc', 'registrar_roll_observado funciona con ficha',
                    v ? 'roll_a', v::text);
  exception when others then
    perform pr_caso('rpc', 'registrar_roll_observado funciona con ficha', false, sqlerrm);
  end;

  -- Y es IDEMPOTENTE. Sin esto, reintentar tras perder cobertura duplica el
  -- roll de dos personas — que es justo lo que hace la cola de salida.
  begin
    v := registrar_roll_observado(
      '11111111-2222-3333-4444-555555555555'::uuid,
      'a0000000-0000-4000-8000-000000000001'::uuid,
      'a0000000-0000-4000-8000-000000000002'::uuid,
      current_date, 'gi', 6::smallint, 'de_pie', 'neutral', 'sumision_favor',
      '[{"actor":"yo","tipo":"sumision","posicion":"montada","rol":"arriba",
         "objetivo":"cuello","tecnica_slug":"mata_leao","completado":true,
         "segundo_roll":80}]'::jsonb);
  exception when others then null;
  end;
  select count(*) into n from rolls
   where roll_grupo_id = '11111111-2222-3333-4444-555555555555';
  perform pr_caso('rpc', 'registrar_roll_observado es idempotente',
                  n = 2, n || ' rolls (esperados 2: uno por persona)');
end $$;

select pr_admin();

-- Un autenticado SIN ficha de practicante no puede registrar nada.
do $$
declare v jsonb; u uuid := 'ffff1111-0000-0000-0000-00000000f001';
begin
  insert into auth.users (id, email) values (u, 'rls-sinficha@test');
  delete from practicantes where user_id = u;      -- la que crea el trigger
  perform pr_es(u);
  begin
    v := registrar_roll_observado(
      '22222222-3333-4444-5555-666666666666'::uuid,
      'a0000000-0000-4000-8000-000000000001'::uuid,
      'a0000000-0000-4000-8000-000000000002'::uuid,
      current_date, 'gi', 6::smallint, 'de_pie', 'neutral', 'sumision_favor',
      '[]'::jsonb);
    perform pr_caso('rpc', 'registrar_roll_observado falla sin ficha', false,
                    'lo dejo pasar');
  exception when others then
    perform pr_caso('rpc', 'registrar_roll_observado falla sin ficha', true, sqlerrm);
  end;
  perform pr_admin();
end $$;

-- ---------- unirse_con_codigo ----------
do $$
declare n int;
begin
  perform pr_es('bbbb1111-0000-0000-0000-00000000b001');   -- B1, que no esta en A
  begin
    perform unirse_con_codigo('NO-EXISTE-99');
    perform pr_caso('rpc', 'unirse_con_codigo falla con un codigo inventado',
                    false, 'lo dejo pasar');
  exception when others then
    perform pr_caso('rpc', 'unirse_con_codigo falla con un codigo inventado', true);
  end;

  -- Dos veces con el bueno: una sola membresia.
  begin
    perform unirse_con_codigo('RLSAAA-001');
    perform unirse_con_codigo('RLSAAA-001');
  exception when others then null;
  end;
  select count(*) into n from miembros_grupo
   where grupo_id = 'a0000000-0000-4000-9000-00000000000a'
     and practicante_id = 'b0000000-0000-4000-8000-000000000001';
  perform pr_caso('rpc', 'unirse_con_codigo dos veces no duplica la membresia',
                  n = 1, n || ' membresias');
  perform pr_admin();
end $$;

-- ---------- apuntarse_a_quedada y las plazas ----------
do $$
declare apuntados int; espera int;
begin
  -- La quedada tiene UNA plaza y el externo ya la ocupa. A2 y B2 llegan
  -- despues: uno se queda fuera, y el orden lo decide el cerrojo, no la suerte.
  perform pr_es('aaaa1111-0000-0000-0000-00000000a002');
  begin perform apuntarse_a_quedada('a0000000-0000-4000-c000-000000000001', null);
  exception when others then null; end;
  perform pr_admin();

  perform pr_es('bbbb1111-0000-0000-0000-00000000b002');
  begin perform apuntarse_a_quedada('a0000000-0000-4000-c000-000000000001', null);
  exception when others then null; end;
  perform pr_admin();

  select count(*) filter (where estado = 'apuntado'),
         count(*) filter (where estado = 'lista_espera')
    into apuntados, espera
    from inscripciones where quedada_id = 'a0000000-0000-4000-c000-000000000001';
  perform pr_caso('rpc', 'apuntarse_a_quedada respeta la plaza unica',
                  apuntados = 1 and espera >= 1,
                  apuntados || ' apuntados, ' || espera || ' en lista de espera');
end $$;

-- ---------- Que anon no pueda llamar a ninguna ----------
--
-- Se lee del CATALOGO y no de memoria: los permisos se conceden de una en una,
-- y la que se olvida es siempre la ultima que se añadio.
--
-- Se mira tambien `PUBLIC`, y eso no es celo de mas: un `grant execute ... to
-- public` no aparece con `grantee = 'anon'` en ninguna parte, y le abre la
-- funcion a anon exactamente igual. Buscar solo 'anon' daria un verde falso.
--
-- El join va por el oid que `specific_name` lleva pegado al final
-- (`nombre_12345`), porque ese nombre no es un `regprocedure` y no se puede
-- castear.
create or replace view rls_secdef_para_anon as
select distinct rp.routine_name
  from information_schema.routine_privileges rp
  join pg_proc p on p.oid = split_part(rp.specific_name, '_', -1)::oid
 where rp.privilege_type = 'EXECUTE'
   and rp.specific_schema = 'public'
   and rp.grantee in ('anon', 'PUBLIC')
   and p.prosecdef;

select pr_caso('rpc', 'ninguna funcion SECURITY DEFINER es ejecutable por anon',
  (select count(*) from rls_secdef_para_anon) = 0,
  coalesce((select string_agg(routine_name, ', ') from rls_secdef_para_anon),
           'ninguna'));

-- ============================================================
--  4 · EL INVITADO EXTERNO
--
--  Alguien de otro gimnasio apuntado a una quedada. Tiene que poder ver el
--  plan al que va, y NADA mas: si de paso ve el feed o los rolls del grupo,
--  invitar a alguien a un open mat le abre el historial de la academia.
-- ============================================================
select pr_es(:UEXT);

-- Este caso FALLA hoy, y se deja fallando a proposito. `quedadas_lectura_grupo`
-- solo deja ver las quedadas de TUS grupos, y un invitado externo no es miembro
-- de ninguno. En la app se apaña por el otro lado —con el enlace de invitacion,
-- que pasa por `quedada_por_token()` y es SECURITY DEFINER—, asi que no es un
-- agujero de seguridad: es que sin el enlace a mano no vuelve a encontrar el
-- plan al que dijo que iba. Lo decide Felipe: o se abre la lectura a quien
-- tenga inscripcion, o se asume que el enlace es la unica puerta.
select pr_caso('externo', 'el invitado ve la quedada a la que esta apuntado',
  (select count(*) from quedadas where id = :QUEDADA) > 0,
  'la politica va por grupo y el invitado no es miembro de ninguno');

-- Y la puerta que si funciona, para que quede claro que la de arriba es una
-- carencia de producto y no una fuga.
select pr_caso('externo', 'pero si la ve con el enlace de invitacion',
  (select count(*) from quedada_por_token(current_setting('rls.token'))) > 0);
select pr_caso('externo', 'el invitado NO ve el feed del grupo',
  (select count(*) from v_feed where grupo_id = :GRUPOA) = 0,
  (select count(*)::text || ' filas' from v_feed where grupo_id = :GRUPOA));
select pr_caso('externo', 'el invitado NO ve los rolls de los del grupo',
  (select count(*) from rolls r join sesiones s on s.id = r.sesion_id
    where s.practicante_id = :A1) = 0);
select pr_caso('externo', 'el invitado NO ve las sesiones de los del grupo',
  (select count(*) from sesiones where practicante_id = :A1) = 0);

select pr_admin();

-- ============================================================
--  EL RESUMEN
-- ============================================================
\echo ''
select lpad(n::text, 3) || '  ' || case when ok then 'ok   ' else 'FALLO' end
       || '  [' || rpad(familia, 9) || '] ' || caso
       || case when detalle <> '' and not ok then '  → ' || detalle else '' end
  from rls_res order by n;

\echo ''
do $$
declare v_total int; v_mal int; f record;
begin
  select count(*), count(*) filter (where not ok) into v_total, v_mal from rls_res;
  if v_mal = 0 then
    raise notice '######## RLS: % casos, todos pasan ########', v_total;
  else
    raise notice '######## RLS: % de % casos FALLAN ########', v_mal, v_total;
    for f in select familia, caso, detalle from rls_res where not ok order by n loop
      raise notice '  FALLA [%] %  %', f.familia, f.caso, f.detalle;
    end loop;
    -- La excepcion hace dos cosas a la vez: deshace la transaccion, que es lo
    -- que queremos igualmente, y le da a psql un codigo de salida distinto de
    -- cero para que esto se pueda meter en CI tal cual.
    raise exception 'La bateria de RLS tiene % casos en rojo', v_mal;
  end if;
end $$;

rollback;
