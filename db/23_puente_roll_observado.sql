-- ============================================================
--  BJJ TRACKER — Puente para la cola vieja   ·   Migracion bjj_28
-- ============================================================
--
--  QUE ARREGLA. `bjj_27` renombro el primer parametro de
--  `registrar_roll_observado()` de `p_grupo` a `p_par`, y ESE NOMBRE VIAJA
--  SERIALIZADO dentro de IndexedDB. Un roll observado que quedara en la cola de
--  un cliente viejo llega con `p_grupo`, PostgREST no encuentra ninguna funcion
--  con ese conjunto de nombres y contesta PGRST202 — un 404.
--
--  Y UN 4xx NO SE REINTENTA. `sync.ts` lo trata como error de datos y manda el
--  elemento a "necesita atencion", que es el comportamiento correcto para un
--  payload invalido pero aqui significa PERDER UN ROLL YA REGISTRADO. Ese es el
--  unico fallo que este producto no se puede permitir: la app existe para no
--  perder lo que apuntaste en el tatami.
--
--  Con este puente, aplicar `bjj_27` deja de estar acoplado a que los cuatro
--  hayan sincronizado antes. Se despliega cuando se quiera.
--
--  ---------------------------------------------------------------------------
--  POR QUE CAMBIA UN TIPO Y NO SOLO LOS NOMBRES
--  ---------------------------------------------------------------------------
--  Postgres identifica una funcion por (nombre, TIPOS de los argumentos). Los
--  nombres de los parametros no entran. Crear la misma firma con otros nombres
--  da:
--
--      ERROR:  function "registrar_roll_observado" already exists
--              with same argument types
--
--  Comprobado, no supuesto. Asi que el puente declara `p_duracion_min` como
--  `integer` en vez de `smallint`: es el cambio mas inocuo posible —el cliente
--  manda un numero de JSON en los dos casos— y basta para que sean dos
--  funciones distintas para Postgres.
--
--  PostgREST, en cambio, resuelve la RPC por el CONJUNTO DE NOMBRES que llegan
--  en el cuerpo. Los dos conjuntos son disjuntos —uno trae `p_grupo`, el otro
--  `p_par`— asi que no hay ambiguedad posible: cada cliente cae en su funcion.
--
--  La llamada interna castea a `smallint`, con lo que la resolucion de tipos de
--  Postgres encuentra coincidencia EXACTA con la funcion nueva. Sin ese cast
--  habria riesgo de que se llamara a si misma.
--
--  ---------------------------------------------------------------------------
--  ESTO ES TEMPORAL Y SE BORRA
--  ---------------------------------------------------------------------------
--  Reintroduce el nombre ambiguo que `bjj_27` vino a quitar, y por eso no se
--  queda. La condicion para borrarlo esta en docs/BACKLOG.md: cuando ninguno de
--  los cuatro tenga elementos en la cola. Mientras exista, el comprobador de
--  vocabulario NO se queja porque solo mira nombres de funcion, tabla, columna y
--  tipo — `p_grupo` es un nombre de parametro y se le escapa. Es justo la mitad
--  que el propio script dice que no ve.
-- ============================================================

begin;

create function public.registrar_roll_observado(
  p_grupo uuid, p_practicante_a uuid, p_practicante_b uuid, p_fecha date,
  p_modalidad bjj_modalidad, p_duracion_min integer, p_posicion_inicio bjj_posicion,
  p_rol_inicio bjj_rol, p_resultado bjj_resultado_roll, p_eventos jsonb)
returns jsonb language sql
set search_path = public as $$
  select public.registrar_roll_observado(
           p_grupo, p_practicante_a, p_practicante_b, p_fecha, p_modalidad,
           p_duracion_min::smallint, p_posicion_inicio, p_rol_inicio,
           p_resultado, p_eventos)
$$;

comment on function public.registrar_roll_observado(uuid, uuid, uuid, date,
  bjj_modalidad, integer, bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb) is
  'PUENTE TEMPORAL (bjj_28). Acepta el nombre de parametro viejo `p_grupo` y '
  'delega en la version buena, que lo llama `p_par`. Existe solo para que un '
  'roll observado que quedara en la cola de IndexedDB de un cliente anterior a '
  'bjj_27 pueda subir en vez de perderse con un 404. Se borra cuando nadie '
  'tenga cola pendiente; la condicion esta en docs/BACKLOG.md.';

-- SECURITY INVOKER a proposito: el puente no necesita privilegios propios, solo
-- delega. Quien lo llama ya tiene EXECUTE sobre la funcion buena, que si es
-- SECURITY DEFINER y hace el trabajo. Menos superficie por el mismo resultado.

-- Y EL REVOKE, que es donde muerde. Postgres regala EXECUTE a PUBLIC en toda
-- funcion nueva y `anon` hereda de PUBLIC: sin esta linea, esta funcion abre a
-- los anonimos justo la puerta que cerro bjj_25. Ya paso al recrear cuatro
-- funciones en bjj_27 y lo cazaron los casos 27 y 48 de db/pruebas/rls.sql.
revoke all on function public.registrar_roll_observado(uuid, uuid, uuid, date,
  bjj_modalidad, integer, bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb)
  from public;
grant execute on function public.registrar_roll_observado(uuid, uuid, uuid, date,
  bjj_modalidad, integer, bjj_posicion, bjj_rol, bjj_resultado_roll, jsonb)
  to authenticated, service_role;

commit;
