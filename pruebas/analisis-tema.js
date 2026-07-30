/**
 * El panel de analisis despues de unificar los tokens: que la rampa siga
 * invirtiendose entre temas, que no desborde a 390px en ninguno de los dos, y
 * que los colores de datos NO sean el verde de marca.
 *
 * No comprueba numeros: de eso ya se ocupa recorrer-analisis.js.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

/** Perfiles del navegador y capturas. Va en .gitignore. */
const SALIDA = '.pruebas';
const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join(process.env.PERFIL ?? SALIDA, 'perfil-viz');

let n = 0;
const ok = (m) => { n++; console.log(`PASS  ${m}`); };
function comprobar(cond, m) {
  if (!cond) { console.log(`FALLO ${m}`); throw new Error(m); }
  ok(m);
}
const lum = (rgb) => {
  const [r, g, b] = rgb.match(/\d+/g).map(Number).map((c) => c / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

(async () => {
  fs.rmSync(PERFIL, { recursive: true, force: true });
  const ctx = await chromium.launchPersistentContext(PERFIL, {
    channel: 'msedge', headless: true, viewport: { width: 390, height: 844 },
  });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('  [pageerror]', e.message));
  const s = await (await fetch(`${STUB}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  })).json();
  await page.goto(`${APP}/login`);
  await page.waitForFunction(() => !!window.__sb, null, { timeout: 30000 });
  await page.evaluate(async (t) => {
    await window.__sb.auth.setSession(
      { access_token: t.access_token, refresh_token: t.refresh_token });
  }, s);

  await page.goto(`${APP}/analisis`);
  await page.waitForSelector('[data-testid="hm-off"]', { timeout: 30000 });
  ok('el panel carga con los tokens unificados');

  comprobar(await page.evaluate(() => document.documentElement.dataset.tema) === 'claro',
    'y arranca en claro, como el resto de la app');

  // La celda con mas y la celda con menos, sacadas de la propia pantalla: asi
  // no dependen del juego de datos que haya en la base.
  const extremos = async () => page.evaluate(() => {
    const con = [...document.querySelectorAll('td.cell.tocable')]
      .map((e) => ({ id: e.dataset.testid, v: Number(e.textContent) }))
      .filter((c) => Number.isFinite(c.v) && c.v > 0);
    con.sort((a, b) => a.v - b.v);
    return { bajo: con[0], alto: con[con.length - 1] };
  });
  // Hace falta alguien con celdas de valores DISTINTOS: si todas valen 1, los
  // dos extremos de la rampa son el mismo color y la prueba no prueba nada.
  let bajo, alto;
  const opciones = await page.locator('[data-testid="selector-practicante"] option')
    .evaluateAll((os) => os.map((o) => o.value));
  for (const id of opciones) {
    await page.getByTestId('selector-practicante').selectOption(id);
    // Esperar a que PINTE, no un rato fijo. Con `waitForTimeout(1200)` esto
    // fallaba de vez en cuando y solo dentro del lote: si el panel tardaba mas
    // de la cuenta, `count() === 0` mandaba al `continue` y ese practicante se
    // saltaba como si no tuviera datos. Con todos saltados, la comprobacion
    // decia "max undefined" — un fallo que parecia de la rampa y era de la
    // espera.
    try {
      await page.locator('td.cell.tocable').first().waitFor({ timeout: 8000 });
    } catch {
      continue;   // este de verdad no tiene datos
    }
    ({ bajo, alto } = await extremos());
    if (alto && bajo && alto.v > bajo.v) break;
  }
  comprobar(alto && bajo && alto.v > bajo.v,
    `hay un practicante con celdas de valores distintos (max ${alto?.v}, min ${bajo?.v})`);

  const fondo = (id) => page.locator(`[data-testid="${id}"]`)
    .evaluate((e) => getComputedStyle(e).backgroundColor);

  // CLARO: cerca de cero es el tono clarito; el valor alto, el mas oscuro.
  comprobar(lum(await fondo(alto.id)) < lum(await fondo(bajo.id)),
    'en CLARO el valor alto es el mas oscuro y el bajo se funde con el fondo');

  await page.getByTestId('tema').click();
  await page.waitForTimeout(400);
  comprobar(await page.evaluate(() => document.documentElement.dataset.tema) === 'oscuro',
    'el interruptor de la cabecera cambia tambien el panel');

  // OSCURO: se invierte. Sin invertirla, los valores bajos serian los que mas
  // brillan y el heatmap mentiria.
  comprobar(lum(await fondo(alto.id)) > lum(await fondo(bajo.id)),
    'y en OSCURO la rampa se invierte: el alto es el mas brillante');

  // El numero de dentro se lee en las dos puntas, en los dos temas.
  const contraste = (id) => page.locator(`[data-testid="${id}"]`).evaluate((e) => {
    const cs = getComputedStyle(e);
    const L = (c) => {
      const [r, g, b] = c.match(/\d+/g).map(Number).map((x) => x / 255)
        .map((x) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4));
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    const a = L(cs.backgroundColor) + 0.05, b = L(cs.color) + 0.05;
    return a > b ? a / b : b / a;
  });
  for (const tema of ['oscuro', 'claro']) {
    const c1 = await contraste(alto.id), c2 = await contraste(bajo.id);
    comprobar(c1 > 4.5 && c2 > 4.5,
      `en ${tema} el numero se lee en las dos puntas (${c1.toFixed(1)}:1 y ${c2.toFixed(1)}:1)`);
    if (tema === 'oscuro') { await page.getByTestId('tema').click(); await page.waitForTimeout(400); }
  }

  // Ningun verde en los datos: ni en las celdas, ni en las barras, ni en la
  // leyenda. Verde contra naranja es el par que se cae con el daltonismo.
  const verdoso = (rgb) => {
    const [r, g, b] = rgb.match(/\d+/g).map(Number);
    return g > r + 18 && g > b + 18;
  };
  for (const tema of ['claro', 'oscuro']) {
    const colores = await page.evaluate(() => {
      const out = [];
      for (const e of document.querySelectorAll(
        'td.cell, .track .fill, .leyenda b, .raya i, .escala i')) {
        out.push(getComputedStyle(e).backgroundColor);
      }
      return out;
    });
    const verdes = colores.filter(verdoso);
    comprobar(verdes.length === 0,
      `en ${tema}, ningun verde en celdas, barras ni leyenda `
      + `(${colores.length} rellenos mirados)`);
    if (tema === 'claro') { await page.getByTestId('tema').click(); await page.waitForTimeout(400); }
  }

  // 390px en los dos temas.
  for (const tema of ['oscuro', 'claro']) {
    const desborde = await page.evaluate(() =>
      document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
    comprobar(!desborde, `a 390px no desborda en horizontal (${tema})`);
    const rueda = await page.locator('.hmbox').first()
      .evaluate((e) => e.scrollWidth > e.clientWidth);
    comprobar(rueda, `y el heatmap rueda dentro de su caja (${tema})`);
    if (tema === 'oscuro') { await page.getByTestId('tema').click(); await page.waitForTimeout(400); }
  }

  await page.screenshot({ path: path.join(process.env.PERFIL ?? SALIDA, 'viz-claro.png'),
    fullPage: true });

  console.log(`\n######## ANALISIS Y TEMA: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
