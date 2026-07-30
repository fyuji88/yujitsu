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

export async function pendientes() {
  return local.outbox.orderBy('creado').toArray();
}

export async function contarPendientes() {
  return local.outbox.count();
}
