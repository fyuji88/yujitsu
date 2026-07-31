-- ============================================================
--  BJJ TRACKER — Una sesion por Open Mat   ·   Migracion bjj_34
-- ============================================================
--
--  EL PROBLEMA. `sesion_del_dia` agrupa por (practicante, fecha, modalidad,
--  academia), asi que DOS Open Mats el mismo dia caen en la MISMA sesion y solo
--  uno puede tener informe. No es hipotetico: Felipe tiene dos reales este
--  domingo, los dos nogi, en el mismo sitio.
--
--  Estaba anotado como "sabido roto" desde bjj_33. Deja de estarlo.
--
--  QUE CAMBIA. `p_quedada` entra en la CLAVE DE BUSQUEDA: se busca la sesion de
--  esa persona/fecha/modalidad/academia CON ese `quedada_id`, y si no existe se
--  crea con el.
--
--  CON `p_quedada` NULO EL COMPORTAMIENTO ES EL DE HOY, y eso es lo primero que
--  se prueba: `db/pruebas/sesion-por-quedada.sql` compara los dos caminos antes
--  de mirar nada nuevo. Un cambio de firma que altere el caso que ya funciona
--  es peor que no hacerlo.
--
--  LO QUE NO HAY QUE REHACER, comprobado y no supuesto: `sesiones` no tiene mas
--  restriccion unica que la clave primaria —los otros tres indices no son
--  unicos—, asi que no hay indice que reconstruir ni filas que migrar.
--
--  Y LA COLA NO SERIALIZA ESTA LLAMADA. El cliente no llama nunca a
--  `sesion_del_dia`: la llaman `registrar_roll_observado` y `espejar_roll`, las
--  dos dentro de Postgres. Comprobado ANTES de tocar la firma, que es el tercer
--  cambio de firma de la semana.
-- ============================================================

begin;

-- Se tira y se recrea porque `create or replace` no deja añadir un parametro.
-- No queda ambiguedad posible: solo hay una `sesion_del_dia` y las llamadas de
-- hoy —cuatro argumentos— siguen encajando porque el quinto tiene default.
drop function public.sesion_del_dia(uuid, date, bjj_modalidad, text);

create function public.sesion_del_dia(
  p_practicante uuid,
  p_fecha       date,
  p_modalidad   bjj_modalidad default 'gi'::bjj_modalidad,
  p_academia    text default null,
  p_quedada     uuid default null)
returns uuid language plpgsql
set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id
    from sesiones
   where practicante_id = p_practicante
     and fecha = p_fecha
     and modalidad = p_modalidad
     -- LA PIEZA NUEVA. Con `p_quedada` nulo esto es `quedada_id is not distinct
     -- from null`... que NO es lo de hoy: hoy se ignora la columna entera. Por
     -- eso la condicion es "o no me han dicho quedada, o coincide": con nulo se
     -- comporta igual que siempre y con valor busca la de ese Open Mat.
     and (p_quedada is null or quedada_id = p_quedada)
   order by created_at
   limit 1;

  if v_id is null then
    insert into sesiones (practicante_id, fecha, modalidad, formato, academia,
                          quedada_id, notas)
    values (p_practicante, p_fecha, p_modalidad, 'sparring', p_academia,
            p_quedada,
            'Sesion creada automaticamente desde el modo observador')
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

-- Y EL REVOKE, que se me olvido y cazo el caso 27 de db/pruebas/rls.sql.
-- Postgres regala EXECUTE a PUBLIC en toda funcion nueva y `anon` hereda de
-- PUBLIC: recrear una funcion deshace en silencio lo que cerro bjj_25. Es la
-- TERCERA vez que pasa —bjj_27, bjj_31 y ahora— y las tres las ha cazado esa
-- bateria, no yo.
revoke all on function public.sesion_del_dia(uuid, date, bjj_modalidad, text, uuid)
  from public, anon;
grant execute on function public.sesion_del_dia(uuid, date, bjj_modalidad, text, uuid)
  to authenticated, service_role;

comment on function public.sesion_del_dia(uuid, date, bjj_modalidad, text, uuid) is
  'Encuentra o crea la sesion de alguien para un dia. `p_quedada` entra en la '
  'clave de busqueda: dos Open Mats el mismo dia son DOS sesiones, y por tanto '
  'dos informes. Con `p_quedada` nulo se comporta como antes de bjj_34.';

commit;
