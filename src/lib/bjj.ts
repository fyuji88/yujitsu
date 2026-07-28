/**
 * El vocabulario BJJ y la máquina de estados del roll.
 *
 * Esto es el corazón del logging: la app sabe en qué posición estás y solo
 * ofrece lo que puede pasar desde ahí. Sin esto sería un formulario con
 * 24 posiciones y 63 técnicas en desplegables, y nadie lo rellenaría.
 */
import type { Objetivo, Posicion, Rol, TipoEvento } from './database.types';

export const NOMBRE_POSICION: Record<Posicion, string> = {
  de_pie: 'De pie', clinch: 'Clinch',
  guardia_cerrada: 'Guardia cerrada', guardia_abierta: 'Guardia abierta',
  media_guardia: 'Media guardia', mariposa: 'Mariposa', de_la_riva: 'De la Riva',
  de_la_riva_inversa: 'DLR inversa', arana: 'Araña', lasso: 'Lasso',
  collar_manga: 'Collar y manga', x_guard: 'X-guard', single_leg_x: 'Single leg X',
  guardia_sentada: 'Guardia sentada', cincuenta_cincuenta: '50/50',
  montada: 'Montada', cien_kilos: 'Cien kilos', kesa_gatame: 'Kesa gatame',
  norte_sur: 'Norte-sur', rodilla_en_barriga: 'Rodilla en barriga',
  espalda: 'Espalda', tortuga: 'Tortuga', scramble: 'Scramble', otra: 'Otra',
};

export const NOMBRE_OBJETIVO: Record<Objetivo, string> = {
  cuello: 'cuello', hombro: 'hombro', codo: 'codo', muneca: 'muñeca',
  biceps: 'bíceps', columna: 'columna', cadera: 'cadera', rodilla: 'rodilla',
  tobillo_pie: 'tobillo/pie', pantorrilla: 'pantorrilla', ninguno: '—',
};

export const GUARDIAS_RAPIDAS: Posicion[] = [
  'guardia_cerrada', 'media_guardia', 'mariposa', 'de_la_riva', 'guardia_abierta',
];

export const GUARDIAS_TODAS: Posicion[] = [
  ...GUARDIAS_RAPIDAS,
  'x_guard', 'single_leg_x', 'guardia_sentada', 'cincuenta_cincuenta',
  'arana', 'lasso', 'collar_manga', 'de_la_riva_inversa',
];

export const DOMINANTES: Posicion[] = [
  'cien_kilos', 'montada', 'espalda', 'norte_sur', 'rodilla_en_barriga',
  'kesa_gatame', 'tortuga',
];

export const esGuardia = (p: Posicion) => GUARDIAS_TODAS.includes(p);

/** Sumisiones plausibles desde cada posición: esto es lo que evita el scroll. */
type Sub = readonly [slug: string, objetivo: Objetivo];

const SUBS: Partial<Record<Posicion, readonly Sub[]>> = {
  montada: [['armbar', 'codo'], ['cruzada', 'cuello'], ['americana', 'hombro'], ['ezekiel', 'cuello']],
  cien_kilos: [['kimura', 'hombro'], ['americana', 'hombro'], ['katagatame', 'cuello']],
  espalda: [['mata_leao', 'cuello'], ['bow_and_arrow', 'cuello'], ['ezekiel', 'cuello']],
  norte_sur: [['north_south_choke', 'cuello'], ['kimura', 'hombro']],
  rodilla_en_barriga: [['cruzada', 'cuello'], ['armbar', 'codo']],
  kesa_gatame: [['americana', 'hombro'], ['katagatame', 'cuello']],
  tortuga: [['mata_leao', 'cuello'], ['darce', 'cuello']],
};

const SUBS_GUARDIA_ABAJO: readonly Sub[] = [
  ['triangulo', 'cuello'], ['omoplata', 'hombro'], ['armbar', 'codo'],
  ['kimura', 'hombro'], ['guillotina', 'cuello'],
];
const SUBS_GUARDIA_ARRIBA: readonly Sub[] = [
  ['guillotina', 'cuello'], ['darce', 'cuello'], ['katagatame', 'cuello'],
];
const SUBS_PIERNAS: readonly Sub[] = [
  ['heel_hook', 'rodilla'], ['straight_ankle', 'tobillo_pie'],
  ['toe_hold', 'tobillo_pie'], ['kneebar', 'rodilla'],
];

export function sumisionesPara(pos: Posicion, rol: Rol): readonly Sub[] {
  const propias = SUBS[pos];
  if (propias) return propias;
  if (pos === 'single_leg_x' || pos === 'cincuenta_cincuenta' || pos === 'x_guard') {
    return SUBS_PIERNAS;
  }
  if (esGuardia(pos)) return rol === 'abajo' ? SUBS_GUARDIA_ABAJO : SUBS_GUARDIA_ARRIBA;
  return SUBS_GUARDIA_ABAJO;
}

// ---------------------------------------------------------------- acciones

export type ClaveAccion =
  | 'derribo' | 'puxada' | 'barrida' | 'sumision' | 'toma_espalda' | 'pase'
  | 'mejora' | 'escape'
  | 'op_derribo' | 'op_puxada' | 'op_barrida' | 'op_sumision' | 'op_espalda'
  | 'op_pase' | 'op_mejora' | 'op_escape';

export interface Accion {
  clave: ClaveAccion;
  etiqueta: string;
}

export interface EstadoRoll {
  pos: Posicion;
  rol: Rol;
}

/** Qué puede pasar desde donde estás. El resto de la app cuelga de esto. */
export function accionesPosibles(e: EstadoRoll): { yo: Accion[]; op: Accion[] } {
  const a = (clave: ClaveAccion, etiqueta: string): Accion => ({ clave, etiqueta });

  if (e.rol === 'neutral') {
    return {
      yo: [a('derribo', 'Derribo'), a('puxada', 'Tiro guardia')],
      op: [a('op_derribo', 'Me derriba'), a('op_puxada', 'Tira guardia')],
    };
  }
  if (esGuardia(e.pos) && e.rol === 'abajo') {
    return {
      yo: [a('barrida', 'Barrida'), a('sumision', 'Sumisión'), a('toma_espalda', 'Tomo espalda')],
      op: [a('op_pase', 'Me pasa'), a('op_sumision', 'Me somete')],
    };
  }
  if (esGuardia(e.pos) && e.rol === 'arriba') {
    return {
      yo: [a('pase', 'Paso guardia'), a('sumision', 'Sumisión')],
      op: [a('op_barrida', 'Me barre'), a('op_sumision', 'Me somete'), a('op_espalda', 'Toma mi espalda')],
    };
  }
  if (e.rol === 'arriba') {
    return {
      yo: [a('sumision', 'Sumisión'), a('mejora', 'Mejoro posición')],
      op: [a('op_escape', 'Escapa')],
    };
  }
  return {
    yo: [a('escape', 'Escapo')],
    op: [a('op_sumision', 'Me somete'), a('op_mejora', 'Mejora posición')],
  };
}

// ---------------------------------------------------------------- transiciones

export interface EventoBorrador {
  actor: 'yo' | 'oponente';
  tipo: TipoEvento;
  posicion: Posicion;
  rol: Rol;
  objetivo: Objetivo;
  tecnicaSlug: string | null;
  completado: boolean;
}

/** Un paso pendiente: la app tiene que preguntar algo antes de cerrar el evento. */
export type Pendiente =
  | { tipo: 'posicion'; titulo: string; opciones: Posicion[]; mas?: boolean;
      siguiente: (p: Posicion) => EstadoRoll }
  | { tipo: 'tecnica'; titulo: string; actor: 'yo' | 'oponente';
      posicion: Posicion; rol: Rol; opciones: readonly Sub[] };

export interface ResultadoAccion {
  /** Evento que se registra ya (puede no haber: p. ej. mejorar posición). */
  evento?: EventoBorrador;
  /** Estado nuevo, si la acción no necesita preguntar nada. */
  estado?: EstadoRoll;
  /** Pregunta pendiente. */
  pendiente?: Pendiente;
}

const otro = (r: Rol): Rol => (r === 'arriba' ? 'abajo' : r === 'abajo' ? 'arriba' : 'neutral');

export function aplicarAccion(clave: ClaveAccion, e: EstadoRoll): ResultadoAccion {
  const ev = (
    actor: 'yo' | 'oponente', tipo: TipoEvento, posicion: Posicion, rol: Rol,
  ): EventoBorrador => ({
    actor, tipo, posicion, rol, objetivo: 'ninguno', tecnicaSlug: null, completado: true,
  });

  switch (clave) {
    case 'derribo':
      return {
        evento: ev('yo', 'derribo', 'de_pie', 'neutral'),
        pendiente: {
          tipo: 'posicion', titulo: '¿Dónde caes?',
          opciones: ['cien_kilos', 'norte_sur', 'media_guardia', 'guardia_cerrada'],
          siguiente: (p) => ({ pos: p, rol: 'arriba' }),
        },
      };
    case 'op_derribo':
      return {
        evento: ev('oponente', 'derribo', 'de_pie', 'neutral'),
        pendiente: {
          tipo: 'posicion', titulo: '¿Dónde caes tú?',
          opciones: ['cien_kilos', 'montada', 'media_guardia', 'guardia_cerrada'],
          siguiente: (p) => ({ pos: p, rol: 'abajo' }),
        },
      };
    case 'puxada':
      return {
        evento: { ...ev('yo', 'derribo', 'de_pie', 'neutral'), tecnicaSlug: 'puxada' },
        pendiente: {
          tipo: 'posicion', titulo: '¿Qué guardia?', opciones: GUARDIAS_RAPIDAS, mas: true,
          siguiente: (p) => ({ pos: p, rol: 'abajo' }),
        },
      };
    case 'op_puxada':
      return {
        evento: { ...ev('oponente', 'derribo', 'de_pie', 'neutral'), tecnicaSlug: 'puxada' },
        pendiente: {
          tipo: 'posicion', titulo: '¿Qué guardia juega?', opciones: GUARDIAS_RAPIDAS, mas: true,
          siguiente: (p) => ({ pos: p, rol: 'arriba' }),
        },
      };

    case 'barrida':
      return {
        evento: ev('yo', 'barrida', e.pos, 'abajo'),
        pendiente: {
          tipo: 'posicion', titulo: '¿Dónde acabas?',
          opciones: ['media_guardia', 'cien_kilos', 'montada', 'de_pie'],
          siguiente: (p) => ({ pos: p, rol: p === 'de_pie' ? 'neutral' : 'arriba' }),
        },
      };
    case 'op_barrida':
      return {
        evento: ev('oponente', 'barrida', e.pos, 'abajo'),
        pendiente: {
          tipo: 'posicion', titulo: '¿Dónde acabas tú?',
          opciones: ['media_guardia', 'cien_kilos', 'montada', 'de_pie'],
          siguiente: (p) => ({ pos: p, rol: p === 'de_pie' ? 'neutral' : 'abajo' }),
        },
      };

    case 'pase':
      return {
        evento: ev('yo', 'pase_guardia', e.pos, 'arriba'),
        pendiente: {
          tipo: 'posicion', titulo: '¿Dónde llegas?',
          opciones: ['cien_kilos', 'montada', 'norte_sur', 'rodilla_en_barriga'],
          siguiente: (p) => ({ pos: p, rol: 'arriba' }),
        },
      };
    case 'op_pase':
      return {
        evento: ev('oponente', 'pase_guardia', e.pos, 'arriba'),
        pendiente: {
          tipo: 'posicion', titulo: '¿Dónde te controla?',
          opciones: ['cien_kilos', 'montada', 'norte_sur', 'rodilla_en_barriga'],
          siguiente: (p) => ({ pos: p, rol: 'abajo' }),
        },
      };

    case 'toma_espalda':
      return {
        evento: ev('yo', 'toma_espalda', e.pos, e.rol),
        estado: { pos: 'espalda', rol: 'arriba' },
      };
    case 'op_espalda':
      return {
        evento: ev('oponente', 'toma_espalda', e.pos, e.rol),
        estado: { pos: 'espalda', rol: 'abajo' },
      };

    // Mejorar posición NO genera evento salvo que acabe en la espalda: no es
    // ninguno de nuestros seis tipos. Ver el backlog: `transicion` pendiente.
    case 'mejora':
      return {
        pendiente: {
          tipo: 'posicion', titulo: '¿A dónde pasas?',
          opciones: DOMINANTES.filter((p) => p !== e.pos),
          siguiente: (p) => ({ pos: p, rol: 'arriba' }),
        },
      };
    case 'op_mejora':
      return {
        pendiente: {
          tipo: 'posicion', titulo: '¿A dónde pasa él?',
          opciones: DOMINANTES.filter((p) => p !== e.pos),
          siguiente: (p) => ({ pos: p, rol: 'abajo' }),
        },
      };

    case 'escape':
      return {
        evento: ev('yo', 'escape', e.pos, 'abajo'),
        pendiente: {
          tipo: 'posicion', titulo: '¿Dónde recuperas?',
          opciones: [...GUARDIAS_RAPIDAS, 'de_pie'],
          siguiente: (p) => ({ pos: p, rol: p === 'de_pie' ? 'neutral' : 'abajo' }),
        },
      };
    case 'op_escape':
      return {
        evento: ev('oponente', 'escape', e.pos, 'abajo'),
        pendiente: {
          tipo: 'posicion', titulo: '¿Qué guardia recupera?',
          opciones: [...GUARDIAS_RAPIDAS, 'de_pie'],
          siguiente: (p) => ({ pos: p, rol: p === 'de_pie' ? 'neutral' : 'arriba' }),
        },
      };

    case 'sumision':
    case 'op_sumision': {
      const actor = clave === 'sumision' ? 'yo' : 'oponente';
      const rol: Rol = clave === 'sumision'
        ? (e.rol === 'neutral' ? 'arriba' : e.rol)
        : otro(e.rol === 'neutral' ? 'abajo' : e.rol);
      return {
        pendiente: {
          tipo: 'tecnica',
          titulo: actor === 'yo' ? '¿Qué le hiciste?' : '¿Qué te hizo?',
          actor, posicion: e.pos, rol, opciones: sumisionesPara(e.pos, rol),
        },
      };
    }
  }
}

/** El resultado del roll se deduce de la última sumisión que entró. */
export function resultadoDe(eventos: EventoBorrador[]) {
  const ultima = [...eventos].reverse().find((e) => e.tipo === 'sumision' && e.completado);
  if (!ultima) return 'sin_sumision' as const;
  return ultima.actor === 'yo' ? ('sumision_favor' as const) : ('sumision_contra' as const);
}
