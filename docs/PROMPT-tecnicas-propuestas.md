# Prompt para Claude Code — técnicas propuestas

**Este bloque va DESPUÉS de `PROMPT-mecanicas.md`.** Necesita la migración de
mecánicas aplicada. No lo empieces antes.

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a montar el circuito para que **cualquiera pueda proponer una técnica que
falta y un admin la revise**. Lee antes `CLAUDE.md` y
`docs/PROMPT-mecanicas.md`, que es de donde sale esto.

## Lo que de verdad va a pasar, y por eso el diseño es este

El instinto dice: formulario, cola de pendientes, botón de aprobar. Pero cuando
alguien dice "falta el J-Lock", **lo más probable no es que falte una técnica: es
que falta un nombre**. La técnica ya está en el catálogo, con otro nombre, o con
el nombre de otro país, o con el que usa su profesor y no el que usa el suyo.

Así que la pieza central de este bloque **no es el formulario, es el buscador**, y
la acción por defecto del revisor **no es aprobar ni rechazar, es "esto ya existe,
se llama Americana, y añado tu nombre como alias"**. El que propuso sale ganando:
a partir de ese momento buscar "J-Lock" encuentra la ficha. Nadie ha perdido y el
catálogo no ha crecido.

Un catálogo compartido solo se mantiene limpio si añadir cuesta más que buscar.

## Fase 1 · Esquema

Migración **`bjj_NN_tecnicas_propuestas`** — la siguiente etiqueta libre según tu
inventario.

```sql
create type bjj_estado_tecnica as enum ('activa','propuesta','fusionada');

alter table tecnicas
  add column estado          bjj_estado_tecnica not null default 'activa',
  add column ambito_equipo_id uuid references equipos(id) on delete cascade,
  add column propuesta_por   uuid references practicantes(id),
  add column fusionada_en    uuid references tecnicas(id),
  add column propuesta_en    timestamptz;
```

Los tres estados:

- **`activa` con `ambito_equipo_id` nulo** — el catálogo global. Las 71 filas de
  hoy. **Solo se toca por migración.**
- **`activa` con `ambito_equipo_id`** — adoptada por un equipo. Real y usable,
  pero solo ahí.
- **`propuesta`** — recién creada por alguien, siempre con equipo. Usable ya, y
  marcada como tal.
- **`fusionada`** — resuelta contra otra: `fusionada_en` dice cuál. **Nunca se
  borra.** Ver abajo, que es lo importante de todo el bloque.

Una propuesta **es usable desde el minuto uno** por todo su equipo, marcada con un
distintivo. Alternativa descartada: dejarla inservible hasta que la aprueben, que
convierte proponer en rellenar un formulario y esperar. Nadie hace eso dos veces.
El desorden se ve, y lo que se ve se limpia.

### Lo que hay que cambiar de la RLS de `tecnicas`

Hoy la política es `for select using (true)`, y con esto deja de valer: una
propuesta del equipo A no la puede ver el equipo B.

```sql
using (
      (estado <> 'propuesta' and ambito_equipo_id is null)
   or ambito_equipo_id in (select private.mis_equipos())
)
```

Ese helper ya existe: hoy es `private.mis_grupos()` y la tanda de vocabulario lo renombra a
`private.mis_equipos()`. Úsalo, no metas la subconsulta a pelo en la política —
así es como se acaba con seis copias de la misma regla.

Insert: un autenticado puede crear **solo** con `estado = 'propuesta'`,
`propuesta_por = private.practicante_actual()` y un `ambito_equipo_id` que sea
suyo. Si pone madre, la restricción de un solo nivel de las mecánicas ya le impide
colgarla de una variante — no la dupliques.

**No des `update` sobre `tecnicas` a nadie.** Postgres no tiene RLS por columna:
una política que deje corregir una errata deja también cambiar `estado` a
`activa` y colar una técnica en el catálogo global. Todo lo que cambia estado va
por RPC, igual que en las mecánicas.

## Fase 2 · Las tres acciones del revisor, y una es especial

Tres RPC `SECURITY DEFINER`, todas restringidas a **admin del equipo** (el rol que
ya existe desde `bjj_09`), todas con `revoke execute from anon, public`:

```
adoptar_tecnica(p_tecnica_id)                 -- propuesta -> activa, sigue en el equipo
fusionar_tecnica(p_origen_id, p_destino_id)   -- "esto ya existía"
alias_de_tecnica(p_tecnica_id, p_alias text)  -- "esto ya existía y solo faltaba el nombre"
```

### `fusionar_tecnica` es la peligrosa. Léela entera.

`eventos_tecnica_id_fkey` está declarada **`on delete set null`**. Es decir: si
alguien resuelve una propuesta duplicada **borrando la fila**, Postgres no da
ningún error — se limita a dejar en nulo la técnica de todos los eventos que la
apuntaban. Pierdes el dato en silencio, y no hay forma de recuperarlo.

Así que **rechazar es fusionar, y fusionar nunca borra.** La RPC, en una sola
transacción:

1. Comprueba que origen y destino son visibles para quien llama, y que el origen
   está en `propuesta`.
2. Reasigna `eventos.tecnica_id` de origen a destino.
3. Reasigna las apariciones del origen dentro de `enfoques.tecnicas` (es un
   `uuid[]`: `array_replace`), y **deduplica** — si alguien tenía las dos en el
   mismo enfoque, se queda una.
4. Vuelca los `alias` del origen en los del destino, sin duplicar, y **añade el
   `nombre` del origen como alias del destino**. Ese es el paso que hace que la
   fusión sea una ganancia y no una pérdida: el nombre que esa persona usa pasa a
   encontrar la técnica buena.
5. `estado = 'fusionada'`, `fusionada_en = destino`.
6. No hay paso 6. **No hay `delete` en esta función.**

Y cuando alguien abra un roll viejo cuya técnica se fusionó, que la pantalla
enseñe la de destino con una nota discreta, no un hueco.

### `alias_de_tecnica` es la que más se va a usar

Añade un alias al array —que ya existe, con su índice GIN— y descarta la
propuesta como fusionada contra esa técnica. Es la ruta de un toque para el caso
mayoritario, y quiero que en la pantalla sea **la opción que se ve primero**, no
la escondida detrás de un menú.

## Fase 3 · Las pantallas

### Proponer, que es sobre todo buscar

- Se entra desde el selector de técnica al registrar: **"no encuentro la mía"**,
  al final de la lista. No hay otra puerta.
- Lo primero y lo más grande es el **buscador, sobre `nombre` y `alias` a la vez**
  —el índice GIN de `alias` ya está—, tolerante a acentos y a erratas. Si escribe
  "jlock", "j-lock" o "kesa americana", tiene que salir la americana.
- El botón de crear aparece **debajo de los resultados, no encima**, y solo
  después de haber buscado.
- El formulario es corto: nombre, tipo, y opcionalmente **de qué técnica es
  variante** —con la regla de las mecánicas escrita ahí mismo en una línea: *la
  posición de entrada no crea una variante*—. Nada más. Cuantos más campos, menos
  propuestas y peores.

### Revisar

- Una lista en la pantalla de Team, visible **solo para admins**, con las propuestas del equipo:
  quién, cuándo, y **cuántos eventos la usan ya** (es el dato que decide: una con
  treinta usos se adopta, una con cero casi siempre es un duplicado).
- Las tres acciones, con **"ya existe: añadir como alias" primero**.
- Al fusionar, un buscador de destino igual que el de proponer.
- Y que diga qué va a pasar antes de hacerlo: *"18 eventos pasarán a Americana"*.
  Una fusión mueve datos de otras personas; se enseña el alcance antes.

## Cómo lo verificas

1. `npm run build` pasa, typecheck estricto incluido.
2. **La migración aplica desde cero**, en orden alfabético detrás de la de mecánicas.
3. **Aislamiento entre equipos, probado**: una propuesta del equipo A devuelve cero
   filas para un miembro del equipo B, en la tabla **y a través de las vistas**.
   Va a `db/pruebas/rls.sql`.
4. **Nadie que no sea admin ejecuta las tres RPC.** Y `anon` tampoco: míralo en
   `information_schema.routine_privileges`.
5. **Un autenticado no puede insertar con `estado = 'activa'`**, ni con
   `ambito_equipo_id` nulo, ni a nombre de otro. Tres casos, los tres tienen que
   fallar.
6. **La fusión, con datos de verdad**: propuesta con eventos y presente en un
   enfoque. Después, esos eventos apuntan al destino, el enfoque no tiene
   duplicados, el nombre viejo está entre los alias del destino, y **el total de
   eventos con técnica no nula es el mismo que antes**. Ese último recuento es la
   prueba de que no se ha borrado nada.
7. **Fusionar dos veces la misma es inocuo** (la segunda no encuentra origen en
   `propuesta` y falla limpio). La cola offline reintenta; una RPC que no es
   idempotente acaba duplicando trabajo.
8. Probado a 390px, en tema claro y oscuro.
9. Migración **primero contra el Postgres local**.

## Fuera de alcance

**Promocionar una técnica al catálogo global** (`ambito_equipo_id` a nulo). Eso lo
decide Felipe y se hace por migración. La app no tiene botón para ello y no
quiero que lo tenga todavía: el catálogo global es el vocabulario común de todos
los gimnasios y no se toca desde una pantalla.

**Editar una técnica global.** Ni erratas. Por migración.

**Notificar al que propuso** cuando su propuesta se resuelve. Va por el feed
cuando toque, no hay push.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios— y tacha lo que corresponda en `docs/BACKLOG.md`.
