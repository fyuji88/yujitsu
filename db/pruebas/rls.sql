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

/**
 * ¿`anon` tiene tapada esta tabla?
 *
 * "Tapada" puede ser dos cosas y las dos valen: que no haya `grant` —y salta
 * 42501— o que lo haya pero ninguna politica le deje ver nada. Un `count(*)`
 * pelado solo cubre la segunda, y en la primera revienta la transaccion.
 */
create or replace function pr_tapado(p_rel text) returns boolean
language plpgsql as $$
declare n bigint;
begin
  execute format('select count(*) from %I', p_rel) into n;
  return n = 0;
exception when insufficient_privilege then
  return true;
end $$;

create or replace function pr_por_que(p_rel text) returns text
language plpgsql as $$
declare n bigint;
begin
  execute format('select count(*) from %I', p_rel) into n;
  return n || ' filas visibles';
exception when insufficient_privilege then
  return 'sin permiso, ni llega a la politica';
end $$;

-- ============================================================
--  EL ESCENARIO
--
--  Dos equipos que no se conocen de nada, con gente y rolls en los dos. Se
--  monta como `postgres` a proposito: aqui la RLS estorba, y lo que se prueba
--  viene despues.
-- ============================================================
do $$
declare
  ua uuid := 'aaaa1111-0000-0000-0000-00000000a001';   -- A1, equipo A
  ub uuid := 'aaaa1111-0000-0000-0000-00000000a002';   -- A2, equipo A
  uc uuid := 'bbbb1111-0000-0000-0000-00000000b001';   -- B1, equipo B
  ud uuid := 'bbbb1111-0000-0000-0000-00000000b002';   -- B2, equipo B
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

  insert into equipos (id, nombre, slug, codigo_union) values
    ('a0000000-0000-4000-9000-00000000000a', 'RLS Tatami A', 'rls-tatami-a', 'RLSAAA-001'),
    ('b0000000-0000-4000-9000-00000000000b', 'RLS Tatami B', 'rls-tatami-b', 'RLSBBB-002');

  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo) values
    ('a0000000-0000-4000-9000-00000000000a', 'a0000000-0000-4000-8000-000000000001', 'admin'),
    ('a0000000-0000-4000-9000-00000000000a', 'a0000000-0000-4000-8000-000000000002', 'miembro'),
    ('a0000000-0000-4000-9000-00000000000a', 'c0000000-0000-4000-8000-000000000001', 'miembro'),
    ('a0000000-0000-4000-9000-00000000000a', 'c0000000-0000-4000-8000-000000000002', 'miembro'),
    ('b0000000-0000-4000-9000-00000000000b', 'b0000000-0000-4000-8000-000000000001', 'admin'),
    ('b0000000-0000-4000-9000-00000000000b', 'b0000000-0000-4000-8000-000000000002', 'miembro');

  -- Un roll con eventos para A1, A2 y B1. Con sumision completada, para que
  -- las vistas de heatmap y head-to-head tengan de que tirar.
  insert into sesiones (id, practicante_id, fecha, modalidad, formato, equipo_id) values
    ('a0000000-0000-4000-a000-000000000001', 'a0000000-0000-4000-8000-000000000001',
     current_date, 'gi', 'sparring', 'a0000000-0000-4000-9000-00000000000a'),
    ('a0000000-0000-4000-a000-000000000002', 'a0000000-0000-4000-8000-000000000002',
     current_date, 'gi', 'sparring', 'a0000000-0000-4000-9000-00000000000a'),
    ('b0000000-0000-4000-a000-000000000001', 'b0000000-0000-4000-8000-000000000001',
     current_date, 'gi', 'sparring', 'b0000000-0000-4000-9000-00000000000b');

  insert into rolls (id, sesion_id, oponente_id, orden_en_sesion, modalidad, posicion_inicio,
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

  -- Una quedada del equipo A con UNA plaza, y el externo apuntado.
  insert into quedadas (id, equipo_id, titulo, fecha, lugar, plazas_max,
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
select pr_caso('lectura', 'A1 ve las sesiones de A2, del mismo equipo',
  (select count(*) from sesiones where practicante_id = :A2) > 0);
select pr_caso('lectura', 'A1 ve los rolls de A2',
  (select count(*) from rolls where sesion_id = :SESA2) > 0);
select pr_caso('lectura', 'A1 ve los eventos de A2',
  (select count(*) from eventos where roll_id = :ROLLA2) > 0);

-- Y la frontera. Cero, no "pocos".
select pr_caso('lectura', 'A1 NO ve sesiones del equipo B',
  (select count(*) from sesiones where practicante_id = :B1) = 0,
  (select count(*)::text || ' filas' from sesiones where practicante_id = :B1));
select pr_caso('lectura', 'A1 NO ve rolls del equipo B',
  (select count(*) from rolls r join sesiones s on s.id = r.sesion_id
    where s.practicante_id = :B1) = 0);
select pr_caso('lectura', 'A1 NO ve eventos del equipo B',
  (select count(*) from eventos e join rolls r on r.id = e.roll_id
    join sesiones s on s.id = r.sesion_id where s.practicante_id = :B1) = 0);

-- LAS VISTAS. Es por donde se escapa esto si a alguna le falta
-- `security_invoker`: la tabla queda tapada y la vista la enseña igual.
select pr_caso('lectura', 'A1 NO ve al equipo B por v_eventos',
  (select count(*) from v_eventos where autor_id = :B1) = 0,
  (select count(*)::text || ' filas' from v_eventos where autor_id = :B1));
select pr_caso('lectura', 'A1 NO ve al equipo B por v_heatmap_ofensivo',
  (select count(*) from v_heatmap_ofensivo where autor_id = :B1) = 0);
select pr_caso('lectura', 'A1 NO ve al equipo B por v_h2h',
  (select count(*) from v_h2h where autor_id = :B1) = 0);
select pr_caso('lectura', 'A1 NO ve al equipo B por v_puntos_roll',
  (select count(*) from v_puntos_roll where autor_id = :B1) = 0);
select pr_caso('lectura', 'A1 NO ve al equipo B por v_feed',
  (select count(*) from v_feed where equipo_id = 'b0000000-0000-4000-9000-00000000000b') = 0);
select pr_caso('lectura', 'A1 NO ve al equipo B por v_logros_practicante',
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
  pr_tapado('sesiones'), pr_por_que('sesiones'));
select pr_caso('lectura', 'anon NO ve rolls',
  pr_tapado('rolls'), pr_por_que('rolls'));
select pr_caso('lectura', 'anon NO ve eventos',
  pr_tapado('eventos'), pr_por_que('eventos'));
-- Los tres que estaban en `USING (true)` para `public` hasta `bjj_22`. Ahora
-- ni siquiera hay `grant`, asi que salta 42501 antes de mirar politica alguna:
-- por eso se comprueban con captura de excepcion y no con un `count(*)` pelado.
select pr_caso('lectura', 'anon NO ve practicantes',
  pr_tapado('practicantes'), pr_por_que('practicantes'));
select pr_caso('lectura', 'anon NO ve retos',
  pr_tapado('retos'), pr_por_que('retos'));
select pr_caso('lectura', 'anon NO ve reto_participaciones (progreso por persona)',
  pr_tapado('reto_participaciones'), pr_por_que('reto_participaciones'));
-- El diccionario tambien queda tapado para `anon` desde `bjj_25`, y conviene
-- explicar por que no contradice al "posiciones y tecnicas se quedan abiertas":
-- lo que se queda abierto es su POLITICA, que sigue siendo permisiva y sin
-- recortar por equipo. Lo que desaparece es el GRANT, y `anon` no lo necesita
-- porque la app solo lee el diccionario ya dentro de `<Marco>`, con sesion.
-- Si algun dia hiciera falta el vocabulario antes del login, se le concede
-- `select` a esas dos y a nada mas.
select pr_caso('lectura', 'anon tampoco ve el diccionario (posiciones)',
  pr_tapado('posiciones'), pr_por_que('posiciones'));
select pr_caso('lectura', 'ni tecnicas', pr_tapado('tecnicas'));
select pr_admin();

-- ---------- Y LA REGLA QUE LO FIJA (bjj_25) ----------
--
-- `anon` no tiene NINGUN privilegio sobre tablas ni vistas. Este caso es el
-- que impide que esto se vuelva a colar dentro de tres migraciones: el
-- problema nunca fue la lista de hoy, era el DEFECTO — `pg_default_acl`
-- concedia todo sobre cada tabla nueva, asi que bastaba crear una y olvidarse
-- del `enable row level security` para publicarla entera.
--
-- Se mira `PUBLIC` ademas de `anon`: un `grant ... to public` no aparece como
-- 'anon' en ningun sitio y le llega igual. Esa trampa ya costo siete funciones.
--
-- Se excluye el andamiaje de esta misma bateria —la tabla `rls_res` y las
-- funciones `pr_*`—, que se crea dentro de la transaccion y muere con ella. No
-- es parte de la app y contarlo daria un rojo permanente por mirarse al espejo.
select pr_caso('permisos', 'anon no tiene NINGUN privilegio de tabla ni vista',
  (select count(*) from information_schema.table_privileges
    where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
      and table_name not like 'rls\_%') = 0,
  coalesce((select string_agg(distinct table_name || ' (' || grantee || ')', ', ')
     from information_schema.table_privileges
    where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
      and table_name not like 'rls\_%'), 'ninguno'));

-- Y ninguna funcion, tampoco por herencia.
select pr_caso('permisos', 'anon no puede ejecutar NINGUNA funcion',
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname not like 'pr\_%'
      and has_function_privilege('anon', p.oid, 'EXECUTE')) = 0,
  coalesce((select string_agg(p.proname, ', ') from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname not like 'pr\_%'
       and has_function_privilege('anon', p.oid, 'EXECUTE')), 'ninguna'));

-- El defecto, que es el arreglo de verdad: una tabla nueva NO nace abierta.
-- Se comprueba creandola, que es la unica forma de saberlo sin fiarse.
do $$
declare abierta boolean;
begin
  create table zzz_defecto_rls (id int);
  select exists (select 1 from information_schema.table_privileges
                  where table_name = 'zzz_defecto_rls' and grantee in ('anon','PUBLIC'))
    into abierta;
  perform pr_caso('permisos', 'una tabla NUEVA no nace abierta a anon',
                  not abierta,
                  case when abierta then 'nace con privilegios: el default_acl sigue mal'
                       else '' end);
  -- Y que a `authenticated` si le siga llegando, o habriamos roto la app.
  perform pr_caso('permisos', 'pero authenticated si la recibe, como debe',
    exists (select 1 from information_schema.table_privileges
             where table_name = 'zzz_defecto_rls' and grantee = 'authenticated'));
  drop table zzz_defecto_rls;
end $$;

-- Se vuelve a anon para lo que queda de esta familia.
select pr_anon();
select pr_caso('lectura', 'anon NO ve equipos',
  pr_tapado('equipos'), pr_por_que('equipos'));
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
    insert into sesiones (practicante_id, fecha, modalidad, formato)
    values ('a0000000-0000-4000-8000-000000000001', current_date, 'gi', 'sparring');
    perform pr_caso('escritura', 'A1 inserta una sesion suya', true);
  exception when others then
    perform pr_caso('escritura', 'A1 inserta una sesion suya', false, sqlerrm);
  end;

  -- A nombre de otro: no.
  begin
    insert into sesiones (practicante_id, fecha, modalidad, formato)
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
  -- `bjj_13` y `bjj_15` abrieron la LECTURA a los del equipo. Si de paso se
  -- hubiera colado la escritura, cualquiera podria editar o borrar los rolls
  -- de un compañero y la app estaria rota sin que nadie lo notara: no da
  -- error, simplemente desaparecen datos ajenos.
  update sesiones set notas = 'tocado por A1'
   where practicante_id = 'a0000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO edita las sesiones de A2 (mismo equipo)',
                  n = 0, n || ' filas tocadas');

  delete from rolls where sesion_id = 'a0000000-0000-4000-a000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO borra los rolls de A2 (mismo equipo)',
                  n = 0, n || ' filas borradas');

  delete from eventos where roll_id = 'a0000000-0000-4000-b000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO borra los eventos de A2 (mismo equipo)',
                  n = 0, n || ' filas borradas');

  update rolls set notas = 'tocado por A1'
   where sesion_id = 'a0000000-0000-4000-a000-000000000002';
  get diagnostics n = row_count;
  perform pr_caso('escritura', 'A1 NO edita los rolls de A2 (mismo equipo)',
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
   where par_id = '11111111-2222-3333-4444-555555555555';
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
  select count(*) into n from miembros_equipo
   where equipo_id = 'a0000000-0000-4000-9000-00000000000a'
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
--  plan al que va, y NADA mas: si de paso ve el feed o los rolls del equipo,
--  invitar a alguien a un open mat le abre el historial de la academia.
-- ============================================================
select pr_es(:UEXT);

-- LA REGLA, desde `bjj_22`: una inscripcion da acceso A ESE EVENTO y a su
-- informe. Nada mas. Ni el feed, ni los datos de otros miembros, ni otras
-- quedadas. El acceso sigue al evento, no al equipo.
select pr_caso('externo', 'el invitado ve la quedada a la que esta apuntado',
  (select count(*) from quedadas where id = :QUEDADA) > 0);

-- Y la puerta que si funciona, para que quede claro que la de arriba es una
-- carencia de producto y no una fuga.
select pr_caso('externo', 'pero si la ve con el enlace de invitacion',
  (select count(*) from quedada_por_token(current_setting('rls.token'))) > 0);
select pr_caso('externo', 'el invitado NO ve el feed del equipo',
  (select count(*) from v_feed where equipo_id = :GRUPOA) = 0,
  (select count(*)::text || ' filas' from v_feed where equipo_id = :GRUPOA));
select pr_caso('externo', 'el invitado NO ve los rolls de los del equipo',
  (select count(*) from rolls r join sesiones s on s.id = r.sesion_id
    where s.practicante_id = :A1) = 0);
select pr_caso('externo', 'el invitado NO ve las sesiones de los del equipo',
  (select count(*) from sesiones where practicante_id = :A1) = 0);
select pr_caso('externo', 'el invitado NO ve OTRAS quedadas del equipo',
  (select count(*) from quedadas where equipo_id = :GRUPOA and id <> :QUEDADA) = 0);
select pr_caso('externo', 'el invitado NO ve el roster del equipo',
  (select count(*) from practicantes where id = :A2) = 0,
  've ' || (select count(*)::text from practicantes) || ' practicantes');

-- ============================================================
--  EL EQUIPO EQUIVOCADO  (bjj_32)
-- ============================================================
--
--  Ser admin no es un grado, es un grado EN UN EQUIPO. A1 lo es del A y no del
--  B, y estos tres son justo los que un `es_admin()` mal puesto —o llamado con
--  el equipo que no es— dejaria pasar. Los tres van juntos porque los tres se
--  arreglan igual y se rompen igual.
select pr_es(:UA1);

-- Editar la quedada de otro equipo. La politica es `quedadas_admin`, que exige
-- `es_admin(equipo_id)` de ESA quedada.
do $$
declare v_q uuid;
begin
  insert into quedadas (equipo_id, titulo, fecha, modalidad, creado_por)
  values ('b0000000-0000-4000-9000-00000000000b', 'Del equipo B',
          current_date + 2, 'nogi', 'b0000000-0000-4000-8000-000000000001')
  returning id into v_q;
  perform pr_caso('equipo', 'un admin de A NO puede crear en el equipo B', false,
                  'la creo, y no deberia');
exception when insufficient_privilege or check_violation then
  perform pr_caso('equipo', 'un admin de A NO puede crear en el equipo B', true);
end $$;

do $$
declare n int;
begin
  update quedadas set titulo = 'secuestrada'
   where equipo_id = 'b0000000-0000-4000-9000-00000000000b';
  get diagnostics n = row_count;
  perform pr_caso('equipo', 'un admin de A NO puede editar una quedada del B',
                  n = 0, 'edito ' || n || ' filas');
end $$;

-- Apuntar a alguien en la quedada de otro equipo. Aqui no manda la RLS sino la
-- comprobacion explicita de `apuntarse_a_quedada`, que es la unica via: un
-- insert directo se saltaria el reparto de plazas.
do $$
declare v_q uuid;
begin
  select id into v_q from quedadas
   where equipo_id = 'b0000000-0000-4000-9000-00000000000b' limit 1;
  if v_q is null then
    perform pr_caso('equipo', 'un admin de A NO puede apuntar a nadie en una quedada del B',
                    true, '(no hay quedada del B: caso no ejercido)');
  else
    begin
      perform apuntarse_a_quedada(v_q, null, 'a0000000-0000-4000-8000-000000000002');
      perform pr_caso('equipo', 'un admin de A NO puede apuntar a nadie en una quedada del B',
                      false, 'apunto a alguien, y no deberia');
    exception when insufficient_privilege then
      perform pr_caso('equipo', 'un admin de A NO puede apuntar a nadie en una quedada del B', true);
    end;
  end if;
end $$;

-- Enganchar una sesion TUYA al Open Mat de otro equipo. La guarda esta en
-- `enganchar_sesion_a_quedada`, no en una politica: sin ella cualquiera colgaria
-- su entreno del Open Mat de otro gimnasio y le ensuciaria el informe.
do $$
declare v_q uuid; v_s uuid;
begin
  select id into v_q from quedadas
   where equipo_id = 'b0000000-0000-4000-9000-00000000000b' limit 1;
  select id into v_s from sesiones
   where practicante_id = 'a0000000-0000-4000-8000-000000000001' limit 1;
  if v_q is null or v_s is null then
    perform pr_caso('equipo', 'un admin de A NO puede enganchar al Open Mat del B',
                    true, '(faltan datos: caso no ejercido)');
  else
    begin
      perform enganchar_sesion_a_quedada(v_s, v_q);
      perform pr_caso('equipo', 'un admin de A NO puede enganchar al Open Mat del B',
                      false, 'lo engancho, y no deberia');
    exception when insufficient_privilege or check_violation then
      perform pr_caso('equipo', 'un admin de A NO puede enganchar al Open Mat del B', true);
    end;
  end if;
end $$;

-- Y enganchar la sesion de OTRO que no has registrado tu.
do $$
declare v_q uuid; v_s uuid;
begin
  select id into v_q from quedadas
   where equipo_id = 'a0000000-0000-4000-9000-00000000000a' limit 1;
  select id into v_s from sesiones
   where practicante_id = 'a0000000-0000-4000-8000-000000000002' limit 1;
  if v_q is null or v_s is null then
    perform pr_caso('equipo', 'nadie engancha la sesion de otro que no registro',
                    true, '(faltan datos: caso no ejercido)');
  else
    begin
      perform enganchar_sesion_a_quedada(v_s, v_q);
      perform pr_caso('equipo', 'nadie engancha la sesion de otro que no registro',
                      false, 'la engancho, y no deberia');
    exception when insufficient_privilege or check_violation then
      perform pr_caso('equipo', 'nadie engancha la sesion de otro que no registro', true);
    end;
  end if;
end $$;

-- Meter gente en el equipo de otro. `miembros_alta_admin` exige es_admin.
do $$
begin
  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo)
  values ('b0000000-0000-4000-9000-00000000000b',
          'c0000000-0000-4000-8000-000000000001', 'miembro');
  perform pr_caso('equipo', 'un admin de A NO puede meter gente en el equipo B', false,
                  'lo metio, y no deberia');
exception when insufficient_privilege then
  perform pr_caso('equipo', 'un admin de A NO puede meter gente en el equipo B', true);
end $$;

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
