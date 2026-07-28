'use client';

import { useCallback, useEffect, useState } from 'react';
import { Marco, type Sesion } from '@/components/Marco';
import { supabase } from '@/lib/supabase';
import { encolar, encolarRollObservado, nuevoId } from '@/lib/db';
import { vaciarCola } from '@/lib/sync';
import {
  accionesPosibles, aplicarAccion, CONTEXTO_PROPIO, esGuardia, GUARDIAS_TODAS,
  NOMBRE_OBJETIVO, NOMBRE_POSICION, resultadoDe,
  type Contexto, type EstadoRoll, type EventoBorrador, type Modo, type Pendiente,
} from '@/lib/bjj';
import type {
  Modalidad, Posicion, PracticanteRow, TipoSesion,
} from '@/lib/database.types';

const CLAVE_SESION = 'bjj.sesion-abierta';
const CLAVE_TECNICAS = 'bjj.tecnicas';

interface SesionAbierta {
  id: string;
  fecha: string;
  modalidad: Modalidad;
  tipo: TipoSesion;
  rolls: number;
}

const hoy = () => new Date().toISOString().slice(0, 10);

/** mm:ss para el cronómetro del observador. */
function reloj(desde: number, ahora: number) {
  const s = Math.max(0, Math.floor((ahora - desde) / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export default function Entreno() {
  return <Marco titulo="Entreno">{(s) => <Flujo sesion={s} />}</Marco>;
}

function Flujo({ sesion }: { sesion: Sesion }) {
  const [abierta, setAbierta] = useState<SesionAbierta | null>(null);
  const [roster, setRoster] = useState<PracticanteRow[]>([]);
  const [tecnicas, setTecnicas] = useState<Record<string, string>>({});
  const [fase, setFase] = useState<'inicio' | 'observadorA' | 'oponente' | 'roll' | 'fin'>('inicio');

  // Quién registra. En modo observador el roll no es de nadie de los que miran:
  // `practA` es quien queda como `actor: 'yo'` en los datos.
  const [modo, setModo] = useState<Modo>('propio');
  const [practA, setPractA] = useState<PracticanteRow | null>(null);
  const [modalidadObs, setModalidadObs] = useState<Modalidad>('gi');

  // roll en curso
  const [oponente, setOponente] = useState<PracticanteRow | null>(null);
  const [estado, setEstado] = useState<EstadoRoll>({ pos: 'de_pie', rol: 'neutral' });
  const [eventos, setEventos] = useState<EventoBorrador[]>([]);
  const [pendiente, setPendiente] = useState<Pendiente | null>(null);
  const [subPendiente, setSubPendiente] = useState<
    { slug: string; objetivo: string; actor: 'yo' | 'oponente'; posicion: Posicion; rol: string } | null
  >(null);

  // El observador registra en vivo: el reloj arranca al elegir al segundo.
  const [tRoll, setTRoll] = useState<number | null>(null);
  const [ahora, setAhora] = useState(() => Date.now());

  useEffect(() => {
    const guardada = localStorage.getItem(CLAVE_SESION);
    if (guardada) {
      const s = JSON.parse(guardada) as SesionAbierta;
      if (s.fecha === hoy()) { setAbierta(s); setModalidadObs(s.modalidad); }
      else localStorage.removeItem(CLAVE_SESION);
    }
    const cache = localStorage.getItem(CLAVE_TECNICAS);
    if (cache) setTecnicas(JSON.parse(cache));
  }, []);

  useEffect(() => {
    (async () => {
      const { data } = await supabase().from('practicantes').select('*').order('nombre');
      if (data) setRoster(data as PracticanteRow[]);
      // El diccionario se cachea: hace falta para mapear técnica -> id sin red.
      const { data: t } = await supabase().from('tecnicas').select('id,slug');
      if (t) {
        const m = Object.fromEntries((t as { id: string; slug: string }[])
          .map((x) => [x.slug, x.id]));
        setTecnicas(m);
        localStorage.setItem(CLAVE_TECNICAS, JSON.stringify(m));
      }
    })();
  }, []);

  // El reloj solo corre observando y dentro del roll.
  useEffect(() => {
    if (modo !== 'observador' || fase !== 'roll' || tRoll === null) return;
    const id = setInterval(() => setAhora(Date.now()), 1000);
    return () => clearInterval(id);
  }, [modo, fase, tRoll]);

  const observando = modo === 'observador';
  const nombreA = observando ? (practA?.nombre ?? '') : 'Yo';
  const nombreB = oponente?.nombre ?? 'Oponente';

  const ctx: Contexto = observando && practA && oponente
    ? { modo: 'observador', a: practA.nombre, b: oponente.nombre }
    : CONTEXTO_PROPIO;

  /** Minuto del roll, solo si hay cronómetro. Se acota igual que el check de la base. */
  const minutoActual = useCallback(() => {
    if (tRoll === null) return null;
    return Math.min(60, Math.floor((Date.now() - tRoll) / 60000));
  }, [tRoll]);

  const agregar = useCallback((ev: EventoBorrador) => {
    setEventos((e) => [...e, { ...ev, minuto: minutoActual() }]);
  }, [minutoActual]);

  const abrirSesion = useCallback(async (modalidad: Modalidad, tipo: TipoSesion) => {
    const s: SesionAbierta = { id: nuevoId(), fecha: hoy(), modalidad, tipo, rolls: 0 };
    await encolar('sesiones', {
      id: s.id,
      practicante_id: sesion.practicante.id,
      fecha: s.fecha,
      modalidad,
      tipo,
      academia: sesion.practicante.academia,
    });
    localStorage.setItem(CLAVE_SESION, JSON.stringify(s));
    setAbierta(s);
    setModalidadObs(modalidad);
    void vaciarCola();
  }, [sesion.practicante]);

  function limpiarRoll() {
    setOponente(null);
    setEstado({ pos: 'de_pie', rol: 'neutral' });
    setEventos([]);
    setPendiente(null);
    setSubPendiente(null);
    setTRoll(null);
  }

  function nuevoRoll() {
    limpiarRoll();
    setModo('propio');
    setPractA(null);
    setFase('oponente');
  }

  function observar() {
    limpiarRoll();
    setModo('observador');
    setPractA(null);
    setFase('observadorA');
  }

  function salirDeObservador() {
    limpiarRoll();
    setModo('propio');
    setPractA(null);
    setFase('inicio');
  }

  function accion(clave: Parameters<typeof aplicarAccion>[0]) {
    const r = aplicarAccion(clave, estado, ctx);
    if (r.evento) agregar(r.evento);
    if (r.estado) setEstado(r.estado);
    setPendiente(r.pendiente ?? null);
  }

  /** Tu propio roll: filas sueltas por la cola de siempre. */
  async function terminarPropio() {
    if (!abierta || !oponente) return;
    const rollId = nuevoId();
    await encolar('rolls', {
      id: rollId,
      sesion_id: abierta.id,
      oponente_id: oponente.id,
      orden: abierta.rolls + 1,
      modalidad: abierta.modalidad,
      posicion_inicio: 'de_pie',
      rol_inicio: 'neutral',
      resultado: resultadoDe(eventos),
      origen: 'propio',
      registrado_por: sesion.practicante.id,
    });
    for (const ev of eventos) {
      await encolar('eventos', {
        id: nuevoId(),
        roll_id: rollId,
        actor: ev.actor,
        tipo: ev.tipo,
        posicion: ev.posicion,
        rol: ev.rol,
        objetivo: ev.objetivo,
        tecnica_id: ev.tecnicaSlug ? tecnicas[ev.tecnicaSlug] ?? null : null,
        completado: ev.completado,
        minuto: ev.minuto ?? null,
      });
    }
    const s = { ...abierta, rolls: abierta.rolls + 1 };
    localStorage.setItem(CLAVE_SESION, JSON.stringify(s));
    setAbierta(s);
    setFase('fin');
    void vaciarCola();
  }

  /**
   * Roll observado: una sola llamada a la RPC.
   *
   * No pasa por `encolar()` porque la RLS no deja escribir filas de otros; y
   * no toca la sesión del observador, porque el roll no es suyo. La técnica
   * viaja por slug: la resuelve Postgres.
   */
  async function terminarObservado() {
    if (!practA || !oponente) return;
    const seg = tRoll ? Math.round((Date.now() - tRoll) / 1000) : 0;
    await encolarRollObservado({
      p_grupo: nuevoId(),
      p_practicante_a: practA.id,
      p_practicante_b: oponente.id,
      p_fecha: hoy(),
      p_modalidad: modalidadObs,
      p_duracion_min: Math.min(60, Math.max(0, Math.round(seg / 60))),
      p_resultado: resultadoDe(eventos),
      p_eventos: eventos.map((ev) => ({
        actor: ev.actor,
        tipo: ev.tipo,
        posicion: ev.posicion,
        rol: ev.rol,
        objetivo: ev.objetivo,
        tecnica_slug: ev.tecnicaSlug,
        completado: ev.completado,
        minuto: ev.minuto ?? null,
      })),
    });
    setFase('fin');
    void vaciarCola();
  }

  const terminar = () => (observando ? terminarObservado() : terminarPropio());

  // ---------------------------------------------------------------- pantallas

  if (!abierta && fase === 'inicio') {
    return (
      <>
        <h1>Nuevo entreno</h1>
        <p className="hint">Se abre una vez al llegar. Después, cada roll es un toque.</p>
        <h2 className="sec">Modalidad</h2>
        <div className="chips">
          <button className="chip" onClick={() => abrirSesion('gi', 'sparring')}>Gi</button>
          <button className="chip" onClick={() => abrirSesion('nogi', 'sparring')}>No-gi</button>
          <button className="chip" onClick={() => abrirSesion('nogi', 'open_mat')}>Open mat</button>
        </div>
        <h2 className="sec">O mira a otros</h2>
        <div style={{ marginTop: 4 }}>
          <button className="ghost" data-testid="observar" onClick={observar}>
            👁 Observar
          </button>
        </div>
        <p className="hint">
          Para registrar el roll de otros dos sin entrenar tú. No hace falta abrir sesión:
          el roll va a la de ellos, no a la tuya.
        </p>
      </>
    );
  }

  if (fase === 'observadorA') {
    return (
      <>
        <h1>Modo observador</h1>
        <p className="hint">
          Tú solo miras. El roll se guarda para los dos: uno lo verá como ataque y el otro
          como defensa, sin que ninguno toque el móvil.
        </p>
        <h2 className="sec">Modalidad del roll</h2>
        <div className="chips">
          {(['gi', 'nogi'] as const).map((m) => (
            <button key={m} className="chip" data-testid={`obs-mod-${m}`}
              style={modalidadObs === m
                ? { borderColor: 'var(--yo)', color: 'var(--yo)' } : undefined}
              onClick={() => setModalidadObs(m)}>
              {m === 'gi' ? 'Gi' : 'No-gi'}
            </button>
          ))}
        </div>
        <h2 className="sec" style={{ color: 'var(--yo)' }}>Primer practicante</h2>
        <div className="chips">
          {roster.map((p) => (
            <button className="chip" key={p.id} data-testid={`obsA-${p.nombre}`}
              onClick={() => { setPractA(p); setFase('oponente'); }}>
              {p.nombre}{p.usa_sistema && <small>app</small>}
            </button>
          ))}
        </div>
        {roster.length < 2 && (
          <p className="hint">
            Hacen falta al menos dos fichas en el roster. Añádelas desde la pestaña Practicantes.
          </p>
        )}
        <div style={{ marginTop: 18 }}>
          <button className="ghost" onClick={salirDeObservador}>← Atrás</button>
        </div>
      </>
    );
  }

  if (fase === 'oponente') {
    const lista = observando
      ? roster.filter((p) => p.id !== practA?.id)
      : roster.filter((p) => p.id !== sesion.practicante.id);
    return (
      <>
        <h2 className="sec" style={observando ? { color: 'var(--op)' } : undefined}>
          {observando ? `${nombreA} contra…` : '¿Con quién ruedas?'}
        </h2>
        <div className="chips">
          {lista.map((p) => (
            <button className="chip" key={p.id} data-testid={`op-${p.nombre}`}
              onClick={() => {
                setOponente(p);
                setTRoll(observando ? Date.now() : null);
                setAhora(Date.now());
                setFase('roll');
              }}>
              {p.nombre}{p.usa_sistema && <small>app</small>}
            </button>
          ))}
        </div>
        {!lista.length && (
          <p className="hint">
            No tienes a nadie más en el roster. Añade compañeros desde la pestaña Practicantes.
          </p>
        )}
        {observando && (
          <p className="hint">En cuanto elijas, arranca el cronómetro del roll.</p>
        )}
        <div style={{ marginTop: 18 }}>
          <button className="ghost"
            onClick={() => setFase(observando ? 'observadorA' : 'inicio')}>← Atrás</button>
        </div>
      </>
    );
  }

  if (fase === 'roll' && oponente && (!observando || practA)) {
    const a = accionesPosibles(estado, modo);
    const quienArriba = estado.rol === 'arriba' ? nombreA : nombreB;
    return (
      <>
        <div className="state">
          <div className="lbl">
            Posición actual
            {observando && tRoll !== null && (
              <> · <span data-testid="crono">{reloj(tRoll, ahora)}</span></>
            )}
          </div>
          <div className="pos">{NOMBRE_POSICION[estado.pos]}</div>
          <div className="rol">
            {estado.rol === 'neutral'
              ? 'nadie controla todavía'
              : observando
                ? <><b>{quienArriba}</b> arriba</>
                : <>estás <b>{estado.rol}</b></>}
          </div>
        </div>

        {pendiente
          ? <Pregunta
              p={pendiente}
              onPosicion={(pos) => {
                if (pendiente.tipo !== 'posicion') return;
                setEstado(pendiente.siguiente(pos));
                setPendiente(null);
              }}
              onMas={() => {
                if (pendiente.tipo !== 'posicion') return;
                setPendiente({ ...pendiente, opciones: GUARDIAS_TODAS, mas: false });
              }}
              onTecnica={(slug, objetivo) => {
                if (pendiente.tipo !== 'tecnica') return;
                setSubPendiente({
                  slug, objetivo, actor: pendiente.actor,
                  posicion: pendiente.posicion, rol: pendiente.rol,
                });
                setPendiente(null);
              }}
              onCancelar={() => setPendiente(null)}
            />
          : subPendiente
            ? (
              <>
                <h2 className="sec">¿Entró?</h2>
                <div className="chips">
                  <button className="chip ok" data-testid="entro-si" onClick={() => {
                    agregar({
                      actor: subPendiente.actor, tipo: 'sumision',
                      posicion: subPendiente.posicion, rol: subPendiente.rol as EstadoRoll['rol'],
                      objetivo: subPendiente.objetivo as EventoBorrador['objetivo'],
                      tecnicaSlug: subPendiente.slug, completado: true,
                    });
                    setSubPendiente(null);
                  }}>✓ Sí, fin del roll</button>
                  <button className="chip no" onClick={() => {
                    agregar({
                      actor: subPendiente.actor, tipo: 'sumision',
                      posicion: subPendiente.posicion, rol: subPendiente.rol as EstadoRoll['rol'],
                      objetivo: subPendiente.objetivo as EventoBorrador['objetivo'],
                      tecnicaSlug: subPendiente.slug, completado: false,
                    });
                    setSubPendiente(null);
                  }}>✗ Falló, seguimos</button>
                </div>
              </>
            )
            : (
              <>
                <h2 className="sec" style={observando ? { color: 'var(--yo)' } : undefined}>
                  {nombreA}
                </h2>
                <div className="grid">
                  {a.yo.map((x) => (
                    <button className="act yo" key={x.clave} data-testid={x.clave}
                      onClick={() => accion(x.clave)}>
                      {!observando && <span className="k">yo</span>}{x.etiqueta}
                    </button>
                  ))}
                </div>
                <h2 className="sec" style={observando ? { color: 'var(--op)' } : undefined}>
                  {nombreB}
                </h2>
                <div className="grid">
                  {a.op.map((x) => (
                    <button className="act op" key={x.clave} data-testid={x.clave}
                      onClick={() => accion(x.clave)}>
                      {!observando && <span className="k">él</span>}{x.etiqueta}
                    </button>
                  ))}
                </div>
              </>
            )}

        <h2 className="sec">Eventos ({eventos.length})</h2>
        <Timeline eventos={eventos} nombreA={nombreA} nombreB={nombreB}
          onBorrar={(i) => setEventos((e) => e.filter((_, j) => j !== i))} />

        <div style={{ display: 'flex', gap: 9, marginTop: 20 }}>
          <button className="primary" data-testid="fin-roll" onClick={terminar}>
            Fin del roll
          </button>
        </div>
      </>
    );
  }

  if (fase === 'fin') {
    const res = resultadoDe(eventos);
    const txt = observando
      ? (res === 'sumision_favor' ? `Ganó ${nombreA}`
        : res === 'sumision_contra' ? `Ganó ${nombreB}` : 'Sin sumisión')
      : (res === 'sumision_favor' ? 'Sumisión a favor'
        : res === 'sumision_contra' ? 'Sumisión en contra' : 'Sin sumisión');
    const espeja = observando && oponente?.usa_sistema;
    return (
      <>
        <div className="state">
          <div className="lbl">{observando ? 'Roll observado' : 'Roll guardado'}</div>
          <div className="pos" data-testid="resultado">{txt}</div>
          <div className="rol">
            {eventos.length} eventos · {observando ? `${nombreA} vs ${nombreB}` : `vs ${nombreB}`}
          </div>
        </div>

        {observando ? (
          <>
            <p className="hint" data-testid="resumen-observado">
              {espeja
                ? <>Se han guardado <b>dos rolls</b>, uno para {nombreA} y otro para {nombreB},
                    unidos por el mismo <code>roll_grupo_id</code>. Ninguno de los dos ha tocado
                    el móvil, y lo que para uno es ataque para el otro es defensa.</>
                : <>Se ha guardado <b>un roll</b>, el de {nombreA}. {nombreB} no usa la app,
                    así que no hay a quién espejárselo: cuando se dé de alta, este roll seguirá
                    contando como suyo en el head-to-head de {nombreA}.</>}
            </p>
            <p className="hint">
              Si alguno de los dos registra este mismo roll por su cuenta, <b>gana esta
              versión</b>: el que mira ve cosas que tú no ves — tu propia espalda, y las
              sumisiones que intentaste y fallaste.
            </p>
          </>
        ) : (
          <p className="hint">
            Se ha guardado en el móvil y sale hacia Supabase en cuanto haya red.
            Mira la píldora de arriba.
          </p>
        )}

        <div style={{ display: 'flex', gap: 9, marginTop: 18 }}>
          <button className="primary" data-testid="otro-roll" onClick={() => {
            limpiarRoll();
            setFase(observando ? 'observadorA' : 'oponente');
          }}>+ Otro roll</button>
          <button className="ghost" onClick={salirDeObservador}>
            {observando ? 'Salir' : 'Fin sesión'}
          </button>
        </div>
      </>
    );
  }

  return (
    <>
      <div className="state">
        <div className="lbl">Sesión abierta</div>
        <div className="pos">{abierta?.modalidad === 'gi' ? 'Gi' : 'No-gi'}</div>
        <div className="rol">{abierta?.rolls ?? 0} rolls registrados hoy</div>
      </div>
      <div style={{ display: 'flex', gap: 9, marginTop: 18 }}>
        <button className="primary" data-testid="nuevo-roll" onClick={nuevoRoll}>
          + Nuevo roll
        </button>
        <button className="ghost" data-testid="observar" onClick={observar}>
          👁 Observar
        </button>
      </div>
      <p className="hint">
        La sesión se cierra sola a medianoche. Si mañana entrenas otra vez, se abre una nueva.
        <b> 👁 Observar</b> es para registrar el roll de otros dos: cada uno recibe sus datos.
      </p>
    </>
  );
}

function Pregunta(
  { p, onPosicion, onMas, onTecnica, onCancelar }: {
    p: Pendiente;
    onPosicion: (pos: Posicion) => void;
    onMas: () => void;
    onTecnica: (slug: string, objetivo: string) => void;
    onCancelar: () => void;
  },
) {
  if (p.tipo === 'posicion') {
    return (
      <>
        <h2 className="sec">{p.titulo}</h2>
        <div className="chips">
          {p.opciones.map((pos) => (
            <button className="chip" key={pos} data-testid={`pos-${pos}`}
              onClick={() => onPosicion(pos)}>{NOMBRE_POSICION[pos]}</button>
          ))}
          {p.mas && <button className="chip" onClick={onMas}>Más…</button>}
        </div>
      </>
    );
  }
  return (
    <>
      <h2 className="sec">{p.titulo}</h2>
      <div className="chips">
        {p.opciones.map(([slug, objetivo]) => (
          <button className="chip" key={slug} data-testid={`tec-${slug}`}
            onClick={() => onTecnica(slug, objetivo)}>
            {slug.replace(/_/g, ' ')}<small>{NOMBRE_OBJETIVO[objetivo]}</small>
          </button>
        ))}
      </div>
      <button className="x" style={{ marginTop: 10 }} onClick={onCancelar}>← cancelar</button>
    </>
  );
}

function Timeline(
  { eventos, nombreA, nombreB, onBorrar }:
  { eventos: EventoBorrador[]; nombreA: string; nombreB: string; onBorrar: (i: number) => void },
) {
  const NOMBRE_TIPO: Record<EventoBorrador['tipo'], string> = {
    sumision: 'Sumisión', barrida: 'Barrida', pase_guardia: 'Pase de guardia',
    derribo: 'Derribo', toma_espalda: 'Toma de espalda', escape: 'Escape',
  };
  if (!eventos.length) {
    return <p className="empty">Nada todavía. Toca una acción arriba.</p>;
  }
  return (
    <div className="tl">
      {eventos.map((e, i) => (
        <div className={`ev${e.completado ? '' : ' fail'}`} key={i}>
          <span className="dot" style={{
            background: e.actor === 'yo' ? 'var(--yo)' : 'var(--op)',
          }} />
          <span className="tx">
            {e.actor === 'yo' ? nombreA : nombreB} · {
              e.tecnicaSlug === 'puxada' ? 'Tira guardia' : NOMBRE_TIPO[e.tipo]
            }{e.completado ? '' : ' (falló)'}
            <small>
              {NOMBRE_POSICION[e.posicion]} · {e.rol}
              {e.minuto != null ? ` · min ${e.minuto}` : ''}
              {e.tecnicaSlug && e.tipo === 'sumision'
                ? ` · ${e.tecnicaSlug.replace(/_/g, ' ')} → ${NOMBRE_OBJETIVO[e.objetivo]}`
                : ''}
            </small>
          </span>
          <button className="x" aria-label="Borrar evento" onClick={() => onBorrar(i)}>✕</button>
        </div>
      ))}
    </div>
  );
}
