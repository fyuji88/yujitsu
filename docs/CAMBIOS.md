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
