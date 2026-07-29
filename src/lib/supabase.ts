'use client';

import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let cliente: SupabaseClient | null = null;

/**
 * Un único cliente por pestaña: si se crean varios, la sesión se pisa.
 *
 * ---------------------------------------------------------------------------
 * POR QUÉ `createClient` Y NO `createBrowserClient` DE @supabase/ssr
 * ---------------------------------------------------------------------------
 *
 * Porque @supabase/ssr **fuerza PKCE y no deja desactivarlo**. En
 * `createBrowserClient.js` (0.12.3) el objeto de auth se construye así:
 *
 *     auth: {
 *       ...options?.auth,          // lo que le pasamos
 *       ...
 *       flowType: "pkce",          // <-- después del spread: nos lo pisa
 *       ...
 *     }
 *
 * `flowType: 'pkce'` va DESPUÉS del spread, así que sobrescribe lo que le
 * mandes. No es un descuido: la librería está construida alrededor de PKCE
 * a propósito, porque su caso de uso es autenticación en servidor con cookies.
 *
 * Durante un tiempo este fichero pedía `flowType: 'implicit'` creyendo que
 * arreglaba el magic link. No arreglaba nada: era una opción ignorada.
 *
 * Y PKCE **no puede funcionar con enlaces por correo**. El verificador se
 * guarda en el almacenamiento del navegador donde PIDES el enlace, y el correo
 * se abre donde se abre: una pestaña que lanza Gmail, la PWA instalada, otro
 * móvil. Cuando coinciden, entras; cuando no, `code verifier not found in
 * storage`. Por eso fallaba de forma intermitente y no siempre.
 *
 * Esta app no tiene autenticación en servidor —no hay `middleware.ts`, no hay
 * `createServerClient`, todas las pantallas son componentes de cliente—, así
 * que @supabase/ssr no aportaba nada y a cambio imponía eso. Con `createClient`
 * la sesión vive en localStorage, que para una PWA sin servidor es lo correcto,
 * y el enlace del correo trae la sesión en el fragmento (`#access_token=…`),
 * que es lo que `src/app/auth/callback` sabe manejar.
 *
 * Aun así, el camino que de verdad cierra el problema es el **código de 6
 * dígitos** de la pantalla de entrada: la sesión se abre en la misma pestaña
 * donde se pidió, así que no hay nada que pueda descuadrarse.
 */
export function supabase(): SupabaseClient {
  if (!cliente) {
    cliente = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        auth: {
          flowType: 'implicit',
          detectSessionInUrl: true,
          persistSession: true,
          autoRefreshToken: true,
        },
      },
    );
    if (process.env.NODE_ENV === 'development') {
      (window as unknown as { __sb?: SupabaseClient }).__sb = cliente;
    }
  }
  return cliente;
}
