# BJJ Tracker — contexto del proyecto

App para registrar rolls de jiu-jitsu y analizar el juego. La construyen Felipe y
Pablo, que entrenan juntos en Barcelona. Este fichero lo lee Claude Code
automáticamente: aquí está lo que hay que saber antes de tocar nada.

**Idioma:** el código, los comentarios y la interfaz están en español. Los
identificadores de base de datos van sin acentos (`sumision`, `posicion`).

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

- Supabase: proyecto `idzlxkxeadrcolcnmoeo`, org `yujitsu`, eu-west-1, plan gratuito
- Vercel: `yujitsu-eight.vercel.app`, plan Hobby
- GitHub: `fyuji88/yujitsu`, privado, rama `main`
- 12 migraciones aplicadas (`bjj_01` … `bjj_12`), copia en `db/`

**Casi sin datos reales.** El diccionario (24 posiciones, 63 técnicas) y un roll
de prueba de Felipe.

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

**Nada escribe directo contra Supabase salvo `practicantes`.** Sesiones, rolls y
eventos pasan siempre por `encolar()` en `src/lib/db.ts`. El roll observado pasa
por `encolarRollObservado()`, que es la misma cola con otro destino: en vez de
`upsert` contra tablas, una llamada a `registrar_roll_observado()`. La regla de
fondo no cambia — nada llega a la red sin pasar por IndexedDB.

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

**La lectura de sesiones, rolls y eventos está abierta a cualquier
autenticado.** Es lo que hace posible el selector de practicante del análisis, y
está decidido a sabiendas (`bjj_13`): un roll es de dos, así que buena parte de
los datos de cada uno ya eran visibles para el otro. **La escritura no se
tocó**: cada uno escribe lo suyo, y los terceros solo por
`registrar_roll_observado()`. Si tocas políticas, mantén esa separación —
abrirla al escribir sí sería un fallo grave.

Ojo: eso abre también las **tablas crudas** por PostgREST, no solo las vistas.
Con dos amigos es aceptable; con gente de la academia dentro, no.

**El análisis no agrega en React.** Todo sale ya sumado de `analisis()` en
Postgres, que existe porque las vistas `v_heatmap_*` agregan sin conservar
`modalidad` ni `fecha` y por eso no dan el filtro gi/nogi. Si hace falta un
corte nuevo, se añade en SQL. Lo único que calcula la pantalla es el máximo de
la rampa de color, que es dibujo y no dato.

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
src/app/login              entrada por magic link
src/app/auth/callback      vuelta del enlace
src/app/practicantes       alta y edición del roster
src/app/entreno            el logging: tu roll y el modo observador
db/                        el esquema SQL, igual que lo desplegado
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

- Para cambios de esquema, probar contra un Postgres local antes de aplicar la
  migración al proyecto real. Sin Docker también se puede: ver `db/README.md`.
- El bucle que más ha valido la pena: recorrer la app en el navegador contra el
  stub, coger el payload que capturó y **replicarlo tal cual contra Postgres**.
  Así se comprueba que lo que la app genera de verdad lo acepta el esquema de
  verdad, que es distinto de que las dos mitades funcionen por separado.

No des por bueno un cambio de logging sin recorrer un roll entero en el
navegador: la máquina de estados tiene caminos que el typecheck no cubre.
