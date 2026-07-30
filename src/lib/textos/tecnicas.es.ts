/**
 * Los nombres visibles de las variantes.
 *
 * Van aquí y no incrustados en la pantalla por la misma razón que los de los
 * logros: cambiar cómo se llama una técnica en el gimnasio es una línea de este
 * fichero, y el identificador de la base —el `slug`— no se toca nunca. Son dos
 * decisiones distintas y cuestan cosas distintas; está en CLAUDE.md.
 *
 * Solo están las variantes. El nombre de las 64 mecánicas viene de
 * `tecnicas.nombre`, que es lo que se ve al registrar en vivo.
 */
export const VARIANTES: Record<string, { nombre: string; pista: string }> = {
  tarikoplata: {
    nombre: 'Tarikoplata',
    pista: 'la kimura con la pierna',
  },
  j_lock: {
    nombre: 'J-Lock',
    pista: 'la americana con la pierna',
  },
  heel_hook_interno: {
    nombre: 'Heel hook interno',
    pista: 'inside',
  },
  heel_hook_externo: {
    nombre: 'Heel hook externo',
    pista: 'outside',
  },
  guillotina_brazo_dentro: {
    nombre: 'Guillotina con brazo dentro',
    pista: 'arm-in',
  },
  guillotina_codo_alto: {
    nombre: 'Guillotina de codo alto',
    pista: 'marcelotine',
  },
  triangulo_invertido: {
    nombre: 'Triángulo invertido',
    pista: 'reverse',
  },
  armbar_triangulo: {
    nombre: 'Armbar desde triángulo',
    pista: '',
  },
};

/** Lo que se lee en el chip cuando la técnica se queda como estaba. */
export const SIGUE_SIENDO = (madre: string) => `Sigue siendo ${madre}`;
