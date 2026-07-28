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
import type { EventoInsert, RollInsert, SesionInsert } from './database.types';

export type TablaRemota = 'sesiones' | 'rolls' | 'eventos';

export interface EnvioPendiente {
  /** id de la fila: el mismo que va a Postgres, para que el reintento sea idempotente */
  id: string;
  tabla: TablaRemota;
  fila: SesionInsert | RollInsert | EventoInsert;
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

/** Escribe local y encola. Devuelve al instante: la red no bloquea la UI. */
export async function encolar(tabla: TablaRemota, fila: SesionInsert | RollInsert | EventoInsert) {
  await local.outbox.put({
    id: fila.id, tabla, fila, creado: Date.now(), intentos: 0,
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
