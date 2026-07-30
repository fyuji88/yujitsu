-- ============================================================
--  BJJ TRACKER — Mecanicas: la jerarquia del catalogo · Migracion bjj_29
-- ============================================================
--
--  EL PROBLEMA. Cuando Felipe elige objetivos de la semana piensa en tecnicas
--  concretas ("esta semana, tarikoplata"). Cuando alguien registra en vivo, con
--  el cronometro corriendo, piensa en genericas: apunta "kimura" porque es lo
--  que se llama en un segundo. Hoy esos dos mundos no se hablan — un objetivo
--  de tarikoplata no se cumple nunca, y una coleccion de 14 kimuras no dice si
--  son la de siempre o el juguete nuevo.
--
--  LA REGLA QUE IMPIDE QUE EL CATALOGO EXPLOTE. Una variante es la MISMA
--  articulacion y la MISMA direccion, aplicada con OTRA cosa o con OTRO agarre.
--  La posicion de entrada NUNCA crea una variante: una kimura desde side
--  control y una desde la guardia son la misma tecnica, y la posicion ya viaja
--  en el evento, en su columna. Emparentar por posicion llevaria el catalogo de
--  63 filas a cuatrocientas, cada una con dos datos, y el analisis se volveria
--  inutil por dispersion.
--
--  Ante la duda, NO se emparenta. Una tecnica sin madre es una mecanica de una
--  sola y no cuesta nada; una madre equivocada corrompe en silencio todos los
--  recuentos agregados y nadie se entera nunca.
--
--  POR QUE `mecanica` Y NO `familia`: porque `logros.familia` ya existe y
--  significa otra cosa. Una palabra, un concepto — la regla esta en CLAUDE.md.
--
--  UN SOLO NIVEL, GARANTIZADO POR LA BASE Y NO POR UN COMENTARIO. Ver el truco
--  del FK compuesto mas abajo: no hay nietos, y tampoco se puede degradar una
--  madre que ya tiene variantes. Las dos violaciones estan probadas en
--  db/pruebas/mecanicas.sql.
-- ============================================================

begin;

-- ------------------------------------------------------------------ 1 · tipos
--
-- Con que se aplica la presion FINAL, no lo que la prepara. En un triangulo las
-- manos colocan la pierna pero lo que cierra es el triangulo; en un armbar las
-- manos sujetan la muñeca pero lo que extiende es la cadera.
--
-- Es ortogonal a `objetivo_default`, que dice QUE atacas: un straight ankle
-- ataca el tobillo y se aplica con el antebrazo. Las dos columnas sirven porque
-- responden a preguntas distintas.
create type bjj_control as enum ('brazo', 'pierna', 'cuerpo');

-- --------------------------------------------------------------- 2 · columnas
alter table tecnicas
  add column variante_de    uuid,
  add column control        bjj_control,
  add column nivel          smallint not null
                 generated always as (case when variante_de is null then 0 else 1 end) stored,
  add column nivel_referido smallint generated always as (0) stored,
  add column mecanica_id    uuid     generated always as (coalesce(variante_de, id)) stored;

-- ---------------------------------------------------------------------------
-- EL TRUCO DEL UN SOLO NIVEL, que es lo mejor de esta migracion.
--
-- `nivel` vale 0 si no tienes madre y 1 si la tienes. `nivel_referido` es una
-- constante 0. La clave foranea compuesta exige que la MADRE tenga nivel 0.
--
--   - Colgar una variante de una variante falla: la madre tendria nivel 1 y la
--     FK apunta a (id, 0). No hay nietos, y no depende de que nadie se acuerde.
--   - Y protege el otro lado: darle madre a una madre que YA tiene variantes
--     tambien falla, porque su nivel pasaria a 1 y sus variantes apuntan a
--     (id, 0). La jerarquia no puede degenerar en ninguna direccion.
--
-- Sin triggers, sin CTE recursiva, y declarativo — o sea que lo comprueba
-- Postgres en cada escritura y no un test que alguien puede olvidar correr.
-- ---------------------------------------------------------------------------
alter table tecnicas add constraint tecnicas_id_nivel_uk unique (id, nivel);
alter table tecnicas add constraint tecnicas_variante_fk
  foreign key (variante_de, nivel_referido) references tecnicas (id, nivel);

-- `mecanica_id` = coalesce(variante_de, id): TODA tecnica tiene mecanica, y las
-- que no tienen madre son su propia mecanica. Asi los agregados se escriben
-- `group by mecanica_id` sin un solo `case`, sin CTE recursiva y con indice.
create index tecnicas_mecanica_idx on tecnicas (mecanica_id);

comment on column tecnicas.variante_de is
  'La mecanica madre, o null si esta tecnica es su propia mecanica. Un solo '
  'nivel: lo garantiza la FK compuesta contra (id, nivel), no un comentario.';
comment on column tecnicas.mecanica_id is
  'coalesce(variante_de, id). Por aqui van TODOS los agregados de tecnica: '
  'catorce kimuras son catorce kimuras, se hayan precisado o no.';
comment on column tecnicas.control is
  'Con que se aplica la presion final, no lo que la prepara. Ortogonal a '
  'objetivo_default, que dice que articulacion se ataca. Nulo = sin '
  'clasificar, que NO es lo mismo que brazo.';

-- ============================================================
-- 3 · EL CONTROL DE LAS 28 SUMISIONES  ← BLOQUE PROVISIONAL
-- ============================================================
--
--  ESTOS VALORES ESTAN EN REVISION con el equipo de Felipe. Van en un bloque
--  propio y marcado a proposito: corregir cualquiera de ellos es un `update`
--  sobre el catalogo, no una migracion, y el diff tiene que ser pequeño.
--
--  Y OJO CON LAS LLAVES DE PIERNA, que no es lo que dice el instinto:
--  `heel_hook` va en BRAZO y `kneebar` en CUERPO. En las cuatro llaves de
--  pierna las piernas atrapan pero no rematan — el talon lo gira el brazo,
--  igual que en el straight ankle, y el kneebar lo remata la extension de
--  cadera. Con el criterio de arriba salen asi. Si de la revision sale al
--  reves, es un update de una linea.
--
--  Las que NO son sumision (pases, barridas, derribos, escapes, tomas de
--  espalda) se quedan con `control` NULO. No se inventan valores para ellas:
--  nulo significa "sin clasificar", no "brazo".
-- ============================================================

update tecnicas set control = 'brazo' where slug in (
  'americana', 'americana_recta', 'anaconda', 'baratoplata', 'baseball_bat',
  'bow_and_arrow', 'cruzada', 'darce', 'ezekiel', 'guillotina', 'heel_hook',
  'katagatame', 'kimura', 'lapela', 'mata_leao', 'muneca', 'north_south_choke',
  'straight_ankle', 'toe_hold');

update tecnicas set control = 'pierna' where slug in (
  'banana_split', 'biceps_slicer', 'omoplata', 'pantorrilla_slicer', 'triangulo');

update tecnicas set control = 'cuerpo' where slug in (
  'armbar', 'armbar_triangulo', 'kneebar', 'twister');

-- Que no se quede ninguna sumision sin clasificar por un slug mal escrito: si
-- la lista de arriba y el catalogo se separan, esto se entera aqui y no dentro
-- de tres meses mirando un grafico raro.
do $$
declare v_sin int;
begin
  select count(*) into v_sin from tecnicas where tipo = 'sumision' and control is null;
  if v_sin > 0 then
    raise exception 'Quedan % sumisiones sin control: %', v_sin,
      (select string_agg(slug, ', ') from tecnicas where tipo = 'sumision' and control is null);
  end if;
end $$;

-- ============================================================
-- 4 · LAS VARIANTES QUE SE SIEMBRAN, Y SOLO ESTAS
-- ============================================================
--
--  Siete altas y una reparentacion. Ni una mas: si al implementar se te ocurren
--  tres obvias, van por el circuito de propuestas. Un catalogo compartido que
--  crece por buenas ideas sueltas no se vuelve a limpiar nunca.
--
--  TRES QUE NO ESTAN, Y POR QUE:
--
--  - `kimura_de_reloj` se cayo de la lista. "Desde el reloj" es una POSICION de
--    entrada, no una mecanica distinta. Saltarse la regla el primer dia deja la
--    regla sin valor.
--  - `baratoplata` se queda suelta, sin madre. Su parentesco es discutido
--    —segun a quien preguntes es prima de la kimura o de la omoplata— y la
--    regla dice que ante la duda no se emparenta.
--  - `armbar_triangulo` SI se emparenta, y es discutible: "desde triangulo"
--    tambien suena a posicion. La diferencia es que esa fila YA EXISTE. La
--    regla completa es: no crees filas que rompan la regla; a las que ya
--    existen, dales la mejor madre que haya. Y sumarla bajo armbar es mas
--    correcto que dejarla de hermana suelta.
--
--  Se comprobo antes de sembrar que el `objetivo` de cada variante coincide con
--  el `objetivo_default` de su madre. Ninguna contradice, asi que entran las
--  ocho. Si alguna hubiera chocado, se habria quedado fuera y dicho — una
--  tecnica mal emparentada es peor que una que falta, porque contamina los
--  agregados sin dar ninguna señal.
-- ============================================================

insert into tecnicas (slug, nombre, alias, tipo, objetivo_default, solo_gi,
                      variante_de, control)
select v.slug, v.nombre, v.alias, 'sumision'::bjj_tipo_evento,
       v.objetivo::bjj_objetivo, false, m.id, v.control::bjj_control
  from (values
    ('tarikoplata',             'Tarikoplata',              'kimura',
     array['leg kimura', 'kimura con la pierna'],                    'pierna', 'hombro'),
    ('j_lock',                  'J-Lock',                   'americana',
     array['j lock', 'kesa americana', 'americana desde kesa', 'leg americana'],
                                                                     'pierna', 'hombro'),
    ('heel_hook_interno',       'Heel hook interno',        'heel_hook',
     array['inside heel hook', 'IHH'],                               'brazo',  'rodilla'),
    ('heel_hook_externo',       'Heel hook externo',        'heel_hook',
     array['outside heel hook', 'OHH'],                              'brazo',  'rodilla'),
    ('guillotina_brazo_dentro', 'Guillotina con brazo dentro', 'guillotina',
     array['arm-in guillotine', 'guillotina con brazo dentro'],       'brazo',  'cuello'),
    ('guillotina_codo_alto',    'Guillotina de codo alto',  'guillotina',
     array['high elbow guillotine', 'marcelotine'],                  'brazo',  'cuello'),
    ('triangulo_invertido',     'Triangulo invertido',      'triangulo',
     array['reverse triangle'],                                      'pierna', 'cuello')
  ) as v(slug, nombre, madre, alias, control, objetivo)
  join tecnicas m on m.slug = v.madre;

-- `armbar_triangulo` ya existe: se REPARENTA con update, nunca con delete +
-- insert. La fila y su id se conservan, y con ellos los eventos que ya la
-- apuntan.
update tecnicas set variante_de = (select id from tecnicas where slug = 'armbar')
 where slug = 'armbar_triangulo';

-- ============================================================
-- 5 · DOS ALTAS DE CATALOGO QUE NO SON VARIANTES
-- ============================================================
--
--  Tecnicas base, nivel 0, sin madre. No tienen nada que ver con la jerarquia:
--  se cuelan aqui porque esta migracion ya esta tocando `tecnicas` y no merece
--  la pena una migracion propia para dos filas.
--
--  Las dos viven en la TORTUGA, que es donde mas pasa y de donde hoy no se
--  puede registrar casi nada. `tortuga` ya existe en `bjj_posicion` y en
--  `posiciones`: no se toca.
--
--  Y por que estas dos y no mas: el crucifijo tambien vive ahi y NO se añade,
--  porque es una POSICION, no una sumision. Desde el crucifijo se hacen ataques
--  que ya estan en el catalogo. Meterlo en `tecnicas` seria el mismo error que
--  la regla de arriba prohibe.
-- ============================================================

insert into tecnicas (slug, nombre, alias, tipo, objetivo_default, solo_gi, control)
values
  ('clock_choke', 'Estrangulacion del reloj',
   array['clock choke', 'reloj', 'relogio'],
   'sumision', 'cuello', true,  'brazo'),
  ('gravata_peruana', 'Gravata peruana',
   array['peruvian necktie', 'corbata peruana'],
   'sumision', 'cuello', false, 'brazo');

-- ============================================================
-- 6 · QUIEN PRECISO QUE
-- ============================================================
--
--  Precisar lo pueden hacer DOS personas —el protagonista del roll y quien lo
--  registro—, asi que hace falta saber quien. Sin esto, dos personas editando
--  el mismo evento acaba en una discusion que nadie puede resolver; con esto es
--  un dato. Las escribe la RPC, nadie mas.
-- ============================================================

alter table eventos
  add column tecnica_precisada_por uuid references practicantes(id),
  add column tecnica_precisada_en  timestamptz;

comment on column eventos.tecnica_precisada_por is
  'Quien bajo la tecnica de la mecanica madre a una variante. Solo lo escribe '
  'precisar_tecnica(). Se enseña en la ficha del roll ("precisado por Pablo").';

commit;

-- ============================================================
-- 7 · PRECISAR: la RPC que conecta el registro rapido con el objetivo concreto
-- ============================================================
--
--  POR QUE ES UNA RPC Y NO UN UPDATE CON POLITICA. Precisar lo puede hacer
--  tanto el protagonista del roll como quien lo registro, y en modo observador
--  eso significa editar un evento que escribio otro.
--
--  Postgres NO tiene RLS por columna. Una politica que deje cambiar
--  `tecnica_id` deja cambiar tambien `tipo`, `posicion` y `completado` — es
--  decir, deja reescribir el marcador de otro. Es exactamente el fallo que el
--  caso 9 de db/pruebas/rls.sql existe para cazar. Por eso va como
--  SECURITY DEFINER, con el mismo patron que `registrar_roll_observado` y
--  `unirse_con_codigo`.
--
--  PRECISAR BAJA, NUNCA SUBE NI CRUZA. Cambiar una kimura por un triangulo es
--  CORREGIR, que es otro boton y otra conversacion. El invariante —misma
--  mecanica— va aqui, en la base, y no en la pantalla: una comprobacion que
--  solo vive en React se salta con una llamada a la API.
-- ============================================================

begin;

create function public.precisar_tecnica(p_evento_id uuid, p_tecnica_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_yo        uuid;
  v_actual    uuid;
  v_duenyo    uuid;
  v_registro  uuid;
  v_mec_vieja uuid;
  v_mec_nueva uuid;
begin
  v_yo := private.practicante_actual();
  if v_yo is null then
    raise exception 'quien precisa no tiene ficha de practicante'
      using errcode = 'insufficient_privilege';
  end if;

  select e.tecnica_id, s.practicante_id, r.registrado_por
    into v_actual, v_duenyo, v_registro
    from eventos e
    join rolls r    on r.id = e.roll_id
    join sesiones s on s.id = r.sesion_id
   where e.id = p_evento_id;
  if not found then
    raise exception 'ese evento no existe' using errcode = 'no_data_found';
  end if;

  -- 1 · Quien llama es el practicante del roll o quien lo registro. Nadie mas:
  --     ni un compañero de equipo, ni un admin.
  if v_yo <> v_duenyo and v_yo is distinct from v_registro then
    raise exception 'solo el practicante del roll o quien lo registro pueden precisar'
      using errcode = 'insufficient_privilege';
  end if;

  -- 3 · Un evento sin tecnica no se precisa: se corrige, que es otra cosa.
  if v_actual is null then
    raise exception 'ese evento no tiene tecnica, asi que no hay nada que precisar'
      using errcode = 'check_violation';
  end if;

  -- 2 · EL INVARIANTE: la tecnica nueva es de la misma mecanica que la actual.
  select mecanica_id into v_mec_vieja from tecnicas where id = v_actual;
  select mecanica_id into v_mec_nueva from tecnicas where id = p_tecnica_id;
  if v_mec_nueva is null then
    raise exception 'esa tecnica no existe' using errcode = 'no_data_found';
  end if;
  if v_mec_nueva is distinct from v_mec_vieja then
    raise exception 'precisar solo baja dentro de la misma mecanica; cambiar de mecanica es corregir'
      using errcode = 'check_violation';
  end if;

  update eventos
     set tecnica_id            = p_tecnica_id,
         tecnica_precisada_por = v_yo,
         tecnica_precisada_en  = now()
   where id = p_evento_id;
end;
$$;

comment on function public.precisar_tecnica(uuid, uuid) is
  'Baja la tecnica de un evento de la mecanica madre a una de sus variantes. '
  'Solo el practicante del roll o quien lo registro, y solo dentro de la misma '
  'mecanica. Es SECURITY DEFINER porque no hay RLS por columna: una politica '
  'de update sobre eventos dejaria reescribir tambien el marcador.';

revoke all on function public.precisar_tecnica(uuid, uuid) from public, anon;
grant execute on function public.precisar_tecnica(uuid, uuid) to authenticated, service_role;

commit;

-- ============================================================
-- 8 · EL ANALISIS, PLEGADO POR MECANICA
-- ============================================================

begin;

-- Los intentos y los aciertos de cada practicante, por tecnica Y por mecanica.
-- La pantalla pliega desde aqui lo que no necesita filtro de modalidad.
create view v_tecnicas_practicante
with (security_invoker = on) as
select s.practicante_id,
       t.mecanica_id,
       t.id                                as tecnica_id,
       count(*)                            as intentos,
       count(*) filter (where e.completado) as completados
  from eventos e
  join tecnicas t on t.id = e.tecnica_id
  join rolls r    on r.id = e.roll_id
  join sesiones s on s.id = r.sesion_id
 where e.actor = 'yo' and e.tipo = 'sumision'
 group by s.practicante_id, t.mecanica_id, t.id;

comment on view v_tecnicas_practicante is
  'Intentos y finalizaciones por practicante y tecnica, con su mecanica al '
  'lado para poder plegar. NO lleva modalidad ni fecha, asi que no sirve para '
  'la pantalla de analisis, que filtra por gi/nogi: esa pliega desde '
  'analisis(). Ver la nota en docs/CAMBIOS.md.';

commit;




-- ============================================================
-- 9 - LO QUE HAY QUE RECREAR, PORQUE LOS CUERPOS SON TEXTO
-- ============================================================
--
--  Las tres de abajo son copia de su fuente comentada con UN cambio quirurgico
--  cada una, no una reescritura. Se recrean porque el cuerpo de una funcion y
--  el de una vista son TEXTO: no hay forma de cambiar una linea sin volver a
--  escribirlas enteras.
--
--  Y VAN TRADUCIDAS AL VOCABULARIO DE bjj_27. Las fuentes originales son
--  anteriores al renombrado y dicen `r.orden`, `miembros_grupo`, `grupos`...
--  Al pegarlas tal cual, Postgres contesto "column r.orden does not exist",
--  que es el mejor error posible: ruidoso e inmediato. Aqui van ya en
--  `orden_en_sesion`, `miembros_equipo` y `equipos`.
--
--  JUGUETE NUEVO no aparece: ya contaba por `tecnica_id` exacta
--  (row_number() over (partition by practicante_id, tecnica_id)), que es justo
--  lo que este bloque necesita. No hacia falta tocarlo, y no se toca.
-- ============================================================

-- ---------- enfoque_contraste, ahora asimetrico
begin;

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
      -- LA COINCIDENCIA ES ASIMETRICA, Y A PROPOSITO:
      --   - un enfoque en la MADRE cuenta la madre y todas sus variantes
      --     (objetivo "kimura" -> las tarikoplatas suman);
      --   - un enfoque en una VARIANTE cuenta solo esa
      --     (objetivo "tarikoplata" -> una kimura normal no suma).
      -- Y por eso viaja `incluye`: si el usuario no ve POR QUE subio el
      -- contador, el contador no vale nada.
      'tecnicas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'nombre', t.nombre, 'veces', x.veces,
                 'incluye', x.incluye))
          from (
            select c.id,
                   (select count(*) from ev e
                      join tecnicas et on et.id = e.tecnica_id
                     where e.tecnica_id = c.id
                        or et.variante_de = c.id) as veces,
                   coalesce((select jsonb_agg(v.nombre order by v.nombre)
                               from tecnicas v where v.variante_de = c.id),
                            '[]'::jsonb) as incluye
              from periodo p, unnest(p.tecnicas) as c(id)
          ) x
          join tecnicas t on t.id = x.id
      ), '[]'::jsonb)
    )
  end
$$;

commit;

-- ---------- analisis(), con el bloque de tecnicas plegado por mecanica
begin;

create or replace function analisis(
  p_autor     uuid,
  p_modalidad text default null,   -- 'gi' | 'nogi' | null = todo
  p_desde     date default null    -- null = todo el historico
) returns jsonb
language sql
stable
set search_path = public
as $$
with ev as (
  select *
    from v_eventos
   where autor_id = p_autor
     and (p_modalidad is null or modalidad_sesion::text = p_modalidad)
     and (p_desde is null or fecha >= p_desde)
),
rl as (
  select r.id, r.oponente_id, r.origen, s.fecha
    from v_rolls_unicos r
    join sesiones s on s.id = r.sesion_id
   where r.practicante_id = p_autor
     and (p_modalidad is null or r.modalidad::text = p_modalidad)
     and (p_desde is null or s.fecha >= p_desde)
),
ses as (
  select s.id, s.duracion_min
    from sesiones s
   where s.practicante_id = p_autor
     and (p_modalidad is null or s.modalidad::text = p_modalidad)
     and (p_desde is null or s.fecha >= p_desde)
)
select jsonb_build_object(

  -- Las cifras de arriba, en la unidad que una persona piensa: rolls, no
  -- eventos. El numero de eventos es un detalle de implementacion.
  'kpi', (select jsonb_build_object(
      'sesiones',   (select count(*) from ses),
      'rolls',      (select count(*) from rl),
      'eventos',    (select count(*) from ev),
      'horas',      (select round(coalesce(sum(duracion_min), 0) / 60.0) from ses),
      'sub_favor',  (select count(*) from ev where actor = 'yo' and tipo = 'sumision' and completado),
      'sub_contra', (select count(*) from ev where actor = 'oponente' and tipo = 'sumision' and completado),
      'desde',      (select min(fecha) from rl),
      'hasta',      (select max(fecha) from rl),
      -- Quien registro los datos. No es lo mismo un practicante cuyos rolls
      -- los ha registrado el coach que uno que se los registra el: cuando te
      -- registras tu faltan sistematicamente las cosas que no ves.
      'observados', (select count(*) from rl where origen = 'observador')
  )),

  -- Heatmaps. Se devuelven las celdas con dato; las columnas vacias las pinta
  -- el cliente, porque que nunca ataques a la muñeca ES informacion.
  'off', coalesce((select jsonb_agg(x) from (
      select posicion, posicion_nombre, objetivo,
             count(*) filter (where completado)     as n,
             count(*)                               as intentos
        from ev where actor = 'yo' and tipo = 'sumision'
       group by posicion, posicion_nombre, objetivo
       having count(*) filter (where completado) > 0
  ) x), '[]'::jsonb),

  'def', coalesce((select jsonb_agg(x) from (
      select posicion, posicion_nombre, objetivo,
             count(*) filter (where completado)     as n,
             count(*)                               as intentos
        from ev where actor = 'oponente' and tipo = 'sumision'
       group by posicion, posicion_nombre, objetivo
       having count(*) filter (where completado) > 0
  ) x), '[]'::jsonb),

  -- Saldo por guardia: barridas y ataques a favor menos pases y sumisiones
  -- en contra. Mismo corte que v_guardias.
  'guardias', coalesce((select jsonb_agg(x order by x.saldo desc) from (
      select posicion, posicion_nombre as nom,
             count(*) filter (where actor = 'yo' and rol = 'abajo'
               and tipo in ('barrida','toma_espalda','sumision') and completado) as favor,
             count(*) filter (where actor = 'oponente' and rol = 'arriba'
               and tipo in ('pase_guardia','sumision') and completado) as contra,
             count(*) filter (where actor = 'yo' and rol = 'abajo'
               and tipo in ('barrida','toma_espalda','sumision') and completado)
             - count(*) filter (where actor = 'oponente' and rol = 'arriba'
               and tipo in ('pase_guardia','sumision') and completado) as saldo
        from ev where es_guardia
       group by posicion, posicion_nombre
  ) x), '[]'::jsonb),

  -- Fuertes y debiles: el mismo saldo, pero en todas las posiciones y sobre
  -- acciones completadas. Mismo corte que v_fuertes_debiles, que excluye las
  -- transiciones porque no son ni ataque ni defensa.
  'posiciones', coalesce((select jsonb_agg(x order by x.saldo desc) from (
      select posicion, posicion_nombre as nom,
             count(*) filter (where actor = 'yo' and completado)       as favor,
             count(*) filter (where actor = 'oponente' and completado) as contra,
             count(*) filter (where actor = 'yo' and completado)
             - count(*) filter (where actor = 'oponente' and completado) as saldo
        from ev where tipo <> 'transicion'
       group by posicion, posicion_nombre
  ) x), '[]'::jsonb),

  'h2h', coalesce((select jsonb_agg(x order by x.rolls desc) from (
      select r.oponente_id as id, p.nombre as nom, p.cinturon::text as cin,
             count(distinct r.id) as rolls,
             count(*) filter (where e.actor = 'yo'
               and e.tipo = 'sumision' and e.completado) as favor,
             count(*) filter (where e.actor = 'oponente'
               and e.tipo = 'sumision' and e.completado) as contra
        from rl r
        left join eventos e on e.roll_id = r.id
        join practicantes p on p.id = r.oponente_id
       group by r.oponente_id, p.nombre, p.cinturon
  ) x), '[]'::jsonb),

  'evo', coalesce((select jsonb_agg(x order by x.semana) from (
      select to_char(date_trunc('week', r.fecha), 'YYYY-MM-DD') as semana,
             count(distinct r.id) as rolls,
             count(*) filter (where e.actor = 'yo'
               and e.tipo = 'sumision' and e.completado) as favor,
             count(*) filter (where e.actor = 'oponente'
               and e.tipo = 'sumision' and e.completado) as contra
        from rl r
        left join eventos e on e.roll_id = r.id
       group by date_trunc('week', r.fecha)
  ) x), '[]'::jsonb),

  -- Mis sumisiones: finalizadas sobre intentadas. Esto no tenia vista; el
  -- diseño de referencia si lo pinta.
  -- PLEGADO POR MECANICA. Catorce kimuras son catorce kimuras, se hayan
  -- precisado o no: nadie pierde nada por precisar, que es la condicion para
  -- que alguien lo haga. El desglose viaja dentro, en `variantes`, para que
  -- desplegar sea una decision de quien mira y no del que registro.
  --
  -- `compara` es la guarda de volumen: la frase "tu tarikoplata entra el 44%
  -- y tu kimura clasica el 20%" solo se puede decir con al menos dos tecnicas
  -- de cinco intentos cada una. 1 de 1 no es el 100%. La guarda va aqui y no
  -- en React porque es una decision sobre el dato, no sobre el dibujo.
  'tec', coalesce((select jsonb_agg(x order by x.ok desc, x.tot desc) from (
      select m.nombre                            as nom,
             m.id                                as mecanica_id,
             sum(d.ok)::int                      as ok,
             sum(d.tot)::int                     as tot,
             case when count(*) > 1 then
               jsonb_agg(jsonb_build_object('id', d.tecnica_id, 'nom', d.nom,
                                            'ok', d.ok, 'tot', d.tot)
                         order by d.ok desc, d.tot desc)
             end                                 as variantes,
             (count(*) filter (where d.tot >= 5) >= 2) as compara
        from (
          select t.mecanica_id, t.id as tecnica_id, t.nombre as nom,
                 count(*) filter (where e.completado) as ok,
                 count(*)                             as tot
            from ev e
            join tecnicas t on t.slug = e.tecnica_slug
           where e.actor = 'yo' and e.tipo = 'sumision'
           group by t.mecanica_id, t.id, t.nombre
        ) d
        join tecnicas m on m.id = d.mecanica_id
       group by m.id, m.nombre
  ) x), '[]'::jsonb)
);
$$;

commit;

-- ---------- v_logros_conseguidos: EL ARTISTA cuenta mecanicas, no tecnicas
begin;

create or replace view v_logros_conseguidos
with (security_invoker = on) as
with base as (
  select r.id            as roll_id,
         r.sesion_id,
         s.practicante_id,
         s.fecha,
         s.quedada_id,
         s.modalidad     as modalidad,
         r.origen,
         r.oponente_id,
         r.orden_en_sesion,
         r.resultado,
         r.registrado_por,
         r.par_id,
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
dominantes as (select codigo from posiciones where categoria = 'dominante'),
-- Sumisiones propias completadas, numeradas por posicion y por tecnica para
-- saber cual fue la PRIMERA vez de cada una en todo el historico.
finales as (
  select b.practicante_id, b.roll_id, b.fecha, e.posicion, e.tecnica_id,
         row_number() over (partition by b.practicante_id, e.posicion
                            order by b.fecha, b.orden_en_sesion, b.roll_id) as n_pos,
         row_number() over (partition by b.practicante_id, e.tecnica_id
                            order by b.fecha, b.orden_en_sesion, b.roll_id) as n_tec
    from base b
    join eventos e on e.roll_id = b.roll_id
   where e.actor = 'yo' and e.tipo = 'sumision' and e.completado
),
-- Los equipos con el cachondeo encendido, para no evaluar siquiera los logros
-- negativos de quien no los ha pedido.
con_cachondeo as (
  select distinct m.practicante_id
    from miembros_equipo m
    join equipos g on g.id = m.equipo_id
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
-- FLAWLESS VICTORY. Con guarda de volumen: en el roll tuvo que PASAR algo.
--
-- Sin ella, un roll tranquilo en el que no pasa nada da cero puntos a los dos
-- y se lo llevaban LOS DOS. Es el mismo agujero que tenia IMPASABLE, y se tapa
-- igual: un logro definido por una ausencia necesita que la situacion haya
-- existido de verdad.
select b.practicante_id, 'sin_marcar', b.roll_id::text, b.fecha, b.origen, b.modalidad
  from base b
  join v_puntos_roll p on p.roll_id = b.roll_id and p.autor_id = b.practicante_id
 where p.puntos_oponente = 0
   and (select count(*) from ev e where e.roll_id = b.roll_id
         and e.tipo in ('barrida','pase_guardia','derribo','toma_espalda',
                        'transicion')) >= 1

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
-- EL ARTISTA. Ambito quedada: tres MECANICAS distintas en la misma quedada.
-- Por mecanica y no por tecnica desde bjj_29: kimura + tarikoplata + americana
-- son DOS mecanicas, no tres, y contarlas como tres regalaria el logro.
-- (Su gemelo JUGUETE NUEVO va justo al reves, por tecnica exacta: tu primera
-- tarikoplata es un juguete nuevo aunque lleves cien kimuras. Los dos niveles
-- se ganan el sueldo aqui.)
select b.practicante_id, 'artista', b.quedada_id::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
  join eventos e  on e.roll_id = b.roll_id
  join tecnicas t on t.id = e.tecnica_id
 where b.quedada_id is not null
   and e.actor = 'yo' and e.tipo = 'sumision' and e.completado
 group by b.practicante_id, b.quedada_id
having count(distinct t.mecanica_id) >= 3

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
-- Se cuenta por `par_id`: una observacion escribe dos rolls espejados,
-- y contarlos por separado daria el doble.
select b.registrado_por, 'ojo_del_coach', b.mes::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
 where b.registrado_por is not null and b.origen = 'observador'
 group by b.registrado_por, b.mes
having count(distinct coalesce(b.par_id::text, b.roll_id::text)) >= 10

union all
-- DOBLE SESION. Aparecer dos veces el mismo dia. Ambito `dia`: `ref_id` es la
-- fecha, igual que la semana y el mes llevan la suya.
select b.practicante_id, 'doble_sesion', b.fecha::text, min(b.fecha),
       null::bjj_origen_roll, null::bjj_modalidad
  from base b
 group by b.practicante_id, b.fecha
having count(distinct b.sesion_id) >= 2

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

commit;
