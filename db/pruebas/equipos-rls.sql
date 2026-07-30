-- ============================================================
--  FASE 2 · Las cuatro pruebas que hay que pasar antes de seguir
--
--    psql ... -f db/pruebas/equipos-rls.sql
--
--  Si la RLS queda mal, todo lo que se construya encima esta mal y no se nota
--  hasta que alguien ve datos que no deberia. Por eso esto va antes que las
--  quedadas, el informe y el feed.
--
--  Se prueba con `set local role authenticated` y el claim del usuario. Como
--  superusuario todo pasa y no significa nada.
-- ============================================================
\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- Preparacion: dos cuentas dentro del equipo por defecto y una fuera.
--
-- Se limpia lo de la pasada anterior primero: el fichero tiene que poder
-- ejecutarse dos veces seguidas, o el segundo intento falla por clave
-- duplicada y parece un fallo de la RLS cuando no lo es.
-- ------------------------------------------------------------
delete from practicantes where id = 'dddddddd-0000-0000-0000-00000000000d';
delete from equipos       where id = 'eeeeeeee-0000-0000-0000-00000000000e';
delete from auth.users;
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'dentro1@test'),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'dentro2@test'),
  ('cccccccc-0000-0000-0000-00000000000c', 'fuera@test');

-- El trigger bjj_08 crea una ficha por cada usuario. Se borran y se enganchan
-- a fichas del equipo que ya tienen historial detras.
delete from practicantes where user_id in (
  'aaaaaaaa-0000-0000-0000-00000000000a',
  'bbbbbbbb-0000-0000-0000-00000000000b',
  'cccccccc-0000-0000-0000-00000000000c');

-- Los dos practicantes con mas rolls del equipo por defecto hacen de "dentro".
with dentro as (
  select p.id, row_number() over (order by count(r.id) desc, p.nombre) as n
    from practicantes p
    join miembros_equipo m on m.practicante_id = p.id
    left join sesiones s on s.practicante_id = p.id
    left join rolls r on r.sesion_id = s.id
   group by p.id, p.nombre
)
update practicantes p
   set user_id = (case d.n when 1 then 'aaaaaaaa-0000-0000-0000-00000000000a'
                           else 'bbbbbbbb-0000-0000-0000-00000000000b' end)::uuid,
       usa_sistema = true
  from dentro d
 where d.id = p.id and d.n <= 2;

-- Y uno fuera: ficha nueva, equipo nuevo, con una sesion y un roll suyos.
insert into practicantes (id, nombre, usa_sistema, user_id)
values ('dddddddd-0000-0000-0000-00000000000d', 'Ajeno', true,
        'cccccccc-0000-0000-0000-00000000000c');

insert into equipos (id, nombre, slug, codigo_union)
values ('eeeeeeee-0000-0000-0000-00000000000e', 'Otro sitio', 'otro-sitio', 'OTRO-XYZ');
insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo)
values ('eeeeeeee-0000-0000-0000-00000000000e',
        'dddddddd-0000-0000-0000-00000000000d', 'admin');

insert into sesiones (id, practicante_id, fecha, equipo_id)
values ('ffffffff-0000-0000-0000-00000000000f',
        'dddddddd-0000-0000-0000-00000000000d', current_date,
        'eeeeeeee-0000-0000-0000-00000000000e');
insert into rolls (id, sesion_id, orden_en_sesion, resultado)
values ('99999999-0000-0000-0000-000000000009',
        'ffffffff-0000-0000-0000-00000000000f', 1, 'sin_sumision');
insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo)
values ('99999999-0000-0000-0000-000000000009', 'yo', 'barrida',
        'guardia_cerrada', 'abajo', 'ninguno');

-- Cuantos rolls hay del equipo por defecto: es el numero que "dentro1" tiene
-- que seguir viendo. Se guarda antes de tocar nada.
-- Tabla normal y no temporal: la leen tambien los bloques que corren como
-- `authenticated`, y a un pg_temp ajeno no se le pueden dar permisos. Se borra
-- al final del fichero.
drop table if exists esperado;
create table esperado as
select count(*)::int as rolls
  from rolls r
  join sesiones s on s.id = r.sesion_id
  join miembros_equipo m on m.practicante_id = s.practicante_id
 where m.equipo_id = (select equipo_id from miembros_equipo
                      where practicante_id = (select id from practicantes
                                               where user_id = 'aaaaaaaa-0000-0000-0000-00000000000a')
                      limit 1);
grant select on esperado to authenticated;


\echo ''
\echo '=== 1. Ve lo suyo y lo de todo el equipo, con cuenta exacta'
begin;
  select set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a"}', true);
  set local role authenticated;
  do $$
  declare v_ve int; v_esp int;
  begin
    select count(*) into v_ve from rolls;
    select rolls into v_esp from esperado;
    if v_ve <> v_esp then
      raise exception 'FALLO: ve % rolls y deberia ver % (los de su equipo)', v_ve, v_esp;
    end if;
    raise notice 'PASS  ve los % rolls del equipo, ni uno mas ni uno menos', v_ve;
  end $$;
rollback;


\echo ''
\echo '=== 2. NO ve nada de un practicante de otro equipo'
begin;
  select set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a"}', true);
  set local role authenticated;
  do $$
  declare n int;
  begin
    select count(*) into n from sesiones
     where practicante_id = 'dddddddd-0000-0000-0000-00000000000d';
    if n > 0 then raise exception 'FALLO GRAVE: ve % sesiones de otro equipo', n; end if;

    select count(*) into n from rolls
     where id = '99999999-0000-0000-0000-000000000009';
    if n > 0 then raise exception 'FALLO GRAVE: ve el roll de otro equipo'; end if;

    select count(*) into n from eventos
     where roll_id = '99999999-0000-0000-0000-000000000009';
    if n > 0 then raise exception 'FALLO GRAVE: ve % eventos de otro equipo', n; end if;

    raise notice 'PASS  de un practicante de otro equipo no ve ni sesiones, ni rolls, ni eventos';
  end $$;
rollback;

-- Y al reves, que la frontera no sea de un solo sentido.
begin;
  select set_config('request.jwt.claims',
    '{"sub":"cccccccc-0000-0000-0000-00000000000c"}', true);
  set local role authenticated;
  do $$
  declare n int;
  begin
    select count(*) into n from rolls
     where id <> '99999999-0000-0000-0000-000000000009';
    if n > 0 then raise exception 'FALLO GRAVE: el de fuera ve % rolls del equipo', n; end if;
    select count(*) into n from rolls;
    if n <> 1 then raise exception 'FALLO: el de fuera deberia ver su unico roll, ve %', n; end if;
    raise notice 'PASS  y el de fuera solo ve el suyo';
  end $$;
rollback;


\echo ''
\echo '=== 3. Escribir sigue como estaba: lo tuyo si, lo de otro no'
begin;
  select set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a"}', true);
  set local role authenticated;
  do $$
  declare v_yo uuid; v_otro uuid; n int;
  begin
    select id into v_yo from practicantes
     where user_id = 'aaaaaaaa-0000-0000-0000-00000000000a';
    select id into v_otro from practicantes
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b';

    insert into sesiones (practicante_id, fecha) values (v_yo, current_date);
    raise notice 'PASS  puede insertar su propia sesion';

    begin
      insert into sesiones (practicante_id, fecha) values (v_otro, current_date);
      raise exception 'FALLO GRAVE: ha insertado una sesion de un compañero de equipo';
    exception when insufficient_privilege then
      raise notice 'PASS  no puede insertar la sesion de un compañero, aunque la vea';
    end;

    update rolls set notas = 'tocado'
     where sesion_id in (select id from sesiones where practicante_id = v_otro);
    get diagnostics n = row_count;
    if n > 0 then
      raise exception 'FALLO GRAVE: ha modificado % rolls de un compañero', n;
    end if;
    raise notice 'PASS  ver los rolls de un compañero no da para editarlos';
  end $$;
rollback;


\echo ''
\echo '=== 4. No desaparecio nada: lo visible antes y despues cuadra'
do $$
declare v_total int; v_equipo int;
begin
  -- Como superusuario, todo lo que hay.
  select count(*) into v_total from rolls;
  -- Lo que queda dentro del equipo por defecto mas el roll del de fuera.
  select rolls into v_equipo from esperado;
  if v_equipo + 1 <> v_total then
    raise exception 'FALLO: hay % rolls en total y solo % quedan alcanzables (%. sin dueño?)',
      v_total, v_equipo + 1, v_total - v_equipo - 1;
  end if;
  raise notice 'PASS  los % rolls siguen alcanzables: % del equipo y 1 del de fuera',
    v_total, v_equipo;
end $$;

\echo ''
\echo '######## LECTURA RECORTADA AL GRUPO, ESCRITURA INTACTA ########'

drop table esperado;
