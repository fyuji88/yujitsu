# Prompt para Claude Code — marcador IBJJF en vivo

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a construir el **marcador de puntos estilo IBJJF en vivo**: mientras el
observador registra el roll, la pantalla muestra el tanteo de los dos
practicantes y se actualiza con cada acción. Lee antes `CLAUDE.md` y
`HANDOVER.md`.

## Antes de escribir una línea: la decisión que ya está tomada

Este bloque estaba bloqueado por una decisión de vocabulario que le tocaba a
Felipe y a Pablo. **Ya está cerrada: se añade `transicion` al enum
`bjj_tipo_evento`.** No la vuelvas a abrir, pero entiende por qué, porque
condiciona todo lo demás.

De las seis acciones que puntúan en IBJJF, el vocabulario actual solo cubre
cuatro: `derribo`, `barrida`, `pase_guardia` y `toma_espalda`. Faltan **montada
(4 puntos)** y **rodilla en barriga (2)**, que hoy no se registran como evento
—se llega a ellas cambiando de posición, y la app actualiza la posición sin
escribir nada—. Sin eso el marcador se dejaría 6 de los puntos posibles y sería
falso en la mayoría de los rolls.

`transicion` en vez de dos tipos nuevos (`monta`, `rodilla_barriga`) porque el
siguiente bloque es el **tiempo de dominio tipo posesión de fútbol**, y eso
necesita *todos* los cambios de posición, también los que no puntúan: norte-sur,
kesa gatame, tortuga, scramble. Dos tipos nuevos cerrarían el marcador y
dejarían la posesión igual de bloqueada.

**La regla de lectura de `transicion`, que hay que documentar en `CLAUDE.md`:**
en un evento de tipo `transicion`, `posicion` es **el destino** —dónde acaba el
actor—, no dónde estaba. Es la única excepción al criterio general, y existe
porque lo que interesa de una transición es dónde te deja. Consecuencia
inmediata: **los heatmaps tienen que excluir `tipo = 'transicion'`**, o se
llenan de filas con `objetivo = 'ninguno'`. Revisa `v_heatmap_ofensivo` y
`v_heatmap_defensivo` y añade el filtro; si ya filtran por objetivo, compruébalo
en vez de suponerlo.

## Regla de arquitectura: los puntos se derivan, nunca se guardan

No añadas una columna `puntos` a `rolls` ni a `eventos`. El tanteo es una
función de la lista de eventos, igual que el heatmap. Si mañana se corrige un
evento mal registrado, el marcador tiene que corregirse solo; una columna
guardada se queda vieja y nadie se entera.

Esto obliga a que el cálculo exista **dos veces**: en TypeScript para el vivo, y
en SQL para el análisis histórico. Dos implementaciones que se separan es un bug
esperando. Móntalo así:

- `src/lib/puntos.ts` — una **tabla de reglas** declarativa (no una cascada de
  `if`) y una función pura `puntuar(eventos): { a: number, b: number, desglose }`.
- Una vista `v_puntos_roll` en SQL que aplique las mismas reglas.
- `src/lib/__fixtures__/puntos.json` — los casos de prueba de más abajo, en un
  fichero que **leen los dos**: el test de TypeScript y un script SQL que los
  carga y compara. Si alguien cambia una regla en un sitio y no en el otro, el
  fixture lo caza.

## La tabla de puntos

Valores oficiales IBJJF:

| Acción | Puntos | Cómo se detecta con nuestro vocabulario |
|---|---|---|
| Derribo | 2 | `tipo = 'derribo'` |
| Barrida | 2 | `tipo = 'barrida'` |
| Rodilla en barriga | 2 | `transicion` con `posicion = 'rodilla_en_barriga'` |
| Paso de guardia | 3 | `tipo = 'pase_guardia'` |
| Montada | 4 | `transicion` con `posicion = 'montada'` |
| Espalda con ganchos | 4 | `tipo = 'toma_espalda'` |

Los puntos van siempre **al `actor` del evento**. Todo lo demás vale cero:
`cien_kilos` (control lateral) no puntúa —lo cubren los 3 del pase—, ni
`norte_sur`, ni `kesa_gatame`, ni `tortuga`, ni `scramble`, ni `escape`, ni
`sumision`.

Sobre los 3 segundos de estabilización del reglamento: **no los implementes**.
El observador pulsa cuando la posición ya está hecha; el dedo humano *es* la
estabilización. Un temporizador aquí solo añadiría latencia y falsos negativos.
Déjalo escrito en un comentario para que nadie lo "arregle" luego.

## La parte difícil: no se re-puntúa la misma posición

Esto es lo que va a estar mal si lo haces sumando. El reglamento no premia
acumular la misma posición: una posición puntúa **una vez por secuencia**, y solo
vuelve a puntuar si el otro ha salido de verdad —ha escapado o ha recuperado la
guardia—. Montar, pasar a cien kilos y volver a montar sin que el otro haga nada
son 4 puntos, no 8.

Implementación: por jugador, un conjunto de posiciones ya puntuadas en la
secuencia en curso. La secuencia de X **se cierra** —y su conjunto se vacía—
cuando el rival hace un evento que significa que ha salido: `escape`, `barrida`,
o una `transicion` que le deja en una posición de guardia. Los tipos que no son
posicionales (`sumision`) no cierran nada.

Si al implementarlo encuentras un caso donde esta regla da un resultado que a ti
te parece raro, **para y pregunta** en vez de inventar una excepción. El
reglamento tiene matices que no vamos a modelar todos, y prefiero un marcador
simple y predecible a uno que intenta ser un árbitro.

## Casos de prueba obligatorios

Van en el fixture. Ninguno es decorativo:

1. `derribo` + `pase_guardia` + `transicion→rodilla_en_barriga` +
   `transicion→montada` + `toma_espalda` = **15 – 0**.
2. `pase_guardia` (3) + `transicion→montada` (4) + `escape` del rival +
   `transicion→montada` otra vez (4) = **11 – 0**. El escape reabre la secuencia.
3. `transicion→montada` (4) + `transicion→cien_kilos` + `transicion→montada`
   sin que el rival haga nada = **4 – 0**, no 8.
4. `barrida` desde `guardia_cerrada` con `rol = 'abajo'` = **2**, y no se cuenta
   además como derribo.
5. Roll que acaba en sumisión sin ninguna acción posicional = **0 – 0**, y el
   marcador lo enseña sin parecer roto.
6. **Invariante del espejo**: coge un roll observado, calcula el tanteo desde la
   fila de A y desde la fila espejada de B. `puntos(rollA).a` tiene que ser igual
   a `puntos(rollB).b`. Si no lo es, el espejo o la puntuación están mal, y da
   igual cuál: es un fallo.

## La pantalla

En **modo observador**, una cabecera fija con los dos nombres y los dos números,
con los colores ya establecidos: azul para A, naranja para B. Al cambiar el
tanteo, el número que sube muestra un instante de dónde vino ("+3 paso") y se
apaga. Tiene que leerse **de reojo, a un metro, desde el borde del tatami** —
número grande, nombre pequeño, sin decoración.

En **modo propio no hay marcador en vivo**: si estás rodando no lo miras. Ahí el
tanteo sale solo en el resumen final del roll, con el desglose de dónde salió
cada punto.

**Deshacer el último evento.** Esto deja de ser un extra en cuanto hay un
marcador visible: el observador va a ver sus propios errores en tiempo real y va
a querer corregirlos en el momento. Un botón de deshacer que quite el último
evento de la lista local y recalcule. Como el roll no se sube hasta que termina,
es barato: es un `pop` sobre el estado, no una operación contra la base.

## La posición inicial se elige

Hoy `registrar_roll_observado` mete todos los rolls como `de_pie` / `neutral`,
porque no recibe la posición de salida. Eso vale para un roll que empieza de pie,
pero en clase se arranca constantemente desde una posición pactada —"empezáis con
la guardia cerrada puesta"— y ahora mismo esa información se pierde en silencio,
que es peor que no tenerla.

En la pantalla de inicio del modo observador, **antes del primer evento**, se
elige la posición de salida y quién está arriba. Que no se convierta en un
formulario: por defecto `de_pie` / `neutral`, un toque para cambiarlo, y una
lista corta con lo que se usa de verdad —de pie, guardia cerrada, guardia
abierta, media guardia, montada, espalda— con un "otra" que despliega el resto.
Si se elige una posición que no es `de_pie` ni `clinch`, hay que preguntar quién
está arriba; si es `de_pie`, no se pregunta nada.

En la base:

- `registrar_roll_observado` necesita dos parámetros nuevos, `p_posicion_inicio`
  y `p_rol_inicio`. Ojo: **añadir parámetros no es un `create or replace`**, es
  una función nueva. Haz `drop function` de la firma vieja y recréala, o te
  quedan dos sobrecargas y PostgREST no sabe cuál llamar. Vuelve a aplicar el
  `revoke ... from public, anon` y el `grant execute to authenticated` a la firma
  nueva: no se heredan.
- **`espejar_roll` hay que comprobarlo aquí.** Invierte `rol_inicio` para B
  —si A empieza en guardia cerrada abajo, B empieza en guardia cerrada arriba—
  pero mantiene `posicion_inicio`, que es física y es la misma para los dos. Esa
  rama nunca se ha ejecutado con nada distinto de `neutral`, así que asume que
  está mal hasta que la pruebes con un roll que empiece en guardia.

**Una cosa que no decides tú:** falta `de_rodillas` en `bjj_posicion`. Empezar de
rodillas no es `de_pie` ni es `clinch`, y en un gimnasio es de las salidas más
frecuentes. Es vocabulario, o sea que lo cierran Felipe y Pablo. Monta el
selector con lo que hay y **dilo en el resumen de lo que has hecho**; no lo
añadas por tu cuenta.

## El cronómetro

Uno solo, continuo, para todo el roll. **No es un cronómetro por posición**: no
hay segmentos en la interfaz, ni cuentas atrás, ni el temporizador de 3 segundos
del reglamento. Arranca cuando empieza el roll y corre hasta que se cierra.

- Formato `mm:ss`, grande, junto al marcador. El observador lo mira de reojo.
- Pausa y reanudar, porque los rolls se interrumpen de verdad —alguien se cae
  encima, hay que atar un cinturón—. Cuando está en pausa tiene que **verse** que
  lo está, no ser un detalle sutil: el número parado y ya está engaña.
- **No acumules con `setInterval`.** Deriva el tiempo de una marca de inicio
  (`Date.now()` al arrancar, más lo acumulado antes de la última pausa) y usa el
  intervalo solo para repintar. Un contador que suma ticks se desincroniza y, si
  el móvil apaga la pantalla o el navegador manda la pestaña a segundo plano, se
  queda parado — y el observador no se entera hasta el final.
- Al cerrar el roll, la **duración se rellena sola** con lo que marque el
  cronómetro. No preguntes una duración que ya sabes; deja editarla por si acaso.

**Cada evento se sella con el segundo del cronómetro**, no con el minuto. Añade
`eventos.segundo_roll smallint` (0..3600) y guárdalo ahí; `minuto` se queda como
está para no romper nada, y lo derivas de los segundos.

Esto es deliberado aunque el análisis de posesión no entre en este bloque: el
cronómetro ya está corriendo, así que sellar en segundos no cuesta nada más, y
si sellamos en minutos, todos los rolls que se registren de aquí al bloque de
posesión nacen inservibles para medirla. El dato que no capturas no lo recuperas
después.

## Migración

`db/07_transicion_y_puntos.sql`, migración `bjj_10`:

- `alter type bjj_tipo_evento add value 'transicion';` — ojo, en Postgres esto
  **no puede ir dentro de una transacción** con otras sentencias que usen el
  valor nuevo. Sepáralo o usa dos migraciones; si lo metes todo en un bloque te
  va a dar `unsafe use of new value of enum type`.
- `alter table eventos add column segundo_roll smallint check (segundo_roll between 0 and 3600);`
- `registrar_roll_observado` recreada con `p_posicion_inicio`, `p_rol_inicio`, y
  `segundo_roll` leído de cada elemento de `p_eventos`. Mantén todo lo que ya
  hace bien: la idempotencia por `roll_grupo_id`, el advisory lock, el
  `registrado_por`, y la resolución de técnicas por slug sin tirar el evento.
- La vista `v_puntos_roll`.
- El filtro de `transicion` en los dos heatmaps.

Pruébala **primero contra un Postgres local**, como está en `db/README.md`.
Producción tiene ahora mismo datos reales que Felipe quiere conservar: 2
practicantes, 2 sesiones, 1 roll y 3 eventos. Déjalos como están.

## Fuera de alcance, a propósito

**Ventajas y penalizaciones.** Son criterio de árbitro y duplicarían el número
de pulsaciones. Un intento de sumisión ya se registra con `completado = false`;
con eso hay suficiente señal por ahora.

**El cálculo del tiempo de dominio / posesión.** El bloque siguiente. Aquí se
captura el dato —el sello en segundos de cada evento— pero **no** se calcula ni
se enseña nada: ni barra de posesión, ni tiempo por posición, ni reparto
dominante/neutral. Eso necesita decidir cómo se cierra el último tramo y qué
cuenta como disputa, y es una conversación aparte.

**Modo torneo** con cronómetro reglamentario. Sale casi gratis a partir de esto,
pero es otra conversación.

## Verificación

1. `npm run build` pasa, typecheck estricto incluido.
2. Los seis casos del fixture pasan **en TypeScript y en SQL**, con los mismos
   números.
3. Un roll observado entero recorrido en el navegador, mirando que el marcador
   sube cuando toca y no sube cuando no toca.
4. Un roll que **empiece en guardia cerrada con A abajo**, comprobando en la base
   que el roll de A dice `abajo` y el espejado de B dice `arriba`, con la misma
   `posicion_inicio`.
5. El cronómetro, con la pantalla apagada un minuto en medio del roll: al volver
   tiene que marcar el tiempo real transcurrido, no haberse quedado parado.
6. La idempotencia sigue viva después de recrear la RPC: dos llamadas con el
   mismo `roll_grupo_id` dejan un solo roll por persona.
7. Probado a 390px de ancho: marcador y cronómetro no pueden comerse los botones
   de acción.
8. Producción como la encontraste.

Cuando acabes, actualiza `CLAUDE.md` —la regla de lectura de `transicion` y que
los puntos se derivan— y tacha el bloque en `docs/02-backlog.md`.
