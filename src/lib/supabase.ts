'use client';

import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';

let cliente: SupabaseClient | null = null;

/**
 * Un único cliente por pestaña: si se crean varios, la sesión se pisa.
 *
 * flowType 'implicit' a propósito. Por defecto supabase-js usa PKCE, que guarda
 * un verificador en el navegador donde PIDES el enlace y lo exige en el
 * navegador donde lo ABRES. Como aquí el enlace llega por correo, es normal
 * pedirlo en el móvil y abrirlo en el portátil (o al revés) — y entonces PKCE
 * falla con "code verifier not found in storage".
 * Con el flujo implícito la sesión viaja en el propio enlace y entras desde
 * cualquier dispositivo.
 */
export function supabase(): SupabaseClient {
  if (!cliente) {
    cliente = createBrowserClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { auth: { flowType: 'implicit', detectSessionInUrl: true, persistSession: true } },
    );
    if (process.env.NODE_ENV === 'development') {
      (window as unknown as { __sb?: SupabaseClient }).__sb = cliente;
    }
  }
  return cliente;
}
