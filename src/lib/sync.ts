'use client';

/**
 * Vaciado de la cola.
 *
 * Orden importante: las sesiones antes que los rolls, y los rolls antes que
 * los eventos. Si un evento llega antes que su roll, Postgres lo rechaza por
 * clave foránea — y como el envío es en orden de creación, eso se respeta solo,
 * pero lo hacemos explícito por tabla para no depender de la suerte.
 */
import {
  local, pendientes, type DestinoCola, type EnvioPendiente, type TablaRemota,
} from './db';
import { supabase } from './supabase';
import type { ArgsRollObservado } from './database.types';

// Los rolls observados van al final: no dependen de nada de lo anterior (la
// RPC se crea su propia sesión), y así un fallo suyo no bloquea lo tuyo.
const ORDEN: DestinoCola[] = ['sesiones', 'rolls', 'eventos', 'roll_observado'];

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

/**
 * Las tres tablas de siempre, en lote.
 *
 * upsert en vez de insert: reenviar una fila ya enviada no es un error, es
 * exactamente lo que queremos que pase tras perder la conexión.
 */
/**
 * Traduce una fila encolada ANTES de bjj_27 al vocabulario de ahora.
 *
 * POR QUE HACE FALTA, y es la misma lección que el puente de `p_grupo`: lo que
 * hay en IndexedDB se serializó con los nombres de columna del día en que se
 * encoló. `bjj_27` renombró `sesiones.tipo` → `formato` y `rolls.orden` →
 * `orden_en_sesion`, así que una sesión o un roll que llevara esperando desde
 * antes llega con nombres que ya no existen: PostgREST contesta 4xx, `sync.ts`
 * no reintenta los 4xx, y el roll se pierde.
 *
 * Esto pasó de verdad — el cliente estuvo escribiendo `tipo` y `orden` contra
 * el esquema renombrado, y ni el typecheck ni los recorridos podían verlo
 * porque los tipos son un subconjunto escrito a mano y el stub CAPTURA las
 * escrituras en vez de aplicarlas. Se destapó replicando contra Postgres lo que
 * el cliente escribe de verdad.
 *
 * Se puede quitar cuando nadie tenga cola pendiente, igual que el puente.
 */
function alVocabularioDeAhora(tabla: TablaRemota, fila: unknown): unknown {
  const f = { ...(fila as Record<string, unknown>) };
  if (tabla === 'sesiones' && 'tipo' in f) {
    f.formato = f.tipo;
    delete f.tipo;
  }
  if (tabla === 'rolls' && 'orden' in f) {
    f.orden_en_sesion = f.orden;
    delete f.orden;
  }
  return f;
}

async function enviarFilas(
  tabla: TablaRemota, lote: EnvioPendiente[],
): Promise<string | null> {
  const { error } = await supabase()
    .from(tabla)
    .upsert(lote.map((p) => alVocabularioDeAhora(tabla, p.fila)), { onConflict: 'id' });
  if (error) return error.message;

  await local.outbox.bulkDelete(lote.map((p) => p.id));
  return null;
}

/**
 * Los rolls observados, de uno en uno: cada uno es una llamada a la RPC, no
 * una fila, y escribe sesión + roll + eventos + espejo en una transacción.
 *
 * Se van borrando de la cola según entran, para que un fallo a la mitad no
 * arrastre a los que ya pasaron. Reenviarlos tampoco haría daño: `p_par` es
 * la clave de idempotencia y la función reconoce el reintento.
 */
async function enviarObservados(lote: EnvioPendiente[]): Promise<string | null> {
  for (const p of lote) {
    const { error } = await supabase()
      .rpc('registrar_roll_observado', p.fila as ArgsRollObservado);
    if (error) return error.message;
    await local.outbox.delete(p.id);
  }
  return null;
}

let enMarcha = false;
let retenido = false;

/**
 * Retiene el vaciado sin vaciar lo que ya hay encolado.
 *
 * Lo usa el resumen del roll observado, donde todavía se puede corregir la
 * duración: si la cola sale antes, la corrección no llega — la RPC reconoce el
 * `par_id` y devuelve el roll que ya existe sin tocarlo. Un campo
 * editable que en silencio no hace nada es peor que no tenerlo.
 *
 * El roll ya está a salvo en IndexedDB mientras tanto; esto solo retrasa la red.
 */
export function retenerCola(v: boolean) {
  retenido = v;
  if (!v) void vaciarCola();
}

export async function vaciarCola(): Promise<void> {
  if (enMarcha) return;
  // Retenido o sin red, se sigue emitiendo la cuenta: si no, la píldora diría
  // "sincronizado" con cosas esperando, que es justo lo que no puede pasar.
  const sinRed = typeof navigator !== 'undefined' && !navigator.onLine;
  if (retenido || sinRed) {
    emitir({ enCola: await local.outbox.count(), enviando: false });
    return;
  }
  enMarcha = true;
  emitir({ enviando: true, error: null });

  try {
    const cola = await pendientes();
    const porTabla = new Map<DestinoCola, EnvioPendiente[]>();
    for (const p of cola) {
      const l = porTabla.get(p.tabla) ?? [];
      l.push(p);
      porTabla.set(p.tabla, l);
    }

    for (const destino of ORDEN) {
      const lote = porTabla.get(destino);
      if (!lote?.length) continue;

      const fallo = destino === 'roll_observado'
        ? await enviarObservados(lote)
        : await enviarFilas(destino, lote);

      if (fallo) {
        await local.transaction('rw', local.outbox, async () => {
          for (const p of lote) {
            if (await local.outbox.get(p.id)) {
              await local.outbox.update(p.id, {
                intentos: p.intentos + 1, ultimoError: fallo,
              });
            }
          }
        });
        emitir({ error: fallo, enviando: false, enCola: await local.outbox.count() });
        return;
      }
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
