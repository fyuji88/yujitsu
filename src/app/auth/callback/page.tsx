'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';

/** El magic link vuelve aquí con un código; lo canjeamos por sesión. */
export default function Callback() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const code = new URLSearchParams(window.location.search).get('code');
      if (code) {
        const { error } = await supabase().auth.exchangeCodeForSession(code);
        if (error) { setError(error.message); return; }
      }
      const { data } = await supabase().auth.getUser();
      router.replace(data.user ? '/entreno' : '/login');
    })();
  }, [router]);

  return (
    <div className="phone">
      <main>
        {error
          ? <><p className="err">{error}</p>
              <p className="hint">El enlace puede haber caducado. Pide otro desde la pantalla de entrada.</p></>
          : <p className="empty">Entrando…</p>}
      </main>
    </div>
  );
}
