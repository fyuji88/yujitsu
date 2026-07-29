/**
 * La pantalla de analisis, a 390px, contra la semilla de demo.
 *
 * Los numeros salen de `db/pruebas/semilla-demo.sql`, que es DETERMINISTA: no
 * usa random(), asi que dos siembras dan exactamente lo mismo y aqui se pueden
 * comprobar cantidades. Si cambias la semilla cambian estos numeros — y esa es
 * la gracia: si `analisis()` empieza a contar distinto, esto se entera.
 *
 *   psql ... -v confirmar=si -f db/pruebas/semilla-demo.sql
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

/** Perfiles del navegador y capturas. Va en .gitignore. */
const SALIDA = '.pruebas';
const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join(process.env.PERFIL ?? SALIDA, 'perfil-analisis');

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
  ok('la pantalla carga');

  // ---------------------------------------------- numeros vs el HTML de referencia
  const kpis = await page.locator('.kpi .v').allTextContents();
  comprobar(kpis.join(',') === '180,45,165,72',
    `los KPI cuadran con la semilla: ${kpis.join(' · ')} (rolls, sesiones, favor, contra)`);

  const cel = (p, o) => page.locator(`[data-testid="celda-${p}-${o}"]`);
  // El juego de Goku tiene forma a proposito: vive en la espalda y en la
  // montada, y apenas toca las piernas. Un heatmap plano no probaria la rampa.
  comprobar(await cel('espalda', 'cuello').textContent() === '51',
    'espalda / cuello = 51: donde vive');
  comprobar(await cel('montada', 'cuello').textContent() === '42',
    'montada / cuello = 42');
  comprobar(await cel('media_guardia', 'rodilla').textContent() === '6',
    'media guardia / rodilla = 6: lo que casi no juega');
  comprobar(await page.locator('td.cell.tocable').count() === 7,
    '7 celdas con dato en el ofensivo');

  // Las columnas vacias se quedan: que nunca ataques ahi es informacion.
  comprobar(await page.locator('table.hm thead th.colh').count() === 10,
    'las diez columnas de objetivo estan, tengan dato o no');
  comprobar(await page.locator('td.cell.zero').count() > 0,
    'y las celdas a cero se ven, no se filtran');

  await page.click('[data-testid="hm-def"]');
  await page.waitForSelector('[data-testid="celda-montada-cuello"]');
  comprobar(await cel('montada', 'cuello').textContent() === '36',
    'en el defensivo, montada / cuello = 36: por donde le entran');
  comprobar(await page.locator('td.cell.tocable').count() === 4,
    '4 celdas con dato en el defensivo');

  // ---------------------------------------------- la rampa se invierte en oscuro
  const fondoDe = async (p, o) => cel(p, o).evaluate((e) => getComputedStyle(e).backgroundColor);
  // La app arranca en CLARO, asi que se mide primero ese y luego el oscuro.
  const altoC = await fondoDe('montada', 'cuello');               // 36, el maximo
  const bajoC = await fondoDe('guardia_abierta', 'tobillo_pie');  // 9, el minimo
  comprobar(lum(altoC) < lum(bajoC),
    'en claro el valor alto es el mas oscuro y el bajo se funde con el fondo');

  await page.click('[data-testid="tema"]');
  await page.waitForTimeout(300);
  const alto = await fondoDe('montada', 'cuello');
  const bajo = await fondoDe('guardia_abierta', 'tobillo_pie');
  comprobar(lum(alto) > lum(bajo),
    'y en oscuro se invierte: el alto es el mas brillante');

  // El numero de dentro se lee en las dos puntas de la rampa.
  const contraste = async (p, o) => cel(p, o).evaluate((e) => {
    const cs = getComputedStyle(e);
    const L = (c) => { const [r, g, b] = c.match(/\d+/g).map(Number).map((x) => x / 255)
      .map((x) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4));
      return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
    const a = L(cs.backgroundColor) + 0.05, b = L(cs.color) + 0.05;
    return a > b ? a / b : b / a;
  });
  const c1 = await contraste('montada', 'cuello');
  const c2 = await contraste('guardia_abierta', 'tobillo_pie');
  comprobar(c1 > 4.5 && c2 > 4.5,
    `el numero se lee en las dos puntas de la rampa (${c1.toFixed(1)}:1 y ${c2.toFixed(1)}:1)`);
  await page.click('[data-testid="tema"]');

  // ---------------------------------------------- 390px
  const desborde = await page.evaluate(() =>
    document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
  comprobar(!desborde, 'a 390px la pagina no desborda en horizontal');
  const rueda = await page.locator('.hmbox').evaluate((e) => e.scrollWidth > e.clientWidth);
  comprobar(rueda, 'el heatmap rueda dentro de su caja, con la columna de posiciones pegada');

  // ---------------------------------------------- de la celda a los rolls
  await page.click('[data-testid="hm-off"]');
  await page.waitForSelector('[data-testid="celda-de_la_riva-codo"]');
  await page.click('[data-testid="celda-de_la_riva-codo"]');
  await page.waitForSelector('[data-testid="detalle-celda"]');
  await page.waitForFunction(
    () => document.querySelectorAll('[data-testid="detalle-celda"] tbody tr').length > 0,
    null, { timeout: 20000 });
  // La celda cuenta finalizadas (5); el detalle lista los 6 intentos, con el
  // fallado marcado. Eso es lo que se quiere ver: donde lo intentaste y no salio.
  const filas = await page.locator('[data-testid="detalle-celda"] tbody tr').allTextContents();
  comprobar(filas.length === 12,
    `tocar la celda enseña los 12 intentos que hay detras, no solo los 6 que entraron`);
  comprobar(filas.filter((f) => f.includes('falló')).length === 6,
    'y los 6 intentos fallados salen marcados');
  comprobar((await page.locator('[data-testid="detalle-celda"] .cap').textContent())
    .includes('6') , 'con la cabecera diciendo cuantas entraron');
  await page.click('[data-testid="cerrar-detalle"]');

  // ---------------------------------------------- el filtro cambia los numeros
  // Ojo: mientras recarga, los KPI se desmontan. Hay que esperar a que el nodo
  // EXISTA y ademas haya cambiado, o se lee el hueco del medio.
  const rollsCuando = async (previo) => {
    await page.waitForFunction((p) => {
      const e = document.querySelector('.kpi .v');
      return !!e && e.textContent !== p;
    }, previo, { timeout: 20000 });
    return (await page.locator('.kpi .v').allTextContents())[0];
  };
  const antes = (await page.locator('.kpi .v').allTextContents())[0];
  await page.click('[data-testid="mod-gi"]');
  const gi = await rollsCuando(antes);
  await page.click('[data-testid="mod-nogi"]');
  const nogi = await rollsCuando(gi);
  comprobar(Number(gi) + Number(nogi) === Number(antes),
    `gi (${gi}) + nogi (${nogi}) = todo (${antes}): el filtro mueve los datos, no solo el boton`);
  await page.click('[data-testid="mod-todo"]');

  // ---------------------------------------------- quien registro los datos
  const cob = await page.locator('[data-testid="cobertura"]').textContent();
  comprobar(cob.length > 0, `dice quien registro los datos: "${cob}"`);

  // ---------------------------------------------- tablas
  await page.click('[data-testid="ver-tablas"]');
  await page.waitForSelector('[data-testid="tablas"]');
  comprobar(await page.locator('[data-testid="tablas"] table.tv').count() === 5,
    'los mismos datos como tabla, los cinco bloques');
  await page.click('[data-testid="ver-tablas"]');

  // ---------------------------------------------- otro practicante, sin datos
  await page.waitForSelector('[data-testid="selector-practicante"]');
  await page.selectOption('[data-testid="selector-practicante"]', { label: 'Bulma' });
  await page.waitForSelector('[data-testid="vacio"]', { timeout: 20000 });
  const vacio = await page.locator('[data-testid="vacio"]').textContent();
  comprobar(vacio.includes('Bulma') && !vacio.includes('Ir a registrar'),
    'con otro practicante sin datos, el mensaje no es "empieza a registrar"');

  await page.selectOption('[data-testid="selector-practicante"]', { label: 'Goku (tú)' });
  await page.waitForSelector('[data-testid="hm-off"]', { timeout: 20000 });
  ok('y se vuelve a los propios');

  await page.screenshot({ path: path.join(process.env.PERFIL ?? SALIDA, 'analisis-claro.png'), fullPage: true });
  await page.click('[data-testid="tema"]');
  await page.waitForTimeout(250);
  await page.screenshot({ path: path.join(process.env.PERFIL ?? SALIDA, 'analisis-oscuro.png'), fullPage: true });

  await ctx.close();
  fs.rmSync(PERFIL, { recursive: true, force: true });
  console.log(`\n######## ${n} COMPROBACIONES, TODAS OK ########`);
})().catch((e) => { console.error('\nEL RECORRIDO FALLO:', e.message); process.exit(1); });
