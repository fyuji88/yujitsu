'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Marco, type Sesion } from '@/components/Marco';
import { Enfoque } from '@/components/Enfoque';
import { Coleccion } from '@/components/Logros';
import { useTema } from '@/components/Tema';
import { contraste } from '@/lib/tema';
import { supabase } from '@/lib/supabase';
import { NOMBRE_OBJETIVO } from '@/lib/bjj';
import type { Objetivo, Posicion, PracticanteRow } from '@/lib/database.types';

/**
 * Análisis de juego. Puerto de docs/BJJ-Analisis-DEMO.html a la app.
 *
 * Todo lo que se pinta sale ya agregado de `analisis()` en Postgres. Aquí no
 * se suma nada: si hace falta un corte nuevo, se añade en SQL. Lo único que
 * calcula esta pantalla es el máximo de cada rampa de color, que es una
 * decisión de dibujo y no un dato.
 */

/** Rampas secuenciales de un solo tono, 13 pasos. Nada de arcoíris. */
const AZUL = [
  '#cde2fb', '#b7d3f6', '#9ec5f4', '#86b6ef', '#6da7ec', '#5598e7', '#3987e5',
  '#2a78d6', '#256abf', '#1c5cab', '#184f95', '#104281', '#0d366b',
];
const NARANJA = [
  '#fbe0d3', '#f8ceba', '#f5bca1', '#f2a988', '#ef966f', '#ec8356', '#eb6834',
  '#d95926', '#c24e21', '#a8431c', '#8d3817', '#722d13', '#57220e',
];

/** Las columnas del heatmap, siempre las diez, tengan dato o no. */
const OBJETIVOS: Objetivo[] = [
  'cuello', 'hombro', 'codo', 'muneca', 'biceps', 'columna', 'cadera',
  'rodilla', 'tobillo_pie', 'pantorrilla',
];
const etiquetaObj = (o: Objetivo) => {
  const n = NOMBRE_OBJETIVO[o];
  return n.charAt(0).toUpperCase() + n.slice(1);
};

/**
 * Por debajo de esto no se enseñan porcentajes, se enseñan cuentas.
 *
 * "Finalizas el 100% desde media guardia" con n=1 es una frase falsa; "1 de 1"
 * es verdad y se lee igual de rápido. Con el selector de practicante se cae
 * constantemente en gente con tres rolls, así que esto no es un detalle del
 * estado vacío: es una regla de la pantalla.
 */
const MINIMO_PARA_PORCENTAJES = 20;

/**
 * Color del número dentro de la celda, según el fondo de esa celda concreta.
 * No por índice de la rampa: en modo claro y oscuro el mismo índice tiene
 * luminancias opuestas.
 *
 * Se **miden las dos opciones** y gana la que más contraste da. Antes había un
 * umbral fijo de luminancia (0,42) y los tonos medios de la rampa caían justo
 * del lado equivocado: un azul medio se llevaba texto blanco y el número
 * quedaba en 2,5:1, ilegible, sin que nada avisara. Con dos medidas no hay
 * frontera que ajustar a ojo.
 */
function tinta(hex: string) {
  return contraste('#0b0b0b', hex) >= contraste('#ffffff', hex) ? '#0b0b0b' : '#ffffff';
}

interface Celda {
  posicion: Posicion;
  posicion_nombre: string;
  objetivo: Objetivo;
  n: number;
  intentos: number;
}
interface Saldo {
  posicion: Posicion; nom: string; favor: number; contra: number; saldo: number;
}
interface Rival {
  id: string; nom: string; cin: string; rolls: number; favor: number; contra: number;
}
interface Semana { semana: string; rolls: number; favor: number; contra: number }
interface Variante { id: string; nom: string; ok: number; tot: number }
interface Tecnica {
  nom: string;
  mecanica_id: string;
  ok: number;
  tot: number;
  /** Solo si la mecánica tiene más de una técnica con datos. */
  variantes: Variante[] | null;
  /** La guarda de volumen la decide SQL: dos técnicas con 5 intentos cada una. */
  compara: boolean;
}

interface Datos {
  kpi: {
    sesiones: number; rolls: number; eventos: number; horas: number;
    sub_favor: number; sub_contra: number;
    desde: string | null; hasta: string | null; observados: number;
  };
  off: Celda[]; def: Celda[];
  guardias: Saldo[]; posiciones: Saldo[];
  h2h: Rival[]; evo: Semana[]; tec: Tecnica[];
}

interface RollCelda {
  roll_id: string; fecha: string; rival: string;
  origen: string; tecnica: string | null; completado: boolean;
}

type Modalidad = 'todo' | 'gi' | 'nogi';
type Ventana = 'todo' | '30';

export default function Analisis() {
  return <Marco titulo="Análisis">{(s) => <Panel sesion={s} />}</Marco>;
}

function Panel({ sesion }: { sesion: Sesion }) {
  const [roster, setRoster] = useState<PracticanteRow[]>([]);
  const [autor, setAutor] = useState(sesion.practicante.id);
  const [modalidad, setModalidad] = useState<Modalidad>('todo');
  const [ventana, setVentana] = useState<Ventana>('todo');
  // El tema es de la app entera, no de esta pantalla. Antes había aquí un
  // interruptor propio porque el análisis era lo único con modo claro; con el
  // tema global, dos interruptores solo servirían para contradecirse.
  const [tema] = useTema();
  const [tablas, setTablas] = useState(false);
  const [datos, setDatos] = useState<Datos | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [celda, setCelda] = useState<
    { actor: 'yo' | 'oponente'; c: Celda; rolls: RollCelda[] | null } | null
  >(null);

  useEffect(() => {
    void supabase().from('practicantes').select('*').order('nombre')
      .then(({ data }) => { if (data) setRoster(data as PracticanteRow[]); });
  }, []);

  const desde = useMemo(() => {
    if (ventana === 'todo') return null;
    const d = new Date();
    d.setDate(d.getDate() - 30);
    return d.toISOString().slice(0, 10);
  }, [ventana]);

  useEffect(() => {
    let vivo = true;
    setCargando(true);
    setCelda(null);
    void supabase()
      .rpc('analisis', {
        p_autor: autor,
        p_modalidad: modalidad === 'todo' ? null : modalidad,
        p_desde: desde,
      })
      .then(({ data, error }) => {
        if (!vivo) return;
        if (error) setError(error.message);
        else { setDatos(data as Datos); setError(null); }
        setCargando(false);
      });
    return () => { vivo = false; };
  }, [autor, modalidad, desde]);

  const abrirCelda = useCallback(async (actor: 'yo' | 'oponente', c: Celda) => {
    setCelda({ actor, c, rolls: null });
    const { data } = await supabase().rpc('analisis_rolls_celda', {
      p_autor: autor, p_actor: actor,
      p_posicion: c.posicion, p_objetivo: c.objetivo,
      p_modalidad: modalidad === 'todo' ? null : modalidad,
      p_desde: desde,
    });
    setCelda((v) => (v && v.c === c ? { ...v, rolls: (data ?? []) as RollCelda[] } : v));
  }, [autor, modalidad, desde]);

  const quien = roster.find((p) => p.id === autor);
  const esMio = autor === sesion.practicante.id;
  const k = datos?.kpi;

  return (
    <div className="viz">
      <select className="f" value={autor} data-testid="selector-practicante"
        onChange={(e) => setAutor(e.target.value)} aria-label="Practicante">
        {roster.map((p) => (
          <option key={p.id} value={p.id}>
            {p.nombre}{p.id === sesion.practicante.id ? ' (tú)' : ''}
          </option>
        ))}
      </select>

      <div className="filtros">
        {(['todo', 'gi', 'nogi'] as const).map((m) => (
          <button key={m} className="f" data-testid={`mod-${m}`}
            aria-pressed={modalidad === m} onClick={() => setModalidad(m)}>
            {m === 'todo' ? 'Gi y no-gi' : m === 'gi' ? 'Solo gi' : 'Solo no-gi'}
          </button>
        ))}
        {(['todo', '30'] as const).map((v) => (
          <button key={v} className="f" data-testid={`ven-${v}`}
            aria-pressed={ventana === v} onClick={() => setVentana(v)}>
            {v === 'todo' ? 'Todo' : 'Últimos 30 días'}
          </button>
        ))}
      </div>

      {error && <p className="err">{error}</p>}
      {cargando && <p className="empty">Calculando…</p>}

      {!cargando && k && k.rolls === 0 && (
        <div className="tarjeta" data-testid="vacio">
          {esMio ? (
            <>
              <h2>Todavía no hay nada que analizar</h2>
              <p className="cap">
                Cuando registres unos cuantos rolls, aquí verás desde dónde atacas,
                dónde te pillan, y contra quién te va mejor.
              </p>
              <Link href="/entreno" className="f" style={{ display: 'inline-block' }}>
                Ir a registrar un roll
              </Link>
            </>
          ) : (
            <>
              <h2>Sin rolls de {quien?.nombre}</h2>
              <p className="cap">
                Todavía no hay ningún roll registrado de {quien?.nombre}
                {modalidad !== 'todo' || ventana !== 'todo'
                  ? ' con estos filtros. Prueba a quitarlos.' : '.'}
              </p>
            </>
          )}
        </div>
      )}

      {!cargando && datos && k && k.rolls > 0 && (
        <>
          <div className="kpis">
            <Kpi v={k.rolls} l="Rolls" />
            <Kpi v={k.sesiones} l="Sesiones" />
            <Kpi v={k.sub_favor} l="Sumisiones a favor" />
            <Kpi v={k.sub_contra} l="Sumisiones en contra" />
          </div>

          <p className="nota" data-testid="contexto">
            {k.desde && k.hasta && <>Del {k.desde} al {k.hasta}. </>}
            {k.horas > 0 && <>{k.horas} horas de tatami. </>}
            {/* Quién registró los datos cambia por completo cómo hay que leer
                el heatmap defensivo: registrándote tú faltan sistemáticamente
                las cosas que no ves — tu propia espalda, y lo que fallaste. */}
            <b data-testid="cobertura">
              {k.observados === 0
                ? 'Ningún roll registrado por un observador'
                : `${k.observados} de ${k.rolls} rolls registrados por un observador`}
            </b>
            {k.observados < k.rolls && (
              <>: en los demás faltan las cosas que no ves, como tu propia espalda.</>
            )}
            {k.rolls < MINIMO_PARA_PORCENTAJES && (
              <> Con menos de {MINIMO_PARA_PORCENTAJES} rolls se enseñan cuentas y
                no porcentajes, porque con tan poco volumen un porcentaje miente.</>
            )}
          </p>
        </>
      )}

      {/* El enfoque va aquí a propósito: pegado a los números que lo
          contradicen. En una pantalla aparte sería un propósito de año nuevo;
          debajo de los KPIs es "dijiste esto y jugaste aquello".
          Se enseña también sin rolls — declarar lo que vas a trabajar es justo
          lo que tiene sentido hacer antes de empezar. */}
      {!cargando && (
        <Enfoque practicanteId={autor} esMio={esMio} nombre={quien?.nombre ?? ''} />
      )}

      {/* La coleccion va aqui, y no en una pestaña propia, por la misma razon
          que el enfoque: esta pantalla ya es la ficha de cada uno — tiene el
          selector de practicante y todo lo que se sabe de su juego. */}
      {!cargando && (
        <Coleccion practicanteId={autor} esMio={esMio} nombre={quien?.nombre ?? ''} />
      )}

      {!cargando && datos && k && k.rolls > 0 && (
        <>
          <Heatmaps off={datos.off} def={datos.def} claro={tema === 'claro'}
            onCelda={abrirCelda} />

          {celda && (
            <DetalleCelda actor={celda.actor} c={celda.c} rolls={celda.rolls}
              onCerrar={() => setCelda(null)} />
          )}

          <Divergente titulo="Saldo por guardia"
            cap="Barridas y ataques a favor menos pases y sumisiones en contra."
            filas={datos.guardias} testid="guardias" />

          <Divergente titulo="Fuertes y débiles"
            cap="Acciones completadas a favor menos en contra, en cada posición."
            filas={datos.posiciones} testid="posiciones" />

          <Divergente titulo="Head-to-head"
            cap="Sumisiones a favor menos en contra, por compañero."
            filas={datos.h2h.map((r) => ({
              posicion: r.id as unknown as Posicion,
              nom: `${r.nom} · ${r.cin.charAt(0).toUpperCase()}`,
              favor: r.favor, contra: r.contra, saldo: r.favor - r.contra,
              extra: `${r.rolls} rolls`,
            }))} testid="h2h" />

          <Evolucion filas={datos.evo} />

          <Tecnicas filas={datos.tec} />

          <div style={{ marginTop: 14 }}>
            <button className="f" data-testid="ver-tablas"
              onClick={() => setTablas((t) => !t)}>
              {tablas ? 'Ocultar tablas' : 'Ver los mismos datos como tabla'}
            </button>
          </div>
          {tablas && <Tablas d={datos} />}
        </>
      )}
    </div>
  );
}

function Kpi({ v, l }: { v: number; l: string }) {
  return <div className="kpi"><div className="v">{v}</div><div className="l">{l}</div></div>;
}

/**
 * Los dos heatmaps.
 *
 * En el diseño de escritorio van lado a lado. A 390px no caben dos rejillas de
 * diez columnas, así que se enseña uno cada vez con pestañas: se sacrifica
 * densidad, nunca legibilidad de las etiquetas.
 */
function Heatmaps(
  { off, def, claro, onCelda }: {
    off: Celda[]; def: Celda[]; claro: boolean;
    onCelda: (actor: 'yo' | 'oponente', c: Celda) => void;
  },
) {
  const [cual, setCual] = useState<'off' | 'def'>('off');
  const datos = cual === 'off' ? off : def;
  return (
    <div className="tarjeta">
      <div className="filtros" style={{ marginTop: 0, marginBottom: 12 }}>
        <button className="f" aria-pressed={cual === 'off'} data-testid="hm-off"
          onClick={() => setCual('off')}>Ofensivo</button>
        <button className="f" aria-pressed={cual === 'def'} data-testid="hm-def"
          onClick={() => setCual('def')}>Defensivo</button>
      </div>
      <h2>{cual === 'off' ? 'Heatmap ofensivo' : 'Heatmap defensivo'}</h2>
      <p className="cap">
        {cual === 'off'
          ? <>Sumisiones que <b>has finalizado</b>, por posición y articulación.</>
          : <>Sumisiones que <b>te han aplicado</b> — dónde te pillan.</>}
      </p>
      <Heat celdas={datos} rampa0={cual === 'off' ? AZUL : NARANJA} claro={claro}
        verbo={cual === 'off' ? 'finalizadas' : 'recibidas'}
        onCelda={(c) => onCelda(cual === 'off' ? 'yo' : 'oponente', c)} />
    </div>
  );
}

function Heat(
  { celdas, rampa0, claro, verbo, onCelda }: {
    celdas: Celda[]; rampa0: string[]; claro: boolean; verbo: string;
    onCelda: (c: Celda) => void;
  },
) {
  // En oscuro la rampa se invierte: el extremo "cerca de cero" tiene que ser
  // el que se funde con el fondo. Sin invertirla, los valores bajos son los
  // que más brillan y el heatmap miente.
  const rampa = claro ? rampa0 : [...rampa0].reverse();
  const max = Math.max(1, ...celdas.map((c) => c.n));
  const porClave = new Map(celdas.map((c) => [`${c.posicion}|${c.objetivo}`, c]));

  // Las filas sí se filtran a las posiciones con algún dato, o la tabla se
  // hace ilegible. Las columnas NO: que nunca ataques a la muñeca es
  // información, no ruido.
  const filas = [...new Map(celdas.map((c) => [c.posicion, c.posicion_nombre])).entries()];

  if (!filas.length) {
    return <p className="nota" data-testid="hm-vacio">
      Ninguna sumisión {verbo} con estos filtros.
    </p>;
  }

  return (
    <>
      <div className="hmbox">
        <table className="hm">
          <thead>
            <tr>
              <th />
              {OBJETIVOS.map((o) => (
                <th key={o} className="colh"><span>{etiquetaObj(o)}</span></th>
              ))}
            </tr>
          </thead>
          <tbody>
            {filas.map(([pos, nombre]) => (
              <tr key={pos}>
                <th className="rowh" title={nombre}>{nombre}</th>
                {OBJETIVOS.map((o) => {
                  const c = porClave.get(`${pos}|${o}`);
                  if (!c) return <td key={o} className="cell zero" />;
                  const i = Math.min(
                    rampa.length - 1,
                    Math.round((c.n / max) * (rampa.length - 1)),
                  );
                  const fondo = rampa[i];
                  return (
                    <td key={o} className="cell tocable"
                      style={{ background: fondo, color: tinta(fondo) }}
                      data-testid={`celda-${pos}-${o}`}
                      title={`${c.n} ${verbo} · ${nombre} · objetivo ${NOMBRE_OBJETIVO[o]}`
                        + (c.intentos > c.n ? ` · ${c.intentos} intentos` : '')
                        + ' · toca para ver los rolls'}
                      onClick={() => onCelda(c)}>
                      {c.n}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="escala">
        <span>0</span>
        {rampa.filter((_, i) => i % 2 === 0).map((c, i) => (
          <i key={i} style={{ background: c }} />
        ))}
        <span>{max}</span>
        <span style={{ marginLeft: 5 }}>sumisiones</span>
      </div>
    </>
  );
}

/** De la celda a los rolls que hay detrás. Es lo que la hace herramienta. */
function DetalleCelda(
  { actor, c, rolls, onCerrar }: {
    actor: 'yo' | 'oponente'; c: Celda; rolls: RollCelda[] | null; onCerrar: () => void;
  },
) {
  return (
    <div className="tarjeta" data-testid="detalle-celda">
      <h2>
        {c.posicion_nombre} · {NOMBRE_OBJETIVO[c.objetivo]}
      </h2>
      <p className="cap">
        {c.n} {actor === 'yo' ? 'finalizadas' : 'recibidas'}
        {c.intentos > c.n && <> de {c.intentos} intentos</>}.
      </p>
      {rolls === null ? <p className="nota">Buscando los rolls…</p> : (
        <table className="tv">
          <thead><tr><th>Fecha</th><th>Rival</th><th>Qué pasó</th></tr></thead>
          <tbody>
            {rolls.map((r, i) => (
              <tr key={`${r.roll_id}-${i}`}>
                <td>{r.fecha}</td>
                <td>{r.rival}</td>
                <td>
                  {r.tecnica ?? 'sin técnica'}
                  {!r.completado && ' (falló)'}
                  {r.origen === 'observador' && ' · observado'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <div style={{ marginTop: 12 }}>
        <button className="f" onClick={onCerrar} data-testid="cerrar-detalle">Cerrar</button>
      </div>
    </div>
  );
}

interface FilaSaldo extends Saldo { extra?: string }

function Divergente(
  { titulo, cap, filas, testid }: {
    titulo: string; cap: string; filas: FilaSaldo[]; testid: string;
  },
) {
  if (!filas.length) return null;
  const max = Math.max(1, ...filas.map((r) => Math.abs(r.saldo)));
  return (
    <div className="tarjeta" data-testid={testid}>
      <h2>{titulo}</h2>
      <p className="cap">{cap}</p>
      <div className="bars">
        {filas.map((r) => {
          const pct = (Math.abs(r.saldo) / max) * 50;
          const positivo = r.saldo >= 0;
          return (
            <div className="brow" key={r.posicion + r.nom}
              title={`${r.nom} · ${r.favor} a favor · ${r.contra} en contra`
                + (r.extra ? ` · ${r.extra}` : '')}>
              <div className="nm">{r.nom}</div>
              <div className="track">
                <span className="mid" style={{ left: '50%' }} />
                <span className="fill" style={{
                  background: positivo ? 'var(--dato-yo)' : 'var(--dato-neg)',
                  ...(positivo ? { left: '50%' } : { right: '50%' }),
                  width: `${pct}%`,
                }} />
              </div>
              <div className="val">{r.saldo > 0 ? '+' : ''}{r.saldo}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** Una línea, dos series, leyenda siempre visible. Nunca dos ejes Y. */
function Evolucion({ filas }: { filas: Semana[] }) {
  if (filas.length < 2) return null;
  // El viewBox va al ancho real de la tarjeta en un móvil, no a los 560 del
  // diseño de escritorio. Con 560 escalados a ~310px, las etiquetas del eje
  // salían a unos 6px: ilegibles. Aquí la escala es ~1:1 y el texto se lee.
  const W = 330, H = 180, PL = 24, PR = 12, PT = 12, PB = 24;
  const n = filas.length;
  const maxY = Math.max(...filas.flatMap((e) => [e.favor, e.contra]), 4);
  const X = (i: number) => PL + (i * (W - PL - PR)) / (n - 1);
  const Y = (v: number) => PT + (1 - v / maxY) * (H - PT - PB);
  const camino = (k: 'favor' | 'contra') =>
    filas.map((e, i) => `${i ? 'L' : 'M'}${X(i).toFixed(1)},${Y(e[k]).toFixed(1)}`).join(' ');
  const paso = Math.max(1, Math.ceil(maxY / 4));
  const marcas: number[] = [];
  for (let t = 0; t <= maxY; t += paso) marcas.push(t);
  const ult = n - 1;

  return (
    <div className="tarjeta" data-testid="evolucion">
      <h2>Evolución semanal</h2>
      <p className="cap">Sumisiones a favor y en contra, semana a semana.</p>
      <div className="leyenda">
        <span><b style={{ background: 'var(--dato-yo)' }} />A favor</span>
        <span><b style={{ background: 'var(--dato-op)' }} />En contra</span>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }} role="img"
        aria-label="Sumisiones a favor y en contra por semana">
        {marcas.map((t) => (
          <g key={t}>
            <line x1={PL} x2={W - PR} y1={Y(t)} y2={Y(t)} stroke="var(--rejilla)" strokeWidth={1} />
            <text x={PL - 7} y={Y(t) + 3.5} textAnchor="end" fontSize={10.5} fill="var(--tenue)">{t}</text>
          </g>
        ))}
        <path d={camino('contra')} fill="none" stroke="var(--dato-op)" strokeWidth={2} strokeLinejoin="round" />
        <path d={camino('favor')} fill="none" stroke="var(--dato-yo)" strokeWidth={2} strokeLinejoin="round" />
        {filas.map((e, i) => (
          <g key={e.semana}>
            <circle cx={X(i)} cy={Y(e.favor)} r={4} fill="var(--dato-yo)"
              stroke="var(--superficie)" strokeWidth={2}>
              <title>{`Semana del ${e.semana}: ${e.rolls} rolls, ${e.favor} a favor`}</title>
            </circle>
            <circle cx={X(i)} cy={Y(e.contra)} r={4} fill="var(--dato-op)"
              stroke="var(--superficie)" strokeWidth={2}>
              <title>{`Semana del ${e.semana}: ${e.contra} en contra`}</title>
            </circle>
          </g>
        ))}
        {/* Etiqueta directa solo en el último punto. */}
        <text x={X(ult) - 4} y={Y(filas[ult].favor) - 10} textAnchor="end" fontSize={11.5}
          fill="var(--texto)">{filas[ult].favor} a favor</text>
        <text x={X(ult) - 4} y={Y(filas[ult].contra) + 18} textAnchor="end" fontSize={11.5}
          fill="var(--texto)">{filas[ult].contra} en contra</text>
        <text x={PL} y={H - 6} fontSize={10.5} fill="var(--tenue)">{filas[0].semana.slice(5)}</text>
        <text x={W - PR} y={H - 6} fontSize={10.5} fill="var(--tenue)" textAnchor="end">
          {filas[ult].semana.slice(5)}
        </text>
      </svg>
    </div>
  );
}

function Tecnicas({ filas }: { filas: Tecnica[] }) {
  /**
   * Plegado por MECÁNICA, y se despliega tocando.
   *
   * Catorce kimuras son catorce kimuras, se hayan precisado o no: nadie pierde
   * nada por precisar, que es la condición para que alguien lo haga. El
   * desglose ya viene dentro de cada fila desde `analisis()`, así que
   * desplegar no pide nada a la red.
   */
  const [abierta, setAbierta] = useState<string | null>(null);
  if (!filas.length) return null;
  const max = Math.max(...filas.map((r) => r.tot));
  const pct = (v: Variante) => Math.round((v.ok / v.tot) * 100);
  return (
    <div className="tarjeta" data-testid="tecnicas">
      <h2>Tus sumisiones</h2>
      <p className="cap">Finalizadas sobre intentadas, agrupadas por mecánica.</p>
      <div className="bars">
        {filas.map((r) => {
          const desplegable = !!r.variantes?.length;
          const abierto = abierta === r.mecanica_id;
          return (
            <div key={r.mecanica_id}>
              <div className="brow" data-testid={`mecanica-${r.mecanica_id}`}
                role={desplegable ? 'button' : undefined}
                tabIndex={desplegable ? 0 : undefined}
                onClick={() => desplegable && setAbierta(abierto ? null : r.mecanica_id)}
                onKeyDown={(e) => {
                  if (desplegable && (e.key === 'Enter' || e.key === ' ')) {
                    e.preventDefault();
                    setAbierta(abierto ? null : r.mecanica_id);
                  }
                }}
                style={{
                  gridTemplateColumns: '98px 1fr 48px',
                  cursor: desplegable ? 'pointer' : undefined,
                  // 44px de objetivo táctil cuando se puede tocar.
                  minHeight: desplegable ? 44 : undefined,
                }}
                title={`${r.nom}: ${r.ok} finalizadas de ${r.tot} intentadas`}>
                <div className="nm">
                  {desplegable && <span aria-hidden>{abierto ? '▾ ' : '▸ '}</span>}
                  {r.nom}
                </div>
                <div className="track">
                  <span className="fill" style={{
                    background: 'var(--rejilla)', left: 0, width: `${(r.tot / max) * 100}%`,
                  }} />
                  <span className="fill" style={{
                    background: 'var(--dato-yo)', left: 0, width: `${(r.ok / max) * 100}%`,
                  }} />
                </div>
                <div className="val">{r.ok}/{r.tot}</div>
              </div>

              {abierto && r.variantes && (
                <div data-testid={`variantes-${r.mecanica_id}`}
                  style={{ margin: '2px 0 8px 14px' }}>
                  {r.variantes.map((v) => (
                    <div className="brow" key={v.id}
                      style={{ gridTemplateColumns: '84px 1fr 48px' }}
                      title={`${v.nom}: ${v.ok} de ${v.tot}`}>
                      <div className="nm" style={{ fontSize: 12 }}>{v.nom}</div>
                      <div className="track">
                        <span className="fill" style={{
                          background: 'var(--rejilla)', left: 0, width: `${(v.tot / max) * 100}%`,
                        }} />
                        <span className="fill" style={{
                          background: 'var(--dato-yo)', left: 0, width: `${(v.ok / max) * 100}%`,
                        }} />
                      </div>
                      <div className="val">{v.ok}/{v.tot}</div>
                    </div>
                  ))}
                  {/* La frase que justifica el bloque entero. Solo cuando los
                      números dan para ella: `compara` lo decide SQL, porque 1
                      de 1 no es el 100%. */}
                  {r.compara && (
                    <p className="nota" data-testid={`compara-${r.mecanica_id}`}
                      style={{ marginTop: 6 }}>
                      {[...r.variantes]
                        .filter((v) => v.tot >= 5)
                        .sort((a, b) => pct(b) - pct(a))
                        .slice(0, 2)
                        .map((v) => `tu ${v.nom.toLowerCase()} entra el ${pct(v)}%`)
                        .join(', y ')}.
                    </p>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
      <p className="nota">Barra llena = finalizadas · barra clara = intentadas.</p>
    </div>
  );
}

/** Los mismos datos como tabla. No es un extra: es la vía accesible. */
function Tablas({ d }: { d: Datos }) {
  const tabla = (tit: string, cabs: string[], filas: (string | number)[][]) => (
    <div key={tit}>
      <h2 style={{ fontSize: 13, margin: '16px 0 6px' }}>{tit}</h2>
      <table className="tv">
        <thead><tr>{cabs.map((c) => <th key={c}>{c}</th>)}</tr></thead>
        <tbody>
          {filas.map((f, i) => (
            <tr key={i}>{f.map((c, j) => <td key={j}>{c}</td>)}</tr>
          ))}
        </tbody>
      </table>
    </div>
  );
  return (
    <div className="tarjeta" data-testid="tablas">
      {tabla('Heatmap ofensivo', ['Posición', 'Objetivo', 'Finalizadas'],
        [...d.off].sort((a, b) => b.n - a.n)
          .map((c) => [c.posicion_nombre, NOMBRE_OBJETIVO[c.objetivo], c.n]))}
      {tabla('Heatmap defensivo', ['Posición', 'Objetivo', 'Recibidas'],
        [...d.def].sort((a, b) => b.n - a.n)
          .map((c) => [c.posicion_nombre, NOMBRE_OBJETIVO[c.objetivo], c.n]))}
      {tabla('Guardias', ['Guardia', 'A favor', 'En contra', 'Saldo'],
        d.guardias.map((r) => [r.nom, r.favor, r.contra, r.saldo]))}
      {tabla('Head-to-head', ['Compañero', 'Cinturón', 'Rolls', 'A favor', 'En contra'],
        d.h2h.map((r) => [r.nom, r.cin, r.rolls, r.favor, r.contra]))}
      {tabla('Evolución semanal', ['Semana', 'Rolls', 'A favor', 'En contra'],
        d.evo.map((r) => [r.semana, r.rolls, r.favor, r.contra]))}
    </div>
  );
}
