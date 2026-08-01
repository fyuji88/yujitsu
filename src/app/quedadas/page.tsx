'use client';

import { useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { Marco, type Sesion } from '@/components/Marco';
import { supabase } from '@/lib/supabase';
import type { PostgrestError } from '@supabase/supabase-js';
import { Cargando, PanelError } from '@/components/Estado';
import { TEXTOS } from '@/lib/textos/es';
import type {
  EquipoRow, InscripcionRow, MiembroRow, Modalidad, PracticanteRow, QuedadaRow,
} from '@/lib/database.types';

/**
 * Quedadas: los open mats del equipo.
 *
 * Las plazas NO se controlan aquí. Dos personas dándole a "apuntarme" a la vez
 * con una plaza libre es el caso clásico y el cliente no puede resolverlo: los
 * dos leen "queda una" antes de que ninguno escriba. Esta pantalla solo llama a
 * `apuntarse_a_quedada()`, que serializa con un lock y decide.
 *
 * Los invitados de fuera llegan con `?invitacion=TOKEN`. Un externo no tiene
 * permiso de lectura sobre `quedadas`, así que su quedada se resuelve por RPC.
 */

/**  distingue al contacto sin cuenta, que es a quien mas sentido
 * tiene apuntar tu: entrena y no usa la app. */
interface Ficha { id: string; nombre: string; usa_sistema: boolean }

interface Informe {
  quedada: { titulo: string; fecha: string; lugar: string | null };
  asistentes: number;
  rolls: number;
  ranking: { id: string; nombre: string; cinturon: string; rolls: number;
             media: number; favor: number; contra: number }[];
  titulos: { titulo: string; quien: string; porque: string;
             valor: number | null }[];
}

export default function Quedadas() {
  return <Marco titulo={TEXTOS.quedadas}>{(s) => <Panel sesion={s} />}</Marco>;
}

function Panel({ sesion }: { sesion: Sesion }) {
  const params = useSearchParams();
  const invitacion = params.get('invitacion');

  const [equipos, setEquipos] = useState<EquipoRow[]>([]);
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
  const [informe, setInforme] = useState<{ quedada: string; datos: Informe } | null>(null);
  const [editando, setEditando] = useState<string | null>(null);
  /**
   * El fallo de la CARGA, aparte del de las acciones (`error`).
   *
   * Son cosas distintas y por eso son dos estados: `error` es «tu clic no se
   * pudo hacer» y va junto al botón; esto es «no sé qué hay», y tiene que tapar
   * la lista entera, porque una lista vacía por un fallo se lee igual que una
   * lista vacía de verdad.
   */
  const [falloCarga, setFalloCarga] = useState<PostgrestError | null>(null);

  const cargar = useCallback(async () => {
    const sb = supabase();
    setFalloCarga(null);
    const [g, m, q, i, p] = await Promise.all([
      sb.from('equipos').select('*').order('nombre'),
      sb.from('miembros_equipo').select('*'),
      sb.from('quedadas').select('*').order('fecha', { ascending: false }),
      sb.from('inscripciones').select('*'),
      sb.from('practicantes').select('id,nombre,usa_sistema').order('nombre'),
    ]);
    // SI FALLA UNA, FALLA LA PANTALLA. Antes se cogía `data ?? []` de las cinco,
    // así que un fallo en `quedadas` pintaba «no hay ninguna quedada» y un fallo
    // en `inscripciones` pintaba a todo el mundo sin apuntar. Media pantalla
    // verdadera y media inventada es peor que una pantalla que dice que falló.
    const malo = [g, m, q, i, p].find((r) => r.error)?.error;
    if (malo) { setFalloCarga(malo); setCargando(false); return; }
    setEquipos((g.data ?? []) as EquipoRow[]);
    setMiembros((m.data ?? []) as MiembroRow[]);
    setQuedadas((q.data ?? []) as QuedadaRow[]);
    setInscripciones((i.data ?? []) as InscripcionRow[]);
    setRoster((p.data ?? []) as Ficha[]);
    setCargando(false);
  }, []);

  useEffect(() => { void cargar(); }, [cargar]);

  // La quedada de una invitación no se puede leer de la tabla si no eres del
  // equipo: se pide por RPC, que devuelve esa y solo esa.
  useEffect(() => {
    if (!invitacion) return;
    void supabase().rpc('quedada_por_token', { p_token: invitacion })
      .then(({ data, error }) => {
        // Quien llega por invitación no tiene NADA más en esta pantalla: si
        // esto falla en silencio ve una página en blanco y se va. Es la primera
        // impresión de alguien de otro gimnasio.
        if (error) { setFalloCarga(error); return; }
        const fila = Array.isArray(data) ? data[0] : data;
        setInvitada((fila ?? null) as Record<string, unknown> | null);
      });
  }, [invitacion]);

  /**
   * Editar. La RLS ya deja al admin hacer el update; aqui solo se manda lo que
   * cambia. Las reglas de plazas NO estan aqui: viven en el trigger, porque
   * cualquier cosa que solo viva en React se salta con una llamada a la API.
   */
  async function editar(qid: string, cambios: Partial<QuedadaRow>) {
    setOcupado(true); setError(null);
    const { error } = await supabase().from('quedadas').update(cambios).eq('id', qid);
    // El mensaje del trigger ya trae el numero ("hay 8 apuntados"): se enseña
    // tal cual en vez de traducirlo a un generico que no dice nada.
    if (error) setError(error.message);
    else { setEditando(null); await cargar(); }
    setOcupado(false);
  }

  /**
   * Cancelar es la accion destructiva por defecto, y NO borra.
   *
   * Un Open Mat cancelado sigue viendose, tachado y con sus apuntados: la gente
   * necesita enterarse de que no hay entreno, y ese es justo el momento en que
   * no puedes hacerlo desaparecer.
   */
  async function cancelar(qid: string) {
    if (!confirm('¿Cancelar este Open Mat? Sigue viéndose, tachado, para que la gente se entere.')) return;
    await editar(qid, { estado: 'cancelada' });
  }

  /**
   * Borrar SOLO si no cuelga nada. Comprobado contra el esquema:
   *   - `inscripciones` y `quedada_informes` van en CASCADE: borrar se lleva
   *     los apuntados y el informe sin avisar;
   *   - `sesiones` va en SET NULL: los rolls no se pierden, pero se
   *     DESENGANCHAN, y con eso los cuatro logros de ambito quedada dejan de
   *     contar para esas sesiones. Nadie se entera nunca.
   * Borrar parece limpieza y en realidad cambia el historial de otra gente en
   * silencio. Por eso el boton no existe si hay algo colgando.
   */
  const sePuedeBorrar = (qid: string) =>
    inscripciones.filter((i) => i.quedada_id === qid).length === 0;

  async function borrar(qid: string) {
    if (!confirm('¿Borrar este Open Mat? No queda nada apuntado, así que no se pierde nada.')) return;
    setOcupado(true); setError(null);
    const { error } = await supabase().from('quedadas').delete().eq('id', qid);
    if (error) setError(error.message);
    else await cargar();
    setOcupado(false);
  }

  /**
   * Enganchar las sesiones del día a este Open Mat.
   *
   * EXISTE PORQUE ALGUIEN SE VA A OLVIDAR. Poder arreglarlo al día siguiente es
   * la diferencia entre tener informe y tener un agujero — que es exactamente
   * lo que teníamos: 0 de 71 sesiones enganchadas, y tres informes vacíos.
   */
  async function engancharDelDia(qid: string) {
    setOcupado(true); setError(null);
    const { data, error } = await supabase().rpc('enganchar_del_dia', { p_quedada: qid });
    if (error) setError(error.message);
    else {
      setAviso(Number(data) > 0
        ? `Enganchadas ${data} ${Number(data) === 1 ? 'sesión' : 'sesiones'}.`
        : 'No había ninguna sesión de ese día que pudieras enganchar.');
      await cargar();
    }
    setOcupado(false);
  }

  /** Apuntar a otra persona. Por la RPC, nunca con un insert directo. */
  async function apuntarA(qid: string, practicanteId: string) {
    setOcupado(true); setError(null);
    const { error } = await supabase().rpc('apuntarse_a_quedada', {
      p_quedada: qid, p_token: null, p_practicante: practicanteId,
    });
    if (error) setError(error.message);
    else await cargar();
    setOcupado(false);
  }

  /** Quitar a otra persona. Promueve al primero de la lista, en la RPC. */
  async function quitarA(qid: string, practicanteId: string, nombre: string) {
    if (!confirm(`¿Quitar a ${nombre}? Si había alguien en lista de espera, sube.`)) return;
    setOcupado(true); setError(null);
    const { error } = await supabase().rpc('cancelar_inscripcion', {
      p_quedada: qid, p_practicante: practicanteId,
    });
    if (error) setError(error.message);
    else await cargar();
    setOcupado(false);
  }

  const soyAdminDe = (equipoId: string) => miembros.some(
    (m) => m.equipo_id === equipoId && m.practicante_id === sesion.practicante.id
      && m.rol_en_equipo === 'admin' && m.estado === 'activo',
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
    equipo_id: string; titulo: string; fecha: string; hora_inicio: string;
    lugar: string; plazas_max: string; modalidad: Modalidad; admite_externos: boolean;
  }) {
    setOcupado(true); setError(null);
    const { error } = await supabase().from('quedadas').insert({
      equipo_id: datos.equipo_id,
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

  /**
   * Cerrar calcula el informe y lo CONGELA. No se hace con un update del
   * estado: el informe se guarda tal como estaba esa tarde, para que corregir
   * un roll el martes no cambie lo que ya se compartió el domingo.
   */
  /**
   * Cerrar enseña ANTES lo que va a incluir.
   *
   * Cerrar es de una sola dirección, y hasta ahora escribía informes vacíos sin
   * decir nada: hay tres en producción con cero rolls. Ahora la base se planta
   * si no hay nada enganchado, y aquí se ve el alcance antes de pulsar.
   */
  async function cerrar(qid: string) {
    const { data: alc } = await supabase().rpc('alcance_quedada', { p_quedada: qid });
    const a = (alc ?? {}) as { rolls?: number; personas?: number };
    if (!a.rolls) {
      setError('No hay ninguna sesión enganchada a este Open Mat: el informe '
        + 'saldría vacío. Pulsa «Enganchar las sesiones del día» y vuelve a cerrarlo.');
      return;
    }
    if (!confirm(
      `Se van a incluir ${a.rolls} rolls de ${a.personas} personas.

`
      + 'Cerrar publica el informe y no se deshace.',
    )) return;
    return cerrarDeVerdad(qid);
  }

  async function cerrarDeVerdad(qid: string) {
    setOcupado(true); setError(null);
    const { data, error } = await supabase().rpc('cerrar_quedada', { p_quedada: qid });
    setOcupado(false);
    if (error) { setError(error.message); return; }
    setInforme({ quedada: qid, datos: data as Informe });
    setAviso('Quedada cerrada y informe publicado.');
    void cargar();
  }

  async function verInforme(qid: string) {
    setOcupado(true); setError(null);
    const { data, error: e } = await supabase().from('quedada_informes')
      .select('datos').eq('quedada_id', qid);
    setOcupado(false);
    // «No tiene informe» y «no pude leerlo» acaban en el mismo sitio si no se
    // mira el error, y solo una de las dos frases es verdad.
    if (e) { setError(`No se pudo leer el informe: ${e.message}`); return; }
    const fila = (data ?? [])[0] as { datos: Informe } | undefined;
    if (!fila) { setError(`Ese ${TEXTOS.quedada} todavía no tiene informe.`); return; }
    setInforme({ quedada: qid, datos: fila.datos });
  }

  if (cargando) return <Cargando que={TEXTOS.quedadas.toLowerCase()} testid="quedadas-cargando" />;

  if (falloCarga) {
    return <PanelError error={falloCarga} que={TEXTOS.quedadas.toLowerCase()}
      testid="quedadas-error" onReintentar={() => { setCargando(true); void cargar(); }} />;
  }

  const hoy = new Date().toISOString().slice(0, 10);
  // UN OPEN MAT CANCELADO SIGUE EN LA LISTA, tachado. Antes se filtraba fuera
  // de 'proximas' y no entraba en 'pasadas' —su fecha aun no ha llegado—, asi
  // que desaparecia de las dos: la unica señal de que se ha cancelado era que
  // ya no estaba. Justo al reves de lo que hace falta, porque ese es el momento
  // en que la gente TIENE que enterarse de que no hay entreno.
  // CANCELADO SI, CERRADO NO. Un cancelado se queda arriba y tachado, que es el
  // punto: la gente tiene que enterarse de que no hay entreno. Pero uno CERRADO
  // con fecha futura casaba tambien con 'pasadas' —que incluye todo lo cerrado—
  // y salia DUPLICADO en la pantalla. Lo introduje yo al quitar el filtro de
  // estado entero en vez de acotarlo.
  const proximas = quedadas.filter((q) => q.fecha >= hoy && q.estado !== 'cerrada');
  const pasadas = quedadas.filter((q) => q.fecha < hoy || q.estado === 'cerrada');
  const puedoCrear = equipos.some((g) => soyAdminDe(g.id));

  return (
    <>
      {error && <p className="err" data-testid="error">{error}</p>}
      {aviso && <p className="hint" data-testid="aviso" style={{ color: 'var(--ok)' }}>{aviso}</p>}

      {/* Invitación de fuera: se ve la quedada y nada más del equipo. */}
      {invitacion && invitada && (
        <div className="state" data-testid="invitacion" style={{ marginTop: 10 }}>
          <div className="lbl">Te han invitado</div>
          <div className="pos">{String(invitada.titulo)}</div>
          <div className="rol">
            {String(invitada.equipo)} · {String(invitada.fecha)}
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
            Este enlace te deja ver y apuntarte a este {TEXTOS.quedada}. No te da acceso a nada
            más del equipo.
          </p>
        </div>
      )}
      {invitacion && !invitada && (
        <p className="err" data-testid="invitacion-mala">
          Ese enlace no vale, o el {TEXTOS.quedada} ya no admite invitados.
        </p>
      )}

      {!equipos.length && (
        <div className="state" data-testid="sin-equipo" style={{ marginTop: 12 }}>
          <div className="lbl">Sin equipo</div>
          <div className="pos" style={{ fontSize: 17 }}>
            {`Los ${TEXTOS.quedadas} son de un ${TEXTOS.equipo}`}
          </div>
          <p className="hint" style={{ margin: '8px 0 0' }}>
            Entra en uno desde la pestaña {TEXTOS.equipo} y aquí verás sus {TEXTOS.quedadas}.
          </p>
        </div>
      )}

      {puedoCrear && (
        <div style={{ marginTop: 12 }}>
          <button className="ghost" data-testid="nueva-quedada"
            onClick={() => setCreando((v) => !v)}>
            {creando ? 'Cancelar' : `+ Nuevo ${TEXTOS.quedada}`}
          </button>
        </div>
      )}
      {creando && (
        <Formulario equipos={equipos.filter((g) => soyAdminDe(g.id))}
          ocupado={ocupado} onCrear={crear} />
      )}

      {proximas.length > 0 && <h2 className="sec">Próximas</h2>}
      {proximas.map((q) => {
        const mia = miInscripcion(q.id);
        const dentro = apuntados(q.id);
        const libres = q.plazas_max == null ? null : q.plazas_max - dentro.length;
        const admin = soyAdminDe(q.equipo_id);
        return (
          <div className="tarjeta-q" key={q.id} data-testid={`quedada-${q.id}`}
            style={{
              background: 'var(--superficie)', border: '1px solid var(--borde)',
              borderRadius: 13, padding: 14, marginTop: 10,
            }}>
            <div style={{ fontSize: 16, fontWeight: 620 }}>
              {q.estado === 'cancelada' ? (
                <span data-testid={`cancelada-${q.id}`}
                  style={{ textDecoration: 'line-through', color: 'var(--tenue)' }}>
                  {q.titulo}
                </span>
              ) : q.titulo}
              {q.estado === 'cancelada' && (
                <span className="pill" style={{ marginLeft: 8, color: 'var(--error)' }}>
                  cancelado
                </span>
              )}
            </div>
            <div style={{ fontSize: 12.5, color: 'var(--texto-2)', marginTop: 3 }}>
              {q.fecha}{q.hora_inicio && ` · ${q.hora_inicio.slice(0, 5)}`}
              {q.lugar && ` · ${q.lugar}`} · {q.modalidad === 'gi' ? 'Gi' : 'No-gi'}
            </div>
            <div style={{ fontSize: 12.5, color: 'var(--tenue)', marginTop: 3 }}>
              {dentro.length} apuntados
              {libres != null && (libres > 0
                ? ` · ${libres} ${libres === 1 ? 'plaza libre' : 'plazas libres'}`
                : ' · sin plazas')}
              {mia?.estado === 'lista_espera' && ` · estás el ${mia.orden_en_lista}º en espera`}
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
                <>
                  <button className="ghost" disabled={ocupado}
                    data-testid={`editar-${q.id}`}
                    onClick={() => setEditando(editando === q.id ? null : q.id)}>
                    Editar
                  </button>
                  {/* De aqui salen el informe, el ranking, los titulos y los
                      tres logros de ambito quedada. Sin esto la columna
                      `sesiones.quedada_id` no la escribia nadie: 0 de 71. */}
                  <button className="ghost" disabled={ocupado}
                    data-testid={`enganchar-${q.id}`}
                    onClick={() => void engancharDelDia(q.id)}>
                    Enganchar las sesiones del día
                  </button>
                  <button className="ghost" disabled={ocupado}
                    data-testid={`cerrar-${q.id}`} onClick={() => void cerrar(q.id)}>
                    Cerrar
                  </button>
                  <button className="ghost" disabled={ocupado}
                    data-testid={`cancelar-${q.id}`}
                    style={{ color: 'var(--error)' }}
                    onClick={() => void cancelar(q.id)}>
                    Cancelar
                  </button>
                </>
              )}
              {/* Borrar SOLO si no cuelga nada. Si hay alguien apuntado, el
                  boton no existe — no se enseña deshabilitado, porque un boton
                  apagado invita a preguntar por que y este no tiene respuesta
                  buena: la respuesta es "usa Cancelar". */}
              {admin && sePuedeBorrar(q.id) && (
                <button className="ghost" disabled={ocupado}
                  data-testid={`borrar-${q.id}`}
                  style={{ color: 'var(--error)' }}
                  onClick={() => void borrar(q.id)}>
                  Borrar
                </button>
              )}
            </div>

            {admin && editando === q.id && (
              <Editar q={q} ocupado={ocupado}
                onGuardar={(c) => void editar(q.id, c)}
                onCancelar={() => setEditando(null)} />
            )}

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
                          {i.es_externo && <small>de fuera del equipo</small>}
                        </span>
                        <span className="pill">
                          {i.estado === 'apuntado' ? 'viene' : `espera ${i.orden_en_lista}`}
                        </span>
                        <button className="ghost" disabled={ocupado}
                          data-testid={`quitar-${q.id}-${i.practicante_id}`}
                          style={{ padding: '7px 10px', fontSize: 12 }}
                          onClick={() => void quitarA(q.id, i.practicante_id,
                            roster.find((p) => p.id === i.practicante_id)?.nombre ?? 'esta persona')}>
                          Quitar
                        </button>
                      </div>
                    ))}
                </div>

                {/* APUNTAR A OTRO. Se ofrecen los del equipo y los contactos
                    sin cuenta: los contactos son justo para esto, gente que
                    entrena y no usa la app. Va por la RPC, que es la que sabe
                    de plazas y de lista de espera. */}
                {q.estado === 'abierta' && (() => {
                  const yaEstan = new Set(inscripciones
                    .filter((i) => i.quedada_id === q.id && i.estado !== 'cancelado')
                    .map((i) => i.practicante_id));
                  const faltan = roster.filter((p) => !yaEstan.has(p.id));
                  if (!faltan.length) return null;
                  return (
                    <>
                      <h2 className="sec" style={{ marginBottom: 6 }}>Apuntar a alguien</h2>
                      <div className="chips">
                        {faltan.map((p) => (
                          <button className="chip" key={p.id} disabled={ocupado}
                            data-testid={`apuntar-${q.id}-${p.id}`}
                            onClick={() => void apuntarA(q.id, p.id)}>
                            + {p.nombre}
                            {!p.usa_sistema && <small>sin cuenta</small>}
                          </button>
                        ))}
                      </div>
                    </>
                  );
                })()}
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
          {q.estado === 'cerrada' ? (
            <button className="ghost" disabled={ocupado}
              data-testid={`informe-${q.id}`}
              style={{ padding: '7px 11px', fontSize: 12 }}
              onClick={() => void verInforme(q.id)}>Ver informe</button>
          ) : soyAdminDe(q.equipo_id) ? (
            <button className="ghost" disabled={ocupado}
              data-testid={`cerrar-${q.id}`}
              style={{ padding: '7px 11px', fontSize: 12 }}
              onClick={() => void cerrar(q.id)}>Cerrar y publicar</button>
          ) : <span className="pill">pasada</span>}
        </div>
      ))}

      {informe && <VistaInforme datos={informe.datos} onCerrar={() => setInforme(null)} />}

      {equipos.length > 0 && !proximas.length && !pasadas.length && (
        <p className="hint" data-testid="sin-quedadas">
          Todavía no hay ningún {TEXTOS.quedada}.
          {puedoCrear ? ' Crea el primero con el botón de arriba.' : ' Cuando el admin cree uno, aparecerá aquí.'}
        </p>
      )}
    </>
  );
}

function Formulario(
  { equipos, ocupado, onCrear }: {
    equipos: EquipoRow[]; ocupado: boolean;
    onCrear: (d: {
      equipo_id: string; titulo: string; fecha: string; hora_inicio: string;
      lugar: string; plazas_max: string; modalidad: Modalidad; admite_externos: boolean;
    }) => void;
  },
) {
  const [equipo, setEquipo] = useState(equipos[0]?.id ?? '');
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
        equipo_id: equipo, titulo, fecha, hora_inicio: hora, lugar,
        plazas_max: plazas, modalidad, admite_externos: externos,
      });
    }}>
      {equipos.length > 1 && (
        <>
          <label htmlFor="equipo">{TEXTOS.equipo}</label>
          <select id="equipo" value={equipo} onChange={(e) => setEquipo(e.target.value)}>
            {equipos.map((g) => <option key={g.id} value={g.id}>{g.nombre}</option>)}
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
            style={modalidad === m ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
            onClick={() => setModalidad(m)}>{m === 'gi' ? 'Gi' : 'No-gi'}</button>
        ))}
      </div>

      <h2 className="sec">Gente de fuera</h2>
      <div className="chips">
        <button type="button" className="chip"
          style={externos ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
          onClick={() => setExternos(true)}>Sí, con enlace</button>
        <button type="button" className="chip"
          style={!externos ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
          onClick={() => setExternos(false)}>Solo el equipo</button>
      </div>
      <p className="hint">
        Con invitados, el enlace deja ver y apuntarse a este {TEXTOS.quedada} y nada más:
        no da acceso al equipo ni a los datos de los demás.
      </p>

      <div style={{ marginTop: 16 }}>
        <button className="primary" type="submit" data-testid="crear-quedada"
          disabled={ocupado || !equipo || titulo.trim().length < 2}>Crear</button>
      </div>
    </form>
  );
}

/**
 * El informe de una quedada.
 *
 * Se pinta lo que se guardó al cerrarla, no un cálculo nuevo: si alguien
 * corrige un roll el martes, esto sigue diciendo lo que pasó el domingo.
 *
 * El ranking va por puntos estimados por roll y no por sumisiones, porque
 * premia a quien domina aunque no finalice — que es lo que se quería medir.
 */
function VistaInforme(
  { datos, onCerrar }: { datos: Informe; onCerrar: () => void },
) {
  return (
    <div data-testid="informe" style={{
      background: 'var(--superficie)', border: '1px solid var(--borde)',
      borderRadius: 13, padding: 14, marginTop: 14,
    }}>
      <div style={{ fontSize: 16, fontWeight: 620 }}>{datos.quedada.titulo}</div>
      <div style={{ fontSize: 12.5, color: 'var(--tenue)', marginTop: 3 }}>
        {datos.quedada.fecha} · {datos.asistentes} asistentes · {datos.rolls} rolls
      </div>

      <h2 className="sec">Títulos de la tarde</h2>
      <div className="tl">
        {datos.titulos.map((t) => (
          <div className="fila" key={t.titulo}>
            <span className="n">
              <b style={{ letterSpacing: '.03em' }}>{t.titulo}</b>
              <small>{t.quien} · {t.porque}</small>
            </span>
          </div>
        ))}
      </div>
      <p className="hint">
        Cada uno se lleva exactamente uno, por lo que más le separa de la media
        del equipo esa tarde. Nadie se queda sin título.
      </p>

      <h2 className="sec">Ranking</h2>
      {datos.ranking.length ? (
        <div className="tl">
          {datos.ranking.map((r, i) => (
            <div className="fila" key={r.id}>
              <span className="n">
                {i + 1}. {r.nombre}
                <small>{r.rolls} rolls · {r.favor} a favor · {r.contra} en contra</small>
              </span>
              <span className="pill" style={{
                color: r.media >= 0 ? 'var(--dato-yo-texto)' : 'var(--dato-neg)',
              }}>
                {r.media > 0 ? '+' : ''}{r.media}
              </span>
            </div>
          ))}
        </div>
      ) : (
        <p className="empty">Nadie llegó a dos rolls, que es el mínimo para entrar.</p>
      )}
      <p className="hint">
        Puntos estimados por roll, no sumisiones: cuenta quién dominó aunque no
        finalizara.
      </p>

      <div style={{ marginTop: 12 }}>
        <button className="ghost" onClick={onCerrar} data-testid="cerrar-informe">Cerrar</button>
      </div>
    </div>
  );
}

/**
 * Editar un Open Mat.
 *
 * Solo manda lo que ha cambiado. Las plazas las vigila el trigger de la base y
 * no esta pantalla: si bajas por debajo de los apuntados, el error viene de
 * Postgres con el numero dentro y se enseña tal cual. Poner esa regla aquí
 * ademas seria tenerla en dos sitios, y el de arriba se puede saltar.
 */
function Editar(
  { q, ocupado, onGuardar, onCancelar }: {
    q: QuedadaRow; ocupado: boolean;
    onGuardar: (c: Partial<QuedadaRow>) => void; onCancelar: () => void;
  },
) {
  const [d, setD] = useState({
    titulo: q.titulo,
    fecha: q.fecha,
    hora_inicio: q.hora_inicio?.slice(0, 5) ?? '',
    duracion_min: q.duracion_min?.toString() ?? '',
    lugar: q.lugar ?? '',
    plazas_max: q.plazas_max?.toString() ?? '',
    modalidad: q.modalidad,
    admite_externos: q.admite_externos,
    notas: q.notas ?? '',
  });
  const campo = (k: keyof typeof d) => ({
    value: String(d[k] ?? ''),
    onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
      setD((x) => ({ ...x, [k]: e.target.value })),
  });

  return (
    <form data-testid={`form-editar-${q.id}`}
      style={{ marginTop: 12, paddingTop: 12, borderTop: '1px solid var(--rejilla)' }}
      onSubmit={(e) => {
        e.preventDefault();
        onGuardar({
          titulo: d.titulo.trim(),
          fecha: d.fecha,
          hora_inicio: d.hora_inicio || null,
          duracion_min: d.duracion_min ? Number(d.duracion_min) : null,
          lugar: d.lugar.trim() || null,
          plazas_max: d.plazas_max ? Number(d.plazas_max) : null,
          modalidad: d.modalidad,
          admite_externos: d.admite_externos,
          notas: d.notas.trim() || null,
        });
      }}>
      <label htmlFor={`t-${q.id}`}>Título</label>
      <input id={`t-${q.id}`} data-testid={`ed-titulo-${q.id}`} {...campo('titulo')} />

      <label htmlFor={`f-${q.id}`}>Día</label>
      <input id={`f-${q.id}`} type="date" data-testid={`ed-fecha-${q.id}`} {...campo('fecha')} />

      <label htmlFor={`h-${q.id}`}>Hora</label>
      <input id={`h-${q.id}`} type="time" {...campo('hora_inicio')} />

      <label htmlFor={`l-${q.id}`}>Dónde</label>
      <input id={`l-${q.id}`} {...campo('lugar')} />

      <label htmlFor={`p-${q.id}`}>Plazas (vacío = sin tope)</label>
      <input id={`p-${q.id}`} type="number" min={0} inputMode="numeric"
        data-testid={`ed-plazas-${q.id}`} {...campo('plazas_max')} />

      <label htmlFor={`d-${q.id}`}>Duración (min)</label>
      <input id={`d-${q.id}`} type="number" min={0} inputMode="numeric" {...campo('duracion_min')} />

      <label htmlFor={`m-${q.id}`}>Modalidad</label>
      <select id={`m-${q.id}`} {...campo('modalidad')}>
        <option value="gi">Gi</option>
        <option value="nogi">No-gi</option>
      </select>

      <label style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 12 }}>
        <input type="checkbox" checked={d.admite_externos}
          onChange={(e) => setD((x) => ({ ...x, admite_externos: e.target.checked }))} />
        Admite invitados de fuera
      </label>

      <label htmlFor={`n-${q.id}`}>Notas</label>
      <input id={`n-${q.id}`} {...campo('notas')} />

      <div style={{ display: 'flex', gap: 9, marginTop: 14 }}>
        <button className="primary" type="submit" disabled={ocupado}
          data-testid={`guardar-${q.id}`}>Guardar</button>
        <button className="ghost" type="button" onClick={onCancelar}>Descartar</button>
      </div>
    </form>
  );
}
