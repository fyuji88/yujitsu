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
