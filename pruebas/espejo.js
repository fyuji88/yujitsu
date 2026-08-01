/**
 * El roll espejo: dos rolls, siempre.
 *
 * LA CAUSA, medida. `espejar_roll()` tenia una guarda —si el oponente no tenia
 * `usa_sistema`, salia devolviendo `null`— y `registrar_roll_observado`
 * contestaba `creado: true` igual. No fallaba nada: no se hacia y no se decia.
 * De los 63 rolls observados huerfanos de produccion, 62 salieron de ahi.
 *
 * Y LO QUE DE VERDAD SE APRENDIO. El primer intento fue sacar esa casilla a la
 * ficha para poder marcarla. Al dia siguiente volvieron a salir ocho de ocho
 * huerfanos, porque nadie la marco. Un mecanismo no es un arreglo cuando el
 * modo de fallo es silencioso: la guarda se fue entera en `bjj_38`.
 *
 * Este recorrido comprueba el liston con el caso que fallaba —el companero SIN
 * `usa_sistema`—, de punta a punta y por la pantalla:
 *   dos rolls · dos sesiones · las dos en el mismo Open Mat.
 *
 * El invariante que lo vigila para siempre esta en `db/pruebas/espejo.sql`.
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

  /**
   * `hoy` LO DICE POSTGRES, no el navegador.
   *
   * `v_mi_quedada_hoy` filtra por `q.fecha = current_date` del servidor, y
   * `new Date().toISOString()` da la fecha UTC. Entre medianoche y las dos de
   * la madrugada en Espana no son el mismo dia: la quedada se creaba con la
   * fecha de ayer, la vista no la traia y el chip del Open Mat no aparecia
   * nunca. Fallo a las 00:44, y el sintoma —un `waitFor` agotado— manda a
   * mirar la pantalla, que estaba bien.
   */
  const HOY = sql('select current_date');

  // ---------- escenario: un Open Mat hoy y dos compañeros ----------
  const esc = await page.evaluate(async (hoy) => {
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
  }, HOY);
  const [A, B] = esc.otros;
  comprobar(!!esc.qid && !!A && !!B, `escenario: «Battle for Namek» y ${esc.otros.length} compañeros`);

  // EL CASO QUE FALLABA: el companero sin `usa_sistema`. Antes de bjj_38 esto
  // bastaba para perder su mitad del roll.
  //
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

  // ============================================ 2 · EL LISTON
  sql(`update practicantes set usa_sistema = false where id in ('${A.id}','${B.id}')`);
  await page.getByTestId(`obsA-${A.nombre}`).click();
  await page.getByTestId(`op-${B.nombre}`).click();
  await page.getByTestId('fin-roll').click();
  await page.getByTestId('resumen-observado').waitFor({ timeout: 20000 });
  await page.goto(`${APP}/quedadas`);
  await page.waitForTimeout(2500);

  comprobar(rollsDe(A.id) === 1 && rollsDe(B.id) === 1,
    `un roll observado deja DOS rolls, uno por jugador (${rollsDe(A.id)} y ${rollsDe(B.id)})`);
  comprobar(sesionesDe(A.id) === 1 && sesionesDe(B.id) === 1,
    'y las dos sesiones, una de cada uno');
  comprobar(sql(`select count(*) from sesiones where quedada_id='${esc.qid}'`) === '2',
    'las dos colgadas del mismo Open Mat, o el informe contaria un solo lado');
  comprobar(sql(`select count(*) from (select par_evento_id from eventos e
      join rolls r on r.id = e.roll_id join sesiones s on s.id = r.sesion_id
     where s.quedada_id='${esc.qid}' group by par_evento_id having count(*)=2) t`) !== '0',
    'y los eventos van emparejados por par_evento_id');

  // Y sin depender de la casilla: es el caso que fallaba, con ella apagada.
  comprobar(sql(`select usa_sistema from practicantes where id='${B.id}'`) === 'f',
    'con «usa la app» APAGADO en el compañero — que es exactamente lo que fallaba');

  // ============================================ 3 · el invariante lo respalda
  comprobar(sql(`select count(*) from (select r.par_id from rolls r
      where r.origen='observador' and r.oponente_id is not null
        and r.created_at >= '2026-08-02'
      group by r.par_id having count(*) <> 2) x`) === '0',
    'y el invariante de db/pruebas/espejo.sql no ve ningún par a medias');

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
