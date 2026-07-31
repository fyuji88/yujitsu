# Registro de cambios

Lo escribe **Claude Code al terminar cada tanda de trabajo**, y es parte de la
definición de terminado. Lo lee el PM al empezar cada sesión, y se audita en la
retro de los domingos cruzándolo con las migraciones aplicadas y con `git log`.

**Más nuevo arriba. Diez líneas por entrada como máximo.**

Qué es obligatorio y qué no:

- **Migraciones** aplicadas, si hubo.
- **Decisiones** tomadas por el camino. Obligatorio. Es lo que ni el `git log` ni
  el esquema me cuentan, y es lo que evita que se vuelva a discutir algo cerrado.
- **Sabido roto**: lo que dejaste a medias o funcionando mal a propósito.
  Obligatorio. Es lo que más tiempo ahorra.
- **Backlog**: qué tachaste o añadiste en `docs/BACKLOG.md`.
- La lista de ficheros es **opcional** — eso ya está en el `git log`.

---

## 2026-08-07 · El informe salía vacío porque faltaba la tubería

**Migración:** `bjj_33_enganchar_la_quedada` (`db/28_enganchar_la_quedada.sql`).

**El diagnóstico, medido: 0 de 71 sesiones tenían `quedada_id`. Ninguna, nunca.**
Y de esa columna cuelga todo el bloque: `metricas_quedada` hace
`from rolls join sesiones where s.quedada_id = p_quedada`, así que devolvía cero
filas siempre. El informe, el ranking, los títulos y los **tres** logros de
ámbito quedada estaban construidos y alimentándose de una columna que **nadie
escribía**. El informe no estaba roto: estaba desconectado.

(El encargo decía cuatro logros de ámbito quedada; son tres: `artista`,
`ambidiestro`, `notario`. Ninguno se había disparado nunca, para nadie.)

**Decisión: una RPC aparte, no un parámetro más en
`registrar_roll_observado`.** Esa función ya tiene DOS firmas por el puente de
`p_grupo` y es lo único que la cola serializa dentro de IndexedDB. Una tercera
firma es pedir el mismo problema otra vez. Se añaden
`enganchar_sesion_a_quedada`, `desenganchar_sesion`, `enganchar_del_dia` y
`alcance_quedada`.

**Decisión: `enganchar_del_dia` sirve para dos cosas** —el modo observador y el
arreglo hacia atrás— porque son la misma operación con distinto disparador.
Engancha lo que puedes: lo tuyo, lo cuyos rolls registraste, y —si eres admin—
lo de quien está apuntado.

**La guarda de fecha es la que más veces va a salvar el dato**: impide colgar el
entreno del martes del Open Mat del domingo, que es el error fácil desde el
botón de "enganchar las de hoy" y el que nadie detectaría después.

**`cerrar_quedada` ya no cierra sin nada que contar.** Hay tres informes en
producción escritos con cero rolls, sin una advertencia, y cerrar es de una sola
dirección. Ahora se planta con un mensaje que dice qué pasa **y qué hacer**, y
la pantalla enseña el alcance antes: *"se van a incluir 14 rolls de 5 personas"*.

**Un fallo del cliente que salió por el camino:** `v_mi_quedada_hoy` se leía con
`.maybeSingle()`, así que con **dos** Open Mats el mismo día la consulta fallaba
y no se enganchaba **ninguna** — el caso raro se llevaba por delante el normal.
Ahora se leen todas y, si hay dos, se pregunta.

**Sabido roto:**
- **`sesion_del_dia` agrupa por (practicante, fecha, modalidad, academia).** Si
  alguien entrena por la mañana en su gimnasio y por la tarde va al Open Mat con
  la misma modalidad y la misma academia, los dos entrenos caen en la **misma
  sesión**, y engancharla arrastraría también los rolls de la mañana. Con
  academias distintas no pasa. **No se arregla en esta tanda**: está en el
  backlog.
- Los tres informes vacíos y las quedadas ya cerradas **se quedan como están**.
  Eso lo decide Felipe.
- En `pruebas/cola.js`, la comprobación de cuántos elementos lista el detalle
  pasa a `>= 1`: entre instalar el bloqueo y recargar, la cola puede haber
  subido parte, y cuántos quedan depende de la carrera y no del producto. Lo que
  prueba ahora es que el detalle **lista** lo que falta; el cuántos lo comprueba
  la píldora justo antes.

---

## 2026-08-06 · Administrar un Open Mat

**Migración:** `bjj_32_admin_de_quedadas` (`db/27_admin_de_quedadas.sql`).
Ni una política nueva: **la RLS ya lo permitía todo**. Lo que faltaba no era
permiso, era que la lógica de plazas no se pudiera saltar.

**Decisión: apuntar a otro va por la RPC, nunca por un insert directo.** La RLS
deja a un admin insertar en `inscripciones`, y si lo hace se salta el reparto de
plazas: acabas con nueve personas en ocho, o con alguien en `apuntado` que
debería estar en `lista_espera`. `apuntarse_a_quedada` y `cancelar_inscripcion`
llevan ahora un `p_practicante` opcional que exige `es_admin` si no eres tú.

**El cambio de firma, mirado antes de tocarlo** —la lección de `p_grupo`—: se
comprobó que **la cola no serializa esa llamada** (solo lleva sesiones, rolls,
eventos y el roll observado), y se **tiró la versión vieja** en vez de añadir
una sobrecarga, porque con las dos una llamada `{p_quedada, p_token}` encajaría
en ambas y PostgREST no sabría cuál. Hay una prueba de que la llamada de hoy
sigue resolviendo.

**Decisión: las plazas las vigila un trigger, no la pantalla.** La RLS deja al
admin hacer un `update quedadas` directo, así que una regla que solo viva en
React se salta con una llamada a la API. Bajar por debajo de los apuntados se
rechaza con el número dentro (*"no puedes bajar a 0 plazas: hay 1 apuntados"*) y
subir promueve desde la lista. **La promoción está escrita una vez** —
`private.promover_lista_espera()`— y la llaman los tres caminos.

**Decisión: borrar solo si no cuelga nada, y el botón no existe si cuelga algo.**
Comprobado en el esquema: `inscripciones` y `quedada_informes` van en CASCADE y
`sesiones` en SET NULL. Borrar parece limpieza y en realidad se lleva los
apuntados, el informe, y **desengancha rolls de otra gente** — con lo que los
cuatro logros de ámbito quedada dejan de contar para esas sesiones y nadie se
entera. No se enseña apagado: no se enseña.

**Decisión: a quien tiene cuenta no lo mete el admin.** Entrar en un equipo le
da acceso a los rolls de todos y da al equipo acceso a los suyos: eso es un
cambio de privilegios sobre datos de otra persona y no se hace por sorpresa. La
pantalla lo dice y enseña el código de unión, para que parezca una decisión y no
una función que falta. Los contactos sin cuenta sí se añaden directos.

**Un fallo real que salió al probarlo:** un Open Mat cancelado **desaparecía de
las dos listas** —lo filtraba `proximas` y su fecha aún no había llegado para
`pasadas`—, así que la única señal de que se había cancelado era que ya no
estaba. Justo al revés de lo que hace falta.

**Pruebas:** `db/pruebas/admin-quedadas.sql` (los cuatro caminos de las plazas,
en CI), cuatro casos de "equipo equivocado" en `rls.sql` —que sube a **59**— y
`pruebas/admin-quedadas.js`, 11 comprobaciones en navegador. La batería entera
son **9 recorridos**, corridos dos lotes seguidos.

**Sabido roto:**
- Que un no-admin cree un Open Mat sigue sin poder ser: hoy `quedadas_admin` es
  la única política de escritura. Es una decisión de producto, no un arreglo.
- `enfoques.js` no limpiaba lo suyo y tumbaba al recorrido siguiente dentro del
  lote. Ya limpia. Es la tercera vez que pasa esto: **el que escribe, limpia**.

---

## 2026-08-05 · Blindar el registro en vivo

**Migraciones:** ninguna. Es todo cliente, como pedía el encargo.

**La píldora distingue dos cosas que no son la misma.** `sin subir` va a llegar
solo; `con error` necesita que alguien mire. Antes las metía a las dos en "error
al sincronizar", que hacía parecer grave lo pasajero y pasajero lo grave. Es
tocable y abre un detalle con qué hay, desde cuándo, el motivo del rechazo y
reintentar.

**Decisión: descartar solo se ofrece para lo que el servidor rechaza.** Lo que
sigue en cola va a entrar solo, y poner un botón de tirarlo sería invitar a
perder un roll por impaciencia. Y nunca automático: la cola no descarta nada
jamás, solo una persona.

**Decisión: la espera creciente es GLOBAL, no por elemento.** La primera versión
le daba a cada uno su propio reloj, y eso **rompe el orden `sesiones → rolls →
eventos`**: si una sesión estaba cumpliendo su espera y su roll ya tocaba, el
roll salía solo y la clave foránea lo rechazaba. Se vio tal cual en el
recorrido — *llegó la sesión y el roll, y los eventos se quedaron fuera*. Un
fallo de red no le pasa a una fila, le pasa a la conexión.

**Decisión: un 23505 es "ya estaba", no un fallo.** Con `upsert` no debería
pasar, y si pasa significa que el envío anterior sí llegó y lo que se perdió fue
la respuesta — que es justo el caso para el que existe la cola. Se da por
entregado en vez de parquearlo como error.

**Y el arnés mentía de dos formas, las dos graves:**

1. `consultar()` corría psql **sin `ON_ERROR_STOP`**: tras un ERROR psql seguía,
   el `commit` se volvía rollback y el proceso salía con 0. Una escritura
   **rechazada por Postgres le llegaba al cliente como 201**, la cola la daba
   por subida y la borraba. Pérdida silenciosa de datos dentro de las pruebas,
   que es el peor sitio: hace que los recorridos den verde justo cuando deberían
   estar rojos.
2. El puente hacía `insert` pelado donde el cliente hace `upsert`, así que un
   reintento —**el caso normal cuando vuelve la red**— reventaba con "duplicate
   key". Un arnés que rompe el invariante que protege el producto inventa fallos
   que no existen. Y no devolvía `code`, así que el cliente no podía distinguir
   un 4xx de una caída de red: ahora devuelve el SQLSTATE, como PostgREST.

**`pruebas/cola.js`**, octavo recorrido, 16 comprobaciones: modo avión con la
píldora contando, recarga (sigue ahí, está en IndexedDB), vuelta de la red y
**comprobación en la base de que llegó todo, no solo la sesión**, un 4xx que
sale como error y **no entra en bucle**, descarte a mano, y el aviso al cerrar.
Corrido tres veces seguidas antes de darlo por estable.

**Sabido roto:**
- El recolector de errores (Sentry) sigue pendiente: hace falta una cuenta y una
  clave que da Felipe. Sin él seguimos enterándonos de los fallos porque alguien
  los cuenta.
- Los recorridos que escriben tienen que limpiar lo suyo o la semilla deriva y
  `analisis.js` empieza a fallar solo, lejos de su causa. Ya pasó durante esta
  tanda. Los tres que escriben lo hacen; el siguiente que se añada, también.

---

## 2026-08-04 (tarde) · Sellar los eventos espejo

**Migración:** `bjj_31_sellar_el_espejo` (`db/26_sellar_el_espejo.sql`),
aplicada a producción. **1424 eventos sellados, 612 pares.**

El diagnóstico bueno no era mío: yo lo había cerrado como "descartado" porque
emparejar por `created_at` es frágil. Pero eso era la solución mala, no el
problema — **lo que faltaba era el enlace**. `eventos.par_evento_id` es a los
eventos lo que `par_id` es a los rolls: `registrar_roll_observado()` lo genera y
`espejar_roll()` lo copia, así que `precisar_tecnica()` actualiza los dos. Un
solo hecho físico deja de poder tener dos nombres.

**El relleno hacia atrás empareja por POSICIÓN dentro del roll**, que es el
orden en que `espejar_roll()` los insertó. Comprobado **antes** de escribir
nada: 99 pares con dos rolls, los 99 con el mismo número de eventos, ninguno
descuadrado. No se ordena por `id` —el espejo tiene ids nuevos— sino por lo que
el espejo copia tal cual, y nunca por `actor`, que es lo único que se invierte.
Si quedan dos eventos empatados en todo eso son indistinguibles para lo que
`precisar` hace, así que la ambigüedad restante es inofensiva por construcción.

**Y una comprobación mía que pasaba en vacío.** El bloque que verifica el
relleno dijo "todo bien" en una base **sin ningún par espejo**: no había mirado
nada. Ahora dice cuántos pares ha comprobado, y avisa a gritos cuando son cero.
Una comprobación que no puede fallar no es una comprobación — la tercera regla
de CLAUDE.md, aplicada a mí mismo.

**Sabido roto:** nada nuevo. Con esto se cierra el bloque de mecánicas.

---

## 2026-08-04 · Los tipos, generados desde la base

**Migración:** ninguna.

**El arreglo del agujero que costó el bug de `bjj_27`**, no el cinturón.
`scripts/generar-tipos.py` vuelca el esquema real a `src/lib/esquema.generado.ts`
y `database.types.ts` **comprueba contra él en tiempo de compilación**. Un
renombrado sin actualizar el cliente deja de compilar.

**Decisión: NO se regenera `database.types.ts`.** Está escrito a mano a
propósito: es un subconjunto y lleva dentro el porqué de cada decisión —por qué
`p_par` se llama así, por qué `posicion` es física, por qué `orden_en_sesion` no
es el orden de la quedada—. Regenerarlo borraría justo lo que hace que valga
algo. Se genera un fichero **aparte**, que nadie lee, y el de mano compara
contra él. Las dos mitades se quedan: el comentario donde hace falta y la verdad
donde tiene que estar.

**Probado viéndolo fallar, dos veces.** Reintroduciendo el bug real
(`orden_en_sesion` → `orden`) deja de compilar; y con un campo que **no usa
nadie** salta el aserto solo, en `database.types.ts:299` — que es el caso que
importa, porque un campo opcional que nunca se escribe no lo caza el punto de
uso.

**Y el generador ya cazó una desviación**: mi base local de desarrollo seguía
teniendo `sesiones.molestias`, que `bjj_26` borró. Por eso el fichero se genera
desde el esquema **canónico** —el que el CI construye desde cero— y no desde una
base de trabajo, que deriva sin avisar.

**En CI**: se regenera y se compara con lo commiteado. Si el esquema se movió y
nadie regeneró, rojo, con el comando para arreglarlo en el mensaje.

**Sabido roto:** falta sellar los eventos espejo. Es lo último que queda de este
bloque.

---

## 2026-08-03 (noche) · Una sola fuente para "intentos por técnica"

**Migración:** `bjj_30_una_sola_fuente` (`db/25_una_sola_fuente.sql`), aplicada a
producción. 19/19 vistas con `security_invoker`, `analisis()` responde.

`bjj_29` dejó dos sitios calculando el mismo recuento: `v_tecnicas_practicante`
y el bloque `tec` de `analisis()`, que lo rehacía porque la vista no llevaba
`modalidad` ni `fecha` y la pantalla filtra por gi/nogi. Ahora la vista las
lleva y **`analisis()` lee de ella**. La vista es el único sitio donde se define
qué cuenta como intento de una técnica.

**Verificado comparando el `tec` de `analisis()` antes y después**, para los tres
filtros (todo, gi, nogi): mismos md5. Si hubieran salido distintos, la vista y
el panel no estaban contando lo mismo — que es exactamente lo que esto viene a
hacer imposible.

**Decisión: la modalidad es la de la SESIÓN**, no la del roll. Es lo que ya
hacía `analisis()` con `modalidad_sesion`; cambiarlo aquí habría movido números
sin que nadie lo pidiera.

**Sabido roto:** sigue faltando generar `database.types.ts` desde la base, y
sellar los eventos espejo. Los dos en el backlog en alta y media.

---

## 2026-08-03 (tarde) · El chip de precisar, y el stub deja de mentir

**Migración:** ninguna. `bjj_29` ya estaba aplicada.

**El chip de precisar, terminado.** Al cerrar un roll propio, cada técnica que
**tiene** variantes ofrece "Sigue siendo Kimura" + sus variantes, en lote y sin
bloquear. Orden: primero lo que está en tu enfoque activo, luego lo que más
usas (de `v_tecnicas_practicante`), luego el resto. Para las 64 técnicas sin
variantes el bloque no existe — que es lo que impide que precisar sea un peaje.

**El stub ya escribe de verdad.** `sesiones`, `rolls` y `eventos` entran en
`TABLAS_PUENTE`. Dejarlas fuera es lo que permitió que seis recorridos dieran
verde con producción rota: el stub apuntaba lo que la app escribiría sin
aplicarlo. El precio es que los recorridos que escriben tienen que limpiar lo
suyo, y ahora `pantalla.js` y `precisar.js` borran **exactamente su sesión** por
id — nunca "las de hoy", porque la semilla también tiene sesiones de hoy.

**`pruebas/precisar.js`**, séptimo recorrido: 13 comprobaciones, y la que
importa mide el invariante **contra Postgres**: el total de la mecánica no se
mueve (37 → 37) y aparece 1 tarikoplata donde había una kimura. Eso no lo podía
comprobar ningún recorrido en modo captura.

**Dos fallos que salieron al probarlo, y ninguno lo habría visto el typecheck:**
- `precisar()` por la vía de la cola corregía la fila encolada pero **nada
  disparaba la subida**: la corrección se quedaba esperando y el análisis seguía
  diciendo "kimura" un rato largo. Ahora empuja la cola.
- El manejador **se tragaba el error** y revertía la marca en silencio: parecía
  que habías precisado y no había pasado nada. Ahora lo dice.

**Sabido roto:**
- **El chip solo está en rolls propios.** Los eventos de un roll observado los
  crea la RPC en el servidor y el cliente no tiene sus ids. Hace falta la
  pantalla de historial, que no existe.
- **`v_tecnicas_practicante` sigue sin modalidad ni fecha.** Ya tiene un
  consumidor real —el orden de los chips— pero el panel de análisis sigue
  calculando lo mismo por su cuenta dentro de `analisis()`. Son dos sitios
  computando "intentos por técnica", que es como empiezan las dos fuentes de la
  verdad. El arreglo es una migración que le añada `modalidad` y `fecha` y haga
  que `analisis()` lea de ella. **No está hecho y es lo primero de lo siguiente.**

---

## 2026-08-03 · Mecánicas: el catálogo deja de ser una lista plana

**Migración:** `bjj_29_mecanicas` (`db/24_mecanicas.sql`). Etiqueta 29 porque 28
es el puente; el fichero es el 24º de `db/`. **Aplicada a producción**: 64
técnicas madre, 8 variantes, 0 sumisiones sin `control`, 19/19 vistas con
`security_invoker`, ninguna función ejecutable por `anon`, y `EL ARTISTA` ya
contando por mecánica.

**Se aplicó en tres llamadas por el MCP, y la tercera es cirugía sobre la
definición viva de `v_logros_conseguidos`** en vez del texto del fichero: son
360 líneas de las que cambia una rama. Antes de aplicarla se comprobó que las
dos versiones dan **el mismo resultado en el caso que las distingue** —con 3
técnicas pero 2 mecánicas ninguna concede el logro; con 3 mecánicas las dos lo
conceden— y el `raise` del bloque hace que, si el predicado no está donde se
espera, falle en vez de recrear la vista sin cambiarla.

**Antes que nada: había un bug en producción y lo destapó esta tanda.** Desde
`bjj_27`, el cliente seguía escribiendo `sesiones.tipo` y `rolls.orden`, que ese
renombrado había convertido en `formato` y `orden_en_sesion`. O sea que **cada
sesión y cada roll propio fallaban al sincronizar**. No lo vio nadie porque
`database.types.ts` es un subconjunto **escrito a mano** —así que TypeScript da
verde: el tipo es la única fuente que consulta— y porque el stub **captura** las
escrituras en vez de aplicarlas, así que los seis recorridos también daban
verde. Salió replicando contra Postgres lo que el cliente escribe de verdad, que
es el bucle que CLAUDE.md ya decía que era el que más valía.

Tres arreglos, y el tercero es el que importa:
1. Los tipos y sus usos, corregidos.
2. `sync.ts` traduce las filas encoladas con nombres viejos antes de enviarlas,
   igual que el puente de `p_grupo`: lo que ya estaba en la cola llevaba los
   nombres dentro y el arreglo del cliente solo no lo rescataba.
3. **Quinta comprobación en `comprobar-vocabulario.py`**: cada campo de los
   `*Insert` tiene que existir como columna. Probada viéndola fallar con el bug
   real. Esto es lo que cierra la clase entera, no el caso.

**La jerarquía, en un solo nivel y garantizada por la base.** `variante_de` +
`nivel` generado + FK compuesta contra `(id, nivel)` con `nivel_referido`
constante 0. No hay nietos, y tampoco se puede degradar una madre que ya tiene
variantes — las dos violaciones probadas en `db/pruebas/mecanicas.sql`.
`mecanica_id = coalesce(variante_de, id)` hace que toda técnica tenga mecánica,
así que los agregados son `group by mecanica_id` sin un solo `case`.

**Decisión: `armbar_triangulo` se emparenta aunque suene a posición.** La regla
dice que la posición nunca crea una variante, y "desde triángulo" lo es. Se
emparenta porque **esa fila ya existía**: la regla completa es no crear filas
que la rompan, y a las que ya están darles la mejor madre que haya. Discutible,
y por eso queda escrito. `kimura_de_reloj` no se creó, y `baratoplata` se queda
suelta porque su parentesco es discutido.

**Decisión: `precisar` tiene dos caminos.** Al cerrar el roll los eventos siguen
en la cola y no existen en el servidor, así que la RPC no puede tocarlos; pero
el id lo genera el cliente, así que corregir la fila encolada hace que suba ya
precisa. Si ya subió, RPC. Está en `precisar()` en `src/lib/db.ts`.

**Decisión: la pantalla de análisis pliega desde `analisis()`, no desde
`v_tecnicas_practicante`.** La vista se creó como pedía el encargo, pero sus
columnas no llevan modalidad ni fecha, y el panel tiene filtro gi/nogi: usarla
ahí mezclaría gi y no-gi en silencio, que es justo lo que CLAUDE.md prohíbe. La
vista queda como el agregado sin filtrar.

**El despliegue fue en dos, a propósito.** Primero el arreglo del bug de
sincronización, que no dependía de `bjj_29`; después la migración y, con ella,
el panel plegado. Primero la base, después el push — la lección de la tanda
anterior, esta vez aplicada.

**Y el arreglo funcionó a la vista:** entre un despliegue y otro producción pasó
de 253 a 254 rolls y de 65 a 67 sesiones. Eso es cola que llevaba atascada desde
`bjj_27` y que subió en cuanto el cliente dejó de mandar `tipo` y `orden`.

**Sabido roto:**
- **El chip de precisar NO está en la pantalla.** El SQL, la RPC y el helper del
  cliente están hechos y probados; falta el paso por el que se toca. Es lo único
  del encargo que queda sin terminar, y lo digo claro porque sin él la fase 2 no
  se usa.
- **Precisar no propaga al roll espejo.** Los eventos espejo no tienen enlace
  entre sí —solo `par_id` a nivel de roll— y emparejarlos por `created_at` no
  vale: en los datos sembrados todos los eventos de un roll comparten sello.
  Así que si A precisa su kimura, la copia de B sigue diciendo kimura. Se miró
  y se descartó: inventar un emparejamiento frágil es peor.
- Precisar puede conceder un **`juguete_nuevo` retroactivo**. Es correcto —lo
  ganaste, el dato llegó tarde— pero si aparece en el feed días después, esto es
  por qué.
- Los valores de `control` son **provisionales** hasta la revisión con el equipo
  de Felipe. Van en un bloque propio y marcado para que corregirlos sea un
  `update` de una línea. Ojo con las llaves de pierna: `heel_hook` va en brazo y
  `kneebar` en cuerpo, que no es lo que dice el instinto.

**Backlog:** añadido el chip de precisar y la propagación al espejo.

---

## 2026-08-02 (tarde) · Puente para la cola vieja

**Migración:** `bjj_28_puente_roll_observado` (`db/23_puente_roll_observado.sql`),
aplicada a producción. Datos intactos: 253 rolls, 65 sesiones, 1415 eventos.

**El problema, que era peor de lo que escribí ayer.** `bjj_27` renombró
`p_grupo` → `p_par`, y ese nombre viaja **serializado en IndexedDB**. Un roll
observado pendiente de un cliente viejo recibía PGRST202 — un 4xx — y `sync.ts`
no reintenta los 4xx: lo manda a "necesita atención". Eso es **perder un roll ya
registrado**, que es el único fallo que este producto no se puede permitir. Lo
correcto no era confiar en que los cuatro sincronizaran a tiempo.

**Decisión: una segunda `registrar_roll_observado` con los nombres viejos que
solo delega.** PostgREST resuelve la RPC por el **conjunto de nombres** del
cuerpo, y los dos conjuntos son disjuntos, así que cada cliente cae en su
función sin ambigüedad. Con esto el despliegue deja de estar acoplado.

**Y un obstáculo que hubo que rodear:** Postgres identifica una función por
(nombre, **tipos**), no por nombres de parámetro — crear la misma firma da
`already exists with same argument types`. Comprobado, no supuesto. El puente
declara `p_duracion_min` como `integer` en vez de `smallint`, que es el cambio
más inocuo posible, y castea al delegar para que la resolución interna encuentre
coincidencia exacta y no se llame a sí misma.

**Verificado en producción**, con el bloque abortando al final para no dejar
nada: un cliente viejo (`p_grupo`) crea los dos rolls espejo; el cliente nuevo
(`p_par`) reconoce ese mismo par y devuelve `creado=false`; reintentar por el
puente tampoco duplica; dos filas con ese `par_id` tras tres llamadas. Y por
REST, los dos conjuntos de nombres dan 42501 en vez de PGRST202 — o sea que
PostgREST los resuelve — y `anon` no puede ejecutar ninguna función.

**La etiqueta `bjj_23` la reclamaban dos ficheros.** `db/18_ambito_dia.sql` y
`db/19_logros_flawless_y_doble_sesion.sql` decían las dos `bjj_23`, y `bjj_24`
no aparecía por ningún lado. La verdad estaba en producción:
`supabase_migrations.schema_migrations` registra
`bjj_24_logros_flawless_y_doble_sesion`. Corregido el comentario de `db/19`, que
era el que mentía. Lo vio Felipe, no yo — y por eso ahora lo mira el script.

**El comprobador tiene ya cuatro comprobaciones**: divergencia de tipo, nombres
prohibidos, `security_invoker` en las 18 vistas, y etiquetas de migración
duplicadas. Las cuatro vistas fallar antes de darlas por buenas.

**Sabido roto:**
- **El puente reintroduce `p_grupo` a propósito y hay que borrarlo.** La
  condición está en `docs/BACKLOG.md`: cuando ninguno de los cuatro tenga cola
  pendiente. El comprobador **no** lo caza, porque no mira nombres de parámetro
  — igual que no caza `private.es_admin(p_grupo)`.
- El `version` de `bjj_27` en `supabase_migrations` quedó `20260730154429`, que
  ordena **antes** que bjj_21…bjj_25 (sellados `20260731…`). No afecta al
  esquema, que ya está aplicado, pero ese registro no sirve para replicar el
  orden. El orden bueno es el alfabético de `db/*.sql`, que es el que usa el CI.

---

## 2026-08-02 · Una palabra, un concepto

**Migración:** etiqueta **`bjj_27_vocabulario`**, en el fichero
**`db/22_vocabulario.sql`** — el encargo la llamaba `bjj_22`, pero `bjj_22` ya
era `db/17_cerrar_lectura_anonima.sql`. Los números de fichero y los de
migración llevan desacoplados desde hace tiempo: el fichero es el 22º de `db/` y
la migración la 27ª. **Aplicada a producción**. Datos intactos: 253 rolls, 1415 eventos, 65 sesiones, 9 fichas, y
los 253 rolls con `par_id`. Copia previa tomada **y restaurada** antes de tocar
nada — cuadraba fila por fila.

`grupo` significaba **cuatro** cosas, no tres: el gimnasio, la categoría de
posición, el par de rolls espejo, y —la que el encargo no recogía— el parámetro
`p_grupo` de `registrar_roll_observado()`, que era el `roll_grupo_id` y no el
gimnasio. Lo delataba su propio comentario en `database.types.ts`: *"p_grupo es
el roll_grupo_id"*. Un comentario que existe para desmentir un nombre es la
definición de nombre malo. Ahora: `equipos`, `posiciones.categoria`,
`rolls.par_id` y `p_par`. Más `rolls.orden` → `orden_en_sesion`,
`inscripciones.orden` → `orden_en_lista`, `sesiones.tipo` → `formato`,
`miembros_equipo.rol` → `rol_en_equipo` y `v_feed.tipo` → `tipo_de_elemento`.

**Decisión: las vistas con `alter view … rename column`, nunca recreadas.**
Recrear es drop + create y ahí se pierde `security_invoker = on` — sin él una
vista lee con los permisos de su dueño y cualquiera ve los datos de otro equipo.
Las 18 lo conservan y el comprobador lo vigila.

**Decisión: `private.es_admin(p_grupo)` conserva su parámetro.** Postgres no deja
renombrar un parámetro con `create or replace`, y hacerlo exigiría tirar la
función — con **seis políticas** colgando de ella. Renombrar seis políticas de
seguridad a mano vale menos que el nombre. Va abajo como sabido roto.

**Decisión: `Team` y `Open Mat` viven en `src/lib/textos/es.ts`.** En la base es
`equipos`, en español como el resto del esquema. Cambiar la etiqueta es una
línea; cambiar el identificador es esto.

**Lo que cazaron las pruebas, y son la razón de que existan.** La batería de RLS
paró dos casos en rojo: al recrear cuatro funciones, Postgres les regaló
`EXECUTE` a `PUBLIC` y `anon` volvía a poder llamarlas — se deshacía `bjj_25` en
silencio. Y el recorrido de logros destapó que `feed()` devolvía
`tipo_de_elemento` mientras el cliente leía `f.tipo`: el `switch` caía al icono
por defecto y **TypeScript no dice nada**, porque la forma de una RPC es una
interfaz escrita a mano.

**El despliegue salió al revés de lo planeado, y conviene saberlo.** Vercel
despliega solo al hacer push, así que el cliente nuevo llevaba un rato pidiendo
`equipo_id` a un esquema que aún decía `grupo_id`: producción estuvo rota entre
el push y la migración. Aplicar dejó de ser el riesgo y pasó a ser el arreglo.
**La próxima vez que una migración y el cliente tengan que ir juntos, el push va
después**, o se despliega desde una rama.

**Verificado en producción**, no supuesto: `/equipos` responde 401 (existe, y
`anon` no lee) y `/grupos` da 404, o sea que PostgREST recargó el caché; la RPC
con `p_par` da 42501 permission denied —existe— y con `p_grupo` da PGRST202 —ya
no—; como usuario autenticado salen 253 rolls, 253 filas de puntos, 50 logros,
`feed()` con 20 elementos y `analisis()` respondiendo; 18/18 vistas conservan
`security_invoker`; y **ninguna** función es ejecutable por `anon`. El linter de
Supabase no saca nada nuevo.

**Sabido roto:**
- **La cola vieja ya no entra.** Un roll observado que quedara sin subir lleva
  `p_grupo` dentro y ahora recibe PGRST202. Si a alguien le aparece un error de
  sincronización, es esto: se puede rescatar añadiendo una sobrecarga temporal
  con el nombre viejo que reenvíe a la nueva, pero no se ha hecho — reintroduce
  el nombre ambiguo y no sabemos si hay algo pendiente.
- `private.es_admin` sigue con `p_grupo`, explicado arriba.
- El payload JSON de `apuntarse_a_quedada` sigue con la clave `'orden'` aunque
  la columna sea `orden_en_lista`: es una etiqueta de la respuesta, no un
  identificador del esquema, y renombrarla no compra nada.
- `db/09_grupos.sql` y `db/10_lectura_por_grupo.sql` conservan su nombre: son
  migraciones ya aplicadas y renombrar el fichero cambiaría el orden en el CI.
- La semilla sigue sin poder arrancar de una base vacía (necesita un equipo, y
  `bjj_14` solo lo crea si ya hay practicantes). Pendiente de antes.

**Backlog:** añadido revisar `academia` en `practicantes` y `sesiones`, que
huele a redundante ahora que existen los equipos.

---

## 2026-08-01 (noche) · La pantalla no se apaga mientras se rueda

**Migraciones:** ninguna. Es todo cliente.

`src/lib/pantalla.ts` mantiene la pantalla encendida **solo mientras
`fase === 'roll'`**. Sujetarlo a toda la sesión de entreno se comería la batería
de quien viene dos horas, y en un gimnasio no se recarga.

**Decisión: se vuelve a pedir en cada `visibilitychange`.** El navegador suelta
el bloqueo en cuanto la pestaña se oculta —una llamada, mirar el WhatsApp— y no
lo devuelve al volver. Sin eso funcionaría hasta la primera distracción, que es
justo cuando hace falta.

**El recorrido encontró una fuga de verdad**: al volver se pedía un bloqueo
nuevo y se perdía la referencia del anterior. Salían 2 peticiones y 1 suelta. El
código daba por hecho que el navegador ya lo había soltado —la especificación
dice que sí, pero esperar a que otro limpie por ti no da síntoma hasta que el
móvil está al 4 %—. Ahora suelta el anterior antes de pedir otro.

**`pruebas/pantalla.js`**, sexto recorrido de `npm run test:navegador`. Espía
`navigator.wakeLock` porque el de verdad rechaza sin cabeza, y así "no lo pide"
no se confunde con "lo pide y le dicen que no". Comprobado que falla si se
desactiva el hook.

**Sabido roto:** `analisis-tema.js` falló una vez en lote y pasó solo y en el
lote siguiente — no encontró celdas, o sea que midió antes de que cargara. Si
reaparece, es una espera que falta, no una regresión.

**Backlog:** tachada la de la pantalla encendida.

---

## 2026-08-01 (tarde) · Copias de seguridad, y fuera `molestias`

**Migraciones:** `bjj_26_fuera_molestias`, aplicada a producción. Datos
intactos: 253 rolls, 65 sesiones.

**1 · Copias de seguridad.** `scripts/copia.sh` vuelca producción a un `.gz`
comprobado, con rotación de las 8 últimas. `scripts/restaurar.sh` la devuelve a
una base local. **No sustituye al plan Pro** —depende de que el portátil se
encienda— pero convierte "lo perdemos todo" en "perdemos como mucho una
semana".

**Y la copia se restauró de verdad, cuatro veces, porque las tres primeras no
servían.** Una copia que nunca se ha restaurado no es una copia:

- La v1 usaba `--table`, que saca **solo esas tablas**: sin tipos, sin
  funciones, sin esquema. 80 KB con 17 bloques COPY que parecían perfectos y
  daban **49 errores** al restaurar.
- La v2 volcaba `auth.users` **después** de `public`, que la referencia por
  clave foránea. 77 errores.
- La v3 se dejaba el esquema **`private`**, donde viven los ayudantes de la
  RLS, así que no se podía recrear ni una política.
- Y volcar `auth.users` con `pg_dump` arrastraba el trigger
  `crear_ficha_al_registrarse`, que **al restaurar se dispara** y crea una
  ficha por usuario encima de las que trae la copia. Ahora de esa tabla solo se
  llevan `id` y `email`, que es lo único que hace falta para que
  `practicantes.user_id` resuelva.

La prueba final: la copia restaurada tiene **exactamente** las mismas cifras que
producción **y pasa los 55 casos de la batería de RLS**. Es una réplica, no un
montón de filas.

**2 · Fuera `molestias`.** Texto libre de lesiones en `sesiones`, o sea dato de
salud del artículo 9 del RGPD. **Cero filas en producción** y la interfaz nunca
llegó a ofrecerlo: era todo el riesgo legal y ninguna de las ventajas. Hoy
borrarlo es gratis; con datos dentro habría que decidir qué se hace con ellos y
avisar a quien los escribió.

**Decisiones:**
- El restaurador reutiliza `db/ci/00_bootstrap.sql`. Que el CI y la
  restauración compartan bootstrap no es casualidad: los dos necesitan lo
  mismo, un Postgres que se parezca a Supabase.
- La restauración repone los privilegios **por defecto**, no solo los actuales.
  Sin eso, la copia parece igual pero una tabla nueva no le llegaría a
  `authenticated` — lo cazó el caso 29 de la batería corriéndola **contra la
  copia**, que es justo para lo que sirve correrla ahí.

**Sabido roto:**
- **La tarea semanal no está registrada.** El script está
  (`scripts/programar-copia.ps1`) pero registrarla toca la máquina, fuera del
  repositorio, y lo lanza Felipe: `powershell -ExecutionPolicy Bypass -File
  scripts\programar-copia.ps1`. **Hasta entonces las copias son manuales**, o
  sea que hoy no hay copia automática de nada.
- Sigue sin haber plan Pro. Esto es el cinturón de repuesto, no el cinturón.


## 2026-08-01 · `anon` a cero, CI, y el disparador de la calibración

**Migraciones:** `bjj_25_anon_sin_privilegios`, **aplicada a producción**. Datos
intactos: 251 rolls, 1403 eventos.

**1 · `anon` sin ningún privilegio, y arreglado el DEFECTO, no solo la lista.**
`pg_default_acl` concedía a `anon` los privilegios completos sobre toda tabla
nueva, por partida doble (`postgres` y `supabase_admin`). Revocar las 31 de hoy
no habría servido: la siguiente migración reabría el agujero. El escenario a
evitar no era el de hoy —ninguna política de escritura le aplica— sino que
alguien cree una tabla y olvide `enable row level security`: con el grant
puesto, esa tabla nace pública. Ahora hacen falta dos errores en vez de uno.

Comprobado **antes** de revocar que no hace falta para nada: las tres pantallas
sin sesión usan solo `supabase().auth.*`, que habla con GoTrue y no con
PostgREST. Cero consultas a tablas antes del login.

**2 · CI, y corriendo en verde de verdad.**
`.github/workflows/ci.yml`: Postgres de servicio, `db/*.sql` desde cero,
`rls.sql`, `puntos.sql`, `test:puntos`, `test:contraste` y `npm run build`.
Los once pasos en verde en 1m01s.

**Y cazó dos cosas en sus dos primeras vueltas**, que es la mejor defensa que
puede tener:

- `puntos.sql` usaba `pg_read_file`, que se ejecuta **dentro de Postgres**. Con
  la base en la misma máquina funciona y no se nota; en CI el servidor es un
  contenedor que no ve el disco del runner, así que el fichero "no existe".
  Ahora el fixture se lee del lado del cliente, con el backtick de psql — y de
  paso deja de hacer falta ser superusuario. Es exactamente la diferencia entre
  "me funciona en local" y "funciona".
- `checkout@v4` y `setup-node@v4` apuntaban a Node 20, deprecado y forzado a
  Node 24. Hoy es un aviso; el día que lo retiren sería un CI roto sin haber
  tocado nada. Subidas a v5.

**3 · La calibración deja de ser "cuando haya datos".** Disparador medible:
200 rolls reales de 5 personas distintas, excluyendo demo, con
`scripts/listo-para-calibrar.sql`. Hoy responde *"Todavía no: 18/200 rolls y
4/5 personas"*. Punto fijo de la retro de los domingos.

**4 · Corregida la regla del idioma de los nombres.** No era "siempre en
español": es que el nombre va en el idioma en el que el chiste funcione, y no
se traduce nunca uno que ya funcionaba. Escrito en el catálogo y en el fichero
de textos. FLAWLESS VICTORY se queda.

**Decisiones:**
- Hubo que revocar también a **`PUBLIC`**, no solo a `anon`: Postgres concede
  `EXECUTE` a `PUBLIC` en toda función, y `anon` lo hereda. Revocarle solo a
  `anon` dejaba **siete funciones** llamables. Es la misma trampa que ya obligó
  a mirar `PUBLIC` en la batería de RLS.
- El bootstrap del CI (`db/ci/00_bootstrap.sql`) reproduce los privilegios por
  defecto de Supabase **con su agujero incluido**. Si viniera limpio, el CI
  daría verde sin haber comprobado la migración que lo cierra.
- `18a_ambito_dia.sql` pasa a `18_ambito_dia.sql` y el otro a `19_`. Por orden
  alfabético, `18_logros_flawless` se aplicaba **antes** que `18a_ambito_dia` y
  usaba un valor de enum que aún no existía. **Lo cazó el CI antes de existir**,
  en el primer ensayo desde cero.

**Sabido roto:**
- **La mitad de `supabase_admin` del `default_acl` no se pudo cerrar**:
  `postgres` no es miembro de ese rol en el plan gestionado y da *permission
  denied*. La migración lo intenta, avisa y sigue. Importa poco —esa entrada
  solo actúa si `supabase_admin` crea una tabla en `public`, y las de la app
  las crea `postgres`, que sí quedó cerrada— pero no está cubierto al 100 %.
- **En CI solo entran `rls.sql` y `puntos.sql`.** Las demás (`logros.sql`,
  `informe.sql`, `quedadas.sql`, `grupos-rls.sql`) dan por hecho que ya hay un
  grupo y datos sembrados. Meterlas pide que la semilla sepa arrancar de cero.
- El diccionario (`posiciones`, `tecnicas`) queda tapado también para `anon`.
  No contradice al "se quedan abiertas" de ayer: lo que sigue abierto es su
  **política**; lo que desaparece es el **grant**, que nadie usa antes del login.

**Batería de RLS: 55 casos, 55 pasan.** Cuatro nuevos, incluido el que crea una
tabla al vuelo para comprobar que **no nace abierta**.


## 2026-07-31 (noche) · El catálogo de logros, cuadrado

**Migraciones:** ninguna. Solo documentación y una herramienta.

Se cruzaron las **cuatro fuentes** del catálogo —`docs/logros-catalogo.sql`, la
migración, `src/lib/textos/logros.es.ts` y la base de producción— para ver si el
renombrado había dejado algo descolgado.

**Ninguna clave cambió.** `sin_marcar` y `de_vuelta` conservan la suya; solo
cambió el nombre visible, y coincide en las cuatro. Eso es lo que importa: la
clave es lo que se guarda, y si hubiera cambiado se habrían roto los iconos, las
vistas y todo lo que la gente ya tenía conseguido.

**Dos diferencias, las dos decisiones ya tomadas y no deriva:** el catálogo de
diseño seguía con `el_ultimo_en_irse` y sin `doble_sesion`. Se actualizó, con el
porqué de la baja escrito donde estaba la fila — incluidas las tres alternativas
que se descartaron, para que nadie la reabra sin saber qué se miró.

**Decisiones:**
- **El renombrado se deja escrito en la cabecera del catálogo**, no solo en el
  registro: quien abra ese fichero dentro de seis meses tiene que ver que SIN
  MARCAR y FLAWLESS VICTORY son el mismo logro, o creerá que falta uno.
- **El comparador se queda en el repositorio** (`scripts/comparar-logros.py`).
  Cuatro copias del mismo catálogo se separan solas — ya pasó una vez, en menos
  de un día. Lo que hay que mirar siempre es la sección de CLAVES: un nombre
  distinto es un despiste, una clave distinta rompe datos.

**Sabido roto:** nada nuevo. Sigue pendiente el `grant all` por defecto de
Supabase a `anon` sobre el resto de tablas, y calibrar las rarezas cuando haya
rolls reales.


## 2026-07-31 (tarde) · Se cierra la lectura anónima, y tres decisiones de Felipe

**Migraciones:** `bjj_22_cerrar_lectura_anonima`, `bjj_23_ambito_dia` y
`bjj_24_logros_flawless_y_doble_sesion`. **Aplicadas a producción.** Datos
intactos: 251 rolls, 1403 eventos, 9 practicantes.

**1 · Cerrada la lectura anónima.** Tres políticas estaban en `USING (true)`
para `public`. Demostrado en local con filas de verdad antes de tocar nada:
como `anon`, `reto_participaciones` devolvía **"Goku (7)"** — nombre y progreso.
Ahora las tres van por grupo y además se revocó el `grant`, así que `anon` ni
llega a la política. `posiciones` y `tecnicas` siguen abiertas: son el
diccionario. Se comprobó antes que **nadie las leía sin autenticar**, ni la app
ni el enlace del invitado — `quedada_por_token()` devuelve contadores, no
nombres.

**2 · EL ÚLTIMO EN IRSE, fuera.** En su hueco entra **DOBLE SESIÓN** (dos
sesiones el mismo día), derivable hoy sin ningún dato nuevo. Constancia sigue
siendo de cuatro.

**3 · El invitado externo: el acceso sigue al evento, no al grupo.** Una
inscripción da su quedada y su informe, y nada más.

**4 · FLAWLESS VICTORY tenía un bug de definición**, no de calibración: un roll
donde no pasa nada da cero puntos a los dos y **se lo llevaban los dos**. Ahora
pide al menos un evento posicional. Los umbrales no se tocan hasta que haya
rolls reales.

**Decisiones:**
- La guarda es de **1 evento posicional y no 2**: con 2 se caían rolls
  legítimos —quien barre una vez y no encaja nada se lo ha ganado— y el bug a
  tapar era solo el roll vacío. La guarda más floja que cierra el agujero.
- **`practicantes` se estrechó también entre autenticados**, que no estaba en el
  encargo. Lo obligó la regla del invitado: con `USING (true)` para
  `authenticated`, apuntarse a un open mat te daba el roster entero. Lo cazó el
  caso 51 de la batería.
- **`v_feed` pasa a filtrar por grupo en la propia vista.** Al dar acceso al
  invitado a su quedada se le colaron dos elementos del feed. Antes el
  aislamiento lo daban de rebote las políticas de cada tabla de origen, y de
  rebote es como se escapan las cosas. Se renombró la vista a `v_feed_crudo` y
  se envolvió, para no duplicar el union de ocho ramas.
- `ALTER TYPE ... ADD VALUE` va en su propia migración: Postgres no deja usar
  un valor de enum en la misma transacción en que se crea, y las migraciones se
  aplican envueltas en una.

**Batería de RLS: 51 casos, 51 pasan.** Los dos que estaban en rojo ayer se han
cerrado, y se añadieron seis casos nuevos — los tres agujeros de `anon`, que el
diccionario siga abierto, y los límites del invitado (ni otras quedadas, ni el
roster).

**Sabido roto:**
- **`anon` conserva `INSERT`/`UPDATE`/`DELETE`/`SELECT` sobre el resto de las
  tablas**: es el `grant all` por defecto de Supabase. Hoy no hace daño porque
  ninguna política de escritura le aplica, pero es mucha superficie de la que
  depender. Solo se revocaron las tres que tenían agujero de lectura. El repaso
  completo está en el backlog.
- Los umbrales de rareza siguen **sin calibrar**, a propósito. La diana para
  cuando haya datos reales: común 10–25 % de los rolls, poco común 3–10 %, raro
  por debajo del 2 %.


## 2026-07-31 · Batería automática de pruebas de RLS

**Migraciones:** ninguna. No se ha tocado ni una política, ni una tabla, ni una
función: esto es red de seguridad, no refactor.

**Entregado:** `db/pruebas/rls.sql`, **45 casos, 43 pasan**. Y
`db/pruebas/README.md` con cómo correr todo lo de esa carpeta y cómo leerlo.
Sale con código distinto de cero si algo falla, así que entra en CI tal cual.

**Decisiones:**
- Todo dentro de **una transacción que acaba en `rollback`**, con el escenario
  montado dentro. Se puede correr mil veces sin dejar rastro.
- El marcador es una tabla **normal y no temporal**: los casos se apuntan desde
  bloques que corren como `authenticated` o `anon`, y a un `pg_temp` ajeno no se
  le pueden dar permisos. El `rollback` la borra igual.
- La comprobación de que `anon` no puede ejecutar funciones `SECURITY DEFINER`
  mira también los permisos a **`PUBLIC`**. Un `grant execute … to public` no
  aparece con `grantee = 'anon'` en ninguna parte y le abre la puerta igual:
  buscar solo 'anon' daba un verde falso.
- Un `INSERT` que rompe el `with check` **lanza 42501**, pero un `UPDATE` o un
  `DELETE` que no casa con el `using` afecta a **cero filas sin error**.
  Confundirlos es la forma fácil de escribir un test que siempre pasa, así que
  cada familia se comprueba como toca.

**Sabido roto — los dos casos en rojo se dejan fallando a propósito:**

- **`anon` ve la tabla `practicantes` entera.** La política
  `practicantes_lectura` es `FOR SELECT TO public USING (true)`, y la clave
  anónima es pública por diseño: va dentro del JavaScript que sirve Vercel.
  Cualquiera puede sacar el roster con un `curl` — nombres, cinturones, pesos y
  academia. Viene de `bjj_01`, no es una regresión de nada reciente. Con tres
  amigos es poca cosa; **el día que entre la academia es una lista de nombres
  reales publicada en internet**. Lo decide Felipe, y no lo he tocado.
- **Un invitado externo no ve la quedada a la que está apuntado.**
  `quedadas_lectura_grupo` va por *tus grupos* y él no es miembro de ninguno.
  **No es una fuga**: la ve por el enlace de invitación, vía
  `quedada_por_token()`, y hay un caso que lo comprueba. Es una carencia de
  producto — sin el enlace a mano no vuelve a encontrar el plan.

**Y un test que mentía, cazado por el camino:** el caso del enlace de
invitación leía el token *ya metido en la piel del invitado*, que justamente no
puede leer `quedadas`. Devolvía null y llamaba a la función con null, así que
fallaba por el test y no por el producto. Ahora el token se captura al montar el
escenario.

**Backlog:** añadido meter esta batería en CI.


## 2026-07-30 · Logros

**Migraciones:** `bjj_21_logros`, **aplicada a producción** el 31 de julio, en
una sola transacción y con `psql -f`. Datos intactos antes y después: 247 rolls,
1392 eventos, 9 practicantes.

**Entregado:** catálogo de 27 logros, `v_logros_conseguidos` / `v_logros_practicante`
/ `v_logros_mes`, colección en la ficha del practicante, ranking del mes en Grupo,
y los logros dentro del feed. Textos en `src/lib/textos/logros.es.ts` y pictogramas
en `src/lib/logros-iconos.ts`, los dos generados de sus fuentes.

**Decisiones:**
- **`el_ultimo_en_irse` se queda FUERA del catálogo.** Su predicado es "el roll con
  el mayor orden de la quedada es del practicante", y `rolls.orden` es el orden
  dentro de la sesión de cada uno, no de la quedada: cada persona numera los suyos
  1..n. Así que no premia irse el último, premia haber rodado más —que ya lo cuenta
  EL NOTARIO— y empata a todos los que lleguen al mismo número. **Lo tiene que
  cerrar Felipe.** Alternativas: (a) el último `created_at` de la quedada, que con
  la cola offline mide quién sincronizó y no quién rodó; (b) una hora de fin en el
  roll, que es un dato nuevo que hoy no se registra; (c) quitarlo.
- **`de_vuelta` se lee con el criterio de `rol`.** "El oponente llegó a montada" es
  un evento suyo con `rol = arriba`; con `rol = abajo` sería justo lo contrario y
  el logro saldría al revés. El test lo cubre con los dos casos.
- **`primera_vez` cuenta una por roll** aunque el roll estrene dos posiciones: el
  ámbito es `roll` y `veces` cuenta instancias del ámbito, no eventos.
- **`impasable` es literal**: cero eventos `pase_guardia` del oponente, completados
  o no. Un pase fallado también rompe el logro.
- **La colección vive en Análisis y el ranking en Grupo.** No hay pantalla de
  perfil; Análisis ya es la ficha de cada uno —tiene el selector de practicante—
  y un ranking sin nadie con quien compararte no es un ranking.

**Sabido roto:**
- **`v_logros_conseguidos` tarda 1,65 s con 252 rolls, y el feed 4,5 s.** Es
  usable pero no es rápido, y crece con los datos. El primer intento del feed
  reevaluaba la vista una vez por sesión y se pasaba de los 30 s de timeout; se
  arregló con un join en vez de una subconsulta correlacionada, y con un índice
  de cobertura. **Si sigue subiendo, toca materializar la vista** — que es lo
  previsto, y no guardar contadores a mano.
- **Dos logros renombrados por Felipe al revisar el catálogo**: SIN MARCAR pasa
  a **FLAWLESS VICTORY** y DE VUELTA a **HIGHLANDER**. Costó una línea en el
  fichero de textos, que es exactamente para lo que se separó del esquema.
- **A vigilar cuando haya datos de verdad**: FLAWLESS VICTORY y LIMPIO salen
  baratos. En producción, Goku los tiene ×74 y ×42 sobre 138 rolls. Un logro que
  cae en la mitad de los rolls deja de significar algo; si se confirma, hay que
  endurecer el predicado.
- **EL ANCLA es el que menos me convence** y se lo dije a Felipe: los otros dos
  de cachondeo premian algo que hiciste, y este premia que el observador dejara
  de pulsar dos minutos. Con un observador distraído salta solo. Sigue dentro,
  pero apagado como toda su familia.
- Los cuatro logros de ámbito `quedada` no tienen datos reales todavía: ninguna
  sesión de producción cuelga de una quedada.
- El feed no marca "el primero del grupo en conseguirlo"; están los otros tres
  casos (primera vez, redondos y raros).

**Backlog:** tachados los logros; anotado el reto tipo "consigue X N veces".


## 2026-07-30 · Tema Gullo y sistema de diseño

**Migraciones:** `bjj_20_acento_del_grupo` (`grupos.color_acento`, con check de hex).

**Entregado:** tokens en tres familias (`--marca-*` tematizable, `--dato-*` y
estado nunca) con escalas de tipografía, espaciado, radios y sombras · claro por
defecto y oscuro como paleta propia · tema por grupo del que se deriva todo
midiendo contraste · avatares de cinturón en SVG · `npm run test:contraste`.

**Decisiones:**
- **El sistema no decide el tema.** El encargo decía "guardada → sistema → claro"
  pero la verificación exigía abrir en claro con el sistema en oscuro. Felipe
  eligió: **guardada → claro**, sin `prefers-color-scheme`.
- **Dos valores de la referencia no pasaban AA y se movieron**: la tinta del botón
  verde (`#0b1a0e` da 4,38 → `#050d06`, 4,80) y el gris tenue del tema claro
  (`#807e79` da 3,56 → `#63615d`, 5,43). Medido, no estimado.
- **Los `--dato-*` son rellenos**; para texto hay `--dato-yo-texto` y
  `--dato-op-texto`, que son pasos de la rampa ya aprobada. El naranja de relleno
  sobre el hueso da 2,81.
- El análisis pierde su interruptor propio y su paleta paralela: un solo tema.

**Iconos:** hechos, con el logo de Gullo ya en `public/logo-gullo.png`.
`scripts/iconos.mjs` recorta el blanco, genera 192/512, el enmascarable al 68 %
—el logo lleva la "G" asomando por encima del círculo y al tamaño normal esa
punta se perdería al recortar Android— y el `apple-touch-icon`, que iOS exige
aparte porque ignora el manifest. El PNG traía un marco gris de 1px que dejaba
el recorte sin efecto; se detecta porque el dibujo toca los cuatro bordes a la
vez, que es cosa de marcos y no de logos. Subida la caché del service worker a
`bjj-v2`: si no, quien ya tenga la app instalada se queda con los iconos viejos.

**Splash de iOS:** hecho, once imágenes verticales de iPhone. iOS exige el
tamaño EXACTO del dispositivo —si no cuadra al píxel, descarta y enseña blanco—
así que la lista de `apple-touch-startup-image` la **genera el mismo script**
que los PNG, en `src/lib/splash.ts`: once entradas con medidas al píxel
mantenidas a mano son once oportunidades de que dejen de coincidir. Solo
iPhone; el iPad son ocho ficheros más para un caso que hoy no existe.

**Playwright entra al repositorio.** `playwright-core` como dependencia de
desarrollo y los cuatro recorridos en `pruebas/`, con `npm run test:navegador`
(70 comprobaciones). Estaban en un scratchpad fuera del repo, o sea que no
existían para nadie más.

**Sabido roto:**
- No hay pantalla para elegir el acento del grupo: hoy se cambia por SQL.
- El service worker solo cachea `/`, `/entreno` y `/practicantes`: análisis,
  grupo y quedadas no abren sin red. Es anterior a esta tanda.
- Los recorridos usan `channel: 'msedge'`: en una máquina sin Edge hay que
  cambiarlo o instalar el Chromium de Playwright.
- Sin splash de iPad, a propósito.
- Los recorridos en navegador siguen viviendo en el scratchpad, no en el
  repositorio: meterlos exigiría `playwright-core` como dependencia y esa
  decisión no la he tomado yo.

**Semilla de demo:** `db/pruebas/semilla-demo.sql`, determinista y solo local
(pide `-v confirmar=si` y aborta si `auth.users` tiene más de tres cuentas).
Roster de Dragon Ball —se ve a la legua que es falso, y así no acaba en una
captura pareciendo real— con 180 rolls de Goku en cuatro meses. El reparto va
**pesado a propósito**: vive en la espalda y la montada y casi no toca las
piernas, porque un heatmap plano no prueba que la rampa funcione. Con eso,
`recorrer-analisis.js` vuelve a pasar entero (23 comprobaciones); antes fallaba
porque esperaba los números de un juego de datos que ya no existía.

**Backlog:** tachadas cinco de "Diseño y UX"; accesibilidad e iconos quedan a
medias con lo que falta escrito.

## 2026-07-29 · Bloques entregados antes de existir este registro

Reconstruido a partir de las migraciones aplicadas y del repositorio, así que puede
faltar algún matiz. A partir de aquí lo escribe Claude Code en el momento.

**Migraciones:** `bjj_01` … `bjj_12`.

**Entregado:** auth por magic link · pestaña de practicantes con altas y edición ·
PWA de logging con la máquina de estados · escritura local-first con cola ·
modo observador con `registrar_roll_observado()` · `transicion` en el enum ·
marcador de puntos IBJJF en vivo con cronómetro, deshacer y selector de posición
inicial · sello en segundos de cada evento.

**Decisiones:**
- `transicion` guarda el destino en **`posicion`**; no se añadió `posicion_destino`.
  Decisión abierta: Felipe quiere revisarla.
- Los 3 segundos de estabilización del reglamento IBJJF **no se implementan**: el
  dedo del observador es la estabilización.
- Los puntos **se derivan, nunca se guardan**. El cálculo vive dos veces
  (`src/lib/puntos.ts` y SQL) y lo que impide que se separen es el fixture
  compartido.
- El id del roll observado lo genera la base, no el cliente. Excepción consciente
  al invariante: la idempotencia la garantiza `roll_grupo_id`.

**Sabido roto:**
- **El login.** `@supabase/ssr` fuerza `flowType: 'pkce'` y pisa el `implicit` que
  pide `src/lib/supabase.ts`, así que el arreglo anterior fue una operación nula.
  Con enlaces abiertos en otro navegador falla. Prompt en
  `docs/PROMPT-arreglar-login.md`.
- **Un pase que aterriza en montada solo cuenta 3** en vez de 7: los 4 de montada
  salen de un evento `transicion`, y "pasar la guardia" no lo emite.
- **Falta `de_rodillas`** en `bjj_posicion`. El selector de posición inicial se
  montó con lo que hay.
- La lectura está abierta a **cualquier usuario autenticado**, pendiente de
  recortarse con el bloque de grupos.

**Datos en producción:** 2 usuarios reales (Felipe y Pablo) · practicantes de demo
Goku, Vegeta, Krilin, Piccolo y Freezer con ~280 rolls simulados. **Todo lo simulado
lleva `roll_grupo_id` que empieza por `00000000-0000-4000-8000-`** y las fichas de
los tres rivales por `00000000-0000-4000-9000-`. No cuenta como actividad real.
