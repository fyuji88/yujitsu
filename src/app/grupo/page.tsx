'use client';

import { useCallback, useEffect, useState } from 'react';
import { Marco, type Sesion } from '@/components/Marco';
import { Feed } from '@/components/Feed';
import { supabase } from '@/lib/supabase';
import type {
  GrupoRow, MiembroRow, PracticanteRow, RolGrupo,
} from '@/lib/database.types';

/**
 * Tu grupo: quién está dentro, quién manda, y cómo entra alguien nuevo.
 *
 * La interfaz solo ofrece lo que la RLS permite: los botones de admin —el
 * código, regenerarlo, dar de alta a alguien— solo se pintan si eres admin de
 * ese grupo, que es la misma condición que la política de Postgres. Si la
 * pantalla ofreciera más, el usuario vería errores en vez de botones ausentes.
 */

interface MiembroConFicha extends MiembroRow {
  ficha: PracticanteRow | undefined;
}

export default function Grupo() {
  return <Marco titulo="Grupo">{(s) => <Panel sesion={s} />}</Marco>;
}

function Panel({ sesion }: { sesion: Sesion }) {
  const [grupos, setGrupos] = useState<GrupoRow[]>([]);
  const [miembros, setMiembros] = useState<MiembroRow[]>([]);
  const [roster, setRoster] = useState<PracticanteRow[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [codigo, setCodigo] = useState('');
  const [nombreNuevo, setNombreNuevo] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const cargar = useCallback(async () => {
    setCargando(true);
    const sb = supabase();
    const [g, m, p] = await Promise.all([
      sb.from('grupos').select('*').order('nombre'),
      sb.from('miembros_grupo').select('*'),
      sb.from('practicantes').select('*').order('nombre'),
    ]);
    setGrupos((g.data ?? []) as GrupoRow[]);
    setMiembros((m.data ?? []) as MiembroRow[]);
    setRoster((p.data ?? []) as PracticanteRow[]);
    setCargando(false);
  }, []);

  useEffect(() => { void cargar(); }, [cargar]);

  const soyAdminDe = (grupoId: string) => miembros.some(
    (m) => m.grupo_id === grupoId && m.practicante_id === sesion.practicante.id
      && m.rol === 'admin' && m.estado === 'activo',
  );

  async function unirse(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setError(null); setAviso(null);
    const { error } = await supabase().rpc('unirse_con_codigo', { p_codigo: codigo.trim() });
    setOcupado(false);
    if (error) {
      setError(error.message.includes('no hay ningun grupo')
        ? 'No hay ningún grupo con ese código. Compruébalo con quien te lo pasó.'
        : error.message);
      return;
    }
    setCodigo(''); setAviso('Ya estás dentro.');
    void cargar();
  }

  async function crear(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setError(null); setAviso(null);
    const { error } = await supabase().rpc('crear_grupo', { p_nombre: nombreNuevo.trim() });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    setNombreNuevo(''); setAviso('Grupo creado. Eres su admin.');
    void cargar();
  }

  async function regenerar(grupoId: string) {
    setOcupado(true); setError(null);
    const { error } = await supabase().rpc('regenerar_codigo', { p_grupo: grupoId });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    setAviso('Código nuevo. El anterior ya no vale.');
    void cargar();
  }

  /** Alta manual de alguien del roster que todavía no está en el grupo. */
  async function anadir(grupoId: string, practicanteId: string) {
    setOcupado(true); setError(null);
    const { error } = await supabase().from('miembros_grupo')
      .insert({ grupo_id: grupoId, practicante_id: practicanteId, rol: 'miembro' });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    void cargar();
  }

  async function cambiarRol(grupoId: string, practicanteId: string, rol: RolGrupo) {
    setOcupado(true); setError(null);
    const { error } = await supabase().from('miembros_grupo')
      .update({ rol }).eq('grupo_id', grupoId).eq('practicante_id', practicanteId);
    setOcupado(false);
    if (error) { setError(error.message); return; }
    void cargar();
  }

  if (cargando) return <p className="empty">Cargando…</p>;

  return (
    <>
      {error && <p className="err" data-testid="error">{error}</p>}
      {aviso && <p className="hint" data-testid="aviso" style={{ color: 'var(--good)' }}>{aviso}</p>}

      {/* El feed va arriba: es lo que se abre a diario. La ficha del grupo y
          la lista de miembros se consultan de vez en cuando. */}
      {grupos.length > 0 && (
        <>
          <h2 className="sec" style={{ marginTop: 4 }}>Lo que está pasando</h2>
          <Feed practicanteId={sesion.practicante.id} />
        </>
      )}

      {grupos.map((g) => {
        const admin = soyAdminDe(g.id);
        const suyos: MiembroConFicha[] = miembros
          .filter((m) => m.grupo_id === g.id && m.estado === 'activo')
          .map((m) => ({ ...m, ficha: roster.find((p) => p.id === m.practicante_id) }))
          .sort((a, b) => (a.rol === b.rol
            ? (a.ficha?.nombre ?? '').localeCompare(b.ficha?.nombre ?? '')
            : a.rol === 'admin' ? -1 : 1));
        const fuera = roster.filter(
          (p) => !miembros.some((m) => m.grupo_id === g.id && m.practicante_id === p.id),
        );

        return (
          <div key={g.id} data-testid={`grupo-${g.slug}`}>
            <div className="state" style={{ marginTop: 12 }}>
              <div className="lbl">Tu grupo</div>
              <div className="pos">{g.nombre}</div>
              <div className="rol">
                {suyos.length} {suyos.length === 1 ? 'miembro' : 'miembros'}
                {g.ciudad && <> · {g.ciudad}</>}
                {admin && <> · eres admin</>}
              </div>
            </div>

            {admin && (
              <>
                <h2 className="sec">Código para entrar</h2>
                <p className="hint" style={{ marginTop: 0 }}>
                  Dilo en el vestuario. Quien lo teclee entra como miembro.
                </p>
                <div className="fila" style={{ marginTop: 8 }}>
                  <span className="n" data-testid="codigo-union"
                    style={{ fontSize: 20, fontWeight: 650, letterSpacing: '.12em' }}>
                    {g.codigo_union}
                  </span>
                  <button className="ghost" disabled={ocupado}
                    data-testid="regenerar" onClick={() => void regenerar(g.id)}>
                    Cambiarlo
                  </button>
                </div>
              </>
            )}

            <h2 className="sec">Quién está dentro</h2>
            <div className="tl">
              {suyos.map((m) => (
                <div className="fila" key={m.practicante_id}>
                  <span className="n">
                    {m.ficha?.nombre ?? 'ficha borrada'}
                    <small>
                      {m.ficha?.cinturon}
                      {m.practicante_id === sesion.practicante.id && ' · tú'}
                      {!m.ficha?.usa_sistema && ' · sin cuenta'}
                    </small>
                  </span>
                  <span className="pill">{m.rol}</span>
                  {admin && m.practicante_id !== sesion.practicante.id && (
                    <button className="ghost" disabled={ocupado}
                      style={{ padding: '7px 10px', fontSize: 12 }}
                      onClick={() => void cambiarRol(g.id, m.practicante_id,
                        m.rol === 'admin' ? 'miembro' : 'admin')}>
                      {m.rol === 'admin' ? 'Quitar admin' : 'Hacer admin'}
                    </button>
                  )}
                </div>
              ))}
            </div>

            {admin && fuera.length > 0 && (
              <>
                <h2 className="sec">Añadir del roster</h2>
                <p className="hint" style={{ marginTop: 0 }}>
                  Para quien ya está dado de alta como contacto y no tiene cuenta.
                </p>
                <div className="chips">
                  {fuera.map((p) => (
                    <button className="chip" key={p.id} disabled={ocupado}
                      data-testid={`anadir-${p.nombre}`}
                      onClick={() => void anadir(g.id, p.id)}>
                      + {p.nombre}
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        );
      })}

      <h2 className="sec">{grupos.length ? 'Entrar en otro grupo' : 'Entrar en un grupo'}</h2>
      {!grupos.length && (
        <p className="hint" style={{ marginTop: 0 }}>
          Todavía no estás en ninguno. Pide el código a quien lleve el grupo, o crea el tuyo.
        </p>
      )}
      <form onSubmit={unirse}>
        <label htmlFor="codigo">Código</label>
        <input id="codigo" value={codigo} data-testid="codigo"
          placeholder="GULLO-7X4" autoCapitalize="characters"
          style={{ letterSpacing: '.1em' }}
          onChange={(e) => setCodigo(e.target.value.toUpperCase())} />
        <div style={{ marginTop: 14 }}>
          <button className="primary" type="submit" data-testid="unirse"
            disabled={ocupado || codigo.trim().length < 3}>Unirme</button>
        </div>
      </form>

      <h2 className="sec">O crea uno</h2>
      <form onSubmit={crear}>
        <label htmlFor="nuevo">Nombre del grupo</label>
        <input id="nuevo" value={nombreNuevo} data-testid="nombre-grupo"
          placeholder="Open mat de los domingos"
          onChange={(e) => setNombreNuevo(e.target.value)} />
        <div style={{ marginTop: 14 }}>
          <button className="ghost" type="submit" data-testid="crear-grupo"
            disabled={ocupado || nombreNuevo.trim().length < 2}>Crear grupo</button>
        </div>
      </form>
      <p className="hint">
        No hace falta que sea un gimnasio: un open mat entre amigos es un grupo igual.
      </p>
    </>
  );
}
