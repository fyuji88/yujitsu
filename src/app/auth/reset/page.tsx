'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';

const MINIMO = 8;

/**
 * Poner una contraseña nueva.
 *
 * Se llega aquí de dos maneras, y las dos acaban igual: con una sesión abierta.
 *
 *  - Por el enlace del correo, que con el flujo implícito trae la sesión en el
 *    fragmento (`#access_token=…`) y la recoge `detectSessionInUrl`.
 *  - Por el código de recuperación tecleado en la pantalla de entrada, que
 *    `verifyOtp({ type: 'recovery' })` canjea por sesión antes de redirigir aquí.
 *
 * Con sesión, cambiar la contraseña es `updateUser`. Sin sesión no hay nada que
 * hacer aquí, y hay que decirlo en vez de enseñar un formulario que va a fallar.
 */
export default function Reset() {
  const router = useRouter();
  const [estado, setEstado] = useState<'esperando' | 'listo' | 'sin-sesion' | 'guardando'>('esperando');
  const [clave, setClave] = useState('');
  const [repetida, setRepetida] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    const sb = supabase();

    // detectSessionInUrl trabaja de forma asíncrona: se espera a que la sesión
    // aparezca en vez de leerla una sola vez y darla por perdida.
    const { data: sub } = sb.auth.onAuthStateChange((_e, sesion) => {
      if (sesion && vivo) { sub.subscription.unsubscribe(); setEstado('listo'); }
    });

    void sb.auth.getSession().then(({ data }) => {
      if (!vivo) return;
      if (data.session) { sub.subscription.unsubscribe(); setEstado('listo'); }
    });

    const reloj = setTimeout(() => {
      if (!vivo) return;
      sub.subscription.unsubscribe();
      void sb.auth.getSession().then(({ data }) => {
        if (!vivo) return;
        setEstado(data.session ? 'listo' : 'sin-sesion');
      });
    }, 4000);

    return () => { vivo = false; clearTimeout(reloj); sub.subscription.unsubscribe(); clearTimeout(reloj); };
  }, []);

  async function guardar(e: React.FormEvent) {
    e.preventDefault();
    if (clave.length < MINIMO) {
      setError(`La contraseña necesita al menos ${MINIMO} caracteres.`);
      return;
    }
    if (clave !== repetida) { setError('Las dos no coinciden.'); return; }
    setEstado('guardando'); setError(null);
    const { error } = await supabase().auth.updateUser({ password: clave });
    if (error) { setError(error.message); setEstado('listo'); return; }
    router.replace('/entreno');
  }

  return (
    <div className="phone">
      <div className="top"><div><div className="t1">BJJ Tracker</div>
        <div className="t2">contraseña nueva</div></div></div>
      <main>
        {estado === 'esperando' && <p className="empty">Comprobando el enlace…</p>}

        {estado === 'sin-sesion' && (
          <>
            <h1>Este enlace ya no vale</h1>
            <p className="err" data-testid="sin-sesion">
              No hemos podido abrir la sesión con este enlace.
            </p>
            <p className="hint">
              Los enlaces de recuperación caducan y son de un solo uso. Pide otro desde
              la pantalla de entrada — y si lo vas a abrir en otro dispositivo, usa el
              código del mismo correo, que no depende del navegador.
            </p>
            <div style={{ marginTop: 18 }}>
              <button className="primary" onClick={() => router.replace('/login')}>
                Volver a intentarlo
              </button>
            </div>
          </>
        )}

        {(estado === 'listo' || estado === 'guardando') && (
          <form onSubmit={guardar}>
            <h1>Contraseña nueva</h1>
            <p className="hint">Elige una y entras directo.</p>
            <label htmlFor="clave">Contraseña</label>
            <input id="clave" type="password" required value={clave} data-testid="clave"
              autoComplete="new-password" placeholder={`mínimo ${MINIMO} caracteres`}
              onChange={(e) => setClave(e.target.value)} />
            <label htmlFor="repetida">Repítela</label>
            <input id="repetida" type="password" required value={repetida}
              data-testid="repetida" autoComplete="new-password"
              onChange={(e) => setRepetida(e.target.value)} />
            {error && <p className="err" data-testid="error">{error}</p>}
            <div style={{ marginTop: 20 }}>
              <button className="primary" type="submit" data-testid="guardar"
                disabled={estado === 'guardando'}>
                {estado === 'guardando' ? 'Guardando…' : 'Guardar y entrar'}
              </button>
            </div>
          </form>
        )}
      </main>
    </div>
  );
}
