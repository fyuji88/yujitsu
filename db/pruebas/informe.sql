-- ============================================================
--  FASE 4 · El informe de la quedada
--
--    psql ... -v quedada=<uuid> -f db/pruebas/informe.sql
--
--  Lo que se comprueba es la REGLA, no la lista de titulos: cada persona se
--  lleva exactamente uno y nadie se queda sin uno. Si eso se rompe, el informe
--  deja de tener gracia — o alguien se lleva dos, o alguien abre el informe y
--  no sale.
-- ============================================================
\set ON_ERROR_STOP on

-- `cerrar_quedada` solo la puede llamar un admin, y eso lo resuelve
-- `private.es_admin()` a partir del claim. Sin ponerlo, auth.uid() es null y
-- la funcion rechaza la llamada — incluso como superusuario, porque la
-- comprobacion no es de permisos de Postgres sino de rol dentro del equipo.
select set_config('request.jwt.claims',
  json_build_object('sub', (
    select p.user_id from practicantes p
      join miembros_equipo m on m.practicante_id = p.id
     where m.rol = 'admin' and m.estado = 'activo' and p.user_id is not null
     limit 1))::text, false);

do $$
declare
  v_q         uuid;
  v_datos     jsonb;
  v_asis      int;
  v_titulos   int;
  v_distintos int;
  v_personas  int;
  v_antes     jsonb;
begin
  -- La quedada con mas rolls dentro, que es la que da un informe con sustancia.
  select s.quedada_id into v_q
    from sesiones s join rolls r on r.sesion_id = s.id
   where s.quedada_id is not null
   group by s.quedada_id order by count(*) desc limit 1;
  if v_q is null then
    raise exception 'FALLO: no hay ninguna quedada con rolls para probar';
  end if;

  v_datos := cerrar_quedada(v_q, true);
  v_asis    := (v_datos->>'asistentes')::int;
  v_titulos := jsonb_array_length(v_datos->'titulos');

  select count(*), count(distinct t->>'titulo'), count(distinct t->>'practicante_id')
    into v_titulos, v_distintos, v_personas
    from jsonb_array_elements(v_datos->'titulos') t;

  if v_titulos <> v_personas then
    raise exception 'FALLO: % titulos para % personas — alguien tiene dos',
      v_titulos, v_personas;
  end if;
  if v_titulos <> v_distintos then
    raise exception 'FALLO: un titulo se repartio dos veces';
  end if;
  if v_personas <> v_asis then
    raise exception 'FALLO: % de % asistentes se quedaron sin titulo',
      v_asis - v_personas, v_asis;
  end if;
  raise notice 'PASS  % asistentes, % titulos distintos, uno por cabeza y nadie sin el',
    v_asis, v_titulos;

  -- El ranking: minimo 2 rolls para entrar, y ordenado por media descendente.
  if exists (select 1 from jsonb_array_elements(v_datos->'ranking') x
              where (x->>'rolls')::int < 2) then
    raise exception 'FALLO: hay alguien en el ranking con menos de 2 rolls';
  end if;
  raise notice 'PASS  en el ranking solo entra quien tiene 2 rolls o mas';

  -- CONGELADO: volver a llamar sin pedir regenerar devuelve lo mismo, aunque
  -- los datos hayan cambiado. Es el punto entero de guardar el jsonb.
  v_antes := v_datos;
  delete from eventos where roll_id in (
    select r.id from rolls r join sesiones s on s.id = r.sesion_id
     where s.quedada_id = v_q limit 5);
  v_datos := cerrar_quedada(v_q);
  if v_datos <> v_antes then
    raise exception 'FALLO GRAVE: el informe cambio al tocar los rolls; no estaba congelado';
  end if;
  raise notice 'PASS  el informe esta congelado: borrar eventos no lo cambia';

  -- Y regenerar a proposito si lo cambia.
  v_datos := cerrar_quedada(v_q, true);
  if v_datos = v_antes then
    raise notice 'AVISO  regenerar dio lo mismo; puede ser casualidad con estos datos';
  else
    raise notice 'PASS  y regenerar a proposito si lo recalcula';
  end if;

  if (select estado from quedadas where id = v_q) <> 'cerrada' then
    raise exception 'FALLO: la quedada deberia quedar cerrada';
  end if;
  raise notice 'PASS  y la quedada queda cerrada';
end $$;

\echo ''
\echo '######## INFORME: UN TITULO POR CABEZA, Y CONGELADO ########'
