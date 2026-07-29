'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import {
  arrancarSync, observarSync, retenerCola, vaciarCola, type EstadoSync,
} from '@/lib/sync';
import { contarPendientes, olvidarDatosDelUsuario } from '@/lib/db';
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
  const [saliendo, setSaliendo] = useState(false);
  const [pendientesAlSalir, setPendientesAlSalir] = useState<number | null>(null);

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

  /**
   * Salir.
   *
   * Lo importante no es cerrar la sesión —eso es una línea— sino no dejarle al
   * siguiente cosas del anterior. Primero se intenta vaciar la cola: los rolls
   * que queden dentro se subirían con la sesión de quien entre después, y la
   * RLS los rechazaría por ajenos. Si no se puede vaciar (sin cobertura), se
   * dice cuántos hay y se pregunta, en vez de tirarlos a la callada.
   */
  async function pedirSalir() {
    setSaliendo(true);
    retenerCola(false);          // por si veníamos del resumen del observador
    await vaciarCola();
    const quedan = await contarPendientes();
    setSaliendo(false);
    if (quedan > 0) { setPendientesAlSalir(quedan); return; }
    await salir();
  }

  async function salir() {
    setSaliendo(true);
    await olvidarDatosDelUsuario();
    await supabase().auth.signOut();
    router.replace('/login');
  }

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
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <span className={pastilla.cls} data-testid="sync">{pastilla.txt}</span>
          {s && (
            <button className="salir" data-testid="salir" disabled={saliendo}
              onClick={() => void pedirSalir()}>Salir</button>
          )}
        </div>
      </div>

      <main>
        {pendientesAlSalir !== null && (
          <div className="state" data-testid="aviso-salir" style={{ marginBottom: 14 }}>
            <div className="lbl">Antes de salir</div>
            <div className="pos" style={{ fontSize: 17 }}>
              {pendientesAlSalir} {pendientesAlSalir === 1 ? 'cosa sin subir' : 'cosas sin subir'}
            </div>
            <p className="hint" style={{ margin: '8px 0 0' }}>
              No hay conexión, o Supabase no las acepta. Si sales ahora se pierden: no
              se pueden dejar para el siguiente que entre, porque se subirían con su
              cuenta y la base las rechazaría por ajenas.
            </p>
            <div style={{ display: 'flex', gap: 9, marginTop: 14 }}>
              <button className="ghost" data-testid="salir-cancelar"
                onClick={() => setPendientesAlSalir(null)}>Me quedo</button>
              <button className="ghost" data-testid="salir-descartar"
                style={{ color: 'var(--bad)' }} disabled={saliendo}
                onClick={() => void salir()}>Salir y descartarlas</button>
            </div>
          </div>
        )}

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
