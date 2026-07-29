-- ============================================================
--  BJJ TRACKER — La pantalla de analisis
--  Migracion bjj_13. Va despues de 01..07.
-- ============================================================
--
--  Dos cosas: abrir la LECTURA de los datos de analisis a cualquier
--  practicante, y dar una funcion que devuelva la pantalla entera ya
--  agregada y filtrada.
-- ============================================================


-- ============================================================
--  1. LECTURA ABIERTA — LEER ESTO ANTES DE PENSAR QUE ES UN DESCUIDO
-- ============================================================
--
--  Hasta aqui, `sesiones`, `rolls` y `eventos` solo dejaban leer lo tuyo. La
--  pantalla de analisis tiene un selector de practicante: al cambiarlo, la RLS
--  devolveria tablas vacias para todo el mundo menos para ti. Es el mismo
--  choque que ya tuvimos al ESCRIBIR en modo observador, pero al leer.
--
--  La decision es abrirlo, y no es un olvido. Tres razones:
--
--  1. Un roll es de dos. El heatmap ofensivo de Felipe contra Pablo ES el
--     defensivo de Pablo: buena parte de los datos de cada uno ya eran
--     visibles para el otro a traves de sus propios rolls. Lo que se abre de
--     nuevo son los rolls con terceros, no el grueso.
--  2. Son dos amigos y su coach, y compararse entre ellos es el objetivo
--     declarado del proyecto.
--  3. Se puede deshacer. Abrir una politica de lectura no es como añadir un
--     valor a un enum: si mañana entra gente de la academia, se cierra con
--     otra migracion y nadie pierde nada.
--
--  LO QUE HAY QUE TENER PRESENTE: esto abre las tablas CRUDAS por PostgREST,
--  no solo las vistas. Cualquier autenticado puede hacer
--  `/rest/v1/eventos?select=*` y ver los eventos de todos, con sus notas.
--  Aqui es aceptable; con gente de la academia dentro, no lo seria.
--
--  Las politicas de ESCRITURA no se tocan: cada uno sigue escribiendo lo suyo,
--  y los terceros solo a traves de registrar_roll_observado().
--
--  La version futura —perfil_publico por practicante, o visibilidad limitada a
--  la gente con la que has rodado— esta anotada en docs/02-backlog.md.
-- ------------------------------------------------------------

create policy sesiones_lectura_comun on sesiones
  for select to authenticated using (true);

create policy rolls_lectura_comun on rolls
  for select to authenticated using (true);

create policy eventos_lectura_comun on eventos
  for select to authenticated using (true);

comment on policy sesiones_lectura_comun on sesiones is
  'Analisis abierto entre practicantes. Ver el razonamiento en db/08_analisis.sql.';


-- ============================================================
--  2. LA PANTALLA, EN UNA LLAMADA
-- ============================================================
--
--  POR QUE UNA FUNCION Y NO LAS VISTAS QUE YA HAY
--
--  `v_heatmap_ofensivo` y compañia agregan con
--  `group by autor_id, posicion, objetivo...`, y en ese group by se pierden
--  `modalidad` y `fecha`. Sin esas dos columnas no se puede filtrar por gi /
--  nogi ni por ventana temporal, y filtrarlo en el cliente obligaria a volver
--  a sumar las celdas en React — que es exactamente lo que no queremos.
--
--  `v_eventos` si conserva las dos, asi que la agregacion se rehace aqui con
--  los filtros dentro. Las vistas existentes no se tocan: siguen sirviendo
--  para el caso sin filtros y para cualquier consulta suelta.
--
--  Devuelve un solo jsonb con la pantalla entera. Es una llamada en vez de
--  siete, que en un movil se nota, y ademas la forma del objeto es la misma
--  que la del HTML de referencia (docs/BJJ-Analisis-DEMO.html), asi que
--  comparar los numeros con el diseño aprobado es literal.
--
--  SECURITY INVOKER (por defecto): quien llama lee con sus permisos, que a
--  partir de las politicas de arriba son de lectura para todo.
-- ------------------------------------------------------------
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
  'tec', coalesce((select jsonb_agg(x order by x.ok desc, x.tot desc) from (
      select tecnica_nombre as nom,
             count(*) filter (where completado) as ok,
             count(*)                           as tot
        from ev
       where actor = 'yo' and tipo = 'sumision' and tecnica_nombre is not null
       group by tecnica_nombre
  ) x), '[]'::jsonb)
);
$$;

comment on function analisis(uuid, text, date) is
  'La pantalla de analisis entera, ya agregada y filtrada por modalidad y fecha. '
  'Existe porque las vistas v_heatmap_* agregan sin conservar modalidad ni fecha '
  'y no permiten el filtro gi/nogi. Misma forma que docs/BJJ-Analisis-DEMO.html.';


-- ------------------------------------------------------------
-- 3. De la celda a los rolls que hay detras
--
--    Lo que convierte la pantalla de poster en herramienta: pasar de "me
--    pillan mucho el cuello desde la espalda" a "fueron esos tres rolls con
--    Pablo de la semana pasada".
-- ------------------------------------------------------------
create or replace function analisis_rolls_celda(
  p_autor     uuid,
  p_actor     bjj_actor,
  p_posicion  bjj_posicion,
  p_objetivo  bjj_objetivo,
  p_modalidad text default null,
  p_desde     date default null
) returns table (
  roll_id   uuid,
  fecha     date,
  rival     text,
  origen    bjj_origen_roll,
  tecnica   text,
  completado boolean
)
language sql
stable
set search_path = public
as $$
  select e.roll_id, e.fecha,
         coalesce(p.nombre, 'sin registrar') as rival,
         r.origen, e.tecnica_nombre, e.completado
    from v_eventos e
    join rolls r on r.id = e.roll_id
    left join practicantes p on p.id = e.oponente_id
   where e.autor_id = p_autor
     and e.actor = p_actor
     and e.tipo = 'sumision'
     and e.posicion = p_posicion
     and e.objetivo = p_objetivo
     and (p_modalidad is null or e.modalidad_sesion::text = p_modalidad)
     and (p_desde is null or e.fecha >= p_desde)
   order by e.fecha desc, e.roll_id;
$$;
