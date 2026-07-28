-- ============================================================
--  BJJ TRACKER — Esquema Postgres / Supabase
--  Bloque 0 · v1.0
--  Pegar en Supabase → SQL Editor → Run
-- ============================================================

-- ------------------------------------------------------------
-- 1. VOCABULARIO (enums) — el contrato entre Felipe y Pablo
-- ------------------------------------------------------------

create type bjj_cinturon as enum (
  'blanca','azul','morada','marron','negra'
);

create type bjj_modalidad as enum (
  'gi','nogi','mixto'
);

create type bjj_tipo_sesion as enum (
  'tecnica','drilling','sparring','open_mat','competicion','privada'
);

-- El actor es relativo al autor del roll:
--   'yo'       = el practicante que registra la sesion
--   'oponente' = con quien rodo
create type bjj_actor as enum (
  'yo','oponente'
);

-- Posicion FISICA (no depende de quien esta arriba)
create type bjj_posicion as enum (
  -- neutral
  'de_pie','clinch',
  -- guardias
  'guardia_cerrada','media_guardia','mariposa','de_la_riva','de_la_riva_inversa',
  'arana','lasso','collar_manga','x_guard','single_leg_x','guardia_sentada',
  'cincuenta_cincuenta','guardia_abierta',
  -- dominantes / control
  'montada','cien_kilos','kesa_gatame','norte_sur','rodilla_en_barriga','espalda','tortuga',
  -- transicion
  'scramble','otra'
);

-- Rol del ACTOR dentro de esa posicion.
-- Ej: posicion='guardia_cerrada' + rol='abajo'  -> jugando la guardia
--     posicion='guardia_cerrada' + rol='arriba' -> intentando pasarla
create type bjj_rol as enum (
  'arriba','abajo','neutral'
);

create type bjj_grupo_posicion as enum (
  'neutral','guardia','dominante','transicion'
);

-- Objetivo articular del ataque (columnas del heatmap)
create type bjj_objetivo as enum (
  'cuello','hombro','codo','muneca','biceps','columna','cadera',
  'rodilla','tobillo_pie','pantorrilla','ninguno'
);

-- Tipo de evento. Un intento fallido = tipo='sumision' + completado=false
create type bjj_tipo_evento as enum (
  'sumision','barrida','pase_guardia','derribo','toma_espalda','escape'
);

-- 'sin_sumision' = el roll acabo sin que nadie tocase. No es un "empate":
-- el saldo posicional del roll sale de los eventos, no de este campo.
-- Si ya ejecutaste una version anterior con 'tablas':
--   alter type bjj_resultado_roll rename value 'tablas' to 'sin_sumision';
create type bjj_resultado_roll as enum (
  'sumision_favor','sumision_contra','sin_sumision','no_registrado'
);

create type bjj_tipo_regla as enum (
  'solo_objetivo','solo_posicion','solo_tecnica','solo_tipo_evento','conteo_libre'
);


-- ------------------------------------------------------------
-- 2. PRACTICANTES
-- ------------------------------------------------------------
create table practicantes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid unique references auth.users(id) on delete set null,
  nombre       text not null,
  apodo        text,
  cinturon     bjj_cinturon not null default 'blanca',
  grados       smallint not null default 0 check (grados between 0 and 4),
  peso_kg      numeric(5,1) check (peso_kg > 0 and peso_kg < 300),
  academia     text,
  usa_sistema  boolean not null default false,  -- true = tiene cuenta -> H2H cruzado
  -- quien dio de alta esta ficha. Solo relevante para companeros sin cuenta:
  -- sin esto no se puede anadir a nadie que no sea uno mismo (la politica de
  -- escritura exigia user_id = auth.uid()).
  creado_por   uuid references auth.users(id) on delete set null default auth.uid(),
  created_at   timestamptz not null default now()
);

comment on column practicantes.usa_sistema is
  'Si true, este oponente tambien loguea: se puede cruzar el head-to-head y compartir retos.';


-- ------------------------------------------------------------
-- 3. DICCIONARIO DE POSICIONES (referencia, no enum-duplicado)
--    Permite "que guardia me funciona mejor" sin un segundo enum.
-- ------------------------------------------------------------
create table posiciones (
  codigo      bjj_posicion primary key,
  nombre      text not null,
  grupo       bjj_grupo_posicion not null,
  es_guardia  boolean generated always as (grupo = 'guardia') stored,
  core_v1     boolean not null default false  -- subconjunto reducido para Sprint 0
);


-- ------------------------------------------------------------
-- 4. DICCIONARIO DE TECNICAS
-- ------------------------------------------------------------
create table tecnicas (
  id                uuid primary key default gen_random_uuid(),
  slug              text unique not null,          -- 'mata_leao'
  nombre            text not null,                 -- 'Mata leao'
  alias             text[] not null default '{}',  -- {'RNC','rear naked choke','estrangulamento pelas costas'}
  tipo              bjj_tipo_evento not null,
  objetivo_default  bjj_objetivo,
  solo_gi           boolean not null default false,
  created_at        timestamptz not null default now()
);

create index tecnicas_alias_idx on tecnicas using gin (alias);


-- ------------------------------------------------------------
-- 5. SESIONES (1 por entrenamiento)
-- ------------------------------------------------------------
create table sesiones (
  id              uuid primary key default gen_random_uuid(),
  practicante_id  uuid not null references practicantes(id) on delete cascade,
  fecha           date not null default current_date,
  academia        text,
  modalidad       bjj_modalidad not null default 'gi',
  tipo            bjj_tipo_sesion not null default 'sparring',
  duracion_min    smallint check (duracion_min between 0 and 400),
  tematica        text,                                   -- "pases de media guardia"
  energia         smallint check (energia between 1 and 5),
  animo           smallint check (animo between 1 and 5),
  molestias       text,                                   -- texto libre, opcional
  notas           text,
  created_at      timestamptz not null default now()
);

create index sesiones_practicante_fecha_idx on sesiones (practicante_id, fecha desc);


-- ------------------------------------------------------------
-- 6. ROLLS (1 por asalto)
-- ------------------------------------------------------------
create table rolls (
  id               uuid primary key default gen_random_uuid(),
  sesion_id        uuid not null references sesiones(id) on delete cascade,
  oponente_id      uuid references practicantes(id) on delete set null,
  orden            smallint,                              -- 1er roll, 2o roll...
  modalidad        bjj_modalidad not null default 'gi',
  duracion_min     smallint check (duracion_min between 0 and 60),
  posicion_inicio  bjj_posicion not null default 'de_pie',
  rol_inicio       bjj_rol not null default 'neutral',
  resultado        bjj_resultado_roll not null default 'no_registrado',
  autovaloracion   smallint check (autovaloracion between 1 and 5),
  intensidad       smallint check (intensidad between 1 and 5),
  notas            text,
  created_at       timestamptz not null default now()
);

create index rolls_sesion_idx   on rolls (sesion_id);
create index rolls_oponente_idx on rolls (oponente_id);


-- ------------------------------------------------------------
-- 7. EVENTOS  ← LA TABLA ESTRELLA
--    Todo el analisis (heatmaps, guardias, H2H, retos) sale de aqui.
-- ------------------------------------------------------------
create table eventos (
  id          uuid primary key default gen_random_uuid(),
  roll_id     uuid not null references rolls(id) on delete cascade,
  actor       bjj_actor not null,
  tipo        bjj_tipo_evento not null,
  posicion    bjj_posicion not null,
  rol         bjj_rol not null,
  objetivo    bjj_objetivo not null default 'ninguno',
  tecnica_id  uuid references tecnicas(id) on delete set null,
  completado  boolean not null default true,   -- false = intento fallado
  minuto      smallint check (minuto between 0 and 60),
  notas       text,
  created_at  timestamptz not null default now(),

  -- una sumision siempre apunta a una articulacion
  constraint eventos_sumision_objetivo_chk
    check (tipo <> 'sumision' or objetivo <> 'ninguno')
);

create index eventos_roll_idx     on eventos (roll_id);
create index eventos_heatmap_idx  on eventos (actor, tipo, posicion, objetivo);
create index eventos_tecnica_idx  on eventos (tecnica_id);


-- ------------------------------------------------------------
-- 8. RETOS (gamificacion)
-- ------------------------------------------------------------
create table retos (
  id                uuid primary key default gen_random_uuid(),
  creador_id        uuid not null references practicantes(id) on delete cascade,
  nombre            text not null,
  descripcion       text,
  tipo_regla        bjj_tipo_regla not null,
  -- regla declarativa; el filtro se aplica sobre eventos.
  -- ej: {"objetivo":"hombro"} | {"posicion":"de_la_riva","rol":"abajo"}
  regla             jsonb not null default '{}'::jsonb,
  objetivo_cantidad smallint not null default 1 check (objetivo_cantidad > 0),
  fecha_inicio      date not null default current_date,
  fecha_fin         date not null,
  created_at        timestamptz not null default now(),
  constraint retos_fechas_chk check (fecha_fin >= fecha_inicio)
);

create table reto_participaciones (
  id              uuid primary key default gen_random_uuid(),
  reto_id         uuid not null references retos(id) on delete cascade,
  practicante_id  uuid not null references practicantes(id) on delete cascade,
  progreso        smallint not null default 0,
  completado      boolean not null default false,
  created_at      timestamptz not null default now(),
  unique (reto_id, practicante_id)
);


-- ------------------------------------------------------------
-- 9. RLS — cada uno ve lo suyo, los retos son compartidos
-- ------------------------------------------------------------
alter table practicantes         enable row level security;
alter table posiciones           enable row level security;
alter table tecnicas             enable row level security;
alter table sesiones             enable row level security;
alter table rolls                enable row level security;
alter table eventos              enable row level security;
alter table retos                enable row level security;
alter table reto_participaciones enable row level security;

-- helper: id del practicante logueado.
-- Vive fuera de `public` a proposito: PostgREST solo publica `public`, y una
-- funcion SECURITY DEFINER expuesta en /rest/v1/rpc/ es un aviso del linter.
create schema if not exists private;

create or replace function private.practicante_actual()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from practicantes where user_id = auth.uid()
$$;

revoke all on function private.practicante_actual() from public;
grant execute on function private.practicante_actual() to anon, authenticated, service_role;

create policy practicantes_lectura on practicantes
  for select using (true);                         -- el roster es comun (nombre/cinturon)

-- los diccionarios son de solo lectura para todo el mundo
create policy posiciones_lectura on posiciones for select using (true);
create policy tecnicas_lectura   on tecnicas   for select using (true);

-- Puedo crear mi propia ficha, o la de un companero que no usa la app.
create policy practicantes_insert on practicantes
  for insert to authenticated
  with check (
    user_id = auth.uid()                                 -- mi ficha
    or (user_id is null and creado_por = auth.uid())     -- un companero
  );

-- Puedo editar mi ficha y las de los companeros que yo di de alta.
-- Nunca la ficha de alguien que tiene cuenta propia.
create policy practicantes_update on practicantes
  for update to authenticated
  using (
    user_id = auth.uid()
    or (user_id is null and creado_por = auth.uid())
  )
  with check (
    user_id = auth.uid()
    or (user_id is null and creado_por = auth.uid())
  );

-- Borrar solo companeros que yo cree. Tu propia ficha no se borra desde aqui.
create policy practicantes_delete on practicantes
  for delete to authenticated
  using (user_id is null and creado_por = auth.uid());

create policy sesiones_propias on sesiones
  for all using (practicante_id = private.practicante_actual())
  with check (practicante_id = private.practicante_actual());

create policy rolls_propios on rolls
  for all using (
    sesion_id in (select id from sesiones where practicante_id = private.practicante_actual())
  )
  with check (
    sesion_id in (select id from sesiones where practicante_id = private.practicante_actual())
  );

create policy eventos_propios on eventos
  for all using (
    roll_id in (
      select r.id from rolls r
      join sesiones s on s.id = r.sesion_id
      where s.practicante_id = private.practicante_actual()
    )
  )
  with check (
    roll_id in (
      select r.id from rolls r
      join sesiones s on s.id = r.sesion_id
      where s.practicante_id = private.practicante_actual()
    )
  );

create policy retos_lectura on retos for select using (true);
create policy retos_escritura on retos
  for all using (creador_id = private.practicante_actual())
  with check (creador_id = private.practicante_actual());

create policy participaciones_lectura on reto_participaciones for select using (true);
create policy participaciones_escritura on reto_participaciones
  for all using (practicante_id = private.practicante_actual())
  with check (practicante_id = private.practicante_actual());


-- ------------------------------------------------------------
-- 10. FK DIFERIDAS
--     `rolls.oponente_id` es ON DELETE SET NULL y `sesiones.practicante_id`
--     es ON DELETE CASCADE. Al borrar un practicante, Postgres intenta poner
--     a null el oponente de un roll que por el otro camino ya esta borrado,
--     y falla al re-validar la FK de la sesion. Difiriendo la comprobacion
--     al final de la transaccion deja de importar el orden del borrado.
-- ------------------------------------------------------------
alter table rolls
  alter constraint rolls_sesion_id_fkey deferrable initially deferred;

alter table eventos
  alter constraint eventos_roll_id_fkey deferrable initially deferred;
