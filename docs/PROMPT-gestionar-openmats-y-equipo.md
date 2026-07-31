# Prompt para Claude Code — gestionar Open Mats y el equipo

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Faltan tres cosas que ya se pueden hacer en la base pero no en la pantalla. Lee
antes `CLAUDE.md`.

## Primero, la palabra, porque en este proyecto engaña

**Aquí "evento" NO es lo que Felipe llama evento.** En el esquema, `eventos` son
las acciones dentro de un roll —una sumisión, un pase—. Lo que Felipe llama
"evento" es una **`quedada`**, que en la interfaz se llama **"Open Mat"**.

**No toques la tabla `eventos` en esta tanda.** Todo esto es `quedadas`,
`inscripciones` y `miembros_equipo`.

## Y lo segundo: la RLS ya lo permite. Esto es cliente.

Comprobado contra producción, las políticas ya existen:

```
quedadas_admin        FOR ALL   private.es_admin(equipo_id)
inscripciones_admin   FOR ALL   sobre quedadas de equipos que administras
miembros_equipo       miembros_alta_admin (insert) · miembros_baja_admin (delete)
                      miembros_cambio_admin (update), todas con es_admin
```

**No hace falta migración, ni política nueva, ni RPC nueva** (salvo un cambio de
firma en la de apuntarse, más abajo). Si te encuentras escribiendo una política,
para: casi seguro que estás resolviendo el problema equivocado.

Nota: hoy **solo un admin puede crear un Open Mat**, porque `quedadas_admin` es la
única política de escritura. Así que "el que lo creó" y "un admin" son la misma
persona por construcción. No montes lógica de `creado_por` aparte.

## 1 · Editar y cancelar un Open Mat

**Editar**: `titulo`, `fecha`, `hora_inicio`, `duracion_min`, `lugar`,
`plazas_max`, `modalidad`, `admite_externos`, `notas`.

**Cancelar es la acción destructiva por defecto, no borrar.** `bjj_estado_quedada`
ya tiene `cancelada`. Un Open Mat cancelado **sigue viéndose**, tachado y con sus
apuntados: la gente necesita enterarse de que no hay entreno, y ese es justo el
momento en que no puedes hacerlo desaparecer.

**Borrar solo se ofrece si no cuelga nada de él** — cero inscripciones, cero
sesiones, sin informe. Si hay algo, el botón no existe. El motivo, comprobado en
producción:

- `inscripciones.quedada_id` y `quedada_informes.quedada_id` son **`ON DELETE
  CASCADE`**: borrar se lleva todos los apuntados y el informe sin avisar.
- `sesiones.quedada_id` es **`ON DELETE SET NULL`**: los rolls no se pierden, pero
  se **desenganchan**, y con eso los cuatro logros de ámbito `quedada` dejan de
  contar para esas sesiones. Nadie se entera nunca.

Borrar parece limpieza y en realidad cambia el historial de otra gente en
silencio.

**El caso interesante son las plazas:**

- **Subir `plazas_max`** debe **promover desde la lista de espera**, por
  `orden_en_lista`. Es la razón por la que alguien sube las plazas.
- **Bajarlas por debajo de los que ya están apuntados: no se permite.** Mensaje
  claro con el número ("hay 8 apuntados"). Nunca degrades en silencio a alguien
  que ya tenía su sitio.

Y al cancelar, **un elemento en el feed**. No hay notificaciones; el feed es el
único canal que tenemos.

## 2 · Apuntar a otra persona

**La trampa está aquí, y es la parte importante del encargo.**

La RLS te deja insertar en `inscripciones` directamente como admin. **No lo
hagas.** La lógica de plazas y lista de espera vive en `apuntarse_a_quedada`; un
insert directo se la salta y acabas con nueve personas en ocho plazas, o con
alguien marcado `apuntado` que debería estar en `lista_espera`.

**Extiende la RPC que ya existe** con un parámetro opcional de a quién apuntas,
por defecto quien llama. Si es otra persona, exige `private.es_admin` del equipo
de esa quedada.

> **Cuidado con el cambio de firma.** Ya nos mordió con `p_grupo`: Postgres
> identifica una función por *(nombre, tipos)* y PostgREST resuelve por el
> conjunto de nombres del cuerpo. Antes de escribir, comprueba que las llamadas
> actuales siguen resolviendo y que no queda ambigüedad entre las dos formas. Y
> mira si la cola de salida serializa esa llamada: si lo hace, dilo antes de
> tocarla.

El selector ofrece **miembros del equipo y contactos sin cuenta** — los contactos
son justo para esto, gente que entrena y no usa la app. Marca `es_externo` para
quien no sea del equipo; la columna ya está.

**Quitar a alguien también hace falta** (se apunta por error, o avisa de que no
va). Y al quitarlo, **promueve al primero de la lista de espera**.

Esa promoción ocurre en tres sitios —alguien se borra, un admin lo quita, suben
las plazas—. **Escríbela una vez y llámala desde los tres.** Tres copias de una
regla de plazas es cómo se acaba con tres comportamientos distintos.

## 3 · Añadir gente al equipo

`miembros_alta_admin` ya lo permite. Pero son **dos casos distintos y no se
tratan igual**:

**Un contacto sin cuenta** → se añade directamente. Es un practicante que creaste
tú, no hay nadie a quien preguntar.

**Una persona con cuenta** → **no la añadas desde la pantalla de admin.** Meter a
alguien en un equipo le da acceso de lectura a los rolls de todos los miembros, y
le da al equipo acceso a los suyos. Eso es un cambio de privilegios sobre los
datos de otra persona, y no se hace por sorpresa. Para eso ya está el
`codigo_union` y `unirse_con_codigo`: el admin comparte el código, la persona
entra. Ponlo en la misma pantalla, con una línea explicando por qué —si no, parece
una función que falta en vez de una decisión.

**Quitar a un miembro** sí se permite (`miembros_baja_admin`). Pero en la
confirmación deja claro que **no borra sus datos**: deja de ver los del equipo y
el equipo deja de ver los suyos. Quien lo pulse tiene que saber qué está haciendo.

## 4 · Enganchar las sesiones al Open Mat. Esto es lo más importante de la tanda.

Comprobado contra producción:

```
quedadas creadas                              5
sesiones con quedada_id                       0   (de 71)
registrar_roll_observado menciona quedada     NO
sesion_del_dia menciona quedada               NO
```

**Ninguna sesión se ha enganchado nunca a un Open Mat.** No es que falten datos:
el enlace no existe en el código. Y de ese campo cuelgan `cerrar_quedada`,
`metricas_quedada`, `quedada_informes` y los **cuatro logros de ámbito
`quedada`** — todo construido, todo alimentándose de una columna que nadie
escribe. La nota de `docs/CAMBIOS.md` que decía "los logros de quedada aún no
tienen datos reales" estaba diagnosticando mal: no faltaban datos, faltaba la
tubería.

El enlace es **`sesiones.quedada_id`**. Va en la sesión, no en el roll: un roll
llega a su Open Mat por `eventos → rolls → sesiones.quedada_id`.

**Tres momentos, y ninguno pregunta más de una vez:**

**Al empezar tu propia sesión.** Si hoy hay **exactamente un** Open Mat de tu
equipo al que estás apuntado, se engancha solo — y **se ve**: "Entreno · Open Mat
en casa de Felipe", con forma de quitarlo. Automático pero visible, nunca
silencioso. Si hay dos, pregunta. Si no hay ninguno, no pasa nada. La vista
`v_mi_quedada_hoy` ya existe y es justo para esto; parece que se construyó y no se
llegó a enchufar.

**En modo observador, se elige una vez al empezar** y vale para toda la tanda.
Cada roll registrado engancha **las sesiones de los dos jugadores**. Es un toque
para toda la tarde, que es lo que puede costar.

**Y hacia atrás**, desde la pantalla del Open Mat: "enganchar las sesiones de hoy".
Porque el domingo alguien se va a olvidar, y poder arreglarlo el lunes es la
diferencia entre un informe y un agujero.

### No toques la firma de `registrar_roll_observado`

Ya tiene **dos** firmas por el puente de `p_grupo`, y es lo que serializa la cola
de salida. Una tercera es pedir problemas.

Haz una RPC pequeña aparte —`enganchar_sesion_a_quedada(p_sesion, p_quedada)`—
`SECURITY DEFINER`, con `revoke execute from anon, public`, y que compruebe: que
quien llama es el dueño de la sesión **o** quien registró el roll, que la quedada
es de un equipo suyo, y que la fecha de la sesión coincide con la del Open Mat.
Esa última guarda es la que evita enganchar el entreno del martes al Open Mat del
domingo.

Idempotente: llamarla dos veces con lo mismo no rompe nada.

## Cómo lo verificas

1. `npm run build` pasa con typecheck estricto.
2. **Los tres casos de "equipo equivocado"**, a `db/pruebas/rls.sql`: un admin del
   equipo A **no** puede editar una quedada del equipo B, **no** puede apuntar a
   nadie en ella, y **no** puede añadir miembros al equipo B. Son los tres que
   importan.
3. **Las plazas, los cuatro caminos**: con una plaza libre, dos altas dejan un
   `apuntado` y un `lista_espera`; subir plazas promueve al primero de la lista;
   quitar a alguien promueve al primero; bajar plazas por debajo de los apuntados
   se rechaza con mensaje.
4. **Cancelar conserva**: el Open Mat sigue ahí, con sus inscripciones, y el
   informe si lo había. Cuenta las filas antes y después: iguales.
5. **Borrar solo aparece en uno vacío.** Demuéstralo: con una inscripción, el
   botón no está.
6. **El enganche, de punta a punta, y esta es la prueba que quiero ver.** Monta un
   Open Mat con dos personas apuntadas, registra unos rolls en modo observador, y
   comprueba que:
   - las sesiones de **los dos** jugadores tienen `quedada_id`;
   - `metricas_quedada` y el informe devuelven algo, por primera vez;
   - **alguno de los cuatro logros de ámbito `quedada` se dispara.** Nunca lo ha
     hecho, para nadie. Si después de esto siguen todos a cero, el enganche no
     está bien hecho aunque la columna esté rellena.
7. **La guarda de fecha**: enganchar una sesión de otro día al Open Mat falla.
8. **La batería entera sigue verde** y las migraciones aplican desde cero.
7. Probado **a 390px**, en tema claro. Esto se usa con una mano en el gimnasio,
   con gente esperando: los botones grandes y la confirmación corta.

## Fuera de alcance

**Que un no-admin pueda crear un Open Mat.** Hoy la RLS no lo permite y cambiarlo
es una decisión de producto, no un arreglo. Si te parece que hace falta, dilo y
para.

**Notificaciones.** El feed es el canal.

**Borrar practicantes.** `sesiones.practicante_id` es `ON DELETE CASCADE`: borrar
a alguien se lleva sus sesiones, sus rolls y sus eventos. Ni lo ofrezcas en esta
tanda.

**Tocar `eventos`.** Ya está dicho arriba, y lo repito porque el nombre engaña.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios— y tacha lo que corresponda en `docs/BACKLOG.md`.
