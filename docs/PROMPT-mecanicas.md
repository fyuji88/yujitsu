# Prompt para Claude Code — mecánicas y variantes

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a montar las **mecánicas**: una tarikoplata pasa a ser una variante
de la kimura, un J-Lock una variante de la americana, y el catálogo deja de ser
una lista plana de 63 nombres sin relación entre sí. Lee antes `CLAUDE.md`.

## El problema que resuelve, porque explica todas las decisiones

Cuando Felipe elige sus objetivos de la semana piensa en técnicas **concretas**
—"esta semana, tarikoplata"—. Cuando alguien registra un roll en vivo, con el
cronómetro corriendo y el móvil en la mano, piensa en técnicas **genéricas**:
apunta "kimura" porque es lo que se llama en un segundo.

Hoy esos dos mundos no se hablan. Un objetivo de tarikoplata nunca se cumple
porque nadie registra "tarikoplata" en vivo, y una colección de 14 kimuras no
dice si son la kimura de siempre o el juguete nuevo.

De ahí salen las tres piezas: **una jerarquía** para que kimura y tarikoplata sean
lo mismo cuando conviene y cosas distintas cuando conviene, **un paso de
precisar** después del roll para bajar de una a otra sin frenar el registro en
vivo, y **el análisis plegado por mecánica** para que el desglose sea una decisión
de quien mira, no del que registró.

## La regla que impide que el catálogo explote

Léela dos veces, porque es la que vas a tener que aplicar tú con criterio:

> **Una variante es la MISMA articulación y la MISMA dirección, aplicada con OTRA
> cosa o con OTRO agarre. La posición de entrada NUNCA crea una variante.**

Una kimura desde side control y una kimura desde la guardia **no son dos
técnicas**: son la misma técnica y la posición ya está en el evento, en su
columna. Si empiezas a crear variantes por posición, el catálogo pasa de 63 filas
a cuatrocientas, cada una con dos datos, y el análisis se vuelve inútil por
dispersión.

Una tarikoplata **sí** es una variante: misma articulación (hombro), misma
dirección (rotación externa), aplicada **con la pierna** en vez de con el brazo.

**Cuando dudes, no emparentes.** Una técnica sin madre es una mecánica de una sola,
y no cuesta nada. Una madre equivocada corrompe en silencio todos los recuentos
agregados y nadie se entera nunca.

## Fase 1 · Esquema

Migración **`bjj_NN_mecanicas`** — usa la siguiente etiqueta libre según tu
inventario, no la que yo te diga. Va **detrás de la del vocabulario**, que
renombra los nombres ambiguos del esquema (entre ellos `grupos` a `equipos`); si esa no está aplicada, para y
hazla primero — este bloque está escrito contra el vocabulario ya limpio.

Y una regla que sale de ahí y que aplica aquí: **una palabra, un concepto en todo
el esquema.** `mecanica` se llama así y no `familia` precisamente porque
`logros.familia` ya existe y significa otra cosa. No introduzcas un nombre de
columna que ya esté usado en otra tabla con otro significado.

### Un solo nivel, y garantizado por la base

Madre y variante. **No hay nietos.** Y no lo dejes en un comentario: se puede
imponer de forma declarativa, sin trigger, con este truco. **Lo he probado contra
Postgres y funciona** — las dos violaciones de abajo saltan de verdad:

```sql
create type bjj_control as enum ('brazo','pierna','cuerpo');

alter table tecnicas
  add column variante_de    uuid,
  add column control     bjj_control,
  add column nivel       smallint  not null
               generated always as (case when variante_de is null then 0 else 1 end) stored,
  add column nivel_referido smallint  generated always as (0) stored,
  add column mecanica_id  uuid      generated always as (coalesce(variante_de, id)) stored;

alter table tecnicas add constraint tecnicas_id_nivel_uk unique (id, nivel);
alter table tecnicas add constraint tecnicas_variante_fk
  foreign key (variante_de, nivel_referido) references tecnicas (id, nivel);

create index tecnicas_mecanica_idx on tecnicas (mecanica_id);
```

Qué compra cada pieza:

- `mecanica_id` generada como `coalesce(variante_de, id)` significa que **toda técnica
  tiene mecánica, también las que no tienen madre** (son su propia mecánica). Todos
  los agregados se escriben `group by mecanica_id` sin un solo `case`, sin CTE
  recursiva y con índice.
- El FK compuesto contra `(id, nivel)` con `nivel_referido` constante a 0 hace que
  **una madre con `nivel = 1` no exista**, así que no puedes colgar una variante de
  una variante. Verificado: el insert del nieto falla con violación de FK.
- Y protege el otro lado: **degradar una madre que ya tiene variantes también falla**,
  porque su `nivel` pasaría a 1 y las variantes apuntan a `(id, 0)`. Verificado.

`control` **es nullable a propósito**: dice con qué se aplica la presión final, y
no siempre está claro. Nulo significa "no clasificada", no "brazo".

Ojo con lo que `control` **no** es: `objetivo_default` ya dice **qué** atacas. Un
straight ankle lock ataca el tobillo (`objetivo`) y se aplica con el antebrazo
(`control`). Las dos columnas son ortogonales y por eso las dos sirven.

### Migración de lo que ya hay

Las 63 técnicas actuales pasan a `nivel = 0`, cada una su propia mecánica, y
**ningún evento existente cambia de significado**. La migración es de riesgo cero
por construcción; compruébalo igualmente contando eventos por mecánica antes y
después.

**No añadas `mecanica_id` a `eventos`.** Se llega por join a `tecnicas`. Una copia
desnormalizada se queda vieja en cuanto alguien precisa un evento, y ese es
justo el caso de uso.

### El `control` de las 28 sumisiones

El criterio, por si tienes que razonar alguna: **el valor es lo que aplica la
presión en el momento del golpe, no lo que la prepara.** En un triángulo las manos
colocan la pierna, pero lo que cierra es el triángulo → `pierna`. En un armbar las
manos sujetan la muñeca, pero lo que extiende es la cadera → `cuerpo`.

Rellénalo tal cual. Esto no lo decides tú y no hace falta que lo investigues:

- **brazo** — `americana`, `americana_recta`, `anaconda`, `baratoplata`,
  `baseball_bat`, `bow_and_arrow`, `cruzada`, `darce`, `ezekiel`, `guillotina`,
  `heel_hook`, `katagatame`, `kimura`, `lapela`, `mata_leao`, `muneca`,
  `north_south_choke`, `straight_ankle`, `toe_hold`
- **pierna** — `banana_split`, `biceps_slicer`, `omoplata`,
  `pantorrilla_slicer`, `triangulo`
- **cuerpo** — `armbar`, `armbar_triangulo`, `kneebar`, `twister`

Las que no son sumisión (pases, barridas, derribos, escapes, tomas de espalda) se
quedan con `control` nulo. No te inventes valores para ellas.

**Tres cosas que tienes que saber de esta lista:**

**El bloque de llaves de pierna cambió y no es un descuido.** `heel_hook` está en
`brazo` y `kneebar` en `cuerpo`, que no es lo que dice el instinto. En las cuatro
llaves de pierna las piernas **atrapan** pero no rematan: el talón lo gira el
brazo, igual que en el straight ankle lock, y el kneebar lo remata la extensión de
cadera. Con el criterio de arriba salen así. Si sale al revés, es un `update`.

**`control` es un dato, no un esquema.** Todos estos valores están en revisión con
el equipo de Felipe ahora mismo. Corregir cualquiera de ellos después es una
sentencia `update` sobre el catálogo, no una migración — así que **escribe la
asignación en un bloque propio y claramente marcado** dentro de la migración, para
que la corrección sea un diff pequeño. Déjalo dicho en `docs/CAMBIOS.md`: los
valores de `control` son provisionales hasta la revisión.

**Lo único caro de cambiar es el enum.** Hay una pregunta abierta sobre si hace
falta un cuarto valor `ropa` para las estrangulaciones de solapa —hoy son `brazo`,
porque la tela es la herramienta pero la aprietan los brazos, y `solo_gi` ya marca
cuáles son de gi—. **No lo añadas.** Si de la revisión sale que sí, entra en su
propia migración.

### Las variantes que se siembran, y solo estas

**Siete** altas y **una reparentación**:

| slug | madre | control | objetivo | alias |
|---|---|---|---|---|
| `tarikoplata` | `kimura` | pierna | hombro | `leg kimura`, `kimura con la pierna` |
| `j_lock` | `americana` | pierna | hombro | `j lock`, `kesa americana`, `americana desde kesa`, `leg americana` |
| `heel_hook_interno` | `heel_hook` | brazo | rodilla | `inside heel hook`, `IHH` |
| `heel_hook_externo` | `heel_hook` | brazo | rodilla | `outside heel hook`, `OHH` |
| `guillotina_brazo_dentro` | `guillotina` | brazo | cuello | `arm-in guillotine`, `guillotina con brazo dentro` |
| `guillotina_codo_alto` | `guillotina` | brazo | cuello | `high elbow guillotine`, `marcelotine` |
| `triangulo_invertido` | `triangulo` | pierna | cuello | `reverse triangle` |

Y **`armbar_triangulo`, que ya existe como fila suelta, pasa a ser variante de
`armbar`** (`update`, no `insert` — la fila y su id se conservan, y con ellos los
eventos que ya la apuntan).

Tres avisos honestos sobre esa lista, para que no la mejores por tu cuenta:

- **`kimura_de_reloj` estaba en esta lista y la he quitado.** "Desde el reloj" es
  una posición de entrada, no una mecánica distinta, y la regla de arriba dice que
  la posición nunca crea una variante. Si me la salto yo el primer día, la regla no
  vale nada. **No la añadas.**
- `armbar_triangulo` tiene la misma pega —"desde triángulo" también suena a
  posición— y aun así **se emparenta**. La diferencia es que esa fila **ya existe**:
  no estamos creando una que rompe la regla, estamos dándole a una fila huérfana la
  mejor madre disponible, y sumarla bajo `armbar` es más correcto que dejarla de
  hermana. Anótalo en `docs/CAMBIOS.md` como decisión discutible. La regla completa
  es: **no crees filas que rompan la regla; a las que ya existen, dales la mejor
  madre que haya.**
- **`baratoplata` se queda suelta, sin madre.** Su parentesco es discutido —según
  a quién preguntes es prima de la kimura o de la omoplata— y la regla dice que
  ante la duda no se emparenta.

### Dos altas de catálogo, que NO son variantes

Aparte de lo anterior, faltan dos sumisiones en el catálogo. **Son técnicas base,
`nivel = 0`, sin madre** — no tienen nada que ver con la jerarquía, se cuelan aquí
porque esta migración ya está tocando `tecnicas` y no merece la pena una migración
propia para dos filas.

| slug | nombre | tipo | objetivo | control | solo_gi | alias |
|---|---|---|---|---|---|---|
| `clock_choke` | Estrangulación del reloj | sumision | cuello | brazo | **sí** | `clock choke`, `reloj`, `relogio` |
| `gravata_peruana` | Gravata peruana | sumision | cuello | brazo | no | `peruvian necktie`, `corbata peruana` |

Las dos viven en la **tortuga**, que es la posición donde más pasa y de la que hoy
no se puede registrar casi nada. `tortuga` ya existe en `bjj_posicion` y en la
tabla `posiciones` — **no la toques**, no hay que añadirla.

Y para que quede claro por qué estas dos y no más: el **crucifijo** también vive
ahí y **no se añade**, porque es una *posición*, no una sumisión — desde el
crucifijo se hacen ataques que ya están en el catálogo. Meterlo en `tecnicas`
sería el mismo error que la regla de arriba prohíbe.

**No añadas ninguna variante más.** Si al implementarlo se te ocurren tres
obvias, no las metas: van por el circuito de propuestas, que es el bloque
siguiente. Un catálogo compartido que crece por buenas ideas sueltas no se
vuelve a limpiar nunca.

Los nombres visibles de las variantes van al fichero de textos, como los logros,
no incrustados.

## Fase 2 · Precisar

El paso que conecta el registro rápido con el objetivo concreto.

### La RPC, y por qué es una RPC

Precisar tiene que poder hacerlo **tanto el protagonista del roll como quien lo
registró** — decisión de Felipe. En modo observador eso significa que alguien
edita un evento que escribió otro, y eso hoy no lo permite la RLS.

**No abras `update` sobre `eventos` para arreglarlo.** Postgres no tiene RLS por
columna, así que una política que deje cambiar `tecnica_id` deja cambiar también
`tipo`, `posicion` y `completado` — es decir, deja reescribir el marcador de otro.
Es exactamente el fallo que el caso 9 de `db/pruebas/rls.sql` existe para cazar.

Va como **RPC `SECURITY DEFINER`**, con el patrón que ya usan
`registrar_roll_observado` y `unirse_con_codigo`:

```
precisar_tecnica(p_evento_id uuid, p_tecnica_id uuid) returns void
```

Y comprueba, en este orden, fallando con mensaje claro:

1. Que quien llama es **el practicante del roll o quien lo registró**. Nadie más.
2. Que la técnica nueva **es de la misma mecánica** que la actual:
   `nueva.mecanica_id = actual.mecanica_id`. Esto es el invariante, y va en la base,
   no en la pantalla.
3. Que el evento tiene técnica. Un evento sin `tecnica_id` no se precisa: se
   corrige, que es otra cosa.

`revoke execute ... from anon, public` y `grant execute to authenticated`, como
las demás.

### Quién tocó qué

Como precisan dos personas, hace falta saber quién:

```sql
alter table eventos
  add column tecnica_precisada_por uuid references practicantes(id),
  add column tecnica_precisada_en  timestamptz;
```

Las escribe la RPC, nadie más. Y **se enseñan** en la ficha del roll —"precisado
por Pablo"—. Sin esto, dos personas editando el mismo evento acaba en una
discusión que nadie puede resolver; con esto es un dato.

### La pantalla

- **Dónde**: al cerrar el roll, y **también después** desde el historial. La mitad
  de las veces te das cuenta de camino a casa, no en el tatami.
- **Qué se ofrece**: solo la madre ("sigue siendo Kimura") y **sus variantes**.
  Nada más. Son tres o cuatro opciones, caben en un toque.
- **Orden**: primero las variantes que están en tu **enfoque activo**, luego las
  que más usas, luego el resto. Si esta semana tu objetivo es la tarikoplata,
  tiene que ser la primera opción que ves al precisar una kimura.
- **En lote**: si la sesión tuvo tres kimuras, se ofrecen juntas, no una por
  pantalla.
- **Nunca bloquea.** No es un modal, no es obligatorio, y un roll sin precisar es
  un roll perfectamente válido. En cuanto precisar sea un peaje, la gente deja de
  registrar — y eso es el único riesgo que mata este producto.
- Solo aparece el chip si la técnica **tiene variantes**. Para las 55 que no
  tienen, no existe.

**Precisar baja, nunca sube ni cruza.** Cambiar una kimura por un triángulo es
**corregir**, es otro botón, y no entra en esta tanda.

## Fase 3 · El análisis, plegado por mecánica

Aquí es donde esto deja de ser fontanería y se ve.

- Los agregados de técnica pasan a **`mecanica_id`** por defecto: catorce kimuras
  son catorce kimuras, las precises o no. Nadie pierde nada por precisar, que es
  la condición para que alguien lo haga.
- Y **se despliega**: tocando la mecánica salen las variantes con sus propios
  números.
- Añade `v_tecnicas_practicante(practicante_id, mecanica_id, tecnica_id, intentos, completados)`
  con `security_invoker = on` como todas. La pantalla pliega desde ahí; no montes
  dos vistas para lo mismo.
- **La frase que justifica el bloque entero**, y quiero verla en pantalla cuando
  los números dan para ella: *"tu tarikoplata entra el 44%, tu kimura clásica el
  20%"*. Con una guarda de volumen —mínimo 5 intentos de cada— porque 1 de 1 no es
  el 100%.
- No rompas `v_heatmap_ofensivo` ni las vistas que ya hay. Añade, no sustituyas.

## Fase 4 · Los enfoques

`enfoques.tecnicas` es un `uuid[]` y ya está. La regla de coincidencia es
asimétrica **a propósito**:

- Un enfoque que apunta a la **madre** cuenta la madre **y todas sus variantes**.
  Objetivo "kimura" → las tarikoplatas suman.
- Un enfoque que apunta a una **variante** cuenta **solo esa**. Objetivo
  "tarikoplata" → una kimura normal no suma.

En SQL es una línea:
`e.tecnica_id = any(enf.tecnicas) or t.variante_de = any(enf.tecnicas)`

**Y dilo en la pantalla.** Un enfoque en Kimura enseña "incluye tarikoplata,
kimura de reloj". Si el usuario no ve por qué el contador subió, el contador no
vale nada.

## Los logros, que se ven afectados

Dos, y en direcciones opuestas. Esto no es un detalle: es la prueba de que los dos
niveles se ganan el sueldo.

- **`juguete_nuevo`** ("finalizas con una técnica que nunca habías usado") pasa a
  contar por **`tecnica_id` exacta**. Tu primera tarikoplata es un juguete nuevo
  aunque lleves cien kimuras. Es literalmente lo que la gente celebra.
- **`artista`** ("tres sumisiones distintas en la misma quedada") pasa a contar
  por **`mecanica_id`**. Kimura + tarikoplata + americana son **dos** mecánicas, no
  tres, y contarlas como tres regala el logro.

Consecuencia de la primera, y va en "sabido roto" no como fallo sino como aviso:
**precisar puede conceder un `juguete_nuevo` retroactivo.** Es correcto —lo
ganaste, solo que el dato llegó tarde—, pero si aparece en el feed días después
hay que saber por qué.

## Cómo lo verificas

1. `npm run build` pasa, typecheck estricto incluido.
2. **La migración aplica desde cero**, que es lo que hace el CI: bootstrap + todas
   las migraciones en orden alfabético. Comprueba que esta migración no depende de nada
   que se aplique después que ella.
3. **Los dos guardias de un solo nivel, probados de verdad**: un insert de nieto
   falla, y un update que le pone madre a una madre que ya tiene variantes falla. Si estos dos
   pasan, la jerarquía no puede degenerar nunca.
4. **Recuento antes y después.** Eventos agrupados por mecánica después de la
   migración = eventos agrupados por técnica antes. Si no cuadra, algo se
   emparentó mal.
5. **La RPC, los cuatro casos**: el protagonista precisa (ok), quien registró
   precisa (ok), un tercero del mismo equipo (falla), y precisar a otra mecánica
   (falla). Añádelos a `db/pruebas/rls.sql`, que hoy son 55 y pasan todos.
6. **`anon` no puede ejecutar `precisar_tecnica`.** Míralo en
   `information_schema.routine_privileges`, no de memoria.
7. **Con los datos de demo que hay** (Goku tiene 138 rolls): precisa un par de
   kimuras a tarikoplata y comprueba que el total de la mecánica **no se mueve** y
   que el desglose sí. Ese es el invariante entero en una prueba.
8. **El enfoque asimétrico, probado**: enfoque en kimura cuenta la tarikoplata;
   enfoque en tarikoplata no cuenta la kimura.
9. Probado a 390px, en tema claro (el de por defecto) y oscuro.
10. Migración **primero contra el Postgres local** (`db/README.md`). Producción
    tiene datos reales.

## Fuera de alcance

**Las técnicas propuestas por usuarios.** Va en su propio bloque, con su prompt.
Aquí el catálogo solo lo toca la migración.

**Corregir** una técnica por otra de distinta mecánica. Es otro botón y otra
conversación.

**Los arquetipos.** `control` les va a servir de entrada —quien finaliza con las
piernas tiene una firma de estilo— pero no los montes aquí.

**Traducir el catálogo.** Los nombres visibles van al fichero de textos y ahí se
quedan.

## Una cosa que no decides tú

Si al sembrar las variantes ves que **una de las ocho no encaja con los datos que
hay** —por ejemplo que `objetivo_default` de la madre contradice el de la
variante—, no la reinterpretes ni la ajustes: déjala fuera, dilo, y propón la
alternativa. Una técnica mal emparentada es peor que una que falta, porque
contamina todos los recuentos agregados sin dar ninguna señal.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios— y tacha lo que corresponda en `docs/BACKLOG.md`.
