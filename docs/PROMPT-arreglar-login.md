# Prompt para Claude Code — arreglar el login de verdad

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

El magic link sigue fallando con `PKCE code verifier not found in storage`, a
pesar de que `src/lib/supabase.ts` pide `flowType: 'implicit'`. **La opción se
está ignorando**, y está comprobado leyendo el paquete instalado, no deducido.

En `node_modules/@supabase/ssr/dist/main/createBrowserClient.js`:

```js
auth: {
  ...options?.auth,
  ...(options?.cookieOptions?.name ? { storageKey: options.cookieOptions.name } : null),
  flowType: "pkce",                    // <-- después del spread: pisa lo nuestro
  autoRefreshToken: options?.auth?.autoRefreshToken ?? isBrowser(),
  detectSessionInUrl: options?.auth?.detectSessionInUrl ?? isBrowser(),
  persistSession: options?.auth?.persistSession ?? true,
  storage,
}
```

`flowType: "pkce"` va **después** de `...options?.auth`, así que sobrescribe lo
que le pasemos. No es configurable: `@supabase/ssr` está construido alrededor de
PKCE a propósito. El arreglo anterior fue una operación nula.

Y PKCE no puede funcionar con enlaces por correo entre contextos distintos: el
verificador vive en el almacenamiento del navegador donde se **pide** el enlace,
y el correo se abre donde se abre —una pestaña de Chrome lanzada desde Gmail, la
PWA instalada, otro móvil—. Cuando coinciden, entra; cuando no, este error. Por
eso es intermitente: hay un login correcto en los registros y otro fallido dos
horas después, del mismo usuario.

## Arreglo 1 — dejar de usar `@supabase/ssr` en el cliente

Esta app **no tiene autenticación en servidor**: no hay `middleware.ts`, no hay
`createServerClient` en ningún sitio, y todas las pantallas son componentes de
cliente. `@supabase/ssr` no aporta nada aquí y a cambio impone PKCE.

En `src/lib/supabase.ts`, cambia a `createClient` de `@supabase/supabase-js`:

```ts
createClient(url, anonKey, {
  auth: {
    flowType: 'implicit',
    detectSessionInUrl: true,
    persistSession: true,
    autoRefreshToken: true,
  },
})
```

Mantén el singleton por pestaña que ya hay. La sesión pasa a vivir en
`localStorage` en vez de en cookies, que para una PWA sin servidor es lo
correcto. Quita `@supabase/ssr` de `package.json` **solo** después de comprobar
con una búsqueda que no lo importa nadie más.

Con esto el enlace del correo deja de traer `?code=` y trae la sesión en el
fragmento (`#access_token=...`), que es lo que `src/app/auth/callback/page.tsx`
ya sabe manejar. Deja la rama de `?code=` que hay ahí: no estorba y cubre los
enlaces viejos que sigan vivos.

## Arreglo 2 — código de 6 dígitos, y esto es lo que de verdad lo cierra

El arreglo 1 hace que el enlace funcione entre dispositivos, pero sigue
dependiendo de un enlace: caduca, es de un solo uso, y los escáneres de correo
de algunos proveedores lo abren antes que el usuario y lo queman.

Añade la entrada por código: `signInWithOtp({ email })` como ahora, y en la
misma pantalla un campo para teclear el código que llega, resuelto con
`verifyOtp({ email, token, type: 'email' })`. La sesión se abre en la pestaña
donde se pidió, así que el problema desaparece por construcción y no hay
pantalla de vuelta que pueda fallar.

Requiere tocar la plantilla del correo en Supabase → Authentication → Email
Templates → Magic Link, para que muestre `{{ .Token }}` además del enlace. Eso
lo hace Felipe desde el panel; **dile exactamente qué poner** en vez de darlo por
hecho.

Deja las dos vías: el enlace para quien lo abra en el mismo sitio, y el código
para todo lo demás.

## Verificación

1. `npm run build` pasa.
2. Con la app desplegada, pedir el enlace en un navegador y abrirlo **en otro**.
   Antes fallaba; tiene que entrar. Esta es la prueba, no que compile.
3. Que el enlace del correo llegue con `#access_token=` y no con `?code=`.
4. Entrar con el código de 6 dígitos, sin tocar el enlace.
5. Que la sesión sobreviva a cerrar y reabrir el navegador.
6. No toques la base: hay dos usuarios reales (`fyhayashi@gmail.com` y el de
   Pablo) con sus fichas creadas por el trigger `bjj_08`, y datos que Felipe
   quiere conservar.

Actualiza `CLAUDE.md`: la nota que dice "el cliente usa `flowType: 'implicit'` a
propósito" está incompleta y engaña — hay que explicar que `@supabase/ssr` fuerza
PKCE y que por eso se usa `createClient` directamente.
