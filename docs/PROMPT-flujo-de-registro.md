# Prompt para Claude Code — el flujo de registro y la tortuga

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a arreglar el árbol de decisión del registro en vivo (`src/lib/bjj.ts`). Hay
un fallo de simetría que sesga los datos, una posición a la que solo puede llegar
la persona equivocada, y once menús sin salida. Lee antes `CLAUDE.md`.

## 1 · La asimetría del derribo. Esto es un fallo, no una decisión.

```ts
case 'derribo':     opciones: ['cien_kilos', 'norte_sur', 'media_guardia', 'guardia_cerrada']
case 'op_derribo':  opciones: ['cien_kilos', 'montada',   'media_guardia', 'guardia_cerrada']
```

La aplicación cree que **a ti te pueden caer montado, pero tú no puedes caer
montando.** Tiene toda la pinta de un `norte_sur` y un `montada` intercambiados al
copiar el caso de al lado.

Por qué importa más de lo que parece: sesga los datos en una sola dirección. Tu
mapa defensivo puede enseñar montada tras derribo y el ofensivo no podrá nunca. Y
en modo observador es peor — el mismo hecho físico ofrece menús distintos según de
cuál de los dos lo registres, así que **el invariante del espejo, que se cumple en
la base, está roto en el menú**.

Las dos listas tienen que ofrecer lo mismo. Deja las dos así:

```ts
['cien_kilos', 'montada', 'media_guardia', 'guardia_cerrada', 'tortuga']
```

Y repasa **los trece** casos con `tipo: 'posicion'` buscando más asimetrías entre
cada par `x` / `op_x`. Si encuentras alguna, dila; puede que alguna sea
deliberada, pero por defecto no lo es.

## 2 · La tortuga, que hoy está al revés

**Hoy solo puede llegar a la tortuga el de arriba.** `tortuga` está dentro de
`DOMINANTES`, así que se ofrece en "¿A dónde pasas?" — y no aparece en ningún
destino del que se hace bola. El caso más común del jiu-jitsu real, que es
"me derriban y me hago bola" o "escapo y me hago bola", **hoy no se puede
registrar**.

Tres cambios:

- **Fuera de `DOMINANTES`.** "Pasar a tortuga" no es una acción que haga nadie: el
  otro se hace bola. Comprueba qué más usa esa constante antes de tocarla.
- **Dentro de los destinos de `derribo`, `op_derribo`, `escape` y `op_escape`.**
  Los escapes hoy ofrecen `[...GUARDIAS_RAPIDAS, 'de_pie']`; pasan a ofrecer
  `[...GUARDIAS_RAPIDAS, 'tortuga', 'de_pie']`.
- **En la base, `posiciones.categoria` de `tortuga` pasa de `dominante` a
  `transicion`**, al lado de `scramble`. Es un `update` de una fila, en su propia
  migración con la siguiente etiqueta libre según tu inventario.

### Lo que NO vas a hacer, aunque te lo pida el cuerpo

**No crees una posición "tortuga arriba".** Ya existe: es `tortuga` + `rol =
arriba`. Para eso el modelo separa posición y rol — igual que no hay "guardia
cerrada arriba" y "guardia cerrada abajo" como posiciones distintas.

Y hay un motivo duro: **el espejo del modo observador invierte solo `actor`**. Si
la posición codificara quién está encima, espejar tendría que reescribir también
`posicion`, y ese invariante es el que sostiene que los heatmaps de los dos
jugadores cuadren. No lo toques.

En el menú, la ficha dice **"Tortuga"** a secas. La pregunta ya establece de quién
se habla.

### El efecto secundario que hay que medir, no suponer

`HOUDINI` cuenta escapes desde posiciones de categoría `dominante`. Al salir
tortuga de esa categoría, **los escapes desde tortuga dejan de contar**, y hoy sí
se pueden registrar. O sea que las cuentas existentes van a cambiar.

Así que, **antes de tocar nada**: saca sobre la base local con datos de demo
cuántos `HOUDINI` hay hoy y desde qué posiciones salen. Vuelve a sacarlo después.
Enséñame las dos cifras. Si la caída es grande, es información sobre el logro, no
un fallo del cambio — pero quiero verla, no deducirla.

Y comprueba que la categoría de `tortuga` **no** entra en el cálculo de puntos: el
comentario de `db/07_transicion_y_puntos.sql` dice que tortuga y scramble no
puntúan, y eso tiene que seguir igual después del cambio.

## 3 · Once menús sin puerta de salida

El tipo ya tiene la puerta:

```ts
| { tipo: 'posicion'; titulo: string; opciones: Posicion[]; mas?: boolean; ... }
```

Y está usada en **2 de las 13** preguntas de posición. Las otras once son listas
cerradas: si lo que pasó no está en las cuatro fichas, no hay forma de
registrarlo.

**Pon `mas: true` en las trece.** El atajo de cuatro fichas está bien y es lo que
hace que registrar en vivo sea rápido — no lo alargues. Lo que falta no es más
opciones, es **una puerta**: cuatro fichas y un "otra…" que abra el listado
completo.

Sin esa puerta, quien registra elige la opción errónea más cercana, y **un heatmap
equivocado se ve exactamente igual que uno correcto**. Es peor que no registrar,
porque no deja rastro de que se ha mentido.

Que el "otra…" sea claramente secundario: las cuatro fichas primero y grandes, la
puerta discreta al final. Y que el listado completo salga **agrupado por
categoría**, no en un chorro de veinticuatro.

## 4 · Deja escrito lo que hoy solo está implícito

Mirando el código se deduce que **la `posicion` de un evento es siempre el
origen**: `ev('yo','escape', e.pos, 'abajo')` sella la posición actual, y el
destino lo fija `siguiente`. Igual en el derribo, que se sella `de_pie` y luego
pregunta dónde cae.

Está bien y no se cambia. Pero **no está escrito en ningún sitio**, y el predicado
de `HOUDINI` depende de ello: "escapes desde posiciones dominantes" solo tiene
sentido si `posicion` es de donde saliste. Con un solo campo por evento, esa
ambigüedad es una bomba de relojería para cualquiera que escriba un predicado
nuevo.

- Comentario en la columna `eventos.posicion`: *la posición donde estaba el actor
  al ejecutar la acción, es decir el ORIGEN. El destino, cuando lo hay, es el
  evento siguiente.*
- Lo mismo en `CLAUDE.md`, en convenciones.
- Y **una prueba** que lo fije: un escape desde montada registra
  `posicion = montada`, no la posición de destino. Si algún día alguien invierte
  esto, que se entere por un test en rojo y no por un ranking raro.

## Cómo lo verificas

1. `npm run build` pasa con typecheck estricto.
2. **La simetría, probada**: un test que recorra los trece pares `x` / `op_x` y
   compruebe que las listas de opciones coinciden. Es la prueba que habría
   evitado el fallo del derribo, y evita el siguiente.
3. **Los cuatro caminos de la tortuga a mano**: me derriban y me hago bola; derribo
   y se hace bola; escapo a tortuga; escapa a tortuga. Los cuatro tienen que
   guardar `posicion = tortuga` con el `rol` correcto en cada lado.
4. **El espejo sigue cuadrando** después de todo esto: un roll observado con
   tortuga dentro, espejado, tiene que dar los mismos heatmaps invertidos. Cero
   discrepancias.
5. Las dos cifras de `HOUDINI`, antes y después.
6. `db/pruebas/rls.sql` y `db/pruebas/puntos.sql` siguen verdes, y las migraciones
   aplican desde cero.
7. Probado **a 390px**: las cinco fichas del derribo más el "otra…" tienen que
   caber sin desbordar. Si no caben, la puerta va en su propia fila — pero no
   quites fichas.
8. La migración, **primero contra el Postgres local**.

## Fuera de alcance

**El `front headlock` como posición propia.** Atacar la tortuga desde delante es
una posición distinta de verdad y algún día merecerá su sitio, pero eso es una
propuesta, no parte de este arreglo.

**El reloj de dominancia.** Este cambio lo prepara —tortuga pasa a ser disputa en
vez de dominio ajeno— pero el reloj es su propio bloque.

**Tocar el espejo, `rol`, o el cálculo de puntos.** Nada de esto lo necesita, y si
crees que sí, para y dilo antes.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios— y tacha lo que corresponda en `docs/BACKLOG.md`.
