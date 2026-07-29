/**
 * El marcador estilo IBJJF.
 *
 * REGLA DE ARQUITECTURA: los puntos se derivan, nunca se guardan. No hay
 * columna `puntos` en `rolls` ni en `eventos`. El tanteo es una función de la
 * lista de eventos, igual que el heatmap — si mañana se corrige un evento mal
 * registrado, el marcador se corrige solo. Una columna guardada se quedaría
 * vieja y nadie se enteraría.
 *
 * Consecuencia: este cálculo existe DOS VECES, aquí para el marcador en vivo y
 * en SQL (`puntos_roll()`, en `db/07_transicion_y_puntos.sql`) para el análisis
 * histórico. Dos implementaciones que se separan son un bug esperando, así que
 * las dos leen las mismas reglas y los mismos casos de prueba:
 * `src/lib/__fixtures__/puntos.json`. Si tocas una regla aquí, tócala allí, y
 * el fixture te dirá si te has dejado una.
 *
 * Sobre los 3 segundos de estabilización del reglamento: NO se implementan a
 * propósito. El observador pulsa cuando la posición ya está hecha — el dedo
 * humano es la estabilización. Un temporizador solo añadiría latencia y falsos
 * negativos. No lo "arregles".
 */
import { esGuardia } from './bjj';
import type { Actor, Posicion, TipoEvento } from './database.types';

/** Lo mínimo que necesita un evento para puntuar. */
export interface EventoPuntuable {
  actor: Actor;
  tipo: TipoEvento;
  posicion: Posicion;
}

export type ClavePunto =
  | 'derribo' | 'barrida' | 'pase' | 'espalda' | 'montada' | 'rodilla_en_barriga';

interface Regla {
  /** Identifica la posición conseguida: es la clave del "no re-puntuar". */
  clave: ClavePunto;
  puntos: number;
  /** Lo que se enseña en el destello del marcador: "+3 paso". */
  etiqueta: string;
  tipo: TipoEvento;
  /** Solo para las transiciones, donde `posicion` es el destino. */
  posicion?: Posicion;
}

/**
 * La tabla oficial. Declarativa a propósito: una cascada de `if` se convierte
 * en un sitio donde meter excepciones, y aquí no queremos excepciones.
 *
 * Todo lo que no está aquí vale cero: `cien_kilos` (control lateral) no puntúa
 * porque ya lo cubren los 3 del pase, y tampoco `norte_sur`, `kesa_gatame`,
 * `tortuga`, `scramble`, `escape` ni `sumision`.
 */
export const REGLAS: readonly Regla[] = [
  { clave: 'derribo',            puntos: 2, etiqueta: 'derribo',  tipo: 'derribo' },
  { clave: 'barrida',            puntos: 2, etiqueta: 'barrida',  tipo: 'barrida' },
  { clave: 'pase',               puntos: 3, etiqueta: 'paso',     tipo: 'pase_guardia' },
  { clave: 'espalda',            puntos: 4, etiqueta: 'espalda',  tipo: 'toma_espalda' },
  { clave: 'montada',            puntos: 4, etiqueta: 'montada',  tipo: 'transicion', posicion: 'montada' },
  { clave: 'rodilla_en_barriga', puntos: 2, etiqueta: 'rodilla',  tipo: 'transicion', posicion: 'rodilla_en_barriga' },
];

function reglaDe(e: EventoPuntuable): Regla | undefined {
  return REGLAS.find((r) => r.tipo === e.tipo
    && (r.posicion === undefined || r.posicion === e.posicion));
}

/**
 * Un evento que significa que el actor SALIÓ de abajo.
 *
 * Cierra la secuencia del rival y le vacía su conjunto de posiciones ya
 * puntuadas, de modo que si vuelve a montar, vuelve a puntuar. Los tipos que no
 * son posicionales (una sumisión, entre o no) no cierran nada.
 */
function libera(e: EventoPuntuable): boolean {
  return e.tipo === 'escape'
    || e.tipo === 'barrida'
    || (e.tipo === 'transicion' && esGuardia(e.posicion));
}

const rival = (a: Actor): Actor => (a === 'yo' ? 'oponente' : 'yo');

export interface Anotacion {
  /** Índice del evento que la produjo, para poder señalarlo en la interfaz. */
  indice: number;
  actor: Actor;
  clave: ClavePunto;
  puntos: number;
  etiqueta: string;
}

export interface Marcador {
  /** Puntos del actor `yo`: el dueño del roll, o el practicante A si se observa. */
  a: number;
  /** Puntos del actor `oponente`. */
  b: number;
  desglose: Anotacion[];
}

/**
 * El tanteo de un roll.
 *
 * Lo que hace que esto no sea una suma: **una posición puntúa una vez por
 * secuencia**. El reglamento no premia acumular la misma posición. Montar,
 * pasar a cien kilos y volver a montar sin que el otro haga nada son 4 puntos,
 * no 8. La posición vuelve a puntuar solo cuando el rival ha salido de verdad.
 */
export function puntuar(eventos: readonly EventoPuntuable[]): Marcador {
  const total: Record<Actor, number> = { yo: 0, oponente: 0 };
  const puntuadas: Record<Actor, Set<ClavePunto>> = { yo: new Set(), oponente: new Set() };
  const desglose: Anotacion[] = [];

  eventos.forEach((e, indice) => {
    const regla = reglaDe(e);
    if (regla && !puntuadas[e.actor].has(regla.clave)) {
      puntuadas[e.actor].add(regla.clave);
      total[e.actor] += regla.puntos;
      desglose.push({
        indice, actor: e.actor, clave: regla.clave,
        puntos: regla.puntos, etiqueta: regla.etiqueta,
      });
    }
    // Primero se puntúa y después se cierra: una barrida puntúa para quien la
    // hace Y le abre la secuencia de nuevo al rival.
    if (libera(e)) puntuadas[rival(e.actor)].clear();
  });

  return { a: total.yo, b: total.oponente, desglose };
}

/** El mismo roll visto desde el otro lado. Solo cambia `actor` — ver CLAUDE.md. */
export function espejar<T extends EventoPuntuable>(eventos: readonly T[]): T[] {
  return eventos.map((e) => ({ ...e, actor: rival(e.actor) }));
}
