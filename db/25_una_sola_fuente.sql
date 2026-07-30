-- ============================================================
--  BJJ TRACKER — Una sola fuente para "intentos por tecnica" · bjj_30
-- ============================================================
--
--  QUE ARREGLA. `bjj_29` dejo dos sitios calculando lo mismo:
--
--    - `v_tecnicas_practicante`, que agrupa intentos y finalizaciones por
--      tecnica y mecanica;
--    - el bloque `tec` de `analisis()`, que hacia exactamente eso otra vez
--      porque la vista no llevaba `modalidad` ni `fecha` y la pantalla filtra
--      por gi/nogi y por ventana temporal.
--
--  Dos implementaciones del mismo recuento son dos fuentes de la verdad
--  esperando a separarse. Ya sabemos como acaba eso aqui: el marcador vive dos
--  veces —`puntos.ts` y `puntos_roll()`— y por eso tiene un fixture compartido
--  y dos baterias que leen los mismos casos. Aqui no hace falta pagar ese
--  precio, porque una de las dos puede desaparecer.
--
--  COMO. La vista pasa a llevar `modalidad` y `fecha` —grano mas fino, mismo
--  significado— y `analisis()` LEE DE ELLA en vez de recalcular. La vista queda
--  como el unico sitio donde se define que cuenta como intento de una tecnica.
--
--  POR QUE LA MODALIDAD ES LA DE LA SESION y no la del roll: es lo que ya hacia
--  `analisis()`, que filtra por `modalidad_sesion`. Cambiarlo aqui movería
--  numeros sin que nadie lo hubiera pedido.
--
--  VERIFICADO comparando el `tec` de `analisis()` antes y despues, para los
--  tres filtros (todo, gi, nogi): mismos md5. Si hubieran salido distintos, la
--  vista y el panel no estaban contando lo mismo — que es justo lo que este
--  bloque viene a hacer imposible.
-- ============================================================

begin;

-- La vista se RECREA, no se renombra ninguna columna, asi que hay que repetir
-- `security_invoker = on` a mano: recrear es drop + create por dentro y el
-- ajuste no sobrevive solo. Lo comprueba scripts/comprobar-vocabulario.py.
drop view v_tecnicas_practicante;

create view v_tecnicas_practicante
with (security_invoker = on) as
select s.practicante_id,
       t.mecanica_id,
       t.id                                 as tecnica_id,
       s.modalidad,
       s.fecha,
       count(*)                             as intentos,
       count(*) filter (where e.completado) as completados
  from eventos e
  join tecnicas t on t.id = e.tecnica_id
  join rolls r    on r.id = e.roll_id
  join sesiones s on s.id = r.sesion_id
 where e.actor = 'yo' and e.tipo = 'sumision'
 group by s.practicante_id, t.mecanica_id, t.id, s.modalidad, s.fecha;

comment on view v_tecnicas_practicante is
  'EL UNICO sitio donde se define que cuenta como intento de una tecnica. '
  'Lleva modalidad y fecha para que analisis() pueda filtrar por gi/nogi y por '
  'ventana temporal LEYENDO DE AQUI en vez de recalcularlo. Si hace falta un '
  'corte nuevo, se añade aqui y lo heredan los dos.';

commit;

-- ---------- analisis(), leyendo de la vista
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
  -- PLEGADO POR MECANICA, LEYENDO DE `v_tecnicas_practicante`.
  --
  -- Antes esto recalculaba el mismo recuento que la vista, porque la vista no
  -- llevaba modalidad ni fecha. Eran dos fuentes de la verdad para "intentos
  -- por tecnica": bjj_30 le puso las dos columnas y aqui se lee de ella.
  --
  -- `compara` es la guarda de volumen: la frase "tu tarikoplata entra el 44% y
  -- tu kimura clasica el 20%" solo se puede decir con al menos dos tecnicas de
  -- cinco intentos cada una. 1 de 1 no es el 100%. La guarda va aqui y no en
  -- React porque es una decision sobre el dato, no sobre el dibujo.
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
          select v.mecanica_id, v.tecnica_id, t.nombre as nom,
                 sum(v.completados)::int as ok,
                 sum(v.intentos)::int    as tot
            from v_tecnicas_practicante v
            join tecnicas t on t.id = v.tecnica_id
           where v.practicante_id = p_autor
             and (p_modalidad is null or v.modalidad::text = p_modalidad)
             and (p_desde is null or v.fecha >= p_desde)
           group by v.mecanica_id, v.tecnica_id, t.nombre
        ) d
        join tecnicas m on m.id = d.mecanica_id
       group by m.id, m.nombre
  ) x), '[]'::jsonb)
);
$$;

commit;
