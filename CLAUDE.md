# BJJ Tracker — contexto del proyecto

App para registrar rolls de jiu-jitsu y analizar el juego. La construyen Felipe y
Pablo, que entrenan juntos en Barcelona. Este fichero lo lee Claude Code
automáticamente: aquí está lo que hay que saber antes de tocar nada.

**Idioma:** el código, los comentarios y la interfaz están en español. Los
identificadores de base de datos van sin acentos (`sumision`, `posicion`).

---

## La decisión que sostiene todo: se modelan eventos, no resultados

Cada acción de un roll es una fila en `eventos` con cinco datos: **quién** la hizo
(`actor`), **qué** hizo (`tipo`), **desde dónde** (`posicion` + `rol`), **a qué
articulación** (`objetivo`) y **con qué técnica** (`tecnica_id`).

De ahí salen, sin tablas nuevas, el heatmap ofensivo, el defensivo, el análisis
por guardia, el head-to-head y la validación de retos. Si aparece una feature que
parece pedir una tabla nueva, primero comprobar si es una vista sobre `eventos`.

### `posicion` + `rol`: leerlo bien

La posición es **física** (montada, guardia cerrada…) y `rol` dice dónde está el
**actor del evento**, no el dueño del roll.

| posición | rol | significado |
|---|---|---|
| `guardia_cerrada` | `abajo` | está jugando la guardia |
| `guardia_cerrada` | `arriba` | está dentro intentando pasarla |

Consecuencia importante: al espejar un roll observado al compañero **solo cambia
`actor`**. `posicion` y `rol` describen a la misma persona física en las dos
filas. Está implementado en `espejar_roll()`.

---

## Estado actual

**Fase 1 terminada y desplegada.** Auth por magic link, pestaña de practicantes y
pantalla de logging, con escritura local-first.

- Supabase: proyecto `idzlxkxeadrcolcnmoeo`, org `yujitsu`, eu-west-1, plan gratuito
- Vercel: `yujitsu-eight.vercel.app`, plan Hobby
- GitHub: `fyuji88/yujitsu`, privado, rama `main`
- 8 migraciones aplicadas (`bjj_01` … `bjj_08`), copia en `db/`

**Sin datos reales todavía.** Solo el diccionario: 24 posiciones, 63 técnicas.

---

## Invariantes que no hay que romper

**Los ids se generan en el cliente** (`crypto.randomUUID()`) y la cola sube con
`upsert`, nunca `insert`. Es lo que hace que reintentar tras perder cobertura no
duplique filas. Si alguien cambia esto a `insert`, se rompe la garantía.

**La cola sube por tablas en orden**: `sesiones` → `rolls` → `eventos`. Un evento
que llegue antes que su roll lo rechaza la clave foránea.

**La interfaz solo ofrece lo que la RLS permite.** En practicantes, el botón de
editar aparece solo en tu ficha y en los contactos que creaste tú — la misma
condición que la política de Postgres. Si la UI ofrece más, el usuario ve errores
en vez de botones ausentes.

**Nada escribe directo contra Supabase salvo `practicantes`.** Sesiones, rolls y
eventos pasan siempre por `encolar()` en `src/lib/db.ts`.

**El vocabulario es cerrado.** No añadir valores a los enums sin decirlo: los
heatmaps dependen de que Felipe y Pablo usen las mismas palabras. Los códigos
feos viven en la base; las etiquetas humanas, en la interfaz.

---

## Mapa del código

```
src/lib/bjj.ts             vocabulario + máquina de estados del roll  ← el corazón
src/lib/db.ts              IndexedDB (Dexie) + cola de salida
src/lib/sync.ts            vaciado de la cola
src/lib/database.types.ts  tipos del esquema (subconjunto escrito a mano)
src/components/Marco.tsx   sesión, pestañas, píldora de sincronización
src/app/login              entrada por magic link
src/app/auth/callback      vuelta del enlace
src/app/practicantes       alta y edición del roster
src/app/entreno            el logging
db/                        el esquema SQL, igual que lo desplegado
docs/                      decisiones de producto y backlog
```

`src/lib/bjj.ts` es donde está la inteligencia: `accionesPosibles()` decide qué
botones se ven según la posición, y `aplicarAccion()` devuelve el evento y el
estado siguiente. Cambiar el flujo de logging es tocar ahí, no en la pantalla.

---

## Cosas que ya nos mordieron

**`transicion` no existe como tipo de evento.** Pasar de cien kilos a montada no
es ninguno de los seis tipos, así que hoy se actualiza la posición sin registrar
evento. Se pierde información, y bloquea los puntos estilo IBJJF. Decisión
pendiente de Felipe y Pablo, no la tomes tú.

**Borrar un practicante fallaba** por el choque entre `ON DELETE CASCADE` en
sesiones y `ON DELETE SET NULL` en `rolls.oponente_id`. Resuelto difiriendo dos
claves foráneas (migración `bjj_06`). Si se recrean esas FK, mantener el
`deferrable initially deferred`.

**PKCE no sirve para magic links** que se piden en un dispositivo y se abren en
otro. El cliente usa `flowType: 'implicit'` a propósito (`src/lib/supabase.ts`).

**El helper de RLS vive en el esquema `private`**, no en `public`, para que
PostgREST no lo publique en `/rest/v1/rpc/`.

**Las vistas llevan `security_invoker = on`.** Sin eso cualquiera leería los
heatmaps de otro a través de la vista.

---

## Cómo verificar que algo funciona

El proyecto tiene poca red de seguridad automática, así que:

- `npm run build` compila y hace typecheck en estricto. Que pase no es opcional.
- `stub-supabase.py` levanta una imitación de Supabase en `127.0.0.1:54321` con
  los ids reales de las técnicas. Sirve para recorrer la app sin tocar la base
  de producción y para capturar en `/tmp/capturado.json` lo que escribiría.
- Para cambios de esquema, probar contra un Postgres local antes de aplicar la
  migración al proyecto real.

No des por bueno un cambio de logging sin recorrer un roll entero en el
navegador: la máquina de estados tiene caminos que el typecheck no cubre.
