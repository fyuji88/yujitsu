/**
 * Que un backend caído NUNCA se parezca a «no hay nada».
 *
 * POR QUE ESTO EXISTE, con nombres y apellidos. Hasta hoy media app cogía
 * `data` y tiraba el `error`, así que un fallo llegaba como `null`, la lista
 * salía vacía y la pantalla decía una frase concreta, creíble y falsa:
 *
 *   - el feed:      «Todavía no ha pasado nada en el equipo»
 *   - los logros:   «0 de 28 conseguidos»  /  «Este mes todavía no hay logros»
 *   - las quedadas: ningún Open Mat
 *   - el entreno:   «Hacen falta al menos dos fichas en el roster»
 *   - el armazón:   «Tu cuenta existe pero no tiene ficha. Sal y vuelve a
 *                    entrar» — y salir BORRA la cola de salida, o sea que le
 *                    pedía a la gente que tirara los rolls sin subir.
 *
 * Y no era hipotético: `feed()` tarda 10,5 s contra un `statement_timeout` de
 * 8 s, así que falla SIEMPRE con 57014. Lo que se veía era el error.
 *
 * LAS DOS DIRECCIONES, o esto no prueba nada:
 *   1. con el backend roto sale el ERROR y no el vacío;
 *   2. con el backend sano y sin datos sigue saliendo el VACIO.
 * Solo con la primera, cambiar todos los vacíos por errores pasaría el test.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join('.pruebas', 'perfil-estados');

let n = 0;
const ok = (m) => { n++; console.log(`PASS  ${m}`); };
function comprobar(cond, m) {
  if (!cond) { console.log(`FALLO ${m}`); throw new Error(m); }
  ok(m);
}

/** El 57014 tal y como lo devuelve PostgREST cuando Postgres cancela. */
const TIMEOUT_REAL = {
  status: 500,
  contentType: 'application/json',
  body: JSON.stringify({
    code: '57014',
    message: 'canceling statement due to statement timeout',
    details: null, hint: null,
  }),
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

  // ================================================== 1 · EL FEED, con 57014
  await ctx.route('**/rest/v1/rpc/feed*', (r) => r.fulfill(TIMEOUT_REAL));
  await page.goto(`${APP}/equipo`);
  await page.getByTestId('feed-error').waitFor({ timeout: 30000 });
  ok('el feed caído enseña un ERROR');

  comprobar(await page.getByTestId('feed-vacio').count() === 0,
    'y NO enseña «todavía no ha pasado nada»: esa frase es la mentira que veníamos contando');

  const codigo = await page.getByTestId('feed-error').getAttribute('data-codigo');
  comprobar(codigo === '57014',
    `lleva el código pegado (${codigo}): sin él, una captura desde el tatami no dice nada`);

  const dice = await page.getByTestId('feed-error').innerText();
  comprobar(/tardó más|canceló/i.test(dice),
    'y lo traduce a algo que se entiende, en vez de escupir el mensaje de Postgres');

  comprobar(await page.getByTestId('reintentar').count() >= 1,
    'con botón de reintentar: sin salida, el único arreglo es recargar en mitad del entreno');

  // ================================================== 2 · reintentar RECUPERA
  await ctx.unroute('**/rest/v1/rpc/feed*');
  await page.getByTestId('reintentar').first().click();
  await page.waitForTimeout(2500);
  comprobar(await page.getByTestId('feed-error').count() === 0,
    'y al reintentar con el backend sano, el error se va sin recargar la página');

  // ================================================== 3 · EL VACIO SIGUE VIVO
  // La otra dirección. Sin esto, cambiar todos los vacíos por errores pasaría
  // el test de arriba y habríamos empeorado la app.
  await ctx.route('**/rest/v1/rpc/feed*', (r) => r.fulfill({
    status: 200, contentType: 'application/json', body: '[]',
  }));
  await page.reload();
  await page.getByTestId('feed-vacio').waitFor({ timeout: 30000 });
  ok('con el backend SANO y sin datos, sigue saliendo el vacío de siempre');
  comprobar(await page.getByTestId('feed-error').count() === 0,
    'y no se cuela un error donde solo hay silencio');
  await ctx.unroute('**/rest/v1/rpc/feed*');

  // ================================================== 4 · EL ARMAZON
  // El peor de todos: decía «sal y vuelve a entrar», y salir borra la cola.
  await ctx.route('**/rest/v1/practicantes*', (r) => r.fulfill(TIMEOUT_REAL));
  await page.goto(`${APP}/analisis`);
  await page.getByTestId('marco-error').waitFor({ timeout: 30000 });
  ok('si no se puede leer tu ficha, el armazón lo dice');

  comprobar(await page.getByTestId('marco-sin-ficha').count() === 0,
    'y NO dice «sal y vuelve a entrar» — salir borra la cola de salida con los rolls sin subir');
  await ctx.unroute('**/rest/v1/practicantes*');

  // ================================================== 5 · EL RANKING DEL MES
  await ctx.route('**/rest/v1/v_logros_mes*', (r) => r.fulfill(TIMEOUT_REAL));
  await page.goto(`${APP}/equipo`);
  await page.getByTestId('ranking-error').waitFor({ timeout: 30000 });
  ok('el ranking del mes caído lo dice, en vez de «este mes no hay logros»');
  comprobar(await page.getByTestId('ranking-vacio').count() === 0,
    'y no se pinta a la vez el vacío, que diría lo contrario en el mismo sitio');
  await ctx.unroute('**/rest/v1/v_logros_mes*');

  // ================================================== 6 · LAS QUEDADAS
  await ctx.route('**/rest/v1/quedadas*', (r) => r.fulfill(TIMEOUT_REAL));
  await page.goto(`${APP}/quedadas`);
  await page.getByTestId('quedadas-error').waitFor({ timeout: 30000 });
  ok('la pantalla de Open Mats caída lo dice en vez de enseñar una lista vacía');
  await ctx.unroute('**/rest/v1/quedadas*');

  // ================================================== 7 · a 390px
  await ctx.route('**/rest/v1/rpc/feed*', (r) => r.fulfill(TIMEOUT_REAL));
  await page.goto(`${APP}/equipo`);
  await page.getByTestId('feed-error').waitFor({ timeout: 30000 });
  const ancho = await page.evaluate(() => document.documentElement.scrollWidth);
  comprobar(ancho <= 390, `el panel de error no desborda a 390px (${ancho}px)`);
  await ctx.unroute('**/rest/v1/rpc/feed*');

  console.log(`\n######## ERROR Y VACIO: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
