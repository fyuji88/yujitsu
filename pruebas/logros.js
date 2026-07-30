/**
 * Los logros en pantalla, a 390px y en los dos temas.
 *
 * Lo que de verdad se comprueba: que la coleccion enseña TAMBIEN los que aun
 * no tienes —que es la mitad del diseño—, que el ranking arranca contando solo
 * los verificados, y que el feed no se ha inundado.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

/** Perfiles del navegador y capturas. Va en .gitignore. */
const SALIDA = '.pruebas';
const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join(process.env.PERFIL ?? SALIDA, 'perfil-logros');

let n = 0;
const ok = (m) => { n++; console.log(`PASS  ${m}`); };
function comprobar(cond, m) {
  if (!cond) { console.log(`FALLO ${m}`); throw new Error(m); }
  ok(m);
}

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

  // ---------- La coleccion ----------
  await page.goto(`${APP}/analisis`);
  await page.getByTestId('coleccion').waitFor({ timeout: 30000 });
  ok('la coleccion carga en la ficha del practicante');

  // El catalogo carga rapido y los conseguidos no: la vista se calcula entera
  // sobre los eventos. Se espera a la CUENTA, no a que aparezca la rejilla, o
  // se cuentan cero conseguidos por llegar antes que la consulta.
  await page.waitForFunction(
    () => Number(document.querySelector('[data-testid="coleccion-cuenta"]')
      ?.getAttribute('data-tengo') ?? 0) > 0, null, { timeout: 30000 });
  await page.getByTestId('ver-coleccion').click();
  await page.getByTestId('familia-defensa').waitFor();

  const total = await page.locator('.logro').count();
  comprobar(total === 28, `estan los 28 del catalogo, no solo los conseguidos (${total})`);

  const conseguidos = await page.locator('.logro.on').count();
  const apagados = total - conseguidos;
  comprobar(conseguidos > 0 && apagados > 0,
    `${conseguidos} conseguidos y ${apagados} apagados: los dos estados se ven`);

  // Lo que hace que la coleccion motive: el apagado enseña QUE hay que hacer.
  const apagado = page.locator('.logro:not(.on)').first();
  comprobar((await apagado.locator('.logro-d').innerText()).length > 10,
    'el apagado explica como se consigue, o no motiva a nadie');

  // Y el conseguido enseña la cuenta, con la procedencia al lado.
  const conCuenta = await page.locator('.logro.on .logro-n').first().innerText();
  comprobar(/^×\d+/.test(conCuenta), `el conseguido lleva su cuenta (${conCuenta})`);
  const verificados = await page.locator('.logro.on .logro-ver').count();
  comprobar(verificados > 0,
    'y los verificados llevan su 👁: la procedencia se enseña, no se esconde');

  // Los de cachondeo estan apagados mientras el equipo no los pida.
  const cachondeo = await page.locator('[data-testid="familia-cachondeo"] .logro.on').count();
  comprobar(cachondeo === 0, 'con el cachondeo apagado, ninguno de esa familia cuenta');

  // Pictogramas, no emoji: cada casilla lleva su SVG de linea.
  const svgs = await page.locator('.logro svg path').count();
  comprobar(svgs >= 28, `${svgs} trazos SVG: son pictogramas, no emoji`);

  // ---------- El ranking ----------
  await page.goto(`${APP}/equipo`);
  await page.getByTestId('ranking-mes').waitFor({ timeout: 30000 });
  comprobar(await page.getByTestId('solo-verificados').getAttribute('aria-pressed') === 'true',
    'el ranking arranca contando solo los verificados');

  // El ranking tarda: la vista se calcula sobre todos los eventos del equipo.
  // Hay que esperar a que termine de contar, o se leen cero filas y la prueba
  // pasa sin haber mirado nada.
  const yaConto = () => page.waitForFunction(() => {
    const r = document.querySelector('[data-testid="ranking-mes"]');
    return !!r && !r.textContent.includes('Contando…');
  }, null, { timeout: 60000 });

  await yaConto();
  const conVerif = await page.locator('[data-testid^="rank-"]').count();
  await page.getByTestId('solo-verificados').click();
  await yaConto();
  await page.waitForTimeout(300);
  const conTodo = await page.locator('[data-testid^="rank-"]').count();
  comprobar(conTodo > 0 && conTodo >= conVerif,
    `el interruptor mueve los datos: ${conVerif} logros verificados, ${conTodo} en total`);

  // ---------- El feed no se ha inundado ----------
  const feed = await page.evaluate(async () => {
    const { data } = await window.__sb.rpc('feed', { p_limite: 40, p_antes: null });
    return data ?? [];
  });
  const tipos = {};
  for (const f of feed) tipos[f.tipo_de_elemento] = (tipos[f.tipo_de_elemento] ?? 0) + 1;
  // El `feed.length > 0` no sobra: sin el, un feed vacio daba PASS con
  // "0 de 0" y la comprobacion no comprobaba nada. Paso de verdad cuando el
  // renombrado dejo `f.tipo` en undefined.
  comprobar(feed.length > 0 && (tipos.logro ?? 0) < feed.length / 2,
    `los logros no ahogan el feed: ${tipos.logro ?? 0} de ${feed.length} elementos`);

  const conLogros = feed.filter(
    (f) => f.tipo_de_elemento === 'sesion' && (f.datos?.logros?.length ?? 0) > 0);
  comprobar(conLogros.length > 0,
    `y viajan dentro de la sesion: ${conLogros.length} sesiones los llevan agregados`);

  // ---------- Los dos temas, a 390px ----------
  await page.goto(`${APP}/analisis`);
  // Se espera otra vez a la cuenta: si no, la captura sale con todo apagado y
  // no enseña lo que de verdad se ve.
  await page.waitForFunction(
    () => Number(document.querySelector('[data-testid="coleccion-cuenta"]')
      ?.getAttribute('data-tengo') ?? 0) > 0, null, { timeout: 30000 });
  await page.getByTestId('ver-coleccion').click();
  await page.getByTestId('familia-defensa').waitFor();
  for (const tema of ['claro', 'oscuro']) {
    const desborde = await page.evaluate(() =>
      document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
    comprobar(!desborde, `a 390px la coleccion no desborda (${tema})`);
    await page.screenshot({
      path: path.join(process.env.PERFIL ?? SALIDA, `logros-${tema}.png`), fullPage: true });
    if (tema === 'claro') { await page.getByTestId('tema').click(); await page.waitForTimeout(400); }
  }

  console.log(`\n######## LOGROS EN PANTALLA: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
