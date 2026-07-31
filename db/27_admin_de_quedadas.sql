-- ============================================================
--  BJJ TRACKER — Administrar un Open Mat   ·   Migracion bjj_32
-- ============================================================
--
--  OJO CON LA PALABRA. Aqui "evento" NO es lo que se llama evento fuera: en el
--  esquema `eventos` son las acciones dentro de un roll. Lo que en pantalla es
--  un "Open Mat" aqui es una `quedada`. Esta migracion no toca `eventos`.
--
--  LA RLS YA PERMITE TODO ESTO. `quedadas_admin`, `inscripciones_admin` y las
--  tres de `miembros_equipo` ya existen y ya dejan a un admin hacer su trabajo.
--  Aqui no se crea ni una politica: lo que falta no es permiso, es que la
--  LOGICA DE PLAZAS no se pueda saltar.
--
--  EL PROBLEMA REAL. La RLS deja a un admin insertar en `inscripciones`
--  directamente, y si lo hace se salta el reparto de plazas y la lista de
--  espera: acabas con nueve personas en ocho plazas, o con alguien en
--  `apuntado` que deberia estar en `lista_espera`. La regla vive en la RPC, y
--  por eso la RPC es la unica via.
--
--  LA PROMOCION OCURRE EN TRES SITIOS —alguien se borra, un admin lo quita,
--  suben las plazas— y aqui se escribe UNA vez. Tres copias de una regla de
--  plazas es como se acaba con tres comportamientos distintos y nadie sabe
--  cual es el bueno.
-- ============================================================

begin;

-- ---------------------------------------------------------- 1 · la promocion
--
-- Sube de la lista de espera tanta gente como quepa, por `orden_en_lista`. Es
-- idempotente y no promueve de mas: si no hay hueco, no hace nada.
--
-- Vive en `private` para que PostgREST no la publique: no es una operacion que
-- nadie deba poder invocar suelta, sino una consecuencia de otras tres.
create function private.promover_lista_espera(p_quedada uuid)
returns int language plpgsql security definer
set search_path = public as $$
declare
  v_plazas    smallint;
  v_apuntados int;
  v_libres    int;
  v_subidos   int := 0;
begin
  select plazas_max into v_plazas from quedadas where id = p_quedada;
  -- Sin tope no hay lista de espera que promover: todo el mundo cabe.
  if v_plazas is null then
    return 0;
  end if;

  select count(*) into v_apuntados from inscripciones
   where quedada_id = p_quedada and estado = 'apuntado';

  v_libres := v_plazas - v_apuntados;
  if v_libres <= 0 then
    return 0;
  end if;

  with suben as (
    select id from inscripciones
     where quedada_id = p_quedada and estado = 'lista_espera'
     order by orden_en_lista nulls last, created_at
     limit v_libres
  )
  update inscripciones i
     set estado = 'apuntado', orden_en_lista = null
    from suben s where s.id = i.id;

  get diagnostics v_subidos = row_count;
  return v_subidos;
end;
$$;

comment on function private.promover_lista_espera(uuid) is
  'Sube de la lista de espera tanta gente como quepa, por orden_en_lista. La '
  'llaman los TRES sitios donde se libera plaza: cancelar, quitar a alguien, y '
  'subir plazas_max. Escrita una vez a proposito.';

-- ------------------------------------------------- 2 · las plazas, por trigger
--
-- POR QUE UN TRIGGER Y NO CODIGO EN LA PANTALLA. La RLS deja al admin hacer un
-- `update quedadas set plazas_max = ...` directo, asi que cualquier regla que
-- viva solo en React se salta con una llamada a la API. Y son dos reglas que no
-- se pueden saltar:
--
--   - BAJAR por debajo de los que ya estan apuntados se RECHAZA. Nunca se
--     degrada en silencio a alguien que ya tenia su sitio: eso es quitarle algo
--     que ya le habias dado, y sin que se entere.
--   - SUBIR promueve desde la lista de espera. Es literalmente la razon por la
--     que alguien sube las plazas; que no pasara sola seria un boton que no
--     hace lo que dice.
create function private.quedada_plazas() returns trigger
language plpgsql security definer
set search_path = public as $$
declare v_apuntados int;
begin
  if new.plazas_max is distinct from old.plazas_max then
    select count(*) into v_apuntados from inscripciones
     where quedada_id = new.id and estado = 'apuntado';

    if new.plazas_max is not null and new.plazas_max < v_apuntados then
      raise exception 'no puedes bajar a % plazas: hay % apuntados',
        new.plazas_max, v_apuntados
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger quedadas_plazas_no_bajan
  before update on quedadas
  for each row execute function private.quedada_plazas();

-- La promocion va DESPUES: en un `before` los apuntados todavia no reflejan el
-- tope nuevo, y `promover_lista_espera` lee `quedadas.plazas_max`.
create function private.quedada_plazas_suben() returns trigger
language plpgsql security definer
set search_path = public as $$
begin
  if new.plazas_max is distinct from old.plazas_max then
    perform private.promover_lista_espera(new.id);
  end if;
  return null;
end;
$$;

create trigger quedadas_plazas_promueven
  after update on quedadas
  for each row execute function private.quedada_plazas_suben();

commit;

-- ============================================================
--  3 · Las dos RPC, con "a quien" opcional
-- ============================================================
--
--  CUIDADO CON EL CAMBIO DE FIRMA, que ya nos mordio con `p_grupo`. Postgres
--  identifica una funcion por (nombre, TIPOS) y PostgREST resuelve por el
--  CONJUNTO DE NOMBRES del cuerpo. Si se añade el parametro sin quitar la
--  version vieja quedan dos funciones y una llamada con {p_quedada, p_token}
--  encaja en las dos: PostgREST no sabria cual, y contestaria ambiguo.
--
--  Por eso se TIRA la vieja y se crea una sola con el parametro nuevo por
--  defecto. Las llamadas actuales —que mandan {p_quedada, p_token} y
--  {p_quedada}— siguen resolviendo, porque un parametro con `default` se puede
--  omitir. Comprobado, no supuesto: esta en db/pruebas/quedadas.sql.
--
--  Y NO VIAJA EN LA COLA. `apuntarse_a_quedada` se llama directa desde la
--  pantalla, no pasa por `encolar()` —solo lo hacen sesiones, rolls, eventos y
--  el roll observado—, asi que no hay nada serializado en IndexedDB con la
--  firma vieja. Comprobado antes de tocarla.
-- ============================================================

begin;

drop function public.apuntarse_a_quedada(uuid, text);

create function public.apuntarse_a_quedada(
  p_quedada     uuid,
  p_token       text default null,
  p_practicante uuid default null    -- null = yo
)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_yo        uuid;
  v_quien     uuid;
  q           quedadas%rowtype;
  v_miembro   boolean;
  v_externo   boolean := false;
  v_ins       inscripciones%rowtype;
  v_apuntados int;
  v_estado    bjj_estado_inscripcion;
  v_orden     smallint;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien se apunta no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_quedada::text, 0));

  select * into q from quedadas where id = p_quedada;
  if not found then
    raise exception 'esa quedada no existe' using errcode = 'no_data_found';
  end if;
  if q.estado <> 'abierta' then
    raise exception 'la quedada esta %', q.estado using errcode = 'check_violation';
  end if;

  -- APUNTAR A OTRO ES COSA DE ADMIN, y del equipo de ESA quedada. Sin esta
  -- comprobacion, cualquiera podria apuntar a cualquiera a cualquier sitio.
  v_quien := coalesce(p_practicante, v_yo);
  if v_quien <> v_yo and not private.es_admin(q.equipo_id) then
    raise exception 'solo un admin del equipo puede apuntar a otra persona'
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from practicantes where id = v_quien) then
    raise exception 'ese practicante no existe' using errcode = 'no_data_found';
  end if;

  v_miembro := exists (select 1 from miembros_equipo m
                        where m.equipo_id = q.equipo_id
                          and m.practicante_id = v_quien
                          and m.estado = 'activo');
  if not v_miembro then
    -- Apuntandote TU, sin ser miembro solo se entra con el token, y solo si la
    -- quedada los admite. El token no abre nada mas que esta quedada.
    --
    -- Apuntando un ADMIN a otra persona, el token no pinta nada: el permiso ya
    -- lo da ser admin. Los contactos sin cuenta son justo este caso, y por eso
    -- entran marcados como externos.
    if v_quien = v_yo
       and (not q.admite_externos or p_token is null
            or p_token <> q.token_invitacion) then
      raise exception 'esta quedada no admite invitados o el enlace no vale'
        using errcode = 'insufficient_privilege';
    end if;
    v_externo := true;
  end if;

  -- Idempotente: apuntarse dos veces no crea dos filas ni te manda a la lista.
  select * into v_ins from inscripciones
   where quedada_id = p_quedada and practicante_id = v_quien;
  if found and v_ins.estado in ('apuntado', 'lista_espera') then
    return jsonb_build_object('estado', v_ins.estado, 'orden', v_ins.orden_en_lista,
                              'es_externo', v_ins.es_externo, 'creado', false);
  end if;

  select count(*) into v_apuntados from inscripciones
   where quedada_id = p_quedada and estado = 'apuntado';

  if q.plazas_max is null or v_apuntados < q.plazas_max then
    v_estado := 'apuntado';
    v_orden  := null;
  else
    v_estado := 'lista_espera';
    select coalesce(max(orden_en_lista), 0) + 1 into v_orden from inscripciones
     where quedada_id = p_quedada and estado = 'lista_espera';
  end if;

  insert into inscripciones (quedada_id, practicante_id, estado, orden_en_lista, es_externo)
  values (p_quedada, v_quien, v_estado, v_orden, v_externo)
  on conflict (quedada_id, practicante_id)
  do update set estado = excluded.estado, orden_en_lista = excluded.orden_en_lista,
                es_externo = excluded.es_externo;

  return jsonb_build_object('estado', v_estado, 'orden', v_orden,
                            'es_externo', v_externo, 'creado', true);
end;
$$;

revoke all on function public.apuntarse_a_quedada(uuid, text, uuid) from public, anon;
grant execute on function public.apuntarse_a_quedada(uuid, text, uuid)
  to authenticated, service_role;

drop function public.cancelar_inscripcion(uuid);

create function public.cancelar_inscripcion(
  p_quedada     uuid,
  p_practicante uuid default null    -- null = yo
)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_yo        uuid;
  v_quien     uuid;
  q           quedadas%rowtype;
  v_ins       inscripciones%rowtype;
  v_subidos   int;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'no hay ficha de practicante' using errcode = 'insufficient_privilege';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_quedada::text, 0));

  select * into q from quedadas where id = p_quedada;
  if not found then
    raise exception 'esa quedada no existe' using errcode = 'no_data_found';
  end if;

  -- Quitar a otro es cosa de admin, igual que apuntarlo.
  v_quien := coalesce(p_practicante, v_yo);
  if v_quien <> v_yo and not private.es_admin(q.equipo_id) then
    raise exception 'solo un admin del equipo puede quitar a otra persona'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_ins from inscripciones
   where quedada_id = p_quedada and practicante_id = v_quien;
  if not found or v_ins.estado = 'cancelado' then
    return jsonb_build_object('cancelado', false, 'promovidos', 0);
  end if;

  update inscripciones set estado = 'cancelado', orden_en_lista = null
   where id = v_ins.id;

  -- Solo se libera plaza si quien se va estaba DENTRO, no en la lista. Y la
  -- promocion es la misma funcion que usan los otros dos caminos.
  v_subidos := case when v_ins.estado = 'apuntado'
                    then private.promover_lista_espera(p_quedada) else 0 end;

  return jsonb_build_object('cancelado', true, 'promovidos', v_subidos);
end;
$$;

revoke all on function public.cancelar_inscripcion(uuid, uuid) from public, anon;
grant execute on function public.cancelar_inscripcion(uuid, uuid)
  to authenticated, service_role;

commit;
