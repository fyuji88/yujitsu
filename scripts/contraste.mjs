/**
 * Comprueba los contrastes del tema. Falla si alguna combinación de texto
 * sobre fondo baja del mínimo de WCAG AA.
 *
 *   node scripts/contraste.mjs        (o: npm run test:contraste)
 *
 * Por qué existe: un tema se degrada solo. Alguien aclara un gris para que
 * "se vea más elegante", nadie mide, y tres meses después media app está por
 * debajo de AA sin que se haya roto nada visiblemente. Un ojo no detecta 4,3
 * frente a 4,6; esto sí.
 *
 * Los valores NO se escriben aquí: se leen de src/app/globals.css. Si alguien
 * toca un token, este script lo mide en su siguiente ejecución. Duplicar los
 * colores en el test sería un gemelo que se separa del original.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const CSS = readFileSync(join(RAIZ, 'src/app/globals.css'), 'utf8');

/** Los dos listones de WCAG 2.1: texto normal y texto grande (>=24px o >=19px negrita). */
const AA = 4.5;
const AA_GRANDE = 3;

// ---------------------------------------------------------------- tokens

/** Saca los `--token: valor` de un bloque que empieza en el selector dado. */
function bloque(selector) {
  const i = CSS.indexOf(selector);
  if (i < 0) throw new Error(`no encuentro el bloque ${selector} en globals.css`);
  const abre = CSS.indexOf('{', i);
  let nivel = 0, fin = abre;
  for (let j = abre; j < CSS.length; j++) {
    if (CSS[j] === '{') nivel++;
    else if (CSS[j] === '}' && --nivel === 0) { fin = j; break; }
  }
  const cuerpo = CSS.slice(abre + 1, fin);
  const t = {};
  for (const m of cuerpo.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)) t[m[1]] = m[2].trim();
  return t;
}

const CLARO = bloque(':root{');
const OSCURO = { ...CLARO, ...bloque(':root[data-tema="oscuro"]') };

/** Resuelve `var(--x)` en cadena, para tokens definidos en términos de otros. */
function valor(tokens, nombre, visto = new Set()) {
  let v = tokens[nombre];
  if (v === undefined) throw new Error(`token ${nombre} no definido`);
  while (v.startsWith('var(')) {
    const ref = v.slice(4, v.indexOf(')')).trim().split(',')[0].trim();
    if (visto.has(ref)) throw new Error(`ciclo de var() en ${nombre}`);
    visto.add(ref);
    v = tokens[ref];
    if (v === undefined) throw new Error(`token ${ref} (referido por ${nombre}) no definido`);
    v = v.trim();
  }
  return v;
}

// ---------------------------------------------------------------- color

function rgb(css) {
  const s = css.trim();
  let m = s.match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
  if (m) {
    const h = m[1].length === 3 ? m[1].split('').map((c) => c + c).join('') : m[1];
    return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)).concat(1);
  }
  m = s.match(/^rgba?\(([^)]+)\)$/i);
  if (m) {
    const p = m[1].split(/[,/]/).map((x) => parseFloat(x));
    return [p[0], p[1], p[2], p.length > 3 && !Number.isNaN(p[3]) ? p[3] : 1];
  }
  throw new Error(`no sé leer el color "${css}"`);
}

/** Aplana un color con alfa sobre su fondo. Un borde a .10 no es un color. */
function sobre(color, fondo) {
  const [r, g, b, a] = rgb(color);
  if (a >= 1) return [r, g, b];
  const [fr, fg, fb] = sobre(fondo, '#ffffff');
  return [r * a + fr * (1 - a), g * a + fg * (1 - a), b * a + fb * (1 - a)];
}

function luminancia([r, g, b]) {
  const c = [r, g, b].map((v) => v / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function ratio(texto, fondo) {
  const a = luminancia(sobre(texto, fondo));
  const b = luminancia(sobre(fondo, '#ffffff'));
  const [hi, lo] = a > b ? [a, b] : [b, a];
  return (hi + 0.05) / (lo + 0.05);
}

// ---------------------------------------------------------------- pares
//
// Cada par es una combinación que EXISTE en la app: token de texto, token de
// fondo y dónde se da. Si añades una pareja nueva de tokens en el CSS, añádela
// aquí — un par que no está listado es un par que nadie mide.

const PARES = [
  ['--texto',        '--plano',      'texto normal sobre el fondo'],
  ['--texto',        '--superficie', 'texto normal sobre tarjeta'],
  ['--texto',        '--superficie-2', 'texto en campos y chips'],
  ['--texto-2',      '--plano',      'texto secundario sobre el fondo'],
  ['--texto-2',      '--superficie', 'texto secundario sobre tarjeta'],
  ['--tenue',        '--plano',      'etiquetas y pies de foto'],
  ['--tenue',        '--superficie', 'etiquetas dentro de tarjeta'],

  // Marca. El de relleno y el de texto son distintos a propósito: el de marca
  // se queda corto para texto pequeño en los dos temas.
  ['--marca-texto',  '--plano',      'enlaces y texto de marca'],
  ['--marca-texto',  '--superficie', 'texto de marca sobre tarjeta'],
  ['--marca-tinta',  '--marca',      'texto dentro del botón principal'],

  // Estado.
  ['--ok',           '--superficie', 'píldora de sincronización al día'],
  ['--aviso',        '--superficie', 'píldora con cosas en cola'],
  ['--error',        '--superficie', 'píldora de error y textos de fallo'],
  ['--error',        '--plano',      'mensajes de error'],

  // Datos como TEXTO. Los de relleno (heatmap, barras) no son texto y no se
  // miden aquí; estos sí lo son: el destello del marcador, los valores del
  // tanteo y los filtros marcados.
  ['--dato-yo-texto', '--plano',     'destello y tanteo, lado propio'],
  ['--dato-op-texto', '--plano',     'destello y tanteo, lado rival'],
  ['--dato-yo-texto', '--superficie', 'filtro marcado del análisis'],
];

// No hay excepción de "texto grande". El marcador es lo único que llega a
// 34px, y usa igualmente los tokens de texto: apurar hasta 3:1 en el número
// más importante de la pantalla para ahorrarse un token no sale a cuenta.

// ---------------------------------------------------------------- salida

let fallos = 0;
const lineas = [];

for (const [tema, tokens] of [['claro', CLARO], ['oscuro', OSCURO]]) {
  lineas.push(`\n  ${tema.toUpperCase()}`);
  for (const [t, f, donde] of PARES) {
    const vt = valor(tokens, t), vf = valor(tokens, f);
    const r = ratio(vt, vf);
    const min = AA;
    const pasa = r >= min;
    if (!pasa) fallos++;
    lineas.push(
      `  ${pasa ? 'ok  ' : 'FALLA'} ${r.toFixed(2).padStart(5)}  `
      + `${t} sobre ${f}`.padEnd(38) + donde
      + (pasa ? '' : `   ← necesita ${min}`),
    );
  }
}

console.log(lineas.join('\n'));

// El verde de marca no puede acabar en los datos: ni en el heatmap, ni en las
// barras, ni en el marcador. No es estética — verde contra naranja es el par
// que se cae con el daltonismo más común, y un gimnasio de BJJ es
// mayoritariamente hombres.
const DATOS = /--dato-|\.hm|\.marcador|\.track|\.raya|\.escala|\.leyenda/;
const cuerpo = CSS.split('\n');
const intrusos = [];
cuerpo.forEach((linea, i) => {
  if (/var\(--marca/.test(linea) && DATOS.test(linea)) intrusos.push(`${i + 1}: ${linea.trim()}`);
});
for (let i = 0; i < cuerpo.length; i++) {
  const sel = cuerpo[i];
  if (!/^\s*\.(hm|marcador|track|raya|escala|leyenda)|\.viz (td|table)/.test(sel)) continue;
  for (let j = i; j < Math.min(i + 6, cuerpo.length); j++) {
    if (/var\(--marca/.test(cuerpo[j])) intrusos.push(`${j + 1}: ${cuerpo[j].trim()}`);
    if (cuerpo[j].includes('}')) break;
  }
}
if (intrusos.length) {
  fallos += intrusos.length;
  console.log('\n  FALLA  el verde de marca se ha colado en los datos:');
  intrusos.forEach((l) => console.log(`         ${l}`));
}

// Un solo verde en toda la hoja. Los verdes que valen son los tres de Gullo.
const VERDES_OK = new Set(['#458c50', '#55a562', '#33693c', '#2f5f37']);
const verdes = new Set();
for (const m of CSS.matchAll(/#[0-9a-f]{6}/gi)) {
  const [r, g, b] = rgb(m[0]);
  if (g > r + 18 && g > b + 18) verdes.add(m[0].toLowerCase());
}
const colados = [...verdes].filter((v) => !VERDES_OK.has(v));
if (colados.length) {
  fallos += colados.length;
  console.log(`\n  FALLA  hay más de un verde en la hoja: ${colados.join(', ')}`);
  console.log('         La app se queda con el de Gullo y sus variantes.');
}

console.log(fallos === 0
  ? `\n  ######## CONTRASTE: ${PARES.length * 2} pares, todos pasan AA ########\n`
  : `\n  ######## CONTRASTE: ${fallos} FALLOS ########\n`);
process.exit(fallos === 0 ? 0 : 1);
