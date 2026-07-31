-- ============================================================
--  PRUEBAS · Administrar un Open Mat   (bjj_32)
-- ============================================================
--
--    psql ... -f db/pruebas/admin-quedadas.sql
--
--  Se monta su propio escenario y termina en ROLLBACK: no deja nada y no
--  necesita la semilla.
--
--  QUE DECIDE, Y POR QUE ESTAS COSAS:
--
--   1. LAS PLAZAS, LOS CUATRO CAMINOS. Es la parte con reglas de verdad: con
--      una plaza libre, dos altas dejan un apuntado y un lista_espera; subir
--      plazas promueve; quitar a alguien promueve; y bajar por debajo de los
--      apuntados se RECHAZA. Lo ultimo importa mas de lo que parece: degradar
--      en silencio a alguien que ya tenia su sitio es quitarle algo sin que se
--      entere.
--   2. EL EQUIPO EQUIVOCADO. Un admin del equipo A no puede tocar nada del B.
--      Son tres casos y los tres van aqui.
--   3. QUE LA FIRMA VIEJA SIGUE RESOLVIENDO. El cambio de `apuntarse` añade un
--      parametro; si las llamadas de hoy dejaran de encajar, la pantalla se
--      rompe entera y el typecheck no lo ve.
-- ============================================================

\set ON_ERROR_STOP on
begin;

do $$
declare
  v_eq_a   uuid; v_eq_b uuid;
  v_admin  uuid; v_admin_user uuid;
  v_uno    uuid; v_dos uuid; v_tres uuid;
  v_qa     uuid; v_qb uuid;
  r        jsonb;
  n        int;
  v_estado text;
begin
  -- ---------------------------------------------------- escenario
  insert into equipos (nombre, slug, codigo_union)
  values ('Equipo A', 'equipo-a-prueba', 'AAA-111') returning id into v_eq_a;
  insert into equipos (nombre, slug, codigo_union)
  values ('Equipo B', 'equipo-b-prueba', 'BBB-222') returning id into v_eq_b;

  select id, user_id into v_admin, v_admin_user
    from practicantes where user_id is not null order by created_at limit 1;
  insert into practicantes (nombre, cinturon, usa_sistema)
  values ('Uno de prueba', 'blanca', false) returning id into v_uno;
  insert into practicantes (nombre, cinturon, usa_sistema)
  values ('Dos de prueba', 'blanca', false) returning id into v_dos;
  insert into practicantes (nombre, cinturon, usa_sistema)
  values ('Tres de prueba', 'blanca', false) returning id into v_tres;

  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo, estado)
  values (v_eq_a, v_admin, 'admin', 'activo'),
         (v_eq_a, v_uno,   'miembro', 'activo'),
         (v_eq_a, v_dos,   'miembro', 'activo'),
         (v_eq_a, v_tres,  'miembro', 'activo');

  -- UNA sola plaza, que es donde las reglas se ven.
  insert into quedadas (equipo_id, titulo, fecha, modalidad, plazas_max, creado_por)
  values (v_eq_a, 'Open mat de prueba', current_date + 1, 'nogi', 1, v_admin)
  returning id into v_qa;
  insert into quedadas (equipo_id, titulo, fecha, modalidad, creado_por)
  values (v_eq_b, 'De otro equipo', current_date + 1, 'nogi', v_admin)
  returning id into v_qb;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_user)::text, true);

  -- ============================================ 1 · la firma vieja resuelve
  r := apuntarse_a_quedada(v_qa);                    -- solo p_quedada
  if (r->>'estado') <> 'apuntado' then
    raise exception 'FALLO: apuntarse con un solo argumento no funciona';
  end if;
  raise notice 'PASS  la llamada de hoy (solo p_quedada) sigue resolviendo';
  perform cancelar_inscripcion(v_qa);

  -- ============================================ 2 · las plazas, los 4 caminos
  -- (a) con UNA plaza: el primero entra, el segundo a la lista
  r := apuntarse_a_quedada(v_qa, null, v_uno);
  if (r->>'estado') <> 'apuntado' then raise exception 'FALLO: el primero no entro'; end if;
  r := apuntarse_a_quedada(v_qa, null, v_dos);
  if (r->>'estado') <> 'lista_espera' then
    raise exception 'FALLO: el segundo deberia ir a la lista, y fue a %', r->>'estado';
  end if;
  raise notice 'PASS  con una plaza: uno apuntado y uno en lista de espera';

  -- (b) BAJAR por debajo de los apuntados: se rechaza, con el numero
  begin
    update quedadas set plazas_max = 0 where id = v_qa;
    raise exception 'FALLO GRAVE: se pudo bajar por debajo de los apuntados';
  exception when check_violation then
    raise notice 'PASS  bajar plazas por debajo de los apuntados se rechaza';
  end;

  -- (c) SUBIR promueve al primero de la lista
  update quedadas set plazas_max = 2 where id = v_qa;
  select estado::text into v_estado from inscripciones
   where quedada_id = v_qa and practicante_id = v_dos;
  if v_estado <> 'apuntado' then
    raise exception 'FALLO: subir plazas no promovio (sigue en %)', v_estado;
  end if;
  raise notice 'PASS  subir plazas promueve desde la lista de espera';

  -- (d) QUITAR a alguien promueve al primero
  update quedadas set plazas_max = 2 where id = v_qa;   -- sin cambio, no promueve
  r := apuntarse_a_quedada(v_qa, null, v_tres);
  if (r->>'estado') <> 'lista_espera' then
    raise exception 'FALLO: el tercero deberia ir a la lista, y fue a %', r->>'estado';
  end if;
  r := cancelar_inscripcion(v_qa, v_uno);
  if (r->>'promovidos')::int <> 1 then
    raise exception 'FALLO: quitar a alguien no promovio (% promovidos)', r->>'promovidos';
  end if;
  select estado::text into v_estado from inscripciones
   where quedada_id = v_qa and practicante_id = v_tres;
  if v_estado <> 'apuntado' then
    raise exception 'FALLO: el de la lista no subio (esta en %)', v_estado;
  end if;
  raise notice 'PASS  quitar a alguien promueve al primero de la lista';

  -- Y nunca se promueve de mas.
  select count(*) into n from inscripciones
   where quedada_id = v_qa and estado = 'apuntado';
  if n > 2 then raise exception 'FALLO GRAVE: % apuntados en 2 plazas', n; end if;
  raise notice 'PASS  nunca hay mas apuntados que plazas (% en 2)', n;

  -- ============================================ 3 · el equipo equivocado
  -- El admin lo es de A, no de B. Los tres casos que importan.
  begin
    perform apuntarse_a_quedada(v_qb, null, v_uno);
    raise exception 'FALLO GRAVE: apunto a alguien en la quedada de otro equipo';
  exception when insufficient_privilege then
    raise notice 'PASS  no puede apuntar a nadie en la quedada de otro equipo';
  end;

  begin
    perform cancelar_inscripcion(v_qb, v_uno);
    raise exception 'FALLO GRAVE: quito a alguien de la quedada de otro equipo';
  exception when insufficient_privilege then
    raise notice 'PASS  no puede quitar a nadie de la quedada de otro equipo';
  end;

  -- ============================================ 4 · cancelar CONSERVA
  select count(*) into n from inscripciones where quedada_id = v_qa;
  update quedadas set estado = 'cancelada' where id = v_qa;
  if (select count(*) from inscripciones where quedada_id = v_qa) <> n then
    raise exception 'FALLO GRAVE: cancelar se llevo inscripciones por delante';
  end if;
  if not exists (select 1 from quedadas where id = v_qa) then
    raise exception 'FALLO GRAVE: cancelar borro la quedada';
  end if;
  raise notice 'PASS  cancelar conserva la quedada y sus % inscripciones', n;

  raise notice '######## ADMIN DE QUEDADAS: todo pasa ########';
end $$;

rollback;
