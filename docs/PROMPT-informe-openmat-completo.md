# Prompt para Claude Code — el informe del Open Mat, completo

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a completar el informe del Open Mat. Lee antes `CLAUDE.md`.

## Lo primero: mañana es el Open Mat de verdad

**Esta tanda es CERO migraciones y cero cambios en el camino de registro.** Si te
encuentras tocando `sesion_del_dia`, `registrar_roll_observado`, `cerrar_quedada`
o `src/lib/bjj.ts`, **para y dímelo** — significa que has cogido otro camino y no
es el momento.

Todo lo que sigue se hace **en la pantalla**, leyendo
`private.metricas_quedada(quedada_id)`, que ya existe y ya devuelve trece
métricas por persona. No hace falta calcular nada nuevo en la base.

**La división que lo hace seguro:** los **títulos se quedan congelados** en
`quedada_informes.datos` —son un juicio hecho al cerrar y así deben quedarse— y
**la tabla del ranking pasa a calcularse en vivo** desde `metricas_quedada`. Los
informes viejos siguen enseñando sus títulos; la tabla se enriquece para todos.

## Lo que ya está bien y NO se toca

Míralo antes de cambiar nada, porque está mejor pensado de lo que parece:

- **«Cada uno se lleva exactamente uno... Nadie se queda sin título.»** Esa regla
  ya existe y funciona. Si en «Battle for Namek» solo salen dos títulos para tres
  asistentes es porque **al tercero le faltan filas** —el fallo del espejo—, no
  porque la regla falle. No la reescribas.
- El reparto por **z-score** (lo que más te separa de la media del equipo esa
  tarde). Es un buen criterio y reparte protagonismo.
- El pie que explica que son **puntos estimados, no sumisiones**. Se queda.

## 1 · Todos los participantes en la lista

Hoy la cabecera dice **«3 asistentes»** y la tabla enseña **una fila**. Eso no es
un hueco: es una contradicción, y quien la lee no sabe si el dato está mal o si
esa gente no hizo nada.

**Aparecen todos**: cualquiera con inscripción o con algún roll en ese Open Mat,
aunque vaya a cero en todo. Quien vino y le sometieron cinco veces sale igual. Es
la diferencia entre una foto de grupo y un podio.

Y de paso esto es un detector: **si alguien aparece con 0 rolls, es que su lado
del espejo no se creó.** La contradicción de arriba llevaba días avisando y
nadie la leía como aviso.

## 2 · El ranking unificado, y es lexicográfico — NO ponderado

Felipe quiere un orden que valore, en este orden:

```
sumisiones  >  puntos  >  logros  >  segundos de dominancia
```

**Ordena por el primero; si empatan, por el segundo; si empatan, por el
tercero.** Nada más.

**No hagas una suma ponderada.** Es la tentación obvia y es peor por tres
motivos: los pesos son arbitrarios y se discuten para siempre; hay que normalizar
unidades que no se parecen —los segundos van en miles y las sumisiones en
unidades—; y el número que sale **no se puede explicar**. Cuando alguien pregunte
por qué una sumisión vale doce puntos, no habrá respuesta buena. Con el orden
lexicográfico no hay pesos que discutir, y se explica en una línea al pie:

> *Primero quién finalizó más. Si empatan, quién dominó más.*

**El cuarto escalón, los segundos de dominancia, NO EXISTE todavía** — el reloj de
posesión no se ha construido. Deja el escalón escrito en el sitio, desactivado y
comentado, para que el día que exista sea añadir una línea.

**Y las columnas son la mitad del diseño.** Enseña los números que deciden el
orden, al lado de cada persona. Un ranking que se puede auditar de un vistazo no
se discute; uno que da un número mágico, sí.

Aviso para que no te sorprenda: con ocho rolls en una tarde **casi todo se decide
en los dos primeros escalones**. Es correcto, no es un fallo, y crece con los
datos.

## 3 · Por qué los logros valen aquí y no valdrían en un ranking del mes

Cinco de los veintiocho logros solo cuentan en modo observador, por la regla del
sesgo: los que se definen por la **ausencia** de algo se inflan solos no
registrando.

Dentro de un Open Mat **todo está observado**, así que todos compiten en las
mismas condiciones y usarlos como criterio es limpio.

En un ranking mensual **no lo sería**: mezclaría rolls propios con observados y
premiaría a quien registra peor. **Déjalo escrito en un comentario donde se
calcula**, porque alguien va a querer reutilizar esta función para el mes y hay
que frenarlo ahí.

## 4 · El cara a cara

Quién rodó con quién y cuántas veces. Es el dato más social que hay —*«tú y
Krilin, tres veces»*— y sale de `rolls.oponente_id` sin calcular nada nuevo.

Que se lea como una lista corta, no como una matriz. Con seis personas una matriz
de 6×6 en 390px no la lee nadie.

## 5 · Un dato del día

El número más raro de la sesión: el mayor `z` de todos. *«La sumisión más rápida
del día: 15 segundos.»* Una línea, arriba del todo, antes de los títulos.

## Lo que NO vas a hacer

**No añadas métricas nuevas.** Hay trece calculadas y la pantalla enseña dos. El
problema es de presentación, no de datos.

**No conviertas esto en un ranking del mes**, ni en una pestaña nueva. Otro
bloque, otra conversación.

**No toques `cerrar_quedada`.** Explicado arriba.

**No montes la tarjeta compartible.** Va después y sola.

## Cómo lo verificas

1. `npm run build` con typecheck estricto.
2. **Contra «Battle for Namek», que está en producción**: 3 asistentes, 8 rolls.
   Los **tres** tienen que salir en la tabla. Si alguno sale con todo a cero, eso
   es correcto y es la señal del espejo — que se vea, no que se esconda.
3. **El orden, probado con empates a propósito**: dos personas con las mismas
   sumisiones se ordenan por puntos; con los mismos puntos, por logros. Fabrica
   los tres casos.
4. **Ninguna migración.** `git diff` sobre `db/` tiene que salir vacío. Si no lo
   está, algo se ha ido de madre.
5. La batería entera sigue verde y los recorridos también.
6. **A 390px**, que es donde se va a leer: con seis personas y cuatro columnas.
   Si no cabe, quita columnas antes que encoger la letra.
7. Y en tema claro, que es el de por defecto.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios— y tacha lo que corresponda en `docs/BACKLOG.md`.
