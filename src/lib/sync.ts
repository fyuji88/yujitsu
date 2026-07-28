'use client';

/**
 * Vaciado de la cola.
 *
 * Orden importante: las sesiones antes que los rolls, y los rolls antes que
 * los eventos. Si un evento llega antes que su roll, Postgres lo rechaza por
 * clave foránea — y como el envío es en orden de creación, eso se respeta solo,
 * pero lo hacemos explícito por tabla para no depender de la suerte.
 */
import { local, pendientes, type EnvioPendiente, type TablaRemota } from './db';
import { supabase } from './supabase';

const ORDEN: TablaRemota[] = ['sesiones', 'rolls', 'eventos'];

export interface EstadoSync {
  enCola: number;
  enviando: boolean;
  error: string | null;
}

type Escucha = (e: EstadoSync) => void;
const escuchas = new Set<Escucha>();
let estado: EstadoSync = { enCola: 0, enviando: false, error: null };

function emitir(parcial: Partial<EstadoSync>) {
  estado = { ...estado, ...parcial };
  escuchas.forEach((f) => f(estado));
}

export function observarSync(f: Escucha) {
  escuchas.add(f);
  f(estado);
  return () => escuchas.delete(f);
}

let enMarcha = false;

export async function vaciarCola(): Promise<void> {
  if (enMarcha) return;
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    emitir({ enCola: await local.outbox.count(), enviando: false });
    return;
  }
  enMarcha = true;
  emitir({ enviando: true, error: null });

  try {
    const cola = await pendientes();
    const porTabla = new Map<TablaRemota, EnvioPendiente[]>();
    for (const p of cola) {
      const l = porTabla.get(p.tabla) ?? [];
      l.push(p);
      porTabla.set(p.tabla, l);
    }

    for (const tabla of ORDEN) {
      const lote = porTabla.get(tabla);
      if (!lote?.length) continue;

      // upsert en vez de insert: reenviar una fila ya enviada no es un error,
      // es exactamente lo que queremos que pase tras perder la conexión.
      const { error } = await supabase()
        .from(tabla)
        .upsert(lote.map((p) => p.fila), { onConflict: 'id' });

      if (error) {
        await local.transaction('rw', local.outbox, async () => {
          for (const p of lote) {
            await local.outbox.update(p.id, {
              intentos: p.intentos + 1, ultimoError: error.message,
            });
          }
        });
        emitir({ error: error.message, enviando: false, enCola: await local.outbox.count() });
        return;
      }

      await local.outbox.bulkDelete(lote.map((p) => p.id));
    }

    emitir({ enviando: false, error: null, enCola: await local.outbox.count() });
  } finally {
    enMarcha = false;
  }
}

let arrancado = false;

/** Arranca el vaciado: al cargar, al recuperar red y al volver a la pestaña. */
export function arrancarSync() {
  if (arrancado || typeof window === 'undefined') return;
  arrancado = true;

  const intentar = () => { void vaciarCola(); };
  window.addEventListener('online', intentar);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') intentar();
  });
  // iOS no tiene Background Sync: la cola solo avanza con la app abierta.
  setInterval(intentar, 20_000);
  intentar();
}
