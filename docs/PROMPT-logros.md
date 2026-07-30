# Prompt para Claude Code — logros

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a implementar los **logros**: un catálogo fijo de hazañas que se ganan
registrando rolls, con su colección en el perfil, su ranking mensual y su
aparición en el feed. Lee antes `CLAUDE.md`.

## Lo que ya está decidido y no se reabre

Todo el diseño está en **`docs/04-logros-privacidad-y-grupo.md`** y la referencia
visual en **`docs/LOGROS-diseno.html`** — ábrela en el navegador, es el diseño
aprobado. Además tienes dos ficheros que te ahorran el trabajo ambiguo:

- **`docs/logros-catalogo.sql`** — las 28 filas del catálogo, con los nombres
  cerrados y la especificación de cada predicado. **Pégalo tal cual** en la
  migración; no reinventes nombres ni añadas logros.
- **`docs/logros-iconos.json`** — los pictogramas, con las reglas de dibujo.

Lo que ya está cerrado, para que no lo replantees:

**Los nombres van en español**, porque son chistes y los chistes no se traducen.
Pero en la base va la `clave` y el nombre visible sale de un **fichero de textos**
(`src/lib/textos/logros.es.ts` o equivalente), para que cambiar de idioma sea
editar un fichero y no una migración. Es también el primer paso de la
internacionalización que está en el backlog.

**Los iconos son pictogramas de línea propios, no emoji.** Un emoji se dibuja
distinto en cada sistema operativo y la tarjeta compartible tiene que verse igual
en todos los móviles. Los emoji se quedan solo para los arquetipos. Un solo color
de acento, y **oro únicamente en el borde de los raros**.

## Lo que hace que esto NO sea los retos otra vez

Ya existen `retos` y `reto_participaciones`. **No son lo mismo y no se
fusionan:**

| | Retos | Logros |
|---|---|---|
| Quién los define | una persona, con `regla` libre | catálogo fijo |
| Ventana | fechas de inicio y fin | siempre |
| Objetivo | una cantidad a alcanzar | ninguno: se acumulan |
| Progreso | **guardado** en `reto_participaciones` | **derivado**, nunca guardado |

Los logros **se derivan**, como los puntos y como el heatmap. Si mañana se
corrige un evento mal registrado, los logros se corrigen solos; un contador
guardado se queda viejo y nadie se entera. Con vuestro volumen el coste es
irrelevante; si algún día molesta, se materializa la vista — pero no se guarda un
contador a mano.

(Lo que sí es una buena idea para más adelante, y **no ahora**: un reto cuyo
`regla` sea "consigue el logro X N veces". Anótalo en el backlog.)

## Fase 1 · Esquema

Migración **`bjj_21_logros`** (la última aplicada es `bjj_20_acento_del_grupo`).

```sql
create type bjj_familia_logro as enum ('defensa','ataque','estilo','constancia','cachondeo');
create type bjj_rareza_logro  as enum ('comun','poco_comun','raro');
create type bjj_ambito_logro  as enum ('roll','quedada','semana','mes');

logros                          -- catálogo, NO datos de usuario
  clave text primary key
  nombre text · descripcion text · descripcion_tecnica text
  familia bjj_familia_logro · rareza bjj_rareza_logro · ambito bjj_ambito_logro
  requiere_observador boolean not null default false
  solo_nogi boolean not null default false
  min_volumen jsonb not null default '{}'
```

Y las vistas, con `security_invoker = on` como todas:

```
v_logros_conseguidos(practicante_id, clave, ambito, ref_id, fecha)
v_logros_practicante(practicante_id, clave, veces, veces_verificadas, primera_vez, ultima_vez)
v_logros_mes(grupo_id, mes, clave, practicante_id, veces)
```

`ref_id` es la instancia del ámbito: el `roll_id`, el `quedada_id`, o la fecha de
inicio de la semana o el mes. Eso es lo que hace que "veces" sea contable sin
duplicar.

**`ambito` no es decorativo.** Un logro de ámbito `roll` se evalúa roll a roll;
uno de `quedada` necesita todos los rolls de esa quedada; uno de `semana` o `mes`
necesita la ventana entera. "Veces conseguido" es **el número de instancias del
ámbito** en las que el predicado se cumplió, nunca el número de eventos.

`logros` es catálogo público: RLS activada con lectura para `authenticated`, y
escritura solo por migración.

## Fase 2 · La regla del sesgo, que es lo más importante de todo esto

Los datos autoregistrados están sesgados y el sesgo va a favor de quien registra:
no ves tu propia espalda, y no recuerdas los intentos que fallaste. Un logro es
moneda pública y comparable, así que acuñarla con datos inflados **premia a quien
registra mal**.

Pero el sesgo no afecta a todos los logros igual, y esa es la clave:

> **Los logros que se definen por la AUSENCIA de algo se inflan solos con no
> registrar el evento. Los que se definen por algo que PASÓ, no.**

`IMPASABLE` es "no hubo ningún pase" — se consigue gratis olvidándose de registrar
el pase. `RELÁMPAGO` es "hubo una sumisión antes del minuto" — hubo que registrarla
activamente.

Implementación: **los logros con `requiere_observador = true` solo cuentan en rolls
con `origen = 'observador'`.** Está ya marcado en el catálogo, y son **5 de 28**: `impasable`,
`muro`, `cuello_de_acero`, `sin_marcar` y `limpio`. No lo apliques a los demás.

Y la procedencia **se enseña, no se esconde**:

- En la colección: `IMPASABLE ×14 · 5 verificados 👁`.
- En el ranking, un interruptor que **por defecto cuenta solo los verificados**.
  Ese interruptor hace un trabajo extra: le explica a la gente por qué importa el
  modo observador sin ningún tutorial.

## Fase 3 · Dónde se ve

**En el perfil, la colección completa.** Los conseguidos con su cuenta, y **los no
conseguidos también, apagados y con su descripción**. Un logro que no sabes que
existe no te motiva: ver "LA CADENA · pasas, montas y tomas la espalda" apagado es
lo que hace que un martes intentes justo eso. Es la misma razón por la que en el
mapa del juego se dejan las posiciones vacías a la vista.

**El ranking del mes**, por logro, ordenado por veces conseguido, con la fila del
usuario resaltada. Reinicio mensual.

**Los de `cachondeo` solo existen si `grupos.modo_cachondeo = true`.** Ni se
evalúan ni se enseñan si está apagado.

**`solo_nogi`**: `piernas` solo cuenta en sesiones nogi.

## Fase 4 · El feed: agregar, no inundar

Esto es una decisión de producto tomada con números, así que no la cambies. Un
elemento de feed por logro serían **unas 150 entradas semanales** con doce
personas — y eso entierra el informe de la quedada, entierra quién se apunta, y se
lleva por delante las reacciones, porque nadie pone 🔥 en el elemento número
noventa.

**La unidad del elemento es la sesión, y los logros viajan dentro:**

> **Pablo registró 6 rolls anoche** · IMPASABLE ×2 · MURO · RELÁMPAGO

Nada queda invisible, que era el punto. Y encima se lee mejor.

**Con elemento propio, solo cuatro casos**, porque son noticia: la **primera vez**
que alguien consigue un logro · los **números redondos** (×5, ×10, ×25, ×50) · el
**primero del grupo** en conseguirlo aunque para él no sea la primera vez · y los
de rareza **`raro`**, siempre. Más el **cierre de mes**, un elemento único con el
ranking.

Añade los tipos nuevos a `v_feed` sin romper los que ya hay.

**El brillo va en el momento, no en el icono:** una animación corta al desbloquear.
Un icono con degradado brilla siempre y deja de significar nada; medio segundo de
animación brilla una vez y se recuerda.

## Los invariantes que no puedes romper

- **Nada se guarda: los logros se derivan.** Ni contadores ni tablas de
  "conseguidos".
- **Todas las vistas con `security_invoker = on`.** Sin eso cualquiera lee los
  logros de otro grupo.
- La lectura ya está recortada por grupo (`bjj_15`). No la toques, y comprueba que
  los logros la respetan: no debes poder ver los logros de alguien que no comparte
  grupo contigo.
- **Los ids se generan en el cliente** y la cola sube con `upsert`. Los logros no
  escriben nada, así que esto no te afecta — pero no lo rompas de paso.
- Los textos visibles viven en el fichero de textos, no incrustados en los
  componentes.

## Cómo lo verificas

1. `npm run build` pasa, typecheck estricto incluido.
2. **Un test por logro, con un roll fabricado que lo cumple y otro que no.** 28
   logros, 56 casos. Es tedioso y es exactamente donde se esconden los errores de
   los predicados: `>=3` contra `>3`, contar intentos fallados o no, olvidar la
   guarda de volumen.
3. **Las guardas de volumen, probadas.** Un roll donde nunca jugaste guardia **no**
   consigue `IMPASABLE`. Un roll con un solo intento **no** consigue nada de ratio.
4. **La regla del observador, probada.** El mismo roll con `origen = 'propio'` y
   con `origen = 'observador'`: los **5** logros de ausencia solo cuentan en el
   segundo. Los otros **23** cuentan en los dos.
5. **Los ámbitos, probados.** `EL ARTISTA` con tres sumisiones distintas repartidas
   en **dos quedadas** no cuenta; en una sola, sí.
6. **Con los datos de demo que ya hay en la base** —Goku tiene 138 rolls—, saca su
   colección y mírala con ojo crítico: si sale con veinte logros a cientos de
   veces, algún predicado está mal. Compárala con lo que dice
   `docs/LOGROS-diseno.html`.
7. **La RLS**, con `set local role authenticated` y el claim de un usuario: los
   logros de alguien de otro grupo devuelven cero filas.
8. Probado a 390px de ancho, en tema claro y oscuro.
9. Migración **primero contra un Postgres local** (`db/README.md`). Producción
   tiene datos reales que Felipe quiere conservar.

## Fuera de alcance

**Los arquetipos.** Van en su propio bloque, aunque comparten la idea de insignia.

**Las insignias en la tarjeta compartible y en el informe de la quedada.** Se
enganchan después; primero que los logros existan y sean correctos.

**Notificaciones push.** No hay infraestructura. El feed es el canal.

**El ranking unificado del grupo** (los cuatro componentes con la progresión contra
ti mismo). Es otro bloque, y no lo montes aquí aunque los logros sean uno de sus
ingredientes.

## Una cosa que no decides tú

Si al escribir los predicados encuentras que **alguno del catálogo es ambiguo o
imposible con los datos que hay**, no lo reinterpretes: dilo, propón la
alternativa, y déjalo fuera de la migración hasta que Felipe lo cierre. Un logro
mal definido que ya está contando en el ranking de alguien es peor que un logro
que falta.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
son obligatorios— y tacha lo que corresponda en `docs/BACKLOG.md`.
