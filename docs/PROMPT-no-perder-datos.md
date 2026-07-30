# Prompt para Claude Code — que no se pierda ni un roll

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a blindar el registro en vivo. Tres cosas pequeñas que atacan el mismo riesgo:
**perder lo que alguien ya se molestó en registrar.** Nada de esto toca el esquema
ni la base — es todo cliente. Lee antes `CLAUDE.md`.

## Por qué esto va antes que cualquier feature

yujitsu es un producto de captura de datos. Sus dos únicos riesgos mortales son
que nadie registre, y **que se pierda una vez lo registrado**. Lo segundo es peor
de lo que parece: la confianza en un diario no se recupera. Alguien que pierde una
sesión no vuelve a registrar con ganas nunca más, y con ella se van los heatmaps,
los logros y todo lo demás.

## 1 · La pantalla no se puede apagar durante un roll

Es el fallo práctico número uno del registro en vivo y cuesta cinco líneas: el
móvil se duerme a los dos minutos, el observador se da cuenta al final, y medio
roll se ha perdido.

- `navigator.wakeLock.request('screen')` al empezar un roll; liberarlo al
  cerrarlo, al salir de la pantalla y al desmontar.
- **Vuelve a pedirlo en `visibilitychange`**: el bloqueo se pierde solo cuando la
  pestaña pasa a segundo plano y no se recupera si no lo pides otra vez. Ese es el
  detalle que casi siempre se olvida.
- Envuelto en `try/catch` y con comprobación de existencia: Safari viejo y
  navegadores en escritorio no lo tienen, y ahí simplemente no pasa nada.
- Y **enséñalo**: un indicador discreto de que la pantalla se mantiene encendida.
  Si no se ve, nadie sabe si funciona; y si falla, tampoco.

## 2 · La cola no puede rendirse en silencio

Hoy la cola de salida (`src/lib/db.ts`, `src/lib/sync.ts`) sube cuando hay red.
Lo que falta es lo de alrededor.

- **Reintentos con espera creciente**: 1s, 2s, 5s, 15s, 60s, y después cada cinco
  minutos. Con un tope de intentos por elemento, pero **el elemento nunca se
  descarta**: cuando se agota, pasa a "necesita atención", no a la basura.
- **Distinguir el fallo de red del fallo de datos.** Un 5xx o una desconexión se
  reintentan para siempre. Un 4xx —una violación de RLS, una clave foránea— **no
  se arregla reintentando**: eso se marca como error y se enseña, porque si no la
  cola se queda dando vueltas eternamente sobre algo que nunca va a entrar.
- **Reintenta al recuperar la conexión** (`online`) y al volver a primer plano,
  no solo por temporizador.
- No rompas los invariantes: los ids se generan en el cliente y se sube con
  `upsert`, nunca `insert`, y el orden por tablas es `sesiones` → `rolls` →
  `eventos`.

## 3 · La cola tiene que verse

La píldora de sincronización que hay en `src/components/Marco.tsx` es el sitio.

- Estados claros: **al día** · **subiendo…** · **3 sin subir** · **1 con error**.
- **Tocable**: abre un detalle con qué hay pendiente, desde cuándo, y un botón de
  reintentar ahora.
- Para lo que falló con un 4xx, que se pueda **ver el error y descartar ese
  elemento a propósito** — decisión del usuario, nunca automática.
- Si hay algo pendiente, que **avise antes de cerrar la pestaña**
  (`beforeunload`), como hace cualquier editor con cambios sin guardar.

## Cómo lo verificas, y esto no se hace leyendo el código

1. `npm run build` pasa.
2. **Prueba del avión**: registra un roll entero con el modo sin conexión de las
   herramientas del navegador activado. La píldora tiene que decir cuántos hay
   pendientes. Vuelve a poner la red: se suben solos y la píldora vuelve a "al
   día". Comprueba en la base que llegó **todo**, no solo la sesión.
3. **Prueba del 4xx**: fuerza un fallo que no sea de red —por ejemplo un evento
   con un `roll_id` que no existe— y comprueba que **no** entra en bucle de
   reintentos y que sale como error visible.
4. **Prueba de la pantalla**: empieza un roll en el móvil, déjalo dos minutos sin
   tocar nada. La pantalla sigue encendida. Cambia de app y vuelve: sigue
   encendida — ahí es donde falla si no repites la petición.
5. **Prueba del cierre**: con algo pendiente, intenta cerrar la pestaña y
   comprueba que avisa.
6. Recarga la app con elementos en la cola: **siguen ahí**. Están en IndexedDB, no
   en memoria; si se pierden al recargar, algo está mal.
7. Probado a 390px.

## Fuera de alcance

**El recolector de errores** (Sentry o equivalente): hace falta una cuenta y una
clave que tiene que dar Felipe. Déjalo anotado.

**Copias de seguridad de la base**: es del lado del servidor y es otra decisión.

**No toques el esquema ni ninguna migración.** Esto es cliente entero.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios— y tacha lo que corresponda en `docs/BACKLOG.md`.
