/**
 * Las palabras que lee la gente, separadas de los identificadores de la base.
 *
 * POR QUE ESTO EXISTE. Son dos decisiones distintas y cuestan cosas distintas:
 *
 * - Cambiar la palabra de pantalla es **una línea de este fichero**.
 * - Cambiar el identificador de la base cuesta una migración, renombrar las
 *   columnas de las vistas, tocar el cliente y coordinar la cola de salida.
 *
 * Mezclarlas obliga a pagar el segundo precio cada vez que alguien quiere el
 * primero. Por eso en Postgres la tabla se llama `equipos` —en español, como el
 * resto del esquema— y aquí se lee "Team", que es como lo dicen en el gimnasio.
 * Si mañana Felipe prefiere "Squad" o "Equipo", se cambia aquí y no hay
 * migración ninguna.
 *
 * Lo mismo con las quedadas: en la base son `quedadas` y no pueden llamarse
 * "open mat" —`open_mat` ya es uno de los seis valores de `bjj_tipo_sesion`, y
 * dos cosas distintas con el mismo nombre es justo lo que no queremos—, pero en
 * pantalla se llaman "Open Mat" porque es como las llama todo el mundo.
 */
export const TEXTOS = {
  /** El gimnasio o la panda con la que entrenas. En la base: `equipos`. */
  equipo: 'Team',
  equipos: 'Teams',
  /** Cuando va dentro de una frase y no arranca en mayúscula. */
  elEquipo: 'el Team',
  delEquipo: 'del Team',
  tuEquipo: 'Tu Team',

  /** El evento al que se apunta la gente. En la base: `quedadas`. */
  quedada: 'Open Mat',
  quedadas: 'Open Mats',
} as const;
