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

**Sabido roto:**
- No hay pantalla para elegir el acento del grupo: hoy se cambia por SQL.
- **Sin splash propio en iOS.** Android lo compone con `background_color` y el
  icono; iOS querría `apple-touch-startup-image` en una docena de tamaños.
- El service worker solo cachea `/`, `/entreno` y `/practicantes`: análisis,
  grupo y quedadas no abren sin red. Es anterior a esta tanda.
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
