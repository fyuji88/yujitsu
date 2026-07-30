'use client';

import { useEffect, useState } from 'react';

/**
 * Mantiene la pantalla encendida mientras dure el roll.
 *
 * EL FALLO QUE ARREGLA es el número uno del registro en la práctica: estás
 * logueando, pasan cuarenta segundos sin que toques nada porque el roll está
 * en el suelo, el móvil se apaga, y cuando lo desbloqueas has perdido la mitad
 * de los eventos y el hilo de dónde ibas.
 *
 * SOLO MIENTRAS SE RODEA, y por eso recibe `activo` en vez de pedirlo al abrir
 * la app. Un `wakeLock` retenido toda la sesión de entreno se come la batería
 * de alguien que ha venido a entrenar dos horas, y la batería en un gimnasio
 * no se recarga.
 *
 * HAY QUE VOLVER A PEDIRLO. El navegador SUELTA el bloqueo en cuanto la
 * pestaña se oculta —una llamada entrante, mirar el WhatsApp— y no lo devuelve
 * solo al volver. Sin el `visibilitychange` esto funcionaría hasta la primera
 * distracción, que es justo cuando hace falta.
 */

/** El tipo mínimo que hace falta; no todos los `lib.dom` lo traen todavía. */
interface Cierre { released: boolean; release(): Promise<void> }
interface ConWakeLock {
  wakeLock?: { request(tipo: 'screen'): Promise<Cierre> };
}

export function usarPantallaEncendida(activo: boolean) {
  /**
   * Si el navegador no sabe. iOS lo soporta desde 16.4; antes de eso, no hay
   * nada que hacer desde la web. Se devuelve para que la pantalla pueda
   * decirlo si algún día interesa, pero no se avisa en cada roll: un aviso que
   * sale siempre y que el usuario no puede resolver es ruido.
   */
  const [soportado, setSoportado] = useState(true);

  useEffect(() => {
    const nav = navigator as Navigator & ConWakeLock;
    if (!nav.wakeLock) { setSoportado(false); return; }
    if (!activo) return;

    let cierre: Cierre | null = null;
    let vivo = true;

    const soltar = () => {
      const c = cierre;
      cierre = null;
      if (c && !c.released) void c.release();
    };

    const pedir = async () => {
      // Pedirlo con la pestaña oculta siempre falla, y ensuciaría la consola
      // con un error por cada cambio de pestaña.
      if (document.visibilityState !== 'visible') return;
      // Soltar el anterior ANTES de pedir otro. La especificación dice que el
      // navegador lo suelta solo al ocultarse la pestaña, pero si se confía en
      // eso y algún navegador no lo hace, el bloqueo viejo se queda retenido
      // para siempre sin que nadie tenga ya la referencia para soltarlo: la
      // pantalla no se apaga en todo el entreno y la batería se va. Esperar a
      // que otro limpie por ti es justo el fallo que no da ningún síntoma
      // hasta que el móvil está al 4 %.
      soltar();
      try {
        const c = await nav.wakeLock!.request('screen');
        if (!vivo) { void c.release(); return; }
        cierre = c;
      } catch {
        // Puede fallar por batería baja o por política del navegador. No es
        // motivo para romper el logging: se sigue sin bloqueo.
      }
    };

    void pedir();
    document.addEventListener('visibilitychange', pedir);

    return () => {
      vivo = false;
      document.removeEventListener('visibilitychange', pedir);
      soltar();
    };
  }, [activo]);

  return soportado;
}
