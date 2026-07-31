/**
 * La cola no puede rendirse en silencio.
 *
 * Los cuatro casos que decide este recorrido, y ninguno se puede comprobar
 * leyendo el codigo:
 *
 *   1. LA PRUEBA DEL AVION. Se registra un roll entero sin red. La pildora
 *      tiene que decir cuantos hay sin subir. Vuelve la red: suben solos y
 *      vuelve a "al dia". Y se comprueba EN LA BASE que llego todo, no solo
 *      la sesion — que es el fallo clasico, subir la cabecera y perder el
 *      contenido.
 *   2. LA RECARGA. Con cosas en la cola, se recarga la app: siguen ahi. Estan
 *      en IndexedDB, no en memoria; si se pierden al recargar, todo lo demas
 *      da igual.
 *   3. EL 4xx. Un evento con un `roll_id` que no existe no se arregla
 *      reintentando. Tiene que salir como "con error", NO entrar en bucle, y
 *      poder descartarse a mano.
 *   4. EL CIERRE. Con algo pendiente, cerrar la pestaña avisa.
 *
 * Escribe de verdad contra Postgres y limpia lo suyo al acabar.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join('.pruebas', 'perfil-cola');

let n = 0;
const ok = (m) => { n++; console.log(`PASS  ${m}`); };
function comprobar(cond, m) {
  if (!cond) { console.log(`FALLO ${m}`); throw new Error(m); }
  ok(m);
}

const pildora = (page) => page.getByTestId('sync').textContent();

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

  await page.goto(`${APP}/entreno`);
  await page.getByTestId('sync').waitFor({ timeout: 30000 });
  await page.waitForTimeout(1500);
  comprobar((await pildora(page)).includes('al día'), 'se arranca con la cola al día');

  const yo = await page.evaluate(async () => {
    const { data } = await window.__sb.auth.getUser();
    const { data: p } = await window.__sb.from('practicantes')
      .select('id').eq('user_id', data.user.id);
    return p?.[0]?.id;
  });

  // ================================================= 1 · LA PRUEBA DEL AVIÓN
  await ctx.setOffline(true);
  ok('modo avión: sin red');

  if (await page.locator('[data-testid="nuevo-roll"]').count() === 0) {
    await page.getByRole('button', { name: 'No-gi', exact: true }).first().click();
    await page.waitForSelector('[data-testid="nuevo-roll"]', { timeout: 10000 });
  }
  await page.click('[data-testid="nuevo-roll"]');
  await page.waitForSelector('[data-testid^="op-"]', { timeout: 10000 });
  await page.locator('[data-testid^="op-"]').first().click();
  await page.waitForSelector('[data-testid="fin-roll"]', { timeout: 10000 });

  // Un roll con dos acciones, para que haya sesión + roll + eventos.
  await page.click('[data-testid="derribo"]');
  await page.waitForSelector('[data-testid="pos-cien_kilos"]', { timeout: 10000 });
  await page.click('[data-testid="pos-cien_kilos"]');
  await page.click('[data-testid="sumision"]');
  await page.waitForSelector('[data-testid="tec-kimura"]', { timeout: 10000 });
  await page.click('[data-testid="tec-kimura"]');
  await page.click('[data-testid="entro-si"]');
  await page.click('[data-testid="fin-roll"]');
  await page.waitForSelector('[data-testid="otro-roll"]', { timeout: 10000 });
  await page.waitForTimeout(2000);

  const sinRed = await pildora(page);
  comprobar(/sin subir/.test(sinRed), `sin red, la píldora dice qué falta: "${sinRed.trim()}"`);

  // ===================================================== 2 · LA RECARGA
  //
  // Sin red no se puede ni recargar la app —el servidor tampoco responde—, asi
  // que para esta parte se vuelve a la red pero se BLOQUEA solo Supabase. Es
  // mas fiel al caso real de todas formas: el movil tiene wifi del gimnasio
  // pero no llega a internet.
  await ctx.setOffline(false);
  // Solo las ESCRITURAS: la app necesita leer para arrancar, y bloquearlo todo
  // haria que ni siquiera pintara la pildora. Lo que se simula es "hay red
  // pero lo que escribo no entra", que es el caso que importa.
  const soloLecturas = (r) => {
    const m = r.request().method();
    (m === 'POST' || m === 'PATCH' || m === 'DELETE') ? r.abort() : r.continue();
  };
  await ctx.route('**/rest/v1/**', soloLecturas);
  await page.reload();
  await page.getByTestId('sync').waitFor({ timeout: 30000 });
  await page.waitForTimeout(2000);
  const trasRecarga = await pildora(page);
  comprobar(/sin subir/.test(trasRecarga),
    `tras recargar sigue ahí: "${trasRecarga.trim()}" — está en IndexedDB, no en memoria`);

  // El detalle, que es lo que convierte un número en algo accionable.
  await page.getByTestId('sync').click();
  await page.getByTestId('detalle-cola').waitFor({ timeout: 10000 });
  const filas = await page.locator('[data-testid^="cola-"]').count();
  comprobar(filas >= 2, `el detalle enseña qué hay dentro (${filas} elementos)`);
  await page.getByTestId('cerrar-cola').click();

  // ============================================ 1b · vuelve la red: suben solos
  await ctx.unroute('**/rest/v1/**');
  await page.evaluate(() => window.dispatchEvent(new Event('online')));
  for (let i = 0; i < 30 && !(await pildora(page)).includes('al día'); i++) {
    await page.waitForTimeout(1000);
  }
  // Si no drena, DECIR QUE SE QUEDO DENTRO. Un test que solo dice "no pasó"
  // obliga a montar un diagnóstico a mano cada vez que falla.
  if (!(await pildora(page)).includes('al día')) {
    const atasco = await page.evaluate(async () => {
      const d = await new Promise((r) => {
        const q = indexedDB.open('bjj-tracker'); q.onsuccess = () => r(q.result); });
      const q = d.transaction('outbox', 'readonly').objectStore('outbox').getAll();
      const t = await new Promise((r) => { q.onsuccess = () => r(q.result); });
      return t.map((x) => `${x.tabla} · ${x.estado ?? 'pendiente'} · ${x.intentos} intentos · ${(x.ultimoError || 'sin error').slice(0, 110)}`);
    });
    console.log('  ATASCADO:');
    for (const linea of atasco) console.log('    ' + linea);
  }
  comprobar((await pildora(page)).includes('al día'),
    'vuelve la red y sube solo, sin tocar nada: la píldora vuelve a "al día"');

  // Y LO QUE IMPORTA: que llegara TODO, no solo la sesión.
  const llego = await page.evaluate(async (quien) => {
    const hoy = new Date().toISOString().slice(0, 10);
    const { data: ses } = await window.__sb.from('sesiones')
      .select('id').eq('practicante_id', quien).eq('fecha', hoy);
    let rolls = 0; let eventos = 0;
    for (const x of ses ?? []) {
      const { data: rs } = await window.__sb.from('rolls').select('id').eq('sesion_id', x.id);
      rolls += (rs ?? []).length;
      for (const r of rs ?? []) {
        const { data: es } = await window.__sb.from('eventos').select('id').eq('roll_id', r.id);
        eventos += (es ?? []).length;
      }
    }
    return { sesiones: (ses ?? []).length, rolls, eventos };
  }, yo);
  comprobar(llego.rolls >= 1 && llego.eventos >= 2,
    `llegó todo a la base: ${llego.sesiones} sesión, ${llego.rolls} roll, ${llego.eventos} eventos`);

  // ===================================================== 3 · EL 4xx
  // Un evento cuyo roll no existe: la clave foránea lo rechaza siempre.
  await page.evaluate(async () => {
    const d = await new Promise((res) => {
      const r = indexedDB.open('bjj-tracker');
      r.onsuccess = () => res(r.result);
    });
    const tx = d.transaction('outbox', 'readwrite');
    tx.objectStore('outbox').put({
      id: '00000000-dead-4000-8000-000000000001',
      tabla: 'eventos',
      fila: {
        id: '00000000-dead-4000-8000-000000000001',
        roll_id: '00000000-dead-4000-8000-0000000000ff',   // no existe
        actor: 'yo', tipo: 'sumision', posicion: 'montada',
        rol: 'arriba', objetivo: 'hombro', completado: true,
      },
      creado: Date.now(), intentos: 0,
    });
    await new Promise((res) => { tx.oncomplete = res; });
  });

  for (let i = 0; i < 25 && !(await pildora(page)).includes('con error'); i++) {
    await page.waitForTimeout(1000);
  }
  const conError = await pildora(page);
  comprobar(/con error/.test(conError),
    `un 4xx sale como error, no como "en cola": "${conError.trim()}"`);

  // Y NO entra en bucle: los intentos no crecen sin parar.
  const intentos = async () => page.evaluate(async () => {
    const d = await new Promise((res) => {
      const r = indexedDB.open('bjj-tracker');
      r.onsuccess = () => res(r.result);
    });
    const q = d.transaction('outbox', 'readonly').objectStore('outbox')
      .get('00000000-dead-4000-8000-000000000001');
    const fila = await new Promise((res) => { q.onsuccess = () => res(q.result); });
    return fila ? { intentos: fila.intentos, estado: fila.estado } : null;
  });
  const i1 = await intentos();
  comprobar(i1?.estado === 'atencion', 'y queda marcado como "necesita atención", no descartado');
  await page.waitForTimeout(12000);
  const i2 = await intentos();
  comprobar(i2 && i2.intentos === i1.intentos,
    `no entra en bucle: sigue en ${i2.intentos} intento(s) tras 12 s`);

  // Descartarlo es decisión de una persona, y se puede.
  await page.getByTestId('sync').click();
  await page.getByTestId('detalle-cola').waitFor({ timeout: 10000 });
  comprobar(await page.getByTestId('error-00000000-dead-4000-8000-000000000001').count() === 1,
    'el detalle enseña el motivo del rechazo');
  await page.getByTestId('descartar-00000000-dead-4000-8000-000000000001').click();
  await page.waitForTimeout(1500);
  comprobar(await intentos() === null, 'y se puede descartar a mano, nunca solo');
  if (await page.getByTestId('cerrar-cola').count()) await page.getByTestId('cerrar-cola').click();

  // ===================================================== 4 · EL CIERRE
  const avisa = await page.evaluate(() => {
    const e = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(e);
    return e.defaultPrevented;
  });
  comprobar(avisa === false, 'sin nada pendiente NO molesta al cerrar');

  await page.evaluate(async () => {
    const d = await new Promise((res) => {
      const r = indexedDB.open('bjj-tracker');
      r.onsuccess = () => res(r.result);
    });
    const tx = d.transaction('outbox', 'readwrite');
    tx.objectStore('outbox').put({
      id: '00000000-dead-4000-8000-000000000002', tabla: 'sesiones',
      fila: { id: '00000000-dead-4000-8000-000000000002' },
      creado: Date.now(), intentos: 0,
    });
    await new Promise((res) => { tx.oncomplete = res; });
  });
  await ctx.route('**/rest/v1/**', soloLecturas);
  await page.waitForTimeout(8000);
  const avisa2 = await page.evaluate(() => {
    const e = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(e);
    return e.defaultPrevented;
  });
  comprobar(avisa2 === true, 'con algo pendiente, avisa antes de cerrar la pestaña');
  await ctx.unroute('**/rest/v1/**');

  const ancho = await page.evaluate(() => document.documentElement.scrollWidth);
  comprobar(ancho <= 390, `a 390px no desborda (${ancho}px)`);

  // ---------- dejar la semilla como estaba ----------
  const limpiado = await page.evaluate(async () => {
    await new Promise((res) => {
      const r = indexedDB.open('bjj-tracker');
      r.onsuccess = () => {
        const tx = r.result.transaction('outbox', 'readwrite');
        tx.objectStore('outbox').clear();
        tx.oncomplete = res;
      };
    });
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

  console.log(`\n######## LA COLA: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
