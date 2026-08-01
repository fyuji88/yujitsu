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
  /**
   * `practicantes.usa_sistema`, con el nombre de lo que hace.
   *
   * Un alta nueva entra en `true`: alguien a quien das de alta es alguien con
   * quien ruedas, y lo normal es querer su mitad del roll. Antes se creaba en
   * `false` y no había forma de cambiarlo desde ninguna pantalla, así que todo
   * contacto nacía sin espejo para siempre.
   */
  guardarRolls: boolean;
}

const vacio: Borrador = {
  nombre: '', cinturon: 'blanca', peso: '', academia: '', guardarRolls: true,
};

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
      usa_sistema: editando.guardarRolls,
      academia: editando.academia.trim() || null,
    };
    const q = editando.id
      ? supabase().from('practicantes').update(fila).eq('id', editando.id)
      : supabase().from('practicantes').insert(fila);
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

        {/* LO QUE DECIDE SI SE LE GUARDA SU MITAD DEL ROLL.
            Esta casilla existía en la base desde el principio y NO se podía
            tocar desde ninguna pantalla: se creaba en `false` y ahí se quedaba.
            Y `espejar_roll()` la mira: con `false` no crea el roll espejo, así
            que de un roll observado solo se guarda un lado y esa persona no
            aparece en el informe del Open Mat.
            Se llamaba «usa la app», que es lo que hacía invisible el efecto:
            lo que importa no es si la tiene instalada, es si le guardas sus
            rolls. */}
        <label style={{ display: 'flex', gap: 9, alignItems: 'flex-start', marginTop: 14 }}>
          <input type="checkbox" data-testid="ed-guardar-rolls"
            checked={editando.guardarRolls}
            onChange={(e) => setEditando({ ...editando, guardarRolls: e.target.checked })}
            style={{ width: 22, height: 22, marginTop: 2, flex: '0 0 auto' }} />
          <span>
            Guardarle sus rolls
            <small style={{ display: 'block', color: 'var(--tenue)', fontWeight: 400 }}>
              Cuando alguien observe un roll suyo, se le guarda su mitad y sale
              en el informe del {'Open Mat'}. Sin esto solo se guarda el lado del
              otro.
            </small>
          </span>
        </label>
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
                  guardarRolls: p.usa_sistema,
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
