# Prompt para Claude Code — vocabulario del esquema

**Este bloque va ANTES de `PROMPT-mecanicas.md`.**

Esta versión **incorpora el inventario que hizo Claude Code** antes de tocar nada:
corrigió la numeración de la migración, encontró un cuarto significado de `grupo`
que a mí se me había escapado, y avisó de que hay quince funciones que no se
renombran solas. Todo eso está ya dentro.

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a renombrar los nombres del esquema que significan más de una cosa, y a montar
una comprobación en CI para que no vuelva a pasar. **No cambias ni una regla de
negocio, ni una política, ni un cálculo.** Es un renombrado y nada más. Lee antes
`CLAUDE.md`.

## La regla

> **Una palabra, un concepto, en todo el esquema.** Si dos columnas no pueden
> compartir el mismo tipo, no pueden compartir el mismo nombre. Y el nombre tiene
> que decir qué es **sin la tabla como contexto**: `rol` no vale, `rol_en_equipo`
> sí.

En una base donde toda la seguridad son políticas de RLS y todo el análisis son
vistas, un nombre ambiguo se convierte en una consulta correcta que devuelve lo
que no es — y eso no da error, da un número.

Y la regla hermana, que decide qué entra aquí y qué no:

> **El identificador de la base y la palabra que lee el usuario son decisiones
> distintas.** La palabra de pantalla vive en el fichero de textos y cambiarla es
> una línea. El identificador cuesta una migración, las vistas, el cliente y
> coordinar la cola. Se renombra el identificador **solo cuando es ambiguo para
> quien programa**, no cuando simplemente nos gusta más otra palabra.

## La numeración: úsala tú, no me hagas caso a mí

**No hardcodeo el número.** Usa la siguiente etiqueta libre según tu propio
inventario. Y de paso, hay un desorden que conviene dejar anotado: `18_ambito_dia`
y `19_logros_flawless_y_doble_sesion` **reclaman los dos `bjj_23`**, y no hay
ningún fichero que reclame `bjj_24`.

**No renumeres el histórico** — lo aplicado, aplicado está. Solo dilo en
`docs/CAMBIOS.md`, y añade a la comprobación de CI (más abajo) que cada fichero
`db/NN_*.sql` declare **una sola** etiqueta y que no haya dos ficheros con la
misma.

## 1 · `grupo` significa cuatro cosas. Esta es la gorda.

1. **el equipo/gimnasio** — la tabla `grupos` y tres columnas `grupo_id`
2. **la categoría de posición** — `posiciones.grupo`: neutral, guardia,
   dominante, transicion
3. **el par de rolls espejados** — `rolls.roll_grupo_id`, la clave de idempotencia
   del modo observador, que no tiene nada que ver con gimnasios
4. **el nombre del gimnasio** — la columna `grupo` que devuelven `feed()` y
   `quedada_por_token()`, que no es un id sino un texto

Cuatro conceptos, una palabra. Lo que se renombra:

| Ahora | Pasa a ser |
|---|---|
| tabla `grupos` | **`equipos`** |
| tabla `miembros_grupo` | **`miembros_equipo`** |
| `grupo_id` en `miembros_equipo`, `quedadas`, `sesiones` | **`equipo_id`** |
| `miembros_grupo.rol` (admin/miembro) | **`rol_en_equipo`** |
| tipo `bjj_rol_grupo` | **`bjj_rol_equipo`** |
| `rolls.roll_grupo_id` | **`par_id`** |
| `posiciones.grupo` | **`categoria`** |
| tipo `bjj_grupo_posicion` | **`bjj_categoria_posicion`** |
| columna `grupo` devuelta por `feed()` y `quedada_por_token()` | **`equipo_nombre`** |
| `private.mis_grupos()` · `private.comparte_grupo()` · `public.crear_grupo()` | **`mis_equipos`** · **`comparte_equipo`** · **`crear_equipo`** |

Y las vistas que exponen `grupo_id` —`v_feed`, `v_feed_crudo`, `v_logros_mes`,
`v_mi_quedada_hoy`— pasan a `equipo_id`; las que exponen `posicion_grupo`
—`v_eventos`, `v_fuertes_debiles`— a `posicion_categoria`; las que exponen
`roll_grupo_id` —`v_puntos_roll`, `v_rolls_unicos`— a `par_id`.

**En la interfaz se llama "Team"**, desde el fichero de textos. En la base va en
español —`equipos`— porque el esquema entero está en español salvo `rolls`. Si
mañana Felipe quiere "Squad", es una línea de textos y cero migraciones.

`par_id` merece un comentario en la columna: *el identificador que comparten los
dos rolls espejo de un mismo combate registrado por un observador*. Es el nombre
peor entendido del esquema y ya que se toca, se documenta.

### Los parámetros de función NO se tocan. Ninguno.

Esto incluye `p_grupo` en `private.es_admin()` y `p_grupo` en
`registrar_roll_observado()` — que además significan cosas distintas entre sí, con
lo cual duele dejarlo. Se deja igual, por tres razones y las tres pesan:

- **`es_admin(p_grupo)` está clavado por seis políticas.** Postgres no deja
  renombrar un parámetro con `create or replace`; habría que tirar la función y
  recrear esas seis políticas de RLS. Eso es la operación más peligrosa que existe
  en esta aplicación, y no se hace en una tanda cosmética.
- **`p_grupo` de `registrar_roll_observado` es lo que serializa la cola de
  salida.** Renombrarlo rompe los elementos que alguien tenga pendientes en
  IndexedDB.
- Un nombre de parámetro es el identificador **menos visible** que hay. El coste
  es alto y el beneficio casi nulo.

Van los dos al backlog, para hacerlos el día que haya que cambiar el formato de la
cola de todas formas. Y `p_grupo` va a las **excepciones** de la comprobación de
nombres prohibidos, con el motivo escrito al lado.

## 2 · `rolls.orden` → `orden_en_sesion`

Este no es hipotético, **ya costó un logro**. En `docs/CAMBIOS.md` está escrito:
`EL ÚLTIMO EN IRSE` se definió como "el roll con el mayor orden de la quedada", y
resulta que `rolls.orden` es el orden dentro de la sesión **de cada uno** — cada
persona numera los suyos del 1 al n. No premiaba irse el último, premiaba haber
rodado más, y hubo que sacarlo del catálogo.

La columna no mentía: no decía **de quién** era la secuencia, y quien la leyó
rellenó el hueco con lo que le pareció razonable.

De paso, `inscripciones.orden` → **`orden_en_lista`**.

## 3 · `sesiones.tipo` → `formato`

`tipo` significa tres cosas en la superficie que lee el cliente: en `eventos` y
`tecnicas` es la clase de acción y ahí las dos comparten el mismo enum, que está
**bien**; en `sesiones` es la clase de entrenamiento; y en `v_feed` es la clase de
elemento del feed.

`sesiones.tipo` → **`formato`**. `v_feed.tipo` → **`tipo_de_elemento`**.
`eventos.tipo` y `tecnicas.tipo` **no se tocan**.

## Las vistas: `alter view`, y NUNCA recrearlas

Al renombrar una columna de tabla, **la vista sigue publicando el nombre viejo**.
Funciona, pero el cliente recibe `grupo_id` donde espera `equipo_id`, y ni el SQL
ni el CI se quejan.

`create or replace view` **no sirve**: falla con `cannot change name of view
column`. Lo que sirve es:

```sql
alter view v_feed rename column grupo_id to equipo_id;
```

Probado: renombra la columna publicada y **conserva `security_invoker = on`** y
los permisos.

**Y por eso no se recrean.** Recrear es borrar y volver a crear, y ahí se pierde
`security_invoker`. Hoy **las 18 vistas de `public` lo tienen, las 18**. Una vista
sin ese ajuste corre con los permisos de su dueño en vez de los de quien
consulta: **cualquiera lee los datos de otro equipo**. Un renombrado cosmético no
puede ser la vía por la que se abre un agujero de RLS.

## Las funciones: quince, y aquí sí hay bisturí

Los cuerpos de las funciones son **texto**, así que no siguen a los renombrados.
Hay unas quince que hay que rehacer, y cuatro que necesitan `drop` + `create`
porque les cambia el tipo de retorno.

**La regla dura, y no tiene excepciones: no se borra ninguna política de RLS.**

Si una función no se puede recrear sin tirar una política que depende de ella,
**esa función no se renombra en esta tanda**. La anotas, sigues, y va al backlog.
Prefiero un nombre feo superviviente a un `drop policy` en una tanda de
renombrados: las políticas son todo el perímetro, y recrearlas "igual que estaban"
es exactamente el momento en que una se queda un poco distinta.

Para las que sí se rehacen: cuerpo actualizado, y que `security definer`, el
`search_path`, y los `revoke`/`grant` queden **idénticos** a como estaban. Compara
`information_schema.routine_privileges` antes y después y enséñame la diferencia,
que tiene que ser vacía.

## La cola de salida

Buena noticia: como **no** tocamos los parámetros de función, lo que la cola
serializa para el modo observador se queda igual y no hay riesgo por ahí.

Lo que sí hay que mirar: **qué nombres de columna serializa la cola para los
`upsert` directos** a `sesiones`, `rolls` y `eventos` — mira `src/lib/db.ts` y
`src/lib/sync.ts`. Si alguno de los renombrados aparece ahí (`orden` es el
sospechoso), dilo **antes** de tocar nada, porque entonces sí hay que coordinar el
despliegue: que los cuatro usuarios sincronicen y la píldora diga "al día", y
después migración y cliente **juntos**. En local da igual.

## La comprobación, para que esto no dependa de que alguien se acuerde

`scripts/comprobar-vocabulario.py`, al lado de `scripts/comparar-logros.py`, y
**en el CI detrás del paso de migraciones**. Cuatro cosas:

**1 · Divergencia de tipo.** Falla si un nombre de columna aparece en más de una
tabla base con más de un tipo:

```sql
select c.column_name, count(distinct c.udt_name), string_agg(distinct c.table_name, ', ')
from information_schema.columns c
join information_schema.tables t
  on t.table_schema = c.table_schema and t.table_name = c.table_name
 and t.table_type = 'BASE TABLE'
where c.table_schema = 'public'
group by c.column_name having count(distinct c.udt_name) > 1;
```

Hoy devuelve exactamente `estado`, `rol` y `tipo`. **Al terminar tiene que
devolver solo `estado`**, que va a las excepciones con su motivo: no es una
palabra para dos conceptos, es el mismo concepto —el estado del ciclo de vida de
la fila— con un enum acotado por tabla.

**2 · Nombres prohibidos.** Ninguno de estos puede sobrevivir en `public` — ni en
tablas, ni en **vistas**, ni en columnas, ni en funciones, ni en tipos:

```
grupos · miembros_grupo · grupo_id · roll_grupo_id · posicion_grupo
bjj_rol_grupo · bjj_grupo_posicion · sesiones.tipo · rolls.orden · inscripciones.orden
```

Excepciones, con motivo escrito: los parámetros `p_grupo`. Esta comprobación es la
que convierte *"¿me acordé de todas las vistas?"* en algo que responde la máquina.

**3 · Todas las vistas con `security_invoker`.** Cero filas o falla:

```sql
select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'v' and n.nspname = 'public'
  and coalesce(c.reloptions::text, '') not like '%security_invoker=on%';
```

**Ojo con la trampa**: Postgres lo guarda como `security_invoker=on`, **no** como
`=true`. Una comprobación escrita contra `=true` devuelve cero filas siempre y da
verde sin haber mirado nada. Ese error ya se cometió una vez aquí; déjalo escrito
en el script.

**4 · Etiquetas de migración.** Cada `db/NN_*.sql` declara una sola etiqueta
`bjj_NN`, y no hay dos ficheros con la misma. Hoy falla —`18` y `19` reclaman los
dos `bjj_23`— así que arranca esta comprobación **avisando** y no fallando, con
el desorden actual en la lista de excepciones, y que falle de aquí en adelante.

Y di en el script lo que **no** ve: la comprobación 1 solo caza divergencia de
tipo; dos columnas `text` con significados distintos se le escapan. De esa mitad
se encarga la regla escrita. Un comprobador que se vende como completo es peor
que ninguno.

## Lo que NO se toca

**`quedadas` se queda como está en la base.** Se estudió llamarla "open mat" y no
puede ser: **`open_mat` ya existe** como valor de `bjj_tipo_sesion`, así que
tendríamos una tabla y un formato de sesión con el mismo nombre y distinto
significado. Y no encaja: una quedada puede ser preparación de campeonato o una
privada. Además `quedada` es un valor de `bjj_ambito_logro` y cuatro logros lo
usan. **En la interfaz sí se llama "Open Mat"** — solo el fichero de textos.

**Los parámetros de función.** Explicado arriba.

**`logros.clave` frente a `slug`.** Dos palabras para un mismo concepto: es una
inconsistencia, no una ambigüedad. De aquí en adelante, tablas nuevas usan `slug`.

**`eventos.tipo` a `accion`.** Más expresivo, y no: es la columna con más
referencias del proyecto y el nombre no es ambiguo, solo genérico.

**`academia` en `practicantes` y `sesiones`**, que huele a redundante ahora que
existen los equipos. Va al backlog.

Y para que conste: `modalidad`, `duracion_min`, `completado`, `fecha`,
`creado_por` y todos los `*_id` significan lo mismo en todas partes. **El esquema
está bien en general.**

## Cómo lo verificas

1. **Cuenta las referencias antes de tocar y dilo.** "grupo" aparece 371 veces en
   17 ficheros de `db/`. Cuenta también `src/`. Si algo se sale de lo razonable,
   para y avisa.
2. **Todo en una sola migración.** Es grande, y aun así es mejor que dos pasadas
   sobre el mismo código con dos despliegues.
3. **Cada vista con `alter view ... rename column`**, nunca recreada. Al terminar,
   18 de 18 con `security_invoker` y ningún nombre prohibido vivo.
4. **Ninguna política borrada.** Si alguna función lo exigía, dime cuál y por qué
   la dejaste.
5. `information_schema.routine_privileges` idéntico antes y después.
6. Regenera los tipos de TypeScript y que `npm run build` pase con typecheck
   estricto. Si pasa a la primera después de esto, sospecha: casi seguro hay un
   `any` tapando algo o una vista sin renombrar.
7. **La batería entera sigue verde**: `db/pruebas/rls.sql` y `db/pruebas/puntos.sql`.
   Es exactamente para lo que existe, y es la razón de hacer esto ahora.
8. **Las migraciones aplican desde cero** en orden alfabético.
9. **El modo observador, de punta a punta**, después del renombrado de `par_id`:
   sigue creando los dos rolls espejo, y dos llamadas con el mismo par siguen
   siendo idempotentes. Es la pieza con más riesgo del bloque.
10. Repaso a ojo en 390px. Un `undefined` en un desplegable que venía de una vista
    no lo caza el typecheck.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios, e incluye **qué etiqueta de migración usaste**— y añade a
`CLAUDE.md`, en convenciones, la regla de "una palabra, un concepto" y la de
"identificador frente a etiqueta".
