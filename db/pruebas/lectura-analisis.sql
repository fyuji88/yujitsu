-- ============================================================
--  La migracion bjj_13 abre la LECTURA entre practicantes. Lo que hay que
--  demostrar es que abrio SOLO la lectura: si se hubiera colado escritura,
--  cualquiera podria meter o borrar rolls en el historial de otro, y eso no
--  lo ve el typecheck ni la pantalla.
--
--    psql ... -f db/pruebas/lectura-analisis.sql
--
--  Se prueba con `set local role authenticated` y el claim del usuario. Como
--  superusuario todo pasa y no significa nada.
-- ============================================================
\set ON_ERROR_STOP on

-- Dos cuentas sobre los datos demo: Felipe mira, Pablo es el mirado.
delete from auth.users;
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'felipe@test'),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'pablo@test');

-- El trigger bjj_08 les crea ficha propia; aqui se enganchan a las del demo
-- para que tengan historial detras.
delete from practicantes
 where user_id in ('aaaaaaaa-0000-0000-0000-00000000000a',
                   'bbbbbbbb-0000-0000-0000-00000000000b');
update practicantes set user_id = 'aaaaaaaa-0000-0000-0000-00000000000a',
       usa_sistema = true where nombre = 'Felipe';
update practicantes set user_id = 'bbbbbbbb-0000-0000-0000-00000000000b',
       usa_sistema = true where nombre = 'Pablo';

\echo ''
\echo '=== Pablo, autenticado, mirando los datos de Felipe'
-- En los datos demo el historial es todo de Felipe; Pablo solo aparece como
-- rival. Asi que el que mira es Pablo: es exactamente el caso del selector.
begin;
  select set_config('request.jwt.claims',
    '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b"}', true);
  set local role authenticated;

  do $$
  declare
    v_felipe uuid;
    n int;
  begin
    select id into v_felipe from practicantes where nombre = 'Felipe';

    -- LEER: tiene que funcionar, o el selector de practicante no sirve.
    select count(*) into n from sesiones where practicante_id = v_felipe;
    if n = 0 then raise exception 'FALLO: Pablo no ve las sesiones de Felipe'; end if;
    raise notice 'PASS  ve % sesiones de Felipe', n;

    select count(*) into n from eventos e
      join rolls r on r.id = e.roll_id
      join sesiones s on s.id = r.sesion_id
     where s.practicante_id = v_felipe;
    if n = 0 then raise exception 'FALLO: Pablo no ve los eventos de Felipe'; end if;
    raise notice 'PASS  ve % eventos de Felipe', n;

    select count(*) into n from jsonb_array_elements(analisis(v_felipe)->'off');
    if n = 0 then raise exception 'FALLO: el analisis de Felipe sale vacio'; end if;
    raise notice 'PASS  analisis(Felipe) devuelve % celdas ofensivas', n;

    -- ESCRIBIR: NO puede funcionar. Aqui es donde estaria el fallo grave.
    begin
      insert into sesiones (practicante_id, fecha) values (v_felipe, current_date);
      raise exception 'FALLO GRAVE: Pablo ha insertado una sesion en el historial de Felipe';
    exception when insufficient_privilege then
      raise notice 'PASS  insertar una sesion ajena sigue fallando';
    end;

    begin
      update rolls set notas = 'tocado por quien no debe'
       where sesion_id in (select id from sesiones where practicante_id = v_felipe);
      get diagnostics n = row_count;
      if n > 0 then
        raise exception 'FALLO GRAVE: Pablo ha modificado % rolls de Felipe', n;
      end if;
      raise notice 'PASS  actualizar rolls ajenos no cambia ninguna fila';
    exception when insufficient_privilege then
      raise notice 'PASS  actualizar rolls ajenos falla';
    end;

    begin
      delete from eventos where roll_id in (
        select r.id from rolls r join sesiones s on s.id = r.sesion_id
         where s.practicante_id = v_felipe);
      get diagnostics n = row_count;
      if n > 0 then
        raise exception 'FALLO GRAVE: Pablo ha borrado % eventos de Felipe', n;
      end if;
      raise notice 'PASS  borrar eventos ajenos no borra ninguna fila';
    exception when insufficient_privilege then
      raise notice 'PASS  borrar eventos ajenos falla';
    end;

    -- Y lo suyo lo sigue pudiendo escribir.
    insert into sesiones (practicante_id, fecha)
      values ((select id from practicantes where nombre = 'Pablo'), current_date);
    raise notice 'PASS  y Pablo sigue pudiendo escribir en lo suyo';
  end $$;
rollback;

\echo ''
\echo '=== anon no entra a leer nada'
begin;
  set local role anon;
  do $$
  declare n int;
  begin
    select count(*) into n from eventos;
    if n > 0 then
      raise exception 'FALLO: anon ve % eventos; la lectura se abrio de mas', n;
    end if;
    raise notice 'PASS  anon no ve ningun evento: se abrio a authenticated, no a todos';
  end $$;
rollback;

\echo ''
\echo '######## LECTURA ABIERTA, ESCRITURA CERRADA ########'
