'use client';

import { useCallback, useEffect, useState } from 'react';
import { Marco, type Sesion } from '@/components/Marco';
import { supabase } from '@/lib/supabase';
import { encolar, nuevoId } from '@/lib/db';
import { vaciarCola } from '@/lib/sync';
import {
  accionesPosibles, aplicarAccion, esGuardia, GUARDIAS_TODAS, NOMBRE_OBJETIVO,
  NOMBRE_POSICION, resultadoDe,
  type EstadoRoll, type EventoBorrador, type Pendiente,
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

export default function Entreno() {
  return <Marco titulo="Entreno">{(s) => <Flujo sesion={s} />}</Marco>;
}

function Flujo({ sesion }: { sesion: Sesion }) {
  const [abierta, setAbierta] = useState<SesionAbierta | null>(null);
  const [roster, setRoster] = useState<PracticanteRow[]>([]);
  const [tecnicas, setTecnicas] = useState<Record<string, string>>({});
  const [fase, setFase] = useState<'inicio' | 'oponente' | 'roll' | 'fin'>('inicio');

  // roll en curso
  const [oponente, setOponente] = useState<PracticanteRow | null>(null);
  const [estado, setEstado] = useState<EstadoRoll>({ pos: 'de_pie', rol: 'neutral' });
  const [eventos, setEventos] = useState<EventoBorrador[]>([]);
  const [pendiente, setPendiente] = useState<Pendiente | null>(null);
  const [subPendiente, setSubPendiente] = useState<
    { slug: string; objetivo: string; actor: 'yo' | 'oponente'; posicion: Posicion; rol: string } | null
  >(null);

  useEffect(() => {
    const guardada = localStorage.getItem(CLAVE_SESION);
    if (guardada) {
      const s = JSON.parse(guardada) as SesionAbierta;
      if (s.fecha === hoy()) setAbierta(s);
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
    void vaciarCola();
  }, [sesion.practicante]);

  function nuevoRoll() {
    setOponente(null);
    setEstado({ pos: 'de_pie', rol: 'neutral' });
    setEventos([]);
    setPendiente(null);
    setSubPendiente(null);
    setFase('oponente');
  }

  function accion(clave: Parameters<typeof aplicarAccion>[0]) {
    const r = aplicarAccion(clave, estado);
    if (r.evento) setEventos((e) => [...e, r.evento!]);
    if (r.estado) setEstado(r.estado);
    setPendiente(r.pendiente ?? null);
  }

  async function terminar() {
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
      });
    }
    const s = { ...abierta, rolls: abierta.rolls + 1 };
    localStorage.setItem(CLAVE_SESION, JSON.stringify(s));
    setAbierta(s);
    setFase('fin');
    void vaciarCola();
  }

  // ---------------------------------------------------------------- pantallas

  if (!abierta) {
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
      </>
    );
  }

  if (fase === 'oponente') {
    return (
      <>
        <h2 className="sec">¿Con quién ruedas?</h2>
        <div className="chips">
          {roster.filter((p) => p.id !== sesion.practicante.id).map((p) => (
            <button className="chip" key={p.id} data-testid={`op-${p.nombre}`}
              onClick={() => { setOponente(p); setFase('roll'); }}>
              {p.nombre}{p.usa_sistema && <small>app</small>}
            </button>
          ))}
        </div>
        {roster.length <= 1 && (
          <p className="hint">
            No tienes a nadie en el roster. Añade compañeros desde la pestaña Practicantes.
          </p>
        )}
        <div style={{ marginTop: 18 }}>
          <button className="ghost" onClick={() => setFase('inicio')}>← Atrás</button>
        </div>
      </>
    );
  }

  if (fase === 'roll' && oponente) {
    const a = accionesPosibles(estado);
    return (
      <>
        <div className="state">
          <div className="lbl">Posición actual</div>
          <div className="pos">{NOMBRE_POSICION[estado.pos]}</div>
          <div className="rol">
            {estado.rol === 'neutral' ? 'nadie controla todavía' : <>estás <b>{estado.rol}</b></>}
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
                    setEventos((e) => [...e, {
                      actor: subPendiente.actor, tipo: 'sumision',
                      posicion: subPendiente.posicion, rol: subPendiente.rol as EstadoRoll['rol'],
                      objetivo: subPendiente.objetivo as EventoBorrador['objetivo'],
                      tecnicaSlug: subPendiente.slug, completado: true,
                    }]);
                    setSubPendiente(null);
                  }}>✓ Sí, fin del roll</button>
                  <button className="chip no" onClick={() => {
                    setEventos((e) => [...e, {
                      actor: subPendiente.actor, tipo: 'sumision',
                      posicion: subPendiente.posicion, rol: subPendiente.rol as EstadoRoll['rol'],
                      objetivo: subPendiente.objetivo as EventoBorrador['objetivo'],
                      tecnicaSlug: subPendiente.slug, completado: false,
                    }]);
                    setSubPendiente(null);
                  }}>✗ Falló, seguimos</button>
                </div>
              </>
            )
            : (
              <>
                <h2 className="sec">Yo</h2>
                <div className="grid">
                  {a.yo.map((x) => (
                    <button className="act yo" key={x.clave} data-testid={x.clave}
                      onClick={() => accion(x.clave)}>
                      <span className="k">yo</span>{x.etiqueta}
                    </button>
                  ))}
                </div>
                <h2 className="sec">{oponente.nombre}</h2>
                <div className="grid">
                  {a.op.map((x) => (
                    <button className="act op" key={x.clave} data-testid={x.clave}
                      onClick={() => accion(x.clave)}>
                      <span className="k">él</span>{x.etiqueta}
                    </button>
                  ))}
                </div>
              </>
            )}

        <h2 className="sec">Eventos ({eventos.length})</h2>
        <Timeline eventos={eventos} oponente={oponente.nombre}
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
    const txt = res === 'sumision_favor' ? 'Sumisión a favor'
      : res === 'sumision_contra' ? 'Sumisión en contra' : 'Sin sumisión';
    return (
      <>
        <div className="state">
          <div className="lbl">Roll guardado</div>
          <div className="pos" data-testid="resultado">{txt}</div>
          <div className="rol">{eventos.length} eventos · vs {oponente?.nombre}</div>
        </div>
        <p className="hint">
          Se ha guardado en el móvil y sale hacia Supabase en cuanto haya red.
          Mira la píldora de arriba.
        </p>
        <div style={{ display: 'flex', gap: 9, marginTop: 18 }}>
          <button className="primary" onClick={nuevoRoll}>+ Otro roll</button>
          <button className="ghost" onClick={() => setFase('inicio')}>Fin sesión</button>
        </div>
      </>
    );
  }

  return (
    <>
      <div className="state">
        <div className="lbl">Sesión abierta</div>
        <div className="pos">{abierta.modalidad === 'gi' ? 'Gi' : 'No-gi'}</div>
        <div className="rol">{abierta.rolls} rolls registrados hoy</div>
      </div>
      <div style={{ marginTop: 18 }}>
        <button className="primary" data-testid="nuevo-roll" onClick={nuevoRoll}>
          + Nuevo roll
        </button>
      </div>
      <p className="hint">
        La sesión se cierra sola a medianoche. Si mañana entrenas otra vez, se abre una nueva.
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
  { eventos, oponente, onBorrar }:
  { eventos: EventoBorrador[]; oponente: string; onBorrar: (i: number) => void },
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
            {e.actor === 'yo' ? 'Yo' : oponente} · {
              e.tecnicaSlug === 'puxada' ? 'Tira guardia' : NOMBRE_TIPO[e.tipo]
            }{e.completado ? '' : ' (falló)'}
            <small>
              {NOMBRE_POSICION[e.posicion]} · {e.rol}
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
