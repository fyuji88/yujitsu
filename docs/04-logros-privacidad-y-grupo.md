# yujitsu · logros, privacidad y pestaña de grupo

**29 julio 2026.** Diseño de las tres ideas nuevas, más el mecanismo para que el
PM no se quede desactualizado.

---

# 1 · Logros mensuales

## La distinción que hace que esto no sea lo mismo que los títulos

Los **títulos de la quedada** son **relativos**: se reparten comparando a los que
estuvieron esa tarde, uno por persona, y nadie se queda sin. Sirven para que el
informe del domingo sea social.

Los **logros mensuales** tienen que ser lo contrario: **absolutos y acumulables.**
Un logro es un hecho sobre **un roll concreto** — o pasó o no pasó, y no depende de
quién más estuviera. IMPASABLE no es "el que menos pases encajó", es **"un roll en
el que no te pasaron la guardia ni una vez"**.

Esa diferencia lo cambia todo:

- **No es de suma cero.** Que Pablo consiga 14 IMPASABLE no te quita los tuyos.
- **Se cuenta.** "IMPASABLE ×14 este mes" es una frase con sentido; "el más
  impasable" ya lo cubren los títulos.
- **Es una colección.** Tu perfil acumula logros de por vida, como un armario de
  trofeos, y el ranking mensual es solo un corte temporal de eso.
- **Alimenta el feed** con el momento que importa: la primera vez que consigues
  uno.

## Cómo se modela

Un logro es un **predicado booleano sobre un roll**, evaluado con los eventos que
ya guardáis. Nada nuevo que registrar.

```sql
logros                          -- catálogo, no datos
  clave text pk · nombre text · descripcion text
  familia (defensa|ataque|estilo|constancia|cachondeo)
  rareza (comun|poco_comun|raro)
  min_volumen jsonb             -- la guarda de volumen de cada uno
  solo_nogi boolean

v_logros_roll(roll_id, autor_id, clave)     -- vista, se deriva de eventos
v_logros_mes(autor_id, mes, clave, veces)   -- el ranking mensual
```

**Cada logro necesita su guarda de volumen**, y esto no es opcional. "IMPASABLE"
en un roll donde nunca jugaste guardia es falso. "100 % de acierto" con un intento
es mentira. La guarda va en el catálogo, no repartida por el código.

**Regla de diseño**: la mayoría de los logros tienen que ser alcanzables por un
cinturón blanco. Si los que necesitan motivación son los que no consiguen ninguno,
el sistema hace justo lo contrario de lo que quieres. Deja unos pocos raros como
aspiracionales, no la mitad.

## Los logros

### Defensa

| Logro | Se consigue en un roll cuando… | Rareza |
|---|---|---|
| **IMPASABLE** | no te pasan la guardia ni una vez (habiendo jugado guardia) | común |
| **MURO** | el rival intenta 3 o más sumisiones y no entra ninguna | poco común |
| **HOUDINI** | escapas 3 o más veces de posiciones dominantes | poco común |
| **DE VUELTA** | te montan o te toman la espalda y acabas ganando el roll | raro |
| **CINTURÓN INVISIBLE** | no te finaliza alguien de cinturón superior | poco común |
| **CUELLO DE ACERO** | te atacan el cuello 3 veces y no cae ninguna | poco común |

### Ataque

| Logro | Se consigue en un roll cuando… | Rareza |
|---|---|---|
| **EL RODILLO** | pasas la guardia 3 o más veces | común |
| **LIMPIO** | finalizas sin haber fallado ningún intento antes | común |
| **RELÁMPAGO** | finalizas en menos de 60 segundos | poco común |
| **LA CADENA** | pasas, montas y tomas la espalda en el mismo roll | raro |
| **QUINCE** | acumulas 15 o más puntos estimados | raro |
| **PRIMERA VEZ** | finalizas desde una posición desde la que nunca habías finalizado | poco común |
| **JUGUETE NUEVO** | finalizas con una técnica que nunca habías usado | poco común |
| **GUARDIA DE HIERRO** | barres 3 o más veces | común |
| **EL MOCHILERO** | tomas la espalda 2 o más veces | común |
| **PIERNAS** | finalizas a la pierna (solo nogi) | poco común |

### Estilo

| Logro | Se consigue cuando… | Rareza |
|---|---|---|
| **EL PULPO** | 5 o más intentos de sumisión en un roll | común |
| **EL ARTISTA** | 3 sumisiones **distintas** en la misma quedada | poco común |
| **AMBIDIESTRO** | finalizas desde arriba y desde abajo en la misma quedada | poco común |
| **SIN GI, SIN PROBLEMA** | finalizas en gi y en nogi la misma semana | poco común |

### Constancia — y esta familia es la más importante de todas

| Logro | Se consigue cuando… | Rareza |
|---|---|---|
| **EL NOTARIO** | registras **todos** los rolls de una quedada, sin dejarte ninguno | común |
| **OJO DEL COACH** | registras 10 rolls como observador en un mes | poco común |
| **SEMANA COMPLETA** | registras en todas las sesiones de una semana | común |
| **EL ÚLTIMO EN IRSE** | tuyo es el último roll registrado de la quedada | común |

Estos cuatro no premian rendimiento, **premian registrar**. Y registrar es el
único riesgo que de verdad mata este producto. La mayoría de las apps gamifican el
resultado; una parte de las vuestras tiene que gamificar la conducta que
necesitáis. Si tuviera que elegir qué familia implementar primero, sería esta.

### Cachondeo — detrás del interruptor del admin

**PEAJE** (te pasan la guardia 4 o más veces en un roll) · **EL ANCLA** (más de dos
minutos en la misma posición sin que pase nada) · **DONANTE** (encajas 3
sumisiones en un roll). Apagados por defecto: en un gimnasio de verdad un logro
negativo automático le sienta mal a alguien tarde o temprano.

## El ranking mensual

Por **veces conseguido**, por logro, con el mes como ventana. Y en el perfil, tu
colección de por vida con las rachas. Reinicio mensual, que además evita que los
mismos lo dominen para siempre.

## ¿Solo en modo observador? No, pero casi — y el criterio es preciso

La preocupación es real y hay que tomársela en serio: **los datos autoregistrados
están sesgados, y el sesgo va a tu favor.** No ves tu propia espalda, no recuerdas
los intentos que fallaste, y sí recuerdas la barrida que te salió. Un logro es
moneda pública y comparable, así que acuñarla con datos inflados corrompe el
ranking — y peor, **premia al que registra mal**.

Pero exigir observador para todos los logros los mata. Tres razones:

- **El volumen se hunde.** Hoy casi ningún roll real está registrado por un
  observador, porque hace falta una tercera persona dispuesta a sentarse seis
  minutos a pulsar botones. La mayoría de la gente tendría cero logros para
  siempre.
- **Castiga a quien no toca.** Alguien que va a un open mat sin coach mirando no
  consigue nada por bien que ruede. Eso no es "sin sesgo", es "solo cuentan los
  que tienen público".
- **Contradice la familia de constancia.** EL NOTARIO es, por definición, sobre
  registrar tú. Si los logros exigen observador, los logros que premian registrar
  no pueden existir.

### El criterio que sí funciona: ausencia contra presencia

El sesgo no afecta a todos los logros igual, y esto es lo que hay que ver. **Los
logros que se definen por la ausencia de algo son inflables sin querer; los que se
definen por algo que pasó, no.**

- **IMPASABLE** es "no hubo ningún pase". Se infla simplemente no registrando el
  pase. Igual **LIMPIO** ("sin intentos fallados antes"), **MURO**, **CUELLO DE
  ACERO** y **CINTURÓN INVISIBLE**.
- **RELÁMPAGO** es "hubo una sumisión antes del minuto". Para conseguirlo tuviste
  que **registrar activamente** el evento. Igual EL RODILLO, LA CADENA, QUINCE,
  HOUDINI, EL MOCHILERO, JUGUETE NUEVO.

Así que la regla es:

> **Los logros de ausencia requieren `origen = 'observador'`. Los de presencia, no.**

En el catálogo, un `requiere_observador boolean`. Son cinco o seis de veinticinco,
así que el coste es bajo y arregla casi todo el problema. Y no hace falta nada
nuevo en la base: `rolls.origen` ya existe y `v_rolls_unicos` ya prefiere la
versión del observador cuando hay las dos.

### Y en vez de esconder la procedencia, enseñarla

- En tu colección: **"IMPASABLE ×14 · 5 verificados 👁"**.
- En el ranking, un interruptor que **por defecto cuenta solo los verificados**.
  Ese interruptor hace un trabajo extra: **le explica a la gente por qué importa
  el modo observador** sin un tutorial.

### Un principio de diseño que sale de aquí

**Prefiere logros cuya inflación exija auto-inculparse.** EL PULPO cuenta intentos
de sumisión fallados: para inflarlo tienes que registrar tus propios fracasos, que
es lo contrario del sesgo cómodo. Los logros con esa propiedad son a prueba de
trampas por construcción y no necesitan observador ni verificación.

## Cómo aparecen en el feed: agregar, no suprimir

Felipe quiere que el feed avise **también las veces siguientes**, no solo la
primera. La intuición es buena —si solo se anuncia la primera vez, al mes los
logros desaparecen del feed y quien lleva catorce IMPASABLE no recibe nada— pero
un elemento de feed por logro no se sostiene.

**Las cuentas.** Un gimnasio de doce personas, ocho rolls por cabeza y semana, uno
o dos logros por roll: **unas 150 entradas semanales**. El feed pasa a ser 95 %
"X ha conseguido IMPASABLE otra vez", y eso entierra lo que sí tiene valor: el
informe de la quedada, quién se apunta el domingo, el primer logro de alguien. Y
se lleva por delante las reacciones, porque **la densidad del feed y la tasa de
reacción son inversamente proporcionales**: nadie pone 🔥 en el elemento número
noventa.

La salida no es esconder logros, es **cambiar la unidad del elemento**: el feed
habla de **sesiones**, y los logros viajan dentro.

> **Pablo registró 6 rolls anoche** · IMPASABLE ×2 · MURO · RELÁMPAGO

Un solo elemento, toda la información, y encima se lee mejor: ves la forma de su
noche en vez de siete líneas sueltas. Nada queda invisible, que era el punto de
Felipe.

Y por encima de eso, **cuatro cosas que sí merecen su propio elemento**, porque
son noticia:

1. **La primera vez** que alguien consigue un logro.
2. **Los números redondos**: ×5, ×10, ×25, ×50. El que va por catorce recibe algo
   al llegar a quince.
3. **El primero del grupo** en conseguir un logro, aunque para él no sea la
   primera vez. Eso es socialmente interesante.
4. **Los raros**, siempre.

Más el **cierre de mes**, un elemento único con el ranking, que es donde las
cuentas acumuladas tienen su momento.

**Nota de secuenciación honesta:** con tres personas la inundación no existe —150
a la semana es un problema de doce—. Así que se empieza por el resumen por sesión
más los cuatro casos de arriba, y se revisa cuando el grupo sea real y se pueda
ver de verdad si alguien echa algo en falta. Si hace falta, un ajuste por grupo
para subir o bajar el detalle.

---

# 2 · Privacidad del perfil

Tu idea es la correcta: privado no significa que tus datos no sirvan, significa
que **nadie ve tu nombre pegado a ellos**. Tres cosas que hay que apretar para que
eso sea verdad y no solo una casilla.

## Tres niveles, no dos

| Nivel | Quién ve tus estadísticas |
|---|---|
| **Privado** | solo tú. Tus datos siguen alimentando las medias del grupo |
| **Grupo** | la gente de tu grupo. **Este es el defecto** |
| **Público** | cualquiera con el enlace — para un coach de fuera, o una competición |

**El defecto es "grupo"**, no privado. Si arranca en privado, todas las funciones
sociales parecen roas el primer día y nadie llega a verlas. Pero se dice claro al
entrar, no escondido en ajustes.

## Un segundo interruptor: los puntos débiles

No todas las estadísticas incomodan igual. Alguien puede querer enseñar sus
sumisiones y no que se vea dónde se atasca. En vez de dar visibilidad por sección
—que son diez controles y nadie los entiende—, **un interruptor más**:

- **Tus resultados**: sumisiones, puntos, logros, arquetipo. Lo que se luce.
- **Tus puntos débiles**: heatmap defensivo, dónde te estancas, tu némesis. Se
  enseñan solo si activas "mostrar también mis puntos débiles".

Dos controles en total. Cubre el miedo real sin convertir los ajustes en un panel
de mandos.

## El agregado anónimo no es anónimo por defecto — y esto es lo importante

"Felipe pasa el 22 %, la media de Gullo es el 45 %" suena inofensivo. Pero
**con cuatro personas en el grupo, tu número más la media del resto permite
despejar los de los demás.** Es una ecuación, no una filtración exótica. Con
gimnasios pequeños es un problema real desde el día uno.

Tres reglas, y las tres van en SQL, no en el cliente:

1. **Suelo de cohorte.** Ningún agregado se muestra si está calculado con menos de
   **5 practicantes**. Por debajo no se enseña un número redondeado: no se enseña
   nada, y se dice por qué ("hacen falta 5 personas con datos para comparar").
2. **Un solo corte a la vez.** No ofrezcas simultáneamente la media del grupo, la
   media de tu cinturón y la media "sin contarte a ti". Cada corte extra es otra
   ecuación para despejar. Elige uno por pantalla.
3. **Sin mínimos por celda tampoco.** La media de pases desde De la Riva de los
   cinturones azules puede ser una sola persona. El suelo se aplica **por celda**,
   no por grupo.

## Dos casos que hay que decidir explícitamente o se cuelan

**El head-to-head es de dos.** Tus rolls contra Pablo son también datos de Pablo.
Regla: **los dos participantes ven siempre su head-to-head**, pase lo que pase con
la visibilidad — un roll es compartido y tú siempre puedes ver los tuyos. La
visibilidad solo gobierna a **terceros**.

**El observador ve lo que registra.** Quien registra tu roll conoce sus datos por
definición. Es asumible, pero que esté escrito.

**Y al cambiar de grupo a privado, el historial del feed sobre ti se oculta.** Si
no, "privado" es mentira.

## Un regalo que sale de aquí

Alguien en privado puede seguir apareciendo **como referencia anónima**: "estás por
debajo de la media de tu cinturón". Eso es exactamente lo que describías, y hace
que el modo privado no sea un agujero en el producto sino una forma distinta de
participar.

---

# 3 · La pestaña de grupo

## Qué se ve, de arriba abajo

**La identidad primero.** Nombre del grupo, escudo o logo, y **lema**
(`grupos.lema`) — el "Jiu-jitsu, sauna, playa" de Gullo puesto donde se vea. Es lo
que hace que la pestaña se sienta de ellos y no de la app, y engancha directamente
con el trabajo de tema por grupo.

**El top 5 del mes**, con el avatar de cinturón y la insignia de arquetipo.

**Debajo, el pulso del grupo**: rolls este mes, gente activa, la próxima quedada
con plazas, y un enlace al mapa colectivo cuando exista.

## El ranking unificado, que es la parte delicada

Un número que ordena a tus compañeros de entrenamiento puede agriar un gimnasio,
así que hay cuatro decisiones que importan más que la fórmula.

**Primera: qué mide.** No ordenes por sumisiones. Eso ordena por cinturón y por
peso, y un ranking cuyo resultado es "los morados son mejores" no informa a nadie.
Cuatro componentes, cada uno normalizado dentro del grupo:

| Componente | Qué premia |
|---|---|
| **Actividad** | rolls registrados este mes — premia la conducta que necesitáis |
| **Dominio** | diferencial medio de puntos estimados por roll |
| **Progresión** | tu mejora **respecto a ti mismo** en los últimos tres meses |
| **Logros** | logros conseguidos este mes |

**La progresión es contra ti mismo, y es la pieza clave**: es lo que permite que un
cinturón blanco que está mejorando mucho quede por delante de un morado estancado.
Sin ese componente el ranking es una escalera de cinturones con pasos extra.

**Segunda: nada de handicap por cinturón.** Es tentador y sale mal — resulta
paternalista y es imposible de calibrar. La progresión ya hace ese trabajo de forma
honesta. Lo que sí añadiría es **un ranking secundario dentro de cada cinturón**,
que es como funcionan las competiciones de verdad y se entiende sin explicación.

**Tercera, y es la que evita el daño: solo se publica el top 5. Nunca la tabla
completa.** Enseñar del puesto 6 al 20 es donde está el problema: un gimnasio donde
alguien es públicamente decimoctavo de veinte pierde a esa persona. El top 5
celebra; la lista entera castiga. **Cada uno ve su propia posición en privado**,
con qué le movería — "dos rolls más y entras en el top 5" es motivación; "eres el
18.º" es una razón para dejarlo.

**Cuarta: los perfiles privados no entran en el top 5 público**, pero ven su
posición. Si no, el top 5 se puede vaciar poniéndose todos en privado.

Reinicio mensual, para que no lo dominen los mismos y para que haya siempre una
carrera abierta.

---

# 4 · Que el PM no se quede desactualizado

Tienes razón y es un problema real: hoy leo el repo entero, la base y el historial
de git para reconstruir dónde estamos, y aun así se me han colado cosas del backlog
que ya estaban hechas.

## Lo que ya es fiable sin que nadie escriba nada

Dos fuentes que no dependen de la disciplina de nadie, y las uso siempre:

- **Las migraciones aplicadas** en Supabase. Es la verdad sobre el esquema.
- **`git log`** en el repositorio. Es la verdad sobre el código.

## Lo que esas fuentes NO me dicen, y es justo lo que hace falta

Un commit me dice *qué ficheros cambiaron*. No me dice **qué se decidió** ni **qué
se sabe que está roto**. Y eso es lo que me hace repetir preguntas ya contestadas
o proponer cosas ya descartadas.

Así que sí: **un `docs/CAMBIOS.md`**, pero con un formato que sirva para eso y no
para duplicar el `git log`.

```markdown
## 2026-07-29 · Marcador IBJJF en vivo
**Migraciones:** bjj_10, bjj_11, bjj_12
**Decisiones:** `transicion` guarda el destino en `posicion`; no se añadió
  `posicion_destino`. Los 3 segundos de estabilización no se implementan.
**Sabido roto:** un pase que aterriza en montada solo cuenta 3, porque los 4 de
  montada salen de un evento `transicion` que ahí no existe.
**Backlog:** tachado "Puntos IBJJF". Añadido "falta `de_rodillas`".
```

Cuatro reglas que hacen que funcione:

1. **Más nuevo arriba.** Leo las tres primeras entradas y estoy al día.
2. **Decisiones y sabido-roto son obligatorios**; la lista de ficheros es opcional,
   porque eso ya lo tengo.
3. **Es parte de la definición de terminado**, escrito en `CLAUDE.md`. Si es
   opcional, no pasa.
4. **Diez líneas por entrada como máximo.** Un registro que nadie lee es peor que
   no tenerlo.

## Y lo que cierra el círculo

**La retro del domingo audita el registro.** El punto 2 de la retro pasa a ser:
leer `CAMBIOS.md`, cruzarlo con las migraciones aplicadas y con `git log`, y
señalar lo que se entregó sin entrada. Así el registro se revisa una vez por
semana y no se podre — que es lo que le pasa a todos los changelogs que nadie
audita.

Con eso, cada sesión mía empieza leyendo tres cosas cortas —memoria, `CAMBIOS.md`
y las migraciones— en vez de reconstruir el proyecto desde cero.
