'use client';

import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';

let cliente: SupabaseClient | null = null;

/** Un único cliente por pestaña: si se crean varios, la sesión se pisa. */
export function supabase(): SupabaseClient {
  if (!cliente) {
    cliente = createBrowserClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    );
    // En desarrollo lo dejamos a mano en la consola del navegador: sirve para
    // depurar la sesion y para las pruebas end-to-end. En produccion no existe.
    if (process.env.NODE_ENV === 'development') {
      (window as unknown as { __sb?: SupabaseClient }).__sb = cliente;
    }
  }
  return cliente;
}
