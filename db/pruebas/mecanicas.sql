-- ============================================================
--  PRUEBAS · Mecanicas, precisar y los dos niveles   (bjj_29)
-- ============================================================
--
--    psql ... -f db/pruebas/mecanicas.sql
--
--  Necesita la base sembrada (db/pruebas/semilla-demo.sql), porque la ultima
--  parte precisa kimuras de verdad y comprueba que el total de la mecanica no
--  se mueve. Todo va dentro de una transaccion que termina en ROLLBACK: no
--  deja nada.
--
--  QUE COMPRUEBA, Y POR QUE ESO Y NO OTRA COSA:
--
--  1. Los dos guardias del UN SOLO NIVEL. Son declarativos, asi que o los
--     prueba alguien o nadie sabe si funcionan hasta que un dia hay un nieto.
--  2. El invariante de `precisar`: el total de la mecanica NO se mueve, el
--     desglose SI. Eso es el bloque entero en una prueba — si precisar restara
--     de un lado sin sumar del otro, nadie precisaria dos veces.
--  3. Los cuatro casos de permiso de la RPC. El tercero (un tercero del mismo
--     equipo) es el que importa: es el que un `update` con politica dejaria
--     pasar, porque Postgres no tiene RLS por columna.
--  4. La asimetria de los enfoques, en las dos direcciones.
-- ============================================================

\set ON_ERROR_STOP on
begin;

do $$
declare
  v_kimura      uuid;
  v_tariko      uuid;
  v_armbar      uuid;
  v_yo          uuid;
  v_yo_user     uuid;
  v_otro        uuid;
  v_otro_user   uuid;
  v_tercero     uuid;
  v_ter_user    uuid;
  v_sesion      uuid;
  v_roll        uuid;
  v_ev1         uuid;
  v_ev2         uuid;
  v_total_antes bigint;
  v_total_desp  bigint;
  n             int;
begin
  select id into v_kimura from tecnicas where slug = 'kimura';
  select id into v_tariko from tecnicas where slug = 'tarikoplata';
  select id into v_armbar from tecnicas where slug = 'armbar';

  -- ================================================== 1 · UN SOLO NIVEL
  begin
    insert into tecnicas (slug, nombre, tipo, objetivo_default, variante_de)
    values ('nieto_imposible', 'Nieto', 'sumision', 'hombro', v_tariko);
    raise exception 'FALLO GRAVE: se pudo colgar una variante de una variante';
  exception when foreign_key_violation then
    raise notice 'PASS  no hay nietos: colgar de una variante viola la FK compuesta';
  end;

  begin
    update tecnicas set variante_de = v_armbar where id = v_kimura;
    raise exception 'FALLO GRAVE: se pudo degradar una madre que ya tiene variantes';
  exception when foreign_key_violation then
    raise notice 'PASS  una madre con variantes no se puede degradar a variante';
  end;

  -- Y lo que SI tiene que poder hacerse: una madre SIN variantes si puede
  -- pasar a variante. Si esto fallara, el guardia estaria de mas y no de menos.
  begin
    update tecnicas set variante_de = v_kimura where slug = 'muneca';
    raise notice 'PASS  y una tecnica sin variantes si puede pasar a variante';
    update tecnicas set variante_de = null where slug = 'muneca';
  exception when others then
    raise exception 'FALLO: el guardia se pasa de frenada: %', sqlerrm;
  end;

  -- ================================================== 2 · mecanica_id
  select count(*) into n from tecnicas where mecanica_id is null;
  if n > 0 then raise exception 'FALLO: % tecnicas sin mecanica_id', n; end if;
  raise notice 'PASS  toda tecnica tiene mecanica: las huerfanas son la suya propia';

  select count(*) into n from tecnicas where variante_de is null and mecanica_id <> id;
  if n > 0 then raise exception 'FALLO: % madres cuya mecanica no son ellas mismas', n; end if;
  select count(*) into n from tecnicas where variante_de is not null and mecanica_id <> variante_de;
  if n > 0 then raise exception 'FALLO: % variantes que no apuntan a su madre', n; end if;
  raise notice 'PASS  mecanica_id = coalesce(variante_de, id), en las 2 direcciones';

  -- ================================================== 3 · escenario
  -- Dos practicantes con cuenta y un tercero del mismo equipo.
  select p.id, p.user_id into v_yo, v_yo_user
    from practicantes p where p.user_id is not null order by p.created_at limit 1;
  select p.id, p.user_id into v_otro, v_otro_user
    from practicantes p where p.user_id is not null and p.id <> v_yo
    order by p.created_at limit 1;
  select p.id, p.user_id into v_tercero, v_ter_user
    from practicantes p where p.user_id is not null and p.id not in (v_yo, v_otro)
    order by p.created_at limit 1;
  -- Sin dos cuentas no se puede montar el escenario de permisos. Se AVISA y se
  -- sale, no se falla: los dos guardias de arriba son estructurales y corren
  -- sobre una base vacia, que es como la ve el CI. Lo que no se puede es dar
  -- por probado lo que no se ha probado, y por eso el aviso es ruidoso.
  if v_otro is null then
    raise notice 'AVISO  sin dos practicantes con cuenta: NO se han probado ni';
    raise notice '       los permisos de precisar_tecnica ni el invariante.';
    raise notice '       Siembra con db/pruebas/semilla-demo.sql para cubrirlos.';
    return;
  end if;

  -- Un roll propio con dos kimuras, registrado por `v_otro` (para poder probar
  -- los dos permisos con el mismo roll).
  insert into sesiones (practicante_id, fecha, modalidad, formato)
  values (v_yo, current_date, 'nogi', 'sparring') returning id into v_sesion;
  insert into rolls (sesion_id, orden_en_sesion, modalidad, resultado, registrado_por, origen)
  values (v_sesion, 1, 'nogi', 'sumision_favor', v_otro, 'observador') returning id into v_roll;
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id, completado)
  values (v_roll, 'yo', 'sumision', 'montada', 'arriba', 'hombro', v_kimura, true)
  returning id into v_ev1;
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id, completado)
  values (v_roll, 'yo', 'sumision', 'cien_kilos', 'arriba', 'hombro', v_kimura, false)
  returning id into v_ev2;

  select count(*) into v_total_antes
    from eventos e join tecnicas t on t.id = e.tecnica_id
   where t.mecanica_id = v_kimura;

  -- ================================================== 4 · los cuatro permisos
  -- (a) el protagonista del roll
  perform set_config('request.jwt.claims', json_build_object('sub', v_yo_user)::text, true);
  perform precisar_tecnica(v_ev1, v_tariko);
  raise notice 'PASS  el protagonista del roll puede precisar';

  -- (b) quien lo registro
  perform set_config('request.jwt.claims', json_build_object('sub', v_otro_user)::text, true);
  perform precisar_tecnica(v_ev2, v_tariko);
  raise notice 'PASS  quien registro el roll tambien puede precisar';

  -- (c) un tercero del mismo equipo NO
  if v_tercero is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_ter_user)::text, true);
    begin
      perform precisar_tecnica(v_ev1, v_kimura);
      raise exception 'FALLO GRAVE: un tercero del equipo pudo precisar un evento ajeno';
    exception when insufficient_privilege then
      raise notice 'PASS  un tercero del mismo equipo NO puede precisar';
    end;
  else
    raise notice 'AVISO faltan practicantes para el caso del tercero';
  end if;

  -- (d) precisar a OTRA mecanica, ni el dueño
  perform set_config('request.jwt.claims', json_build_object('sub', v_yo_user)::text, true);
  begin
    perform precisar_tecnica(v_ev1, v_armbar);
    raise exception 'FALLO GRAVE: se pudo precisar a otra mecanica';
  exception when check_violation then
    raise notice 'PASS  precisar a otra mecanica falla: eso es corregir, no precisar';
  end;

  -- ================================================== 5 · EL INVARIANTE
  select count(*) into v_total_desp
    from eventos e join tecnicas t on t.id = e.tecnica_id
   where t.mecanica_id = v_kimura;
  if v_total_desp <> v_total_antes then
    raise exception 'FALLO GRAVE: el total de la mecanica se movio al precisar (% -> %)',
      v_total_antes, v_total_desp;
  end if;
  raise notice 'PASS  el total de la mecanica NO se mueve al precisar (% eventos)', v_total_desp;

  select count(*) into n from eventos where tecnica_id = v_tariko;
  if n <> 2 then raise exception 'FALLO: el desglose no se movio (% tarikoplatas)', n; end if;
  raise notice 'PASS  y el desglose SI se mueve: 2 tarikoplatas donde habia 2 kimuras';

  -- La auditoria, que es la que resuelve las discusiones.
  select count(*) into n from eventos
   where id in (v_ev1, v_ev2) and tecnica_precisada_por is not null
     and tecnica_precisada_en is not null;
  if n <> 2 then raise exception 'FALLO: no quedo constancia de quien preciso'; end if;
  select count(distinct tecnica_precisada_por) into n from eventos where id in (v_ev1, v_ev2);
  if n <> 2 then raise exception 'FALLO: los dos eventos dicen que los preciso el mismo'; end if;
  raise notice 'PASS  queda escrito quien preciso cada uno, y no son el mismo';

  -- ================================================== 6 · enfoques asimetricos
  perform set_config('request.jwt.claims', json_build_object('sub', v_yo_user)::text, true);

  -- (a) enfoque en la MADRE: la tarikoplata suma
  delete from enfoques where practicante_id = v_yo;
  insert into enfoques (practicante_id, texto, tecnicas, desde)
  values (v_yo, 'Kimura', array[v_kimura], current_date - 1);
  select (x->>'veces')::int into n
    from jsonb_array_elements(enfoque_contraste(v_yo) -> 'tecnicas') x
   where (x->>'id')::uuid = v_kimura;
  if coalesce(n, 0) < 2 then
    raise exception 'FALLO: un enfoque en la madre no cuenta sus variantes (veces=%)', n;
  end if;
  raise notice 'PASS  enfoque en KIMURA cuenta las tarikoplatas (% veces)', n;

  -- y lo dice, para que el contador se entienda
  select jsonb_array_length(x -> 'incluye') into n
    from jsonb_array_elements(enfoque_contraste(v_yo) -> 'tecnicas') x
   where (x->>'id')::uuid = v_kimura;
  if coalesce(n, 0) < 1 then
    raise exception 'FALLO: el enfoque no dice que variantes incluye';
  end if;
  raise notice 'PASS  y dice cuales incluye (% variantes), que es lo que hace que se entienda', n;

  -- (b) enfoque en la VARIANTE: la kimura normal NO suma
  update eventos set tecnica_id = v_kimura where id = v_ev1;   -- una vuelve a ser kimura
  delete from enfoques where practicante_id = v_yo;
  insert into enfoques (practicante_id, texto, tecnicas, desde)
  values (v_yo, 'Tarikoplata', array[v_tariko], current_date - 1);
  select (x->>'veces')::int into n
    from jsonb_array_elements(enfoque_contraste(v_yo) -> 'tecnicas') x
   where (x->>'id')::uuid = v_tariko;
  if coalesce(n, 0) <> 1 then
    raise exception 'FALLO: un enfoque en la variante no cuenta solo esa (veces=%)', n;
  end if;
  raise notice 'PASS  enfoque en TARIKOPLATA no cuenta la kimura normal (% vez)', n;

  raise notice '######## MECANICAS: todo pasa ########';
end $$;

rollback;
