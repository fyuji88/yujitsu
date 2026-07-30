# yujitsu · backlog

**Actualizado: 29 julio 2026.** Lo lleva Claude como PM del proyecto. Felipe
aporta ideas y decide; Claude Code implementa.

> **Este fichero es el backlog vivo.** `docs/02-backlog.md` es el anterior y se
> queda como archivo: tiene las notas de diseño detalladas de lo que ya se
> implementó y merece la pena conservarlo. Lo pendiente se lleva **aquí**.
> El diseño detallado de cada bloque está en los `docs/PROMPT-*.md` y en
> `docs/03-social-y-tarjeta-de-roll.md`.

---

## Cómo están priorizadas

Con un solo criterio, el del documento de fundador: **yujitsu es un producto de
captura de datos**, así que lo que sube es lo que hace que la gente registre, o
lo que evita perder lo registrado. Todo lo demás va después, por bonito que sea.

**Alta** · o bloquea el uso, o evita una catástrofe, o es la razón por la que
alguien registra. **Media** · mejora real, no urgente. **Baja** · buena idea sin
ventana clara, o esperando a que pase algo antes.

Han salido **dieciocho altas**, que son más de las que me gustaría — pero la mitad
son baratas, no grandes: mantener la pantalla encendida son unas pocas líneas y
quitar `molestias` es un borrado. "Alta" aquí significa prioridad, no tamaño.

Si solo puedes con cinco cosas, este es el orden: **el login**, **las copias de
seguridad**, **que la cola no pierda nada**, **las pruebas de RLS** y **los cuatro
números medidos**. Las cuatro primeras evitan que el proyecto se muera de golpe; la
quinta es la que te dice si se está muriendo despacio.

---

# 1 · Fiabilidad y operación

| | Iniciativa |
|---|---|
| 🔴 **Alta** | **Arreglar el login.** `@supabase/ssr` fuerza PKCE y pisa el `flowType: 'implicit'`; PKCE no funciona con enlaces abiertos en otro navegador. Usar `createClient` directamente y añadir código de 6 dígitos. Prompt escrito. **Hasta que esto esté, Pablo solo entra si abre el enlace donde lo pidió.** |
| 🟡 Media | **Pasar Supabase a Pro** para tener copias diarias y recuperación a un punto en el tiempo. Baja de alta a media porque ya hay red: `scripts/copia.sh` + `scripts/restaurar.sh`, con la restauración probada de verdad. Falta que Felipe registre la tarea semanal (`scripts/programar-copia.ps1`); hasta entonces las copias son manuales. |
| 🔴 **Alta** | **La cola no puede perder nada.** Reintentos con espera creciente, nada descartado en silencio, e indicador visible de "3 rolls sin subir". En un producto de captura, perder una sesión una vez es el final. |
| 🔴 **Alta** | **Recolector de errores** (Sentry gratuito). Hoy te enteras de los fallos si alguien te los cuenta. Estás operando a ciegas. |
| 🔴 **Alta** | **Aviso de versión nueva** dentro de la app, nunca recarga silenciosa y jamás en mitad de un roll. Y **migraciones compatibles hacia atrás**: expandir → migrar → contraer. Hoy se hacen cambios que rompen clientes viejos. |
| 🔴 **Alta** | **`docs/CAMBIOS.md`, escrito por Claude Code** al terminar cada tanda, como parte de la definición de terminado. Migraciones, **decisiones** y **sabido roto** — las dos últimas obligatorias, porque son lo que el `git log` no cuenta. Se audita en la retro del domingo. Es lo que evita que el PM proponga cosas ya hechas. |
| 🟡 Media | **Entorno de pruebas.** Hoy cada migración va directa a producción. Usar ramas de Supabase. |
| 🟡 Media | **Dos administradores por grupo** y credenciales que no cuelguen solo de tu correo personal. Continuidad barata. |
| 🟢 Baja | **Semilla de demo en el repo** (`db/98_datos_demo.sql`) para que cualquier rama arranque con la base poblada. |

# 2 · Seguridad y privacidad

| | Iniciativa |
|---|---|
| 🔴 **Alta** | **Pruebas de RLS automáticas.** La RLS es todo tu perímetro: no hay servidor, el navegador habla directo con Postgres. Que corran en cada cambio, no a mano. Es la acción de seguridad con más retorno que existe aquí. |
| ~~🔴 Alta~~ | ~~**Quitar o proteger `molestias`**~~ — **hecho** (`bjj_26`): columna borrada. Era dato de salud del artículo 9 del RGPD, con cero filas y sin interfaz que lo ofreciera. |
| 🔴 **Alta** | **Solo mayores de edad, dicho explícitamente**, y aviso de privacidad de una página. Las academias viven en parte de las clases infantiles; en cuanto entre una, alguien querrá registrar niños. |
| 🔴 **Alta** | **Visibilidad del perfil en tres niveles** (privado / grupo / público, con "grupo" por defecto) y un segundo interruptor para los puntos débiles. Entra **junto con el bloque de grupos**: si la gente entra antes de que exista el control, ya has publicado sus datos sin preguntar. |
| 🔴 **Alta** | **Suelo de cohorte en los agregados.** Ningún promedio se muestra con menos de 5 practicantes, **aplicado por celda y en SQL**. Con un gimnasio pequeño, tu número más la media del resto despeja los de los demás: es una ecuación, no una filtración exótica. |
| 🟡 Media | **Exportar y borrar tus datos.** Ética, cumplimiento y argumento de venta con un coach desconfiado, las tres cosas a la vez. |
| 🟡 Media | **Portabilidad en formato abierto**, que además te obliga a mantener el esquema limpio. |
| 🟢 Baja | **Confirmación del dueño** para rolls que le mete un tercero. Resuelve el modelo de confianza sin modelar relaciones, y de paso da la interfaz de deduplicación. |
| 🟢 Baja | **Tope de escritura por llamante** en `registrar_roll_observado`, para que un bug no inunde el historial de alguien. |

# 3 · Registro y análisis (el núcleo)

| | Iniciativa |
|---|---|
| 🔴 **Alta** | **Pantalla de análisis y heatmaps.** Es la recompensa de registrar; sin ella el registro no paga. Vistas desplegadas y prompt escrito, con selector de practicante, filtro gi/nogi, cuentas en vez de porcentajes con pocos datos, y toque en una celda para ver los rolls detrás. |
| 🔴 **Alta** | **Ficha del rival antes de rodar.** Tres líneas sobre el compañero que tienes delante. Es lo único del producto que te sirve **esa misma tarde** en vez de dentro de tres meses, y sale de vistas que ya existen. |
| 🔴 **Alta** | **Tarjeta de resumen del roll.** Dominancia, ganador con gracia, exportable. Cierra de paso el bloque de posesión. Y es el átomo del que se construye el informe de la quedada. |
| ~~🔴 Alta~~ | ~~**Mantener la pantalla encendida** durante el roll (`wakeLock`)~~ — **hecho**: `src/lib/pantalla.ts`, activo solo mientras `fase === 'roll'` para no comerse la batería del entreno entero. Se vuelve a pedir al volver de una distracción, que es cuando el navegador lo suelta. Eran más de cinco líneas. |
| ~~🔴 Alta~~ | ~~**El chip de precisar, en la pantalla**~~ — **hecho**: al cerrar un roll propio, en lote, ordenado por enfoque activo y por uso, y solo si la técnica tiene variantes. Falta la entrada desde el historial (rolls observados), que necesita una pantalla que no existe. |
| 🔴 **Alta** | **Generar `database.types.ts` desde la base**, y que el CI falle si lo commiteado no coincide. La quinta comprobación de `comprobar-vocabulario.py` es el cinturón —caza el campo que sobra—; esto es el arreglo: elimina la clase entera en vez de vigilarla. |
| 🔴 **Alta** | **`v_tecnicas_practicante` con `modalidad` y `fecha`, y que `analisis()` lea de ella.** Hoy el panel y la vista calculan lo mismo por separado: dos fuentes de la verdad esperando a separarse. |
| 🟡 Media | **Sellar los eventos espejo con un id común** en `registrar_roll_observado()`, para que precisar propague. Hoy los rolls comparten `par_id` y los eventos no comparten nada, así que el mismo hecho físico puede acabar con dos técnicas distintas según a quién mires. |
| 🟡 Media | **Precisar no propaga al roll espejo.** Si A precisa su kimura a tarikoplata, la copia de B sigue diciendo kimura. Hace falta un enlace a nivel de EVENTO entre los dos espejos: hoy solo hay `par_id`, que es del roll, y `created_at` no vale porque los eventos de un roll comparten sello. |
| 🟡 Media | **Tiempo de dominio / posesión.** El dato ya se captura en `segundo_roll`; falta decidir cómo se cierra el último tramo y qué cuenta como disputa. |
| 🟡 Media | **Borrar el puente `registrar_roll_observado(p_grupo, …)`** (`bjj_28`). **Condición para borrarlo: que ninguno de los cuatro tenga elementos en la cola** — se comprueba abriendo la app en cada móvil y viendo la píldora en "sincronizado". Hasta entonces se queda: reintroduce el nombre ambiguo que `bjj_27` vino a quitar, pero es lo que impide que un roll pendiente se pierda con un 404. |
| 🟡 Media | **`academia` en `practicantes` y `sesiones`, ¿sigue haciendo falta?** Es texto libre, y desde `bjj_14` el equipo dice lo mismo mejor. Salió al renombrar el vocabulario (`bjj_27`) y se dejó fuera a propósito: quitar una columna con datos dentro es otra conversación, no un renombrado. |
| ~~🟡 Media~~ | ~~**Aplicar `bjj_27` a producción**~~ — **hecho**. Con copia previa restaurada antes. Salió con el cliente ya desplegado por delante, así que hubo un hueco con producción rota: la próxima vez que migración y cliente vayan juntos, el push va después. |
| 🟡 Media | **Línea de tiempo del roll, editable.** Deshacer solo el último evento se queda corto en cuanto hay marcador visible. |
| 🟡 Media | **Radar de efectividad** en la tarjeta. Bloqueado: pases y barridas fallados no se registran, así que dos de los cinco ejes no tienen denominador. |
| 🟢 Baja | **Rolls observados sin sumisión**, el "solo resultado" del prototipo, para cuando el coach solo quiere anotar quién ganó. |
| 🟢 Baja | **Sugerencias de técnicas** con curación vuestra. Cuando haya gente fuera de vosotros dos. |
| 🟢 Baja | **Comparativa lado a lado** de dos practicantes. Exige mismos ejes y escala; hacerlo mal invita a conclusiones falsas. |

# 4 · Social y comunidad

| | Iniciativa |
|---|---|
| 🔴 **Alta** | **Grupos con roles + recorte de la RLS.** Es la unidad de crecimiento del producto y lo que arregla el "todos ven a todos" que dejamos abierto. Las dos cosas entran juntas. Prompt escrito. |
| 🔴 **Alta** | **Quedadas con plazas e inscripciones**, admitiendo externos (tu open mat es 90 % Gullo y 10 % de fuera). Llegas al domingo con el evento creado. |
| 🔴 **Alta** | **Informe de la quedada con ranking y títulos.** No es una feature de uso: **es tu bucle de crecimiento.** Ocho personas nombradas quieren verlo, y el enlace les pide unirse. |
| 🟡 Media | **Feed del gimnasio con reacciones.** Derivado, sin tablas nuevas salvo `reacciones`. Enseña lo que el WhatsApp no puede. |
| 🟡 Media | **Enfoques** — "qué estoy trabajando estas semanas", con posiciones y técnicas estructuradas para poder contrastar lo que dijiste con lo que hiciste. Lo más original de la lista. |
| 🟢 Baja | **Chat de verdad.** Decidido: feed primero. Solo si el feed se queda corto. |
| 🟢 Baja | **Emparejador de open mat**: quién debería rodar con quién esta tarde. |

# 5 · Gamificación

| | Iniciativa |
|---|---|
| 🟡 Media | **Arquetipos animal + elemento**, en inglés, con Monkey. Siguiente después del social. El eje animal ya está validado contra datos; el elemento necesita percentiles dentro del grupo y unas 8 personas para significar algo. |
| 🟡 Media | **Retos semanales.** El enum `bjj_tipo_regla` ya está en el esquema esperándolos. Demo dibujada. |
| 🟡 Media | **El mapa de tu juego.** Posiciones que se encienden al finalizar desde ellas por primera vez. Barato y motivador. Demo dibujada. |
| 🟡 Media | **Némesis y cliente.** Una consulta sobre `v_h2h`, por proporción y no por bruto, mínimo 10 rolls. Demo dibujada. |
| ~~🟡 Media~~ | ~~**Logros mensuales y su ranking**~~ — **hecho** (`bjj_21`): 27 logros derivados, colección en la ficha, ranking del mes y feed agregado por sesión. Falta cerrar `el_ultimo_en_irse`, que se dejó fuera porque `rolls.orden` es por sesión y no por quedada. |
| 🟡 Media | **Sesgo de los logros: ausencia contra presencia.** Los logros que se definen por **la ausencia** de algo (IMPASABLE, LIMPIO, MURO, CUELLO DE ACERO, CINTURÓN INVISIBLE) se inflan solos con no registrar el evento, así que **requieren `origen = 'observador'`**. Los de presencia no, porque para conseguirlos hubo que registrar algo activamente. Flag `requiere_observador` en el catálogo; `rolls.origen` ya existe. Y la procedencia se enseña: "×14 · 5 verificados 👁", con el ranking contando solo verificados por defecto. |
| 🟡 Media | **Logros en el feed: resumen por sesión, no un elemento por logro.** "Pablo registró 6 rolls anoche · IMPASABLE ×2 · MURO · RELÁMPAGO". Con elemento propio solo para la primera vez, los números redondos (×5, ×10, ×25), el primero del grupo y los raros. Un elemento por logro serían ~150 a la semana con doce personas, y eso mata el feed y las reacciones a la vez. |
| 🟡 Media | **La familia de logros de constancia** — EL NOTARIO, OJO DEL COACH, SEMANA COMPLETA. Son los únicos que premian **registrar** en vez de rendir, y registrar es el único riesgo que mata el producto. De todos los logros, estos primero. |
| 🟡 Media | **Pestaña de grupo**: nombre, escudo, lema y **top 5 del mes**. Ranking unificado de cuatro componentes, con la **progresión contra ti mismo** como pieza clave para que no sea una escalera de cinturones. Solo top 5, nunca la tabla entera. |
| 🟢 Baja | **Modo torneo** con cronómetro reglamentario. Sale casi gratis desde el marcador, pero es otra conversación. |

| ~~🔴 Alta~~ | ~~**La batería de RLS en CI**~~ — **hecho**: `.github/workflows/ci.yml` aplica las migraciones desde cero en un Postgres de servicio, corre `rls.sql` y `puntos.sql`, y añade `test:puntos`, `test:contraste` y `npm run build`. Falta meter las pruebas que necesitan datos sembrados (`logros.sql`, `informe.sql`, `quedadas.sql`). |
| ~~🔴 Alta~~ | ~~**Cerrar la lectura de `practicantes` a `anon`**~~ — **hecho** (`bjj_22`), y con ella `retos` y `reto_participaciones`. Queda **repasar el `grant all` por defecto de Supabase**: `anon` conserva INSERT/UPDATE/DELETE/SELECT sobre el resto de tablas. Hoy lo tapa la RLS, pero es superficie de la que no conviene depender. |
| ~~🟡 Media~~ | ~~**Que un invitado externo vea su quedada**~~ — **hecho** (`bjj_22`): una inscripción da acceso a esa quedada y a su informe, y a nada más. |

# 6 · Diseño y UX

Paleta de Gullo medida del logo: verde **`#458c50`**, hueso `#f1f0ee`, naranja
`#ff9058`. **El verde es marca, no es dato**: azul `#3987e5` (yo) y naranja
`#d95926` (rival) no se tocan nunca. **El tema claro es el defecto.**

| | Iniciativa |
|---|---|
| 🔴 **Alta** | **Plantilla de tarjeta compartible** con la marca del grupo. Cosmética y motor de crecimiento a la vez, y por eso es la única alta de este grupo. |
| ~~🟡 Media~~ | ~~**Tokens en una sola fuente de verdad + tema por grupo**~~ — **hecho** (`bjj_20`). Tres familias en `globals.css`: `--marca-*` tematizable, `--dato-*` y estado nunca. El grupo elige un color y la app deriva el resto midiendo contraste. |
| ~~🟡 Media~~ | ~~**Tema claro por defecto**~~ — **hecho**. El oscuro es paleta propia, no derivada. El sistema no decide: guardada → claro. |
| ~~🟡 Media~~ | ~~**Avatares de cinturón**~~ — **hecho**. `src/components/Avatar.tsx`, SVG generado. La foto opcional sigue pendiente y va en su bloque. |
| ~~🟡 Media~~ | ~~**Un solo verde**~~ — **hecho**. `--good:#0ca30c` fundido con el de marca, y `npm run test:contraste` falla si aparece un segundo verde. |
| ~~🟡 Media~~ | ~~**Botones verdes con texto oscuro**~~ — **hecho**, y medido: la tinta acabó en `#050d06`, porque el `#0b1a0e` de la referencia da 4,38 y tampoco pasaba. |
| 🟡 Media | **Pictogramas de las 24 posiciones.** Lo que hace que parezca hecha por alguien que entrena, y arregla la legibilidad del heatmap en móvil. |
| 🟡 Media | **Modo tatami**: brillo y contraste altos, objetivos grandes, todo en la mitad inferior, usable con una mano y dedos sudados. |
| 🟡 Media | **Estados vacíos con carácter.** Son las primeras pantallas que ve cualquiera y hoy no existen. |
| 🟡 Media | **Onboarding de tres pantallas** y diseño explícito del arranque en frío: qué ves el día uno y el día tres. |
| 🟡 Media | **Auditoría de accesibilidad** — **medio hecho**: `npm run test:contraste` cubre los 34 pares de tokens y el recorrido comprueba los 44px de lo que se toca rodando. Falta el resto: lectores de pantalla, orden de foco y textos alternativos fuera de los avatares. |
| 🟢 Baja | **Confirmación sin mirar**: vibración corta y micro-animación al registrar. |
| ~~🟢 Baja~~ | ~~**Icono, splash y manifest**~~ — **hecho** con el logo de Gullo: 192, 512, enmascarable al 68 %, `apple-touch-icon` y once splash de iPhone. Se regeneran con `scripts/iconos.mjs`, que también escribe la lista de `src/lib/splash.ts`. Sin iPad, a propósito. |
| 🟢 Baja | **Tipografía de display** parecida al wordmark de Gullo. La **escala tipográfica ya está declarada** (seis pasos, `--txt-1` … `--txt-6`), igual que la de espaciado de 4px, los radios y las sombras. |

| 🟢 Baja | **Un reto cuya regla sea "consigue el logro X N veces".** Los retos ya tienen ventana, objetivo y progreso guardado; los logros ya son un predicado contable. Engancharlos es barato y da retos que se validan solos, sin que nadie tenga que arbitrar. |

| 🟡 Media | **Calibrar las rarezas de los logros.** <br>**Disparador, no "cuando haya datos":** cuando existan **200 rolls reales de al menos 5 personas distintas**, excluyendo los de demo (Goku y Vegeta). Se mide con `scripts/listo-para-calibrar.sql`. <br>**Diana:** común 10–25 % de los rolls, poco común 3–10 %, raro por debajo del 2 %. Lo que se salga por arriba, se endurece. <br>**Punto fijo de la retro de los domingos**, no una tarjeta esperando a que alguien se acuerde. Hoy no se puede medir: los datos de Goku salen de un generador que solo emite evento cuando pasa algo, así que calibrar contra ellos sería calibrar contra las manías del simulador. |

# 7 · Datos y ciencia de datos

| | Iniciativa |
|---|---|
| 🟡 Media | **Etapa comparativa**: "tu tasa de pase desde media guardia es 22 %, la media de los blancos del gimnasio es 41 %". El salto de valor más grande de todos, y no necesita modelos — necesita población, o sea el bloque social. |
| 🟡 Media | **Matriz de transiciones** ("desde cien kilos, ¿a dónde vas?"). Es lo que `posicion_destino` desbloquea. |
| 🟡 Media | **Mapa colectivo del gimnasio**: dónde flojea toda la academia, para que el coach planifique el mes con datos. **Es literalmente lo que una academia pagaría.** Sube a alta el día que entre un segundo gimnasio. |
| 🟡 Media | **Vídeo con marcas de tiempo.** Saltar al momento de cada evento porque ya tienes `segundo_roll`. Cero modelos, valor enorme. |
| 🟢 Baja | **Dónde te estancas**: la posición donde acumulas tiempo y eventos sin progresar. |
| 🟢 Baja | **Planes de partida prescriptivos** por rival. Producto entero, y llega después de la comparativa. |
| 🟢 Baja | **Registro por voz.** El vocabulario es cerrado, así que la gramática ya existe. Infravalorada, pero no ahora. |
| 🟢 Baja | **Carga de entrenamiento.** Pisa terreno de salud; enmarcar como carga, nunca como consejo médico. |
| 🟢 Baja | **Vídeo analizado por IA** y **datos de competición / luchadores famosos.** Riesgo legal, coste alto, y te convierten en un producto de contenido. |

# 8 · Crecimiento y negocio

| | Iniciativa |
|---|---|
| 🔴 **Alta** | **Los cuatro números, medidos cada semana**: rolls por persona activa, proporción registrada por observador, gente que entra desde un informe compartido, y quién vuelve. Hoy no mides nada, o sea que no puedes dirigir. |
| 🔴 **Alta** | **No meter un segundo gimnasio hasta que Gullo registre cuatro semanas seguidas sin que nadie se lo recuerde.** Es una iniciativa de no hacer, y es de las importantes: escalar antes es escalar una fuga. |
| 🟡 Media | **Media página con Pablo** sobre quién es dueño de qué. Ahora que da igual es cuando es fácil. |
| 🟡 Media | **Mirar el paisaje competitivo**: qué apps existen, qué cobran, qué les critican. Es lo único de todo esto sobre lo que ni tú ni yo tenemos datos. |
| 🟡 Media | **Extraer los textos a un fichero de traducciones.** No traducir todavía, pero dejar de incrustar textos: ahora cuesta una tarde, con la app hecha cuesta semanas. |
| 🟢 Baja | **Decidir el canal de soporte.** Un WhatsApp basta para tres gimnasios. Decide cuál es antes de necesitarlo. |
| 🟢 Baja | **Entidad legal, términos de servicio y facturación.** El día que entre dinero, no antes. |
| 🟢 Baja | **Comprobar nombre y dominio** antes de imprimir nada. |
| 🟢 Baja | **Nada de publicidad.** En un producto con datos del cuerpo y del rendimiento, quema la confianza que es tu activo. |

# 9 · Condicionadas: el día que entre gente de la academia

Las cuatro pasan a **alta** ese día y hoy son bajas. El bloque de grupos es lo que
las desbloquea.

**Fichas duplicadas y fusionarlas** — hoy si tú y Pablo dais de alta a Marc hay dos
Marc y el head-to-head se parte en dos · **Reclamar ficha** cuando alguien se
registra, conservando su historial · **Restringir el modo observador al roster** ·
**Analítica agregada de academia** como primera cosa vendible.

---

## Decisiones abiertas

| Decisión | Bloquea | Mi recomendación |
|---|---|---|
| `posicion_destino` para las transiciones | matriz de transiciones | sí, columna aparte |
| `de_rodillas` en `bjj_posicion` | posición inicial | vosotros |
| ¿la guardia es disputa? | dominancia | disputa |
| pases/barridas fallados: ¿toque, inferencia o nada? | radar | tres ejes honestos |
| ¿ganador siempre? | tarjeta del roll | interruptor por grupo |
| ¿títulos negativos? | informe | detrás de un interruptor |
| pase que aterriza en montada cuenta 3 en vez de 7 | puntos | vosotros |

**Cerradas el 29 de julio:** el bloque social entero en un prompt, en seis fases con
parada tras la RLS · el open mat de los domingos es una **quedada de Gullo que
admite externos** · **feed ahora, chat después** · alta por **código de unión y
también manual** · la entidad se llama `grupos` · arquetipos **en inglés**, con
**Monkey** · **tema claro por defecto**.

---

## ✅ Hecho

**Tema Gullo y sistema de diseño** · tokens en tres familias con el claro como
base y el oscuro como paleta propia · tema por grupo con un solo acento, del que
se deriva todo lo demás midiendo contraste · avatares de cinturón en SVG ·
iconos de la PWA desde el logo · `npm run test:contraste`, que falla por debajo
de AA y si el verde se cuela en los datos.

**Bloque social** · grupos con roles y código de unión · lectura por grupo ·
quedadas con plazas y lista de espera · feed con reacciones · informe congelado
de la quedada con ranking y títulos · enfoques contrastados con los datos.

**Semilla de demo** determinista y solo local, con roster de Dragon Ball, para
que los recorridos en navegador tengan datos con forma que comprobar.

Auth por magic link · pestaña de practicantes con altas y edición · PWA de logging
con máquina de estados · escritura local-first con cola · modo observador con
`registrar_roll_observado()` · `transicion` en el enum · marcador de puntos IBJJF
en vivo con cronómetro y deshacer · selector de posición inicial · sello en
segundos de cada evento.

## 🧊 Fuera a propósito

**Ventajas y penalizaciones**: criterio de árbitro, duplicarían las pulsaciones, y
un intento fallido ya se registra con `completado = false`. **App nativa**: una URL
instalable, sin store ni 99 €/año; solo si algún día queréis Apple Watch o push en
segundo plano.
