# Prompt para Claude Code — tema Gullo y sistema de diseño

**Antes de pegarlo:** guarda el fichero `yujitsu-tema-gullo.html` que te pasé en el
repositorio como **`docs/TEMA-GULLO.html`**. Es la referencia visual de este
bloque y Claude Code la necesita delante. Copia todo lo que hay debajo de la
línea.

---

Vas a aplicar el **tema visual de Gullo Jiu-Jitsu** y a formalizar el sistema de
diseño de la app. Lee antes `CLAUDE.md`.

## La referencia es un fichero, no una descripción

Abre **`docs/TEMA-GULLO.html`** en el navegador. Tiene la paleta medida, la tabla
de contrastes, la pantalla de entreno maquetada en oscuro y en claro, y los
avatares de cinturón. **Es el diseño aprobado.** Tu trabajo es portarlo a la app,
no reinterpretarlo. Si algo te parece mejorable, dilo antes de cambiarlo.

## La paleta, medida del logo

```
verde de marca      #458c50   idéntico en el logo, la web y las fotos de Gullo
verde aclarado      #55a562   para texto pequeño y enlaces sobre fondo oscuro
verde oscuro        #33693c   estados pulsados y bordes
hueso               #f1f0ee   fondo del tema claro (el de su web)
naranja Gullo       #ff9058   disponible, de momento sin uso semántico
```

## La regla que gobierna todo esto: el verde es marca, no es dato

**No metas el verde en ningún gráfico, barra, celda de heatmap ni marcador.**
Azul `#3987e5` para "yo" y naranja `#d95926` para el rival se quedan exactamente
como están.

Dos razones, y las dos importan:

1. **Verde contra naranja es el par que se cae con el daltonismo más común.**
   Afecta a cerca del 8 % de los hombres y un gimnasio de BJJ es mayoritariamente
   hombres. Azul contra naranja sobrevive.
2. Cuando el tema sea por grupo, si los colores de datos fueran tematizables una
   academia podría elegir un acento que deje ilegible su propio heatmap.

El verde va en: cabecera y marca, pestaña activa, botón principal, enlaces,
píldora de sincronización correcta, y acentos de foco.

## Tres cosas concretas que salen de medir el contraste

**Los botones verdes llevan texto oscuro, no blanco.** Blanco sobre `#458c50` da
4,10 y no pasa AA; negro da 4,80 y sí. La web de Gullo lo usa en blanco pero solo
con tipografía enorme, donde el listón es más bajo.

**Para texto pequeño y enlaces sobre el fondo oscuro, usa `#55a562`** (6,43), no
el de marca (4,74, justo justo).

**Hay dos verdes peleándose y hay que fundirlos.** Hoy existe
`--good:#0ca30c` para la píldora de sincronización, que no tiene nada que ver con
el de marca. La app se queda con **un solo verde**, el de Gullo y sus variantes.

## Fase 1 · Tokens en una sola fuente de verdad

`src/app/globals.css` ya tiene los tokens centralizados, que es un buen punto de
partida. Lo que falta:

- Separar los tokens en tres familias con nombres que digan su trabajo:
  **marca** (tematizable), **datos** (nunca tematizable) y **estado**.
- Escala tipográfica y de espaciado declaradas, en vez de tamaños sueltos por
  componente. No hace falta nada sofisticado: seis tamaños y una escala de
  espaciado de 4px.
- Radios y sombras como tokens.

Que quede escrito en un comentario de la cabecera del fichero cuáles son
tematizables y cuáles no. Es la clase de cosa que alguien rompe con buena
intención.

## Fase 2 · Tema por grupo

El acento sale de **un solo sitio**, y el grupo elige **solo el acento**, nunca la
paleta entera.

- Si la tabla `grupos` ya existe (bloque social), añade
  `grupos.color_acento text` con `#458c50` por defecto, y que el tema se resuelva
  del grupo activo del usuario.
- **Si `grupos` todavía no existe**, no lo inventes: deja el acento en una única
  constante con el verde de Gullo, y estructúralo para que enchufarlo a la
  columna sea cambiar una línea. Dilo en el resumen.

Valida el color que llegue de la base: si no es un hex válido, cae al verde por
defecto. Nunca inyectes un valor de la base directo en un `style` sin comprobarlo.

## Fase 3 · El tema claro es el que manda

**El claro es el tema por defecto de la app.** Decisión de Felipe, y es coherente
con la identidad de Gullo, que es clara: hueso `#f1f0ee` con el verde encima. Es
también el tema de los informes de quedada y las tarjetas compartibles, así que la
app y lo que se comparte se ven como la misma cosa.

Hoy `globals.css` arranca con `color-scheme:dark` y todos los tokens en oscuro. Eso
hay que darle la vuelta: **el claro es la base, el oscuro es la variante.** No lo
hagas con un filtro invertido ni derivando colores del oscuro — el oscuro es una
paleta elegida, con sus propios valores, y ya está definida en
`docs/TEMA-GULLO.html`.

Detalle que te ahorra trabajo: el hueso de Gullo es casi idéntico al fondo del
panel de análisis ya aprobado (`docs/BJJ-Analisis-DEMO.html`), así que
**reconcilia los dos en un solo conjunto de tokens claros** en vez de mantener dos
paletas parecidas.

El oscuro se mantiene entero y accesible, y se elige de dos maneras: respetando
`prefers-color-scheme` del sistema, y con un interruptor manual que se recuerda.
El orden es: preferencia guardada del usuario → preferencia del sistema → claro.

**Dos cosas que hay que comprobar al invertir el defecto**, porque son las que se
rompen:

- **Los colores de datos sobre fondo claro.** Azul `#3987e5` y naranja `#d95926`
  están elegidos contra el oscuro. Sobre el hueso hay que usar los del panel de
  análisis aprobado, `#2a78d6` y `#eb6834`, que es exactamente para lo que
  existen.
- **La rampa del heatmap se invierte entre temas.** En claro, el extremo "cerca de
  cero" es el tono clarito; en oscuro, el oscuro. Está explicado en el prompt de
  análisis y es un fallo que ya cometí una vez.

## Fase 4 · Avatares de cinturón

Un componente, SVG generado, sin imágenes. Está implementado en el fichero de
referencia; puedes copiar la lógica.

Un cinturón de BJJ no es un anillo de un color: lleva **una barra donde van los
grados**, negra en los cinturones de color y **roja en el negro**. El avatar es
eso: aro del color del cinturón + barra + grados en blanco encima de la barra +
iniciales en el centro.

Requisitos que no son estéticos:

- **El negro necesita su barra roja.** Un aro negro sobre el fondo oscuro es
  invisible.
- **El blanco necesita filo.** Un aro blanco sobre el hueso claro también
  desaparece. Filo de 1px por dentro y por fuera del aro, en los dos temas.
- Los grados repartidos **dentro** de la barra, no pegados a un lado, para que
  cuatro grados se distingan de uno sin contarlos.
- `aria-label` con el nombre, el cinturón y los grados. Un avatar que solo
  comunica por color no comunica.
- La insignia del arquetipo va **al lado**, no dentro del aro.

Pruébalo con los cinco cinturones en los dos temas.

**La foto de perfil no entra aquí.** Va encima como opción en otro bloque
—Supabase Storage, recorte y reescalado en el cliente—, manteniendo el aro del
cinturón. No montes el cubo ni las políticas todavía.

## Fase 5 · Icono, splash y manifest

Hoy son provisionales. **Pídele a Felipe el logo** en PNG o SVG en vez de dibujar
algo: lo tiene. Genera los tamaños del manifest, el icono enmascarable y el color
de tema, con el verde de marca.

## Verificación

1. `npm run build` pasa.
2. **Un script que compruebe los contrastes**, no un ojo. Que falle si alguna
   combinación de texto sobre fondo de la app baja de 4,5. Déjalo en el
   repositorio: es la única forma de que esto no se degrade solo.
3. **Ningún verde en los datos.** Búscalo: que no aparezca el token de marca en
   heatmaps, barras, marcador ni leyendas.
4. **Un solo verde** en toda la hoja de estilos.
5. Los cinco cinturones distinguibles en oscuro y en claro, comparados contra
   `docs/TEMA-GULLO.html`.
6. Objetivos táctiles de **44px mínimo** en todo lo que se toque durante un roll.
7. Probado a 390px de ancho, en los dos temas.
8. **Arranque en claro**: instalación nueva, sin preferencia guardada y con el
   sistema en oscuro, la app abre en claro. Y el interruptor manual sobrevive a
   cerrar y reabrir.
9. **No toques la paleta de datos del panel de análisis.** Es diseño aprobado y
   validado para daltonismo.

## Fuera de alcance

Pictogramas de las 24 posiciones, modo tatami, vibración al registrar, estados
vacíos, tipografía de display y onboarding. Están en el backlog y van cada uno en
su bloque. Este es el cimiento: tokens, tema y avatares.

Cuando termines, actualiza `CLAUDE.md` con la regla del verde —marca sí, datos
no— y con qué tokens son tematizables, y tacha lo que corresponda en
`docs/BACKLOG.md`.
