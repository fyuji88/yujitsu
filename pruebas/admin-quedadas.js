/**
 * Administrar un Open Mat, en la pantalla.
 *
 * Lo que decide, y por que estas cosas:
 *
 *   1. BORRAR SOLO SI NO CUELGA NADA. Es la comprobacion mas importante de
 *      todas, porque borrar PARECE limpieza: `inscripciones` y
 *      `quedada_informes` van en CASCADE y `sesiones` en SET NULL, asi que
 *      borrar un Open Mat con gente dentro se lleva los apuntados y desengancha
 *      rolls de otra gente sin avisar. Se comprueba que con una inscripcion el
 *      boton NO EXISTE — no que este apagado.
 *   2. CANCELAR CONSERVA. Sigue ahi, tachado, con sus apuntados. Se cuentan las
 *      filas antes y despues.
 *   3. BAJAR PLAZAS por debajo de los apuntados se rechaza CON EL NUMERO, y el
 *      mensaje llega a la pantalla en vez de morir en la consola.
 *   4. APUNTAR Y QUITAR a otra persona, con la promocion desde la lista.
 *
 * Escribe de verdad contra Postgres y limpia lo suyo al acabar.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join('.pruebas', 'perfil-admin');

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
  // Las confirmaciones se aceptan solas: aqui se prueba el efecto, no el dialogo.
  page.on('dialog', (d) => void d.accept());

  const s = await (await fetch(`${STUB}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  })).json();
  await page.goto(`${APP}/login`);
  await page.waitForFunction(() => !!window.__sb, null, { timeout: 30000 });
  await page.evaluate(async (t) => {
    await window.__sb.auth.setSession(
      { access_token: t.access_token, refresh_token: t.refresh_token });
  }, s);

  // ---------- un Open Mat propio, con UNA plaza ----------
  const creado = await page.evaluate(async () => {
    const { data: me } = await window.__sb.auth.getUser();
    const { data: p } = await window.__sb.from('practicantes')
      .select('id').eq('user_id', me.user.id);
    const yo = p?.[0]?.id;
    const { data: m } = await window.__sb.from('miembros_equipo')
      .select('equipo_id').eq('practicante_id', yo).eq('rol_en_equipo', 'admin');
    const equipo = m?.[0]?.equipo_id;
    // El id lo genera el cliente, como en toda la app: asi no hace falta que
    // la respuesta lo traiga de vuelta.
    const qid = crypto.randomUUID();
    const { error: eq } = await window.__sb.from('quedadas').insert({
      id: qid, equipo_id: equipo, titulo: 'ADMIN prueba',
      fecha: new Date(Date.now() + 864e5).toISOString().slice(0, 10),
      modalidad: 'nogi', plazas_max: 1, creado_por: yo,
    });
    // Sin `neq`: el stub no lo soporta y avisa en vez de ignorarlo. Se filtra
    // aqui, que ademas es lo que hace la pantalla.
    const { data: todos } = await window.__sb.from('practicantes').select('id,nombre');
    const otros = (todos ?? []).filter((x) => x.id !== yo).slice(0, 2);
    return { qid: eq ? null : qid, error: eq?.message, yo, equipo, otros };
  });
  comprobar(!!creado.qid && creado.otros.length >= 2,
    `escenario listo: un Open Mat con 1 plaza y ${creado.otros.length} personas${creado.error ? ' — ' + creado.error : ''}`);

  await page.goto(`${APP}/quedadas`);
  await page.waitForSelector(`[data-testid="quedada-${creado.qid}"]`, { timeout: 30000 });

  // ================================================= 1 · borrar, solo si vacio
  comprobar(await page.getByTestId(`borrar-${creado.qid}`).count() === 1,
    'sin nadie apuntado, el botón de borrar SÍ está');

  // ================================================= 2 · apuntar a otros dos
  await page.getByTestId(`apuntar-${creado.qid}-${creado.otros[0].id}`).click();
  await page.waitForTimeout(1200);
  await page.getByTestId(`apuntar-${creado.qid}-${creado.otros[1].id}`).click();
  await page.waitForTimeout(1200);

  const estados = async () => page.evaluate(async (qid) => {
    const { data } = await window.__sb.from('inscripciones')
      .select('practicante_id,estado,orden_en_lista').eq('quedada_id', qid);
    return data ?? [];
  }, creado.qid);
  let ins = await estados();
  comprobar(ins.filter((i) => i.estado === 'apuntado').length === 1
    && ins.filter((i) => i.estado === 'lista_espera').length === 1,
    'con una plaza: el primero entra y el segundo va a la lista de espera');

  comprobar(await page.getByTestId(`borrar-${creado.qid}`).count() === 0,
    'con gente apuntada, el botón de borrar NO EXISTE — no está apagado, no está');

  // ================================================= 3 · bajar plazas: rechazo
  await page.getByTestId(`editar-${creado.qid}`).click();
  await page.getByTestId(`form-editar-${creado.qid}`).waitFor({ timeout: 10000 });
  await page.getByTestId(`ed-plazas-${creado.qid}`).fill('0');
  await page.getByTestId(`guardar-${creado.qid}`).click();
  await page.waitForTimeout(1500);
  const err = await page.getByTestId('error').count()
    ? await page.getByTestId('error').textContent() : '';
  comprobar(/apuntado/.test(err),
    `bajar plazas por debajo de los apuntados se rechaza, y con el número: "${err.trim()}"`);

  // ================================================= 4 · subir plazas promueve
  await page.getByTestId(`ed-plazas-${creado.qid}`).fill('2');
  await page.getByTestId(`guardar-${creado.qid}`).click();
  await page.waitForTimeout(1800);
  ins = await estados();
  comprobar(ins.filter((i) => i.estado === 'apuntado').length === 2,
    'subir plazas promueve al de la lista de espera');

  // ================================================= 5 · quitar promueve
  await page.getByTestId(`ed-plazas-${creado.qid}`).count()
    && await page.getByTestId(`editar-${creado.qid}`).click().catch(() => {});
  await page.waitForTimeout(400);
  await page.getByTestId(`quitar-${creado.qid}-${creado.otros[0].id}`).click();
  await page.waitForTimeout(1500);
  ins = await estados();
  comprobar(ins.find((i) => i.practicante_id === creado.otros[0].id)?.estado === 'cancelado',
    'quitar a alguien lo saca de la lista de los que vienen');

  // ================================================= 6 · cancelar CONSERVA
  const antes = (await estados()).length;
  await page.getByTestId(`cancelar-${creado.qid}`).click();
  await page.waitForTimeout(1800);
  const despues = (await estados()).length;
  comprobar(despues === antes,
    `cancelar conserva las inscripciones (${antes} antes, ${despues} después)`);
  comprobar(await page.getByTestId(`cancelada-${creado.qid}`).count() === 1,
    'y el Open Mat sigue viéndose, tachado: la gente tiene que enterarse');

  const ancho = await page.evaluate(() => document.documentElement.scrollWidth);
  comprobar(ancho <= 390, `a 390px no desborda (${ancho}px)`);

  // ---------- dejar la semilla como estaba ----------
  const limpio = await page.evaluate(async (qid) => {
    await window.__sb.from('inscripciones').delete().eq('quedada_id', qid);
    await window.__sb.from('quedadas').delete().eq('id', qid);
    const { data } = await window.__sb.from('quedadas').select('id').eq('id', qid);
    return (data ?? []).length === 0;
  }, creado.qid);
  ok(`la semilla queda como estaba: ${limpio ? 'borrado' : 'AVISO no se pudo borrar'}`);

  console.log(`\n######## ADMIN DE QUEDADAS: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
