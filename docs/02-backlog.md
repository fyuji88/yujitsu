# Backlog de producto

**Actualizado: 29 julio 2026**
Ideas registradas, con el diseño ya pensado para que no haya que redescubrirlo.

---

## 0 · ~~Modo observador~~ — HECHO (29 julio 2026)

~~Un tercero registra en vivo el roll de otros dos, y cada uno recibe sus datos.~~

Implementado y desplegado. La base ya lo soportaba desde `bjj_04`; lo que
faltaba era la puerta de escritura, porque **la RLS impide que un tercero
escriba datos de otros** — autenticado como el coach, crear la sesión de otro
practicante falla con `42501: new row violates row-level security policy`.

Se resolvió con `registrar_roll_observado()` (`bjj_09`, SECURITY DEFINER): una
sola llamada que escribe sesión, roll, eventos y el espejo al compañero en una
transacción. En la app es el botón **👁 Observar** de la pantalla de entreno.

### Lo que queda pendiente de esto

**Restringir a tu roster.** Hoy cualquier usuario autenticado puede meter rolls
en el historial de cualquier practicante: la función se salta la RLS por
diseño y no comprueba que el observador conozca de nada a los dos que registra.

Con dos amigos y su coach es asumible — la función solo escribe, nunca lee datos
ajenos, y el dueño puede borrar lo que le metan. Pero **el día que entre gente
de la academia esto se queda corto**: hace falta exigir que A y B estén en el
roster del observador, o que exista una relación previa entre ellos. Es una
condición añadida al principio de la función, no un rediseño.

**Rolls observados sin sumisión.** El roll observado siempre pasa por la
pantalla de eventos. El "solo resultado" del prototipo (`pMinimo`) no está
portado — para los días en que el coach solo quiere anotar quién ganó.

---

## 1 · Pestaña "Practicantes" — DESBLOQUEADA

**Estado: la base ya lo soporta** (migración `bjj_07_alta_de_companeros`).

Al diseñarla apareció que **no se podía**: la política de RLS original solo dejaba escribir la
fila cuyo `user_id = auth.uid()`, o sea tu propia ficha. Dar de alta a Marc, que no usa la app,
fallaba con `new row violates row-level security policy`. La pestaña era imposible de construir.

Ahora hay dos tipos de ficha en el roster:

| | Ficha con cuenta | Ficha de contacto |
|---|---|---|
| `user_id` | el de su usuario | `null` |
| Quién la edita | solo esa persona | quien la dio de alta (`creado_por`) |
| H2H cruzado | sí | no, pero cuenta igual como oponente |
| Para qué | Felipe, Pablo | el resto de la academia |

Comprobado contra la base real: puedes crear tu ficha, dar de alta compañeros y editarlos; y
**no** puedes tocar la ficha de alguien con cuenta propia ni los contactos que dio de alta otro.

### Lo que falta pensar

**Duplicados.** Si Felipe da de alta a "Marc" y Pablo también, hay dos Marc distintos y el H2H se
parte en dos. Hace falta o bien un roster compartido por academia, o una función de fusionar
fichas. No es urgente con dos usuarios, pero se convierte en el problema número uno el día que
entre gente de la academia.

**Los grupos (`bjj_14`) lo desbloquean por los dos lados.** El "roster compartido
por academia" ya existe: es la lista de miembros del grupo, y una ficha creada
dentro del grupo la ven todos, así que el segundo Marc deja de aparecer solo. Y
para los duplicados que ya existan, fusionar es ahora una operación con un
ámbito claro —dos fichas del mismo grupo— en vez de una búsqueda a ciegas por
toda la tabla. Sigue faltando escribirla.

**Reclamar ficha.** Cuando Marc se instale la app, su historial ya existe como contacto. Hay que
poder decir "esta ficha soy yo": pasar `user_id` de null a su id, conservando todos los rolls.
Con grupos, el permiso para hacerlo es evidente: que un admin del grupo lo
confirme. Sin grupos no había forma de decidir quién podía autorizarlo.

---

## 2 · ~~Puntos y dominancia (estilo IBJJF)~~ — HECHO (29 julio 2026)

~~No medir solo sumisiones, sino quién dominó el roll.~~

Implementado y desplegado. Observando, una cabecera fija con el tanteo de los
dos y un cronómetro con pausa; en modo propio, en el resumen con desglose.

**Se desbloqueó añadiendo `transicion`** al enum (`bjj_10`), que era la decisión
de vocabulario que faltaba. Sin ella, montada (4) y rodilla en barriga (2) no
se registraban y el marcador se dejaba 6 de los puntos posibles.

Los puntos **se derivan, nunca se guardan**: son una función de los eventos,
como el heatmap. El precio es que el cálculo vive dos veces —`src/lib/puntos.ts`
en vivo y `puntos_roll()` en SQL— y lo que impide que se separen es que los dos
leen los mismos casos, `src/lib/__fixtures__/puntos.json`.

### Lo que queda pendiente de esto

**Falta `de_rodillas` en `bjj_posicion`.** Empezar de rodillas no es `de_pie` ni
es `clinch`, y en un gimnasio es de las salidas más frecuentes. El selector de
posición de salida se montó con lo que hay. Es vocabulario, así que lo cierran
Felipe y Pablo.

**Un pase que aterriza directo en montada solo cuenta 3.** Los puntos de montada
salen de un evento `transicion`, y ese solo lo genera "mejorar posición". Si el
observador pasa la guardia y elige `montada` como destino del pase, no hay
transición y los 4 de la montada se pierden. Se puede resolver haciendo que
cualquier acción que aterrice en una posición que puntúa emita también su
transición — pero eso cambia cómo se cuentan los eventos y es una decisión, no
un arreglo.

**Ventajas y penalizaciones** siguen fuera: son criterio de árbitro y duplicarían
las pulsaciones. Un intento de sumisión ya se registra con `completado = false`.

---

## 2 bis · Notas del diseño original de los puntos

La idea: no medir solo sumisiones, sino **quién dominó el roll**. Especialmente en modo
observador, donde el coach ya está mirando y puede llevar la cuenta.

### El hallazgo: los puntos ya están en los datos

No hace falta registrar nada nuevo. La puntuación IBJJF es una función de `tipo` + `posicion`,
que es exactamente lo que guarda cada evento:

| Acción | Puntos | Nuestro evento |
|---|---|---|
| Derribo | 2 | `tipo = derribo` |
| Barrida | 2 | `tipo = barrida` |
| Rodilla en barriga | 2 | posición `rodilla_en_barriga` |
| Pase de guardia | 3 | `tipo = pase_guardia` |
| Montada | 4 | posición `montada` |
| Toma de espalda (con ganchos) | 4 | `tipo = toma_espalda` |

Así que es una vista más sobre `eventos`, no un modelo nuevo. Sale casi gratis.

### Los dos huecos, y por qué importan

**Las transiciones no generan evento.** Pasar de cien kilos a montada vale 4 puntos, pero hoy no
lo registramos como evento — solo cambia la posición de estado. Esto convierte lo de añadir
`transicion` al enum de **"estaría bien"** en **"hace falta"**: sin eso, la puntuación se deja
fuera casi todos los puntos de montada y buena parte de los de espalda.

**No somos un campeonato.** El IBJJF exige 3 segundos de estabilización y tiene ventajas, y en un
open mat no hay árbitro. Propuesta: llamarlo **"puntos estimados"** en la interfaz y no fingir
precisión de competición. La utilidad no es el número exacto, es la tendencia: contra quién
dominas aunque no finalices, y si tu juego está mejorando por posición y no solo por sumisión.

### Qué desbloquea

Un roll que hoy sale como "sin sumisión" pasa a leerse como "8-2, dominaste". Es justo el vacío
que dejó la conversación sobre qué significaba `sin_sumision`: el saldo posicional del roll.
También da un H2H mucho más rico contra los cinturones altos, donde casi nunca finalizas.

---

## 2 ter · ~~Pantalla de análisis~~ — HECHA (29 julio 2026)

~~Heatmaps, head-to-head y evolución dentro de la app.~~

Puerto de `docs/BJJ-Analisis-DEMO.html` a React, leyendo de Supabase. Con
selector de practicante, filtro gi/no-gi y ventana temporal.

**Hizo falta SQL, al contrario de lo que parecía.** Las vistas
`v_heatmap_ofensivo` y compañía agregan con `group by autor_id, posicion,
objetivo…`, y ahí se pierden `modalidad` y `fecha`: con ellas el filtro gi/no-gi
es imposible. `analisis()` (`bjj_13`) rehace la agregación sobre `v_eventos`,
que sí las conserva, y devuelve la pantalla entera en un jsonb.

**Y hubo que abrir la lectura** de sesiones, rolls y eventos a cualquier
autenticado, o el selector devolvería tablas vacías. La escritura no se tocó.

### Lo que queda pendiente de esto

~~**Cerrar la lectura cuando entre gente de la academia.**~~ — **hecho**
(`bjj_15`). Ya no lee cualquiera: se lee lo de la gente con la que compartes
grupo, vía `private.practicantes_visibles()`. Se cerró exactamente como estaba
previsto, con una migración y sin que nadie perdiera nada.

La primera versión de esa política se escribió con un predicado por fila y
tardaba **631 ms** en 679 eventos. Reescrita como `in (select …)` sobre
conjuntos: **9 ms**. Si alguien vuelve a tocar esas políticas, que mida antes
de dar por bueno el resultado.

**Comparar dos practicantes lado a lado.** El selector enseña a uno cada vez, a
propósito. Comparar bien —mismos ejes, misma escala de color, misma ventana—
es un problema de diseño entero: dos heatmaps con escalas distintas invitan a
conclusiones falsas, y hacerlo mal es peor que no hacerlo.

**Los puntos IBJJF no están en esta pantalla.** El marcador vive en el logging.
Llevarlos al análisis —"dominas 8-2 de media contra Pablo"— es su propio bloque.

---

## 2 quater · ~~Bloque social~~ — HECHO (29 julio 2026)

~~Grupos con roles, quedadas con inscripciones, informe, feed y enfoques.~~

Seis migraciones (`bjj_14` … `bjj_19`) y cuatro pantallas. Lo que cambia de
verdad: hasta aquí la app era un cuaderno personal que además dejaba observar;
ahora tiene una unidad social —el grupo— y todo lo demás cuelga de ella.

| | Qué es | Migración |
|---|---|---|
| **Grupos** | academia o pandilla, con admin y código de unión | `bjj_14` |
| **Lectura por grupo** | ves lo de la gente con la que compartes grupo | `bjj_15` |
| **Quedadas** | open mat con plazas, lista de espera y token de invitación | `bjj_16` |
| **Feed** | qué ha pasado en el grupo, con reacciones | `bjj_17` |
| **Informe** | resumen congelado de la quedada, con títulos | `bjj_18` |
| **Enfoques** | lo que dices que trabajas, contra lo que hiciste | `bjj_19` |

**Lo que hace distinto al informe:** se calcula una vez y se guarda en jsonb.
Un resumen que cambia cuando alguien corrige un evento de hace un mes no es un
recuerdo de esa noche, es una consulta. Regenerarlo es explícito.

**Lo que hace distinto a los enfoques:** las posiciones y las técnicas van
estructuradas, no solo en texto libre. Por eso la app puede decir "dijiste De
la Riva y la has jugado en 2 de 34 rolls". Con texto libre eso no existe.

### Lo que queda pendiente de esto

**El informe todavía no tiene de qué tirar en producción.** Ninguna quedada
tiene rolls colgados, porque las quedadas son de ayer y los 247 rolls son de
antes. El primer open mat que se registre desde la app lo llena solo.

**Los títulos se reparten por |z| sobre las métricas de esa quedada.** Con
cuatro asistentes eso es casi un reparto por orden. Con veinte tiene sentido;
con cuatro, hay que mirar si las frases siguen sonando a verdad.

**Enfoques solo se ven en Análisis.** Es donde tienen sentido —pegados a los
números que los contradicen—, pero un enfoque también es algo que quieres ver
del compañero al abrir su ficha. La ficha de practicante no existe todavía como
pantalla propia.

---

## 3 · Sugerir técnicas nuevas / mandar feedback

**Principio: nadie escribe directamente en `tecnicas`.** El diccionario es lo que sostiene los
heatmaps; si cada uno mete su variante, en tres meses hay cuatro nombres para la misma
estrangulación y el análisis se rompe. Ese fue el motivo de cerrar el vocabulario en el Bloque 0.

Diseño propuesto — una tabla de sugerencias que vosotros dos curáis:

```
tecnica_sugerencias
  id · practicante_id · texto_libre · posicion · objetivo · tipo
  estado (pendiente | aceptada | rechazada) · tecnica_id (al aceptar) · notas
```

**El detalle que lo hace bueno:** en la app, el chip "Otra…" abre texto libre y hace dos cosas a
la vez. Crea la sugerencia **y registra el evento igual**, con `tecnica_id = null` pero con su
posición y su objetivo — que es lo que alimenta el heatmap. Así el dato nunca se pierde por no
tener la técnica en el diccionario. Cuando aceptáis la sugerencia, un `update` reasigna los
eventos huérfanos a la técnica nueva y el histórico queda completo hacia atrás.

Con `alias[]` ya en la tabla de técnicas, muchas sugerencias no serán técnicas nuevas sino
nombres nuevos para una existente: aceptar = añadir el alias. Eso además enseña qué palabras usa
la gente de verdad.

---

## Orden que propongo

1. ~~**Auth + pestaña Practicantes**~~ — hecho.
2. ~~**PWA de logging**~~ — hecho, el MVP de verdad.
3. ~~**Modo observador**~~ — hecho.
4. ~~**`transicion` en el enum**~~ — hecho, y con él los puntos.
5. ~~**Puntos estimados**~~ — hecho.
6. **Tiempo de dominio / posesión** — el dato ya se captura (`eventos.segundo_roll`
   sella cada evento con el segundo del cronómetro). Falta decidir cómo se cierra
   el último tramo y qué cuenta como disputa.
7. ~~**Heatmaps y head-to-head en la app**~~ — hecho.
8. ~~**Bloque social**~~ — hecho: grupos, quedadas, informe, feed y enfoques.
9. **`de_rodillas` en `bjj_posicion`** — vocabulario, lo cierran Felipe y Pablo.
10. **Sugerencias de técnicas** — cuando haya gente fuera de vosotros dos usándolo.

Duplicados, reclamar ficha y restringir el modo observador al roster entran todos
a la vez: el día que entre la primera persona de la academia. Los grupos ya dan
el marco para los tres —quién puede autorizar qué—, así que ahora es trabajo de
escribirlo, no de decidirlo.
