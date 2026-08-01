'use client';

import { useCallback, useEffect, useState } from 'react';
import { Marco, type Sesion } from '@/components/Marco';
import { Avatar } from '@/components/Avatar';
import { supabase } from '@/lib/supabase';
import type { Cinturon, PracticanteRow } from '@/lib/database.types';

const CINTURONES: Cinturon[] = ['blanca', 'azul', 'morada', 'marron', 'negra'];
const LABEL: Record<Cinturon, string> = {
  blanca: 'Blanca', azul: 'Azul', morada: 'Morada', marron: 'Marrón', negra: 'Negra',
};

interface Borrador {
  id?: string;
  nombre: string;
  cinturon: Cinturon;
  peso: string;
  academia: string;
}

const vacio: Borrador = { nombre: '', cinturon: 'blanca', peso: '', academia: '' };

export default function Practicantes() {
  return (
    <Marco titulo="Practicantes" sub="quién hay en el tatami">
      {(s) => <Lista sesion={s} />}
    </Marco>
  );
}

function Lista({ sesion }: { sesion: Sesion }) {
  const [filas, setFilas] = useState<PracticanteRow[]>([]);
  const [editando, setEditando] = useState<Borrador | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const { data, error } = await supabase()
      .from('practicantes').select('*').order('nombre');
    if (error) { setError(error.message); return; }
    setFilas((data ?? []) as PracticanteRow[]);
  }, []);

  useEffect(() => { void cargar(); }, [cargar]);

  // Solo puedo editar mi ficha y los compañeros que di de alta yo.
  // Es la misma regla que aplica la RLS: la interfaz no debe ofrecer lo que
  // la base va a rechazar.
  const puedoEditar = (p: PracticanteRow) =>
    p.user_id === sesion.userId || (p.user_id === null && p.creado_por === sesion.userId);

  async function guardar() {
    if (!editando || !editando.nombre.trim()) return;
    setGuardando(true);
    setError(null);
    const fila = {
      nombre: editando.nombre.trim(),
      cinturon: editando.cinturon,
      peso_kg: editando.peso ? Number(editando.peso) : null,
      academia: editando.academia.trim() || null,
    };
    const q = editando.id
      ? supabase().from('practicantes').update(fila).eq('id', editando.id)
      // `usa_sistema` en false: significa «usa la app», y un contacto que das
      // de alta no la usa. Desde bjj_38 NO decide si se le guardan sus rolls —
      // eso pasa siempre.
      : supabase().from('practicantes').insert({ ...fila, usa_sistema: false });
    const { error } = await q;
    setGuardando(false);
    if (error) { setError(error.message); return; }
    setEditando(null);
    await cargar();
  }

  async function borrar(id: string) {
    const { error } = await supabase().from('practicantes').delete().eq('id', id);
    if (error) { setError(error.message); return; }
    await cargar();
  }

  if (editando) {
    return (
      <>
        <h2 className="sec">{editando.id ? 'Editar ficha' : 'Nuevo compañero'}</h2>
        <label htmlFor="n">Nombre</label>
        <input id="n" value={editando.nombre} autoFocus
          onChange={(e) => setEditando({ ...editando, nombre: e.target.value })} />
        <label>Cinturón</label>
        <div className="chips">
          {CINTURONES.map((c) => (
            <button key={c} type="button"
              className={`chip${editando.cinturon === c ? ' ok' : ''}`}
              onClick={() => setEditando({ ...editando, cinturon: c })}>{LABEL[c]}</button>
          ))}
        </div>
        <label htmlFor="p">Peso (kg, opcional)</label>
        <input id="p" inputMode="decimal" value={editando.peso}
          onChange={(e) => setEditando({ ...editando, peso: e.target.value })} />
        <label htmlFor="a">Academia (opcional)</label>
        <input id="a" value={editando.academia}
          onChange={(e) => setEditando({ ...editando, academia: e.target.value })} />

        {/* Aqui hubo un dia una casilla «guardarle sus rolls». Duro un dia.
            Era el interruptor de `usa_sistema`, que decidia si al companero se
            le creaba su mitad del roll observado — y sacarlo a la pantalla no
            arreglaba el fallo, solo lo convertia en algo que habia que
            acordarse de marcar persona a persona antes de cada Open Mat. Al
            dia siguiente volvieron a salir ocho de ocho rolls huerfanos porque
            nadie lo marco. Desde `bjj_38` el espejo no depende de nada y la
            casilla no tenia ya nada que controlar. */}
        {error && <p className="err">{error}</p>}
        <div style={{ display: 'flex', gap: 9, marginTop: 20 }}>
          <button className="primary" onClick={guardar}
            disabled={guardando || !editando.nombre.trim()}>
            {guardando ? 'Guardando…' : 'Guardar'}
          </button>
          <button className="ghost" onClick={() => { setEditando(null); setError(null); }}>
            Cancelar
          </button>
        </div>
      </>
    );
  }

  return (
    <>
      {error && <p className="err">{error}</p>}
      <h2 className="sec">Roster ({filas.length})</h2>
      <div className="tl">
        {filas.length === 0 && (
          <p className="empty">Nadie todavía. Añade a los que ruedas más a menudo.</p>
        )}
        {filas.map((p) => (
          <div className="fila" key={p.id}>
            <Avatar nombre={p.nombre} cinturon={p.cinturon} grados={p.grados ?? 0} />
            <span className="n">
              {p.nombre}
              <small>
                {LABEL[p.cinturon]}
                {p.peso_kg ? ` · ${p.peso_kg} kg` : ''}
                {p.user_id === sesion.userId ? ' · tú' : ''}
              </small>
            </span>
            {p.usa_sistema && <span className="pill">app</span>}
            {puedoEditar(p) && (
              <button className="x" aria-label={`Editar ${p.nombre}`}
                onClick={() => setEditando({
                  id: p.id, nombre: p.nombre, cinturon: p.cinturon,
                  peso: p.peso_kg?.toString() ?? '', academia: p.academia ?? '',
                })}>✎</button>
            )}
            {p.user_id === null && p.creado_por === sesion.userId && (
              <button className="x" aria-label={`Borrar ${p.nombre}`}
                onClick={() => borrar(p.id)}>✕</button>
            )}
          </div>
        ))}
      </div>

      <p className="hint">
        La etiqueta <b>app</b> marca a los que tienen cuenta: con ellos el
        head-to-head se cruza y un roll registrado por uno cuenta para los dos.
        Los demás son fichas de contacto — cuentan igual como oponentes.
      </p>

      <div style={{ marginTop: 18 }}>
        <button className="primary" onClick={() => setEditando({ ...vacio })}>
          + Añadir compañero
        </button>
      </div>
    </>
  );
}
