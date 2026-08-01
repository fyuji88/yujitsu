/**
 * El ranking del informe de un Open Mat.
 *
 * ------------------------------------------------------------------
 *  POR QUÉ ESTO VIVE AQUÍ Y NO EN SQL
 * ------------------------------------------------------------------
 *  El encargo decía «leyendo `private.metricas_quedada(quedada_id)`». **No se
 *  puede desde el cliente**: esa función vive en `private` y PostgREST solo
 *  publica `public`, que es justo el motivo por el que ese esquema existe.
 *  Comprobado contra producción, no deducido del código: la llamada contesta
 *  `404 PGRST202 · Searched for the function public.metricas_quedada`.
 *
 *  Un envoltorio en `public` sería una línea, pero es una migración, y esta
 *  tanda es de cero migraciones. Así que los números se piden de donde ya
 *  salen calculados —`v_puntos_roll` y `v_logros_sesion`, las dos en `public`
 *  y las dos legibles— y aquí solo se AGRUPA y se ORDENA.
 *
 *  Esa distinción es la que mantiene la regla de la casa: los puntos siguen
 *  derivándose en SQL —`v_puntos_roll` es la misma vista con la que
 *  `cerrar_quedada` arma el ranking congelado, así que los dos números salen
 *  del mismo sitio y no pueden separarse—. Lo que hace React es sumar por
 *  persona, que es presentación.
 *
 * ------------------------------------------------------------------
 *  EL ORDEN ES LEXICOGRÁFICO, NO PONDERADO
 * ------------------------------------------------------------------
 *      sumisiones  >  puntos  >  logros  >  segundos de dominancia
 *
 *  Se ordena por el primero; si empatan, por el segundo; y así. Nada más.
 *
 *  No es una suma con pesos, y no por gusto: los pesos son arbitrarios y se
 *  discuten para siempre, hay que normalizar unidades que no se parecen —los
 *  segundos van en miles y las sumisiones en unidades— y el número que sale no
 *  se puede explicar. El día que alguien pregunte por qué una sumisión vale
 *  doce puntos no hay respuesta buena. Así la explicación cabe en una línea:
 *  primero quién finalizó más; si empatan, quién dominó más.
 *
 *  Con ocho rolls en una tarde casi todo se decide en los dos primeros
 *  escalones. Es correcto, no es un fallo, y crece con los datos.
 */

export interface FilaRanking {
  practicante_id: string;
  nombre: string;
  cinturon: string;
  /** Rolls suyos en este Open Mat. Cero es un dato, no un hueco: ver abajo. */
  rolls: number;
  /** Sumisiones que ÉL completó. De `eventos`, no de `rolls.resultado`. */
  sumisiones: number;
  /** Puntos IBJJF estimados a favor. De `v_puntos_roll`, calculados en SQL. */
  puntos: number;
  /** Logros conseguidos en las sesiones de este Open Mat. De `v_logros_sesion`. */
  logros: number;
  /**
   * EL CUARTO ESCALÓN, QUE TODAVÍA NO EXISTE.
   *
   * El reloj de posesión no está construido, así que esto es siempre `null` y
   * el comparador lo salta. Está escrito y en su sitio para que el día que
   * exista sea rellenar este campo y borrar el `?? 0` de abajo — no rehacer el
   * orden.
   */
  dominancia: number | null;
  /** Si vino pero no le consta ningún roll. Es una señal, no un adorno. */
  sinRolls: boolean;
}

/**
 * El orden. Devuelve una copia; no toca el array que le pasan.
 *
 * `sort` en JavaScript es estable desde ES2019, así que dos personas iguales en
 * los cuatro escalones se quedan como venían — y vienen ordenadas por nombre,
 * que es lo único neutral que hay.
 */
export function ordenarRanking(filas: readonly FilaRanking[]): FilaRanking[] {
  const escalones: ((f: FilaRanking) => number)[] = [
    (f) => f.sumisiones,
    (f) => f.puntos,
    (f) => f.logros,
    // El reloj de posesión, cuando exista. Hoy `dominancia` es siempre null y
    // este escalón nunca desempata nada.
    (f) => f.dominancia ?? 0,
  ];
  return [...filas].sort((a, b) => {
    for (const de of escalones) {
      const d = de(b) - de(a);
      if (d !== 0) return d;
    }
    return 0;
  });
}

/** Lo que hace falta para armar una fila, tal y como sale de cada consulta. */
export interface FuentesInforme {
  /** `sesiones` de este Open Mat: id de la sesión y de quién es. */
  sesiones: { id: string; practicante_id: string }[];
  /** `rolls` de esas sesiones. */
  rolls: { id: string; sesion_id: string; oponente_id: string | null }[];
  /** `eventos` de esos rolls. Solo hacen falta cuatro campos. */
  eventos: {
    roll_id: string; actor: string; tipo: string;
    completado: boolean; segundo_roll: number | null;
  }[];
  /** `v_puntos_roll`, que es de donde SQL saca los puntos. */
  puntos: { roll_id: string; autor_id: string; puntos_autor: number }[];
  /** `v_logros_sesion`. */
  logros: { sesion_id: string; practicante_id: string; veces: number }[];
  /** Quién estaba apuntado, con rolls o sin ellos. */
  inscritos: string[];
  /** El roster, para poner nombre y cinturón. */
  fichas: Record<string, { nombre: string; cinturon: string }>;
}

/**
 * Arma el ranking con TODOS los que estuvieron.
 *
 * QUIÉN SALE: cualquiera con inscripción o con algún roll, aunque vaya a cero
 * en todo. Quien vino y le sometieron cinco veces sale igual — es la
 * diferencia entre una foto de grupo y un podio.
 *
 * Y no es solo cortesía. La cabecera decía «3 asistentes» y la tabla enseñaba
 * una fila, y quien lo leía no sabía si el dato estaba mal o si esa gente no
 * había hecho nada. Esa contradicción llevaba días avisando de que los rolls
 * espejo no se estaban creando, y nadie la leyó como aviso. Con todos en la
 * lista, un cero es una señal que se ve.
 *
 * (El informe CONGELADO enseña menos gente por otro motivo, y es deliberado:
 * `cerrar_quedada` corta el ranking con `having count(*) >= 2`. Esa regla se
 * queda donde está; aquí no aplica porque aquí no se premia, se enseña.)
 */
export function armarRanking(f: FuentesInforme): FilaRanking[] {
  const duenyoDeSesion = new Map(f.sesiones.map((s) => [s.id, s.practicante_id]));
  const duenyoDeRoll = new Map<string, string>();
  for (const r of f.rolls) {
    const p = duenyoDeSesion.get(r.sesion_id);
    if (p) duenyoDeRoll.set(r.id, p);
  }

  const quienes = new Set<string>([...f.inscritos, ...duenyoDeRoll.values()]);

  const cuenta = (id: string) => {
    const susRolls = [...duenyoDeRoll.entries()]
      .filter(([, p]) => p === id).map(([r]) => r);
    const suyos = new Set(susRolls);
    return {
      rolls: susRolls.length,
      // `actor = 'yo'` es quien hizo la acción en SU roll. En el espejo del
      // compañero la misma sumisión aparece como 'oponente', así que contar
      // por 'yo' sobre los rolls de cada uno no cuenta dos veces.
      sumisiones: f.eventos.filter((e) => suyos.has(e.roll_id)
        && e.actor === 'yo' && e.tipo === 'sumision' && e.completado).length,
      puntos: f.puntos.filter((p) => p.autor_id === id && suyos.has(p.roll_id))
        .reduce((t, p) => t + Number(p.puntos_autor ?? 0), 0),
      logros: f.logros.filter((l) => l.practicante_id === id)
        .reduce((t, l) => t + Number(l.veces ?? 0), 0),
    };
  };

  const filas: FilaRanking[] = [...quienes].map((id) => {
    const c = cuenta(id);
    const ficha = f.fichas[id];
    return {
      practicante_id: id,
      nombre: ficha?.nombre ?? 'alguien',
      cinturon: ficha?.cinturon ?? 'blanca',
      ...c,
      dominancia: null,
      sinRolls: c.rolls === 0,
    };
  });

  // Se entra ordenado por nombre para que el desempate final sea estable y no
  // dependa del orden en que Postgres devolvió las filas.
  filas.sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));
  return ordenarRanking(filas);
}

/** Una pareja del cara a cara. */
export interface Pareja { a: string; b: string; veces: number }

/**
 * Quién rodó con quién, y cuántas veces.
 *
 * COMO LISTA, NO COMO MATRIZ. Con seis personas una matriz de 6×6 a 390px no
 * la lee nadie, y el dato es social antes que analítico: «tú y Krilin, tres
 * veces» se entiende de un vistazo.
 *
 * Cada combate son DOS rolls —el original y su espejo—, así que la pareja se
 * normaliza por nombre y se cuenta una sola vez. Sin eso, todas las cifras
 * saldrían dobladas menos las de quien no tiene espejo, que es el peor error
 * posible: el número parecería bueno y estaría mal solo a veces.
 */
export function caraACara(f: FuentesInforme): Pareja[] {
  const duenyoDeSesion = new Map(f.sesiones.map((s) => [s.id, s.practicante_id]));
  const vistos = new Map<string, Pareja>();
  const nombre = (id: string) => f.fichas[id]?.nombre ?? 'alguien';

  for (const r of f.rolls) {
    const a = duenyoDeSesion.get(r.sesion_id);
    const b = r.oponente_id;
    if (!a || !b) continue;
    const [x, y] = [nombre(a), nombre(b)].sort((p, q) => p.localeCompare(q, 'es'));
    const clave = `${x} ${y}`;
    const ya = vistos.get(clave);
    if (ya) ya.veces += 1;
    else vistos.set(clave, { a: x, b: y, veces: 1 });
  }

  // Cada combate se ha contado dos veces si tiene espejo. Se divide, pero se
  // redondea HACIA ARRIBA: un combate sin espejo se ha contado una sola vez y
  // dividiéndolo se quedaría en cero, o sea que desaparecería de la lista justo
  // en el caso en que hace falta verlo.
  for (const p of vistos.values()) p.veces = Math.ceil(p.veces / 2);

  return [...vistos.values()].sort((p, q) => q.veces - p.veces
    || p.a.localeCompare(q.a, 'es'));
}

/**
 * El dato del día: el número más raro de la tarde.
 *
 * Sale de los títulos CONGELADOS, que ya traen su `z` — la distancia a la media
 * del equipo esa tarde. El mayor z de todos es, por construcción, lo más fuera
 * de lo normal que pasó. No se recalcula nada: es un juicio hecho al cerrar, y
 * así debe quedarse.
 */
export function datoDelDia(
  titulos: { titulo: string; quien: string; porque: string; z?: number | null;
             valor?: number | null }[],
): { quien: string; porque: string; valor: number | null } | null {
  const conZ = titulos.filter((t) => typeof t.z === 'number');
  if (!conZ.length) return null;
  const mejor = conZ.reduce((a, b) => ((b.z ?? 0) > (a.z ?? 0) ? b : a));
  return { quien: mejor.quien, porque: mejor.porque, valor: mejor.valor ?? null };
}
