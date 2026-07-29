-- ============================================================
--  FASE 6 · Enfoques
--
--    psql ... -f db/pruebas/enfoques.sql
--
--  Tres cosas:
--    1. El contraste cuenta bien — comparado contra una cuenta a mano, no
--       contra si mismo.
--    2. Hay historial de verdad: cerrar un enfoque y abrir otro no pisa el
--       anterior, y el activo es el nuevo.
--    3. La RLS: se leen los del grupo, y NADIE escribe el enfoque de otro.
--       Esto ultimo es lo que de verdad importa — un enfoque ajeno editable
--       seria poner palabras en boca de otro.
-- ============================================================
\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- Preparacion: hacen falta DOS cuentas en el mismo grupo, y la base local
-- normalmente tiene una. Se le da cuenta a un companero de grupo que no la
-- tenga, y al final se le quita. Sin dos cuentas no hay nada que probar: la
-- pregunta entera es si uno puede escribir el enfoque del otro.
-- ------------------------------------------------------------
insert into auth.users (id, email)
values ('bbbbbbbb-e0f0-0000-0000-00000000000b', 'enfoques-otro@test')
    on conflict (id) do nothing;

-- El trigger bjj_08 le crea ficha propia; sobra, porque lo que se quiere es
-- engancharlo a una ficha que ya esta en el grupo.
delete from practicantes where user_id = 'bbbbbbbb-e0f0-0000-0000-00000000000b';

update practicantes set user_id = 'bbbbbbbb-e0f0-0000-0000-00000000000b',
                        usa_sistema = true
 where id = (
   select p.id from practicantes p
     join miembros_grupo m on m.practicante_id = p.id and m.estado = 'activo'
    where p.user_id is null
      and m.grupo_id in (select grupo_id from miembros_grupo
                          where estado = 'activo'
                            and practicante_id in (select id from practicantes
                                                    where user_id is not null))
    limit 1);

do $$
declare
  v_yo      uuid;  v_yo_user   uuid;
  v_otro    uuid;  v_otro_user uuid;
  v_e1      uuid;  v_e2        uuid;
  v_datos   jsonb;
  v_rolls   int;   v_esperado  int;   v_dice int;
  v_pos     bjj_posicion := 'media_guardia';
begin
  select p.id, p.user_id into v_yo, v_yo_user
    from practicantes p
    join miembros_grupo m on m.practicante_id = p.id and m.estado = 'activo'
   where p.user_id is not null
     and exists (select 1 from sesiones s join rolls r on r.sesion_id = s.id
                  where s.practicante_id = p.id)
   limit 1;

  select p.id, p.user_id into v_otro, v_otro_user
    from practicantes p
    join miembros_grupo m2 on m2.practicante_id = p.id and m2.estado = 'activo'
   where p.user_id is not null and p.id <> v_yo
     and m2.grupo_id in (select grupo_id from miembros_grupo
                          where practicante_id = v_yo and estado = 'activo')
   limit 1;

  if v_yo is null or v_otro is null then
    raise exception 'FALLO: hacen falta dos practicantes con cuenta en el mismo grupo';
  end if;

  delete from enfoques where practicante_id in (v_yo, v_otro);

  -- ---------- 1. El contraste cuenta bien ----------
  insert into enfoques (practicante_id, desde, texto, posiciones)
  values (v_yo, current_date - 400, 'prueba: media guardia', array[v_pos])
  returning id into v_e1;

  v_datos := enfoque_contraste(v_yo);

  -- La cuenta a mano, sin pasar por la funcion.
  select count(*) into v_rolls
    from rolls r join sesiones s on s.id = r.sesion_id
   where s.practicante_id = v_yo and s.fecha between current_date - 400 and current_date;

  select count(distinct e.roll_id) into v_esperado
    from eventos e
    join rolls r on r.id = e.roll_id
    join sesiones s on s.id = r.sesion_id
   where s.practicante_id = v_yo and e.actor = 'yo' and e.posicion = v_pos
     and s.fecha between current_date - 400 and current_date;

  if (v_datos->>'rolls')::int <> v_rolls then
    raise exception 'FALLO: el contraste dice % rolls y son %',
      v_datos->>'rolls', v_rolls;
  end if;

  select (x->>'rolls')::int into v_dice
    from jsonb_array_elements(v_datos->'posiciones') x
   where x->>'codigo' = v_pos::text;

  if v_dice is distinct from v_esperado then
    raise exception 'FALLO: dice % rolls en % y a mano salen %',
      v_dice, v_pos, v_esperado;
  end if;
  raise notice 'PASS  el contraste cuadra con la cuenta a mano: % de % rolls en %',
    v_esperado, v_rolls, v_pos;

  -- ---------- 2. Historial: el viejo no se pisa ----------
  update enfoques set hasta = current_date - 1 where id = v_e1;
  insert into enfoques (practicante_id, desde, texto, posiciones)
  values (v_yo, current_date, 'prueba: de la riva', array['de_la_riva'::bjj_posicion])
  returning id into v_e2;

  if (select count(*) from enfoques where practicante_id = v_yo) <> 2 then
    raise exception 'FALLO: el enfoque nuevo piso al anterior en vez de sumarse';
  end if;
  if (enfoque_contraste(v_yo)->'enfoque'->>'id')::uuid <> v_e2 then
    raise exception 'FALLO: el activo deberia ser el nuevo';
  end if;
  raise notice 'PASS  hay historial: el cerrado se queda y el activo es el nuevo';

  -- Cerrar HOY deja de estar activo hoy mismo. Con la regla anterior
  -- (`hasta is null or hasta >= current_date`) el enfoque seguia saliendo el
  -- resto del dia y el boton "darlo por terminado" no hacia nada visible.
  update enfoques set hasta = current_date where id = v_e2;
  if enfoque_contraste(v_yo) is not null then
    raise exception 'FALLO: cerrado hoy y sigue apareciendo como activo';
  end if;
  raise notice 'PASS  cerrarlo hoy lo desactiva hoy, no manana';
  update enfoques set hasta = null where id = v_e2;

  -- ---------- 3. La RLS ----------
  -- Leer el del companero: si.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_otro_user)::text, true);
  set local role authenticated;

  if not exists (select 1 from enfoques where practicante_id = v_yo) then
    raise exception 'FALLO: un companero de grupo no ve mi enfoque';
  end if;
  raise notice 'PASS  el companero de grupo lee mi enfoque';

  -- Escribirlo: NO.
  begin
    update enfoques set texto = 'esto no deberia poder escribirlo' where id = v_e2;
    if found then
      raise exception 'FALLO GRAVE: % edito el enfoque de %', v_otro, v_yo;
    end if;
  exception when insufficient_privilege then
    null;   -- rechazado por la politica, que es lo que se busca
  end;

  begin
    insert into enfoques (practicante_id, texto) values (v_yo, 'enfoque puesto por otro');
    raise exception 'FALLO GRAVE: % creo un enfoque a nombre de %', v_otro, v_yo;
  exception when insufficient_privilege then
    null;
  end;

  if exists (select 1 from enfoques
              where id = v_e2 and texto <> 'prueba: de la riva') then
    raise exception 'FALLO GRAVE: el texto del enfoque ajeno cambio';
  end if;
  raise notice 'PASS  y no puede escribirlo: ni editar el mio ni crear uno a mi nombre';

  reset role;
  delete from enfoques where practicante_id in (v_yo, v_otro);
end $$;

-- Se deshace la cuenta prestada: la ficha se queda como estaba.
update practicantes set user_id = null, usa_sistema = false
 where user_id = 'bbbbbbbb-e0f0-0000-0000-00000000000b';
delete from auth.users where id = 'bbbbbbbb-e0f0-0000-0000-00000000000b';

\echo ''
\echo '######## ENFOQUES: EL CONTRASTE CUADRA Y NADIE HABLA POR OTRO ########'
