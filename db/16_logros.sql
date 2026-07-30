-- ============================================================
--  BJJ TRACKER — Logros   ·   Migracion bjj_21
-- ============================================================
--
--  Un catalogo fijo de hazañas que se ganan registrando rolls. No son los
--  retos otra vez: los retos los define una persona con una regla libre, una
--  ventana y un objetivo, y su progreso se GUARDA en reto_participaciones.
--  Los logros son catalogo cerrado, sin ventana, sin objetivo, y se DERIVAN.
--
--  NADA SE GUARDA. Ni contadores ni tabla de "conseguidos". Igual que los
--  puntos y que el heatmap: si mañana se corrige un evento mal registrado, los
--  logros se corrigen solos. Un contador guardado se queda viejo y nadie se
--  entera. Con este volumen el coste es irrelevante; si algun dia molesta, se
--  materializa la vista — pero no se guarda un contador a mano.
--
--  EL AMBITO NO ES DECORATIVO. Un logro de ambito `roll` se evalua roll a
--  roll; uno de `quedada` necesita todos los rolls de esa quedada; uno de
--  `semana` o `mes`, la ventana entera. "Veces conseguido" es el numero de
--  INSTANCIAS DEL AMBITO en las que el predicado se cumplio, nunca el numero
--  de eventos. `ref_id` es esa instancia: el roll, la quedada, o la fecha en
--  que empieza la semana o el mes.
--
--  LA REGLA DEL SESGO. Los datos autoregistrados estan sesgados a favor de
--  quien registra: no ves tu propia espalda y no recuerdas los intentos que
--  fallaste. Pero el sesgo no afecta a todos los logros igual, y ahi esta la
--  clave: los que se definen por la AUSENCIA de algo se inflan solos con no
--  registrar el evento; los que se definen por algo que PASO, no. IMPASABLE se
--  consigue gratis olvidandose de apuntar el pase; RELAMPAGO exigio registrar
--  la sumision. Por eso `requiere_observador` marca solo 5 de 27, y solo esos
--  cuentan en rolls con `origen = 'observador'`.
-- ============================================================

create type bjj_familia_logro as enum
  ('defensa', 'ataque', 'estilo', 'constancia', 'cachondeo');
create type bjj_rareza_logro as enum ('comun', 'poco_comun', 'raro');
create type bjj_ambito_logro as enum ('roll', 'quedada', 'semana', 'mes');

-- ------------------------------------------------------------
-- El catalogo. Es CATALOGO, no datos de usuario: lo escribe una migracion y
-- lo lee todo el mundo.
--
-- El `nombre` esta aqui por comodidad al depurar, pero la interfaz NO lo usa:
-- el nombre visible sale de `src/lib/textos/logros.es.ts`. Cambiar de idioma
-- tiene que ser editar un fichero, no aplicar una migracion.
-- ------------------------------------------------------------
create table logros (
  clave               text primary key,
  nombre              text not null,
  descripcion         text not null,
  descripcion_tecnica text not null,
  familia             bjj_familia_logro not null,
  rareza              bjj_rareza_logro  not null,
  ambito              bjj_ambito_logro  not null,
  requiere_observador boolean not null default false,
  solo_nogi           boolean not null default false,
  min_volumen         jsonb   not null default '{}'
);

alter table logros enable row level security;

-- Catalogo publico para quien tenga cuenta. La escritura no tiene politica:
-- solo entra por migracion.
create policy logros_lectura on logros
  for select to authenticated using (true);

comment on table logros is
  'Catalogo fijo de logros. El nombre visible sale del fichero de textos, no '
  'de aqui: cambiar de idioma es editar un fichero, no migrar. Nada de datos '
  'de usuario — los conseguidos se derivan en v_logros_conseguidos.';
comment on column logros.min_volumen is
  'La guarda de volumen. IMPASABLE en un roll donde nunca jugaste guardia es '
  'falso, y un 100 % con un intento es mentira. Va en el catalogo y no '
  'repartida por el codigo.';
comment on column logros.requiere_observador is
  'Los logros de AUSENCIA se inflan solos con no registrar el evento, asi que '
  'solo cuentan si el roll lo registro un tercero.';

-- ------------------------------------------------------------
-- El catalogo, tal cual viene de docs/logros-catalogo.sql.
--
-- FALTA UNO A PROPOSITO: `el_ultimo_en_irse`. Su predicado es "el roll
-- con el mayor orden de la quedada es del practicante", y `rolls.orden`
-- es el orden DENTRO DE LA SESION de cada uno, no de la quedada: cada
-- persona numera los suyos 1..n. Asi que el logro no premia irse el
-- ultimo, premia haber rodado mas veces —y eso ya lo cuenta EL NOTARIO—,
-- y empata a todo el que llegue al mismo numero. No se reinterpreta: se
-- deja fuera hasta que Felipe cierre que quiere medir. Un logro mal
-- definido que ya esta contando en el ranking de alguien es peor que un
-- logro que falta.
-- ------------------------------------------------------------
insert into logros
  (clave, nombre, descripcion, familia, rareza, ambito, requiere_observador, solo_nogi,
   min_volumen, descripcion_tecnica) values

-- ---------- DEFENSA ----------
('impasable', 'IMPASABLE', 'Ningún pase de guardia encajado en el roll',
 'defensa', 'comun', 'roll', true, false,
 '{"eventos_guardia_propios": 1}',
 'Cero eventos pase_guardia del oponente en el roll, exigiendo al menos un evento propio con rol=abajo en una posicion es_guardia. Sin esa guarda, un roll que nunca pasó por la guardia lo conseguiría gratis.'),

('muro', 'MURO', 'El rival lo intenta tres veces y no entra ninguna',
 'defensa', 'poco_comun', 'roll', true, false,
 '{"intentos_del_rival": 3}',
 'El oponente tiene >=3 eventos tipo sumision en el roll y ninguno con completado = true.'),

('houdini', 'HOUDINI', 'Tres escapes desde posiciones dominantes',
 'defensa', 'poco_comun', 'roll', false, false,
 '{"escapes": 3}',
 '>=3 eventos propios tipo escape desde posiciones con grupo = dominante o desde espalda.'),

('de_vuelta', 'DE VUELTA', 'Te montan o te toman la espalda, y acabas ganando',
 'defensa', 'raro', 'roll', false, false, '{}',
 'El oponente llegó a montada o espalda en algún momento del roll, y el resultado del roll es sumision_favor.'),

('cuello_de_acero', 'CUELLO DE ACERO', 'Te atacan el cuello tres veces y no cae ninguna',
 'defensa', 'poco_comun', 'roll', true, false,
 '{"ataques_al_cuello": 3}',
 '>=3 eventos del oponente tipo sumision con objetivo = cuello, ninguno completado.'),

('sin_marcar', 'SIN MARCAR', 'El rival no consigue ni un punto en todo el roll',
 'defensa', 'poco_comun', 'roll', true, false, '{}',
 'puntos_oponente = 0 en v_puntos_roll para ese roll. Requiere observador porque es una ausencia.'),

-- ---------- ATAQUE ----------
('rodillo', 'EL RODILLO', 'Tres pases de guardia en un roll',
 'ataque', 'comun', 'roll', false, false, '{"pases": 3}',
 '>=3 eventos propios tipo pase_guardia con completado = true.'),

('limpio', 'LIMPIO', 'Finalizas sin haber fallado ni un intento antes',
 'ataque', 'comun', 'roll', true, false, '{}',
 'Hay una sumision propia completada y ninguna sumision propia con completado = false anterior en el roll. Requiere observador: no registrar los fallos lo consigue gratis.'),

('relampago', 'RELÁMPAGO', 'Finalizas en menos de sesenta segundos',
 'ataque', 'poco_comun', 'roll', false, false, '{}',
 'Sumision propia completada con segundo_roll < 60. Si segundo_roll es null, el logro no cuenta — no lo estimes desde minuto.'),

('la_cadena', 'LA CADENA', 'Pasas, montas y tomas la espalda en el mismo roll',
 'ataque', 'raro', 'roll', false, false, '{}',
 'En el mismo roll, y en este orden temporal por segundo_roll: un pase_guardia propio, una transicion propia a montada, y una toma_espalda propia o una transicion propia a espalda.'),

('quince', 'QUINCE', 'Quince puntos estimados en un solo roll',
 'ataque', 'raro', 'roll', false, false, '{}',
 'puntos_autor >= 15 en v_puntos_roll.'),

('primera_vez', 'PRIMERA VEZ', 'Finalizas desde una posición nueva para ti',
 'ataque', 'poco_comun', 'roll', false, false, '{}',
 'Sumision propia completada desde una posicion desde la que el practicante no habia finalizado nunca antes, mirando todo su histórico anterior a ese roll. Es acumulable: cada posicion nueva cuenta una vez.'),

('juguete_nuevo', 'JUGUETE NUEVO', 'Finalizas con una técnica que nunca habías usado',
 'ataque', 'poco_comun', 'roll', false, false, '{}',
 'Igual que primera_vez pero por tecnica_id. Los eventos con tecnica_id null no cuentan.'),

('guardia_de_hierro', 'GUARDIA DE HIERRO', 'Tres barridas en un roll',
 'ataque', 'comun', 'roll', false, false, '{"barridas": 3}',
 '>=3 eventos propios tipo barrida completados.'),

('mochilero', 'EL MOCHILERO', 'Dos espaldas tomadas en un roll',
 'ataque', 'comun', 'roll', false, false, '{"espaldas": 2}',
 '>=2 eventos propios tipo toma_espalda completados.'),

('piernas', 'PIERNAS', 'Finalizas atacando una pierna',
 'ataque', 'poco_comun', 'roll', false, true, '{}',
 'Sumision propia completada con objetivo en (rodilla, tobillo_pie, pantorrilla). Solo nogi.'),

('cinturon_invisible', 'CINTURÓN INVISIBLE', 'Finalizas a alguien de cinturón superior',
 'ataque', 'poco_comun', 'roll', false, false, '{}',
 'Sumision propia completada en un roll cuyo oponente tiene un cinturon mas alto en el orden del enum bjj_cinturon. Si el oponente no tiene cinturon registrado, no cuenta.'),

-- ---------- ESTILO ----------
('pulpo', 'EL PULPO', 'Cinco intentos de sumisión en un roll',
 'estilo', 'comun', 'roll', false, false, '{"intentos": 5}',
 '>=5 eventos propios tipo sumision, completados o no. Es a prueba de trampas por construccion: inflarlo exige registrar tus propios fallos.'),

('artista', 'EL ARTISTA', 'Tres sumisiones distintas en la misma quedada',
 'estilo', 'poco_comun', 'quedada', false, false, '{}',
 '>=3 tecnica_id distintas en sumisiones propias completadas dentro de la misma quedada.'),

('ambidiestro', 'AMBIDIESTRO', 'Finalizas desde arriba y desde abajo el mismo día',
 'estilo', 'poco_comun', 'quedada', false, false, '{}',
 'En la misma quedada, al menos una sumision propia completada con rol = arriba y otra con rol = abajo.'),

('sin_gi_sin_problema', 'SIN GI, SIN PROBLEMA', 'Finalizas en gi y en nogi la misma semana',
 'estilo', 'poco_comun', 'semana', false, false, '{}',
 'En la misma semana ISO, sumisiones propias completadas en una sesion gi y en una sesion nogi.'),

-- ---------- CONSTANCIA ----------
-- Estos cuatro no premian rendimiento, premian REGISTRAR, que es el unico
-- riesgo que mata el producto. Si hay que implementar una sola familia, esta.
('notario', 'EL NOTARIO', 'Registras todos los rolls de la quedada, sin dejarte ninguno',
 'constancia', 'comun', 'quedada', false, false,
 '{"rolls_en_la_quedada": 3}',
 'El practicante tiene rolls registrados en la quedada y ninguno de sus rolls de ese dia quedo sin eventos. Minimo 3 rolls para que cuente.'),

('ojo_del_coach', 'OJO DEL COACH', 'Diez rolls registrados como observador en un mes',
 'constancia', 'poco_comun', 'mes', false, false, '{}',
 '>=10 rolls con registrado_por = este practicante y origen = observador dentro del mes.'),

('semana_completa', 'SEMANA COMPLETA', 'Registras en tres días distintos de la misma semana',
 'constancia', 'comun', 'semana', false, false, '{}',
 '>=3 fechas distintas con al menos un roll propio registrado, dentro de la misma semana ISO.'),

-- ---------- CACHONDEO ----------
-- Solo se evalúan y se muestran si grupos.modo_cachondeo = true.
-- Apagados por defecto: un logro negativo automatico le sienta mal a
-- alguien tarde o temprano, y esa decision la toma un humano.
('peaje', 'PEAJE', 'Te pasan la guardia cuatro veces en un roll',
 'cachondeo', 'comun', 'roll', false, false, '{"pases_encajados": 4}',
 '>=4 eventos pase_guardia del oponente completados en el roll.'),

('el_ancla', 'EL ANCLA', 'Más de dos minutos en la misma posición sin que pase nada',
 'cachondeo', 'comun', 'roll', false, false, '{}',
 'Hueco de >120 segundos entre dos eventos consecutivos del roll sin cambio de posicion. Necesita segundo_roll en los dos eventos.'),

('donante', 'DONANTE', 'Encajas tres sumisiones en un roll',
 'cachondeo', 'comun', 'roll', false, false, '{"sumisiones_encajadas": 3}',
 '>=3 sumisiones del oponente completadas en el mismo roll.');


-- Los predicados preguntan una y otra vez "cuantos eventos de este roll son de
-- este actor y de este tipo". Sin este indice, cada rama del union vuelve a
-- recorrer los eventos del roll: con 252 rolls, la vista tardaba 3,0 s y con el
-- indice 1,65 s. El `include` evita ir a la tabla para leer las tres columnas
-- que se miran justo despues.
create index if not exists eventos_logros_idx
  on eventos (roll_id, actor, tipo)
  include (completado, objetivo, segundo_roll);

-- ============================================================
--  v_logros_conseguidos — el corazon
--
--  Una fila por (practicante, logro, instancia del ambito). `ref_id` es text
--  y no uuid a proposito: para `roll` y `quedada` es un uuid, y para `semana`
--  y `mes` es la fecha en que empieza la ventana. Una sola columna con las
--  dos cosas, en vez de dos columnas de las que siempre hay una vacia.
--
--  Las tres reglas transversales —observador, solo nogi y cachondeo— se
--  aplican UNA VEZ al final, leyendolas del catalogo. Repartidas por las
--  ramas serian veintisiete sitios donde olvidarse de una.
-- ============================================================
create or replace view v_logros_conseguidos
with (security_invoker = on) as
with base as (
  select r.id            as roll_id,
         s.practicante_id,
         s.fecha,
         s.quedada_id,
         s.modalidad     as modalidad,
         r.origen,
         r.oponente_id,
         r.orden,
         r.resultado,
         r.registrado_por,
         r.roll_grupo_id,
         -- La semana empieza en lunes, que es lo que hace date_trunc('week')
         -- en Postgres y coincide con la semana ISO del enunciado.
         date_trunc('week',  s.fecha)::date as semana,
         date_trunc('month', s.fecha)::date as mes
    from rolls r
    join sesiones s on s.id = r.sesion_id
),
-- Los eventos de cada roll, ya con el dueño del roll al lado.
ev as (
  select b.roll_id, b.practicante_id, b.fecha,
         e.actor, e.tipo, e.posicion, e.rol, e.objetivo, e.tecnica_id,
         e.completado, e.segundo_roll, e.created_at
    from base b
    join eventos e on e.roll_id = b.roll_id
),
guardias   as (select codigo from posiciones where es_guardia),
dominantes as (select codigo from posiciones where grupo = 'dominante'),
-- Sumisiones propias completadas, numeradas por posicion y por tecnica para
-- saber cual fue la PRIMERA vez de cada una en todo el historico.
finales as (
  select b.practicante_id, b.roll_id, b.fecha, e.posicion, e.tecnica_id,
         row_number() over (partition by b.practicante_id, e.posicion
                            order by b.fecha, b.orden, b.roll_id) as n_pos,
         row_number() over (partition by b.practicante_id, e.tecnica_id
                            order by b.fecha, b.orden, b.roll_id) as n_tec
    from base b
    join eventos e on e.roll_id = b.roll_id
   where e.actor = 'yo' and e.tipo = 'sumision' and e.completado
),
-- Los grupos con el cachondeo encendido, para no evaluar siquiera los logros
-- negativos de quien no los ha pedido.
con_cachondeo as (
  select distinct m.practicante_id
    from miembros_grupo m
    join grupos g on g.id = m.grupo_id
   where m.estado = 'activo' and g.modo_cachondeo
),
crudo as (

-- ---------- DEFENSA ----------

-- IMPASABLE. Literal: CERO eventos pase_guardia del oponente, completados o
-- no. Y la guarda de volumen, que es media mitad del logro: sin haber jugado
-- la guardia no te la pueden pasar, y saldria gratis.
select b.practicante_id, 'impasable' as clave, b.roll_id::text as ref_id,
       b.fecha, b.origen, b.modalidad
  from base b
 where not exists (select 1 from ev e where e.roll_id = b.roll_id
                    and e.actor = 'oponente' and e.tipo = 'pase_guardia')
   and exists (select 1 from ev e where e.roll_id = b.roll_id
                and e.actor = 'yo' and e.rol = 'abajo'
                and e.posicion in (select codigo from guardias))

union all
-- MURO
select b.practicante_id, 'muro', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'oponente' and e.tipo = 'sumision') >= 3
   and not exists (select 1 from ev e where e.roll_id = b.roll_id
                    and e.actor = 'oponente' and e.tipo = 'sumision' and e.completado)

union all
-- HOUDINI
select b.practicante_id, 'houdini', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'yo' and e.tipo = 'escape'
         and e.posicion in (select codigo from dominantes)) >= 3

union all
-- DE VUELTA. "El oponente llego a montada o espalda" se lee con el criterio
-- de `rol`, que describe al ACTOR del evento: un evento del oponente en
-- montada con rol=arriba es el oponente montado encima. Con rol=abajo seria
-- justo lo contrario, y contarlo daria el logro al reves.
select b.practicante_id, 'de_vuelta', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where b.resultado = 'sumision_favor'
   and exists (select 1 from ev e where e.roll_id = b.roll_id and e.actor = 'oponente'
                and (e.tipo = 'toma_espalda'
                     or (e.posicion in ('montada', 'espalda') and e.rol = 'arriba')))

union all
-- CUELLO DE ACERO
select b.practicante_id, 'cuello_de_acero', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'oponente' and e.tipo = 'sumision' and e.objetivo = 'cuello') >= 3
   and not exists (select 1 from ev e where e.roll_id = b.roll_id
                    and e.actor = 'oponente' and e.tipo = 'sumision'
                    and e.objetivo = 'cuello' and e.completado)

union all
-- SIN MARCAR
select b.practicante_id, 'sin_marcar', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
  join v_puntos_roll p on p.roll_id = b.roll_id and p.autor_id = b.practicante_id
 where p.puntos_oponente = 0

-- ---------- ATAQUE ----------

union all
-- EL RODILLO
select b.practicante_id, 'rodillo', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'yo' and e.tipo = 'pase_guardia' and e.completado) >= 3

union all
-- LIMPIO. "Sin haber fallado ni un intento ANTES": se ordena por
-- `segundo_roll`, y lo que no tenga sello se desempata por `created_at`, que
-- en un roll registrado en vivo es el orden en que se pulsaron los botones.
select b.practicante_id, 'limpio', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where exists (
   select 1 from ev ok
    where ok.roll_id = b.roll_id and ok.actor = 'yo'
      and ok.tipo = 'sumision' and ok.completado
      and not exists (
        select 1 from ev fallo
         where fallo.roll_id = b.roll_id and fallo.actor = 'yo'
           and fallo.tipo = 'sumision' and not fallo.completado
           and (coalesce(fallo.segundo_roll, 2147483647), fallo.created_at)
             < (coalesce(ok.segundo_roll, 2147483647), ok.created_at)))

union all
-- RELAMPAGO. Sin sello de segundo no cuenta: no se estima desde `minuto`.
select b.practicante_id, 'relampago', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where exists (select 1 from ev e where e.roll_id = b.roll_id
                and e.actor = 'yo' and e.tipo = 'sumision' and e.completado
                and e.segundo_roll is not null and e.segundo_roll < 60)

union all
-- LA CADENA. Los tres eslabones, y EN ORDEN. Sin sello de segundo no hay
-- orden que comprobar, asi que no cuenta.
select b.practicante_id, 'la_cadena', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where exists (
   select 1
     from ev pase, ev monta, ev espalda
    where pase.roll_id = b.roll_id and monta.roll_id = b.roll_id
      and espalda.roll_id = b.roll_id
      and pase.actor = 'yo' and monta.actor = 'yo' and espalda.actor = 'yo'
      and pase.tipo = 'pase_guardia'
      and monta.tipo = 'transicion' and monta.posicion = 'montada'
      and (espalda.tipo = 'toma_espalda'
           or (espalda.tipo = 'transicion' and espalda.posicion = 'espalda'))
      and pase.segundo_roll is not null and monta.segundo_roll is not null
      and espalda.segundo_roll is not null
      and pase.segundo_roll < monta.segundo_roll
      and monta.segundo_roll < espalda.segundo_roll)

union all
-- QUINCE
select b.practicante_id, 'quince', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
  join v_puntos_roll p on p.roll_id = b.roll_id and p.autor_id = b.practicante_id
 where p.puntos_autor >= 15

union all
-- PRIMERA VEZ. Una por roll aunque el roll estrene dos posiciones: el ambito
-- es `roll`, y `veces` cuenta instancias del ambito, no eventos.
select distinct f.practicante_id, 'primera_vez', f.roll_id::text, f.fecha,
       b.origen, b.modalidad
  from finales f join base b on b.roll_id = f.roll_id
 where f.n_pos = 1

union all
-- JUGUETE NUEVO
select distinct f.practicante_id, 'juguete_nuevo', f.roll_id::text, f.fecha,
       b.origen, b.modalidad
  from finales f join base b on b.roll_id = f.roll_id
 where f.n_tec = 1 and f.tecnica_id is not null

union all
-- GUARDIA DE HIERRO
select b.practicante_id, 'guardia_de_hierro', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'yo' and e.tipo = 'barrida' and e.completado) >= 3

union all
-- EL MOCHILERO
select b.practicante_id, 'mochilero', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'yo' and e.tipo = 'toma_espalda' and e.completado) >= 2

union all
-- PIERNAS. El "solo nogi" lo aplica el filtro del final, desde el catalogo.
select b.practicante_id, 'piernas', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where exists (select 1 from ev e where e.roll_id = b.roll_id
                and e.actor = 'yo' and e.tipo = 'sumision' and e.completado
                and e.objetivo in ('rodilla', 'tobillo_pie', 'pantorrilla'))

union all
-- CINTURON INVISIBLE. Sin oponente en la ficha no hay cinturon que comparar.
select b.practicante_id, 'cinturon_invisible', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
  join practicantes yo    on yo.id    = b.practicante_id
  join practicantes rival on rival.id = b.oponente_id
 where rival.cinturon > yo.cinturon
   and exists (select 1 from ev e where e.roll_id = b.roll_id
                and e.actor = 'yo' and e.tipo = 'sumision' and e.completado)

-- ---------- ESTILO ----------

union all
-- EL PULPO. Completados o no: inflarlo exige registrar tus propios fallos.
select b.practicante_id, 'pulpo', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'yo' and e.tipo = 'sumision') >= 5

union all
-- EL ARTISTA. Ambito quedada: tres tecnicas DISTINTAS en la misma quedada.
select b.practicante_id, 'artista', b.quedada_id::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
  join eventos e on e.roll_id = b.roll_id
 where b.quedada_id is not null
   and e.actor = 'yo' and e.tipo = 'sumision' and e.completado
   and e.tecnica_id is not null
 group by b.practicante_id, b.quedada_id
having count(distinct e.tecnica_id) >= 3

union all
-- AMBIDIESTRO
select b.practicante_id, 'ambidiestro', b.quedada_id::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
  join eventos e on e.roll_id = b.roll_id
 where b.quedada_id is not null
   and e.actor = 'yo' and e.tipo = 'sumision' and e.completado
 group by b.practicante_id, b.quedada_id
having count(*) filter (where e.rol = 'arriba') > 0
   and count(*) filter (where e.rol = 'abajo')  > 0

union all
-- SIN GI, SIN PROBLEMA. Ambito semana, y la modalidad es la de la SESION.
select b.practicante_id, 'sin_gi_sin_problema', b.semana::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
  join eventos e on e.roll_id = b.roll_id
 where e.actor = 'yo' and e.tipo = 'sumision' and e.completado
 group by b.practicante_id, b.semana
having count(*) filter (where b.modalidad = 'gi')   > 0
   and count(*) filter (where b.modalidad = 'nogi') > 0

-- ---------- CONSTANCIA ----------

union all
-- EL NOTARIO. Tres rolls o mas en la quedada, y NINGUNO sin eventos.
select b.practicante_id, 'notario', b.quedada_id::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
 where b.quedada_id is not null
 group by b.practicante_id, b.quedada_id
having count(*) >= 3
   and count(*) filter (
     where not exists (select 1 from eventos e where e.roll_id = b.roll_id)) = 0

union all
-- OJO DEL COACH. Aqui el practicante es el OBSERVADOR, no el dueño del roll.
-- Se cuenta por `roll_grupo_id`: una observacion escribe dos rolls espejados,
-- y contarlos por separado daria el doble.
select b.registrado_por, 'ojo_del_coach', b.mes::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
 where b.registrado_por is not null and b.origen = 'observador'
 group by b.registrado_por, b.mes
having count(distinct coalesce(b.roll_grupo_id::text, b.roll_id::text)) >= 10

union all
-- SEMANA COMPLETA. Tres dias distintos con algo registrado.
select b.practicante_id, 'semana_completa', b.semana::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
 group by b.practicante_id, b.semana
having count(distinct b.fecha) >= 3

-- ---------- CACHONDEO ----------

union all
-- PEAJE
select b.practicante_id, 'peaje', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'oponente' and e.tipo = 'pase_guardia' and e.completado) >= 4

union all
-- EL ANCLA. Hueco de mas de dos minutos entre dos eventos seguidos SIN que
-- cambie la posicion. Hacen falta los dos sellos.
select distinct b.practicante_id, 'el_ancla', b.roll_id::text, b.fecha,
       b.origen, b.modalidad
  from base b
  join (
    select roll_id, posicion, segundo_roll,
           lag(posicion)     over (partition by roll_id order by segundo_roll) as pos_ant,
           lag(segundo_roll) over (partition by roll_id order by segundo_roll) as seg_ant
      from eventos where segundo_roll is not null
  ) h on h.roll_id = b.roll_id
 where h.pos_ant = h.posicion and h.segundo_roll - h.seg_ant > 120

union all
-- DONANTE
select b.practicante_id, 'donante', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
 where (select count(*) from ev e where e.roll_id = b.roll_id
         and e.actor = 'oponente' and e.tipo = 'sumision' and e.completado) >= 3

)
select c.practicante_id,
       c.clave,
       l.ambito,
       c.ref_id,
       c.fecha,
       -- Verificado = lo registro un tercero. Solo tiene sentido en el ambito
       -- `roll`: una semana no se verifica.
       coalesce(c.origen = 'observador', false) as verificado
  from crudo c
  join logros l on l.clave = c.clave
 where (not l.requiere_observador or c.origen = 'observador')
   and (not l.solo_nogi           or c.modalidad = 'nogi')
   and (l.familia <> 'cachondeo'
        or c.practicante_id in (select practicante_id from con_cachondeo));

comment on view v_logros_conseguidos is
  'Una fila por practicante, logro e instancia del ambito. Se deriva entera: '
  'no hay tabla de conseguidos ni contadores. `ref_id` es el roll, la quedada '
  'o la fecha en que empieza la semana o el mes, en text porque unas son uuid '
  'y otras fecha.';


-- ------------------------------------------------------------
-- La coleccion de cada uno, de por vida.
-- ------------------------------------------------------------
create or replace view v_logros_practicante
with (security_invoker = on) as
select practicante_id,
       clave,
       count(*)                           as veces,
       count(*) filter (where verificado) as veces_verificadas,
       min(fecha)                         as primera_vez,
       max(fecha)                         as ultima_vez
  from v_logros_conseguidos
 group by practicante_id, clave;

comment on view v_logros_practicante is
  '`veces_verificadas` es cuantas de esas veces las registro un tercero. Se '
  'enseña al lado de `veces` en vez de esconderse: la procedencia del dato es '
  'parte del dato.';


-- ------------------------------------------------------------
-- El ranking del mes, por grupo. Quien esta en dos grupos sale en los dos.
-- ------------------------------------------------------------
create or replace view v_logros_mes
with (security_invoker = on) as
select m.grupo_id,
       date_trunc('month', c.fecha)::date   as mes,
       c.clave,
       c.practicante_id,
       count(*)                             as veces,
       count(*) filter (where c.verificado) as veces_verificadas
  from v_logros_conseguidos c
  join miembros_grupo m
    on m.practicante_id = c.practicante_id and m.estado = 'activo'
 group by m.grupo_id, date_trunc('month', c.fecha), c.clave, c.practicante_id;

comment on view v_logros_mes is
  'Ranking mensual por grupo. El reinicio mensual es a proposito: evita que '
  'los mismos lo dominen para siempre.';


-- ============================================================
--  El feed: agregar, no inundar
--
--  Un elemento por logro serian unas 150 entradas semanales con doce
--  personas. Eso entierra el informe de la quedada, entierra quien se apunta,
--  y se lleva por delante las reacciones — nadie pone un emoji en el elemento
--  numero noventa.
--
--  Asi que la unidad del elemento es LA SESION y los logros viajan dentro:
--
--    Pablo registro 6 rolls anoche · IMPASABLE ×2 · MURO · RELAMPAGO
--
--  Nada queda invisible, que era el punto, y encima se lee mejor.
--
--  Con elemento propio, solo cuatro casos, porque son noticia: la primera vez
--  que alguien lo consigue, los numeros redondos, el primero del grupo aunque
--  para el no sea la primera vez, y los raros siempre.
-- ============================================================

-- Los logros de cada sesion, ya agrupados. Se saca aparte porque lo usan el
-- elemento de sesion y el de hito.
create or replace view v_logros_sesion
with (security_invoker = on) as
select s.id as sesion_id, s.practicante_id, c.clave, count(*) as veces
  from v_logros_conseguidos c
  join rolls r    on r.id::text = c.ref_id
  join sesiones s on s.id = r.sesion_id and s.practicante_id = c.practicante_id
 where c.ambito = 'roll'
 group by s.id, s.practicante_id, c.clave;

comment on view v_logros_sesion is
  'Los logros de ambito roll, agrupados por sesion. Es lo que viaja dentro del '
  'elemento de feed de la sesion, en vez de generar uno por logro.';


-- Los hitos: las cuatro veces que un logro SI merece su propio elemento.
create or replace view v_logros_hitos
with (security_invoker = on) as
with num as (
  select c.practicante_id, c.clave, c.fecha, c.ref_id, c.ambito,
         row_number() over (partition by c.practicante_id, c.clave
                            order by c.fecha, c.ref_id) as n_suyo,
         min(c.fecha) over (partition by c.clave)       as primera_del_mundo
    from v_logros_conseguidos c
)
select n.practicante_id, n.clave, n.fecha, n.ref_id, n.ambito, n.n_suyo, l.rareza,
       case
         when n.n_suyo = 1 then 'primera'
         when l.rareza = 'raro' then 'raro'
         when n.n_suyo in (5, 10, 25, 50) then 'redondo'
       end as motivo
  from num n
  join logros l on l.clave = n.clave
 where n.n_suyo = 1
    or l.rareza = 'raro'
    or n.n_suyo in (5, 10, 25, 50);

comment on view v_logros_hitos is
  'Los logros que se ganan un elemento propio en el feed: la primera vez, los '
  'numeros redondos y los raros. Todo lo demas viaja agregado dentro de la '
  'sesion.';


-- ------------------------------------------------------------
-- Y el feed, con los tipos nuevos. Se reescribe entero porque
-- `create or replace view` exige repetir las columnas de siempre en el mismo
-- orden; lo de antes no cambia.
-- ------------------------------------------------------------
create or replace view v_feed with (security_invoker = on) as

-- Alguien registro una sesion de entreno. AHORA CON SUS LOGROS DENTRO.
select s.grupo_id,
       'sesion'::text                       as tipo,
       s.id                                 as referencia_id,
       s.practicante_id,
       s.created_at                         as cuando,
       jsonb_build_object(
         'fecha', s.fecha,
         'modalidad', s.modalidad,
         'rolls', (select count(*) from rolls r where r.sesion_id = s.id),
         'quedada', (select q.titulo from quedadas q where q.id = s.quedada_id),
         'logros', coalesce(ls.lista, '[]'::jsonb)
       )                                    as datos
  from sesiones s
  -- JOIN y no subconsulta correlacionada. Con `(select ... from
  -- v_logros_sesion where sesion_id = s.id)`, Postgres reevaluaba la vista de
  -- logros entera UNA VEZ POR SESION: tres segundos por sesenta y nueve
  -- sesiones, y el feed se pasaba de los treinta segundos de timeout. Asi se
  -- evalua una sola vez.
  left join (
    select sesion_id,
           jsonb_agg(jsonb_build_object('clave', clave, 'veces', veces)
                     order by veces desc, clave) as lista
      from v_logros_sesion group by sesion_id
  ) ls on ls.sesion_id = s.id
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
 where m.estado = 'activo'

union all

-- NUEVO · El logro que si es noticia. `cuando` sale de la fecha de la sesion
-- y no de `created_at`: un logro no tiene fila propia de la que sacar la hora,
-- porque no se guarda en ningun sitio.
select m.grupo_id, 'logro', h.ref_id::uuid, h.practicante_id,
       h.fecha::timestamptz + interval '20 hours',
       jsonb_build_object('clave', h.clave, 'motivo', h.motivo,
                          'veces', h.n_suyo, 'rareza', h.rareza)
  from v_logros_hitos h
  join miembros_grupo m
    on m.practicante_id = h.practicante_id and m.estado = 'activo'
   -- Solo los ambitos cuyo `ref_id` es un uuid: la semana y el mes son una
   -- fecha, y no hay fila a la que apuntar una reaccion.
 where h.ambito in ('roll', 'quedada')

union all

-- NUEVO · El cierre de mes: un solo elemento con quien mando en cada logro.
select r.grupo_id, 'mes', r.grupo_id, null::uuid,
       (r.mes + interval '1 month')::timestamptz,
       jsonb_build_object('mes', r.mes, 'ranking', r.ranking)
  from (
    select mes, grupo_id,
           jsonb_agg(jsonb_build_object('clave', clave, 'practicante_id', practicante_id,
                                        'veces', veces)
                     order by veces desc) as ranking
      from (
        select distinct on (grupo_id, mes, clave)
               grupo_id, mes, clave, practicante_id, veces
          from v_logros_mes
         order by grupo_id, mes, clave, veces desc
      ) top1
     group by mes, grupo_id
  ) r
 where r.mes < date_trunc('month', current_date)::date;


comment on view v_feed is
  'Actividad del grupo, derivada. No hay tabla de entradas: si se corrige una '
  'sesion, el feed se corrige solo. Los logros normales viajan DENTRO del '
  'elemento de la sesion; solo la primera vez, los redondos y los raros se '
  'ganan uno propio, porque un elemento por logro serian 150 a la semana y '
  'enterrarian todo lo demas.';
