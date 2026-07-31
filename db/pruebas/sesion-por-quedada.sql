-- ============================================================
--  PRUEBAS · Una sesion por Open Mat   (bjj_34)
-- ============================================================
--
--    psql ... -f db/pruebas/sesion-por-quedada.sql
--
--  Se monta su propio escenario y termina en ROLLBACK.
--
--  EL ORDEN NO ES CASUAL. Lo primero que se comprueba es que CON NULO NO CAMBIA
--  NADA: un cambio de firma que altere el caso que ya funcionaba es peor que no
--  hacerlo, y es lo que hay que descartar antes de mirar nada nuevo.
--
--  Y la que manda es la ultima: dos Open Mats el mismo dia, misma modalidad,
--  mismo sitio, la misma persona rodando en los dos. Dos sesiones, dos
--  informes, cada uno con SUS rolls y ninguno con los del otro.
-- ============================================================

\set ON_ERROR_STOP on
begin;

do $$
declare
  v_eq  uuid; v_a uuid; v_a_user uuid; v_b uuid;
  v_q1  uuid; v_q2 uuid;
  s1    uuid; s2 uuid; s3 uuid;
  par   uuid; r jsonb; n int; i int;
  d1    jsonb; d2 jsonb;
begin
  select id, user_id into v_a, v_a_user
    from practicantes where user_id is not null order by created_at limit 1;
  select id into v_b from practicantes
   where id <> v_a and usa_sistema order by created_at limit 1;
  if v_a is null or v_b is null then
    raise notice 'AVISO  hacen falta dos practicantes con cuenta: NO se ha probado NADA';
    return;
  end if;

  insert into equipos (nombre, slug, codigo_union)
  values ('Equipo dos open mats', 'equipo-2om', 'DOS-111') returning id into v_eq;
  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo, estado)
  values (v_eq, v_a, 'admin', 'activo'), (v_eq, v_b, 'miembro', 'activo');

  -- DOS Open Mats el mismo dia, MISMA modalidad, MISMO sitio. El caso de
  -- Felipe: antes de bjj_34 los dos caian en la misma sesion.
  insert into quedadas (equipo_id, titulo, fecha, hora_inicio, lugar, modalidad, creado_por)
  values (v_eq, 'Open mat 10h', current_date, '10:00', 'Casa Felipe', 'nogi', v_a)
  returning id into v_q1;
  insert into quedadas (equipo_id, titulo, fecha, hora_inicio, lugar, modalidad, creado_por)
  values (v_eq, 'Open mat 16h', current_date, '16:00', 'Casa Felipe', 'nogi', v_a)
  returning id into v_q2;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_user)::text, true);

  -- ================================================== 1 · CON NULO, LO DE HOY
  s1 := sesion_del_dia(v_a, current_date, 'nogi', 'Casa Felipe');
  s2 := sesion_del_dia(v_a, current_date, 'nogi', 'Casa Felipe');
  if s1 <> s2 then
    raise exception 'FALLO GRAVE: con nulo ya no encuentra la sesion que acaba de crear';
  end if;
  raise notice 'PASS  con p_quedada nulo, dos llamadas dan LA MISMA sesion (lo de hoy)';

  -- Y sigue encontrandola aunque se le pase el cuarto argumento como siempre.
  if sesion_del_dia(v_a, current_date, 'nogi', 'Casa Felipe') <> s1 then
    raise exception 'FALLO: la llamada de cuatro argumentos ya no resuelve igual';
  end if;
  raise notice 'PASS  la llamada de hoy (cuatro argumentos) sigue resolviendo';

  -- Y una sesion SIN quedada la sigue encontrando aunque despues se enganche:
  -- nulo significa "me da igual la quedada", que es lo que hacia siempre.
  perform enganchar_sesion_a_quedada(s1, v_q1);
  if sesion_del_dia(v_a, current_date, 'nogi', 'Casa Felipe') <> s1 then
    raise exception 'FALLO: con nulo dejo de encontrar una sesion ya enganchada';
  end if;
  raise notice 'PASS  y con nulo encuentra tambien una sesion ya enganchada';

  -- ================================================== 2 · CON QUEDADA, SEPARA
  -- La del Open Mat de la mañana ya existe (es s1, enganchada arriba).
  if sesion_del_dia(v_a, current_date, 'nogi', 'Casa Felipe', v_q1) <> s1 then
    raise exception 'FALLO: no encuentra la sesion del Open Mat que ya tiene una';
  end if;
  raise notice 'PASS  con la quedada del Open Mat encuentra SU sesion';

  s3 := sesion_del_dia(v_a, current_date, 'nogi', 'Casa Felipe', v_q2);
  if s3 = s1 then
    raise exception 'FALLO GRAVE: el segundo Open Mat cayo en la sesion del primero. '
      'Es exactamente el bug que esta migracion viene a arreglar.';
  end if;
  if (select quedada_id from sesiones where id = s3) is distinct from v_q2 then
    raise exception 'FALLO: la sesion nueva no quedo colgada del segundo Open Mat';
  end if;
  raise notice 'PASS  ==> el segundo Open Mat crea SU PROPIA sesion, ya enganchada';

  -- ================================================== 3 · rolls en cada uno
  -- Dos rolls en el Open Mat de la mañana y uno en el de la tarde, con la
  -- sesion de cada uno. Se escriben directos porque lo que se prueba aqui es la
  -- separacion, no la RPC del observador.
  for i in 1..2 loop
    insert into rolls (sesion_id, orden_en_sesion, modalidad, resultado, registrado_por, origen)
    values (s1, i, 'nogi', 'sumision_favor', v_a, 'propio') returning id into par;
    insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id, completado)
    select par, 'yo', 'sumision', 'montada', 'arriba', 'cuello', id, true
      from tecnicas where slug = (array['mata_leao','armbar'])[i];
  end loop;
  insert into rolls (sesion_id, orden_en_sesion, modalidad, resultado, registrado_por, origen)
  values (s3, 1, 'nogi', 'sumision_favor', v_a, 'propio') returning id into par;
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id, completado)
  select par, 'yo', 'sumision', 'montada', 'arriba', 'cuello', id, true
    from tecnicas where slug = 'triangulo';

  -- El segundo practicante, para que el ranking tenga a alguien mas.
  insert into rolls (sesion_id, orden_en_sesion, modalidad, resultado, registrado_por, origen)
  values (sesion_del_dia(v_b, current_date, 'nogi', 'Casa Felipe', v_q1),
          1, 'nogi', 'sumision_contra', v_a, 'propio') returning id into par;
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id, completado)
  select par, 'yo', 'sumision', 'montada', 'arriba', 'cuello', id, false
    from tecnicas where slug = 'kimura';

  select count(*) into n from rolls r join sesiones s on s.id = r.sesion_id
   where s.quedada_id = v_q1;
  if n <> 3 then raise exception 'FALLO: el Open Mat de la mañana tiene % rolls, deberian ser 3', n; end if;
  select count(*) into n from rolls r join sesiones s on s.id = r.sesion_id
   where s.quedada_id = v_q2;
  if n <> 1 then raise exception 'FALLO: el de la tarde tiene % rolls, deberia ser 1', n; end if;
  raise notice 'PASS  cada Open Mat tiene SUS rolls: 3 y 1, sin mezclarse';

  -- ================================================== 4 · DOS INFORMES
  d1 := cerrar_quedada(v_q1);
  d2 := cerrar_quedada(v_q2);
  if (d1->>'rolls')::int <> 3 or (d2->>'rolls')::int <> 1 then
    raise exception 'FALLO GRAVE: los informes se mezclaron (% y %)',
      d1->>'rolls', d2->>'rolls';
  end if;
  raise notice 'PASS  ==> DOS informes, uno con % rolls y otro con %, ninguno con los del otro',
    d1->>'rolls', d2->>'rolls';

  select count(*) into n from quedada_informes where quedada_id in (v_q1, v_q2);
  if n <> 2 then raise exception 'FALLO: hay % informes guardados, deberian ser 2', n; end if;
  raise notice 'PASS  y los dos quedan guardados por separado';

  raise notice '######## UNA SESION POR OPEN MAT: todo pasa ########';
end $$;

rollback;
