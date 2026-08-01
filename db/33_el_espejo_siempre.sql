-- ============================================================
--  BJJ TRACKER — El espejo, siempre   ·   Migracion bjj_38
-- ============================================================
--
--  LA CAUSA, medida y no supuesta.
--
--  `espejar_roll()` llevaba esta guarda:
--
--      if not (select usa_sistema from practicantes where id = r.oponente_id)
--      then return null; end if;
--
--  No es un error y nadie se lo traga: `registrar_roll_observado` no tiene
--  NINGUN `exception when`, y `espejar_roll` tampoco. Es una salida temprana
--  deliberada que no produce nada y no dice nada.
--
--  De los 63 rolls observados huerfanos de produccion, **62 son esa guarda** y
--  el otro es un roll con `oponente_id` nulo, que es otra cosa y esta bien
--  como esta: sin oponente no hay a quien espejar. Cero caen fuera de esas dos.
--  Repartidos en diez dias distintos, del 6 de junio al 1 de agosto: no es una
--  ventana concreta, es la regla actuando siempre que el rival no tenia la
--  casilla.
--
--  NO ES REGRESION DE `bjj_35`. Comprobado contra una base con `bjj_35`
--  aplicada: con la casilla puesta salen los dos rolls, las dos sesiones y las
--  dos enganchadas al mismo Open Mat. La quedada que ahora lee `espejar_roll`
--  de `s.quedada_id` funciona.
--
--  ---------------------------------------------------------------------------
--  POR QUE SE QUITA LA GUARDA EN VEZ DE PEDIR QUE ALGUIEN MARQUE LA CASILLA
--  ---------------------------------------------------------------------------
--  Ayer se hizo lo segundo: se saco `usa_sistema` a la ficha con un nombre
--  honesto —«guardarle sus rolls»— para poder tocarlo. Y hoy vuelven a salir
--  ocho de ocho huerfanos, porque nadie lo marco. Un mecanismo no es un
--  arreglo cuando el modo de fallo es silencioso: lo que queda es una casilla
--  que hay que acordarse de marcar persona a persona antes de cada Open Mat,
--  y el precio de olvidarla es perder la mitad de cada roll sin que nada avise.
--
--  El invariante que se quiere es incondicional: **un roll observado deja dos
--  rolls**. Asi que la condicion se va.
--
--  QUE SIGNIFICA AHORA `usa_sistema`: si esa persona usa la app. Nada mas.
--  Ya no decide si se le guardan sus rolls — se le guardan siempre.
--
--  LO QUE NO SE TOCA:
--   · la salida por `oponente_id` nulo: sin rival no hay espejo posible;
--   · la salida por «ya existe el espejo de este par», que es lo que hace que
--     reintentar desde la cola no duplique;
--   · el resto del cuerpo: se invierten `resultado`, `rol_inicio` y el `actor`
--     de cada evento, y NADA MAS. `posicion` y `rol` describen a la misma
--     persona fisica en las dos filas.
--
--  Se opera sobre la definicion VIVA: el cuerpo de una funcion se guarda
--  verbatim, asi que el reemplazo textual es exacto, y `pg_get_functiondef`
--  arrastra `SET search_path` — que es lo que se perdio la ultima vez que se
--  recreo esta funcion a mano.
-- ============================================================

begin;

do $bloque$
declare d text; nuevo text;
begin
  d := pg_get_functiondef('public.espejar_roll(uuid)'::regprocedure);

  -- SE ANCLA EN CODIGO, NUNCA EN COMENTARIOS. El cuerpo que hay en produccion
  -- y el que produce este repo en local NO son el mismo texto: al aplicar por
  -- el MCP los comentarios se pierden, asi que en local la guarda lleva encima
  -- un `-- solo se espeja a quien tiene cuenta` que en produccion no existe.
  -- La primera version de esta migracion anclaba incluyendolo y no encajaba en
  -- local; en produccion habria «funcionado» por el motivo equivocado.
  -- Por eso el patron se come ese comentario si esta y no lo exige si no.
  nuevo := regexp_replace(d,
    '([ \t]*--[^\n]*\n)?' ||
    '[ \t]*if not \(select usa_sistema from practicantes ' ||
    'where id = r\.oponente_id\) then[ \t]*\n' ||
    '[ \t]*return null;[ \t]*\n' ||
    '[ \t]*end if;[ \t]*\n',
'  -- Aqui vivia la guarda de `usa_sistema`, y se fue en bjj_38. Decidia si al
  -- companero se le guardaba su mitad del roll, se escribia en `false` al dar
  -- de alta a alguien, y estuvo mucho tiempo sin poder cambiarse desde ninguna
  -- pantalla: 62 de los 63 rolls huerfanos de produccion salieron de aqui.
  -- Un roll observado deja DOS rolls, sin condiciones.
');
  if nuevo = d then
    raise exception 'NO ENCONTRE la guarda de usa_sistema en espejar_roll. '
      'No se toca nada: mira la definicion viva antes de reintentar.';
  end if;

  execute nuevo;
end $bloque$;

-- Se comprueba aqui mismo, sobre la funcion recien escrita, que las otras dos
-- salidas siguen en su sitio. Quitar una guarda de mas seria peor que el fallo
-- que se viene a arreglar: la de `oponente_id` evita espejar contra nadie y la
-- de «ya existe» es lo que hace idempotente el reintento de la cola.
do $$
declare src text;
begin
  select prosrc into src from pg_proc where proname = 'espejar_roll';
  if src not like '%if r.oponente_id is null then return null; end if;%' then
    raise exception 'SE HA IDO LA GUARDA DE oponente_id NULO';
  end if;
  if src not like '%where r2.par_id = r.par_id%' then
    raise exception 'SE HA IDO LA GUARDA DE IDEMPOTENCIA: reintentar duplicaria rolls';
  end if;
  -- Se busca LA GUARDA, no la palabra. La primera version comprobaba
  -- `like '%usa_sistema%'` y saltaba por el comentario que deja la propia
  -- cirugia tres lineas mas arriba: la operacion habia salido bien y la
  -- comprobacion decia que no. Una comprobacion que no distingue el codigo del
  -- comentario que habla del codigo no comprueba nada.
  if src like '%if not (select usa_sistema%' then
    raise exception 'LA GUARDA DE usa_sistema SIGUE AHI';
  end if;
  raise notice 'OK  fuera la de usa_sistema; siguen la de oponente nulo y la de idempotencia';
end $$;

comment on function public.espejar_roll(uuid) is
  'Crea el roll espejo del companero: misma posicion y mismo rol —describen a '
  'la misma persona fisica— con `resultado`, `rol_inicio` y el `actor` de cada '
  'evento invertidos. Desde bjj_38 NO depende de `usa_sistema`: un roll '
  'observado deja siempre dos rolls. Solo no espeja si no hay oponente o si el '
  'espejo de ese par ya existe.';

commit;
