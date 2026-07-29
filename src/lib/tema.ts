/**
 * El tema: claro u oscuro, y el acento de marca.
 *
 * Sin `'use client'` a propósito: `layout.tsx` es un componente de servidor y
 * necesita `SCRIPT_TEMA`. Un módulo marcado como cliente no se puede importar
 * desde el servidor para sacarle una constante. Aquí no hay JSX ni hooks, así
 * que no hace falta la marca; el hook vive en `src/components/Tema.tsx`.
 *
 * ORDEN DE RESOLUCIÓN: preferencia guardada → claro. **El sistema no decide.**
 *
 * El claro es el defecto de la app, no el oscuro: es la identidad de Gullo
 * —hueso con el verde encima— y es el mismo tema de los informes y de las
 * tarjetas que se comparten, así que lo que se ve dentro y lo que sale fuera
 * son la misma cosa.
 *
 * Que `prefers-color-scheme` no entre es una decisión, no un olvido. Una
 * instalación nueva en un móvil configurado en oscuro abre igualmente en
 * claro: la primera impresión de la app es la marca, y quien prefiera oscuro
 * lo pulsa una vez y no vuelve a pensarlo. Si alguien "arregla" esto añadiendo
 * la media query, cambia el defecto para todo el mundo sin querer.
 *
 * El atributo `data-tema` lo pone un script en `layout.tsx` ANTES de pintar.
 * Por eso el CSS no usa `prefers-color-scheme`: con las dos fuentes a la vez
 * el interruptor manual perdería contra el sistema.
 */

export type Tema = 'claro' | 'oscuro';

export const CLAVE_TEMA = 'bjj.tema';

/** El verde de Gullo, medido sobre el logo. Es el acento por defecto. */
export const ACENTO_GULLO = '#458c50';

// ---------------------------------------------------------------- color

/**
 * Un hex válido, o null.
 *
 * Esto no es paranoia de sobra: `color_acento` viene de la base y acaba
 * dentro de un `style`. Un valor sin validar ahí es una inyección de CSS —
 * `red;background:url(...)` es un valor de texto perfectamente legal en una
 * columna `text`.
 */
export function hexValido(v: string | null | undefined): string | null {
  if (typeof v !== 'string') return null;
  const s = v.trim().toLowerCase();
  const m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/.exec(s);
  if (!m) return null;
  return m[1].length === 3
    ? '#' + m[1].split('').map((c) => c + c).join('')
    : s;
}

type RGB = [number, number, number];

const aRgb = (hex: string): RGB =>
  [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)) as RGB;

const aHex = ([r, g, b]: RGB) =>
  '#' + [r, g, b].map((v) => Math.round(Math.min(255, Math.max(0, v)))
    .toString(16).padStart(2, '0')).join('');

function luminancia([r, g, b]: RGB) {
  const c = [r, g, b].map((v) => v / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

/** Contraste WCAG entre dos colores opacos. */
export function contraste(a: string, b: string) {
  const la = luminancia(aRgb(a)), lb = luminancia(aRgb(b));
  const [hi, lo] = la > lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
}

/** Mueve un color hacia el negro (f<0) o hacia el blanco (f>0). */
function mover(hex: string, f: number): string {
  const rgb = aRgb(hex);
  const destino = f < 0 ? 0 : 255;
  const k = Math.abs(f);
  return aHex(rgb.map((v) => v + (destino - v) * k) as RGB);
}

/**
 * Busca la variante del acento que pasa AA sobre el fondo dado.
 *
 * Se aleja del fondo en pasos pequeños hasta llegar a 4.5. Si el acento ya
 * pasa, se devuelve tal cual — no se toca lo que ya está bien.
 *
 * Esto es lo que impide que una academia se deje la interfaz ilegible
 * eligiendo un amarillo: puede poner el color que quiera de relleno, pero el
 * texto que va encima lo decide esta función, no la base de datos.
 */
export function acentoLegible(acento: string, fondo: string, minimo = 4.5): string {
  if (contraste(acento, fondo) >= minimo) return acento;
  const haciaElNegro = luminancia(aRgb(fondo)) > 0.4;
  let mejor = acento, mejorRatio = contraste(acento, fondo);
  for (let i = 1; i <= 20; i++) {
    const cand = mover(acento, (haciaElNegro ? -1 : 1) * (i / 20));
    const r = contraste(cand, fondo);
    if (r > mejorRatio) { mejor = cand; mejorRatio = r; }
    if (r >= minimo) return cand;
  }
  return mejor;   // fondo imposible: se devuelve lo más legible que había
}

/** Blanco o negro sobre el acento, el que más contraste dé. */
export function tintaSobre(acento: string): string {
  return contraste('#050d06', acento) >= contraste('#ffffff', acento)
    ? '#050d06' : '#ffffff';
}

/** El acento con alfa, para rellenos suaves y filos. */
function conAlfa(hex: string, a: number) {
  const [r, g, b] = aRgb(hex);
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}

// ---------------------------------------------------------------- tema

/** El fondo de cada tema. Tiene que coincidir con `--plano` en globals.css. */
const PLANO: Record<Tema, string> = { claro: '#f1f0ee', oscuro: '#0d0d0d' };

export function temaGuardado(): Tema | null {
  if (typeof localStorage === 'undefined') return null;
  const v = localStorage.getItem(CLAVE_TEMA);
  return v === 'claro' || v === 'oscuro' ? v : null;
}

/** Guardado, o claro. El sistema no entra. */
export function resolverTema(): Tema {
  return temaGuardado() ?? 'claro';
}

export function aplicarTema(t: Tema) {
  document.documentElement.dataset.tema = t;
}

export function guardarTema(t: Tema) {
  localStorage.setItem(CLAVE_TEMA, t);
  aplicarTema(t);
}

/**
 * Aplica el acento del grupo. Todo lo demás se deriva de él: el color de
 * texto legible, la tinta de dentro del botón y los rellenos suaves.
 *
 * El grupo elige **el acento**, nunca la paleta entera — ni los colores de
 * datos, ni los de estado.
 */
export function aplicarAcento(acentoCrudo: string | null | undefined, tema: Tema) {
  const acento = hexValido(acentoCrudo) ?? ACENTO_GULLO;
  const raiz = document.documentElement.style;
  const fondo = PLANO[tema];

  raiz.setProperty('--marca', acento);
  raiz.setProperty('--marca-texto', acentoLegible(acento, fondo));
  raiz.setProperty('--marca-fuerte', mover(acento, -0.28));
  raiz.setProperty('--marca-tinta', tintaSobre(acento));
  raiz.setProperty('--marca-suave', conAlfa(acento, tema === 'claro' ? 0.14 : 0.18));
  raiz.setProperty('--marca-filo', conAlfa(acento, tema === 'claro' ? 0.35 : 0.4));

  // La barra del navegador y de la PWA va del color de marca, no del fondo:
  // instalada, la franja de arriba es lo primero que se ve, y ahí es donde la
  // academia se reconoce. Se mueve con el acento del grupo.
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', acento);
}

/**
 * El script que corre antes de pintar.
 *
 * Va en línea en el `<head>` a propósito: si esto esperase a React, la app
 * abriría en claro y saltaría a oscuro delante del usuario. Un destello de
 * pantalla blanca en un gimnasio a oscuras es exactamente lo que no queremos.
 */
export const SCRIPT_TEMA = `(function(){try{
var g=localStorage.getItem('${CLAVE_TEMA}');
document.documentElement.dataset.tema=(g==='oscuro')?'oscuro':'claro';
}catch(e){document.documentElement.dataset.tema='claro'}})()`;
