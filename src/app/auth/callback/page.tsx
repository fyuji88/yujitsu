'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';

/**
 * Vuelta del magic link.
 *
 * Con el flujo implícito la sesión llega en el fragmento (#access_token=...) y
 * supabase-js la recoge solo al cargar. Aquí solo esperamos a que aparezca.
 * Se contempla también el caso PKCE (?code=...) por si algún enlace antiguo
 * sigue vivo, y los errores que Supabase devuelve en el propio fragmento.
 */
export default function Callback() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;

    (async () => {
      const sb = supabase();
      const query = new URLSearchParams(window.location.search);
      const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''));

      const fallo = query.get('error_description') ?? hash.get('error_description');
      if (fallo) { setError(decodeURIComponent(fallo)); return; }

      const code = query.get('code');
      if (code) {
        const { error } = await sb.auth.exchangeCodeForSession(code);
        if (error && !hash.get('access_token')) { setError(error.message); return; }
      }

      // detectSessionInUrl trabaja de forma asíncrona: esperamos a que la sesión
      // exista en vez de leerla una sola vez y darla por perdida.
      const { data: sub } = sb.auth.onAuthStateChange((_e, sesion) => {
        if (sesion && vivo) { sub.subscription.unsubscribe(); router.replace('/entreno'); }
      });

      const { data } = await sb.auth.getSession();
      if (data.session && vivo) { sub.subscription.unsubscribe(); router.replace('/entreno'); return; }

      setTimeout(() => {
        if (!vivo) return;
        sub.subscription.unsubscribe();
        void sb.auth.getSession().then(({ data }) => {
          if (!vivo) return;
          if (data.session) router.replace('/entreno');
          else setError('No hemos podido abrir la sesión con este enlace.');
        });
      }, 4000);
    })();

    return () => { vivo = false; };
  }, [router]);

  return (
    <div className="phone">
      <main>
        {error
          ? (
            <>
              <h1>No se pudo entrar</h1>
              <p className="err">{error}</p>
              <p className="hint">
                Los enlaces caducan y son de un solo uso. Pide otro desde la pantalla
                de entrada y ábrelo en cuanto llegue.
              </p>
              <div style={{ marginTop: 18 }}>
                <button className="primary" onClick={() => router.replace('/login')}>
                  Volver a intentarlo
                </button>
              </div>
            </>
          )
          : <p className="empty">Entrando…</p>}
      </main>
    </div>
  );
}
