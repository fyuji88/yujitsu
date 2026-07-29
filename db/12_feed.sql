-- ============================================================
--  BJJ TRACKER — Feed de actividad y reacciones   ·   FASE 5
--  Migracion bjj_17. Va despues de 09, 10 y 11.
-- ============================================================
--
--  FEED, NO CHAT. Decidido: feed ahora, chat solo si el feed se queda corto.
--  Aqui no hay mensajeria y no se construye.
--
--  EL FEED ES UNA VISTA, NO UNA TABLA DE ENTRADAS. Nada lo escribe: se deriva
--  de lo que ya pasa. Asi no hay dos verdades que puedan separarse — si se
--  corrige una sesion, el feed se corrige solo, igual que el heatmap.
--
--  Filtrado por private.mis_grupos(), y paginado por `cuando`, no por offset:
--  con offset, si entra algo nuevo mientras lees, la pagina siguiente repite o
--  se salta filas.
-- ============================================================

-- ------------------------------------------------------------
-- USAGE sobre `private` para `authenticated`
--
--  Hasta aqui los helpers de `private` solo se llamaban desde POLITICAS, y una
--  politica puede llamarlos aunque el rol no tenga USAGE sobre el esquema.
--  `feed()` los llama desde el CUERPO de una funcion SECURITY INVOKER, y ahi
--  si hace falta el permiso.
--
--  Esto NO contradice el motivo por el que viven en `private`: ese motivo es
--  que PostgREST solo publica `public`, asi que siguen sin aparecer en
--  /rest/v1/rpc/. Y ninguno de ellos dice nada que el usuario no pueda saber
--  ya: quien eres, en que grupos estas, y que ids alcanzas.
--
--  La alternativa era hacer `feed()` SECURITY DEFINER, y se descarto a
--  proposito: en invoker la RLS de las tablas de debajo sigue actuando como
--  segunda linea. Si un dia el filtro por grupo de la vista tuviera un fallo,
--  en definer no habria nada detras.
-- ------------------------------------------------------------
grant usage on schema private to authenticated, service_role;


-- ------------------------------------------------------------
-- Reacciones
--
--  EL DETALLE QUE HAY QUE ACERTAR: la clave apunta a la FILA DE ORIGEN — el
--  sesion_id, la inscripcion_id, el evento_id — y nunca a una fila del feed.
--  El feed es una vista y sus filas no tienen identidad estable: al cambiar la
--  vista, las reacciones se despegarian de su contenido.
-- ------------------------------------------------------------
create table reacciones (
  id             uuid primary key default gen_random_uuid(),
  practicante_id uuid not null references practicantes(id) on delete cascade,
  item_tipo      text not null,
  referencia_id  uuid not null,
  emoji          text not null,
  created_at     timestamptz not null default now(),
  unique (practicante_id, item_tipo, referencia_id, emoji),
  -- Cerrado a un puñado, no un selector libre: con emoji libre, en un mes hay
  -- cuarenta y ninguno significa nada.
  constraint reacciones_emoji_chk check (emoji in ('🔥', '💪', '😂', '🫡', '🥋'))
);

create index reacciones_item_idx on reacciones (item_tipo, referencia_id);

alter table reacciones enable row level security;

-- Se ven las reacciones de la gente con la que compartes grupo, y se escriben
-- solo las tuyas.
create policy reacciones_lectura on reacciones
  for select to authenticated
  using (practicante_id in (select private.practicantes_visibles()));

create policy reacciones_propias on reacciones
  for all to authenticated
  using (practicante_id = private.practicante_actual())
  with check (practicante_id = private.practicante_actual());


-- ------------------------------------------------------------
-- El feed
--
--  Cada rama trae: de que grupo es, que tipo de cosa, LA FILA DE ORIGEN para
--  poder reaccionar, quien la hizo, cuando, y lo justo para pintarla.
--
--  Falta la rama de "informe publicado": la tabla llega en la fase 4. Se añade
--  entonces, no ahora, para no referenciar algo que no existe.
-- ------------------------------------------------------------
create or replace view v_feed with (security_invoker = on) as

-- Alguien registro una sesion de entreno.
select s.grupo_id,
       'sesion'::text                       as tipo,
       s.id                                 as referencia_id,
       s.practicante_id,
       s.created_at                         as cuando,
       jsonb_build_object(
         'fecha', s.fecha,
         'modalidad', s.modalidad,
         'rolls', (select count(*) from rolls r where r.sesion_id = s.id),
         'quedada', (select q.titulo from quedadas q where q.id = s.quedada_id)
       )                                    as datos
  from sesiones s
 where s.grupo_id is not null
   and exists (select 1 from rolls r where r.sesion_id = s.id)

union all

-- Primera vez que alguien registra algo desde una posicion. Es el hito que de
-- verdad se celebra: "ya juega De la Riva".
select s.grupo_id, 'posicion', primera.evento_id, s.practicante_id, primera.cuando,
       jsonb_build_object('posicion', primera.posicion,
                          'nombre', pos.nombre)
  from (
    select distinct on (s2.practicante_id, e2.posicion)
           s2.practicante_id, e2.posicion,
           e2.id as evento_id, e2.created_at as cuando, r2.sesion_id
      from eventos e2
      join rolls r2    on r2.id = e2.roll_id
      join sesiones s2 on s2.id = r2.sesion_id
     where e2.actor = 'yo'
     order by s2.practicante_id, e2.posicion, e2.created_at
  ) primera
  join sesiones s   on s.id = primera.sesion_id
  join posiciones pos on pos.codigo = primera.posicion
 where s.grupo_id is not null

union all

-- Un reto completado.
select g.id, 'reto', rp.id, rp.practicante_id, rp.created_at,
       jsonb_build_object('reto', re.nombre, 'progreso', rp.progreso)
  from reto_participaciones rp
  join retos re on re.id = rp.reto_id
  join miembros_grupo m on m.practicante_id = rp.practicante_id and m.estado = 'activo'
  join grupos g on g.id = m.grupo_id
 where rp.completado

union all

-- Alguien monto una quedada.
select q.grupo_id, 'quedada', q.id, q.creado_por, q.created_at,
       jsonb_build_object('titulo', q.titulo, 'fecha', q.fecha,
                          'lugar', q.lugar, 'plazas', q.plazas_max)
  from quedadas q
 where q.estado <> 'cancelada'

union all

-- Alguien se apunto. Es lo que convierte una quedada en plan.
select q.grupo_id, 'inscripcion', i.id, i.practicante_id, i.created_at,
       jsonb_build_object('titulo', q.titulo, 'fecha', q.fecha,
                          'externo', i.es_externo)
  from inscripciones i
  join quedadas q on q.id = i.quedada_id
 where i.estado = 'apuntado'

union all

-- Gente nueva en el grupo.
select m.grupo_id, 'miembro', m.grupo_id, m.practicante_id, m.created_at,
       jsonb_build_object('rol', m.rol)
  from miembros_grupo m
 where m.estado = 'activo';


comment on view v_feed is
  'Actividad del grupo, derivada. No hay tabla de entradas: si se corrige una '
  'sesion, el feed se corrige solo. Las reacciones apuntan a la fila de origen '
  '(referencia_id), nunca a una fila de esta vista, que no tiene identidad '
  'estable.';


-- ------------------------------------------------------------
-- Lo que pinta la pantalla: una pagina del feed de tus grupos, con las
-- reacciones ya contadas y sabiendo cuales son tuyas.
--
-- Se pagina con `p_antes`: se piden los N siguientes anteriores a esa marca de
-- tiempo. Con offset, si entra algo nuevo mientras lees, la pagina siguiente
-- repite o se salta filas.
-- ------------------------------------------------------------
create or replace function feed(
  p_antes timestamptz default null,
  p_limite int default 30
) returns table (
  grupo_id       uuid,
  grupo          text,
  tipo           text,
  referencia_id  uuid,
  practicante_id uuid,
  quien          text,
  cuando         timestamptz,
  datos          jsonb,
  reacciones     jsonb
)
language sql
stable
set search_path = public
as $$
  select f.grupo_id, g.nombre, f.tipo, f.referencia_id, f.practicante_id,
         coalesce(p.nombre, 'alguien'), f.cuando, f.datos,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'emoji', x.emoji, 'cuantos', x.cuantos, 'mia', x.mia))
             from (
               select r.emoji, count(*) as cuantos,
                      bool_or(r.practicante_id = private.practicante_actual()) as mia
                 from reacciones r
                where r.item_tipo = f.tipo and r.referencia_id = f.referencia_id
                group by r.emoji
             ) x
         ), '[]'::jsonb)
    from v_feed f
    join grupos g on g.id = f.grupo_id
    left join practicantes p on p.id = f.practicante_id
   where f.grupo_id in (select private.mis_grupos())
     and (p_antes is null or f.cuando < p_antes)
   order by f.cuando desc
   limit least(coalesce(p_limite, 30), 100)
$$;

revoke all on function feed(timestamptz, int) from public, anon;
grant execute on function feed(timestamptz, int) to authenticated;
