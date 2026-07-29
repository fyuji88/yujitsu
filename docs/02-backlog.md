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

**Reclamar ficha.** Cuando Marc se instale la app, su historial ya existe como contacto. Hay que
poder decir "esta ficha soy yo": pasar `user_id` de null a su id, conservando todos los rolls.

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

**Cerrar la lectura cuando entre gente de la academia.** Hoy cualquier
autenticado lee los datos de cualquiera, y además las tablas crudas por
PostgREST. La versión futura es un `perfil_publico` por practicante, o
visibilidad limitada a la gente con la que has rodado. Se cierra con una
migración y nadie pierde nada — por eso se abrió sin miedo.

**Comparar dos practicantes lado a lado.** El selector enseña a uno cada vez, a
propósito. Comparar bien —mismos ejes, misma escala de color, misma ventana—
es un problema de diseño entero: dos heatmaps con escalas distintas invitan a
conclusiones falsas, y hacerlo mal es peor que no hacerlo.

**Los puntos IBJJF no están en esta pantalla.** El marcador vive en el logging.
Llevarlos al análisis —"dominas 8-2 de media contra Pablo"— es su propio bloque.

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
8. **`de_rodillas` en `bjj_posicion`** — vocabulario, lo cierran Felipe y Pablo.
9. **Sugerencias de técnicas** — cuando haya gente fuera de vosotros dos usándolo.

Duplicados, reclamar ficha y restringir el modo observador al roster entran todos
a la vez: el día que entre la primera persona de la academia.
