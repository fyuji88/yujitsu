-- ============================================================
--  FASE 3 · Quedadas: plazas, idempotencia y externos
--
--    psql ... -f db/pruebas/quedadas.sql
--
--  La concurrencia de plazas NO se prueba aqui: hace falta que dos sesiones
--  distintas se pisen de verdad, y eso va en db/pruebas/quedadas-concurrencia.sh.
--  Razonar sobre el codigo no sirve para esto.
-- ============================================================
\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- Preparacion, repetible
-- ------------------------------------------------------------
delete from quedadas where titulo like 'PRUEBA%';
delete from practicantes where nombre in ('T-Admin', 'T-Miembro', 'T-Externo');
delete from equipos where slug in ('t-equipo', 't-otro');
delete from auth.users where email like 't-%@test';

insert into auth.users (id, email) values
  ('11110000-0000-0000-0000-000000000001', 't-admin@test'),
  ('22220000-0000-0000-0000-000000000002', 't-miembro@test'),
  ('33330000-0000-0000-0000-000000000003', 't-externo@test');
delete from practicantes where user_id in (
  '11110000-0000-0000-0000-000000000001',
  '22220000-0000-0000-0000-000000000002',
  '33330000-0000-0000-0000-000000000003');

insert into practicantes (id, nombre, usa_sistema, user_id) values
  ('aaaa0000-0000-0000-0000-00000000000a', 'T-Admin',   true, '11110000-0000-0000-0000-000000000001'),
  ('bbbb0000-0000-0000-0000-00000000000b', 'T-Miembro', true, '22220000-0000-0000-0000-000000000002'),
  ('cccc0000-0000-0000-0000-00000000000c', 'T-Externo', true, '33330000-0000-0000-0000-000000000003');

insert into equipos (id, nombre, slug, codigo_union)
values ('dddd0000-0000-0000-0000-00000000000d', 'T-Equipo', 't-equipo', 'TGRUPO-A1B');
insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo) values
  ('dddd0000-0000-0000-0000-00000000000d', 'aaaa0000-0000-0000-0000-00000000000a', 'admin');

insert into quedadas (id, equipo_id, titulo, fecha, plazas_max, admite_externos,
                      token_invitacion, creado_por)
values ('eeee0000-0000-0000-0000-00000000000e', 'dddd0000-0000-0000-0000-00000000000d',
        'PRUEBA open mat', current_date, 2, true, 'token-de-prueba',
        'aaaa0000-0000-0000-0000-00000000000a');


\echo ''
\echo '=== 1. unirse_con_codigo es idempotente'
begin;
  select set_config('request.jwt.claims',
    '{"sub":"22220000-0000-0000-0000-000000000002"}', true);
  set local role authenticated;
  do $$
  declare g1 uuid; g2 uuid; n int;
  begin
    g1 := unirse_con_codigo('TGRUPO-A1B');
    g2 := unirse_con_codigo('tgrupo-a1b');   -- y no distingue mayusculas
    if g1 <> g2 then raise exception 'FALLO: dos equipos distintos'; end if;
    select count(*) into n from miembros_equipo
     where equipo_id = g1 and practicante_id = 'bbbb0000-0000-0000-0000-00000000000b';
    if n <> 1 then raise exception 'FALLO: % filas de miembro, esperaba 1', n; end if;
    raise notice 'PASS  unirse dos veces deja una sola fila de miembro';

    begin
      perform unirse_con_codigo('NO-EXISTE');
      raise exception 'FALLO: un codigo inventado deberia fallar';
    exception when no_data_found then
      raise notice 'PASS  un codigo que no existe da error claro';
    end;
  end $$;
commit;


\echo ''
\echo '=== 2. apuntarse es idempotente y respeta las plazas'
begin;
  select set_config('request.jwt.claims',
    '{"sub":"11110000-0000-0000-0000-000000000001"}', true);
  set local role authenticated;
  do $$
  declare r1 jsonb; r2 jsonb; n int;
  begin
    r1 := apuntarse_a_quedada('eeee0000-0000-0000-0000-00000000000e');
    r2 := apuntarse_a_quedada('eeee0000-0000-0000-0000-00000000000e');
    if r1->>'estado' <> 'apuntado' then
      raise exception 'FALLO: con plazas libres deberia entrar apuntado, salio %', r1->>'estado';
    end if;
    if (r2->>'creado')::boolean then
      raise exception 'FALLO: la segunda llamada ha creado otra fila';
    end if;
    select count(*) into n from inscripciones
     where quedada_id = 'eeee0000-0000-0000-0000-00000000000e'
       and practicante_id = 'aaaa0000-0000-0000-0000-00000000000a';
    if n <> 1 then raise exception 'FALLO: % inscripciones, esperaba 1', n; end if;
    raise notice 'PASS  apuntarse dos veces deja una sola inscripcion';
  end $$;
commit;


\echo ''
\echo '=== 3. El externo: sin token no entra, con token si, y no ve nada mas'
begin;
  select set_config('request.jwt.claims',
    '{"sub":"33330000-0000-0000-0000-000000000003"}', true);
  set local role authenticated;
  do $$
  declare r jsonb; n int;
  begin
    begin
      perform apuntarse_a_quedada('eeee0000-0000-0000-0000-00000000000e');
      raise exception 'FALLO GRAVE: un externo se ha apuntado sin token';
    exception when insufficient_privilege then
      raise notice 'PASS  sin token, un externo no se puede apuntar';
    end;

    r := apuntarse_a_quedada('eeee0000-0000-0000-0000-00000000000e', 'token-de-prueba');
    if r->>'estado' <> 'apuntado' or not (r->>'es_externo')::boolean then
      raise exception 'FALLO: con token deberia entrar como externo apuntado, salio %', r;
    end if;
    raise notice 'PASS  con el token entra, y queda marcado como externo';

    -- Y aqui lo que de verdad importa: NO ve la tabla.
    select count(*) into n from quedadas;
    if n > 0 then
      raise exception 'FALLO GRAVE: el externo ve % quedadas por la tabla', n;
    end if;
    raise notice 'PASS  y por la tabla de quedadas no ve ni la suya: solo por el token';

    select count(*) into n from miembros_equipo;
    if n > 0 then raise exception 'FALLO GRAVE: el externo ve % miembros del equipo', n; end if;
    select count(*) into n from rolls;
    if n > 0 then raise exception 'FALLO GRAVE: el externo ve % rolls del equipo', n; end if;
    raise notice 'PASS  ni los miembros del equipo ni sus rolls';

    -- Lo que si puede: consultar SU quedada por el token.
    select count(*) into n from quedada_por_token('token-de-prueba');
    if n <> 1 then raise exception 'FALLO: quedada_por_token deberia devolver 1 fila, dio %', n; end if;
    raise notice 'PASS  y por el token ve exactamente su quedada';
  end $$;
commit;


\echo ''
\echo '=== 4. Al liberarse una plaza sube el primero de la lista'
-- Las dos plazas estan ocupadas (admin y externo). El miembro entra en espera.
begin;
  select set_config('request.jwt.claims',
    '{"sub":"22220000-0000-0000-0000-000000000002"}', true);
  set local role authenticated;
  do $$
  declare r jsonb;
  begin
    r := apuntarse_a_quedada('eeee0000-0000-0000-0000-00000000000e');
    if r->>'estado' <> 'lista_espera' then
      raise exception 'FALLO: sin plazas deberia ir a la lista, salio %', r->>'estado';
    end if;
    raise notice 'PASS  sin plazas libres se entra en lista de espera (orden %)', r->>'orden';
  end $$;
commit;

begin;
  select set_config('request.jwt.claims',
    '{"sub":"11110000-0000-0000-0000-000000000001"}', true);
  set local role authenticated;
  do $$
  declare r jsonb; v_estado text;
  begin
    r := cancelar_inscripcion('eeee0000-0000-0000-0000-00000000000e');
    if r->>'promovido' is null then
      raise exception 'FALLO: al irse un apuntado deberia subir el de la lista';
    end if;
    if (r->>'promovido')::uuid <> 'bbbb0000-0000-0000-0000-00000000000b' then
      raise exception 'FALLO: subio quien no tocaba (%)', r->>'promovido';
    end if;
    raise notice 'PASS  al borrarse uno, sube el primero de la lista en la misma transaccion';
  end $$;
commit;

do $$
declare n int;
begin
  select count(*) into n from inscripciones
   where quedada_id = 'eeee0000-0000-0000-0000-00000000000e' and estado = 'apuntado';
  if n <> 2 then raise exception 'FALLO: quedan % apuntados, esperaba 2', n; end if;
  raise notice 'PASS  la quedada sigue con sus 2 plazas ocupadas, ni una mas';
end $$;

\echo ''
\echo '######## QUEDADAS: PLAZAS, IDEMPOTENCIA Y EXTERNOS ########'
