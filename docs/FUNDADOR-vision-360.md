# yujitsu · la vista de fundador

**29 julio 2026.** Lo que hay que mirar además de las features. Escrito para
alguien que construye el producto pero todavía no ha tenido que operarlo.

---

## 0 · Antes de nada: qué es realmente esto

Dos frases que deberían gobernar todas las decisiones que vienen.

**Uno: yujitsu no es una app de fitness, es un producto de captura de datos.**
Todo su valor —heatmaps, arquetipos, informes, recomendaciones— depende de que
alguien haga un trabajo aburrido: registrar. Si el registro no ocurre, no hay
producto; no hay una versión degradada, hay cero. Así que la pregunta que hay que
hacerle a cada decisión no es "¿es útil?" sino **"¿esto hace que se registre más
o menos?"**. Una feature preciosa que añade dos toques por roll puede ser
negativa en valor neto.

**Dos: tu unidad de crecimiento es el gimnasio, no la persona.** Y tienes una
razón concreta, no una intuición: **el modo observador**. La razón por la que las
apps de diario de BJJ mueren es que no puedes registrar mientras ruedas, así que
lo rellenas en el coche, mal, dos días, y lo dejas. Que el coach o el que está
mirando registre por ti rompe eso. Pero solo funciona si hay alguien mirando —o
sea, en un gimnasio—. Eso significa que la venta, la retención y el dinero son
todos por academia, no por usuario.

De ahí sale casi todo lo demás.

**Los dos riesgos reales**, por orden, y no son los que la gente espera:

1. **Que nadie registre.** Todos los riesgos técnicos juntos son menos probables
   que este.
2. **Que se pierdan datos una vez.** En un producto de captura, perder la sesión
   de alguien no es un bug: es el final. La confianza en un diario no se
   recupera.

Servidores, competencia y seguridad vienen después de esos dos.

---

## 1 · Estabilidad — el listón mínimo

No hace falta "99,9 % de uptime". Hace falta esto:

**La cola de salida no puede perder nada, nunca.** Es lo más importante de esta
sección entera. Hoy escribís local-first con una cola en IndexedDB, que es la
decisión correcta. Lo que falta es lo de alrededor: reintentos con espera
creciente, nada que se descarte en silencio, y **un indicador visible de "3 rolls
sin subir"** que el usuario pueda tocar para ver qué pasa. Si algo falla
definitivamente, que quede en pantalla, no en la consola.

**Los errores los tienes que ver tú, no el usuario.** Ahora mismo, si a Pablo le
peta el registro un martes, tú te enteras si te lo cuenta. Monta un recolector de
errores —Sentry tiene plan gratuito de sobra para esto— y míralo una vez por
semana. Sin esto estás operando a ciegas.

**Copias de seguridad.** El plan gratuito de Supabase **no tiene ninguna**. Con
240 rolls dentro y gente ajena a punto de entrar, esto pasa de "ya lo haremos" a
condición de salida. O `pg_dump` semanal automatizado a un sitio que no sea
Supabase, o el plan Pro con recuperación a un punto en el tiempo.

**La pausa por inactividad.** El proyecto gratuito se pausa tras una semana sin
actividad. Un gimnasio que se va de vacaciones en agosto vuelve en septiembre a
una app muerta, y ese es exactamente el momento en que se pierde un cliente. Es
otro argumento para Pro, y es barato comparado con el daño.

**Un entorno de pruebas.** Hoy cada migración va directa a producción. Supabase
tiene ramas; úsalas. La regla: nada toca producción sin haber corrido antes en
una rama o en el Postgres local.

**Lo que ya tienes bien y conviene no romper:** funciona sin cobertura. Los
sótanos de los gimnasios no tienen señal, y la mayoría de apps del sector fallan
justo ahí. Es una ventaja competitiva real que salió de una decisión de
arquitectura temprana.

---

## 2 · Que todo el mundo tenga la última versión

Ser una PWA te ahorra las tiendas de aplicaciones, pero te trae un problema
propio: **el service worker cachea, y la gente se queda clavada en una versión
vieja durante semanas sin saberlo.**

El listón mínimo:

- **Aviso de versión nueva dentro de la app**, no recarga silenciosa. "Hay una
  versión nueva · Actualizar". Recargar solo cuando el usuario lo pide, **jamás
  en mitad de un roll** — perderías el registro en curso, que es el pecado
  original de esta app.
- **Número de versión visible** en ajustes. Cuando alguien te diga "no me deja
  apuntarme", lo primero que necesitas saber es qué versión tiene.
- **Compatibilidad hacia atrás de las migraciones, y esto es lo que os va a
  morder.** Hoy hacéis cambios que rompen clientes viejos: renombrar valores de
  enum, cambiar la firma de una función RPC. Con dos usuarios se arregla
  recargando; con veinte, la mitad del gimnasio ve errores el domingo por la
  tarde. La disciplina se llama expandir → migrar → contraer: **añades lo nuevo
  sin quitar lo viejo, esperas un release, y solo entonces quitas**. Cuesta un
  poco de tiempo y elimina una clase entera de fallos.
- **Prueba con Gullo antes de que llegue a los demás.** Cuando haya más de un
  grupo, que los cambios lleguen primero al tuyo.

---

## 3 · Seguridad — el listón mínimo, y dónde está el riesgo de verdad

Tu superficie de ataque es pequeña, pero está concentrada en un punto:

**La RLS es todo tu perímetro.** No hay servidor propio: el navegador habla
directamente con Postgres con una clave pública por diseño. Lo único que separa
los datos de una persona de los de otra son las políticas. Consecuencia directa:
**las pruebas de RLS tienen que ser automáticas y correr en cada cambio**, no una
comprobación manual que alguien recuerda hacer. Es la acción de seguridad con
más retorno que puedes tomar, y hoy no existe.

**Cada `SECURITY DEFINER` es un agujero que has abierto a propósito.** Ya tienes
`registrar_roll_observado` y vienen `unirse_con_codigo` y `apuntarse_a_quedada`.
Mantén la lista corta, comentada y revisada. Hoy cualquier usuario autenticado
puede escribir rolls en el historial de cualquiera; es asumible entre amigos y
deja de serlo con una academia dentro.

**Nada secreto en el cliente. Nunca.** El día que necesites una clave de verdad
—una pasarela de pago, un servicio externo— va en una edge function, no en el
front. Es el error más común y el más caro.

**Dependencias**: `npm audit` y avisos automáticos de actualización. Gratis.

**Recuperación de cuentas y continuidad**: si tú desapareces un mes, ¿quién
administra Gullo? Que haya siempre **dos administradores** por grupo, y que las
credenciales de Supabase, Vercel y el dominio no cuelguen solo de tu correo
personal.

---

## 4 · Privacidad y legal — aquí es donde veo el riesgo que no estás viendo

Estás en la UE, guardando datos de conducta de personas **con nombre y
apellidos**, algunas de las cuales **nunca se han registrado** en tu app —los
contactos tipo "Marc"—. Eso es tratamiento de datos personales de terceros. Con
tres amigos no le importa a nadie; con una academia, sí.

Tres cosas concretas:

**El campo `molestias`.** En `sesiones` guardáis un texto libre de molestias y
lesiones. Eso es **dato de salud**, que en el RGPD es categoría especial y tiene
un listón mucho más alto que el resto. O lo quitas, o lo tratas como lo que es
(consentimiento explícito, y no aparece en nada compartido). Yo lo quitaría hasta
que haya una razón fuerte para tenerlo — y desde luego no debería salir nunca en
un informe de quedada ni en el feed.

**Los menores.** Las academias dan clases infantiles, y es una parte enorme de su
negocio. En cuanto una academia empiece a usar esto, alguien va a querer registrar
a los niños. Datos de menores requieren consentimiento parental y un montón de
cuidado. La decisión sana ahora: **la app es solo para mayores de edad**, dicho
explícitamente, y no lo cambias hasta que haya una razón de negocio que pague el
coste de hacerlo bien.

**Lo básico que hay que tener antes de que entre gente ajena**: un aviso de
privacidad de una página en lenguaje normal, exportar tus datos, borrar tu cuenta
de verdad, y saber decir quién ve qué. No es burocracia: es lo que te permite
enseñárselo a un dueño de academia sin que se ponga nervioso.

Y si algún día cobras: **entidad legal** (autónomo o sociedad), términos de
servicio, y facturación con IVA. Cobrar de forma informal por una app en España
es el tipo de atajo que sale caro.

---

## 5 · Crecimiento, y cómo dejar la puerta del dinero abierta

### El bucle de crecimiento que ya tienes y no has visto

No es la pantalla de análisis. **Es el informe de la quedada.**

El coach registra un open mat → se genera un informe con **ocho personas
nombradas, cada una con su título** → esas ocho quieren verlo → el enlace lleva a
una pantalla que les pide unirse al grupo para ver su perfil. Ese es el bucle
completo, y es el único mecanismo del producto en el que **una persona que usa la
app trae a otra sin que tú hagas nada**.

Consecuencia práctica: el informe merece más cariño del que le darías por su
valor de uso. La tarjeta compartible, el enlace con código de unión, el "mira lo
que hiciste el domingo". Ahí es donde va el esfuerzo de diseño.

### La regla de no escalar todavía

**No metas un segundo gimnasio hasta que Gullo registre cuatro semanas seguidas
sin que tú tengas que recordárselo a nadie.** Si escalas antes, escalas una fuga:
metes gente en un producto que todavía no engancha y quemas la única primera
impresión que tienes con cada academia.

### Qué medir, porque ahora no mides nada

Cuatro números, revisados una vez por semana:

- Rolls registrados por persona activa y semana.
- Qué proporción los registra un observador y cuál el propio practicante. Si el
  observador cae, el producto se está muriendo aunque los totales suban.
- Cuántas personas entran desde un informe compartido.
- Cuántos vuelven a la semana siguiente.

### Monetización: diseñar para que sea posible, sin cobrar ahora

El modelo honesto para esto es **gratis para el practicante, de pago por
academia**. Un particular no paga por un diario de entrenamiento; una academia sí
paga por herramientas que retienen alumnos, porque su problema real es la fuga de
cinturones blancos. Un precio ancla realista en España son 20–40 € al mes por
academia, no por alumno.

Qué va detrás del muro y qué no:

- **Gratis para siempre**: registrar tus rolls y ver tus propios datos. Si cobras
  por esto, matas la captura, y sin captura no hay nada que vender.
- **De pago (academia)**: varios coaches administradores, analítica agregada del
  gimnasio, informes con la marca de la academia, histórico ilimitado,
  exportaciones.

Decisiones de ahora que mantienen esa puerta abierta: `grupos` ya es la unidad
facturable, que es exactamente lo que hacía falta; no construyas nada que asuma
un solo grupo por persona; y mantén separada la analítica personal de la
agregada, porque la segunda es lo que se vende.

Y una que es de criterio: **nada de publicidad**. En un producto que guarda datos
del cuerpo y del rendimiento de la gente, los anuncios queman la confianza que es
justamente tu activo.

---

## 6 · Ciencia de datos, sin humo

Tu activo real aquí es raro y conviene que sepas por qué: **casi todas las apps
de BJJ guardan "entrené 60 minutos, me sentí bien". Tú guardas eventos a nivel de
posición.** Eso es un orden de magnitud más de resolución, y es lo que hace
posible todo lo que viene. Pero solo paga con volumen — otra vez, la fricción del
registro es el cuello de botella de todo.

La restricción honesta: **n es pequeño**. Una persona registra quizá 200 rolls al
año. Cualquier modelo con más de un puñado de parámetros va a sobreajustar y
decir tonterías con mucha seguridad. El valor aquí **no está en el machine
learning**, está en agregación buena, comparación honesta y disciplina con las
muestras pequeñas.

Cuatro etapas, en orden, y cada una útil por sí sola:

**Descriptiva** — dónde atacas, dónde te pillan. Ya está hecho.

**Comparativa** — la que desbloquea el grupo. "Tu tasa de pase desde media
guardia es del 22 %; la media de los blancos de tu gimnasio es del 41 %." No
necesita modelos, necesita población. Es el salto de valor más grande de los
cuatro y llega solo con que haya gente.

**De secuencias** — la matriz de transiciones. "Cuando llegas a cien kilos, montas
el 12 % de las veces; los que finalizan desde ahí pasan antes por rodilla en
barriga." Es minería de secuencias básica, no IA, y es donde empiezan a salir
consejos que un cinturón blanco no ve solo. Ojo: **esto es lo que la columna
`posicion_destino` que tienes pendiente hace posible**, y es la razón de peso para
decidirla.

**Prescriptiva** — el plan de partida contra un rival concreto. "Freezer te pasa
desde media guardia el 60 % de las veces. En tus últimos 20 rolls, tu mejor
recuperación viene de mariposa." Eso es un producto entero, y sale de vistas y
reglas, no de un modelo entrenado.

Un detalle de calidad de datos que ya tienes resuelto y deberías explotar: **los
datos registrados por un observador son mejores que los autoregistrados**, porque
uno no ve su propia espalda ni recuerda los intentos fallidos. Tenéis `origen` en
cada roll. Úsalo para ponderar, y para avisar cuando un perfil está construido
solo con datos propios.

---

## 7 · Innovación, ordenada por lo que cuesta

**Vídeo con marcas de tiempo — hazlo, y no hagas el otro.** El vídeo "analizado
por IA" es un problema de investigación, caro, y además la gente no graba sus
rolls de entrenamiento. Pero hay una versión del 80 % que es casi gratis: si
alguien graba el roll con el móvil y tus eventos ya llevan `segundo_roll`,
**puedes saltar al momento exacto de cada evento**. "Enséñame las tres veces que
me pasaron la guardia el domingo." Cero modelos, valor enorme, y encaja con lo
que ya construiste.

**El mapa colectivo del gimnasio.** Las posiciones donde toda la academia es
débil, para que el coach planifique el mes desde datos en vez de intuición. Esto
no es una feature bonita: **es literalmente lo que una academia pagaría**. Si
tuviera que elegir una sola cosa de esta sección, sería esta.

**El emparejador de open mat.** Quién debería rodar con quién esta tarde, para
que el combate sea competido y los datos útiles. Resuelve un problema real de los
domingos en tu casa, y nadie lo tiene.

**Carga de entrenamiento.** Ya guardas intensidad y volumen; avisar de un pico
brusco es fácil. Pero pisa terreno de salud: enmárcalo como carga de
entrenamiento, nunca como consejo médico ni predicción de lesión.

**Datos de competición y perfiles de luchadores famosos.** Suena bien y yo lo
dejaría para más tarde: raspar resultados de federaciones tiene riesgo legal y de
términos de uso, y te convierte en un producto de contenido, que es otro negocio.
La versión barata y sin riesgo: que la gente marque un roll como "competición" y
compare su propio perfil con el de su categoría dentro de la app.

**Registro por voz.** Ya está en el backlog y sigue siendo la más infravalorada:
vuestro vocabulario es cerrado, o sea que la gramática ya existe.

---

## 8 · Lo que no me has preguntado y deberías

**Tu presupuesto real es de horas, no de euros.** Tienes un trabajo a jornada
completa. Cualquier plan que asuma que estarás disponible un domingo por la noche
va a fallar. La consecuencia práctica: automatiza el aviso de errores, no montes
nada que requiera guardia, y asume unas cinco horas por semana al planificar.

**Pablo.** Sois dos. Hoy es un proyecto de amigos y está perfecto. Pero si algún
día entra dinero, o si uno de los dos se cansa, vais a querer haber hablado antes
de quién es dueño de qué. Media página, ahora, mientras da igual. Es el momento
en que es fácil.

**Soporte.** Cuando a un coach no le entre el login un domingo con doce personas
esperando, ¿a quién escribe? Un número de WhatsApp basta para tres gimnasios y no
para treinta. Pero decide cuál es ahora.

**El arranque en frío.** Una academia nueva abre la app y ve pantallas vacías,
porque no hay datos. Las tres primeras sesiones deciden si se queda o no. Eso
merece diseño explícito: qué ve el día uno, qué ve el día tres, y en qué momento
la app le enseña algo que no sabía.

**Portabilidad de los datos.** Exportar en un formato abierto no es solo ética:
es un argumento de venta con un coach desconfiado, y te obliga a mantener el
esquema limpio.

**Idioma.** Todo está en español y la lengua franca del BJJ es el portugués y el
inglés. Si algún día quieres salir de Barcelona, extraer los textos a un fichero
de traducciones **ahora** cuesta una tarde; hacerlo con la app hecha cuesta
semanas. No traduzcas todavía, pero no incrustes más textos en los componentes.

**El paisaje competitivo.** No sé qué hay ahí fuera hoy y tú tampoco. Antes de
invertir tres meses más, dedica una tarde a mirar qué apps de registro de BJJ
existen, qué cobran y qué les critica la gente en las reseñas. Puedo hacerlo yo si
quieres. Lo importante no es copiar: es saber si tu apuesta por el modo observador
es tan diferencial como creemos.

**Nombre y dominio.** "yujitsu" está bien. Antes de imprimir nada o de hacer
cuentas en redes, comprueba que el dominio y el nombre están libres de conflicto.

---

## 9 · Qué haría yo en los próximos 90 días

**Días 1–30 · Que funcione y no se pierda nada.** Arreglar el login. Recolector
de errores. Copias de seguridad y plan Pro. Indicador de cola y reintentos.
Aviso de versión nueva. Pruebas de RLS automáticas. Quitar o proteger
`molestias`. Aviso de privacidad de una página. Y el bloque social, que ya está
en marcha.

**Días 31–60 · Que enganche.** Los cuatro números medidos cada semana. La tarjeta
del roll y el informe de la quedada, cuidados como el producto de marketing que
son. Arquetipos. El objetivo del mes es uno solo: **que Gullo registre cuatro
semanas seguidas sin que nadie se lo recuerde.**

**Días 61–90 · Que se pueda enseñar.** El mapa colectivo del gimnasio, que es la
pieza que un dueño de academia entiende en diez segundos. Vídeo con marcas de
tiempo. Un segundo gimnasio, uno solo, y observar qué se rompe.

Lo que **no** haría en 90 días: cobrar, hacer app nativa, tocar vídeo con IA,
traducir, o meter más de un gimnasio nuevo.

---

## 10 · ¿Meter al coach como socio?

Pregunta de Felipe: ofrecerle una participación al profesor cuando el proyecto esté
maduro. La respuesta corta es **sí a involucrarlo, no a empezar por la
participación** — y sobre todo, no en ese orden.

### Por qué él es la pieza más valiosa que te falta

**Es la distribución.** La unidad de crecimiento es el gimnasio, y el que decide
la cultura de un gimnasio es el profesor. Si él quiere que esto se use, se usa: le
basta con decir "aquí los open mats se registran". Ninguna cantidad de pulido de
producto sustituye eso, y ataca directamente el único riesgo que mata el proyecto.

**Es la autoridad de dominio.** Las decisiones de vocabulario que llevamos
aparcadas —si se añade `de_rodillas`, si la guardia cuenta como disputa, qué
títulos hacen gracia y cuáles ofenden— son exactamente las que un cinturón negro
con academia decide mejor que dos amigos. Y su nombre hace creíble la taxonomía
ante otras academias, que en jiu-jitsu es una moneda real.

**Es el primer cliente y el socio de diseño a la vez.** El mapa colectivo del
gimnasio, que es lo único que una academia pagaría, necesita que un coach te diga
si le sirve. Construirlo sin él es adivinar.

### Los cuatro riesgos, y el cuarto no es obvio

**El capital es lo más caro que tienes y todavía no tienes nada.** Regalar un
trozo de algo que aún no funciona es baratísimo en euros y carísimo en señal: no
se puede desregalar. La regla sana es que **el capital paga trabajo futuro
comprometido, no entusiasmo pasado**.

**Sus incentivos no son los tuyos.** Él quiere que su academia prospere. Eso puede
significar querer features que solo sirven a Gullo, o exclusividad, o incomodidad
con que se lo vendas a otra academia de Barcelona. Si es socio, eso es un veto que
regalaste.

**La asimetría de aportación.** Vosotros construís de forma continua; el respaldo
es valioso pero se da una vez y el siguiente coach lo da igual.

**Y el que no es evidente: es un conflicto de interés con la privacidad que
acabamos de diseñar.** Estamos montando controles precisamente para que cada uno
decida quién ve sus estadísticas. Un coach que además es dueño del producto tiene
un incentivo estructural a querer verlo todo. Si entra como socio, ese conflicto
queda dentro de la empresa en vez de fuera. Se puede gestionar, pero hay que verlo
antes y no después.

Y uno personal que no es de negocio pero pesa: **ahora es tu profesor.** Si además
es tu socio, un desacuerdo sobre el roadmap se convierte en un desacuerdo en el
sitio al que vas a entrenar. Merece la pena pensar si quieres eso.

### La secuencia que yo seguiría

**Primero, y ya: socio de diseño, sin papeles.** Enséñaselo. Pregúntale qué querría
ver. Dale el mapa colectivo cuando exista. Coste cero, y te da la información que
necesitas antes de cualquier otra cosa: **si le interesa de verdad o solo está
siendo amable.**

**Después, cuando funcione en Gullo: un papel con nombre y algo concreto que no sea
capital.** Asesor técnico, primera academia, gratis para siempre, su marca en los
informes, y **voto de veto en el vocabulario**. Si quieres alinearlo con el
crecimiento, **un porcentaje de los ingresos de las academias que él traiga** — no
capital. Eso es precioso aquí: no cuesta nada hasta que hay dinero, le alinea con
vender, es fácil de terminar, y **no le da gobierno**.

**Y solo si quiere trabajar en esto de verdad** —vender, hacer el onboarding de
otras academias, ser la cara— entonces capital, con vesting y periodo de carencia.
Porque para entonces estarías pagando trabajo futuro, que es para lo que sirve el
capital.

### Dos condiciones previas

**Felipe y Pablo primero.** No puedes meter limpiamente a un tercero cuando los dos
primeros no habéis definido quién es dueño de qué. Esa media página que estaba en
prioridad media pasa a ser **bloqueante de esta conversación**.

**Y define el disparador, no lo dejes en "cuando estemos maduros".** Yo lo pondría
en tres hechos: Gullo registra cuatro semanas seguidas sin que nadie lo recuerde ·
el mapa colectivo existe y él lo ha mirado y ha pedido algo · una segunda academia
ha preguntado por la app. Hasta entonces no hay nada sobre lo que asociarse, y la
conversación prematura te quema la única primera vez que puedes proponérselo.

**Y hay un dato de la primera semana que apunta justo aquí:** de los 16 rolls
reales registrados, **los metió todos Felipe.** Pablo, Nicolas y Sasza no han
registrado ninguno por su cuenta. O sea que el problema que el coach resolvería
—que registrar sea lo que se hace aquí, no un favor que le hace uno al proyecto—
es exactamente el que ya se está manifestando. Eso **adelanta** el momento de
hablar con él, aunque sea como socio de diseño y no como socio de nada más.

### Una alternativa que quizá es mejor que la sociedad

Que sea **tu primer cliente que paga.** Un coach que suelta 30 € al mes valida más
y ata menos que un coach que tiene el 10 %. Y hay una diferencia que importa: **los
clientes te dicen la verdad; los socios te dicen lo que les gustaría que fuera
verdad.**

---

## Una última cosa

Lo que tienes montado en tres semanas —un modelo de eventos coherente, escritura
sin conexión, modo observador y un marcador en vivo— está por encima de lo que la
mayoría de proyectos de este tipo consigue en seis meses. El riesgo no es
técnico. El riesgo es que sigas construyendo features porque construir es
divertido, y no te enteres a tiempo de si la gente registra o no.

Todo lo de arriba es, en el fondo, una manera de comprarte información sobre esa
única pregunta.
