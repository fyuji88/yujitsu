# Prompt para Claude Code — pantalla de análisis y heatmaps

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a construir la **pantalla de análisis** dentro de la app: heatmaps,
head-to-head y evolución. Lee antes `CLAUDE.md` y `HANDOVER.md`.

## La referencia es un fichero, no una descripción

Abre **`docs/BJJ-Analisis-DEMO.html`** en el navegador. Ese es el diseño
aprobado, construido con 3 meses de datos simulados. Tiene el modo claro y el
oscuro (botón arriba a la derecha) y la vista de tablas.

**No lo reinventes.** Tu trabajo es portarlo a React dentro de la app, leyendo
de Supabase en vez de datos incrustados, y hacerlo funcionar en móvil. Si algo
del diseño te parece mejorable, dilo antes de cambiarlo.

## De dónde salen los datos

Las vistas ya existen y están desplegadas. No hace falta SQL nuevo:

| Bloque | Vista |
|---|---|
| Heatmap ofensivo | `v_heatmap_ofensivo` |
| Heatmap defensivo | `v_heatmap_defensivo` |
| Saldo por guardia | `v_guardias` |
| Fuertes / débiles | `v_fuertes_debiles` |
| Head-to-head | `v_h2h` |
| Evolución semanal | `v_evolucion_semanal` |
| Cobertura del observador | `v_cobertura_observador` |

Todas llevan `security_invoker = on`. **No repliques la lógica de agregación en
el cliente**: si necesitas un corte que no existe, añade una vista, no un
`reduce` en React.

## La pantalla es de cualquier practicante, no solo tuya

Arriba del todo, un selector de practicante. Por defecto tú; al cambiarlo, toda
la pantalla —los dos heatmaps, las guardias, los fuertes y débiles, la
evolución— pasa a ser de esa persona. Es un selector, no una pantalla nueva:
mismo diseño, otra fila de datos.

**Esto choca de frente con la RLS y hay que tocarla.** Hoy las políticas de
`sesiones`, `rolls` y `eventos` solo dejan leer lo tuyo, así que el selector
devolvería tablas vacías para todo el mundo menos para ti. Es el reflejo exacto
del problema que ya resolvimos al escribir en modo observador, pero al leer.

La decisión está tomada: **cualquier usuario autenticado puede leer los datos de
análisis de cualquier practicante.** El razonamiento va en un comentario de la
migración, porque dentro de seis meses parecerá un descuido y no lo es:

- Un roll es de dos. El heatmap ofensivo de Felipe contra Pablo *es* el
  defensivo de Pablo, así que buena parte de los datos de cada uno ya eran
  visibles para el otro a través de sus propios rolls. Lo que se abre de nuevo
  son los rolls con terceros, no el grueso.
- Son dos amigos y su coach, y compararse entre ellos es el objetivo declarado
  del proyecto.
- Se puede deshacer. Abrir una política de lectura no es como añadir un valor a
  un enum: si mañana entra gente de la academia y esto se queda corto, se cierra
  con otra migración y nadie pierde nada. Anota en `docs/02-backlog.md` la
  versión futura: un `perfil_publico` por practicante, o visibilidad limitada a
  la gente con la que has rodado.

Implementación: políticas de `select` para `authenticated` sobre `sesiones`,
`rolls` y `eventos`. Ten presente que eso abre también las tablas crudas por
PostgREST, no solo las vistas — es aceptable aquí, pero **déjalo escrito**. Las
políticas de escritura **no se tocan**: cada uno sigue escribiendo lo suyo, y
los terceros solo a través de `registrar_roll_observado`.

Comprueba que cada vista expone el id del practicante, y filtra por el
seleccionado de forma explícita en el cliente. No te apoyes en que la RLS filtre:
a partir de esta migración ya no filtra nada en lectura.

## Las reglas de diseño que hacen que se vea así

Están todas aplicadas en el HTML de referencia. Respétalas:

**Los dos heatmaps usan rampas secuenciales de un solo tono**, no arcoíris:
azul para el ofensivo, naranja para el defensivo. La rampa azul va de `#cde2fb`
a `#0d366b` en 13 pasos.

**En modo oscuro la rampa se invierte.** El extremo "cerca de cero" tiene que
ser el que se funde con el fondo. En claro eso es el tono clarito; en oscuro, el
oscuro. Si no lo inviertes, los valores bajos son los que más brillan y el
heatmap miente. Es un fallo que ya cometí una vez.

**El color del número dentro de la celda se calcula por luminancia** del fondo de
esa celda, no con un umbral de índice. Está la función `ink()` en el HTML.

**Las columnas vacías se dejan a la vista.** Que muñeca, bíceps, columna y
pantorrilla estén a cero no es ruido: es la información de que nunca atacas ahí.
No filtres las columnas sin datos. Las filas sí se filtran a las posiciones que
tienen algún dato, o la tabla se hace ilegible.

**El saldo por guardia y el head-to-head son barras divergentes**, con azul a
favor, rojo `#d03b3b` en contra, y una línea neutra en el cero.

**La evolución es una línea con dos series** (a favor / en contra), con leyenda
siempre visible y etiqueta directa solo en el último punto. Nunca dos ejes Y.

**Paleta:**

```
claro   superficie #fcfcfb · fondo #f9f9f7 · tinta #0b0b0b / #52514e / #898781
        rejilla #e1e0d9 · eje #c3c2b7 · borde rgba(11,11,11,.10)
        serie 1 #2a78d6 · serie 2 #eb6834
oscuro  superficie #1a1a19 · fondo #0d0d0d · tinta #fff / #c3c2b7 / #898781
        rejilla #2c2c2a · eje #383835 · borde rgba(255,255,255,.10)
        serie 1 #3987e5 · serie 2 #d95926
```

**Accesibilidad, que no es opcional aquí:** cada celda y cada barra llevan
tooltip; hay un botón para ver los mismos datos como tabla; y el modo oscuro es
una paleta elegida, no un filtro invertido.

## Lo que el HTML de referencia NO resuelve: el móvil

El demo está pensado para pantalla ancha. La app es móvil primero, y ahí un
heatmap de 24 filas × 10 columnas no cabe. Esto es tu problema de diseño, no un
detalle. Algunas salidas posibles:

- Un heatmap cada vez, con pestañas ofensivo/defensivo en lugar de lado a lado.
- Scroll horizontal con la columna de posiciones fija.
- Celdas más pequeñas y las etiquetas de objetivo abreviadas o en vertical.

Prueba de verdad a 390px de ancho antes de darlo por bueno. Si hay que sacrificar
algo, sacrifica densidad, nunca legibilidad de las etiquetas.

## Filtros: dos, y no más

**Gi / nogi / todo.** Este es el importante y no es opcional. Mezclar gi y nogi
en el mismo heatmap produce un dibujo que no describe ningún juego real: en gi
hay agarres y estrangulamientos con solapa que en nogi no existen, y en nogi hay
una rama entera de ataques a las piernas que en gi está restringida por
cinturón. Sumarlos borra las dos cosas. Ponlo arriba, junto al selector de
practicante.

**Ventana temporal**, con "todo" por defecto y una opción de "últimos 30 días".
Mientras haya poco volumen, "todo" es lo único sensato; en cuanto haya seis
meses dentro, un heatmap de todo el histórico esconde precisamente lo que ha
cambiado.

Nada más. La tentación es añadir un filtro por rival, por posición y por
técnica, y acabar con una pantalla que hay que configurar antes de que diga
nada. El head-to-head ya cubre el corte por rival.

## Honestidad con pocos datos

Con un selector de practicante vas a caer constantemente en gente con tres
rolls, así que esto deja de ser un detalle del estado vacío y pasa a ser una
regla de la pantalla:

**Por debajo de cierto volumen no se enseñan porcentajes, se enseñan cuentas.**
"Pasas la media guardia el 100% de las veces" con n=1 es una frase falsa; "1 de
1" es verdad y se lee igual de rápido. Elige un umbral, ponlo en un solo sitio
del código y decláralo en la interfaz.

**Arriba, la unidad que una persona piensa: rolls.** "12 rolls, 3 sesiones", no
"47 eventos". El número de eventos es un detalle de implementación.

**Di quién registró los datos.** No es lo mismo un practicante cuyos rolls los
ha registrado el coach que uno que se los registra él: cuando te registras tú,
faltan sistemáticamente las cosas que no ves —tu propia espalda, las sumisiones
que intentaste y no salieron—. `v_cobertura_observador` ya tiene ese dato. Una
línea discreta del tipo "8 de 12 rolls registrados por un observador" cambia por
completo cómo hay que leer el heatmap defensivo, y cuesta nada.

## De la celda a los rolls

Al tocar una celda del heatmap, una lista de los rolls que hay detrás: fecha,
rival, y qué pasó. Esto convierte la pantalla de póster en herramienta — es lo
que te deja pasar de "me pillan mucho el cuello desde la espalda" a "ah, fueron
esos tres rolls con Pablo de la semana pasada". Y es lo que hace que os fiéis de
los números, que con datos propios importa más de lo que parece.

Si por tiempo hay que dejar algo fuera de esta versión, que sea el filtro
temporal, no esto.

## Estado vacío

Ahora mismo la base **casi no tiene datos**: hay un roll de prueba y poco más, y
practicantes con cero. Con cero, la pantalla no puede verse rota ni llena de
ceros: debe decir algo tipo "cuando registres unos cuantos rolls, aquí verás
dónde atacas y dónde te pillan", con un enlace a Entreno.

Con el selector hay un segundo estado vacío que es distinto y también hay que
escribir: **el practicante existe pero no tiene datos**. Ahí el mensaje no es
"empieza a registrar" —puede que no sea tu cuenta— sino algo como "todavía no hay
rolls registrados de Pablo".

## Cómo probarlo con datos

`db/99_datos_demo_opcional.sql` tiene 3 meses simulados: 41 sesiones, 180 rolls,
679 eventos, con un perfil de cinturón blanco que evoluciona. Cárgalo **en un
Postgres local**, no en producción, y desarrolla contra eso. Es exactamente lo
que alimenta el HTML de referencia, así que puedes comparar tu pantalla con él
celda por celda.

## Verificación

1. `npm run build` pasa.
2. Comparado contra `docs/BJJ-Analisis-DEMO.html` con los mismos datos: los
   números coinciden.
3. Probado a 390px de ancho, en claro y en oscuro.
4. Probado con la base vacía, con 3 rolls y con los 679 eventos. Los tres.
5. **La RLS, probada de verdad**: con `set local role authenticated` y el claim
   de un usuario, leer los datos de otro practicante tiene que funcionar en
   `select` y seguir fallando en `insert` y `update`. Si al abrir la lectura se
   ha colado escritura, es un fallo grave y no lo va a ver el typecheck.
6. El filtro gi/nogi cambia los números, no solo el estado del botón. Compruébalo
   con un practicante que tenga rolls de los dos tipos.
7. Si tocas producción, déjala como estaba. Ahora hay datos reales que Felipe
   quiere conservar: 5 practicantes, 2 usuarios con cuenta, un roll con sus
   eventos.

Cuando acabes, actualiza `CLAUDE.md` y tacha el bloque en `docs/02-backlog.md`.

## Fuera de alcance

Los **puntos estilo IBJJF** no entran aquí. Van en su propio bloque, junto con el
marcador en vivo, y dependen de una migración que puede no estar aplicada todavía
cuando trabajes en esto. No los implementes por tu cuenta ni los añadas a la
pantalla "ya que estamos".

La **comparativa lado a lado** de dos practicantes tampoco. El selector enseña a
uno cada vez. Comparar bien —mismos ejes, misma escala de color, misma ventana
temporal— es un problema de diseño entero y merece su propia versión; hacerlo mal
es peor que no hacerlo, porque dos heatmaps con escalas distintas invitan a
conclusiones falsas. Anótalo en `docs/02-backlog.md`.
