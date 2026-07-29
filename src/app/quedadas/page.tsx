'use client';

import { useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { Marco, type Sesion } from '@/components/Marco';
import { supabase } from '@/lib/supabase';
import type {
  GrupoRow, InscripcionRow, MiembroRow, Modalidad, PracticanteRow, QuedadaRow,
} from '@/lib/database.types';

/**
 * Quedadas: los open mats del grupo.
 *
 * Las plazas NO se controlan aquí. Dos personas dándole a "apuntarme" a la vez
 * con una plaza libre es el caso clásico y el cliente no puede resolverlo: los
 * dos leen "queda una" antes de que ninguno escriba. Esta pantalla solo llama a
 * `apuntarse_a_quedada()`, que serializa con un lock y decide.
 *
 * Los invitados de fuera llegan con `?invitacion=TOKEN`. Un externo no tiene
 * permiso de lectura sobre `quedadas`, así que su quedada se resuelve por RPC.
 */

interface Ficha { id: string; nombre: string }

export default function Quedadas() {
  return <Marco titulo="Quedadas">{(s) => <Panel sesion={s} />}</Marco>;
}

function Panel({ sesion }: { sesion: Sesion }) {
  const params = useSearchParams();
  const invitacion = params.get('invitacion');

  const [grupos, setGrupos] = useState<GrupoRow[]>([]);
  const [miembros, setMiembros] = useState<MiembroRow[]>([]);
  const [quedadas, setQuedadas] = useState<QuedadaRow[]>([]);
  const [inscripciones, setInscripciones] = useState<InscripcionRow[]>([]);
  const [roster, setRoster] = useState<Ficha[]>([]);
  const [invitada, setInvitada] = useState<Record<string, unknown> | null>(null);
  const [cargando, setCargando] = useState(true);
  const [ocupado, setOcupado] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [creando, setCreando] = useState(false);

  const cargar = useCallback(async () => {
    const sb = supabase();
    const [g, m, q, i, p] = await Promise.all([
      sb.from('grupos').select('*').order('nombre'),
      sb.from('miembros_grupo').select('*'),
      sb.from('quedadas').select('*').order('fecha', { ascending: false }),
      sb.from('inscripciones').select('*'),
      sb.from('practicantes').select('id,nombre').order('nombre'),
    ]);
    setGrupos((g.data ?? []) as GrupoRow[]);
    setMiembros((m.data ?? []) as MiembroRow[]);
    setQuedadas((q.data ?? []) as QuedadaRow[]);
    setInscripciones((i.data ?? []) as InscripcionRow[]);
    setRoster((p.data ?? []) as Ficha[]);
    setCargando(false);
  }, []);

  useEffect(() => { void cargar(); }, [cargar]);

  // La quedada de una invitación no se puede leer de la tabla si no eres del
  // grupo: se pide por RPC, que devuelve esa y solo esa.
  useEffect(() => {
    if (!invitacion) return;
    void supabase().rpc('quedada_por_token', { p_token: invitacion })
      .then(({ data }) => {
        const fila = Array.isArray(data) ? data[0] : data;
        setInvitada((fila ?? null) as Record<string, unknown> | null);
      });
  }, [invitacion]);

  const soyAdminDe = (grupoId: string) => miembros.some(
    (m) => m.grupo_id === grupoId && m.practicante_id === sesion.practicante.id
      && m.rol === 'admin' && m.estado === 'activo',
  );
  const miInscripcion = (qid: string) => inscripciones.find(
    (i) => i.quedada_id === qid && i.practicante_id === sesion.practicante.id
      && i.estado !== 'cancelado',
  );
  const apuntados = (qid: string) => inscripciones.filter(
    (i) => i.quedada_id === qid && i.estado === 'apuntado',
  );

  async function apuntarse(qid: string, token?: string | null) {
    setOcupado(true); setError(null); setAviso(null);
    const { data, error } = await supabase().rpc('apuntarse_a_quedada', {
      p_quedada: qid, p_token: token ?? null,
    });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    const r = data as { estado?: string; orden?: number } | null;
    setAviso(r?.estado === 'lista_espera'
      ? `Sin plazas: estás en la lista de espera, el ${r.orden}º. Si alguien se borra, subes solo.`
      : 'Apuntado.');
    void cargar();
  }

  async function borrarse(qid: string) {
    setOcupado(true); setError(null); setAviso(null);
    const { data, error } = await supabase().rpc('cancelar_inscripcion', { p_quedada: qid });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    const r = data as { promovido?: string | null } | null;
    const quien = roster.find((p) => p.id === r?.promovido)?.nombre;
    setAviso(quien ? `Te has borrado. Sube ${quien} desde la lista de espera.` : 'Te has borrado.');
    void cargar();
  }

  async function crear(datos: {
    grupo_id: string; titulo: string; fecha: string; hora_inicio: string;
    lugar: string; plazas_max: string; modalidad: Modalidad; admite_externos: boolean;
  }) {
    setOcupado(true); setError(null);
    const { error } = await supabase().from('quedadas').insert({
      grupo_id: datos.grupo_id,
      titulo: datos.titulo.trim(),
      fecha: datos.fecha,
      hora_inicio: datos.hora_inicio || null,
      lugar: datos.lugar.trim() || null,
      plazas_max: datos.plazas_max ? Number(datos.plazas_max) : null,
      modalidad: datos.modalidad,
      admite_externos: datos.admite_externos,
      creado_por: sesion.practicante.id,
    });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    setCreando(false); setAviso('Quedada creada.');
    void cargar();
  }

  async function cerrar(qid: string) {
    setOcupado(true); setError(null);
    const { error } = await supabase().from('quedadas')
      .update({ estado: 'cerrada' }).eq('id', qid);
    setOcupado(false);
    if (error) { setError(error.message); return; }
    void cargar();
  }

  if (cargando) return <p className="empty">Cargando…</p>;

  const hoy = new Date().toISOString().slice(0, 10);
  const proximas = quedadas.filter((q) => q.fecha >= hoy && q.estado !== 'cancelada');
  const pasadas = quedadas.filter((q) => q.fecha < hoy || q.estado === 'cerrada');
  const puedoCrear = grupos.some((g) => soyAdminDe(g.id));

  return (
    <>
      {error && <p className="err" data-testid="error">{error}</p>}
      {aviso && <p className="hint" data-testid="aviso" style={{ color: 'var(--good)' }}>{aviso}</p>}

      {/* Invitación de fuera: se ve la quedada y nada más del grupo. */}
      {invitacion && invitada && (
        <div className="state" data-testid="invitacion" style={{ marginTop: 10 }}>
          <div className="lbl">Te han invitado</div>
          <div className="pos">{String(invitada.titulo)}</div>
          <div className="rol">
            {String(invitada.grupo)} · {String(invitada.fecha)}
            {invitada.lugar ? ` · ${String(invitada.lugar)}` : ''}
            {invitada.libres != null && ` · ${String(invitada.libres)} plazas libres`}
          </div>
          <div style={{ marginTop: 12 }}>
            <button className="primary" disabled={ocupado} data-testid="apuntarse-invitado"
              onClick={() => void apuntarse(String(invitada.id), invitacion)}>
              Apuntarme
            </button>
          </div>
          <p className="hint" style={{ marginBottom: 0 }}>
            Este enlace te deja ver y apuntarte a esta quedada. No te da acceso a nada
            más del grupo.
          </p>
        </div>
      )}
      {invitacion && !invitada && (
        <p className="err" data-testid="invitacion-mala">
          Ese enlace no vale, o la quedada ya no admite invitados.
        </p>
      )}

      {!grupos.length && (
        <div className="state" data-testid="sin-grupo" style={{ marginTop: 12 }}>
          <div className="lbl">Sin grupo</div>
          <div className="pos" style={{ fontSize: 17 }}>Las quedadas son de un grupo</div>
          <p className="hint" style={{ margin: '8px 0 0' }}>
            Entra en uno desde la pestaña Grupo y aquí verás sus open mats.
          </p>
        </div>
      )}

      {puedoCrear && (
        <div style={{ marginTop: 12 }}>
          <button className="ghost" data-testid="nueva-quedada"
            onClick={() => setCreando((v) => !v)}>
            {creando ? 'Cancelar' : '+ Nueva quedada'}
          </button>
        </div>
      )}
      {creando && (
        <Formulario grupos={grupos.filter((g) => soyAdminDe(g.id))}
          ocupado={ocupado} onCrear={crear} />
      )}

      {proximas.length > 0 && <h2 className="sec">Próximas</h2>}
      {proximas.map((q) => {
        const mia = miInscripcion(q.id);
        const dentro = apuntados(q.id);
        const libres = q.plazas_max == null ? null : q.plazas_max - dentro.length;
        const admin = soyAdminDe(q.grupo_id);
        return (
          <div className="tarjeta-q" key={q.id} data-testid={`quedada-${q.id}`}
            style={{
              background: 'var(--surface)', border: '1px solid var(--border)',
              borderRadius: 13, padding: 14, marginTop: 10,
            }}>
            <div style={{ fontSize: 16, fontWeight: 620 }}>{q.titulo}</div>
            <div style={{ fontSize: 12.5, color: 'var(--ink-2)', marginTop: 3 }}>
              {q.fecha}{q.hora_inicio && ` · ${q.hora_inicio.slice(0, 5)}`}
              {q.lugar && ` · ${q.lugar}`} · {q.modalidad === 'gi' ? 'Gi' : 'No-gi'}
            </div>
            <div style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 3 }}>
              {dentro.length} apuntados
              {libres != null && (libres > 0
                ? ` · ${libres} ${libres === 1 ? 'plaza libre' : 'plazas libres'}`
                : ' · sin plazas')}
              {mia?.estado === 'lista_espera' && ` · estás el ${mia.orden}º en espera`}
            </div>

            <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
              {mia ? (
                <button className="ghost" disabled={ocupado}
                  data-testid={`borrarse-${q.id}`} onClick={() => void borrarse(q.id)}>
                  {mia.estado === 'apuntado' ? 'Borrarme' : 'Salir de la lista'}
                </button>
              ) : (
                <button className="primary" disabled={ocupado || q.estado !== 'abierta'}
                  data-testid={`apuntarse-${q.id}`} onClick={() => void apuntarse(q.id)}>
                  {libres === 0 ? 'A la lista de espera' : 'Apuntarme'}
                </button>
              )}
              {admin && q.estado === 'abierta' && (
                <button className="ghost" disabled={ocupado}
                  data-testid={`cerrar-${q.id}`} onClick={() => void cerrar(q.id)}>
                  Cerrar
                </button>
              )}
            </div>

            {admin && (
              <>
                <h2 className="sec" style={{ marginBottom: 6 }}>Quién viene</h2>
                <div className="tl">
                  {inscripciones.filter((i) => i.quedada_id === q.id && i.estado !== 'cancelado')
                    .sort((a, b) => (a.estado === b.estado ? 0 : a.estado === 'apuntado' ? -1 : 1))
                    .map((i) => (
                      <div className="fila" key={i.id}>
                        <span className="n">
                          {roster.find((p) => p.id === i.practicante_id)?.nombre ?? '—'}
                          {i.es_externo && <small>de fuera del grupo</small>}
                        </span>
                        <span className="pill">
                          {i.estado === 'apuntado' ? 'viene' : `espera ${i.orden}`}
                        </span>
                      </div>
                    ))}
                </div>
                <p className="hint">
                  Enlace para invitar a alguien de fuera:{' '}
                  <code style={{ wordBreak: 'break-all' }}>
                    /quedadas?invitacion={q.token_invitacion}
                  </code>
                </p>
              </>
            )}
          </div>
        );
      })}

      {pasadas.length > 0 && <h2 className="sec">Pasadas</h2>}
      {pasadas.map((q) => (
        <div className="fila" key={q.id} style={{ marginTop: 8 }}>
          <span className="n">
            {q.titulo}
            <small>{q.fecha} · {apuntados(q.id).length} apuntados</small>
          </span>
          <span className="pill">{q.estado === 'cerrada' ? 'cerrada' : 'pasada'}</span>
        </div>
      ))}
      {pasadas.length > 0 && (
        <p className="hint">
          El informe de cada quedada —ranking y títulos— llega en el siguiente bloque.
        </p>
      )}

      {grupos.length > 0 && !proximas.length && !pasadas.length && (
        <p className="hint" data-testid="sin-quedadas">
          Todavía no hay ninguna quedada.
          {puedoCrear ? ' Crea la primera con el botón de arriba.' : ' Cuando el admin cree una, aparecerá aquí.'}
        </p>
      )}
    </>
  );
}

function Formulario(
  { grupos, ocupado, onCrear }: {
    grupos: GrupoRow[]; ocupado: boolean;
    onCrear: (d: {
      grupo_id: string; titulo: string; fecha: string; hora_inicio: string;
      lugar: string; plazas_max: string; modalidad: Modalidad; admite_externos: boolean;
    }) => void;
  },
) {
  const [grupo, setGrupo] = useState(grupos[0]?.id ?? '');
  const [titulo, setTitulo] = useState('Open mat');
  const [fecha, setFecha] = useState(new Date().toISOString().slice(0, 10));
  const [hora, setHora] = useState('11:00');
  const [lugar, setLugar] = useState('');
  const [plazas, setPlazas] = useState('');
  const [modalidad, setModalidad] = useState<Modalidad>('nogi');
  const [externos, setExternos] = useState(true);

  return (
    <form onSubmit={(e) => {
      e.preventDefault();
      onCrear({
        grupo_id: grupo, titulo, fecha, hora_inicio: hora, lugar,
        plazas_max: plazas, modalidad, admite_externos: externos,
      });
    }}>
      {grupos.length > 1 && (
        <>
          <label htmlFor="grupo">Grupo</label>
          <select id="grupo" value={grupo} onChange={(e) => setGrupo(e.target.value)}>
            {grupos.map((g) => <option key={g.id} value={g.id}>{g.nombre}</option>)}
          </select>
        </>
      )}
      <label htmlFor="titulo">Título</label>
      <input id="titulo" value={titulo} data-testid="q-titulo"
        onChange={(e) => setTitulo(e.target.value)} />
      <label htmlFor="fecha">Día</label>
      <input id="fecha" type="date" value={fecha} data-testid="q-fecha"
        onChange={(e) => setFecha(e.target.value)} />
      <label htmlFor="hora">Hora</label>
      <input id="hora" type="time" value={hora}
        onChange={(e) => setHora(e.target.value)} />
      <label htmlFor="lugar">Dónde</label>
      <input id="lugar" value={lugar} placeholder="Gullo, tatami grande"
        onChange={(e) => setLugar(e.target.value)} />
      <label htmlFor="plazas">Plazas (vacío = sin límite)</label>
      <input id="plazas" type="number" min={1} value={plazas} data-testid="q-plazas"
        onChange={(e) => setPlazas(e.target.value)} />

      <h2 className="sec">Modalidad</h2>
      <div className="chips">
        {(['gi', 'nogi'] as const).map((m) => (
          <button key={m} type="button" className="chip"
            style={modalidad === m ? { borderColor: 'var(--yo)', color: 'var(--yo)' } : undefined}
            onClick={() => setModalidad(m)}>{m === 'gi' ? 'Gi' : 'No-gi'}</button>
        ))}
      </div>

      <h2 className="sec">Gente de fuera</h2>
      <div className="chips">
        <button type="button" className="chip"
          style={externos ? { borderColor: 'var(--yo)', color: 'var(--yo)' } : undefined}
          onClick={() => setExternos(true)}>Sí, con enlace</button>
        <button type="button" className="chip"
          style={!externos ? { borderColor: 'var(--yo)', color: 'var(--yo)' } : undefined}
          onClick={() => setExternos(false)}>Solo el grupo</button>
      </div>
      <p className="hint">
        Con invitados, el enlace deja ver y apuntarse a esta quedada y nada más:
        no da acceso al grupo ni a los datos de los demás.
      </p>

      <div style={{ marginTop: 16 }}>
        <button className="primary" type="submit" data-testid="crear-quedada"
          disabled={ocupado || !grupo || titulo.trim().length < 2}>Crear</button>
      </div>
    </form>
  );
}
