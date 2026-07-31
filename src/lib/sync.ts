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
  /** Lo que aun no ha llegado y se sigue intentando. */
  enCola: number;
  enviando: boolean;
  error: string | null;
  /** Lo que el servidor rechazo y necesita que alguien decida. */
  conError: number;
}

type Escucha = (e: EstadoSync) => void;
const escuchas = new Set<Escucha>();
let estado: EstadoSync = { enCola: 0, enviando: false, error: null, conError: 0 };

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

/**
 * Es un fallo que reintentar NO va a arreglar?
 *
 * Un 5xx o una desconexion se reintentan para siempre: la red vuelve. Un 4xx
 * -una violacion de RLS, una clave foranea que no existe, una columna que el
 * esquema no acepta- no se arregla insistiendo, y dejarlo dando vueltas
 * bloquea todo lo que va detras y no avisa a nadie.
 *
 * Se es CONSERVADOR a proposito: solo se da por permanente lo que se reconoce.
 * Ante la duda se reintenta, porque el coste de reintentar de mas es bateria y
 * el de reintentar de menos es un roll perdido.
 */
function esFalloDeDatos(e: { code?: string; message?: string }): boolean {
  const c = e.code ?? '';
  // PostgREST rechaza la peticion: el esquema no la acepta tal cual.
  if (c.startsWith('PGRST')) return true;
  // SQLSTATE: 22 dato invalido - 23 integridad - 42 sintaxis o permisos (RLS).
  return /^(22|23|42)/.test(c);
}

/**
 * 1s, 2s, 5s, 15s, 60s y luego cada cinco minutos.
 *
 * LA ESPERA ES GLOBAL, no por elemento. Un fallo de red no le pasa a una fila,
 * le pasa a la conexion: darle su propio reloj a cada elemento hacia que unos
 * estuvieran listos y otros no, y con eso se rompia el orden `sesiones -> rolls
 * -> eventos`. Un roll sin su sesion lo rechaza la clave foranea, y ese roll se
 * quedaba fuera para siempre. Lo cazo `pruebas/cola.js`.
 */
const ESPERAS = [1_000, 2_000, 5_000, 15_000, 60_000];
let fallosSeguidos = 0;
let esperarHasta = 0;

function reprogramar() {
  const espera = fallosSeguidos >= ESPERAS.length
    ? 300_000
    : ESPERAS[fallosSeguidos];
  fallosSeguidos += 1;
  esperarHasta = Date.now() + espera;
}

/**
 * Apunta el resultado de un intento fallido en el propio elemento.
 *
 * NUNCA borra. Un 4xx pasa a "necesita atencion" y deja de reintentarse solo;
 * un fallo de red se reprograma con la espera que toque. Las dos cosas se ven
 * en la pildora, que es lo que convierte "se perdio" en "hay que mirar esto".
 */
async function marcar(p: EnvioPendiente, error: { code?: string; message: string }) {
  if (!(await local.outbox.get(p.id))) return;
  const datos = esFalloDeDatos(error);
  await local.outbox.update(p.id, {
    intentos: p.intentos + 1,
    ultimoError: error.message,
    estado: datos ? 'atencion' : 'pendiente',
  });
}

async function enviarFilas(
  tabla: TablaRemota, lote: EnvioPendiente[],
): Promise<string | null> {
  const { error } = await supabase()
    .from(tabla)
    .upsert(lote.map((p) => alVocabularioDeAhora(tabla, p.fila)), { onConflict: 'id' });

  if (!error) {
    await local.outbox.bulkDelete(lote.map((p) => p.id));
    return null;
  }

  // UN 4xx EN UN LOTE NO DICE QUIEN LO CAUSO, y tumbar el lote entero por una
  // fila mala castiga a las buenas: se quedarian atras para siempre detras de
  // algo que nunca va a entrar. Asi que se reenvia de una en una para aislar
  // al culpable. Solo en este caso: es caro y no hace falta si es la red.
  if (esFalloDeDatos(error) && lote.length > 1) {
    for (const p of lote) {
      const r = await supabase()
        .from(tabla)
        .upsert([alVocabularioDeAhora(tabla, p.fila)], { onConflict: 'id' });
      if (r.error) await marcar(p, r.error);
      else await local.outbox.delete(p.id);
    }
    return null;   // ya se ha decidido elemento a elemento
  }

  for (const p of lote) await marcar(p, error);
  return esFalloDeDatos(error) ? null : error.message;
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
    if (error) {
      await marcar(p, error);
      // Si es de datos se sigue con los demas: son rolls independientes y no
      // tiene sentido que uno malo bloquee a los otros. Si es de red, no hay
      // red para nadie: se para.
      if (!esFalloDeDatos(error)) return error.message;
      continue;
    }
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

export async function vaciarCola(forzar = false): Promise<void> {
  if (enMarcha) return;
  // Retenido o sin red, se sigue emitiendo la cuenta: si no, la píldora diría
  // "sincronizado" con cosas esperando, que es justo lo que no puede pasar.
  const sinRed = typeof navigator !== 'undefined' && !navigator.onLine;
  // La espera creciente tras un fallo de red. `forzar` la salta: si el usuario
  // le da a "reintentar ahora" es que cree que la causa ya no esta, y hacerle
  // esperar un minuto por un contador interno seria absurdo.
  const esperando = !forzar && Date.now() < esperarHasta;
  if (retenido || sinRed || esperando) {
    await emitirCuenta(estado.error);
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

      // Un fallo de RED corta aqui: si no hay red no la hay para las tablas de
      // despues, y seguir solo suma intentos. Los de datos ya se han marcado
      // uno a uno dentro de `enviarFilas`, y esos no cortan nada.
      if (fallo) {
        reprogramar();
        await emitirCuenta(fallo);
        return;
      }
    }

    // Todo lo que tocaba ha salido: la conexion va bien, se reinicia la espera.
    fallosSeguidos = 0;
    esperarHasta = 0;
    await emitirCuenta(null);
  } finally {
    enMarcha = false;
  }
}

/** La cuenta de verdad: lo que espera y lo que necesita mano, por separado. */
async function emitirCuenta(error: string | null) {
  const todo = await local.outbox.toArray();
  const conError = todo.filter((p) => p.estado === 'atencion').length;
  emitir({ enviando: false, error, conError, enCola: todo.length - conError });
}

let arrancado = false;

/** Arranca el vaciado: al cargar, al recuperar red y al volver a la pestaña. */
export function arrancarSync() {
  if (arrancado || typeof window === 'undefined') return;
  arrancado = true;

  const intentar = () => { void vaciarCola(); };
  // Al recuperar la conexion no se espera: la causa del fallo acaba de
  // desaparecer, y hacer esperar cinco minutos a alguien que ya tiene red es
  // justo lo que hace que la gente crea que la app ha perdido sus datos.
  window.addEventListener('online', () => { fallosSeguidos = 0; esperarHasta = 0; intentar(); });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') intentar();
  });
  // Cada 5 s se MIRA, pero cada elemento tiene su propio `proximoIntento`, asi
  // que mirar seguido no significa reintentar seguido: el que no toca, no se
  // toca. iOS no tiene Background Sync, asi que la cola solo avanza con la app
  // abierta y por eso se mira a menudo.
  setInterval(intentar, 5_000);
  intentar();

  // AVISAR ANTES DE CERRAR, como cualquier editor con cambios sin guardar. Es
  // barato y evita el peor caso: cerrar la pestana con un roll dentro.
  window.addEventListener('beforeunload', (e) => {
    if (estado.enCola + estado.conError > 0) {
      e.preventDefault();
      e.returnValue = '';
    }
  });
}
