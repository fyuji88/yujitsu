-- ============================================================
--  BJJ TRACKER — Una palabra, un concepto   ·   Migracion bjj_27
-- ============================================================
--
--  OJO CON EL NUMERO: el encargo pedia `bjj_22_vocabulario`, pero bjj_22 ya
--  esta cogido — es `db/17_cerrar_lectura_anonima.sql`. Los numeros de fichero
--  y los de migracion llevan desacoplados desde hace tiempo. Este fichero es el
--  22 de `db/` y la migracion 27.
--
--  QUE HACE: separar los nombres que significan mas de una cosa. No cambia ni
--  una regla de negocio, ni una politica, ni un calculo. Solo nombres.
--
--  POR QUE IMPORTA AQUI MAS QUE EN OTROS SITIOS: en esta base la seguridad
--  entera son politicas de RLS y el analisis entero son vistas. Un nombre
--  ambiguo no se convierte en un error, se convierte en una consulta correcta
--  que devuelve otra cosa — y eso no se cae, da un numero. Ya paso: EL ULTIMO
--  EN IRSE se definio como "el roll con el mayor `orden` de la quedada" y
--  `rolls.orden` era el orden dentro de la sesion de cada uno. El logro no
--  premiaba irse el ultimo, premiaba haber rodado mas. Hubo que sacarlo.
--
--  LAS TRES COSAS QUE SE LLAMABAN `grupo`:
--    - el gimnasio          -> equipos / equipo_id
--    - la categoria de posicion -> posiciones.categoria
--    - el par de rolls espejo   -> rolls.par_id
--
--  Y UNA CUARTA QUE EL ENCARGO NO RECOGIA, la peor de todas: el parametro
--  `p_grupo` de `registrar_roll_observado()` NO es el gimnasio, es el
--  `roll_grupo_id`. Lo decia el comentario de `database.types.ts`: "p_grupo es
--  el roll_grupo_id". Un comentario que existe para desmentir un nombre es la
--  definicion de nombre malo. Pasa a `p_par`.
--
--  LAS VISTAS SE RENOMBRAN CON `alter view ... rename column`, NUNCA
--  recreandolas. `create or replace view` ni siquiera deja cambiar el nombre de
--  una columna; y recrear —drop + create— pierde `security_invoker = on`, que
--  es lo unico que impide que una vista lea con los permisos de su dueño en vez
--  de con los de quien consulta. Un renombrado cosmetico no puede ser la via
--  por la que se abre un agujero de privacidad. Las 18 vistas lo tienen puesto
--  y siguen teniendolo; `scripts/comprobar-vocabulario.py` lo comprueba.
--
--  LAS FUNCIONES SI SE RECREAN, y no queda otra: sus cuerpos son TEXTO, no
--  arboles, asi que un renombrado de tabla no llega hasta ellos. Las politicas
--  y las vistas si son arboles y siguen solas — por eso aqui no se toca ni una
--  politica.
--
--  LA COLA DE SALIDA. `registrar_roll_observado` cambia el nombre de un
--  parametro, y ese nombre viaja serializado dentro de IndexedDB. En produccion
--  esto se aplica SOLO cuando todo el mundo haya sincronizado y la pildora diga
--  "al dia"; migracion y despliegue del cliente, juntos. En local da igual.
-- ============================================================

begin;

-- ------------------------------------------------------------------ 1 · tipos
alter type bjj_rol_grupo      rename to bjj_rol_equipo;
alter type bjj_grupo_posicion rename to bjj_categoria_posicion;

-- ----------------------------------------------------------------- 2 · tablas
alter table grupos         rename to equipos;
alter table miembros_grupo rename to miembros_equipo;

-- --------------------------------------------------------------- 3 · columnas
alter table miembros_equipo rename column grupo_id to equipo_id;
alter table miembros_equipo rename column rol      to rol_en_equipo;
alter table quedadas        rename column grupo_id to equipo_id;
alter table sesiones        rename column grupo_id to equipo_id;

alter table rolls      rename column roll_grupo_id to par_id;
alter table rolls      rename column orden         to orden_en_sesion;
alter table inscripciones rename column orden      to orden_en_lista;
alter table posiciones rename column grupo         to categoria;
alter table sesiones   rename column tipo          to formato;

-- El nombre peor entendido del esquema. Ya que se toca, se explica.
comment on column rolls.par_id is
  'Identificador que comparten los dos rolls espejo de un mismo combate '
  'registrado por un observador: A contra B y B contra A son dos filas con el '
  'mismo par_id. Es la clave de idempotencia del modo observador — lo genera '
  'el cliente antes de enviar, y por eso reintentar un envio que no se sabe si '
  'llego no duplica el roll. No tiene ninguna relacion con los equipos.';

comment on column rolls.orden_en_sesion is
  'Orden del roll DENTRO DE LA SESION DE SU DUEÑO: cada persona numera los '
  'suyos del 1 al n. No es el orden de la quedada — dos personas distintas '
  'tienen las dos un roll numero 1 la misma tarde.';

comment on column inscripciones.orden_en_lista is
  'Puesto en la lista de espera. Null si la persona esta dentro de la quedada.';

-- ------------------------------------------------- 4 · lo que publican las vistas
--
-- Sin esto la migracion daria verde y la aplicacion se rompería en silencio: la
-- vista sigue funcionando (Postgres la guarda por numero de columna) pero
-- publica hacia fuera el nombre viejo, asi que el cliente pediria `equipo_id` y
-- recibiria `grupo_id`. Es el fallo mudo de este bloque.
alter view v_feed          rename column grupo_id to equipo_id;
alter view v_feed_crudo    rename column grupo_id to equipo_id;
alter view v_logros_mes    rename column grupo_id to equipo_id;
alter view v_mi_quedada_hoy rename column grupo_id to equipo_id;

alter view v_feed       rename column tipo to tipo_de_elemento;
alter view v_feed_crudo rename column tipo to tipo_de_elemento;

alter view v_eventos         rename column posicion_grupo to posicion_categoria;
alter view v_fuertes_debiles rename column posicion_grupo to posicion_categoria;

alter view v_puntos_roll  rename column roll_grupo_id to par_id;
alter view v_rolls_unicos rename column roll_grupo_id to par_id;
alter view v_rolls_unicos rename column orden         to orden_en_sesion;

-- ------------------------------------------------- 5 · nombres de las funciones
--
-- `alter function ... rename` conserva el oid, asi que las politicas que las
-- llaman siguen apuntando a ellas sin tocarlas.
alter function private.mis_grupos()             rename to mis_equipos;
alter function private.comparte_grupo(uuid)     rename to comparte_equipo;
alter function public.crear_grupo(text, text)   rename to crear_equipo;

-- ------------------------------------------------- 6 · cuerpos de las funciones
--
-- Todas repiten `set search_path = public`. Un `create or replace` sin la
-- clausula `set` BORRA la configuracion de la funcion: ya paso con
-- `espejar_roll` y lo cazo el linter de Supabase. El codigo "no cambiaba", la
-- funcion si.

create or replace function private.mis_equipos()
returns setof uuid language sql stable security definer
set search_path = public as $$
  select equipo_id from miembros_equipo
   where practicante_id = private.practicante_actual()
     and estado = 'activo'
$$;

create or replace function private.comparte_equipo(p_practicante uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select p_practicante = private.practicante_actual()
      or exists (
        select 1
          from miembros_equipo m1
          join miembros_equipo m2 on m2.equipo_id = m1.equipo_id
         where m1.practicante_id = private.practicante_actual()
           and m1.estado = 'activo'
           and m2.practicante_id = p_practicante
           and m2.estado = 'activo')
$$;

-- `es_admin` SE QUEDA CON SU PARAMETRO `p_grupo`, y no es un descuido.
-- Postgres no deja cambiar el nombre de un parametro con `create or replace`, y
-- para hacerlo habria que tirar la funcion — pero SEIS politicas dependen de
-- ella, asi que el drop se las llevaria por delante y este encargo dice
-- explicitamente que no se tocan politicas. Renombrar el parametro vale menos
-- que el riesgo de recrear seis politicas de seguridad a mano. Esta anotado en
-- docs/CAMBIOS.md como sabido roto.
create or replace function private.es_admin(p_grupo uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from miembros_equipo
     where equipo_id = p_grupo
       and practicante_id = private.practicante_actual()
       and rol_en_equipo = 'admin'
       and estado = 'activo')
$$;

create or replace function private.practicantes_visibles()
returns setof uuid language sql stable security definer
set search_path = public as $$
  select private.practicante_actual()
  union
  select m2.practicante_id
    from miembros_equipo m1
    join miembros_equipo m2 on m2.equipo_id = m1.equipo_id
   where m1.practicante_id = private.practicante_actual()
     and m1.estado = 'activo'
     and m2.estado = 'activo'
$$;

create or replace function public.crear_equipo(p_nombre text, p_ciudad text default null)
returns uuid language plpgsql security definer
set search_path = public as $$
declare
  v_equipo uuid;
  v_yo     uuid;
  v_slug   text;
  v_codigo text;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien crea el equipo no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;
  if coalesce(trim(p_nombre), '') = '' then
    raise exception 'el equipo necesita un nombre';
  end if;

  v_slug := regexp_replace(lower(trim(p_nombre)), '[^a-z0-9]+', '-', 'g');
  if exists (select 1 from equipos where slug = v_slug) then
    v_slug := v_slug || '-' || substring(gen_random_uuid()::text from 1 for 4);
  end if;

  loop
    v_codigo := private.nuevo_codigo(p_nombre);
    exit when not exists (select 1 from equipos where codigo_union = v_codigo);
  end loop;

  insert into equipos (nombre, slug, ciudad, codigo_union, creado_por)
  values (trim(p_nombre), v_slug, p_ciudad, v_codigo, auth.uid())
  returning id into v_equipo;

  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo, estado)
  values (v_equipo, v_yo, 'admin', 'activo');

  return v_equipo;
end;
$$;

create or replace function public.unirse_con_codigo(p_codigo text)
returns uuid language plpgsql security definer
set search_path = public as $$
declare
  v_equipo uuid;
  v_yo     uuid;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien se une no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  select id into v_equipo from equipos
   where upper(codigo_union) = upper(trim(p_codigo));
  if v_equipo is null then
    raise exception 'no hay ningun equipo con el codigo %', trim(p_codigo)
      using errcode = 'no_data_found';
  end if;

  -- Idempotente: la gente pulsa dos veces. Y si estabas de baja, volver a
  -- entrar te reactiva en vez de fallar.
  insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo, estado)
  values (v_equipo, v_yo, 'miembro', 'activo')
  on conflict (equipo_id, practicante_id)
  do update set estado = 'activo';

  return v_equipo;
end;
$$;

create or replace function public.apuntarse_a_quedada(p_quedada uuid, p_token text default null)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_yo        uuid;
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

  v_miembro := q.equipo_id in (select private.mis_equipos());
  if not v_miembro then
    -- Sin ser miembro solo se entra con el token, y solo si la quedada los
    -- admite. El token no abre nada mas que esta quedada.
    if not q.admite_externos or p_token is null
       or p_token <> q.token_invitacion then
      raise exception 'esta quedada no admite invitados o el enlace no vale'
        using errcode = 'insufficient_privilege';
    end if;
    v_externo := true;
  end if;

  -- Idempotente: apuntarse dos veces no crea dos filas ni te manda a la lista.
  select * into v_ins from inscripciones
   where quedada_id = p_quedada and practicante_id = v_yo;
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
  values (p_quedada, v_yo, v_estado, v_orden, v_externo)
  on conflict (quedada_id, practicante_id)
  do update set estado = excluded.estado, orden_en_lista = excluded.orden_en_lista,
                es_externo = excluded.es_externo;

  return jsonb_build_object('estado', v_estado, 'orden', v_orden,
                            'es_externo', v_externo, 'creado', true);
end;
$$;

create or replace function public.cancelar_inscripcion(p_quedada uuid)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_yo        uuid;
  v_ins       inscripciones%rowtype;
  v_promovido uuid;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'no hay ficha de practicante' using errcode = 'insufficient_privilege';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_quedada::text, 0));

  select * into v_ins from inscripciones
   where quedada_id = p_quedada and practicante_id = v_yo;
  if not found or v_ins.estado = 'cancelado' then
    return jsonb_build_object('cancelado', false, 'promovido', null);
  end if;

  update inscripciones set estado = 'cancelado', orden_en_lista = null
   where id = v_ins.id;

  -- Solo se libera plaza si quien se va estaba dentro, no en la lista.
  if v_ins.estado = 'apuntado' then
    update inscripciones set estado = 'apuntado', orden_en_lista = null
     where id = (select id from inscripciones
                  where quedada_id = p_quedada and estado = 'lista_espera'
                  order by orden_en_lista, created_at
                  limit 1)
    returning practicante_id into v_promovido;
  end if;

  return jsonb_build_object('cancelado', true, 'promovido', v_promovido);
end;
$$;

create or replace function public.cerrar_quedada(p_quedada uuid, p_regenerar boolean default false)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  q          quedadas%rowtype;
  v_yo       uuid;
  v_datos    jsonb;
  v_rank     jsonb;
  v_titulos  jsonb := '[]'::jsonb;
  v_asignado jsonb;
  fila       record;
  usados_p   uuid[] := '{}';
  usados_t   text[] := '{}';
begin
  select * into q from quedadas where id = p_quedada;
  if not found then
    raise exception 'esa quedada no existe' using errcode = 'no_data_found';
  end if;
  if not private.es_admin(q.equipo_id) then
    raise exception 'solo un admin del equipo puede cerrar la quedada'
      using errcode = 'insufficient_privilege';
  end if;
  v_yo := private.practicante_actual();

  -- Congelado: volver a llamar NO recalcula salvo que se pida a proposito.
  if exists (select 1 from quedada_informes where quedada_id = p_quedada)
     and not p_regenerar then
    select datos into v_datos from quedada_informes where quedada_id = p_quedada;
    return v_datos;
  end if;

  -- RANKING por puntos estimados por roll. Es mas honesto que contar
  -- sumisiones: premia a quien domina aunque no finalice, que es justo lo que
  -- se queria medir. Minimo 2 rolls para entrar.
  select coalesce(jsonb_agg(x order by x.media desc), '[]'::jsonb) into v_rank
    from (
      select p.id, p.nombre, p.cinturon::text as cinturon,
             count(*)                                   as rolls,
             round(avg(v.puntos_autor - v.puntos_oponente), 2) as media,
             sum(v.puntos_autor)                        as favor,
             sum(v.puntos_oponente)                     as contra
        from v_puntos_roll v
        join sesiones s on s.id = (select r2.sesion_id from rolls r2 where r2.id = v.roll_id)
        join practicantes p on p.id = v.autor_id
       where s.quedada_id = p_quedada
       group by p.id, p.nombre, p.cinturon
      having count(*) >= 2
    ) x;

  -- TITULOS. Se ordenan todas las parejas (persona, titulo) por cuanto se
  -- desvia esa persona de la media del equipo en esa metrica, y se van
  -- repartiendo sin repetir ni persona ni titulo.
  for fila in
    with m as (select * from private.metricas_quedada(p_quedada)),
    stats as (
      select metrica, avg(valor) as media, coalesce(stddev_pop(valor), 0) as desv
        from m group by metrica
    ),
    z as (
      select m.practicante_id, m.nombre, t.titulo, t.explica, m.valor,
             case when s.desv = 0 then 0
                  else (m.valor - s.media) / s.desv end
             * case when t.mayor then 1 else -1 end as z
        from m
        join stats s on s.metrica = m.metrica
        join private.titulos_disponibles(q.equipo_id in
              (select id from equipos where modo_cachondeo)) t on t.metrica = m.metrica
        join (select practicante_id, valor as rolls from m where metrica = 'rolls') rr
          on rr.practicante_id = m.practicante_id
       -- El umbral de volumen: un ratio con dos intentos no dice nada.
       where m.valor >= t.minimo or t.mayor = false
    )
    select * from z where z > 0 order by z desc, titulo
  loop
    if fila.practicante_id = any(usados_p) or fila.titulo = any(usados_t) then
      continue;
    end if;
    usados_p := usados_p || fila.practicante_id;
    usados_t := usados_t || fila.titulo;
    v_titulos := v_titulos || jsonb_build_object(
      'titulo', fila.titulo, 'practicante_id', fila.practicante_id,
      'quien', fila.nombre, 'porque', fila.explica,
      'valor', round(fila.valor, 2), 'z', round(fila.z, 2));
  end loop;

  -- NADIE SE QUEDA SIN UNO. Si hay mas gente que titulos repartidos, a los que
  -- quedan se les da el titulo que mejor les pegue de los que sobran.
  for fila in
    select distinct m.practicante_id, m.nombre
      from private.metricas_quedada(p_quedada) m
     where not (m.practicante_id = any(usados_p))
  loop
    select jsonb_build_object('titulo', titulo, 'explica', explica) into v_asignado
      from private.titulos_disponibles(false)
     where not (titulo = any(usados_t))
     limit 1;
    exit when v_asignado is null;
    usados_p := usados_p || fila.practicante_id;
    usados_t := usados_t || (v_asignado->>'titulo');
    v_titulos := v_titulos || jsonb_build_object(
      'titulo', v_asignado->>'titulo', 'practicante_id', fila.practicante_id,
      'quien', fila.nombre, 'porque', v_asignado->>'explica', 'valor', null, 'z', 0);
  end loop;

  v_datos := jsonb_build_object(
    'quedada', jsonb_build_object('titulo', q.titulo, 'fecha', q.fecha,
                                  'lugar', q.lugar, 'modalidad', q.modalidad),
    'asistentes', (select count(distinct s.practicante_id)
                     from sesiones s where s.quedada_id = p_quedada),
    'rolls', (select count(*) from rolls r
                join sesiones s on s.id = r.sesion_id
               where s.quedada_id = p_quedada),
    'ranking', v_rank,
    'titulos', v_titulos,
    'generado', now()
  );

  insert into quedada_informes (quedada_id, datos, generado_por)
  values (p_quedada, v_datos, v_yo)
  on conflict (quedada_id)
  do update set datos = excluded.datos, generado_por = excluded.generado_por,
                generado_at = now();

  update quedadas set estado = 'cerrada' where id = p_quedada;

  return v_datos;
end;
$$;

create or replace function public.sesion_del_dia(
  p_practicante uuid, p_fecha date,
  p_modalidad bjj_modalidad default 'gi'::bjj_modalidad,
  p_academia text default null)
returns uuid language plpgsql
set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id
    from sesiones
   where practicante_id = p_practicante
     and fecha = p_fecha
     and modalidad = p_modalidad
   order by created_at
   limit 1;

  if v_id is null then
    insert into sesiones (practicante_id, fecha, modalidad, formato, academia, notas)
    values (p_practicante, p_fecha, p_modalidad, 'sparring', p_academia,
            'Sesion creada automaticamente desde el modo observador')
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

create or replace function public.espejar_roll(p_roll_id uuid)
returns uuid language plpgsql
set search_path = public as $$
declare
  r            rolls%rowtype;
  s            sesiones%rowtype;
  v_sesion     uuid;
  v_nuevo      uuid;
  v_resultado  bjj_resultado_roll;
  v_rol_inicio bjj_rol;
begin
  select * into r from rolls where id = p_roll_id;
  if not found then raise exception 'roll % no existe', p_roll_id; end if;
  if r.oponente_id is null then return null; end if;

  select * into s from sesiones where id = r.sesion_id;

  -- solo se espeja a quien tiene cuenta
  if not (select usa_sistema from practicantes where id = r.oponente_id) then
    return null;
  end if;

  -- no espejar dos veces el mismo roll fisico
  if exists (select 1 from rolls r2
              join sesiones s2 on s2.id = r2.sesion_id
             where r2.par_id = r.par_id
               and s2.practicante_id = r.oponente_id) then
    return null;
  end if;

  v_resultado := case r.resultado
                   when 'sumision_favor'  then 'sumision_contra'
                   when 'sumision_contra' then 'sumision_favor'
                   else r.resultado
                 end;

  -- `rol_inicio` SI se invierte: describe al dueño del roll, que cambia. Si A
  -- empieza en guardia cerrada abajo, B empieza en guardia cerrada arriba.
  -- `posicion_inicio` NO: es fisica y es la misma para los dos.
  v_rol_inicio := case r.rol_inicio
                    when 'arriba' then 'abajo'
                    when 'abajo'  then 'arriba'
                    else 'neutral'
                  end;

  v_sesion := sesion_del_dia(r.oponente_id, s.fecha, r.modalidad, s.academia);

  insert into rolls (sesion_id, oponente_id, orden_en_sesion, modalidad, duracion_min,
                     posicion_inicio, rol_inicio, resultado, intensidad, notas,
                     registrado_por, origen, par_id)
  values (v_sesion, s.practicante_id, r.orden_en_sesion, r.modalidad, r.duracion_min,
          r.posicion_inicio, v_rol_inicio, v_resultado, r.intensidad, r.notas,
          r.registrado_por, r.origen, r.par_id)
  returning id into v_nuevo;

  -- El espejo: solo cambia `actor`. posicion y rol describen al actor, que es
  -- la misma persona fisica en ambas filas.
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       tecnica_id, completado, minuto, segundo_roll, notas,
                       created_at)
  select v_nuevo,
         case actor when 'yo' then 'oponente'::bjj_actor else 'yo'::bjj_actor end,
         tipo, posicion, rol, objetivo, tecnica_id, completado, minuto,
         segundo_roll, notas,
         created_at              -- conserva el orden; ver el comentario de arriba
    from eventos
   where roll_id = p_roll_id
   order by created_at, segundo_roll nulls first, id;

  return v_nuevo;
end;
$$;

-- ---------------------------------------------------------------------------
-- Estas cuatro cambian parametros o tipo de retorno, y eso `create or replace`
-- no lo permite: hay que tirarlas y volver a crearlas. Ninguna esta referenciada
-- por una politica —lo comprobe antes— asi que el drop no arrastra nada.
--
-- Y HAY QUE REVOCAR A `public` EN CADA UNA. Postgres regala EXECUTE a PUBLIC en
-- toda funcion nueva, y `anon` hereda de PUBLIC: recrear una funcion deshace en
-- silencio lo que cerro bjj_25. No es una hipotesis — la primera version de esta
-- migracion dejo `registrar_roll_observado`, `regenerar_codigo`,
-- `quedada_por_token` y `feed` abiertas a anon, y lo cazaron los casos 27 y 48
-- de db/pruebas/rls.sql. Por eso existe esa bateria.
-- ---------------------------------------------------------------------------

drop function public.feed(timestamptz, integer);
create function public.feed(p_antes timestamptz default null, p_limite integer default 30)
returns table (equipo_id uuid, equipo text, tipo_de_elemento text,
               referencia_id uuid, practicante_id uuid, quien text,
               cuando timestamptz, datos jsonb, reacciones jsonb)
language sql stable
set search_path = public as $$
  select f.equipo_id, g.nombre, f.tipo_de_elemento, f.referencia_id, f.practicante_id,
         coalesce(p.nombre, 'alguien'), f.cuando, f.datos,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'emoji', x.emoji, 'cuantos', x.cuantos, 'mia', x.mia))
             from (
               select r.emoji, count(*) as cuantos,
                      bool_or(r.practicante_id = private.practicante_actual()) as mia
                 from reacciones r
                where r.item_tipo = f.tipo_de_elemento and r.referencia_id = f.referencia_id
                group by r.emoji
             ) x
         ), '[]'::jsonb)
    from v_feed f
    join equipos g on g.id = f.equipo_id
    left join practicantes p on p.id = f.practicante_id
   where f.equipo_id in (select private.mis_equipos())
     and (p_antes is null or f.cuando < p_antes)
   order by f.cuando desc
   limit least(coalesce(p_limite, 30), 100)
$$;
revoke all on function public.feed(timestamptz, integer) from public;
grant execute on function public.feed(timestamptz, integer) to authenticated, service_role;

drop function public.quedada_por_token(text);
create function public.quedada_por_token(p_token text)
returns table (id uuid, titulo text, fecha date, hora_inicio time,
               duracion_min smallint, lugar text, plazas_max smallint,
               modalidad bjj_modalidad, estado bjj_estado_quedada,
               equipo text, apuntados bigint, libres integer)
language sql stable security definer
set search_path = public as $$
  select q.id, q.titulo, q.fecha, q.hora_inicio, q.duracion_min,
         q.lugar, q.plazas_max, q.modalidad, q.estado, g.nombre,
         count(i.id) filter (where i.estado = 'apuntado'),
         case when q.plazas_max is null then null
              else q.plazas_max - count(i.id) filter (where i.estado = 'apuntado')::int
         end
    from quedadas q
    join equipos g on g.id = q.equipo_id
    left join inscripciones i on i.quedada_id = q.id
   where q.token_invitacion = p_token
     and q.admite_externos
   group by q.id, g.nombre
$$;
revoke all on function public.quedada_por_token(text) from public;
grant execute on function public.quedada_por_token(text) to authenticated, service_role;

drop function public.regenerar_codigo(uuid);
create function public.regenerar_codigo(p_equipo uuid)
returns text language plpgsql security definer
set search_path = public as $$
declare v_codigo text;
begin
  if not private.es_admin(p_equipo) then
    raise exception 'solo un admin del equipo puede regenerar el codigo'
      using errcode = 'insufficient_privilege';
  end if;
  loop
    select private.nuevo_codigo(nombre) into v_codigo from equipos where id = p_equipo;
    exit when not exists (select 1 from equipos where codigo_union = v_codigo);
  end loop;
  update equipos set codigo_union = v_codigo where id = p_equipo;
  return v_codigo;
end;
$$;
revoke all on function public.regenerar_codigo(uuid) from public;
grant execute on function public.regenerar_codigo(uuid) to authenticated, service_role;

-- El unico renombrado que cruza la red: `p_grupo` -> `p_par`. PostgREST empareja
-- los argumentos POR NOMBRE, y ese nombre viaja serializado dentro de la cola de
-- IndexedDB. Ver la nota sobre la cola en la cabecera.
drop function public.registrar_roll_observado(uuid, uuid, uuid, date, bjj_modalidad,
       smallint, bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb);
create function public.registrar_roll_observado(
  p_par uuid, p_practicante_a uuid, p_practicante_b uuid, p_fecha date,
  p_modalidad bjj_modalidad, p_duracion_min smallint, p_posicion_inicio bjj_posicion,
  p_rol_inicio bjj_rol, p_resultado bjj_resultado_roll, p_eventos jsonb)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_observador uuid;
  v_sesion_a   uuid;
  v_roll_a     uuid;
  v_roll_b     uuid;
  v_academia   text;
  v_orden      smallint;
begin
  -- Quien pulsa los botones. Sin ficha no se registra nada: `registrado_por`
  -- es lo unico que permite auditar quien metio un roll ajeno.
  v_observador := private.practicante_actual();
  if v_observador is null then
    raise exception 'quien registra no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  if p_practicante_a is null or p_practicante_b is null then
    raise exception 'hacen falta los dos practicantes';
  end if;
  if p_practicante_a = p_practicante_b then
    raise exception 'un roll necesita dos personas distintas';
  end if;

  -- Serializa los reintentos del mismo roll.
  perform pg_advisory_xact_lock(hashtextextended(p_par::text, 0));

  -- ---------------------------------------------------------
  -- IDEMPOTENCIA — esto no es opcional
  -- La cola reintenta los envios que no sabe si llegaron. Sin esta
  -- comprobacion, volver del gimnasio sin cobertura duplica el roll.
  -- ---------------------------------------------------------
  select r.id into v_roll_a
    from rolls r
    join sesiones s on s.id = r.sesion_id
   where r.par_id = p_par
     and s.practicante_id = p_practicante_a
   limit 1;

  if v_roll_a is not null then
    select r.id into v_roll_b
      from rolls r
      join sesiones s on s.id = r.sesion_id
     where r.par_id = p_par
       and s.practicante_id = p_practicante_b
     limit 1;
    return jsonb_build_object('roll_a', v_roll_a, 'roll_b', v_roll_b, 'creado', false);
  end if;

  select academia into v_academia from practicantes where id = p_practicante_a;
  if not found then
    raise exception 'el practicante % no existe', p_practicante_a;
  end if;
  if not exists (select 1 from practicantes where id = p_practicante_b) then
    raise exception 'el practicante % no existe', p_practicante_b;
  end if;

  v_sesion_a := sesion_del_dia(p_practicante_a, p_fecha, p_modalidad, v_academia);

  select coalesce(max(orden_en_sesion), 0) + 1 into v_orden
    from rolls where sesion_id = v_sesion_a;

  insert into rolls (sesion_id, oponente_id, orden_en_sesion, modalidad, duracion_min,
                     posicion_inicio, rol_inicio, resultado,
                     registrado_por, origen, par_id)
  values (v_sesion_a, p_practicante_b, v_orden, p_modalidad, p_duracion_min,
          coalesce(p_posicion_inicio, 'de_pie'), coalesce(p_rol_inicio, 'neutral'),
          coalesce(p_resultado, 'no_registrado'),
          v_observador, 'observador', p_par)
  returning id into v_roll_a;

  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       tecnica_id, completado, segundo_roll, minuto, created_at)
  select v_roll_a,
         (x.e->>'actor')::bjj_actor,
         (x.e->>'tipo')::bjj_tipo_evento,
         (x.e->>'posicion')::bjj_posicion,
         (x.e->>'rol')::bjj_rol,
         coalesce(nullif(x.e->>'objetivo', ''), 'ninguno')::bjj_objetivo,
         t.id,
         coalesce((x.e->>'completado')::boolean, true),
         x.seg,
         -- `minuto` se deriva de los segundos y se queda por compatibilidad.
         case when x.seg is not null then least(60, x.seg / 60)::smallint
              else x.min end,
         -- clock_timestamp() avanza dentro de la sentencia (now() no):
         -- conserva el orden en que ocurrieron los eventos.
         clock_timestamp()
    from (
      select e, ord,
             -- Ojo con greatest/least: ignoran los NULL, asi que
             -- greatest(null, 0) devuelve 0. Sin este case, un evento sin
             -- sello acabaria diciendo que paso en el segundo 0.
             case when e->>'segundo_roll' is null then null
                  else least(greatest((e->>'segundo_roll')::int, 0), 3600)::smallint
             end as seg,
             case when e->>'minuto' is null then null
                  else least(greatest((e->>'minuto')::int, 0), 60)::smallint
             end as min
        from jsonb_array_elements(coalesce(p_eventos, '[]'::jsonb))
             with ordinality as a(e, ord)
    ) x
    -- La tecnica llega por slug. Si no esta en el diccionario, el evento entra
    -- igual con tecnica_id null y sigue alimentando el heatmap.
    left join tecnicas t on t.slug = nullif(x.e->>'tecnica_slug', '')
   order by x.ord;

  v_roll_b := espejar_roll(v_roll_a);

  return jsonb_build_object('roll_a', v_roll_a, 'roll_b', v_roll_b, 'creado', true);
end;
$$;
revoke all on function public.registrar_roll_observado(uuid, uuid, uuid, date,
  bjj_modalidad, smallint, bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb) from public;
grant execute on function public.registrar_roll_observado(uuid, uuid, uuid, date,
  bjj_modalidad, smallint, bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb)
  to authenticated, service_role;

-- --------------------------------------- 7 · indices, restricciones, politicas
--
-- Cosmetico y sin riesgo, pero si no se hace queda una tabla `equipos` cuya
-- clave primaria se llama `grupos_pkey`, que es exactamente el tipo de pista
-- falsa que esta migracion viene a quitar. Renombrar una politica NO cambia la
-- politica: la expresion no se toca.
-- Los que respaldan una restriccion van por `rename constraint`, que renombra
-- las dos caras. Con `alter index` se renombraria el indice y la restriccion se
-- quedaria con el nombre viejo: dos nombres para el mismo objeto.
alter table equipos         rename constraint grupos_pkey             to equipos_pkey;
alter table equipos         rename constraint grupos_slug_key         to equipos_slug_key;
alter table equipos         rename constraint grupos_codigo_union_key to equipos_codigo_union_key;
alter table miembros_equipo rename constraint miembros_grupo_pkey     to miembros_equipo_pkey;
alter table equipos         rename constraint grupos_color_acento_chk to equipos_color_acento_chk;
alter table equipos         rename constraint grupos_creado_por_fkey  to equipos_creado_por_fkey;

-- Y estos son indices sueltos.
alter index quedadas_grupo_fecha_idx rename to quedadas_equipo_fecha_idx;
alter index rolls_grupo_idx          rename to rolls_par_idx;
alter index sesiones_grupo_idx       rename to sesiones_equipo_idx;
alter table miembros_equipo rename constraint miembros_grupo_grupo_id_fkey        to miembros_equipo_equipo_id_fkey;
alter table miembros_equipo rename constraint miembros_grupo_practicante_id_fkey  to miembros_equipo_practicante_id_fkey;
alter table quedadas        rename constraint quedadas_grupo_id_fkey  to quedadas_equipo_id_fkey;
alter table sesiones        rename constraint sesiones_grupo_id_fkey  to sesiones_equipo_id_fkey;

alter policy grupos_admin           on equipos rename to equipos_admin;
alter policy grupos_alta            on equipos rename to equipos_alta;
alter policy grupos_lectura         on equipos rename to equipos_lectura;
alter policy quedadas_lectura_grupo on quedadas rename to quedadas_lectura_equipo;
alter policy sesiones_lectura_grupo on sesiones rename to sesiones_lectura_equipo;
alter policy rolls_lectura_grupo    on rolls    rename to rolls_lectura_equipo;
alter policy eventos_lectura_grupo  on eventos  rename to eventos_lectura_equipo;

commit;
