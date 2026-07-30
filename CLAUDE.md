# BJJ Tracker — contexto del proyecto

App para registrar rolls de jiu-jitsu y analizar el juego. La construyen Felipe y
Pablo, que entrenan juntos en Barcelona. Este fichero lo lee Claude Code
automáticamente: aquí está lo que hay que saber antes de tocar nada.

**Idioma:** el código, los comentarios y la interfaz están en español. Los
identificadores de base de datos van sin acentos (`sumision`, `posicion`).

---

## Cómo se nombran las cosas

Dos reglas. La primera dice qué nombre es válido; la segunda, cuándo vale la
pena cambiarlo.

### Una palabra, un concepto

En todo el esquema, una palabra significa **una sola cosa**. Si dos columnas no
pueden compartir tipo, no pueden compartir nombre. Y el nombre tiene que decir
qué es **sin la tabla como contexto**: `rol` no vale, `rol_en_equipo` sí.

No es estética. Aquí la seguridad entera son políticas de RLS y el análisis
entero son vistas, así que un nombre ambiguo no produce un error: produce una
consulta correcta que devuelve otra cosa. Eso no se cae, **da un número** — y un
número equivocado no se distingue de uno bueno mirándolo.

Ya pasó. `rolls.orden` era el orden dentro de la sesión de cada uno, y el logro
EL ÚLTIMO EN IRSE se escribió como "el roll con el mayor `orden` de la quedada".
No premiaba irse el último, premiaba haber rodado más; hubo que sacarlo del
catálogo. La columna no mentía: no decía **de quién** era la secuencia, y quien
la leyó rellenó el hueco con lo que le pareció razonable.

`bjj_27` separó las cuatro cosas que se llamaban `grupo` —el gimnasio
(`equipos`), la categoría de posición (`posiciones.categoria`), el par de rolls
espejo (`rolls.par_id`) y el parámetro `p_grupo` de la RPC del observador, que
era el par y no el gimnasio—, y de paso `rolls.orden` → `orden_en_sesion`,
`inscripciones.orden` → `orden_en_lista` y `sesiones.tipo` → `formato`.

`scripts/comprobar-vocabulario.py` lo vigila en CI: nombres repetidos con tipos
distintos, nombres prohibidos, y `security_invoker` en las 18 vistas. **Solo ve
la mitad**: dos columnas `text` que signifiquen cosas distintas se le escapan.
De esa otra mitad se encarga esta regla, no la máquina.

Las excepciones van a `scripts/excepciones-vocabulario.txt` **con el motivo
escrito**. Hoy solo hay una, `estado`: es el mismo concepto —el estado del ciclo
de vida de la fila— con un enum acotado a cada tabla, que es un patrón y no una
ambigüedad.

### El identificador y la etiqueta son decisiones distintas

La palabra que lee la gente vive en `src/lib/textos/`. Cambiarla es **una
línea**. El identificador de la base cuesta una migración, renombrar las
columnas de las vistas, tocar el cliente y coordinar la cola de salida.

Por eso el identificador se renombra **solo cuando es ambiguo para quien
programa**, nunca porque nos guste más otra palabra. En pantalla se lee "Team" y
"Open Mat"; en Postgres son `equipos` y `quedadas`, en español como el resto del
esquema. Si mañana Felipe quiere "Squad", es una línea de textos y ninguna
migración: para eso están separadas.

Y al revés: `quedadas` **no** puede llamarse `open_mat` en la base, porque
`open_mat` ya es uno de los seis valores de `bjj_tipo_sesion` — sería otra vez
una palabra con dos significados.

---

## La decisión que sostiene todo: se modelan eventos, no resultados

Cada acción de un roll es una fila en `eventos` con cinco datos: **quién** la hizo
(`actor`), **qué** hizo (`tipo`), **desde dónde** (`posicion` + `rol`), **a qué
articulación** (`objetivo`) y **con qué técnica** (`tecnica_id`).

De ahí salen, sin tablas nuevas, el heatmap ofensivo, el defensivo, el análisis
por guardia, el head-to-head y la validación de retos. Si aparece una feature que
parece pedir una tabla nueva, primero comprobar si es una vista sobre `eventos`.

### `posicion` + `rol`: leerlo bien

La posición es **física** (montada, guardia cerrada…) y `rol` dice dónde está el
**actor del evento**, no el dueño del roll.

| posición | rol | significado |
|---|---|---|
| `guardia_cerrada` | `abajo` | está jugando la guardia |
| `guardia_cerrada` | `arriba` | está dentro intentando pasarla |

Consecuencia importante: al espejar un roll observado al compañero **solo cambia
`actor`**. `posicion` y `rol` describen a la misma persona física en las dos
filas. Está implementado en `espejar_roll()`.

### `transicion`: la única excepción a lo anterior

En un evento de tipo `transicion`, **`posicion` es el destino** —dónde acaba el
actor—, no desde dónde actuó. Es la única excepción al criterio general, y
existe porque lo que interesa de una transición es dónde te deja.

Consecuencia práctica: cualquier vista que agrupe por posición y objetivo tiene
que excluir `tipo = 'transicion'`, o se llena de filas con `objetivo = 'ninguno'`
que no significan nada. Los dos heatmaps ya estaban a salvo porque filtran
`tipo = 'sumision'`; `v_fuertes_debiles` sí necesitó el filtro.

`transicion` existe en vez de dos tipos nuevos (`monta`, `rodilla_barriga`)
porque el análisis de posesión que viene después necesita **todos** los cambios
de posición, también los que no puntúan: norte-sur, kesa gatame, tortuga,
scramble. Dos tipos nuevos habrían cerrado el marcador y dejado la posesión
igual de bloqueada.

---

## Estado actual

**Fase 1 terminada y desplegada.** Auth por magic link (verificado de punta a
punta), pestaña de practicantes y pantalla de logging, con escritura local-first.

**Modo observador terminado y desplegado.** Un tercero registra en vivo el roll
de otros dos y cada uno recibe sus datos. Es el botón 👁 Observar del entreno.

**Marcador IBJJF en vivo.** Observando, una cabecera fija con el tanteo de los
dos y un cronómetro con pausa. En modo propio no hay marcador en vivo —si estás
rodando no lo miras—: el tanteo sale en el resumen, con el desglose.

**Pantalla de análisis.** Heatmaps ofensivo y defensivo, saldo por guardia,
fuertes y débiles, head-to-head, evolución semanal y técnicas. Con selector de
practicante, filtro gi/nogi y ventana temporal. El diseño aprobado es
`docs/BJJ-Analisis-DEMO.html`; la pantalla es su puerto a React.

**Bloque social terminado y desplegado.** La app dejó de ser un cuaderno
personal: ahora hay una unidad social —el **equipo**— y todo cuelga de ella.
(En pantalla se lee "Team"; en la base es `equipos`. Ver las reglas de arriba.)

- **Equipos** con admin y código de unión (`bjj_14`). Todo el mundo está en uno.
- **La lectura va por equipo** (`bjj_15`): ves lo de la gente con la que
  compartes equipo, no lo de cualquier autenticado.
- **Quedadas** con plazas, lista de espera y token de invitación (`bjj_16`).
- **Feed** del equipo con reacciones (`bjj_17`).
- **Informe de la quedada** (`bjj_18`): ranking y títulos, congelado en jsonb.
- **Enfoques** (`bjj_19`): lo que dices que trabajas, contrastado con lo que
  hiciste. Vive dentro de Análisis, pegado a los KPIs.

- Supabase: proyecto `idzlxkxeadrcolcnmoeo`, org `yujitsu`, eu-west-1, plan gratuito
- Vercel: `yujitsu-eight.vercel.app`, plan Hobby
- GitHub: `fyuji88/yujitsu`, privado, rama `main`
- 27 migraciones aplicadas (`bjj_01` … `bjj_27`), copia en `db/`

**Datos reales, pero pocos.** El diccionario (24 posiciones, 63 técnicas), el
equipo "Gullo" y unos 250 rolls entre Felipe, Pablo, Nicolas y Sasza.

---

## Invariantes que no hay que romper

**Los ids se generan en el cliente** (`crypto.randomUUID()`) y la cola sube con
`upsert`, nunca `insert`. Es lo que hace que reintentar tras perder cobertura no
duplique filas. Si alguien cambia esto a `insert`, se rompe la garantía.

**La cola sube por tablas en orden**: `sesiones` → `rolls` → `eventos`. Un evento
que llegue antes que su roll lo rechaza la clave foránea.

**La interfaz solo ofrece lo que la RLS permite.** En practicantes, el botón de
editar aparece solo en tu ficha y en los contactos que creaste tú — la misma
condición que la política de Postgres. Si la UI ofrece más, el usuario ve errores
en vez de botones ausentes.

**Los datos del roll no llegan a la red sin pasar por IndexedDB.** Sesiones,
rolls y eventos pasan siempre por `encolar()` en `src/lib/db.ts`. El roll
observado pasa por `encolarRollObservado()`, que es la misma cola con otro
destino: en vez de `upsert` contra tablas, una llamada a
`registrar_roll_observado()`.

Lo demás —`practicantes`, `equipos`, `miembros_equipo`, `quedadas`,
`inscripciones`, `reacciones`, `enfoques`— sí escribe directo, y es
deliberado: son cosas que se hacen sentado y con cobertura, no en mitad de un
roll con el móvil en la bolsa. La cola existe por el tatami, no por gusto de
tener cola. Si añades algo que se toca **rodando**, va por `encolar()`.

**El modo observador solo puede escribir por RPC.** La RLS impide que un tercero
toque las sesiones de otros, así que `registrar_roll_observado()` es SECURITY
DEFINER. Si alguien intenta "simplificarlo" escribiendo las tablas desde el
cliente, se encuentra `42501` y no hay forma de rodearlo desde el frontend.

**El vocabulario es cerrado.** No añadir valores a los enums sin decirlo: los
heatmaps dependen de que Felipe y Pablo usen las mismas palabras. Los códigos
feos viven en la base; las etiquetas humanas, en la interfaz.

**Entrar y crear cuenta son dos cosas distintas.** Al entrar se pasa
`shouldCreateUser: false`. Si no, un correo mal tecleado no da error: crea una
cuenta nueva, y con ella una ficha de practicante nueva por el trigger
`bjj_08` — el historial se parte en dos sin que nadie se entere. Ese fue el
comportamiento durante un tiempo.

**Salir tiene que limpiar lo local, no solo cerrar la sesión.** Está en
`olvidarDatosDelUsuario()` (`src/lib/db.ts`) y lo llama `Marco.tsx`. Hay dos
cosas que son del usuario y no del dispositivo:

- La **cola de salida**: lo que quede dentro se subiría con la sesión de quien
  entre después. La RLS rechazaría sesiones, rolls y eventos ajenos, y un roll
  observado quedaría atribuido a quien no es.
- **`bjj.sesion-abierta`**: el id de la sesión de entreno de hoy. Si se queda,
  el siguiente cuelga rolls de una sesión que no es suya, la RLS los rechaza y
  la cola se atasca sin explicar por qué.

La caché de técnicas sí se queda: el diccionario es igual para todos.

**La lectura de sesiones, rolls y eventos va por equipo.** Durante un tiempo
estuvo abierta a cualquier autenticado (`bjj_13`), que era el precio del
selector de practicante del análisis. Ya no: desde `bjj_15` se lee lo de la
gente con la que compartes equipo, y el filtro es
`private.practicantes_visibles()`.

**La escritura no se ha tocado nunca**: cada uno escribe lo suyo, y los
terceros solo por `registrar_roll_observado()`. Si tocas políticas, mantén esa
separación — abrirla al escribir sí sería un fallo grave.

Esas políticas van **por conjuntos**, `in (select private.…_visibles())`, y no
con un predicado por fila. No es estilo: la primera versión con predicado por
fila tardaba 631 ms en 679 eventos y la de conjuntos 9 ms. Si las reescribes,
mide antes de darlas por buenas.

**El análisis no agrega en React.** Todo sale ya sumado de `analisis()` en
Postgres, que existe porque las vistas `v_heatmap_*` agregan sin conservar
`modalidad` ni `fecha` y por eso no dan el filtro gi/nogi. Si hace falta un
corte nuevo, se añade en SQL. Lo único que calcula la pantalla es el máximo de
la rampa de color, que es dibujo y no dato.

**Un enfoque está activo cuando `hasta is null`**, no cuando su fecha de fin
llega hasta hoy. Con la otra regla, "darlo por terminado" ponía `hasta` = hoy y
el enfoque seguía saliendo como activo el resto del día: el botón no hacía lo
que dice. Y así `hasta` no necesita pinzas —ni `max(desde, ayer)` ni casos
especiales para el que empezó hoy— y el periodo guardado es verdad: desde el
día que lo escribiste hasta el día que lo cerraste.

Cambiar de enfoque **cierra el anterior, nunca lo borra**. El historial es la
mitad del valor: saber que en mayo estuviste con De la Riva y en junio con
media guardia es lo que hace que esto no sea una nota en el móvil.

**El contraste del enfoque mira el periodo del enfoque, no el filtro de la
pantalla.** Si empezó hace tres semanas, la pregunta es qué hiciste en esas
tres semanas, y da igual qué ventana esté seleccionada arriba. La pantalla lo
dice, porque si no el número parece incoherente con todo lo demás.

**El verde es marca, no es dato.** El acento de Gullo (`#458c50`) va en la
cabecera, la pestaña activa, el botón principal, los enlaces, la píldora de
sincronización y el foco. **No entra nunca** en un heatmap, una barra, una celda,
el marcador ni una leyenda: ahí manda azul `#3987e5` para ti y naranja `#d95926`
para el rival, y no se tocan.

Las dos razones, y las dos cuentan. Verde contra naranja es el par que se cae
con el daltonismo más común —cerca del 8 % de los hombres, y un gimnasio de BJJ
es mayoritariamente hombres—; azul contra naranja sobrevive. Y como el acento
es tematizable por equipo, si los colores de datos también lo fueran una
academia podría elegir un color que deje ilegible su propio heatmap.

`npm run test:contraste` lo comprueba: falla si el token de marca aparece en un
selector de datos, y falla si aparece un segundo verde en la hoja.

**Qué se tematiza y qué no.** Está escrito en la cabecera de `globals.css`, que
es la única fuente de tokens:

| familia | ejemplo | ¿lo cambia el equipo? |
|---|---|---|
| `--marca-*` | `--marca`, `--marca-texto`, `--marca-tinta` | **sí**, `equipos.color_acento` |
| `--dato-*` | `--dato-yo`, `--dato-op`, `--dato-neg` | nunca |
| estado | `--ok`, `--aviso`, `--error` | nunca |
| superficies | `--plano`, `--superficie`, `--texto` | no, cambian con el tema |

El equipo elige **un** color. De ahí `aplicarAcento()` (`src/lib/tema.ts`) deriva
el texto legible midiendo contraste contra el fondo del tema, y la tinta del
botón eligiendo entre negro y blanco. Por eso una academia puede poner el color
que quiera sin dejarse la interfaz ilegible. El hex que llega de la base **se
valida** antes de tocar un `style`: acaba en CSS, y `red;background:url(…)` es
un valor legal para un `text`.

**Los `--dato-*` son rellenos; para texto están `--dato-yo-texto` y
`--dato-op-texto`.** El naranja de relleno sobre el hueso claro da 2,81 y no se
puede leer. Los de texto son pasos de la misma rampa aprobada, no colores
nuevos.

**Los botones de marca llevan texto oscuro, no blanco.** Blanco sobre el verde
de Gullo da 4,10 y no pasa AA; el casi-negro da 4,80. Su web lo usa en blanco,
pero solo con tipografía enorme, donde el listón baja a 3.

**El tema por defecto es el CLARO, y el sistema no decide.** El orden es
preferencia guardada → claro. `prefers-color-scheme` **no** se mira: una
instalación nueva en un móvil en oscuro abre igualmente en claro, porque la
primera impresión es la marca y porque el claro es el tema de los informes y de
lo que se comparte. El atributo `data-tema` lo pone un script en línea en
`layout.tsx` antes de pintar; si eso se mueve a React, vuelve el fogonazo
blanco al abrir.

**El tema se lee de un store, no de un `useState` por componente.** `useTema()`
usa `useSyncExternalStore`. Con estado por componente parecía funcionar —el CSS
cuelga del atributo y todo se repinta— pero el heatmap, que es quien de verdad
lee el tema desde React para invertir la rampa, se quedaba con el valor viejo y
dibujaba la rampa al revés en oscuro.

**Mezclar gi y no-gi en el mismo heatmap dibuja un juego que no existe.** En gi
hay agarres y estrangulaciones de solapa que en no-gi no existen, y en no-gi hay
una rama entera de ataques a las piernas. Por eso el filtro está arriba y no
escondido.

**En modo claro la rampa del heatmap va de claro a oscuro; en oscuro, al
revés.** El extremo "cerca de cero" tiene que ser el que se funde con el fondo.
Sin invertirla, los valores bajos son los que más brillan y el heatmap miente.
El color del número de dentro se calcula por luminancia de esa celda, no por
índice de la rampa.

**Los puntos se derivan, nunca se guardan.** No hay columna `puntos` en `rolls`
ni en `eventos`, y no la añadas: el tanteo es una función de la lista de
eventos, igual que el heatmap. Si mañana se corrige un evento mal registrado, el
marcador se corrige solo; una columna guardada se queda vieja y nadie se entera.

El precio de esa decisión es que el cálculo existe **dos veces**:
`src/lib/puntos.ts` para el marcador en vivo y `puntos_roll()` en SQL para el
histórico. Dos implementaciones que se separan son un bug esperando, así que las
dos leen los mismos casos: `src/lib/__fixtures__/puntos.json`. Si tocas una
regla, tócala en los dos sitios y pasa `npm run test:puntos` **y**
`db/pruebas/puntos.sql`.

---

## Mapa del código

```
src/lib/bjj.ts             vocabulario + máquina de estados del roll  ← el corazón
src/lib/puntos.ts          el marcador IBJJF (gemelo de puntos_roll() en SQL)
src/lib/__fixtures__/      los casos que leen el test de TS y el de SQL
src/lib/db.ts              IndexedDB (Dexie) + cola de salida
src/lib/sync.ts            vaciado de la cola
src/lib/database.types.ts  tipos del esquema (subconjunto escrito a mano)
src/components/Marco.tsx   sesión, pestañas, píldora de sincronización
src/components/Feed.tsx    qué ha pasado en el equipo, con reacciones
src/components/Enfoque.tsx lo que dices que trabajas, contra lo que hiciste
src/components/Tema.tsx    el store del tema y el interruptor
src/components/Avatar.tsx  el cinturón de cada uno, en SVG
src/lib/tema.ts            resolución del tema y derivación del acento
src/app/globals.css        LOS TOKENS ← la única fuente de color de la app
scripts/contraste.mjs      mide los contrastes; falla por debajo de AA
src/app/login              entrar, crear cuenta, código de 6-10 dígitos
src/app/auth/callback      vuelta del enlace
src/app/auth/reset         contraseña nueva
src/app/practicantes       alta y edición del roster
src/app/entreno            el logging: tu roll y el modo observador
src/app/analisis           heatmaps, head-to-head, evolución, enfoque
src/app/equipo             feed, ficha del equipo, miembros, unirse/crear
src/lib/textos/es.ts       las palabras de pantalla: "Team", "Open Mat"
src/app/quedadas           próximas y pasadas, plazas, informe
db/                        el esquema SQL, igual que lo desplegado
db/pruebas/                los tests en SQL, uno por bloque
db/pruebas/semilla-demo.sql  el juego de datos de prueba, SOLO local
pruebas/                   los recorridos en navegador (npm run test:navegador)
scripts/contraste.mjs      mide los contrastes; falla por debajo de AA
scripts/iconos.mjs         genera iconos y splash desde public/logo-gullo.png
docs/                      decisiones de producto y backlog
```

`src/lib/bjj.ts` es donde está la inteligencia: `accionesPosibles()` decide qué
botones se ven según la posición, y `aplicarAccion()` devuelve el evento y el
estado siguiente. Cambiar el flujo de logging es tocar ahí, no en la pantalla.

Las dos funciones reciben el **modo**. Cada acción lleva dos etiquetas y cada
pregunta dos redacciones: logueando lo tuyo dicen "Me pasa" y "¿Dónde caes?";
observando dicen "Pasa la guardia" y "¿Dónde cae Pablo?". La máquina de estados
es exactamente la misma — lo único que cambia son las palabras. Si añades una
acción, tiene que llevar sus dos etiquetas.

`docs/BJJ-Log-Prototipo.html` es la referencia viva de cómo debe sentirse el
logging, modo observador incluido. Se abre en el navegador.

---

## Cosas que ya nos mordieron

**Un `create or replace function` sin la cláusula `set` borra la configuración
de la función.** Al recrear `espejar_roll` sin repetir `set search_path = public`
se quedó sin él, y el linter de Supabase lo cazó. El código "no cambiaba", pero
la función sí. Si recreas una función, comprueba `proconfig` después.

**`mejorar posición` no generaba evento.** Se actualizaba la posición y no se
escribía nada, así que los 4 puntos de la montada y los 2 de la rodilla en
barriga eran invisibles. Resuelto con `transicion` (`bjj_10`): ahora sí genera
evento, salvo cuando el destino es la espalda, que se registra como
`toma_espalda` porque ese tipo ya existía y puntúa igual.

**Borrar un practicante fallaba** por el choque entre `ON DELETE CASCADE` en
sesiones y `ON DELETE SET NULL` en `rolls.oponente_id`. Resuelto difiriendo dos
claves foráneas (migración `bjj_06`). Si se recrean esas FK, mantener el
`deferrable initially deferred`.

**@supabase/ssr fuerza PKCE, y PKCE no sirve para enlaces por correo.** Por eso
`src/lib/supabase.ts` usa `createClient` de `@supabase/supabase-js` y **no**
`createBrowserClient` de `@supabase/ssr`. Ese paquete construye el objeto de
auth con `flowType: "pkce"` **después** del spread de tus opciones, así que
pedirle `implicit` no hace nada: es una opción ignorada, no una preferencia.

Estuvimos un tiempo creyendo que estaba arreglado porque el fichero decía
`flowType: 'implicit'`. No lo estaba. Si alguien vuelve a meter `@supabase/ssr`
"porque es el recomendado para Next", el magic link se rompe otra vez, y de
forma intermitente —solo cuando el correo se abre en otro navegador—, que es la
peor manera de romperse.

Por qué PKCE no puede funcionar aquí: el verificador se guarda en el navegador
donde **pides** el enlace y se exige en el que lo **abres**. Con un enlace que
llega por correo, esos dos sitios no tienen por qué coincidir — Gmail abre su
propia pestaña, la PWA instalada es otro contexto, el correo se mira en otro
móvil.

Esta app no tiene autenticación en servidor (no hay `middleware.ts`, no hay
`createServerClient`, todas las pantallas son de cliente), así que ese paquete
no aportaba nada. La sesión vive en `localStorage`.

**El camino que de verdad cierra el problema es el código de 6 dígitos**, no el
enlace: la sesión se abre en la misma pestaña donde se pidió. El enlace se
mantiene porque es cómodo cuando el correo se abre en el mismo sitio, pero
depende de un enlace que caduca, es de un solo uso y que algunos escáneres de
correo corporativos abren —y queman— antes que el usuario.

Requisito: las plantillas de correo tienen que enseñar `{{ .Token }}`. En el
panel nuevo están en **Authentication → Emails → pestaña Templates** (ya no
cuelgan del menú lateral). Hacen falta tres: *Magic Link*, *Confirm signup* y
*Reset Password*. Sin el token no llega ningún código y media pantalla de
entrada no sirve.

**El helper de RLS vive en el esquema `private`**, no en `public`, para que
PostgREST no lo publique en `/rest/v1/rpc/`.

**Las vistas llevan `security_invoker = on`.** Sin eso cualquiera leería los
heatmaps de otro a través de la vista.

**El linter de Supabase avisa de `registrar_roll_observado`**, y el aviso es
correcto: es una función SECURITY DEFINER que puede llamar cualquier usuario
autenticado. Está así a propósito y el porqué está escrito al principio de
`db/06_rpc_roll_observado.sql`. No la "arregles" pasándola a SECURITY INVOKER
—dejaría de funcionar el modo observador entero— ni le quites el permiso a
`authenticated`. Lo que sí falta algún día es exigir que los dos practicantes
estén en tu roster; está en el backlog.

**El linter también avisa de las contraseñas filtradas, y ese no se puede
cerrar.** La comprobación contra HaveIBeenPwned es de plan Pro y el proyecto
está en el gratuito. Comprobado en el panel, no supuesto. Lo único que filtra
hoy es el mínimo de 8 caracteres. No persigas ese aviso creyendo que es un
descuido.

**Un test de RLS como superusuario no prueba nada.** `postgres` se salta la RLS,
así que todo pasa. Hay que hacer `set local role authenticated` y poner el claim
del usuario en `request.jwt.claims`. En `db/README.md` está el apaño completo.

---

## Cómo verificar que algo funciona

El proyecto tiene poca red de seguridad automática, así que:

- `npm run build` compila y hace typecheck en estricto. Que pase no es opcional.
- `npm run test:puntos` pasa los casos del fixture por el cálculo en TypeScript,
  y comprueba en cada uno el invariante del espejo. Su gemelo en SQL:

  ```bash
  psql ... -v ruta=$PWD/src/lib/__fixtures__/puntos.json -f db/pruebas/puntos.sql
  ```

  Ese sí manda cada caso por `registrar_roll_observado()`, así que de paso cubre
  la RPC, el espejo y el orden de los eventos. **Los dos tienen que dar los
  mismos números.**
- `stub-supabase.py` levanta una imitación de Supabase en `127.0.0.1:54321` con
  los ids reales de las técnicas y cuatro fichas — dos con cuenta además del
  usuario, que es el mínimo para probar una observación de verdad. Captura todo
  lo que la app escribiría, tablas y RPC, en `$CAPTURA` (por defecto
  `/tmp/capturado.json`; en Windows hay que apuntarlo a otro sitio). Se arranca
  con las variables de entorno del stub por delante:

  ```bash
  CAPTURA=./capturado.json python stub-supabase.py &
  NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 \
  NEXT_PUBLIC_SUPABASE_ANON_KEY=stub npm run dev
  ```

  **Con `PGURL` y `PSQL` puestos deja de imitar y habla con el Postgres local**,
  y además **con la RLS puesta**: pone el claim y hace `set local role
  authenticated` en cada consulta. Eso es lo que hace que un fallo de privacidad
  salga recorriendo la app y no en el móvil de alguien — la primera vez que se
  activó, cazó la pantalla de equipo enseñando un equipo del que no eras miembro.

  Las tablas y funciones que cruzan el puente están en `TABLAS_PUENTE` y
  `RPC_PUENTE`. Una tabla que no esté en la lista no da error: contesta `[]`
  desde la imitación en memoria, que se parece bastante a "no hay datos". Si un
  recorrido enseña vacíos que no te cuadran, mira ahí antes que en la app.

- `npm run test:navegador` recorre la app entera a 390px en los dos temas: el
  tema, el análisis contra la semilla, la rampa del heatmap y los enfoques. Son
  70 comprobaciones y **es lo único que ve lo que el typecheck no puede** — la
  máquina de estados, los objetivos táctiles, la RLS de verdad. Necesita el
  stub y el servidor de desarrollo levantados; si faltan, se planta y dice
  cómo, en vez de fallar con un error raro veinte segundos después.
- `npm run test:contraste` mide los contrastes de los tokens y falla por debajo
  de AA. También falla si el verde de marca se cuela en un heatmap, una barra o
  una leyenda, y si aparece un segundo verde en la hoja. Los valores los lee de
  `globals.css`, así que no hay un gemelo que se separe.
- **La base local se siembra**, no se llena a mano:

  ```bash
  psql ... -v confirmar=si -f db/pruebas/semilla-demo.sql
  ```

  Es determinista —nada de `random()`— así que los recorridos en navegador
  pueden comprobar cantidades. Da 180 rolls de Goku en cuatro meses, con el
  reparto **pesado a propósito**: vive en la espalda y la montada y casi no
  toca las piernas. Un juego de datos plano dibuja un heatmap sin relieve y no
  prueba que la rampa de color funcione.

  El roster es de Dragon Ball para que se vea de un golpe que es falso: un juego
  de prueba con nombres realistas acaba en una captura pareciendo un
  head-to-head de verdad. **Borra sesiones, rolls y eventos**, así que pide
  `-v confirmar=si` y se planta si `auth.users` tiene más de tres cuentas.
- **Antes de tocar el esquema de producción, una copia**: `scripts/copia.sh`.
  Y `scripts/restaurar.sh` la devuelve a una base local. Correr el restaurador
  de vez en cuando **en frío** no es paranoia: las tres primeras versiones del
  script de copia producían ficheros con muy buena pinta que no se podían
  restaurar, y solo se supo restaurándolos. La prueba de que una copia sirve es
  que la copia restaurada pasa `db/pruebas/rls.sql`.
- Para cambios de esquema, probar contra un Postgres local antes de aplicar la
  migración al proyecto real. Sin Docker también se puede: ver `db/README.md`.
- **A producción se llega por `psql`**, con las credenciales en `.env.local`
  (`SUPABASE_DB_HOST`, `_PORT`, `_NAME`, `_USER`, `_PASSWORD`). Es el pooler de
  sesión, que es IPv4; la conexión directa es solo IPv6 y desde una red
  corporativa no suele salir.

  ```bash
  val() { grep -m1 "^$1=" .env.local | cut -d= -f2- | tr -d '
'; }
  export PGPASSWORD="$(val SUPABASE_DB_PASSWORD)"
  psql -h "$(val SUPABASE_DB_HOST)" -p "$(val SUPABASE_DB_PORT)"        -U "$(val SUPABASE_DB_USER)" -d "$(val SUPABASE_DB_NAME)" -f db/XX.sql
  ```

  Se leen así, con `cut`, y no con `eval`: una contraseña con comillas o
  símbolos rompe el `eval` entero y el error no se parece en nada a la causa.

  Esto existe porque aplicar una migración por el MCP obliga a escribir el SQL
  entero en el mensaje —ochocientas líneas son unos nueve mil tokens— y eso se
  come el contexto justo al final de una sesión larga, que es cuando toca
  desplegar. Con `-f` el coste es cero.
- El bucle que más ha valido la pena: recorrer la app en el navegador contra el
  stub, coger el payload que capturó y **replicarlo tal cual contra Postgres**.
  Así se comprueba que lo que la app genera de verdad lo acepta el esquema de
  verdad, que es distinto de que las dos mitades funcionen por separado.

No des por bueno un cambio de logging sin recorrer un roll entero en el
navegador: la máquina de estados tiene caminos que el typecheck no cubre.

---

## Al terminar cada tanda: escribe en el registro de cambios

Añade una entrada **arriba** en `docs/CAMBIOS.md`. Es parte de la definición de
terminado, no un extra: sin ella, quien recoja el proyecto la semana siguiente
—Felipe, el PM o tú mismo en otra sesión— vuelve a discutir cosas ya cerradas y
propone lo que ya está hecho.

El formato completo está en la cabecera de ese fichero. Lo esencial:

- **Decisiones** que hayas tomado por el camino. Obligatorio. Es lo que ni el
  `git log` ni el esquema cuentan.
- **Sabido roto**: lo que dejas a medias o funcionando mal a propósito.
  Obligatorio. Es lo que más tiempo ahorra al siguiente.
- Migraciones aplicadas, y qué tachaste o añadiste en `docs/BACKLOG.md`.
- La lista de ficheros es **opcional**: eso ya está en el `git log`.

Diez líneas por entrada como máximo. Un registro que nadie lee es peor que no
tenerlo.

## Dónde está la documentación de producto

- `docs/BACKLOG.md` — el backlog vivo, por temática y prioridad. `02-backlog.md`
  es el anterior y se queda solo como archivo.
- `docs/CAMBIOS.md` — el registro de cambios.
- `docs/00-…`, `01-…`, `03-…`, `04-…` — decisiones de producto y diseño por bloque.
- `docs/PROMPT-*.md` — los encargos escritos, con el contexto y la verificación
  que se pidió en cada uno.
- `docs/TEMA-GULLO.html` — el tema visual aprobado. **El verde es marca, no es
  dato**: azul `#3987e5` (yo) y naranja `#d95926` (rival) no se tematizan nunca.
- `docs/BJJ-Analisis-DEMO.html` y `docs/BJJ-Log-Prototipo.html` — las referencias
  de diseño del análisis y del logging.
