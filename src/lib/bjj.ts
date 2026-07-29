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

/**
 * Quién está registrando. Cambia las palabras, nunca la máquina de estados.
 *
 * `propio`     — logueas tu roll: "Me pasa", "Escapo", "¿Dónde caes?".
 * `observador` — miras a otros dos: "Pasa la guardia", "Escapa", "¿Dónde cae
 *                Pablo?". Ahí "yo" y "él" no significan nada, y hay que decir
 *                nombres o el coach se pierde sobre quién está tocando.
 */
export type Modo = 'propio' | 'observador';

/**
 * Los dos que ruedan, por nombre.
 *
 * `a` es quien queda como `actor: 'yo'` en los datos y `b` como
 * `actor: 'oponente'`. En modo propio, A eres tú.
 */
export interface Contexto {
  modo: Modo;
  a: string;
  b: string;
}

export const CONTEXTO_PROPIO: Contexto = { modo: 'propio', a: 'Yo', b: 'Él' };

/** Qué puede pasar desde donde estás. El resto de la app cuelga de esto. */
export function accionesPosibles(
  e: EstadoRoll, modo: Modo = 'propio',
): { yo: Accion[]; op: Accion[] } {
  // Cada acción lleva dos etiquetas: la de loguear lo tuyo y la de observar.
  const a = (clave: ClaveAccion, propio: string, observando: string): Accion =>
    ({ clave, etiqueta: modo === 'observador' ? observando : propio });

  if (e.rol === 'neutral') {
    return {
      yo: [a('derribo', 'Derribo', 'Derriba'),
           a('puxada', 'Tiro guardia', 'Tira guardia')],
      op: [a('op_derribo', 'Me derriba', 'Derriba'),
           a('op_puxada', 'Tira guardia', 'Tira guardia')],
    };
  }
  if (esGuardia(e.pos) && e.rol === 'abajo') {
    return {
      yo: [a('barrida', 'Barrida', 'Barrida'),
           a('sumision', 'Sumisión', 'Sumisión'),
           a('toma_espalda', 'Tomo espalda', 'Toma espalda')],
      op: [a('op_pase', 'Me pasa', 'Pasa la guardia'),
           a('op_sumision', 'Me somete', 'Somete')],
    };
  }
  if (esGuardia(e.pos) && e.rol === 'arriba') {
    return {
      yo: [a('pase', 'Paso guardia', 'Pasa la guardia'),
           a('sumision', 'Sumisión', 'Sumisión')],
      op: [a('op_barrida', 'Me barre', 'Barrida'),
           a('op_sumision', 'Me somete', 'Somete'),
           a('op_espalda', 'Toma mi espalda', 'Toma la espalda')],
    };
  }
  if (e.rol === 'arriba') {
    return {
      yo: [a('sumision', 'Sumisión', 'Sumisión'),
           a('mejora', 'Mejoro posición', 'Mejora posición')],
      op: [a('op_escape', 'Escapa', 'Escapa')],
    };
  }
  return {
    yo: [a('escape', 'Escapo', 'Escapa')],
    op: [a('op_sumision', 'Me somete', 'Somete'),
         a('op_mejora', 'Mejora posición', 'Mejora posición')],
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
  /**
   * Segundo del roll. Solo lo rellena el observador, que registra en vivo con
   * el cronómetro corriendo; loguear lo tuyo se hace de memoria al acabar y ahí
   * el sello sería inventado. Aquí no hay reloj: lo pone la pantalla.
   *
   * En segundos y no en minutos porque el cronómetro ya está corriendo y la
   * precisión sale gratis. `minuto` lo deriva Postgres.
   */
  segundo?: number | null;
}

/** Un paso pendiente: la app tiene que preguntar algo antes de cerrar el evento. */
export type Pendiente =
  | { tipo: 'posicion'; titulo: string; opciones: Posicion[]; mas?: boolean;
      siguiente: (p: Posicion) => EstadoRoll;
      /**
       * Evento que solo se puede construir cuando se sabe el destino.
       *
       * Lo usa "mejorar posición": hasta que no eliges a dónde pasas no se
       * sabe si eso es una transición cualquiera o una toma de espalda.
       */
      eventoAlElegir?: (p: Posicion) => EventoBorrador }
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

export function aplicarAccion(
  clave: ClaveAccion, e: EstadoRoll, ctx: Contexto = CONTEXTO_PROPIO,
): ResultadoAccion {
  const ev = (
    actor: 'yo' | 'oponente', tipo: TipoEvento, posicion: Posicion, rol: Rol,
  ): EventoBorrador => ({
    actor, tipo, posicion, rol, objetivo: 'ninguno', tecnicaSlug: null, completado: true,
  });

  // Las preguntas intermedias también cambian de voz: observando no hay "tú",
  // hay dos nombres, y sin ellos no se sabe de quién se está hablando.
  const t = (propio: string, observando: string) =>
    (ctx.modo === 'observador' ? observando : propio);

  switch (clave) {
    case 'derribo':
      return {
        evento: ev('yo', 'derribo', 'de_pie', 'neutral'),
        pendiente: {
          tipo: 'posicion', titulo: t('¿Dónde caes?', `¿Dónde cae ${ctx.b}?`),
          opciones: ['cien_kilos', 'norte_sur', 'media_guardia', 'guardia_cerrada'],
          siguiente: (p) => ({ pos: p, rol: 'arriba' }),
        },
      };
    case 'op_derribo':
      return {
        evento: ev('oponente', 'derribo', 'de_pie', 'neutral'),
        pendiente: {
          tipo: 'posicion', titulo: t('¿Dónde caes tú?', `¿Dónde cae ${ctx.a}?`),
          opciones: ['cien_kilos', 'montada', 'media_guardia', 'guardia_cerrada'],
          siguiente: (p) => ({ pos: p, rol: 'abajo' }),
        },
      };
    case 'puxada':
      return {
        evento: { ...ev('yo', 'derribo', 'de_pie', 'neutral'), tecnicaSlug: 'puxada' },
        pendiente: {
          tipo: 'posicion', titulo: t('¿Qué guardia?', `¿Qué guardia juega ${ctx.a}?`),
          opciones: GUARDIAS_RAPIDAS, mas: true,
          siguiente: (p) => ({ pos: p, rol: 'abajo' }),
        },
      };
    case 'op_puxada':
      return {
        evento: { ...ev('oponente', 'derribo', 'de_pie', 'neutral'), tecnicaSlug: 'puxada' },
        pendiente: {
          tipo: 'posicion', titulo: t('¿Qué guardia juega?', `¿Qué guardia juega ${ctx.b}?`),
          opciones: GUARDIAS_RAPIDAS, mas: true,
          siguiente: (p) => ({ pos: p, rol: 'arriba' }),
        },
      };

    case 'barrida':
      return {
        evento: ev('yo', 'barrida', e.pos, 'abajo'),
        pendiente: {
          tipo: 'posicion', titulo: t('¿Dónde acabas?', `¿Dónde acaba ${ctx.a}?`),
          opciones: ['media_guardia', 'cien_kilos', 'montada', 'de_pie'],
          siguiente: (p) => ({ pos: p, rol: p === 'de_pie' ? 'neutral' : 'arriba' }),
        },
      };
    case 'op_barrida':
      return {
        evento: ev('oponente', 'barrida', e.pos, 'abajo'),
        pendiente: {
          tipo: 'posicion', titulo: t('¿Dónde acabas tú?', `¿Dónde acaba ${ctx.a}?`),
          opciones: ['media_guardia', 'cien_kilos', 'montada', 'de_pie'],
          siguiente: (p) => ({ pos: p, rol: p === 'de_pie' ? 'neutral' : 'abajo' }),
        },
      };

    case 'pase':
      return {
        evento: ev('yo', 'pase_guardia', e.pos, 'arriba'),
        pendiente: {
          tipo: 'posicion', titulo: t('¿Dónde llegas?', `¿Dónde llega ${ctx.a}?`),
          opciones: ['cien_kilos', 'montada', 'norte_sur', 'rodilla_en_barriga'],
          siguiente: (p) => ({ pos: p, rol: 'arriba' }),
        },
      };
    case 'op_pase':
      return {
        evento: ev('oponente', 'pase_guardia', e.pos, 'arriba'),
        pendiente: {
          tipo: 'posicion', titulo: t('¿Dónde te controla?', `¿Dónde controla ${ctx.b}?`),
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

    // Mejorar posición SÍ genera evento desde que existe `transicion`. Antes se
    // actualizaba la posición sin escribir nada, y eso dejaba fuera los 4 de la
    // montada y los 2 de la rodilla en barriga: el marcador se dejaba 6 de los
    // puntos posibles y era falso en la mayoría de los rolls.
    //
    // Llegar a la espalda es la excepción: eso ya tenía su tipo propio, y
    // `toma_espalda` puntúa 4, así que se registra como toma de espalda y no
    // como transición.
    case 'mejora':
      return {
        pendiente: {
          tipo: 'posicion', titulo: t('¿A dónde pasas?', `¿A dónde pasa ${ctx.a}?`),
          opciones: DOMINANTES.filter((p) => p !== e.pos),
          siguiente: (p) => ({ pos: p, rol: 'arriba' }),
          eventoAlElegir: (p) => (p === 'espalda'
            ? ev('yo', 'toma_espalda', e.pos, 'arriba')
            : ev('yo', 'transicion', p, 'arriba')),
        },
      };
    case 'op_mejora':
      return {
        pendiente: {
          tipo: 'posicion', titulo: t('¿A dónde pasa él?', `¿A dónde pasa ${ctx.b}?`),
          opciones: DOMINANTES.filter((p) => p !== e.pos),
          siguiente: (p) => ({ pos: p, rol: 'abajo' }),
          eventoAlElegir: (p) => (p === 'espalda'
            ? ev('oponente', 'toma_espalda', e.pos, 'arriba')
            : ev('oponente', 'transicion', p, 'arriba')),
        },
      };

    case 'escape':
      return {
        evento: ev('yo', 'escape', e.pos, 'abajo'),
        pendiente: {
          tipo: 'posicion', titulo: t('¿Dónde recuperas?', `¿Dónde recupera ${ctx.a}?`),
          opciones: [...GUARDIAS_RAPIDAS, 'de_pie'],
          siguiente: (p) => ({ pos: p, rol: p === 'de_pie' ? 'neutral' : 'abajo' }),
        },
      };
    case 'op_escape':
      return {
        evento: ev('oponente', 'escape', e.pos, 'abajo'),
        pendiente: {
          tipo: 'posicion', titulo: t('¿Qué guardia recupera?', `¿Qué guardia recupera ${ctx.b}?`),
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
          titulo: actor === 'yo'
            ? t('¿Qué le hiciste?', `¿Qué hizo ${ctx.a}?`)
            : t('¿Qué te hizo?', `¿Qué hizo ${ctx.b}?`),
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
