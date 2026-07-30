/**
 * La pantalla no se apaga mientras se rueda.
 *
 * Lo que se comprueba no es que el codigo exista, sino el CICLO: que se pida
 * al entrar en el roll, que se vuelva a pedir despues de que el navegador lo
 * suelte —que lo hace solo con ocultar la pestaña— y que se libere al acabar.
 *
 * Los tres fallos posibles son silenciosos: no pedirlo nunca, no recuperarlo
 * tras una distraccion, o retenerlo para siempre y fundir la bateria. Ninguno
 * da error en pantalla.
 *
 * ESTE RECORRIDO ABRE UNA SESION Y CIERRA UN ROLL de verdad, porque el ciclo
 * que interesa es el real. Y desde que `sesiones`, `rolls` y `eventos` estan en
 * el puente del stub, eso llega a Postgres: por eso BORRA su sesion al acabar.
 * Sin esa limpieza los numeros exactos que comprueba `analisis.js` se mueven
 * solos, y el fallo aparece lejos de su causa.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

const SALIDA = '.pruebas';
const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join(process.env.PERFIL ?? SALIDA, 'perfil-pantalla');

let n = 0;
const ok = (m) => { n++; console.log(`PASS  ${m}`); };
function comprobar(cond, m) {
  if (!cond) { console.log(`FALLO ${m}`); throw new Error(m); }
  ok(m);
}

/**
 * Un `navigator.wakeLock` de mentira que apunta lo que le piden.
 *
 * Hace falta porque en un navegador sin cabeza el de verdad rechaza, asi que
 * con el real no se distinguiria "no lo pide" de "lo pide y le dicen que no".
 */
const ESPIA = `
  window.__wake = { pedidos: 0, sueltas: 0, vivos: 0 };
  Object.defineProperty(navigator, 'wakeLock', {
    configurable: true,
    value: {
      request: async () => {
        window.__wake.pedidos++; window.__wake.vivos++;
        const c = {
          released: false,
          release: async () => { c.released = true; window.__wake.sueltas++; window.__wake.vivos--; },
        };
        return c;
      },
    },
  });
`;

(async () => {
  fs.rmSync(PERFIL, { recursive: true, force: true });
  const ctx = await chromium.launchPersistentContext(PERFIL, {
    channel: 'msedge', headless: true, viewport: { width: 390, height: 844 },
  });
  await ctx.addInitScript(ESPIA);
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

  await page.goto(`${APP}/entreno`);
  await page.getByTestId('sync').waitFor({ timeout: 30000 });

  const wake = () => page.evaluate(() => window.__wake);

  comprobar((await wake()).pedidos === 0,
    'antes de rodar no se pide: la pantalla puede apagarse como siempre');

  // ---------- Empezar un roll propio ----------
  // Roll propio, no observado: es el caso en el que el movil lo llevas TU y es
  // el tuyo el que se apaga. Observando, el que registra tiene el movil en la
  // mano todo el rato.
  // Primero abrir la sesion del dia; sin ella no hay boton de roll.
  if (await page.locator('[data-testid="nuevo-roll"]').count() === 0) {
    await page.getByRole('button', { name: 'No-gi', exact: true }).first().click();
    await page.waitForSelector('[data-testid="nuevo-roll"]', { timeout: 10000 });
  }
  await page.click('[data-testid="nuevo-roll"]');
  await page.waitForSelector('[data-testid^="op-"]', { timeout: 10000 });
  await page.locator('[data-testid^="op-"]').first().click();
  await page.waitForSelector('[data-testid="fin-roll"]', { timeout: 10000 });
  ok('se entra en un roll propio');

  await page.waitForTimeout(400);
  comprobar((await wake()).pedidos >= 1, 'al entrar en el roll se pide el bloqueo');
  comprobar((await wake()).vivos === 1, 'y queda uno vivo, no varios');

  // ---------- Una distraccion: el navegador lo suelta solo ----------
  // Se simula lo que hace de verdad: soltar el bloqueo y ocultar la pestaña.
  await page.evaluate(() => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true, get: () => 'hidden',
    });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await page.waitForTimeout(300);
  await page.evaluate(() => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true, get: () => 'visible',
    });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await page.waitForTimeout(400);
  comprobar((await wake()).pedidos >= 2,
    `al volver a la app se vuelve a pedir (${(await wake()).pedidos} peticiones)`);

  // ---------- Cerrar el roll: hay que soltarlo ----------
  await page.click('[data-testid="fin-roll"]');
  await page.waitForSelector('[data-testid="fin-roll"]', { state: 'detached', timeout: 10000 });
  await page.waitForTimeout(500);
  const fin = await wake();
  comprobar(fin.vivos === 0,
    `al salir del roll se suelta: ${fin.pedidos} pedidos, ${fin.sueltas} sueltas`);

  // ---------- dejar la semilla como estaba ----------
  // Este recorrido ESCRIBE de verdad contra Postgres desde que `sesiones`,
  // `rolls` y `eventos` estan en el puente del stub. Borra EXACTAMENTE la
  // sesion que abrio —su id esta en localStorage—, nunca "las de hoy": la
  // semilla tambien tiene sesiones de hoy y borrarlas la romperia.
  const limpiado = await page.evaluate(async () => {
    const guardada = localStorage.getItem('bjj.sesion-abierta');
    if (!guardada) return 'no habia sesion que borrar';
    const { id: sid } = JSON.parse(guardada);
    const { data: rolls } = await window.__sb.from('rolls').select('id').eq('sesion_id', sid);
    for (const r of rolls ?? []) {
      await window.__sb.from('eventos').delete().eq('roll_id', r.id);
      await window.__sb.from('rolls').delete().eq('id', r.id);
    }
    await window.__sb.from('sesiones').delete().eq('id', sid);
    localStorage.removeItem('bjj.sesion-abierta');
    return `${(rolls ?? []).length} rolls y su sesion`;
  });
  ok(`la semilla queda como estaba: ${limpiado}`);

  console.log(`\n######## PANTALLA ENCENDIDA: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
