# Backlog de producto

**Actualizado: 28 julio 2026**
Ideas registradas, con el diseño ya pensado para que no haya que redescubrirlo.

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

## 2 · Puntos y dominancia (estilo IBJJF)

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

1. **Auth + pestaña Practicantes** — bloquea todo lo demás; sin fichas no hay nada que loguear.
2. **`transicion` en el enum** — decisión de vocabulario, y ahora es prerrequisito de los puntos.
3. **PWA de logging** — el MVP de verdad.
4. **Puntos estimados** — barato una vez existan las transiciones.
5. **Sugerencias de técnicas** — cuando haya gente fuera de vosotros dos usándolo.

Duplicados y reclamar ficha entran cuando entre la primera persona de la academia.
