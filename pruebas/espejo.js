/**
 * El roll espejo, y por qué se perdía la mitad de cada roll observado.
 *
 * EL ENSAYO EN PRODUCCIÓN. En «Battle for Namek» se registraron tres rolls
 * observados y salieron los tres huérfanos: Goku con sus 3 rolls, y Freezer y
 * Krilin sin sesión y sin nada. Con eso el informe del Open Mat cuenta un solo
 * lado, porque `metricas_quedada` agrupa por el DUEÑO de la sesión.
 *
 * LA CAUSA, medida y no supuesta: `espejar_roll()` tiene esta guarda —
 *
 *     if not (select usa_sistema from practicantes where id = r.oponente_id)
 *     then return null; end if;
 *
 * — y `usa_sistema` se escribía en `false` al dar de alta a alguien y NO SE
 * PODÍA CAMBIAR DESDE NINGUNA PANTALLA. O sea que todo contacto nacía sin
 * espejo, para siempre, en silencio.
 *
 * No es regresión de bjj_35: los huérfanos empiezan el 6 de junio.
 *
 * Este recorrido comprueba LAS DOS DIRECCIONES, que es lo único que distingue
 * «lo he arreglado» de «he quitado la comprobación»:
 *   1. con la casilla quitada NO hay espejo (el fallo, reproducido);
 *   2. con la casilla puesta SÍ lo hay, y el oponente tiene su sesión.
 *
 * Y de paso, lo que pidió Felipe: que el Open Mat SE LEA.
 */
const { chromium } = require('playwright-core');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join('.pruebas', 'perfil-espejo');
const PSQL = process.env.PSQL || 'psql';
const PGURL = process.env.PGURL || 'postgresql://postgres@127.0.0.1:55432/bjj';

let n = 0;
const ok = (m) => { n++; console.log(`PASS  ${m}`); };
function comprobar(cond, m) {
  if (!cond) { console.log(`FALLO ${m}`); throw new Error(m); }
  ok(m);
}
const sql = (q) =>
  execFileSync(PSQL, [PGURL, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', q],
               { encoding: 'utf8' }).trim();

(async () => {
  try { sql('select 1'); } catch {
    console.log('FALLO no encuentro psql. Exporta PSQL y PGURL, los mismos del stub.');
    process.exit(1);
  }

  fs.rmSync(PERFIL, { recursive: true, force: true });
  const ctx = await chromium.launchPersistentContext(PERFIL, {
    channel: 'msedge', headless: true, viewport: { width: 390, height: 844 },
  });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('  [pageerror]', e.message));
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

  // ---------- escenario: un Open Mat hoy y dos compañeros ----------
  const esc = await page.evaluate(async () => {
    const hoy = new Date().toISOString().slice(0, 10);
    const { data: me } = await window.__sb.auth.getUser();
    const { data: p } = await window.__sb.from('practicantes').select('id').eq('user_id', me.user.id);
    const yo = p?.[0]?.id;
    const { data: m } = await window.__sb.from('miembros_equipo')
      .select('equipo_id').eq('practicante_id', yo).eq('rol_en_equipo', 'admin');
    const qid = crypto.randomUUID();
    await window.__sb.from('quedadas').insert({
      id: qid, equipo_id: m?.[0]?.equipo_id, titulo: 'Battle for Namek',
      fecha: hoy, hora_inicio: '10:00', lugar: 'Namek', modalidad: 'nogi', creado_por: yo,
    });
    await window.__sb.rpc('apuntarse_a_quedada',
      { p_quedada: qid, p_token: null, p_practicante: yo });
    const { data: todos } = await window.__sb.from('practicantes')
      .select('id,nombre,usa_sistema');
    const otros = (todos ?? []).filter((x) => x.id !== yo).slice(0, 2);
    return { qid, otros, yo, hoy, userId: me.user.id };
  });
  const [A, B] = esc.otros;
  comprobar(!!esc.qid && !!A && !!B, `escenario: «Battle for Namek» y ${esc.otros.length} compañeros`);

  // FOTO ANTES DE TOCAR NADA, y por psql. Este recorrido cambia `usa_sistema`
  // de dos fichas, y la primera versión restauraba desde lo que había leído el
  // navegador: se dejó a Vegeta en `false` y el recorrido siguiente se quedó
  // sin compañeros. La foto se toma de la base y se devuelve a la base.
  const antesA = sql(`select usa_sistema from practicantes where id='${A.id}'`);
  const antesB = sql(`select usa_sistema from practicantes where id='${B.id}'`);
  const antesCreado = sql(`select coalesce(creado_por::text,'') from practicantes where id='${B.id}'`);

  /**
   * La limpieza, en `finally`.
   *
   * Este recorrido CAMBIA `usa_sistema` de dos fichas. Cuando falló a la mitad,
   * dejó a dos personas marcadas al revés y el recorrido siguiente se quedó sin
   * compañeros con los que probar: un fallo se convirtió en dos, y el segundo
   * no se parecía en nada a su causa.
   */
  const limpiar = () => sql(`
    delete from eventos where roll_id in (select r.id from rolls r
      join sesiones s on s.id=r.sesion_id where s.quedada_id='${esc.qid}');
    delete from rolls where sesion_id in
      (select id from sesiones where quedada_id='${esc.qid}');
    delete from sesiones where quedada_id='${esc.qid}';
    delete from inscripciones where quedada_id='${esc.qid}';
    delete from quedadas where id='${esc.qid}';
    update practicantes set usa_sistema='${antesB}' where id='${B.id}';
    update practicantes set usa_sistema='${antesA}' where id='${A.id}';
    update practicantes set creado_por=${antesCreado ? `'${antesCreado}'` : 'null'}
      where id='${B.id}';`);
  process.on('exit', () => { try { limpiar(); } catch { /* ya estaba */ } });

  // El botón de editar solo sale en las fichas que diste de alta tú — es la
  // misma condición que la política de Postgres, y por eso la prueba tiene que
  // ponerse en ese caso en vez de saltárselo.
  sql(`update practicantes set creado_por = '${esc.userId}'
        where id = '${B.id}' and user_id is null`);

  const espejosDe = (par) => Number(sql(`select count(*) from rolls where par_id in (
    select par_id from rolls r join sesiones s on s.id=r.sesion_id
     where s.fecha='${esc.hoy}' and s.practicante_id='${A.id}') and par_id is not null`));
  /**
   * Sesiones de alguien EN ESTE Open Mat, no «hoy».
   *
   * La primera versión contaba todas las de hoy y la semilla ya le da sesiones
   * a esa gente: el aserto pasaba o fallaba según qué datos hubiera, que es lo
   * contrario de una prueba.
   */
  const sesionesDe = (pid) => Number(sql(
    `select count(*) from sesiones
      where practicante_id='${pid}' and quedada_id='${esc.qid}'`));
  /** Rolls de alguien en este Open Mat. */
  const rollsDe = (pid) => Number(sql(
    `select count(*) from rolls r join sesiones s on s.id=r.sesion_id
      where s.practicante_id='${pid}' and s.quedada_id='${esc.qid}'`));

  /** Una observación entera, del botón 👁 hasta que la cola la suelta. */
  async function observar() {
    await page.goto(`${APP}/entreno`);
    await page.getByTestId('observar').first().click();
    await page.getByTestId('obs-mod-nogi').click();
    await page.getByTestId(`obs-quedada-${esc.qid}`).click();
    return page;
  }

  // ============================================ 1 · EL OPEN MAT, DICHO
  await observar();
  const dice = await page.getByTestId('obs-quedada-elegida').innerText();
  comprobar(/Battle for Namek/.test(dice),
    `observando se lee a qué Open Mat va la tanda: "${dice.trim()}"`);

  // ============================================ 2 · SIN LA CASILLA: SIN ESPEJO
  sql(`update practicantes set usa_sistema = false where id in ('${A.id}','${B.id}')`);
  await page.getByTestId(`obsA-${A.nombre}`).click();
  await page.getByTestId(`op-${B.nombre}`).click();
  await page.getByTestId('fin-roll').click();
  await page.getByTestId('resumen-observado').waitFor({ timeout: 20000 });
  await page.goto(`${APP}/quedadas`);
  await page.waitForTimeout(2500);

  comprobar(sesionesDe(B.id) === 0,
    'sin «guardarle sus rolls», el compañero NO tiene sesión: el fallo del ensayo, reproducido');
  comprobar(rollsDe(A.id) === 1,
    `y solo hay un lado del roll (${rollsDe(A.id)}), que es medio roll perdido`);

  // ============================================ 3 · CON LA CASILLA: SÍ HAY
  await page.goto(`${APP}/practicantes`);
  await page.getByRole('button', { name: `Editar ${B.nombre}` }).click();
  await page.getByTestId('ed-guardar-rolls').check();
  await page.getByRole('button', { name: 'Guardar' }).click();
  await page.waitForTimeout(1500);
  comprobar(sql(`select usa_sistema from practicantes where id='${B.id}'`) === 't',
    'la casilla «guardarle sus rolls» se puede tocar desde la app — antes no existía');

  await observar();
  await page.getByTestId(`obsA-${A.nombre}`).click();
  await page.getByTestId(`op-${B.nombre}`).click();
  await page.getByTestId('fin-roll').click();
  await page.getByTestId('resumen-observado').waitFor({ timeout: 20000 });
  await page.goto(`${APP}/quedadas`);
  await page.waitForTimeout(2500);

  comprobar(sesionesDe(B.id) === 1,
    'con la casilla puesta, el compañero YA tiene su sesión');
  comprobar(rollsDe(B.id) === 1, 'y su mitad del roll, espejada');
  comprobar(sesionesDe(B.id) === 1,
    'colgada del mismo Open Mat: sin eso no saldría en el informe (bjj_35)');

  // ============================================ 4 · LA TARJETA LO DICE
  await page.goto(`${APP}/entreno`);
  // Se elige el Open Mat y LUEGO la modalidad, que es el orden de la pantalla.
  await page.getByTestId(`quedada-${esc.qid}`).click();
  await page.getByTestId('modalidad-nogi').click();
  await page.getByTestId('sesion-openmat').waitFor({ timeout: 20000 });
  const tarjeta = await page.getByTestId('sesion-openmat').innerText();
  comprobar(/Battle for Namek/.test(tarjeta),
    `la tarjeta de sesión abierta nombra el Open Mat: "${tarjeta.trim()}"`);

  // ============================================ 5 · a 390px
  const ancho = await page.evaluate(() => document.documentElement.scrollWidth);
  comprobar(ancho <= 390, `a 390px no desborda (${ancho}px)`);

  // ---------- limpieza ----------
  // (la hace `limpiar()`, registrada arriba en `process.on('exit')`, para que
  //  tambien se ejecute cuando un aserto tumba el recorrido a la mitad)
  limpiar();
  comprobar(sesionesDe(A.id) === 0 && sesionesDe(B.id) === 0
    && sql(`select usa_sistema from practicantes where id='${A.id}'`) === antesA
    && sql(`select usa_sistema from practicantes where id='${B.id}'`) === antesB,
    'la base queda como estaba, banderas incluidas');

  console.log(`
######## EL ESPEJO: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
