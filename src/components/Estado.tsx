'use client';

import type { PostgrestError } from '@supabase/supabase-js';

/**
 * Los tres estados de una pantalla que carga datos, y por qué son TRES.
 *
 * Hasta hoy había dos y medio: se pedía, se guardaba `data`, y **el error se
 * tiraba**. Con `data` a null la lista salía vacía, así que un backend caído
 * se pintaba como «todavía no ha pasado nada». Eso no es un detalle de estilo:
 * es la app diciendo una mentira concreta y creíble sobre el equipo.
 *
 * No es hipotético. `feed()` tarda 10,5 s contra un `statement_timeout` de 8 s
 * del rol `authenticated`, así que **falla siempre**, con `57014`, y lo que
 * llevamos viendo todo este tiempo es esa mentira.
 *
 * La regla, entonces: `vacío` sólo se pinta cuando el backend contestó y no
 * había nada. Si no contestó, se pinta `error`. Nunca se adivina.
 */

/** Lo que puede estar haciendo un bloque que carga datos. */
export type Estado = 'cargando' | 'listo' | 'error';

/**
 * El error, en una frase que se pueda leer en el tatami.
 *
 * Se traducen los pocos códigos que significan algo distinto para quien mira.
 * El resto cae en el genérico: inventar un mensaje bonito para un código que no
 * conoces es cómo se acaba diciendo «revisa tu conexión» cuando el fallo es del
 * servidor.
 */
export function explicarFallo(e: PostgrestError | Error | null): string {
  if (!e) return 'No se pudo cargar.';
  const codigo = (e as PostgrestError).code ?? '';

  // 57014 · lo canceló Postgres por tardar demasiado. Es EL caso de esta app.
  if (codigo === '57014') {
    return 'La consulta tardó más de lo que el servidor permite y se canceló. '
      + 'No es tu conexión, y no significa que no haya datos.';
  }
  // 42501 · la RLS dijo que no. Casi siempre es sesión caducada o equipo.
  if (codigo === '42501') {
    return 'No tienes permiso para ver esto. Si acabas de entrar, prueba a '
      + 'salir y volver a entrar.';
  }
  // PGRST301 · el JWT caducó.
  if (codigo === 'PGRST301' || codigo === 'PGRST303') {
    return 'Tu sesión ha caducado. Sal y vuelve a entrar.';
  }
  // Sin código y con mensaje de red: el navegador no llegó a hablar con nadie.
  if (!codigo && /fetch|network|failed to fetch/i.test(e.message ?? '')) {
    return 'No hay conexión con el servidor. Si estás en el gimnasio, puede ser '
      + 'la cobertura.';
  }
  return e.message || 'No se pudo cargar.';
}

/**
 * El bloque de error.
 *
 * LLEVA BOTÓN DE REINTENTAR SIEMPRE. Un error sin salida obliga a recargar la
 * página entera, y recargar en mitad de un entreno es justo lo que no se puede
 * pedir. Y lleva el código pegado, en pequeño: cuando Felipe mande una captura
 * desde el tatami, ese código es la diferencia entre saber qué pasó y adivinar.
 */
export function PanelError({
  error, onReintentar, que, testid,
}: {
  error: PostgrestError | Error | null;
  onReintentar?: () => void;
  /** Qué se estaba cargando, en una palabra: «el feed», «los logros». */
  que: string;
  testid?: string;
}) {
  const codigo = (error as PostgrestError | null)?.code;
  return (
    <div className="tarjeta" data-testid={testid ?? 'error-de-carga'}
      data-codigo={codigo ?? ''}
      style={{ borderColor: 'var(--error)', padding: 12, marginTop: 8 }}>
      <p style={{ color: 'var(--error)', fontWeight: 600, margin: 0 }}>
        No se pudo cargar {que}.
      </p>
      <p className="hint" style={{ marginTop: 4 }}>{explicarFallo(error)}</p>
      {onReintentar && (
        <button className="ghost" data-testid="reintentar"
          style={{ marginTop: 10 }} onClick={onReintentar}>
          Reintentar
        </button>
      )}
      {codigo && (
        <p className="hint" style={{ marginTop: 8, opacity: 0.7 }}>
          Código {codigo} — díselo a quien lo esté arreglando.
        </p>
      )}
    </div>
  );
}

/** El «cargando», para que los tres estados se escriban igual en todas partes. */
export function Cargando({ que, testid }: { que: string; testid?: string }) {
  return (
    <p className="empty" data-testid={testid ?? 'cargando'}>Cargando {que}…</p>
  );
}
