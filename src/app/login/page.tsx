'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';

export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [nombre, setNombre] = useState('');
  const [estado, setEstado] = useState<'idle' | 'enviando' | 'enviado'>('idle');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void supabase().auth.getUser().then(({ data }) => {
      if (data.user) router.replace('/entreno');
    });
  }, [router]);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setEstado('enviando');
    setError(null);
    // El nombre viaja como metadata: el trigger de Postgres lo usa para crear
    // la ficha de practicante. Sin esto, el nombre se deduce del email y sale feo.
    const { error } = await supabase().auth.signInWithOtp({
      email: email.trim(),
      options: {
        data: { nombre: nombre.trim() || undefined },
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });
    if (error) { setError(error.message); setEstado('idle'); return; }
    setEstado('enviado');
  }

  return (
    <div className="phone">
      <div className="top"><div><div className="t1">BJJ Tracker</div>
        <div className="t2">diario de rolls</div></div></div>
      <main>
        {estado === 'enviado' ? (
          <>
            <h1>Mira tu correo</h1>
            <p className="hint">
              Te hemos mandado un enlace a <b>{email}</b>. Ábrelo en este mismo móvil
              y entras directo, sin contraseña.
            </p>
          </>
        ) : (
          <form onSubmit={enviar}>
            <h1>Entrar</h1>
            <p className="hint">Sin contraseñas: te mandamos un enlace al correo.</p>
            <label htmlFor="nombre">Cómo te llamas</label>
            <input id="nombre" value={nombre} onChange={(e) => setNombre(e.target.value)}
              placeholder="Felipe" autoComplete="given-name" />
            <label htmlFor="email">Tu email</label>
            <input id="email" type="email" required value={email} inputMode="email"
              onChange={(e) => setEmail(e.target.value)} placeholder="tu@email.com"
              autoComplete="email" />
            {error && <p className="err">{error}</p>}
            <div style={{ marginTop: 20 }}>
              <button className="primary" type="submit" disabled={estado === 'enviando'}>
                {estado === 'enviando' ? 'Enviando…' : 'Mandarme el enlace'}
              </button>
            </div>
          </form>
        )}
      </main>
    </div>
  );
}
