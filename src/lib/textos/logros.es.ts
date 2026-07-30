/**
 * Los nombres y las descripciones de los logros, en castellano.
 *
 * POR QUE ESTO NO ESTA EN LA BASE. En `logros` va la CLAVE, que es lo estable,
 * y el nombre visible sale de aquí. Cambiar una palabra —o el idioma entero—
 * tiene que ser editar un fichero, no aplicar una migración a producción.
 * También es el primer paso de la internacionalización: cuando haga falta el
 * inglés, se copia este fichero y se cambia el que se importa.
 *
 * Los nombres son chistes, y los chistes no se traducen: la versión en otro
 * idioma tendrá que inventarse los suyos, no traducir estos literalmente.
 */

export interface TextoLogro {
  nombre: string;
  descripcion: string;
}

export const LOGROS_ES: Record<string, TextoLogro> = {
  impasable: { nombre: 'IMPASABLE', descripcion: 'Ningún pase de guardia encajado en el roll' },
  cuello_de_acero: { nombre: 'CUELLO DE ACERO', descripcion: 'Te atacan el cuello tres veces y no cae ninguna' },
  houdini: { nombre: 'HOUDINI', descripcion: 'Tres escapes desde posiciones dominantes' },
  muro: { nombre: 'MURO', descripcion: 'El rival lo intenta tres veces y no entra ninguna' },
  sin_marcar: { nombre: 'FLAWLESS VICTORY', descripcion: 'El rival no consigue ni un punto en todo el roll' },
  de_vuelta: { nombre: 'HIGHLANDER', descripcion: 'Te montan o te toman la espalda, y acabas ganando' },
  guardia_de_hierro: { nombre: 'GUARDIA DE HIERRO', descripcion: 'Tres barridas en un roll' },
  limpio: { nombre: 'LIMPIO', descripcion: 'Finalizas sin haber fallado ni un intento antes' },
  mochilero: { nombre: 'EL MOCHILERO', descripcion: 'Dos espaldas tomadas en un roll' },
  rodillo: { nombre: 'EL RODILLO', descripcion: 'Tres pases de guardia en un roll' },
  cinturon_invisible: { nombre: 'CINTURÓN INVISIBLE', descripcion: 'Finalizas a alguien de cinturón superior' },
  juguete_nuevo: { nombre: 'JUGUETE NUEVO', descripcion: 'Finalizas con una técnica que nunca habías usado' },
  piernas: { nombre: 'PIERNAS', descripcion: 'Finalizas atacando una pierna' },
  primera_vez: { nombre: 'PRIMERA VEZ', descripcion: 'Finalizas desde una posición nueva para ti' },
  relampago: { nombre: 'RELÁMPAGO', descripcion: 'Finalizas en menos de sesenta segundos' },
  la_cadena: { nombre: 'LA CADENA', descripcion: 'Pasas, montas y tomas la espalda en el mismo roll' },
  quince: { nombre: 'QUINCE', descripcion: 'Quince puntos estimados en un solo roll' },
  pulpo: { nombre: 'EL PULPO', descripcion: 'Cinco intentos de sumisión en un roll' },
  ambidiestro: { nombre: 'AMBIDIESTRO', descripcion: 'Finalizas desde arriba y desde abajo el mismo día' },
  artista: { nombre: 'EL ARTISTA', descripcion: 'Tres sumisiones distintas en la misma quedada' },
  sin_gi_sin_problema: { nombre: 'SIN GI, SIN PROBLEMA', descripcion: 'Finalizas en gi y en nogi la misma semana' },
  notario: { nombre: 'EL NOTARIO', descripcion: 'Registras todos los rolls de la quedada, sin dejarte ninguno' },
  semana_completa: { nombre: 'SEMANA COMPLETA', descripcion: 'Registras en tres días distintos de la misma semana' },
  ojo_del_coach: { nombre: 'OJO DEL COACH', descripcion: 'Diez rolls registrados como observador en un mes' },
  donante: { nombre: 'DONANTE', descripcion: 'Encajas tres sumisiones en un roll' },
  el_ancla: { nombre: 'EL ANCLA', descripcion: 'Más de dos minutos en la misma posición sin que pase nada' },
  peaje: { nombre: 'PEAJE', descripcion: 'Te pasan la guardia cuatro veces en un roll' },
};

/** Lo que se enseña cuando falta la traducción: la clave, que siempre existe. */
export function textoLogro(clave: string): TextoLogro {
  return LOGROS_ES[clave] ?? { nombre: clave.toUpperCase(), descripcion: '' };
}

/** Las familias, en el orden en que se pintan en la colección. */
export const FAMILIAS_ES: Record<string, string> = {
  defensa: 'Defensa',
  ataque: 'Ataque',
  estilo: 'Estilo',
  constancia: 'Constancia',
  cachondeo: 'Cachondeo',
};

export const RAREZAS_ES: Record<string, string> = {
  comun: 'común',
  poco_comun: 'poco común',
  raro: 'raro',
};
