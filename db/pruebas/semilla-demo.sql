-- ============================================================
--  SEMILLA DE DEMO — SOLO PARA LA BASE LOCAL
--
--    psql "postgresql://postgres@127.0.0.1:55432/bjj" \
--         -v confirmar=si -f db/pruebas/semilla-demo.sql
--
--  Crea un juego de datos con volumen de verdad para poder recorrer la
--  pantalla de análisis: un roster de Dragon Ball, ~180 rolls repartidos en
--  cuatro meses, con gi y no-gi, rolls propios y observados, y sumisiones a
--  favor y en contra desde posiciones distintas.
--
--  POR QUÉ NOMBRES DE DRAGON BALL. Porque a la primera ojeada se ve que son
--  falsos. Un juego de prueba con nombres realistas acaba confundiéndose con
--  datos de verdad — y peor, acaba en una captura de pantalla enseñando el
--  "head-to-head" de alguien que no existe.
--
--  ES DETERMINISTA. No usa `random()`: todo sale de aritmética modular sobre
--  el número de roll. Dos ejecuciones dan exactamente los mismos números, que
--  es lo que permite que un recorrido en navegador compruebe cantidades.
--
--  BORRA TODO LO QUE HAY. Por eso pide `-v confirmar=si` y por eso se planta
--  si la base no huele a local: si esto se ejecuta contra producción, se lleva
--  por delante los rolls de Felipe y de Pablo.
-- ============================================================
\set ON_ERROR_STOP on

-- El `-v confirmar=si` es una variable de psql, del lado del cliente, y el
-- bloque de abajo corre en el servidor: hay que pasarla. Si no viene, se pone
-- 'no' para que el guardia salte.
\if :{?confirmar}
\else
  \set confirmar no
\endif
select set_config('bjj.confirmar', :'confirmar', false);

do $$
declare
  v_confirmado text := current_setting('bjj.confirmar', true);
begin
  if v_confirmado is distinct from 'si' then
    raise exception
      'Esta semilla BORRA sesiones, rolls y eventos. Ejecuta con -v confirmar=si';
  end if;
  -- Un cinturón de seguridad más, por si el `-v` se copia sin pensar: en
  -- producción hay usuarios de verdad en auth.users.
  if (select count(*) from auth.users) > 3 then
    raise exception
      'Hay % cuentas en auth.users: esto no parece la base local. Semilla abortada.',
      (select count(*) from auth.users);
  end if;
end $$;

begin;

-- ------------------------------------------------------------
-- 1. El roster
--
-- El practicante con cuenta —el que abre la app en las pruebas— es Goku. Los
-- demás son fichas de contacto salvo Vegeta y Piccolo, que tienen cuenta para
-- que el head-to-head cruzado tenga con quién cruzarse.
--
-- Los cinco cinturones están representados a propósito: el recorrido del tema
-- comprueba que los cinco avatares se distinguen en claro y en oscuro.
-- ------------------------------------------------------------
create temporary table semilla_gente (
  n int, nombre text, cinturon bjj_cinturon, grados int, peso numeric, cuenta boolean
) on commit drop;

insert into semilla_gente values
  (0, 'Goku',         'negra',  3, 62, true),    -- el de la cuenta
  (1, 'Vegeta',       'negra',  2, 70, true),
  (2, 'Piccolo',      'marron', 1, 86, true),
  (3, 'Gohan',        'morada', 2, 61, false),
  (4, 'Krilin',       'azul',   3, 45, false),
  (5, 'Ten Shin Han', 'marron', 0, 72, false),
  (6, 'Yamcha',       'azul',   1, 68, false),
  (7, 'Chi-Chi',      'blanca', 1, 50, false),
  (8, 'Bulma',        'blanca', 0, 49, false),   -- sin un solo roll, a propósito
  (9, 'Freezer',      'negra',  4, 56, false);

-- Fuera lo anterior. Las fichas se borran en cascada con sus sesiones.
delete from enfoques;
delete from eventos;
delete from rolls;
delete from sesiones;
delete from practicantes where user_id is null;

-- ------------------------------------------------------------
-- La cuenta con la que entra el navegador.
--
-- La semilla la GARANTIZA en vez de darla por hecha, y no es paranoia:
-- `db/pruebas/puntos.sql` hace `truncate practicantes cascade` y
-- `delete from auth.users` para montar su propio mundo. Después de correrlo el
-- usuario del stub ya no existe, `private.practicante_actual()` devuelve null,
-- y la app abre pero no se reconoce: la colección a cero y el análisis vacío.
-- El síntoma no se parece nada a la causa.
--
-- Este uuid es el que usa `stub-supabase.py` (constante `USER_ID`). Si cambia
-- allí, cambia aquí.
-- ------------------------------------------------------------
insert into auth.users (id, email)
values ('55555555-5555-5555-5555-555555555555', 'e2e@bjjtracker.test')
    on conflict (id) do nothing;

-- Fuera las fichas de otras cuentas que se hayan quedado por el medio, y la
-- que el trigger `bjj_08` acaba de crear para esta.
delete from practicantes where user_id is not null;

insert into practicantes (nombre, cinturon, grados, peso_kg, academia,
                          usa_sistema, user_id)
values ('Goku', 'negra', 3, 62, 'Kame House', true,
        '55555555-5555-5555-5555-555555555555');

insert into practicantes (id, nombre, cinturon, grados, peso_kg, academia, usa_sistema)
select ('dbdb0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       nombre, cinturon, grados, peso, 'Kame House', cuenta
  from semilla_gente where n > 0;

-- Todo el mundo dentro del mismo equipo, EMPEZANDO POR GOKU.
--
-- Y esto es lo que se me olvidó la primera vez: antes la ficha con cuenta se
-- reciclaba, así que ya venía dentro del equipo; ahora se crea de cero y hay
-- que meterla a mano. Sin eso, el usuario del navegador no está en ningún
-- equipo — y la lectura va por equipo, así que la app abre sin ranking, sin
-- acento de marca y con el análisis vacío. Otra vez un síntoma que no se
-- parece a la causa.
--
-- Va de admin porque la pantalla de equipo enseña el código de unión y el botón
-- de regenerarlo solo a los admin, y eso también hay que poder recorrerlo.
delete from miembros_equipo
 where equipo_id = (select id from equipos order by created_at limit 1);

insert into miembros_equipo (equipo_id, practicante_id, rol_en_equipo, estado)
select (select id from equipos order by created_at limit 1), p.id,
       (case when p.user_id is not null then 'admin' else 'miembro' end)::bjj_rol_equipo,
       'activo'
  from practicantes p
 where not exists (select 1 from miembros_equipo m where m.practicante_id = p.id);

-- ------------------------------------------------------------
-- 2. Las sesiones y los rolls de Goku
--
-- 45 sesiones repartidas en 120 días, 4 rolls por sesión = 180 rolls. La
-- modalidad alterna por sesión —nunca `mixto`— para que gi + no-gi sume
-- exactamente el total: es lo que comprueba el recorrido cuando toca el filtro.
-- ------------------------------------------------------------
insert into sesiones (id, practicante_id, fecha, academia, modalidad, formato,
                      duracion_min, equipo_id)
select ('5e510000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       (select id from practicantes where user_id is not null),
       current_date - (i * 8 / 3),                 -- ~2,7 días entre sesiones
       'Kame House',
       (case when i % 2 = 0 then 'gi' else 'nogi' end)::bjj_modalidad,
       (case i % 5 when 0 then 'competicion' when 1 then 'open_mat'
                   else 'sparring' end)::bjj_tipo_sesion,
       60 + (i % 4) * 15,
       (select id from equipos order by created_at limit 1)
  from generate_series(0, 44) i;

-- Un tercio de los rolls van como observados: la pantalla avisa de cuántos lo
-- son, porque registrándote tú faltan sistemáticamente las cosas que no ves.
insert into rolls (id, sesion_id, oponente_id, orden_en_sesion, modalidad, duracion_min,
                   posicion_inicio, rol_inicio, resultado, origen)
select ('401100' || lpad(i::text, 2, '0') || '-0000-0000-0000-' || lpad(j::text, 12, '0'))::uuid,
       ('5e510000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       ('dbdb0000-0000-0000-0000-' || lpad((1 + (i * 4 + j) % 7)::text, 12, '0'))::uuid,
       j + 1,
       (case when i % 2 = 0 then 'gi' else 'nogi' end)::bjj_modalidad,
       5 + (j % 3) * 2,
       (case (i + j) % 4 when 0 then 'de_pie' when 1 then 'guardia_cerrada'
                         when 2 then 'de_pie' else 'media_guardia' end)::bjj_posicion,
       (case (i + j) % 4 when 1 then 'abajo' when 3 then 'arriba'
                         else 'neutral' end)::bjj_rol,
       (case (i * 4 + j) % 5
          when 0 then 'sumision_favor' when 1 then 'sumision_contra'
          else 'sin_sumision' end)::bjj_resultado_roll,
       (case when (i * 4 + j) % 3 = 0 then 'observador' else 'propio' end)::bjj_origen_roll
  from generate_series(0, 44) i, generate_series(0, 3) j;

-- ------------------------------------------------------------
-- 3. Los eventos
--
-- Tres familias, y las tres importan para que la pantalla tenga algo que
-- enseñar:
--   · sumisiones de Goku            → heatmap ofensivo
--   · sumisiones del rival          → heatmap defensivo
--   · barridas, pases y transiciones→ saldo por guardia y puntos
--
-- El reparto sale de `k = i*4 + j`, el número de roll. Nada de `random()`.
-- ------------------------------------------------------------
create temporary table semilla_ataque (n int, pos bjj_posicion, obj bjj_objetivo, slug text)
  on commit drop;
insert into semilla_ataque values
  (0, 'espalda',            'cuello',      'mata_leao'),
  (1, 'montada',            'cuello',      'cruzada'),
  (2, 'cien_kilos',         'hombro',      'kimura'),
  (3, 'guardia_cerrada',    'codo',        'armbar'),
  (4, 'media_guardia',      'rodilla',     'kneebar'),
  (5, 'guardia_abierta',    'tobillo_pie', 'straight_ankle'),
  (6, 'de_la_riva',         'codo',        'omoplata'),
  (7, 'mariposa',           'cuello',      'guillotina'),
  (8, 'norte_sur',          'cuello',      'north_south_choke'),
  (9, 'rodilla_en_barriga', 'codo',        'armbar');

create temporary table semilla_defensa (n int, pos bjj_posicion, obj bjj_objetivo, slug text)
  on commit drop;
insert into semilla_defensa values
  (0, 'montada',         'cuello',      'cruzada'),
  (1, 'espalda',         'cuello',      'mata_leao'),
  (2, 'guardia_cerrada', 'codo',        'armbar'),
  (3, 'cien_kilos',      'hombro',      'americana'),
  (4, 'guardia_abierta', 'tobillo_pie', 'heel_hook'),
  (5, 'media_guardia',   'rodilla',     'kneebar'),
  (6, 'tortuga',         'cuello',      'guillotina');

-- El REPARTO, que es lo que le da forma al heatmap.
--
-- Con un `k % 10` todas las celdas salen iguales y el mapa queda plano: bonito
-- de programar, inútil de mirar. Un practicante de verdad tiene un juego —dos o
-- tres sitios donde vive y muchos donde apenas pasa—, así que el reparto va
-- pesado. Goku ataca la espalda y la montada, y casi nunca las piernas.
create temporary table semilla_reparto_off (slot int, n int) on commit drop;
insert into semilla_reparto_off
select slot,
       case
         when slot < 9  then 0    -- espalda / cuello       ← su juego
         when slot < 16 then 1    -- montada / cuello
         when slot < 21 then 2    -- cien kilos / hombro
         when slot < 25 then 3    -- guardia cerrada / codo
         when slot < 27 then 6    -- de la riva / codo
         when slot < 29 then 8    -- norte-sur / cuello
         else 4                   -- media guardia / rodilla ← lo que no toca
       end
  from generate_series(0, 29) slot;

-- Lo que le hacen a él tiene otra forma: le pillan la espalda y la montada,
-- que es lo típico de quien juega arriba y a veces se pasa de largo.
create temporary table semilla_reparto_def (slot int, n int) on commit drop;
insert into semilla_reparto_def
select slot,
       case
         when slot < 7  then 0    -- montada / cuello
         when slot < 12 then 1    -- espalda / cuello
         when slot < 15 then 2    -- guardia cerrada / codo
         when slot < 17 then 4    -- guardia abierta / tobillo
         when slot < 18 then 3    -- cien kilos / hombro
         else 6                   -- tortuga / cuello
       end
  from generate_series(0, 19) slot;

-- 3a. Ataques de Goku. Uno por roll, y un segundo en uno de cada tres.
insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id,
                     completado, segundo_roll)
select r.id, 'yo', 'sumision', a.pos,
       (case when a.pos in ('guardia_cerrada','media_guardia','de_la_riva',
                            'mariposa','guardia_abierta') then 'abajo'
             else 'arriba' end)::bjj_rol,
       a.obj, t.id,
       -- Uno de cada tres intentos no entra. Los fallados son la mitad del
       -- valor del heatmap: dicen dónde lo intentas y no te sale.
       (k % 3 <> 1),
       40 + (k % 7) * 25
  from (
    select r.id, (row_number() over (order by s.fecha, r.orden))::int - 1 as k
      from rolls r join sesiones s on s.id = r.sesion_id
     where s.practicante_id = (select id from practicantes where user_id is not null)
  ) r
  join semilla_reparto_off w on w.slot = r.k % 30
  join semilla_ataque a on a.n = w.n
  join tecnicas t on t.slug = a.slug;

insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id,
                     completado, segundo_roll)
select r.id, 'yo', 'sumision', a.pos,
       (case when a.pos in ('guardia_cerrada','media_guardia','de_la_riva',
                            'mariposa','guardia_abierta') then 'abajo'
             else 'arriba' end)::bjj_rol,
       a.obj, t.id, (k % 4 <> 2), 120 + (k % 5) * 20
  from (
    select r.id, (row_number() over (order by s.fecha, r.orden))::int - 1 as k
      from rolls r join sesiones s on s.id = r.sesion_id
     where s.practicante_id = (select id from practicantes where user_id is not null)
  ) r
  join semilla_reparto_off w on w.slot = (r.k * 7 + 3) % 30
  join semilla_ataque a on a.n = w.n
  join tecnicas t on t.slug = a.slug
 where r.k % 3 = 0;

-- 3b. Lo que le hacen a Goku.
insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id,
                     completado, segundo_roll)
select r.id, 'oponente', 'sumision', d.pos,
       (case when d.pos in ('guardia_cerrada','media_guardia','guardia_abierta')
             then 'abajo' else 'arriba' end)::bjj_rol,
       d.obj, t.id, (k % 5 <> 3), 70 + (k % 6) * 30
  from (
    select r.id, (row_number() over (order by s.fecha, r.orden))::int - 1 as k
      from rolls r join sesiones s on s.id = r.sesion_id
     where s.practicante_id = (select id from practicantes where user_id is not null)
  ) r
  join semilla_reparto_def w on w.slot = r.k % 20
  join semilla_defensa d on d.n = w.n
  join tecnicas t on t.slug = d.slug
 where r.k % 2 = 0;

-- 3c. Lo que no es sumisión: barridas, pases y transiciones. Sin esto el saldo
--     por guardia y el marcador salen vacíos.
insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, completado, segundo_roll)
select r.id,
       (case when k % 2 = 0 then 'yo' else 'oponente' end)::bjj_actor,
       (case k % 4 when 0 then 'barrida' when 1 then 'pase_guardia'
                   when 2 then 'transicion' else 'derribo' end)::bjj_tipo_evento,
       (case k % 4
          when 0 then (case k % 3 when 0 then 'guardia_cerrada'
                                  when 1 then 'media_guardia' else 'mariposa' end)
          when 1 then (case k % 3 when 0 then 'guardia_cerrada'
                                  when 1 then 'de_la_riva' else 'guardia_abierta' end)
          when 2 then (case k % 3 when 0 then 'montada'
                                  when 1 then 'rodilla_en_barriga' else 'norte_sur' end)
          else 'de_pie' end)::bjj_posicion,
       (case k % 4 when 0 then 'abajo' when 1 then 'arriba'
                   when 2 then 'arriba' else 'neutral' end)::bjj_rol,
       'ninguno', true, 30 + (k % 8) * 22
  from (
    select r.id, (row_number() over (order by s.fecha, r.orden))::int - 1 as k
      from rolls r join sesiones s on s.id = r.sesion_id
     where s.practicante_id = (select id from practicantes where user_id is not null)
  ) r;

-- ------------------------------------------------------------
-- 4. Un poco de historia para Vegeta y Piccolo
--
-- El selector del análisis tiene que poder cambiar a alguien con datos, y no
-- solo a fichas vacías. Bulma se queda sin nada a propósito: es la que prueba
-- el estado vacío.
-- ------------------------------------------------------------
insert into sesiones (id, practicante_id, fecha, academia, modalidad, formato,
                      duracion_min, equipo_id)
select ('5e520000-0000-000' || g.n::text || '-0000-' || lpad(i::text, 12, '0'))::uuid,
       ('dbdb0000-0000-0000-0000-' || lpad(g.n::text, 12, '0'))::uuid,
       current_date - (i * 5), 'Kame House',
       (case when i % 2 = 0 then 'nogi' else 'gi' end)::bjj_modalidad,
       'sparring', 75,
       (select id from equipos order by created_at limit 1)
  from semilla_gente g, generate_series(0, 11) i
 where g.n in (1, 2);

insert into rolls (id, sesion_id, oponente_id, orden_en_sesion, modalidad, duracion_min,
                   posicion_inicio, rol_inicio, resultado, origen)
select ('40220' || g.n::text || lpad(i::text, 2, '0') || '-0000-0000-0000-' || lpad(j::text, 12, '0'))::uuid,
       ('5e520000-0000-000' || g.n::text || '-0000-' || lpad(i::text, 12, '0'))::uuid,
       (select id from practicantes where user_id is not null),
       j + 1,
       (case when i % 2 = 0 then 'nogi' else 'gi' end)::bjj_modalidad,
       6, 'de_pie', 'neutral',
       (case (i + j) % 3 when 0 then 'sumision_favor'
                         when 1 then 'sumision_contra'
                         else 'sin_sumision' end)::bjj_resultado_roll,
       'propio'
  from semilla_gente g, generate_series(0, 11) i, generate_series(0, 2) j
 where g.n in (1, 2);

insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo, tecnica_id,
                     completado, segundo_roll)
select r.id,
       (case when k % 2 = 0 then 'yo' else 'oponente' end)::bjj_actor,
       'sumision', a.pos,
       (case when a.pos in ('guardia_cerrada','media_guardia','de_la_riva',
                            'mariposa','guardia_abierta') then 'abajo'
             else 'arriba' end)::bjj_rol,
       a.obj, t.id, (k % 4 <> 1), 60 + (k % 5) * 25
  from (
    select r.id, (row_number() over (order by s.practicante_id, s.fecha, r.orden))::int - 1 as k
      from rolls r join sesiones s on s.id = r.sesion_id
     where s.practicante_id in ('dbdb0000-0000-0000-0000-000000000001'::uuid,
                                'dbdb0000-0000-0000-0000-000000000002'::uuid)
  ) r
  join semilla_reparto_off w on w.slot = r.k % 30
  join semilla_ataque a on a.n = w.n
  join tecnicas t on t.slug = a.slug;

commit;

-- ------------------------------------------------------------
-- Lo que ha quedado. Estos números son los que puede dar por buenos un
-- recorrido en navegador: son deterministas.
-- ------------------------------------------------------------
\echo ''
\echo '######## SEMILLA DE DEMO ########'
select p.nombre, p.cinturon, p.grados,
       count(distinct s.id) as sesiones,
       count(distinct r.id) as rolls,
       count(e.id)          as eventos
  from practicantes p
  left join sesiones s on s.practicante_id = p.id
  left join rolls r on r.sesion_id = s.id
  left join eventos e on e.roll_id = r.id
 group by p.id, p.nombre, p.cinturon, p.grados
 order by rolls desc, p.nombre;
