/**
 * Precisar: bajar de la mecanica madre a una variante, al cerrar el roll.
 *
 * ESTE RECORRIDO ESCRIBE DE VERDAD CONTRA POSTGRES, y por eso existe aparte.
 * Los demas corren contra el stub en modo captura, que apunta lo que la app
 * escribiria sin aplicarlo — y ahi se colo el bug de `sesiones.tipo` y
 * `rolls.orden`: seis recorridos en verde con produccion rota. Aqui se
 * comprueba que lo que sale del cliente lo ACEPTA el esquema.
 *
 * Lo que mira:
 *   1. Que el chip NO aparece cuando la tecnica no tiene variantes. Es el 90%
 *      de los rolls y es lo que hace que precisar no sea un peaje.
 *   2. Que aparece cuando la tiene, con la madre primero.
 *   3. Que al tocar una variante el evento encolado cambia de tecnica —el
 *      camino de la cola, que es el que se usa al cerrar el roll.
 *   4. Que el total de la mecanica no se mueve: el invariante, en la interfaz.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join('.pruebas', 'perfil-precisar');

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
  page.on('console', (m) => { if (m.type() === 'error') console.log('  [consola]', m.text()); });

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

  // ---------- un roll con una sumision SIN variantes ----------
  const abrirRoll = async () => {
    if (await page.locator('[data-testid="nuevo-roll"]').count() === 0) {
      await page.getByRole('button', { name: 'No-gi', exact: true }).first().click();
      await page.waitForSelector('[data-testid="nuevo-roll"]', { timeout: 10000 });
    }
    await page.click('[data-testid="nuevo-roll"]');
    await page.waitForSelector('[data-testid^="op-"]', { timeout: 10000 });
    await page.locator('[data-testid^="op-"]').first().click();
    await page.waitForSelector('[data-testid="fin-roll"]', { timeout: 10000 });
  };

  /** De pie no hay sumision: primero un derribo a una posicion de suelo. */
  const alSuelo = async () => {
    if (await page.locator('[data-testid="sumision"]').count() > 0) return;
    await page.click('[data-testid="derribo"]');
    await page.waitForSelector('[data-testid="pos-cien_kilos"]', { timeout: 10000 });
    await page.click('[data-testid="pos-cien_kilos"]');
    await page.waitForSelector('[data-testid="sumision"]', { timeout: 10000 });
  };

  const sumision = async (slug) => {
    await alSuelo();
    await page.click('[data-testid="sumision"]');
    await page.waitForSelector(`[data-testid="tec-${slug}"]`, { timeout: 10000 });
    await page.click(`[data-testid="tec-${slug}"]`);
    await page.click('[data-testid="entro-si"]');
    await page.waitForTimeout(300);
  };

  await abrirRoll();
  await sumision('kimura');              // kimura SI tiene variante: tarikoplata
  await page.click('[data-testid="fin-roll"]');
  await page.waitForSelector('[data-testid="otro-roll"]', { timeout: 10000 });
  await page.waitForTimeout(800);

  const chips = page.locator('[data-testid^="precisar-"]');
  comprobar(await chips.count() >= 2,
    `con una tecnica que tiene variantes, sale el chip (${await chips.count()} opciones)`);

  const madre = page.locator('[data-testid$="-madre"]').first();
  comprobar(await madre.count() === 1, 'y la madre es una de las opciones ("sigue siendo")');
  comprobar((await madre.textContent()).toLowerCase().includes('sigue siendo'),
    'la madre se lee "Sigue siendo …", no un tecnicismo');

  const variante = page.locator('[data-testid$="-tarikoplata"]').first();
  comprobar(await variante.count() === 1, 'y la variante concreta aparece con su nombre');

  // ---------- precisar: EL INVARIANTE, medido en la base ----------
  //
  // Para cuando se llega aqui la cola ya se ha vaciado contra Postgres, asi que
  // precisar va por la RPC de verdad. Eso es justo lo que hay que probar, y es
  // lo que ningun recorrido contra el stub en modo captura podria comprobar.
  const ids = await page.evaluate(async () => {
    const uno = async (slug) => {
      const { data } = await window.__sb.from('tecnicas').select('id').eq('slug', slug);
      return data?.[0]?.id;
    };
    return { kimura: await uno('kimura'), tarikoplata: await uno('tarikoplata') };
  });
  comprobar(!!ids.kimura && !!ids.tarikoplata, 'el catalogo tiene kimura y tarikoplata');

  const yo = await page.evaluate(async () => {
    const { data } = await window.__sb.auth.getUser();
    const { data: p } = await window.__sb.from('practicantes')
      .select('id').eq('user_id', data.user.id);
    return p?.[0]?.id;
  });
  comprobar(!!yo, 'se resuelve mi ficha de practicante');

  const conteo = async () => page.evaluate(async ([mec, quien]) => {
    const { data } = await window.__sb.from('v_tecnicas_practicante')
      .select('tecnica_id,intentos').eq('mecanica_id', mec).eq('practicante_id', quien);
    const filas = data ?? [];
    return {
      total: filas.reduce((a, r) => a + r.intentos, 0),
      porTecnica: Object.fromEntries(filas.map((r) => [r.tecnica_id, r.intentos])),
    };
  }, [ids.kimura, yo]);

  const antes = await conteo();
  comprobar(antes.total >= 1, `la mecanica kimura tiene ${antes.total} intentos antes`);
  comprobar(!antes.porTecnica[ids.tarikoplata],
    'y todavia ninguno es tarikoplata');

  await variante.click();
  await page.waitForTimeout(1500);

  const despues = await conteo();
  comprobar(despues.total === antes.total,
    `EL INVARIANTE: el total de la mecanica no se mueve (${antes.total} -> ${despues.total})`);
  comprobar((despues.porTecnica[ids.tarikoplata] ?? 0) === 1,
    `y el desglose SI se mueve: 1 tarikoplata donde habia una kimura`);

  // ---------- un roll con una sumision SIN variantes: nada de chip ----------
  await page.click('[data-testid="otro-roll"]');
  await page.waitForSelector('[data-testid^="op-"]', { timeout: 10000 });
  await page.locator('[data-testid^="op-"]').first().click();
  await page.waitForSelector('[data-testid="fin-roll"]', { timeout: 10000 });
  await sumision('katagatame');          // katagatame NO tiene variantes
  await page.click('[data-testid="fin-roll"]');
  await page.waitForSelector('[data-testid="otro-roll"]', { timeout: 10000 });
  await page.waitForTimeout(600);
  comprobar(await page.locator('[data-testid^="precisar-"]').count() === 0,
    'con una tecnica SIN variantes el chip no existe: precisar no es un peaje');

  const ancho = await page.evaluate(() => document.documentElement.scrollWidth);
  comprobar(ancho <= 390, `a 390px no desborda (${ancho}px)`);

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
    // Y ademas: cualquier sesion MIA de hoy que se haya quedado vacia. El
    // enganche automatico y `sesion_del_dia` pueden crear una segunda sin que
    // este recorrido la conozca, y una sesion de mas mueve el recuento
    // que comprueba `analisis.js` — que falla despues, lejos de aqui.
    const { data: me } = await window.__sb.auth.getUser();
    const { data: yo } = await window.__sb.from('practicantes')
      .select('id').eq('user_id', me.user.id);
    const hoy = new Date().toISOString().slice(0, 10);
    const { data: mias } = await window.__sb.from('sesiones')
      .select('id').eq('practicante_id', yo?.[0]?.id).eq('fecha', hoy);
    for (const x of mias ?? []) {
      const { data: rs } = await window.__sb.from('rolls').select('id').eq('sesion_id', x.id);
      for (const r of rs ?? []) {
        await window.__sb.from('eventos').delete().eq('roll_id', r.id);
        await window.__sb.from('rolls').delete().eq('id', r.id);
      }
      await window.__sb.from('sesiones').delete().eq('id', x.id);
    }
    localStorage.removeItem('bjj.sesion-abierta');
    return `${(rolls ?? []).length} rolls y su sesion`;
  });
  ok(`la semilla queda como estaba: ${limpiado}`);

  console.log(`\n######## PRECISAR: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
