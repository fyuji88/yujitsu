/**
 * El domingo de Felipe, en la pantalla: dos Open Mats el mismo dia.
 *
 * POR QUE ESTE RECORRIDO EXISTE. `bjj_35` mete `p_quedada` en
 * `registrar_roll_observado()`, y eso el typecheck no lo ve: la RPC se llama
 * por nombre desde una cola en IndexedDB. Lo unico que prueba que la cadena
 * entera funciona —pantalla, cola, RPC, espejo, sesion— es recorrerla.
 *
 * LO QUE DECIDE:
 *
 *   1. Observando en el Open Mat de las 10:00, la sesion sale colgada de ESE
 *      Open Mat. Antes salia suelta: por el camino del observador no se
 *      enganchaba nada, y por eso los informes salian vacios.
 *   2. La del COMPANERO tambien, sin que nadie se lo pase. `espejar_roll` lee
 *      la quedada de la sesion del original. Si esto fallara, el companero
 *      saldria del informe con cero rolls.
 *   3. Observando despues en el de las 16:00, sale una sesion DISTINTA. Es el
 *      caso que motivo todo: dos Open Mats, misma modalidad, mismo sitio.
 *   4. Y «Suelto» sigue existiendo: entrenar sin Open Mat es lo normal.
 *
 * Escribe de verdad contra Postgres y limpia lo suyo al acabar.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join('.pruebas', 'perfil-obs-openmat');

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

  // ---------- DOS Open Mats hoy, misma modalidad y mismo sitio ----------
  const esc = await page.evaluate(async () => {
    const hoy = new Date().toISOString().slice(0, 10);
    const { data: me } = await window.__sb.auth.getUser();
    const { data: p } = await window.__sb.from('practicantes')
      .select('id').eq('user_id', me.user.id);
    const yo = p?.[0]?.id;
    const { data: m } = await window.__sb.from('miembros_equipo')
      .select('equipo_id').eq('practicante_id', yo).eq('rol_en_equipo', 'admin');
    const equipo = m?.[0]?.equipo_id;
    const q = [];
    for (const [titulo, hora] of [['OM manana', '10:00'], ['OM tarde', '16:00']]) {
      const id = crypto.randomUUID();
      const { error } = await window.__sb.from('quedadas').insert({
        id, equipo_id: equipo, titulo, fecha: hoy, hora_inicio: hora,
        lugar: 'Mismo sitio', modalidad: 'nogi', creado_por: yo,
      });
      // Y APUNTARSE: `v_mi_quedada_hoy` solo trae los Open Mats a los que vas,
      // que es lo correcto — el selector de la pantalla no puede ofrecer todos
      // los del equipo. Sin esto, los chips no existen.
      const { error: ei } = await window.__sb.rpc('apuntarse_a_quedada',
        { p_quedada: id, p_token: null, p_practicante: yo });
      q.push({ id, titulo, error: error?.message ?? ei?.message });
    }
    // Dos companeros CON cuenta: sin eso no hay espejo que comprobar.
    const { data: todos } = await window.__sb.from('practicantes')
      .select('id,nombre,usa_sistema');
    const otros = (todos ?? []).filter((x) => x.id !== yo && x.usa_sistema).slice(0, 2);
    return { q, otros, yo, hoy };
  });
  comprobar(esc.q.every((x) => !x.error) && esc.otros.length >= 2,
    `escenario: dos Open Mats hoy y ${esc.otros.length} companeros con cuenta`);

  const [A, B] = esc.otros;

  /** Las sesiones de alguien hoy, con su Open Mat. */
  const sesionesDe = (pid) => page.evaluate(async (x) => {
    const { data } = await window.__sb.from('sesiones')
      .select('id,quedada_id,modalidad').eq('practicante_id', x.pid).eq('fecha', x.hoy);
    return data ?? [];
  }, { pid, hoy: esc.hoy });

  /** Una observacion entera, del boton 👁 hasta que la cola la suelta. */
  async function observar(quedadaId) {
    await page.goto(`${APP}/entreno`);
    await page.getByTestId('observar').first().click();
    await page.getByTestId('obs-mod-nogi').click();
    await page.getByTestId(quedadaId ? `obs-quedada-${quedadaId}` : 'obs-quedada-ninguna')
      .click();
    await page.getByTestId(`obsA-${A.nombre}`).click();
    await page.getByTestId(`op-${B.nombre}`).click();
    await page.getByTestId('fin-roll').click();
    await page.getByTestId('resumen-observado').waitFor({ timeout: 20000 });
    // Salir de la pantalla suelta la cola: el efecto que la retiene se limpia
    // al desmontar. Ver `retenerCola` en src/lib/sync.ts.
    await page.goto(`${APP}/quedadas`);
    await page.waitForTimeout(2500);
  }

  // ================================================= 1 · el de la manana
  await observar(esc.q[0].id);
  let sesA = await sesionesDe(A.id);
  const deQ1 = sesA.filter((x) => x.quedada_id === esc.q[0].id);
  comprobar(deQ1.length === 1,
    `observando en «${esc.q[0].titulo}», la sesion sale colgada de ESE Open Mat`);

  const sesB = await sesionesDe(B.id);
  comprobar(sesB.some((x) => x.quedada_id === esc.q[0].id),
    'y la del companero tambien, sin que nadie se la pase: la lee el espejo');

  // ================================================= 2 · el de la tarde
  await observar(esc.q[1].id);
  sesA = await sesionesDe(A.id);
  const deQ2 = sesA.filter((x) => x.quedada_id === esc.q[1].id);
  comprobar(deQ2.length === 1 && deQ2[0].id !== deQ1[0].id,
    'y en el de la tarde sale una sesion DISTINTA, no la de la manana');

  comprobar((await sesionesDe(A.id)).filter((x) => x.quedada_id === esc.q[0].id).length === 1
    && deQ1[0].id !== deQ2[0].id,
    'la de la manana sigue donde estaba: nada arrastro sus rolls al segundo');

  // ================================================= 3 · «Suelto», y su letra pequena
  //
  // OJO CON LO QUE SE AFIRMA AQUI. Elegir «Suelto» NO crea una sesion suelta si
  // ya hay una sesion de ese dia: con `p_quedada` nulo, `sesion_del_dia`
  // reutiliza la primera que encuentre, y eso es DELIBERADO — es lo que hace
  // que nulo se comporte igual que antes de bjj_34, que era el requisito.
  //
  // La consecuencia es que un roll marcado «Suelto» despues de haber observado
  // en un Open Mat acaba contando en ese Open Mat. Esta anotado como sabido
  // roto; lo que no puede pasar es que la prueba diga que no pasa.
  const antes = (await sesionesDe(A.id)).length;
  await observar(null);
  sesA = await sesionesDe(A.id);
  comprobar(sesA.length === antes,
    '«Suelto» no abre sesion nueva si ya hay una del dia: nulo = «me da igual», '
    + 'no «sin Open Mat» (bjj_34, a proposito — y con su precio)');

  // ================================================= 4 · a 390px
  const ancho = await page.evaluate(() => document.documentElement.scrollWidth);
  comprobar(ancho <= 390, `a 390px no desborda (${ancho}px)`);

  // ---------- limpieza ----------
  //
  // POR `psql` Y NO POR EL CLIENTE, y no es pereza: lo que este recorrido crea
  // son las sesiones de OTRAS DOS PERSONAS —eso es el modo observador— y la RLS
  // no deja que las borre quien no es su dueño. Que ese borrado falle es la
  // politica haciendo su trabajo; el primer intento se estrello justo ahi.
  //
  // Las escribio `registrar_roll_observado`, que es SECURITY DEFINER: entran
  // por una puerta que no tiene vuelta desde el navegador.
  const { execFileSync } = require('node:child_process');
  const PSQL = process.env.PSQL || 'psql';
  const PGURL = process.env.PGURL || 'postgresql://postgres@127.0.0.1:55432/bjj';
  // Y si no está, se dice CÓMO. La primera vez esto salió como
  // `spawnSync psql ENOENT` después de siete comprobaciones en verde, que no
  // le cuenta a nadie que lo que falta es una variable de entorno.
  try {
    execFileSync(PSQL, [PGURL, '-Atq', '-c', 'select 1'], { encoding: 'utf8' });
  } catch {
    console.log('FALLO no encuentro psql para limpiar lo que ha escrito este recorrido.\n'
      + `      PSQL="${PSQL}"  PGURL="${PGURL}"\n`
      + '      Este recorrido escribe las sesiones de OTRAS DOS personas por la RPC del\n'
      + '      observador, y la RLS no deja borrarlas desde el navegador. Exporta PSQL y\n'
      + '      PGURL —los mismos con los que arrancas el stub— y vuelve a correrlo.');
    process.exit(1);
  }
  const sql = `
    delete from eventos where roll_id in (
      select r.id from rolls r join sesiones s on s.id = r.sesion_id
       where s.practicante_id in ('${A.id}','${B.id}') and s.fecha = '${esc.hoy}');
    delete from rolls where sesion_id in (
      select id from sesiones
       where practicante_id in ('${A.id}','${B.id}') and fecha = '${esc.hoy}');
    delete from sesiones
     where practicante_id in ('${A.id}','${B.id}') and fecha = '${esc.hoy}';
    delete from inscripciones where quedada_id in ('${esc.q[0].id}','${esc.q[1].id}');
    delete from quedadas where id in ('${esc.q[0].id}','${esc.q[1].id}');
    select count(*) from sesiones
     where practicante_id in ('${A.id}','${B.id}') and fecha = '${esc.hoy}';`;
  const quedan = Number(
    execFileSync(PSQL, [PGURL, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', sql],
                 { encoding: 'utf8' }).trim().split('\n').pop());
  comprobar(quedan === 0, 'la base queda como estaba: sesiones y Open Mats borrados');

  console.log(`\n######## EL OBSERVADOR Y EL OPEN MAT: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
