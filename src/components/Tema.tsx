'use client';

import { useCallback, useEffect, useSyncExternalStore } from 'react';
import { CLAVE_TEMA, aplicarTema, guardarTema, resolverTema, type Tema } from '@/lib/tema';

/**
 * El tema actual, compartido por toda la app.
 *
 * Va con `useSyncExternalStore` sobre un valor de módulo y no con `useState`
 * dentro del hook. La primera versión usaba `useState` y parecía funcionar: el
 * botón de la cabecera cambiaba el atributo `data-tema` y toda la interfaz se
 * repintaba, porque el CSS cuelga de ese atributo. Pero cada componente que
 * llamaba al hook tenía **su propio estado**, así que el que de verdad lee el
 * tema desde React —el heatmap, que invierte la rampa— seguía creyendo que
 * estaba en claro. El resultado era un heatmap con la rampa al revés en modo
 * oscuro: los valores bajos, los que más brillaban.
 *
 * Con un store no hay dos verdades: el CSS y React leen lo mismo.
 */

let actual: Tema | null = null;      // null = todavía sin resolver (servidor)
const oyentes = new Set<() => void>();

const leer = (): Tema => actual ?? 'claro';
const enElServidor = (): Tema => 'claro';
const notificar = () => oyentes.forEach((f) => f());

function suscribir(f: () => void) {
  oyentes.add(f);
  return () => { oyentes.delete(f); };
}

export function useTema(): [Tema, (t: Tema) => void] {
  const tema = useSyncExternalStore(suscribir, leer, enElServidor);

  useEffect(() => {
    // La preferencia real solo se puede leer en el cliente. Empezar en
    // 'claro' y corregir aquí es lo que evita el error de hidratación; en
    // pantalla no se ve el salto porque el atributo ya lo puso el script del
    // `<head>` antes de pintar.
    if (actual === null) { actual = resolverTema(); notificar(); }

    // Si se cambia en otra pestaña, esta se entera. No se escucha
    // `prefers-color-scheme`: el sistema no decide el tema de esta app.
    const alAlmacen = (e: StorageEvent) => {
      if (e.key !== CLAVE_TEMA) return;
      actual = resolverTema();
      aplicarTema(actual);
      notificar();
    };
    addEventListener('storage', alAlmacen);
    return () => removeEventListener('storage', alAlmacen);
  }, []);

  const cambiar = useCallback((t: Tema) => {
    actual = t;
    guardarTema(t);
    notificar();
  }, []);

  return [tema, cambiar];
}

/** El interruptor. Va en la cabecera, junto a la píldora de sincronización. */
export function BotonTema() {
  const [tema, setTema] = useTema();
  const otro: Tema = tema === 'claro' ? 'oscuro' : 'claro';
  return (
    <button className="tema" data-testid="tema" data-tema-actual={tema}
      aria-label={`Cambiar al tema ${otro}`} title={`Cambiar al tema ${otro}`}
      onClick={() => setTema(otro)}>
      {tema === 'claro' ? '🌙' : '☀'}
    </button>
  );
}
