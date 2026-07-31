'use client';

/**
 * Capa local-first.
 *
 * Nada escribe directamente contra Supabase. Todo se guarda primero en
 * IndexedDB y entra en `outbox`; un worker vacía la cola cuando hay red.
 * Así se puede loguear en un gimnasio sin cobertura y la interfaz nunca
 * se queda esperando a la red.
 *
 * Los ids se generan aquí (UUID v4). Eso es lo que hace que reintentar sea
 * seguro: si no sabemos si la fila llegó, la reenviamos y Postgres la
 * rechaza por clave primaria en vez de duplicarla.
 */
import Dexie, { type Table } from 'dexie';
import { supabase } from './supabase';
import type {
  ArgsRollObservado, EventoInsert, RollInsert, SesionInsert,
} from './database.types';

export type TablaRemota = 'sesiones' | 'rolls' | 'eventos';

/**
 * Dónde va cada cosa al vaciar la cola.
 *
 * Las tres tablas se suben con `upsert`. `roll_observado` no es una tabla: es
 * una llamada a la RPC `registrar_roll_observado()`, porque la RLS no deja
 * escribir filas de otros y hace falta pasar por una función SECURITY DEFINER.
 * Comparte cola con el resto para que valga lo mismo de siempre: se registra
 * sin cobertura y sale solo cuando hay red.
 */
export type DestinoCola = TablaRemota | 'roll_observado';

export interface EnvioPendiente {
  /**
   * Clave de idempotencia. Para las tablas es el id de la fila; para el roll
   * observado, el `par_id`. En los dos casos lo genera el cliente, que
   * es lo que hace que reintentar tras perder cobertura no duplique nada.
   */
  id: string;
  tabla: DestinoCola;
  fila: SesionInsert | RollInsert | EventoInsert | ArgsRollObservado;
  creado: number;
  intentos: number;
  ultimoError?: string;
  /**
   * `atencion` es un 4xx: el servidor ha dicho que ese dato no entra, y
   * reintentarlo no lo va a arreglar. Deja de reintentarse SOLO, pero **no se
   * borra nunca**: se enseña y lo decide una persona. Descartar en silencio
   * algo que alguien registró es el único fallo que este producto no se puede
   * permitir.
   */
  estado?: 'pendiente' | 'atencion';
}

class BaseLocal extends Dexie {
  outbox!: Table<EnvioPendiente, string>;

  constructor() {
    super('bjj-tracker');
    this.version(1).stores({
      outbox: 'id, tabla, creado',
    });
  }
}

export const local = new BaseLocal();

export const nuevoId = () => crypto.randomUUID();

/**
 * Lo que se guarda en `localStorage`.
 *
 * `SESION_ABIERTA` es **de un usuario concreto**: guarda el id de la sesión de
 * entreno de hoy. `TECNICAS` es solo la caché del diccionario, que es igual
 * para todo el mundo y no hay por qué tirar al cambiar de usuario.
 */
export const CLAVE_SESION = 'bjj.sesion-abierta';
export const CLAVE_TECNICAS = 'bjj.tecnicas';

/**
 * Deja el dispositivo listo para otra persona.
 *
 * Esto no es limpieza cosmética: sin ello, quien entre después hereda cosas del
 * anterior y se encuentra errores en vez de una app vacía.
 *
 *  - La **cola** puede tener rolls sin subir. Se enviarían con la sesión del
 *    nuevo usuario: la RLS rechazaría sesiones, rolls y eventos ajenos, y un
 *    roll observado quedaría atribuido a quien no es, porque `registrado_por`
 *    sale de `private.practicante_actual()`.
 *  - La **sesión de entreno abierta** pertenece al usuario anterior. Si se
 *    queda, el siguiente empieza a colgar rolls de una sesión que no es suya,
 *    la RLS los rechaza y la cola se atasca sin decir por qué.
 *
 * Devuelve cuántos envíos pendientes se descartaron, para poder avisar.
 */
export async function olvidarDatosDelUsuario(): Promise<number> {
  const pendientes = await local.outbox.count();
  await local.outbox.clear();
  localStorage.removeItem(CLAVE_SESION);
  return pendientes;
}

/** Escribe local y encola. Devuelve al instante: la red no bloquea la UI. */
export async function encolar(tabla: TablaRemota, fila: SesionInsert | RollInsert | EventoInsert) {
  await local.outbox.put({
    id: fila.id, tabla, fila, creado: Date.now(), intentos: 0,
  });
}

/**
 * Encola un roll observado entero: sesión, roll, eventos y el espejo al
 * compañero, todo en una llamada.
 *
 * Va aparte de `encolar()` porque no es una fila sino una RPC, y porque la
 * unidad de reintento es distinta: aquí el roll entero se manda o no se manda,
 * no hay medio roll. La clave es `p_par`, así que reenviarlo es inofensivo —
 * la función lo reconoce y devuelve lo que ya había.
 */
export async function encolarRollObservado(args: ArgsRollObservado) {
  await local.outbox.put({
    id: args.p_par, tabla: 'roll_observado', fila: args, creado: Date.now(), intentos: 0,
  });
}

/** Si borras un evento antes de sincronizar, se va de la cola sin llegar nunca. */
export async function desencolar(id: string) {
  await local.outbox.delete(id);
}

/**
 * Lo que toca enviar: todo menos lo que necesita mano.
 *
 * OJO CON FILTRAR POR TIEMPO AQUI. La primera version daba a cada elemento su
 * propia espera, y eso ROMPE EL ORDEN POR TABLAS: si una sesion estaba
 * cumpliendo su espera y su roll ya tocaba, el roll salia solo y Postgres lo
 * rechazaba por clave foranea. Se vio en `pruebas/cola.js`: llegaba la sesion y
 * el roll, y los eventos se quedaban fuera.
 *
 * La espera creciente es GLOBAL y vive en `sync.ts`, que es donde tiene
 * sentido: un fallo de red no es de un elemento, es de todos.
 */
export async function pendientes() {
  return (await local.outbox.orderBy('creado').toArray())
    .filter((p) => p.estado !== 'atencion');
}

/** Todo lo que no ha llegado, incluido lo que espera y lo que falló. */
export async function todoLoPendiente() {
  return local.outbox.orderBy('creado').toArray();
}

export async function contarPendientes() {
  return local.outbox.count();
}

/**
 * Descartar a mano un elemento que el servidor rechaza.
 *
 * Es la única forma de que algo salga de la cola sin haber llegado, y por eso
 * la decide una persona desde la píldora. Nunca automático.
 */
export async function descartar(id: string) {
  await local.outbox.delete(id);
}

/** Vuelve a poner en la cola algo que estaba en "necesita atención". */
export async function reintentarYa(id: string) {
  await local.outbox.update(id, { estado: 'pendiente', intentos: 0 });
}

/**
 * Precisar una técnica: bajar de la mecánica madre a una variante.
 *
 * DOS CAMINOS, Y NO ES UN CAPRICHO. Al cerrar el roll los eventos todavía están
 * en la cola: no existen en el servidor, así que `precisar_tecnica()` no puede
 * tocarlos —le pasarías un id que allí no existe—. Pero el id lo genera el
 * cliente, así que el evento que suba después ya lleva la técnica buena.
 *
 *   - si el evento sigue en la cola  → se corrige ahí y sube ya preciso;
 *   - si ya subió                    → RPC, que es la única vía: no hay RLS por
 *                                      columna, así que abrir `update` sobre
 *                                      eventos dejaría reescribir el marcador.
 *
 * Devuelve por dónde fue, que es lo que la pantalla necesita para saber si
 * enseñar "precisado por ti" o esperar a la siguiente sincronización.
 */
export async function precisar(eventoId: string, tecnicaId: string): Promise<'cola' | 'rpc'> {
  const pendiente = await local.outbox.get(eventoId);
  if (pendiente && pendiente.tabla === 'eventos') {
    const fila = { ...(pendiente.fila as EventoInsert), tecnica_id: tecnicaId };
    await local.outbox.put({ ...pendiente, fila });
    return 'cola';
  }
  const { error } = await supabase().rpc('precisar_tecnica', {
    p_evento_id: eventoId, p_tecnica_id: tecnicaId,
  });
  if (error) throw new Error(error.message);
  return 'rpc';
}
