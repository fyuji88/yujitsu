'use client';

import { useCallback, useEffect, useState } from 'react';
import { Marco, type Sesion } from '@/components/Marco';
import { Feed } from '@/components/Feed';
import { Avatar } from '@/components/Avatar';
import { RankingDelMes } from '@/components/Logros';
import { supabase } from '@/lib/supabase';
import { TEXTOS } from '@/lib/textos/es';
import type {
  EquipoRow, MiembroRow, PracticanteRow, RolEnEquipo,
} from '@/lib/database.types';

/**
 * Tu equipo: quién está dentro, quién manda, y cómo entra alguien nuevo.
 *
 * La interfaz solo ofrece lo que la RLS permite: los botones de admin —el
 * código, regenerarlo, dar de alta a alguien— solo se pintan si eres admin de
 * ese equipo, que es la misma condición que la política de Postgres. Si la
 * pantalla ofreciera más, el usuario vería errores en vez de botones ausentes.
 */

interface MiembroConFicha extends MiembroRow {
  ficha: PracticanteRow | undefined;
}

export default function Equipo() {
  return <Marco titulo={TEXTOS.equipo}>{(s) => <Panel sesion={s} />}</Marco>;
}

function Panel({ sesion }: { sesion: Sesion }) {
  const [equipos, setEquipos] = useState<EquipoRow[]>([]);
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
      sb.from('equipos').select('*').order('nombre'),
      sb.from('miembros_equipo').select('*'),
      sb.from('practicantes').select('*').order('nombre'),
    ]);
    setEquipos((g.data ?? []) as EquipoRow[]);
    setMiembros((m.data ?? []) as MiembroRow[]);
    setRoster((p.data ?? []) as PracticanteRow[]);
    setCargando(false);
  }, []);

  useEffect(() => { void cargar(); }, [cargar]);

  const soyAdminDe = (equipoId: string) => miembros.some(
    (m) => m.equipo_id === equipoId && m.practicante_id === sesion.practicante.id
      && m.rol_en_equipo === 'admin' && m.estado === 'activo',
  );

  async function unirse(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setError(null); setAviso(null);
    const { error } = await supabase().rpc('unirse_con_codigo', { p_codigo: codigo.trim() });
    setOcupado(false);
    if (error) {
      setError(error.message.includes('no hay ningun equipo')
        ? `No hay ningún ${TEXTOS.equipo} con ese código. Compruébalo con quien te lo pasó.`
        : error.message);
      return;
    }
    setCodigo(''); setAviso('Ya estás dentro.');
    void cargar();
  }

  async function crear(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setError(null); setAviso(null);
    const { error } = await supabase().rpc('crear_equipo', { p_nombre: nombreNuevo.trim() });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    setNombreNuevo(''); setAviso(`${TEXTOS.equipo} creado. Eres su admin.`);
    void cargar();
  }

  async function regenerar(equipoId: string) {
    setOcupado(true); setError(null);
    const { error } = await supabase().rpc('regenerar_codigo', { p_equipo: equipoId });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    setAviso('Código nuevo. El anterior ya no vale.');
    void cargar();
  }

  /**
   * Sacar a alguien del equipo.
   *
   * NO BORRA NADA SUYO, y la confirmación lo dice: deja de ver los datos del
   * equipo y el equipo deja de ver los suyos. Es un cambio de visibilidad, no
   * un borrado — confundir las dos cosas en un botón rojo es cómo alguien
   * destruye datos creyendo que ordena.
   */
  async function sacar(equipoId: string, practicanteId: string, nombre: string) {
    if (!confirm(
      `¿Sacar a ${nombre} del ${TEXTOS.equipo}?\n\n`
      + 'No se borra nada suyo: deja de ver los datos del equipo y el equipo '
      + 'deja de ver los suyos.',
    )) return;
    setOcupado(true); setError(null);
    const { error } = await supabase().from('miembros_equipo').delete()
      .eq('equipo_id', equipoId).eq('practicante_id', practicanteId);
    if (error) setError(error.message);
    else await cargar();
    setOcupado(false);
  }

  /** Alta manual de alguien del roster que todavía no está en el equipo. */
  async function anadir(equipoId: string, practicanteId: string) {
    setOcupado(true); setError(null);
    const { error } = await supabase().from('miembros_equipo')
      .insert({ equipo_id: equipoId, practicante_id: practicanteId, rol_en_equipo: 'miembro' });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    void cargar();
  }

  async function cambiarRol(equipoId: string, practicanteId: string, rol: RolEnEquipo) {
    setOcupado(true); setError(null);
    const { error } = await supabase().from('miembros_equipo')
      .update({ rol_en_equipo: rol }).eq('equipo_id', equipoId).eq('practicante_id', practicanteId);
    setOcupado(false);
    if (error) { setError(error.message); return; }
    void cargar();
  }

  if (cargando) return <p className="empty">Cargando…</p>;

  return (
    <>
      {error && <p className="err" data-testid="error">{error}</p>}
      {aviso && <p className="hint" data-testid="aviso" style={{ color: 'var(--ok)' }}>{aviso}</p>}

      {/* El feed va arriba: es lo que se abre a diario. La ficha del equipo y
          la lista de miembros se consultan de vez en cuando. */}
      {equipos.length > 0 && (
        <>
          <h2 className="sec" style={{ marginTop: 4 }}>Lo que está pasando</h2>
          <Feed practicanteId={sesion.practicante.id} />

          {/* El ranking va aquí y no en el perfil porque es del EQUIPO: sin
              alguien con quien compararte, un ranking de uno no es nada.
              Del primer equipo, que con este tamaño es el único que hay. */}
          <RankingDelMes equipoId={equipos[0].id} practicanteId={sesion.practicante.id}
            roster={Object.fromEntries(roster.map((p) => [p.id, p.nombre]))} />
        </>
      )}

      {equipos.map((g) => {
        const admin = soyAdminDe(g.id);
        const suyos: MiembroConFicha[] = miembros
          .filter((m) => m.equipo_id === g.id && m.estado === 'activo')
          .map((m) => ({ ...m, ficha: roster.find((p) => p.id === m.practicante_id) }))
          .sort((a, b) => (a.rol_en_equipo === b.rol_en_equipo
            ? (a.ficha?.nombre ?? '').localeCompare(b.ficha?.nombre ?? '')
            : a.rol_en_equipo === 'admin' ? -1 : 1));
        const fuera = roster.filter(
          (p) => !miembros.some((m) => m.equipo_id === g.id && m.practicante_id === p.id),
        );

        return (
          <div key={g.id} data-testid={`equipo-${g.slug}`}>
            <div className="state" style={{ marginTop: 12 }}>
              <div className="lbl">{TEXTOS.tuEquipo}</div>
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
                  {m.ficha && (
                    <Avatar nombre={m.ficha.nombre} cinturon={m.ficha.cinturon}
                      grados={m.ficha.grados ?? 0} />
                  )}
                  <span className="n">
                    {m.ficha?.nombre ?? 'ficha borrada'}
                    <small>
                      {m.ficha?.cinturon}
                      {m.practicante_id === sesion.practicante.id && ' · tú'}
                      {!m.ficha?.usa_sistema && ' · sin cuenta'}
                    </small>
                  </span>
                  <span className="pill">{m.rol_en_equipo}</span>
                  {admin && m.practicante_id !== sesion.practicante.id && (
                    <>
                      <button className="ghost" disabled={ocupado}
                        style={{ padding: '7px 10px', fontSize: 12 }}
                        onClick={() => void cambiarRol(g.id, m.practicante_id,
                          m.rol_en_equipo === 'admin' ? 'miembro' : 'admin')}>
                        {m.rol_en_equipo === 'admin' ? 'Quitar admin' : 'Hacer admin'}
                      </button>
                      {/* La confirmacion dice QUE HACE, no "¿estas seguro?".
                          Sacar a alguien no borra nada suyo: cambia quien ve
                          que. Quien lo pulse tiene que saber eso. */}
                      <button className="ghost" disabled={ocupado}
                        data-testid={`sacar-${m.practicante_id}`}
                        style={{ padding: '7px 10px', fontSize: 12, color: 'var(--error)' }}
                        onClick={() => void sacar(g.id, m.practicante_id,
                          m.ficha?.nombre ?? 'esta persona')}>
                        Sacar
                      </button>
                    </>
                  )}
                </div>
              ))}
            </div>

            {admin && (
              <>
                {/* ============================================================
                    DOS CASOS QUE NO SE TRATAN IGUAL, Y NO ES UN DESCUIDO.

                    Un CONTACTO SIN CUENTA se añade directamente: es una ficha
                    que creaste tú, no hay nadie a quien preguntar.

                    Una PERSONA CON CUENTA no. Meterla en el equipo le da acceso
                    de lectura a los rolls de todos, y le da al equipo acceso a
                    los suyos. Eso es un cambio de privilegios sobre los datos
                    de otra persona, y no se hace por sorpresa. Para eso está el
                    código de unión: tú lo compartes, ella entra.
                    ============================================================ */}
                {fuera.filter((p) => !p.usa_sistema).length > 0 && (
                  <>
                    <h2 className="sec">Añadir del roster</h2>
                    <p className="hint" style={{ marginTop: 0 }}>
                      Contactos sin cuenta: fichas que creaste tú para poder
                      registrar rolls con ellos.
                    </p>
                    <div className="chips">
                      {fuera.filter((p) => !p.usa_sistema).map((p) => (
                        <button className="chip" key={p.id} disabled={ocupado}
                          data-testid={`anadir-${p.nombre}`}
                          onClick={() => void anadir(g.id, p.id)}>
                          + {p.nombre}
                        </button>
                      ))}
                    </div>
                  </>
                )}

                {fuera.some((p) => p.usa_sistema) && (
                  <>
                    <h2 className="sec">Con cuenta se entra con el código</h2>
                    <p className="hint" style={{ marginTop: 0 }}
                      data-testid="por-que-codigo">
                      A quien tiene cuenta no lo metemos nosotros: entrar en un{' '}
                      {TEXTOS.equipo} le da acceso a los rolls de todos y da al{' '}
                      {TEXTOS.equipo} acceso a los suyos. Eso lo decide cada uno.
                      Pásale el código <b>{g.codigo_union}</b> y entra en un toque.
                    </p>
                    <div className="tl">
                      {fuera.filter((p) => p.usa_sistema).map((p) => (
                        <div className="fila" key={p.id}>
                          <span className="n">{p.nombre}<small>tiene cuenta</small></span>
                          <span className="pill">le pasas el código</span>
                        </div>
                      ))}
                    </div>
                  </>
                )}
              </>
            )}
          </div>
        );
      })}

      <h2 className="sec">{equipos.length ? `Entrar en otro ${TEXTOS.equipo}` : `Entrar en un ${TEXTOS.equipo}`}</h2>
      {!equipos.length && (
        <p className="hint" style={{ marginTop: 0 }}>
          Todavía no estás en ninguno. Pide el código a quien lleve {TEXTOS.elEquipo}, o crea el tuyo.
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
        <label htmlFor="nuevo">Nombre {TEXTOS.delEquipo}</label>
        <input id="nuevo" value={nombreNuevo} data-testid="nombre-equipo"
          placeholder="Open mat de los domingos"
          onChange={(e) => setNombreNuevo(e.target.value)} />
        <div style={{ marginTop: 14 }}>
          <button className="ghost" type="submit" data-testid="crear-equipo"
            disabled={ocupado || nombreNuevo.trim().length < 2}>Crear {TEXTOS.equipo}</button>
        </div>
      </form>
      <p className="hint">
        No hace falta que sea un gimnasio: un {TEXTOS.quedada} entre amigos es un {TEXTOS.equipo} igual.
      </p>
    </>
  );
}
