# yujitsu · los dos bloques de esta semana

**29 julio 2026.** Estructura de producto de las dos cosas que Felipe ha puesto
como prioridad: el **bloque social** (gimnasio, feed, quedadas, informe, enfoque)
y la **tarjeta de resumen del roll** en modo observador.

No es un prompt todavía. Es la estructura, las decisiones que hay que tomar
antes de escribirlo, y los agujeros que he encontrado mirando el esquema real.

---

## Cómo se enganchan los dos bloques

No son dos cosas separadas y conviene verlo antes de diseñarlos:

```
      roll  ──►  TARJETA DEL ROLL  ──┐
                                     ├──►  INFORME DE LA QUEDADA  ──►  FEED
   quedada ──►  todos sus rolls    ──┘
```

La tarjeta es el átomo. El informe de la quedada es la agregación de todas las
tarjetas de esa tarde. El feed es donde aparecen las dos. Si la tarjeta se diseña
como una pantalla suelta, el informe hay que rehacerlo entero; si se diseña como
un componente que recibe los datos de un roll, el informe es el mismo componente
repetido más un ranking.

**Consecuencia de orden**: la tarjeta va primero, aunque social parezca más
grande.

---

# BLOQUE A · Social

## A.1 · El gimnasio como entidad

Hoy `academia` es un **campo de texto libre** en `practicantes` y en `sesiones`.
Escribir "Gullo", "gullo bjj" y "Gullo Jiu-Jitsu" produce tres academias
distintas y nadie se entera. Convertirlo en entidad es la base de todo lo demás.

```
gimnasios
  id · nombre · slug · ciudad · codigo_union (para apuntarse)
  creado_por · created_at

miembros_gimnasio
  gimnasio_id · practicante_id · rol (admin | miembro)
  estado (activo | invitado | baja) · created_at
  PK (gimnasio_id, practicante_id)
```

**Por qué tabla de miembros y no una columna en `practicantes`:** la gente
entrena en más de un sitio —tu academia y el open mat de un colega— y el rol es
por gimnasio, no global. Una columna te obliga a rehacerlo en cuanto aparezca el
segundo gimnasio, que es exactamente lo que estás montando los domingos en tu
casa.

**Roles.** `admin` puede editar el gimnasio, invitar y quitar miembros, crear
quedadas y nombrar a otro admin. `miembro` ve el feed y se apunta a quedadas.
Nada más por ahora — cuanto más simple el modelo de permisos, menos superficie
para un bug de privacidad.

**Cómo entra la gente.** Recomiendo **código de unión** en vez de invitación por
correo: el SMTP del plan gratuito está muy limitado, y "apúntate con el código
GULLO-7X4" funciona en un vestuario mucho mejor que un email. El admin puede
regenerar el código si se filtra.

### Esto es lo que arregla la privacidad, y no es un detalle

Cuando abrimos la lectura para que se pudiera ver a cualquier practicante en el
análisis, lo dejamos en "cualquier usuario autenticado ve a cualquiera", con la
nota de que se quedaba corto en cuanto entrara gente. **El gimnasio es la
frontera que faltaba.** Con esta tabla, la política pasa a ser "ves los datos de
la gente que comparte gimnasio contigo", que es lo que cualquiera esperaría, y
cuesta lo mismo de escribir.

Así que la migración del gimnasio y el recorte de la RLS **entran juntos**. Si se
separan, queda una ventana en la que hay gimnasios pero todo el mundo lo ve todo,
y esa ventana no se cierra sola.

## A.2 · Feed, no chat

Pediste "un chat donde se vean las últimas actividades". Ahí hay dos productos
metidos en la misma frase y creo que solo uno merece la pena:

**El feed** es derivado: no se escribe nada nuevo, es una vista sobre lo que ya
hay. "Pablo registró 6 rolls anoche", "Goku ha desbloqueado Kesa gatame",
"Krilin se ha apuntado al open mat del domingo", "quedan 3 plazas".

**El chat** son mensajes de verdad: tabla nueva, no leídos, notificaciones,
moderación, y compite de frente con el grupo de WhatsApp que ya tenéis. Mi
recomendación es **no construirlo**. Vais a mantener el WhatsApp igualmente, y lo
que el WhatsApp no puede hacer es enseñar que has desbloqueado una posición
nueva.

Si quieres conversación, sale mucho más barato y da más juego permitir
**reacciones y comentarios sobre los elementos del feed**: un 🔥 en el roll de
alguien vale más que otro canal de texto vacío.

```
v_feed  (vista, union de varias fuentes, filtrada por gimnasio)
  tipo · referencia_id · practicante_id · gimnasio_id · cuando · datos jsonb

reacciones
  id · practicante_id · item_tipo · referencia_id · emoji · created_at
  UNIQUE (practicante_id, item_tipo, referencia_id, emoji)
```

El detalle que hay que acertar: la clave de una reacción es
`(item_tipo, referencia_id)` apuntando a la **fila de origen** —el `sesion_id`,
el `roll_id`, la inscripción— no a una fila del feed, porque el feed es una vista
y sus filas no tienen identidad estable.

Tipos de elemento para empezar: sesión registrada, posición desbloqueada, reto
completado, quedada creada, alguien se apunta, informe de quedada publicado,
nuevo miembro.

## A.3 · Quedadas

### Antes de nada: el nombre

**`eventos` está cogido.** Es la tabla central del modelo —cada acción de un
roll—. Llamar `eventos` a los open mats sería el peor choque de nombres posible
del proyecto. Propongo **`quedadas`**, que además es como lo dirías en voz alta:
"la quedada del domingo".

```
quedadas
  id · gimnasio_id · titulo · fecha · hora_inicio · duracion_min
  lugar · plazas_max · modalidad · notas
  estado (abierta | cerrada | cancelada) · creado_por · created_at

inscripciones
  id · quedada_id · practicante_id
  estado (apuntado | lista_espera | cancelado) · orden · created_at
  UNIQUE (quedada_id, practicante_id)
```

**Las plazas se controlan en la base, nunca en el cliente.** Dos personas dándole
a "apuntarme" a la vez con una plaza libre es el caso clásico. Hace falta
`apuntarse_a_quedada(p_quedada)` como `SECURITY DEFINER` con
`pg_advisory_xact_lock`, exactamente el mismo patrón que ya usa
`registrar_roll_observado`. Si hay hueco entras como `apuntado`; si no, a
`lista_espera` con su `orden`. Al cancelar alguien, sube el primero de la lista y
aparece en el feed.

### Enganchar los rolls a la quedada

`sesiones.quedada_id` nullable. **A nivel de sesión, no de roll**: todos los
rolls que haces esa tarde en ese sitio son de esa quedada, y preguntarlo una vez
en lugar de en cada roll son cuatro toques menos por tarde. Se puede cambiar
desde el resumen si te equivocas.

Y el detalle que lo hace bueno: **si hay una quedada hoy en tu gimnasio y estás
apuntado, viene preseleccionada**. En el caso normal son cero toques; "roll
libre" es solo lo que sale cuando no hay ninguna.

## A.4 · El informe de la quedada

Todo derivado: es una consulta sobre `eventos` filtrando por
`sesiones.quedada_id`. Cero tablas nuevas para calcularlo.

**Una decisión que sí hay que tomar: ¿vivo o congelado?** Si el informe se
recalcula, alguien que corrija un roll el martes cambia el informe del domingo
que ya se compartió. Recomiendo **congelarlo** al cerrar la quedada
(`quedada_informes` con un `jsonb`), y que sea el admin quien lo publica. Un
informe compartible que cambia solo confunde a todo el mundo.

### El ranking

Por **puntos estimados por roll** —promedio de `v_puntos_roll.puntos_autor`
menos los del rival—, que ya existe. Es más honesto que contar sumisiones: premia
al que domina aunque no finalice, que es justo lo que querías medir.

### Los títulos

La regla de diseño que importa más que la lista: **cada persona se lleva
exactamente un título, y nadie se queda sin uno.** Se asignan por mayor
desviación respecto a la media del grupo, en orden, sin repetir. Si se asignan
por umbrales fijos, los tres mismos se llevan todo cada domingo y el resto deja
de mirar el informe.

Positivos, que son los que puedes enseñar en el grupo:

| Título | Cómo se gana |
|---|---|
| **IMPASABLE** | menos pases de guardia encajados por roll |
| **EL RODILLO** | más pases completados |
| **EL FRANCOTIRADOR** | mejor ratio de sumisiones finalizadas sobre intentadas (mínimo 5 intentos) |
| **EL PULPO** | más intentos de sumisión, salgan o no |
| **HOUDINI** | más escapes desde posiciones dominantes |
| **EL MOCHILERO** | más espaldas tomadas |
| **PRIMERA SANGRE** | la sumisión más rápida de la tarde |
| **EL PROFESOR** | rodó con más compañeros distintos |
| **CINTURÓN INVISIBLE** | finalizó a alguien de cinturón superior |
| **PIERNAS DE ACERO** | más ataques a las piernas (nogi) |
| **LA MÁQUINA** | más rolls registrados en la quedada |
| **DIPLOMÁTICO** | más rolls terminados sin sumisión de ninguno |

Los de cachondeo —**EL ANCLA** para quien más tiempo pasa en una posición sin
progresar, **PEAJE** para quien más veces le pasan la guardia— los dejaría detrás
de un interruptor del admin. En un gimnasio de verdad, un título negativo
automático le sienta mal a alguien tarde o temprano, y prefiero que esa decisión
la tome un humano.

## A.5 · "En qué estoy trabajando"

Pedías un campo en el perfil para decir qué guardia, qué pase y qué sumisiones
estás priorizando estas dos semanas. Lo modelaría con historial, no como un campo
que se pisa:

```
enfoques
  id · practicante_id · desde · hasta
  texto · posiciones bjj_posicion[] · tecnicas uuid[]
  created_at
```

**Y aquí está lo que lo convierte en la mejor idea de tu lista.** Con las
posiciones y las técnicas estructuradas —no solo texto libre— la app puede
comparar lo que dijiste que ibas a trabajar con lo que hiciste de verdad:

> Dijiste que estas dos semanas ibas a jugar De la Riva.
> La has usado en **2 de 34 rolls**.

Eso no lo hace ninguna app de BJJ, sale gratis de vuestro modelo, y es
exactamente el tipo de espejo incómodo que hace que la gente vuelva. El texto
libre se queda igualmente, para el matiz; lo estructurado es lo que permite el
contraste.

---

# BLOQUE B · La tarjeta del roll

Al terminar un roll en modo observador, una tarjeta con: dominancia en % del
tiempo, radar de efectividad, y el ganador anunciado con gracia.

## B.1 · La dominancia obliga a cerrar el bloque de posesión

Esto ya no se puede aplazar: la tarjeta **es** el bloque de posesión. La buena
noticia es que el dato ya se captura, `eventos.segundo_roll` sella cada evento
con el segundo del cronómetro. Lo que falta es la regla, y es una decisión de
producto, no de código.

**Propuesta.** El roll es una sucesión de tramos entre eventos consecutivos, más
un último tramo desde el último evento hasta el final del cronómetro. Cada tramo
se atribuye según el **grupo** de la posición, y resulta que el enum
`bjj_grupo_posicion` ya existe con exactamente los valores que hacen falta:

| Grupo de la posición | A quién cuenta el tramo |
|---|---|
| `dominante` | al que está arriba |
| `guardia` | **disputa** |
| `neutral` (de pie, clinch) | disputa |
| `transicion` (scramble) | disputa |

O sea, tres barras: **dominio de A · disputa · dominio de B**. Como la posesión
en el fútbol, donde el centro del campo no es de nadie.

**La decisión que te toca:** ¿la guardia es disputa, o cuenta para el que la
juega? Yo la dejaría en disputa —una guardia cerrada activa no es dominio de
nadie, y si cuenta para abajo, el que juega guardia sale "dominando" el 70 % de
un roll en el que le pasaron tres veces—. Pero es discutible y el número cambia
mucho según lo que elijas. Como consuelo: el tiempo en guardia se puede enseñar
aparte, que es información útil sin contaminar la barra.

## B.2 · El radar: te lo hago, pero con una advertencia y un agujero

**La advertencia.** Los radar charts engañan: el área crece con el cuadrado del
valor, y cambiar el orden de los ejes cambia la forma sin cambiar los datos. Para
**la tarjeta** me parece bien —es un póster, se mira tres segundos y transmite
"forma del juego"—. Para la pantalla de análisis usaría barras emparejadas. Si
lo hacemos, con reglas: todos los ejes son porcentajes de 0 a 100 con el mismo
sentido, y el orden de los ejes se fija y se documenta.

**El agujero, que es lo importante.** De los ejes que quieres, **hoy solo dos son
calculables**:

| Eje | ¿Sale hoy? |
|---|---|
| Sumisiones (finalizadas / intentadas) | ✅ `completado` ya lo distingue |
| Defensa (escapes / veces que te dominaron) | ✅ derivable de los eventos |
| Control (% de tiempo dominante) | ⚠️ sale con B.1 |
| **Pases (completados / intentados)** | ❌ **los pases fallados no se registran** |
| **Barridas (completadas / intentadas)** | ❌ igual |

`eventos.completado` existe para todos los tipos, pero la máquina de estados solo
escribe pases y barridas que **salieron**. Un ratio de acierto sin denominador no
es un ratio.

Dos salidas, y esta la decides tú:

1. **Añadir el toque.** Un botón "lo intentó y no pudo" para pase y barrida. Es
   un toque más en el momento de más carga del observador, y es el que más
   probabilidad tiene de no pulsarse.
2. **Aproximar el denominador.** Contar como "intento fallado" cada vez que el
   rival recupera guardia o escapa desde una posición en la que estabas
   pasando. Cero toques, pero es una inferencia y hay que etiquetarla como tal.

Yo empezaría por **el radar de tres ejes honestos** (sumisiones, defensa,
control) y añadiría los otros dos cuando decidáis. Un radar de cinco ejes con dos
inventados es peor que uno de tres verdaderos.

## B.3 · El ganador

Orden de desempate: **sumisión** gana siempre; si no hay, **puntos estimados**;
si empatan, **dominancia**; si también, empate de verdad. Con carácter, no con un
veredicto seco:

> 🏆 **Pablo** por sumisión — mata leão a los 4:12
> 🥋 **Felipe** 11–4 en puntos, sin finalizar
> ⚖️ **Empate técnico**, 51 % – 49 % de dominio. Hay que repetirlo.
> 🐙 **Pablo** dominó, pero **Felipe** lo intentó 7 veces. Uno de los dos aprendió más.

Un aviso de producto: en un open mat entre amigos, **declarar un ganador en cada
roll puede agriar la tarde**. Lo dejaría con un interruptor por gimnasio y, con
él apagado, la tarjeta enseña los mismos datos sin coronar a nadie — "la lectura
del roll" en vez de un veredicto.

## B.4 · Y es la misma tarjeta compartible

Esta tarjeta y la "tarjeta compartible al final del roll" del backlog son la
misma cosa. Un botón de exportar como imagen, y con eso alimenta el feed, el
informe de la quedada y el grupo de WhatsApp. Una pieza, tres usos.

---

# Decisiones que necesito de ti

Ninguna bloquea el diseño, pero las cinco cambian lo que se construye:

1. **¿La guardia cuenta como disputa** o para quien la juega? (B.1)
2. **¿Toque extra para pases y barridas falladas**, aproximación, o radar de tres
   ejes? (B.2)
3. **¿Ganador siempre, o interruptor por gimnasio?** (B.3)
4. **¿Chat de verdad, o feed con reacciones?** Yo recomiendo feed. (A.2)
5. **¿Títulos negativos sí o no?** (A.4)

Y las dos de vocabulario que ya estaban abiertas: `de_rodillas` en
`bjj_posicion`, y `posicion_destino` para las transiciones.

---

# Orden que propongo para la semana

1. **Tarjeta del roll con dominancia y ganador** — sin radar todavía. Cierra el
   bloque de posesión, que estaba a medias, y es lo que se ve al terminar cada
   roll, o sea lo que más veces vais a mirar.
2. **Gimnasio + roles + recorte de la RLS.** Sin esto no hay nada social, y es lo
   que arregla la privacidad que dejamos abierta.
3. **Quedadas con inscripciones y plazas.** Llegas al domingo con el open mat
   creado.
4. **Informe de la quedada con ranking y títulos.**
5. **Feed con reacciones.**
6. **Enfoques** y la comparación con lo que hiciste de verdad.

El radar entra cuando decidas lo de los denominadores.
