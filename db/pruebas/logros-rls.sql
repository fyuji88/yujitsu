-- ============================================================
--  LOGROS · que la RLS por equipo tambien los tape
--
--    psql ... -f db/pruebas/logros-rls.sql
--
--  Las vistas de logros no tienen politicas propias: llevan
--  `security_invoker = on` y por debajo leen `rolls`, `sesiones` y `eventos`,
--  que sí las tienen (bjj_15, lectura por equipo). Eso DEBERIA bastar, pero
--  "deberia" no es una comprobacion: basta que a alguien se le escape un
--  `security_definer` en una vista intermedia para que los logros se
--  conviertan en una puerta lateral que enseña la actividad de otro equipo.
--
--  Un test de RLS como superusuario no prueba nada: `postgres` se la salta.
--  Hay que ponerse el claim y el rol.
-- ============================================================
\set ON_ERROR_STOP on

begin;

do $$
declare
  v_fuera_user uuid := 'cccccccc-1010-0000-0000-00000000000c';
  v_fuera uuid; v_otro_grupo uuid; v_dentro uuid;
  v_s uuid; v_r uuid;
  v_ve_ajenos int; v_ve_lo_suyo int;
begin
  -- Alguien de OTRO equipo, con un logro suyo para que la prueba distinga
  -- "no ve nada" de "no ve lo de los demas".
  delete from practicantes where academia = 'PRUEBAS-RLS';
  delete from equipos where slug = 'pruebas-rls';
  delete from auth.users where id = v_fuera_user;

  insert into auth.users (id, email) values (v_fuera_user, 'fuera-logros@test');
  delete from practicantes where user_id = v_fuera_user;   -- la que crea el trigger

  insert into practicantes (nombre, cinturon, academia, usa_sistema, user_id)
  values ('RLS-Fuera', 'azul', 'PRUEBAS-RLS', true, v_fuera_user) returning id into v_fuera;

  insert into equipos (nombre, slug, codigo_union)
  values ('Otro tatami', 'pruebas-rls', 'RLSLOG-Z9') returning id into v_otro_grupo;
  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo)
  values (v_otro_grupo, v_fuera, 'admin');

  -- Un roll suyo que consigue GUARDIA DE HIERRO.
  insert into sesiones (practicante_id, fecha, modalidad, formato, equipo_id)
  values (v_fuera, current_date, 'gi', 'sparring', v_otro_grupo) returning id into v_s;
  insert into rolls (id, sesion_id, orden_en_sesion, origen, resultado, posicion_inicio, rol_inicio)
  values (gen_random_uuid(), v_s, 1, 'propio', 'sin_sumision', 'de_pie', 'neutral')
  returning id into v_r;
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, completado, segundo_roll)
  values (v_r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 20),
         (v_r, 'yo', 'barrida', 'mariposa',        'abajo', 'ninguno', true, 40),
         (v_r, 'yo', 'barrida', 'de_la_riva',      'abajo', 'ninguno', true, 60);

  -- Alguien del equipo de siempre, para saber a quien NO deberia ver.
  select p.id into v_dentro
    from practicantes p
    join miembros_equipo m on m.practicante_id = p.id and m.estado = 'activo'
   where m.equipo_id <> v_otro_grupo
     and exists (select 1 from v_logros_practicante v where v.practicante_id = p.id)
   limit 1;
  if v_dentro is null then
    raise exception 'FALLO: no hay nadie con logros fuera del equipo de pruebas';
  end if;

  -- ---------- Y ahora, como el de fuera ----------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_fuera_user)::text, true);
  set local role authenticated;

  select count(*) into v_ve_ajenos
    from v_logros_practicante where practicante_id = v_dentro;
  select count(*) into v_ve_lo_suyo
    from v_logros_practicante where practicante_id = v_fuera;

  if v_ve_ajenos <> 0 then
    raise exception
      'FALLO GRAVE: desde otro equipo se ven % logros ajenos. Los logros son '
      'una puerta lateral a la actividad de otra academia.', v_ve_ajenos;
  end if;
  raise notice 'PASS  desde otro equipo, los logros ajenos devuelven cero filas';

  if v_ve_lo_suyo = 0 then
    raise exception 'FALLO: tampoco ve los suyos, asi que la prueba no probaba nada';
  end if;
  raise notice 'PASS  y los suyos si los ve (% logros), o esto no probaria nada',
    v_ve_lo_suyo;

  -- El ranking del mes va por equipo y no puede colar a nadie de fuera.
  if exists (select 1 from v_logros_mes where practicante_id = v_dentro) then
    raise exception 'FALLO GRAVE: el ranking del mes enseña a gente de otro equipo';
  end if;
  raise notice 'PASS  el ranking del mes tampoco cuela a los de fuera';

  -- El catalogo si es publico: sin el, la coleccion no puede pintar los
  -- logros que aun no tienes.
  if (select count(*) from logros) = 0 then
    raise exception 'FALLO: el catalogo no se lee, y sin el no hay coleccion';
  end if;
  raise notice 'PASS  el catalogo se lee: es publico a proposito';

  reset role;
end $$;

rollback;

\echo ''
\echo '######## LOGROS Y RLS: NO SE VE LO DE OTRO GRUPO ########'
