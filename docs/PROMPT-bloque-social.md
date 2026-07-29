# Prompt para Claude Code — bloque social completo

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a construir el **bloque social** de yujitsu: grupos con roles, quedadas con
inscripciones, informe de la quedada, feed de actividad y enfoques de
entrenamiento. Lee antes `CLAUDE.md` y `HANDOVER.md`.

Es mucho para una tanda, y Felipe lo ha querido así a sabiendas. Por eso va en
**fases con un punto de parada obligatorio**: la fase 2 cambia la RLS, y todo lo
demás se construye encima. Si la RLS queda mal, lo que venga después está mal y
no se nota hasta que alguien ve datos que no debería. **No pases de la fase 2 sin
haberla verificado con los tests que se piden ahí.**

## El modelo, en una frase

Un **grupo** reúne practicantes con roles. Un grupo organiza **quedadas** con
plazas. Una quedada agrupa **sesiones**, que ya existen y ya contienen los rolls.
Todo lo demás —informe, feed, ranking— es derivado.

---

# FASE 1 · Grupos, miembros y roles

## Por qué

Hoy `academia` es **texto libre** en `practicantes` y en `sesiones`. "Gullo",
"gullo bjj" y "Gullo Jiu-Jitsu" son tres academias distintas y nadie se entera.
Además no hay forma de decir quién manda ni quién pertenece a qué.

## Esquema

```sql
grupos
  id uuid pk · nombre text · slug text unique · ciudad text
  codigo_union text unique          -- p.ej. 'GULLO-7X4'
  modo_cachondeo boolean default false   -- ver fase 4
  creado_por uuid → auth.users · created_at

miembros_grupo
  grupo_id uuid → grupos · practicante_id uuid → practicantes
  rol bjj_rol_grupo (admin | miembro)
  estado bjj_estado_miembro (activo | baja)
  created_at
  primary key (grupo_id, practicante_id)
```

**Tabla de miembros, no una columna en `practicantes`.** La gente entrena en más
de un sitio y el rol es por grupo, no global. Una columna obliga a rehacerlo en
cuanto aparezca el segundo grupo.

**Se llama `grupos` y no `gimnasios`** porque no siempre es un gimnasio: el open
mat de los domingos en casa de Felipe es la mitad del caso de uso. En la interfaz
la etiqueta puede ser "Gimnasio", pero el esquema no debe mentir. Si prefieres
otro nombre, dilo antes de escribirlo, no después.

## Alta: las dos vías

**Código de unión.** El admin genera un código y lo dice en el vestuario.

```sql
unirse_con_codigo(p_codigo text) returns uuid   -- devuelve grupo_id
```

`SECURITY DEFINER`, `set search_path = public`, `revoke execute from anon`. Crea
la fila en `miembros_grupo` con `rol = 'miembro'`. Si ya eres miembro activo,
devuelve el grupo sin error — idempotente, porque la gente pulsa dos veces.
Si el código no existe, excepción clara.

**Alta manual por el admin**, para la gente que ya está en el roster como
contacto. Solo un `admin` del grupo puede hacerlo, y eso se comprueba en la
política, no en el cliente.

Y `regenerar_codigo(p_grupo)`, solo admin, para cuando el código se filtre.

## Qué puede hacer cada rol

| | admin | miembro |
|---|---|---|
| Editar el grupo, regenerar código | sí | no |
| Añadir y quitar miembros, nombrar admins | sí | no |
| Crear, editar y cerrar quedadas | sí | no |
| Ver el feed y apuntarse a quedadas | sí | sí |

Nada más por ahora. Cuanto más pequeño el modelo de permisos, menos superficie
para un fallo de privacidad.

## La migración de datos existentes — LEE ESTO DOS VECES

En producción hay datos reales que Felipe quiere conservar: 2 usuarios con
cuenta, varios contactos, y ~240 rolls entre practicantes de demo (Goku, Vegeta,
Krilin, Piccolo, Freezer). **Si creas los grupos y recortas la RLS sin migrar,
todo eso desaparece de la aplicación** y va a parecer que se han borrado datos.

La migración tiene que, en la misma transacción:

1. Crear el grupo **Gullo** con Felipe como `admin`.
2. Meter a **todos** los practicantes existentes como `miembro` activo.
3. Rellenar `sesiones.grupo_id` a partir del texto de `academia`, con Gullo por
   defecto.
4. Dejar `academia` donde está por ahora, sin borrarla. Se quita en otra
   migración cuando esté claro que nada la lee.

Después de migrar, comprueba contando: los mismos rolls visibles antes y después.

---

# FASE 2 · Recortar la RLS ← PUNTO DE PARADA

## Qué cambia y por qué

Cuando se hizo el selector de practicantes en la pantalla de análisis, la lectura
se abrió a **cualquier usuario autenticado ve a cualquiera**, con la nota escrita
de que se quedaría corto en cuanto entrara gente. El grupo es la frontera que
faltaba.

Nueva regla: **ves los datos de quien comparte grupo contigo, y los tuyos.**

Helpers en el esquema `private`, como manda `CLAUDE.md` —ahí viven para que
PostgREST no los publique en `/rest/v1/rpc/`:

```sql
private.mis_grupos() returns setof uuid
private.comparte_grupo(p_practicante uuid) returns boolean
private.es_admin(p_grupo uuid) returns boolean
```

Aplica la condición de lectura a `sesiones`, `rolls` y `eventos`. **Las políticas
de escritura no se tocan**: cada uno sigue escribiendo lo suyo y los terceros
solo por `registrar_roll_observado`.

## Cómo verificarlo, y no es opcional

Con `set local role authenticated` y el claim del usuario, **no como
superusuario, que se salta la RLS**:

1. Felipe ve sus rolls y los de todos los del grupo Gullo. Cuenta exacta.
2. Crea un grupo de prueba con un practicante que no esté en Gullo. Desde Felipe,
   `select` sobre sus rolls devuelve **cero filas**. Si devuelve algo, para.
3. Escribir sigue funcionando igual que antes: puedes insertar tu sesión, no la
   de otro.
4. El total de rolls visibles para Felipe antes y después de la migración es el
   mismo. Si bajó, la migración de la fase 1 se dejó gente fuera.

Deja los cuatro comprobados por escrito en `db/pruebas/` antes de seguir.

---

# FASE 3 · Quedadas

## El nombre

**`eventos` está cogido** — es la tabla central del modelo, cada acción de cada
roll. Los open mats se llaman **`quedadas`**. No lo cambies.

## Esquema

```sql
quedadas
  id uuid pk · grupo_id uuid → grupos
  titulo text · fecha date · hora_inicio time · duracion_min smallint
  lugar text · plazas_max smallint · modalidad bjj_modalidad
  admite_externos boolean default true
  token_invitacion text unique          -- para el enlace de compartir
  notas text
  estado bjj_estado_quedada (abierta | cerrada | cancelada)
  creado_por uuid · created_at

inscripciones
  id uuid pk · quedada_id uuid → quedadas · practicante_id uuid → practicantes
  estado bjj_estado_inscripcion (apuntado | lista_espera | cancelado)
  orden smallint · es_externo boolean · created_at
  unique (quedada_id, practicante_id)
```

## Los externos, que son el 10 % del caso real

El open mat de los domingos en casa de Felipe es **90 % gente de Gullo y 10 % de
otros gimnasios**. O sea que una quedada tiene que admitir a alguien que **no es
miembro del grupo**, sin por eso darle acceso al feed y a los datos de todo el
grupo.

- `admite_externos` en la quedada, y `es_externo` en la inscripción.
- `token_invitacion`: un enlace que deja ver **esa quedada y solo esa**, y
  apuntarse. No abre nada más.
- Un externo apuntado ve la quedada y su propia ficha. **No** ve el feed del
  grupo ni los datos de los demás. Que esto quede escrito en un comentario de la
  migración, porque es justo el sitio donde se cuela un fallo de privacidad.
- Los rolls que el externo registre en esa quedada sí son visibles para el grupo:
  la quedada es del grupo.

## Las plazas se controlan en la base, nunca en el cliente

Dos personas dándole a "apuntarme" a la vez con una plaza libre es el caso
clásico y el cliente no puede resolverlo.

```sql
apuntarse_a_quedada(p_quedada uuid, p_token text default null) returns jsonb
```

`SECURITY DEFINER`, con `pg_advisory_xact_lock(hashtextextended(...))` sobre la
quedada — el mismo patrón que ya usa `registrar_roll_observado`, cópialo. Si hay
hueco entras como `apuntado`; si no, a `lista_espera` con su `orden`. Idempotente:
apuntarse dos veces no crea dos filas ni te manda a la lista.

Y `cancelar_inscripcion(p_quedada)`: al liberarse una plaza, **sube
automáticamente el primero de la lista de espera** dentro de la misma
transacción, y eso aparece en el feed.

## Enganchar los rolls a la quedada

`sesiones.quedada_id` nullable.

**A nivel de sesión, no de roll.** Todos los rolls de esa tarde en ese sitio son
de esa quedada; preguntarlo una vez en vez de en cada roll son cuatro toques
menos por tarde. Se puede corregir desde el resumen.

Y el detalle que lo hace bueno: **si hay una quedada hoy en tu grupo y estás
apuntado, viene preseleccionada.** En el caso normal son cero toques. "Roll
libre" es lo que sale cuando no hay ninguna.

## Pantalla

Una pestaña **Quedadas**: las próximas con plazas restantes y un botón de
apuntarse o borrarse; las pasadas con enlace a su informe. El admin ve además
crear, editar, cerrar y la lista de apuntados con los externos marcados.

---

# FASE 4 · El informe de la quedada

Todo derivado: una consulta sobre `eventos` filtrando por `sesiones.quedada_id`.
Cero tablas nuevas para calcularlo.

## Congelado, no vivo

Si el informe se recalcula, alguien que corrija un roll el martes cambia el
informe del domingo que ya se compartió. Se **congela** al cerrar la quedada:

```sql
quedada_informes
  quedada_id uuid pk → quedadas · datos jsonb
  generado_por uuid · generado_at
```

`cerrar_quedada(p_quedada)`, solo admin, calcula y guarda el `jsonb`, y pone la
quedada en `cerrada`. Volver a llamarla regenera solo si el admin lo pide
explícitamente.

## El ranking

Por **puntos estimados por roll**: promedio de `puntos_autor - puntos_oponente`
de `v_puntos_roll`, mínimo 2 rolls para entrar. Es más honesto que contar
sumisiones porque premia al que domina aunque no finalice, que es justo lo que
se quería medir.

## Los títulos

**La regla importa más que la lista: cada persona se lleva exactamente un título
y nadie se queda sin uno.** Se asignan por mayor desviación respecto a la media
del grupo esa tarde —normaliza cada métrica y ordena por |z|—, de forma voraz,
sin repetir persona ni título. Si se asignan por umbrales fijos, los tres mismos
se lo llevan todo cada domingo y el resto deja de abrir el informe.

| Título | Métrica |
|---|---|
| **IMPASABLE** | menos pases de guardia encajados por roll |
| **EL RODILLO** | más pases completados |
| **EL FRANCOTIRADOR** | mejor ratio finalizadas/intentadas (mínimo 5 intentos) |
| **EL PULPO** | más intentos de sumisión, salgan o no |
| **HOUDINI** | más escapes desde posiciones dominantes |
| **EL MOCHILERO** | más espaldas tomadas |
| **PRIMERA SANGRE** | la sumisión más rápida de la tarde |
| **EL PROFESOR** | rodó con más compañeros distintos |
| **CINTURÓN INVISIBLE** | finalizó a alguien de cinturón superior |
| **PIERNAS DE ACERO** | más ataques a las piernas (nogi) |
| **LA MÁQUINA** | más rolls registrados |
| **DIPLOMÁTICO** | más rolls terminados sin sumisión |

Detrás de `grupos.modo_cachondeo`, apagado por defecto, dos más: **EL ANCLA**
(más tiempo en una posición sin progresar) y **PEAJE** (más veces le pasan la
guardia). En un gimnasio real un título negativo automático le sienta mal a
alguien tarde o temprano, y esa decisión la toma un humano, no la app.

Si hay más gente que títulos, amplía la lista antes de dejar a nadie sin uno.

---

# FASE 5 · Feed de actividad

**Feed, no chat.** Felipe ha elegido feed ahora y chat más adelante si hace
falta; **no construyas mensajería**.

El feed es **derivado**: una vista, no una tabla de entradas.

```sql
v_feed(grupo_id, tipo, referencia_id, practicante_id, cuando, datos jsonb)
```

Union de, para empezar: sesión registrada (con nº de rolls), posición
desbloqueada por primera vez, reto completado, quedada creada, alguien se apunta
a una quedada, informe publicado, nuevo miembro en el grupo.

Filtrado por `private.mis_grupos()`. Paginado por `cuando`, no por offset.

```sql
reacciones
  id uuid pk · practicante_id uuid · item_tipo text · referencia_id uuid
  emoji text · created_at
  unique (practicante_id, item_tipo, referencia_id, emoji)
```

**El detalle que hay que acertar:** la clave de una reacción apunta a la **fila de
origen** —el `sesion_id`, el `roll_id`, la `inscripcion_id`— no a una fila del
feed, porque el feed es una vista y sus filas no tienen identidad estable. Si lo
haces al revés, las reacciones se despegan de su contenido en cuanto cambie la
vista.

Emojis cerrados a un puñado (🔥 💪 😂 🫡 🥋), no un selector libre.

---

# FASE 6 · Enfoques

Lo que cada uno está trabajando estas semanas. Con historial, no un campo que se
pisa:

```sql
enfoques
  id uuid pk · practicante_id uuid → practicantes
  desde date · hasta date
  texto text
  posiciones bjj_posicion[] · tecnicas uuid[]
  created_at
```

**Y aquí está lo que lo convierte en algo que ninguna app de BJJ hace.** Como las
posiciones y las técnicas van estructuradas y no solo en texto libre, la ficha
puede contrastar lo que dijiste con lo que hiciste:

> Dijiste que estas dos semanas ibas a jugar De la Riva.
> La has usado en **2 de 34 rolls**.

Ese contraste es la mitad del valor de la feature. Si solo guardas texto libre,
no existe. El texto libre se queda igualmente, para el matiz.

En el perfil de cada practicante: el enfoque activo, el contraste con los datos
del periodo, y el histórico de enfoques anteriores.

---

# Invariantes que no puedes romper

Están en `CLAUDE.md` y siguen valiendo:

- **Los ids se generan en el cliente** y la cola sube con `upsert`, nunca
  `insert`.
- **La cola sube por tablas en orden**: `sesiones` → `rolls` → `eventos`.
- **Nada escribe directo contra Supabase** salvo `practicantes` — y ahora
  `miembros_grupo`, `inscripciones`, `reacciones` y `enfoques`, que son
  interacciones en línea, no registro de rolls. Sesiones, rolls y eventos siguen
  pasando por `encolar()`.
- **Todas las vistas nuevas llevan `security_invoker = on`.** Sin eso, cualquiera
  lee el feed de otro grupo a través de la vista.
- **La interfaz solo ofrece lo que la RLS permite.** Si el botón de cerrar una
  quedada le sale a un miembro, verá un error en vez de un botón ausente.

---

# Verificación

1. `npm run build` pasa, typecheck estricto incluido.
2. **Las cuatro pruebas de RLS de la fase 2**, escritas en `db/pruebas/` y
   pasando. Con `set local role authenticated`, no como superusuario.
3. **Concurrencia de plazas**: dos llamadas simultáneas a `apuntarse_a_quedada`
   con una sola plaza libre dejan un `apuntado` y un `lista_espera`. Pruébalo de
   verdad con dos sesiones, no razonando sobre el código.
4. **Idempotencia** de `unirse_con_codigo` y `apuntarse_a_quedada`: llamarlas dos
   veces no duplica nada.
5. **El externo no ve de más**: autenticado como un practicante que no es miembro
   pero está apuntado con token, `select` sobre el feed del grupo y sobre los
   rolls de otros devuelve cero filas.
6. **Nada desapareció**: el número de rolls visibles para Felipe es el mismo
   antes y después de todo esto.
7. Un informe generado con datos reales, comprobando que **cada asistente tiene
   exactamente un título**.
8. Probado a 390px de ancho.
9. Migraciones **primero contra un Postgres local**, como está en
   `db/README.md`. Producción tiene datos que Felipe quiere conservar.

---

# Fuera de alcance

**Chat.** Decidido: feed ahora, chat solo si el feed se queda corto.

**Notificaciones push.** No hay infraestructura y no entra aquí. La lista de
espera avisa por el feed.

**Fusionar fichas duplicadas y reclamar ficha.** Van a hacer falta pronto —el
grupo es justo lo que las desbloquea— pero no en esta tanda. Anótalas en el
backlog con lo que hayas aprendido montando los grupos.

**La tarjeta de resumen del roll** y el radar de efectividad: bloque aparte.

---

# Decisiones que NO tomas tú

- **`de_rodillas`** en `bjj_posicion`: vocabulario, lo cierran Felipe y Pablo.
- **`posicion_destino`** para las transiciones: pendiente de Felipe.
- Si al montar los grupos te parece que **`grupos` debería llamarse de otra
  forma**, dilo antes de escribir la migración. Un valor de enum o un nombre de
  tabla no se quita después sin dolor.

Cuando termines, actualiza `CLAUDE.md` —el modelo de grupos y la nueva regla de
lectura— y `docs/02-backlog.md`.
