'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { arrancarSync, observarSync, type EstadoSync } from '@/lib/sync';
import { contarPendientes } from '@/lib/db';
import type { PracticanteRow } from '@/lib/database.types';

export interface Sesion {
  userId: string;
  practicante: PracticanteRow;
}

/**
 * Marco común: comprueba la sesión, arranca el vaciado de la cola y pinta la
 * píldora de sincronización. Las páginas reciben ya el practicante resuelto,
 * así no tienen que preocuparse de la autenticación.
 */
export function Marco(
  { titulo, sub, children, pie, sesion }:
  {
    titulo: string;
    sub?: string;
    children: (s: Sesion) => React.ReactNode;
    pie?: React.ReactNode;
    sesion?: never;
  },
) {
  const router = useRouter();
  const ruta = usePathname();
  const [s, setS] = useState<Sesion | null>(null);
  const [cargando, setCargando] = useState(true);
  const [sync, setSync] = useState<EstadoSync>({ enCola: 0, enviando: false, error: null });

  useEffect(() => {
    let vivo = true;
    (async () => {
      const { data } = await supabase().auth.getUser();
      if (!vivo) return;
      if (!data.user) { router.replace('/login'); return; }

      const { data: p } = await supabase()
        .from('practicantes').select('*').eq('user_id', data.user.id).maybeSingle();
      if (!vivo) return;
      if (p) setS({ userId: data.user.id, practicante: p as PracticanteRow });
      setCargando(false);
    })();
    return () => { vivo = false; };
  }, [router]);

  useEffect(() => {
    // La PWA: sin esto la app no abre sin conexion ni se puede instalar.
    if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
      void navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
    arrancarSync();
    const parar = observarSync(setSync);
    void contarPendientes().then((n) => setSync((v) => ({ ...v, enCola: n })));
    return () => { parar(); };
  }, []);

  const pastilla = sync.error
    ? { cls: 'sync err', txt: 'error al sincronizar' }
    : sync.enviando
      ? { cls: 'sync', txt: '↑ enviando…' }
      : sync.enCola > 0
        ? { cls: 'sync off', txt: `● ${sync.enCola} en cola` }
        : { cls: 'sync ok', txt: '✓ sincronizado' };

  return (
    <div className="phone">
      <div className="top">
        <div>
          <div className="t1">{titulo}</div>
          <div className="t2">{sub ?? (s ? s.practicante.nombre : '…')}</div>
        </div>
        <span className={pastilla.cls} data-testid="sync">{pastilla.txt}</span>
      </div>

      <main>
        {cargando && <p className="empty">Cargando…</p>}
        {!cargando && !s && (
          <p className="err">
            Tu cuenta existe pero no tiene ficha de practicante. Sal y vuelve a entrar.
          </p>
        )}
        {s && children(s)}
      </main>

      {pie}

      <nav className="tabs">
        <Link href="/entreno" className={ruta === '/entreno' ? 'on' : ''}>Entreno</Link>
        <Link href="/practicantes" className={ruta === '/practicantes' ? 'on' : ''}>Practicantes</Link>
      </nav>
    </div>
  );
}
