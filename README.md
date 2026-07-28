# BJJ Tracker — app (Fase 1)

PWA de logging: auth por magic link, gestión de practicantes y registro de rolls
con la máquina de estados contextual. Escritura local-first: todo entra primero
en IndexedDB y sale hacia Supabase cuando hay red.

## Arrancar

```bash
npm install
cp .env.local.example .env.local     # y rellena las dos variables
npm run dev
```

Las dos variables salen del panel de Supabase (Project Settings → API), o con:

```bash
npx supabase projects api-keys --project-ref idzlxkxeadrcolcnmoeo
```

## Desplegar

Vercel lo detecta sin configuración. Solo hay que meter las dos variables de
entorno en el proyecto y añadir la URL de producción en Supabase →
Authentication → URL Configuration → Redirect URLs, como
`https://<tu-dominio>/auth/callback`. Sin eso, el magic link rebota.

## Cómo está montado

```
src/lib/bjj.ts             el vocabulario y la máquina de estados del roll
src/lib/db.ts              IndexedDB (Dexie) + cola de salida
src/lib/sync.ts            vaciado de la cola contra Supabase
src/lib/database.types.ts  tipos del esquema
src/components/Marco.tsx   sesión, pestañas y píldora de sincronización
src/app/login              entrada por magic link
src/app/practicantes       alta y edición del roster
src/app/entreno            el logging
public/sw.js               service worker (solo el esqueleto; los datos van en IndexedDB)
```

### Tres decisiones que conviene no deshacer

**Los ids se generan en el cliente.** Cada fila lleva su UUID desde el móvil, y
la cola sube con `upsert` en vez de `insert`. Por eso reenviar es seguro: si no
sabemos si la fila llegó, la mandamos otra vez y Postgres la reconoce en lugar
de duplicarla. Es lo que hace que perder la cobertura a mitad de sincronización
no rompa nada.

**La cola sube por tablas en orden**: sesiones, luego rolls, luego eventos. Un
evento que llegue antes que su roll lo rechaza la clave foránea.

**La interfaz solo ofrece lo que la RLS permite.** En la pestaña de practicantes,
el botón de editar aparece únicamente en tu ficha y en los compañeros que diste
de alta tú — la misma regla que aplica la base. Si la interfaz ofreciera más,
el usuario vería errores en vez de botones deshabilitados.

## Probar sin salir a internet

`stub-supabase.py` imita GoTrue y PostgREST en `127.0.0.1:54321` con los datos
semilla reales del proyecto. Sirve para recorrer la app entera sin conexión y
para capturar en `/tmp/capturado.json` exactamente lo que la app escribiría.

```bash
python3 stub-supabase.py &
# apunta NEXT_PUBLIC_SUPABASE_URL a http://127.0.0.1:54321
npm run dev
```

## Lo que falta (Fase 2)

Modo observador, heatmaps y head-to-head, retos, y los puntos estimados —
que necesitan primero `transicion` en el enum de tipos de evento. Está todo
en `11-BACKLOG.md`.
