# Prompt para Claude Code — enganchar las sesiones al Open Mat

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

El informe del Open Mat sale vacío siempre, y no es un fallo del informe. Lee
antes `CLAUDE.md`.

## Lo medido, para que no lo redescubras

Contra producción:

```
Open Mat                          fecha    estado    apuntados  sesiones  metricas  informes
Open mat                          29 jul   cerrada       1          0         0         1
Open mat                          2 ago    cerrada       2          0         0         1
Open mat                          2 ago    abierta       3          0         0         0
Open mat Casa Felipe 16h          2 ago    abierta       1          0         0         0
Open mat Casa Felipe              30 ago   cerrada       2          0         0         1

sesiones con quedada_id: 0 de 71
registrar_roll_observado menciona quedada: NO
sesion_del_dia menciona quedada: NO
```

`private.metricas_quedada` y `cerrar_quedada` sacan los rolls así:

```sql
from rolls r join sesiones s on s.id = r.sesion_id
where s.quedada_id = p_quedada
```

Como **ninguna sesión se ha enganchado nunca**, ese join devuelve cero filas
siempre. El informe, el ranking, los títulos y los cuatro logros de ámbito
`quedada` están todos construidos y todos alimentándose de una columna que nadie
escribe.

Y la nota de `docs/CAMBIOS.md` que decía *"los logros de quedada aún no tienen
datos reales"* estaba diagnosticando mal: no faltaban datos, faltaba la tubería.

## Fallo 1 · No hay forma de enganchar una sesión a un Open Mat

El enlace es **`sesiones.quedada_id`**. Va en la **sesión**, no en el roll: un roll
llega a su Open Mat por `eventos → rolls → sesiones.quedada_id`. Eso está bien
modelado y no se cambia.

Lo que falta es escribirlo, en tres momentos:

**Al empezar tu propia sesión.** Si hoy hay **exactamente un** Open Mat de tu
equipo al que estás apuntado, se engancha solo — y **se ve**: "Entreno · Open Mat
Casa Felipe", con forma de quitarlo. Automático pero nunca silencioso. Si hay dos,
pregunta. Si no hay ninguno, no pasa nada.

La vista `v_mi_quedada_hoy` ya existe y parece hecha justo para esto. Mírala antes
de escribir nada nuevo: puede que la pieza esté y solo falte enchufarla.

**En modo observador, se elige una vez al empezar la tanda** y vale para toda la
tarde. Cada roll registrado engancha **las sesiones de los dos jugadores**. Un
toque para el día entero, que es lo que puede costar cuando hay gente esperando.

**Y hacia atrás**, desde la pantalla del Open Mat: "enganchar las sesiones de hoy".
Alguien se va a olvidar, y poder arreglarlo al día siguiente es la diferencia
entre tener informe y tener un agujero.

### No toques la firma de `registrar_roll_observado`

Ya tiene **dos** firmas por el puente de `p_grupo`, y es lo que serializa la cola
de salida. Una tercera es pedir problemas.

Haz una RPC pequeña aparte, `SECURITY DEFINER`, con `revoke execute from anon,
public`:

```
enganchar_sesion_a_quedada(p_sesion uuid, p_quedada uuid)
```

Que compruebe, fallando con mensaje claro:

1. Quien llama es **el dueño de la sesión o quien registró sus rolls**.
2. La quedada es de un **equipo suyo**.
3. **La fecha de la sesión coincide con la del Open Mat.** Esta guarda es la que
   impide enganchar el entreno del martes al Open Mat del domingo, y es la que más
   veces va a salvar el dato.

Idempotente: dos llamadas iguales no rompen nada. Y una forma de **desenganchar**,
porque el enganche automático se va a equivocar alguna vez.

## Fallo 2 · `cerrar_quedada` genera informes vacíos sin quejarse

Hay **tres informes ya generados con cero rolls**. La función cerró, escribió el
informe y puso `estado = 'cerrada'` sin una sola advertencia. Cerrar es de una
sola dirección.

- **Si no hay ni un roll enganchado, `cerrar_quedada` no cierra.** Falla con un
  mensaje que diga qué pasa y qué hacer: *"no hay sesiones enganchadas a este Open
  Mat"*. Un informe vacío parece que la app está rota, cuando lo que falta es un
  campo.
- Antes de cerrar, **enseña el alcance**: "se van a incluir 14 rolls de 5
  personas". El mismo principio que en la fusión de técnicas — una acción de una
  sola dirección enseña lo que va a hacer antes de hacerlo.
- `p_regenerar` ya existe: **úsalo como vía de recuperación**. Si alguien engancha
  sesiones después de cerrar, se puede regenerar el informe. Que la pantalla lo
  ofrezca cuando detecte sesiones enganchadas posteriores al informe.

**No toques los tres informes vacíos que ya hay en producción**, ni las quedadas
ya cerradas. Eso lo decide Felipe.

## Cómo lo verificas

1. `npm run build` pasa con typecheck estricto.
2. **La prueba que de verdad importa, de punta a punta**: monta un Open Mat con dos
   personas apuntadas, registra unos rolls en **modo observador**, y comprueba
   que:
   - las sesiones de **los dos** jugadores tienen `quedada_id`;
   - `private.metricas_quedada` devuelve filas, por primera vez;
   - `cerrar_quedada` produce un informe **con números y con títulos**;
   - y **al menos uno de los cuatro logros de ámbito `quedada` se dispara**.

   Ese último es el que manda. Nunca se ha disparado ninguno, para nadie. Si
   después de esto siguen todos a cero, el enganche no está bien hecho por mucho
   que la columna esté rellena.
3. **La guarda de fecha, probada**: enganchar una sesión de otro día falla.
4. **`cerrar_quedada` con cero rolls falla**, y con rolls funciona. Los dos casos.
5. **La RLS**: no puedes enganchar una sesión tuya a un Open Mat de un equipo que
   no es tuyo, ni la sesión de otro que no hayas registrado tú. A
   `db/pruebas/rls.sql`.
6. Las migraciones aplican desde cero y la batería entera sigue verde.
7. Probado **a 390px**. En modo observador esto se toca una vez al principio, con
   gente esperando en el tatami: que sea un botón grande y no un desplegable
   escondido.

## Un caso que quiero que anotes, no que resuelvas

`sesion_del_dia` encuentra o crea una sesión por *(practicante, fecha, modalidad,
academia)*. Si alguien entrena por la mañana en su gimnasio y por la tarde va al
Open Mat **con la misma modalidad y la misma academia**, los dos entrenos caen en
la misma sesión — y engancharla al Open Mat arrastraría también los rolls de la
mañana.

Con academias distintas no pasa. **No lo arregles en esta tanda**: anótalo en
"sabido roto" de `docs/CAMBIOS.md` y en el backlog, con esta explicación.

## Fuera de alcance

**Cambiar el modelo** para que el enlace vaya en el roll en vez de en la sesión.
Está bien donde está.

**Rehacer el informe o los títulos.** Funcionan; lo que les falta son datos.

**Tocar producción.** Los tres informes vacíos y las quedadas ya cerradas se
quedan como están.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios— y tacha lo que corresponda en `docs/BACKLOG.md`.
