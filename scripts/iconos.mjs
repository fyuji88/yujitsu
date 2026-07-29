/**
 * Genera los iconos de la PWA a partir del logo de Gullo.
 *
 *   node scripts/iconos.mjs               (usa public/logo-gullo.png)
 *   node scripts/iconos.mjs otro.png
 *
 * Es de un solo uso: se ejecuta cuando cambia el logo y los PNG resultantes se
 * commitean, asi que no esta en `package.json`. Usa el mismo `playwright-core`
 * que los recorridos en navegador.
 *
 * Lo que hace, y el porqué de cada cosa:
 *
 *  - **Recorta el blanco.** El logo viene sobre un cuadrado blanco y sin canal
 *    alfa. Si se usara tal cual, en el escritorio saldría un cuadrado blanco
 *    sobre el hueso de la app, con un borde visible donde no debería haberlo.
 *  - **Fondo hueso, no transparente.** Un icono transparente se ve distinto en
 *    cada lanzador y en algunos desaparece. El hueso `#f1f0ee` es el fondo de
 *    la web de Gullo y el tema por defecto de la app: lo que se instala y lo
 *    que se abre son la misma cosa.
 *  - **El enmascarable va más pequeño.** Android recorta el icono a la forma
 *    que quiera el lanzador —círculo, cuadrado redondeado, gota— y solo
 *    garantiza el 80 % central. El logo lleva la "G" asomando por encima del
 *    círculo, así que con el tamaño normal esa punta se perdería.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

import { chromium } from 'playwright-core';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const ORIGEN = resolve(process.argv[2] ?? join(RAIZ, 'public/logo-gullo.png'));
const HUESO = '#f1f0ee';

/** Lo que se genera. `escala` es la fracción del lienzo que ocupa el logo. */
const PIEZAS = [
  { fichero: 'icon-192.png', ancho: 192, alto: 192, escala: 0.84, fondo: HUESO },
  { fichero: 'icon-512.png', ancho: 512, alto: 512, escala: 0.84, fondo: HUESO },
  // 68 %: el logo entero, punta de la G incluida, dentro del 80 % que Android
  // promete no recortar, y con margen para que no roce.
  { fichero: 'icon-maskable-512.png', ancho: 512, alto: 512, escala: 0.68, fondo: HUESO },
  { fichero: 'apple-touch-icon.png', ancho: 180, alto: 180, escala: 0.84, fondo: HUESO },
  // Y el logo suelto, recortado y con transparencia, para las tarjetas
  // compartibles y para donde haga falta la marca sin fondo.
  { fichero: 'logo-gullo-recortado.png', ancho: 1024, alto: 1024, escala: 1, fondo: null },
];

/**
 * Las pantallas de arranque de iOS.
 *
 * Android compone el splash solo, con `background_color` y el icono del
 * manifest. iOS no: o le das una imagen del tamaño EXACTO del dispositivo, o
 * enseña una pantalla en blanco mientras abre. Y "del tamaño exacto" es
 * literal — si no cuadra al píxel, la descarta y vuelve al blanco.
 *
 * Solo vertical: el manifest fija `orientation: portrait`, así que la mitad de
 * las combinaciones no hacen falta. Y solo iPhone: la app es de 430px de ancho
 * y en un iPad se instalaría igual, pero cubrir tabletas son ocho ficheros más
 * para un caso que hoy no existe. Cuando pase, se añaden aquí.
 *
 * `dw`/`dh` son los puntos que reporta el navegador y `dpr` la densidad: es lo
 * que va en el `media`, no los píxeles.
 */
const PANTALLAS = [
  { dw: 375, dh: 667, dpr: 2, modelos: 'SE 2ª/3ª, 6, 7, 8' },
  { dw: 414, dh: 736, dpr: 3, modelos: '8 Plus' },
  { dw: 375, dh: 812, dpr: 3, modelos: 'X, XS, 11 Pro, 12 mini, 13 mini' },
  { dw: 414, dh: 896, dpr: 2, modelos: 'XR, 11' },
  { dw: 414, dh: 896, dpr: 3, modelos: 'XS Max, 11 Pro Max' },
  { dw: 390, dh: 844, dpr: 3, modelos: '12, 13, 14' },
  { dw: 393, dh: 852, dpr: 3, modelos: '14 Pro, 15, 16' },
  { dw: 402, dh: 874, dpr: 3, modelos: '16 Pro' },
  { dw: 428, dh: 926, dpr: 3, modelos: '12/13 Pro Max, 14 Plus' },
  { dw: 430, dh: 932, dpr: 3, modelos: '14 Pro Max, 15 Pro Max, 16 Plus' },
  { dw: 440, dh: 956, dpr: 3, modelos: '16 Pro Max' },
];

for (const p of PANTALLAS) {
  const ancho = p.dw * p.dpr, alto = p.dh * p.dpr;
  PIEZAS.push({
    fichero: `splash-${ancho}x${alto}.png`,
    ancho, alto,
    // Un cuarto del ancho: en una pantalla alta, un logo grande parece un
    // error de escala. La marca se reconoce igual y el arranque no grita.
    escala: 0.42, base: 'ancho', fondo: HUESO,
  });
}

const b64 = readFileSync(ORIGEN).toString('base64');

const ctx = await chromium.launchPersistentContext('', {
  channel: 'msedge', headless: true,
});
const page = await ctx.newPage();

const salidas = await page.evaluate(async ({ b64, piezas }) => {
  const img = new Image();
  img.src = 'data:image/png;base64,' + b64;
  await img.decode();

  // 1. Pasar el blanco a transparente y encontrar el recuadro del contenido.
  const c = document.createElement('canvas');
  c.width = img.width; c.height = img.height;
  const g = c.getContext('2d');
  g.drawImage(img, 0, 0);
  const d = g.getImageData(0, 0, c.width, c.height);
  const px = d.data;

  // El logo es negro puro sobre blanco puro; 235 deja fuera el blanco y el
  // antialias más claro, y se queda con el trazo y sus bordes.
  let x0 = c.width, y0 = c.height, x1 = -1, y1 = -1;
  for (let i = 0; i < px.length; i += 4) {
    if (px[i] > 235 && px[i + 1] > 235 && px[i + 2] > 235) { px[i + 3] = 0; continue; }
    const p = i / 4, x = p % c.width, y = (p / c.width) | 0;
    if (x < x0) x0 = x; if (x > x1) x1 = x;
    if (y < y0) y0 = y; if (y > y1) y1 = y;
  }

  // Segunda pasada, si la primera no recortó nada.
  //
  // El PNG del diseñador trae una línea gris de 1px rodeando el cuadrado. Con
  // ella, el recuadro del contenido es la imagen entera, el recorte no recorta
  // y el logo sale diminuto en medio de un mar de blanco. En vez de intentar
  // reconocer el marco —lleva antialias y no es de un solo tono—, se usa lo
  // que de verdad se sabe: si el dibujo llega justo hasta el borde por los
  // cuatro lados, no es el dibujo, es un marco. Se reintenta ignorando el 1 %
  // exterior, donde ningún logo razonable pone nada.
  const pegadoAlBorde = x0 === 0 && y0 === 0 && x1 === c.width - 1 && y1 === c.height - 1;
  let marco = 0;
  if (pegadoAlBorde) {
    marco = Math.max(1, Math.round(Math.min(c.width, c.height) * 0.01));
    x0 = c.width; y0 = c.height; x1 = -1; y1 = -1;
    for (let y = marco; y < c.height - marco; y++) {
      for (let x = marco; x < c.width - marco; x++) {
        const i = (y * c.width + x) * 4;
        if (px[i + 3] === 0) continue;
        if (x < x0) x0 = x; if (x > x1) x1 = x;
        if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
    // Y el marco desaparece del todo, que si no se cuela en el icono.
    for (let y = 0; y < c.height; y++) {
      for (let x = 0; x < c.width; x++) {
        if (y < marco || y >= c.height - marco || x < marco || x >= c.width - marco) {
          px[(y * c.width + x) * 4 + 3] = 0;
        }
      }
    }
  }
  g.putImageData(d, 0, 0);

  const ancho = x1 - x0 + 1, alto = y1 - y0 + 1;
  const salidas = {};

  for (const p of piezas) {
    const o = document.createElement('canvas');
    o.width = p.ancho; o.height = p.alto;
    const og = o.getContext('2d');
    if (p.fondo) { og.fillStyle = p.fondo; og.fillRect(0, 0, p.ancho, p.alto); }

    // En un lienzo cuadrado se escala contra el lado menor —da igual cuál—;
    // en uno alto, como los splash, contra el ANCHO, o `escala` acabaría
    // midiendo respecto a una altura de 2800px y el logo saldría enorme.
    const referencia = p.base === 'ancho' ? p.ancho : Math.min(p.ancho, p.alto);
    // Se escala por el lado mayor del contenido, así el logo nunca se deforma
    // ni se sale por el lado más largo.
    const k = (referencia * p.escala) / Math.max(ancho, alto);
    const w = ancho * k, h = alto * k;
    og.imageSmoothingQuality = 'high';
    og.drawImage(c, x0, y0, ancho, alto,
                 (p.ancho - w) / 2, (p.alto - h) / 2, w, h);
    salidas[p.fichero] = o.toDataURL('image/png');
  }
  return { salidas, recorte: { x0, y0, ancho, alto, original: c.width,
                               marco } };
}, { b64, piezas: PIEZAS });

for (const [nombre, uri] of Object.entries(salidas.salidas)) {
  const destino = join(RAIZ, 'public', nombre);
  writeFileSync(destino, Buffer.from(uri.split(',')[1], 'base64'));
  console.log(`  ${nombre}`);
}
// La lista de `apple-touch-startup-image` la escribe este script, no una
// persona: son once entradas con medidas al píxel, y mantenerlas a mano al
// lado de los PNG es garantía de que un día dejen de coincidir y iOS enseñe el
// blanco sin que nadie sepa por qué.
const ts = [
  '/* GENERADO POR scripts/iconos.mjs — no editar a mano. */',
  '',
  '/**',
  ' * Las pantallas de arranque de iOS.',
  ' *',
  ' * Android compone el splash con `background_color` y el icono del manifest.',
  ' * iOS exige una imagen del tamaño EXACTO del dispositivo: si no cuadra al',
  ' * píxel la descarta y enseña una pantalla en blanco mientras abre.',
  ' */',
  'export const PANTALLAS_DE_ARRANQUE = [',
  ...PANTALLAS.map((p) => {
    const w = p.dw * p.dpr, h = p.dh * p.dpr;
    return `  { url: '/splash-${w}x${h}.png',\n`
      + `    media: '(device-width: ${p.dw}px) and (device-height: ${p.dh}px) '\n`
      + `      + 'and (-webkit-device-pixel-ratio: ${p.dpr}) and (orientation: portrait)' },`
      + `   // ${p.modelos}`;
  }),
  '];',
  '',
].join('\n');
writeFileSync(join(RAIZ, 'src/lib/splash.ts'), ts);
console.log('  src/lib/splash.ts');

const r = salidas.recorte;
console.log(`\n  Marco pelado: ${r.marco}px por lado`);
console.log(`  Logo recortado: ${r.ancho}x${r.alto} de ${r.original}x${r.original}`
  + ` (sobraban ${r.original - r.ancho}px a lo ancho)`);

await ctx.close();
