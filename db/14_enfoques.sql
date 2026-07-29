-- ============================================================
--  BJJ TRACKER — Enfoques   ·   FASE 6
--  Migracion bjj_19. Va despues de 09..13.
-- ============================================================
--
--  Lo que cada uno esta trabajando estas semanas. CON HISTORIAL, no un campo
--  que se pisa: saber que en mayo estuviste con De la Riva y en junio con
--  media guardia es la mitad de lo que hace util esto.
--
--  Y LA OTRA MITAD: como las posiciones y las tecnicas van ESTRUCTURADAS y no
--  solo en texto libre, la ficha puede contrastar lo que dijiste con lo que
--  hiciste:
--
--    "Dijiste que ibas a jugar De la Riva. La has usado en 2 de 34 rolls."
--
--  Ese contraste es la razon de la feature. Con solo texto libre no existe —
--  pero el texto libre se queda igualmente, porque el matiz ("trabajar la
--  presion, no correr") no cabe en un array de enums.
-- ============================================================

create table enfoques (
  id             uuid primary key default gen_random_uuid(),
  practicante_id uuid not null references practicantes(id) on delete cascade,
  desde          date not null default current_date,
  hasta          date,                       -- null = sigue activo
  texto          text,
  posiciones     bjj_posicion[] not null default '{}',
  tecnicas       uuid[]         not null default '{}',
  created_at     timestamptz not null default now(),
  constraint enfoques_fechas_chk check (hasta is null or hasta >= desde)
);

create index enfoques_practicante_idx on enfoques (practicante_id, desde desc);

alter table enfoques enable row level security;

-- Se leen los de la gente con la que compartes grupo: el sentido es que el
-- companero sepa que estas trabajando, y el coach tambien.
create policy enfoques_lectura on enfoques
  for select to authenticated
  using (practicante_id in (select private.practicantes_visibles()));

create policy enfoques_propios on enfoques
  for all to authenticated
  using (practicante_id = private.practicante_actual())
  with check (practicante_id = private.practicante_actual());

comment on table enfoques is
  'Lo que alguien esta trabajando, con historial. `posiciones` y `tecnicas` van '
  'estructuradas para poder contrastar lo dicho con lo hecho; `texto` se queda '
  'para el matiz que no cabe en un enum.';


-- ------------------------------------------------------------
-- El contraste: lo que dijiste contra lo que hiciste
--
--  Se mira solo el periodo del enfoque, y solo lo que hizo esa persona
--  (actor = 'yo'). Se cuenta por ROLLS y no por eventos: "la has usado en 2 de
--  34 rolls" se entiende; "tienes 3 eventos en De la Riva" no dice nada.
-- ------------------------------------------------------------
create or replace function enfoque_contraste(p_practicante uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  with activo as (
    select * from enfoques
     where practicante_id = p_practicante
       -- Activo es SIN FECHA DE FIN, no "que llegue hasta hoy". Con la otra
       -- regla, darlo por terminado ponia `hasta` = hoy y el enfoque seguia
       -- saliendo como activo el resto del dia: el boton no hacia lo que dice.
       -- Asi ademas `hasta` no necesita pinzas (ni `max(desde, ayer)` ni casos
       -- especiales para el que empezo hoy) y el periodo guardado es verdad:
       -- desde el dia que lo escribiste hasta el dia que lo cerraste.
       and hasta is null
     -- Deberia haber uno solo abierto. El desempate es un seguro para que, si
     -- alguna vez hay dos, cual sale no sea cuestion de suerte.
     order by desde desc, created_at desc
     limit 1
  ),
  periodo as (
    select a.*, a.desde as ini, coalesce(a.hasta, current_date) as fin from activo a
  ),
  rolls_p as (
    select r.id
      from rolls r
      join sesiones s on s.id = r.sesion_id
      join periodo p on true
     where s.practicante_id = p_practicante
       and s.fecha between p.ini and p.fin
  ),
  ev as (
    select e.* from eventos e join rolls_p rp on rp.id = e.roll_id
     where e.actor = 'yo'
  )
  select case when not exists (select 1 from periodo) then null else
    jsonb_build_object(
      'enfoque', (select jsonb_build_object(
                    'id', id, 'desde', desde, 'hasta', hasta, 'texto', texto,
                    'posiciones', to_jsonb(posiciones), 'tecnicas', to_jsonb(tecnicas))
                    from periodo),
      'rolls', (select count(*) from rolls_p),
      'posiciones', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'codigo', x.codigo, 'nombre', pos.nombre, 'rolls', x.rolls))
          from (
            select c.codigo,
                   (select count(distinct e.roll_id) from ev e
                     where e.posicion = c.codigo) as rolls
              from periodo p, unnest(p.posiciones) as c(codigo)
          ) x
          join posiciones pos on pos.codigo = x.codigo
      ), '[]'::jsonb),
      'tecnicas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'nombre', t.nombre, 'veces', x.veces))
          from (
            select c.id,
                   (select count(*) from ev e where e.tecnica_id = c.id) as veces
              from periodo p, unnest(p.tecnicas) as c(id)
          ) x
          join tecnicas t on t.id = x.id
      ), '[]'::jsonb)
    )
  end
$$;

revoke all on function enfoque_contraste(uuid) from public, anon;
grant execute on function enfoque_contraste(uuid) to authenticated;

comment on function enfoque_contraste(uuid) is
  'Lo que dijiste contra lo que hiciste, en el periodo del enfoque activo. Se '
  'cuenta por rolls y no por eventos porque "2 de 34 rolls" se entiende y '
  '"3 eventos en De la Riva" no.';
