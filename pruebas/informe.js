/**
 * El informe del Open Mat: que salgan TODOS, en el orden correcto, y que quepa.
 *
 * LO QUE DECIDE:
 *
 *   1. TODOS LOS PARTICIPANTES. Cualquiera con inscripción o con algún roll,
 *      aunque vaya a cero en todo. La cabecera decía «3 asistentes» y la tabla
 *      enseñaba una fila: eso no era un hueco, era una contradicción, y quien
 *      la leía no sabía si el dato estaba mal o si esa gente no hizo nada.
 *   2. EL CERO SE VE Y SE EXPLICA. Alguien con 0 rolls es la señal de que su
 *      mitad del roll observado no se creó. Llevaba días avisando y nadie lo
 *      leía como aviso.
 *   3. EL ORDEN ES EL DE LA REGLA. Aquí no se comprueba la regla —eso es
 *      `npm run test:informe`, con empates fabricados— sino que **lo que pinta
 *      la pantalla es lo que la regla predice sobre estos datos**. Son dos
 *      cosas distintas y las dos hacen falta: la regla puede estar bien y la
 *      pantalla ordenar por otra cosa.
 *   4. QUE QUEPA A 390px con seis personas y cuatro columnas, en tema claro,
 *      que es el de por defecto y el de los informes que se comparten.
 *
 * Escribe de verdad contra Postgres y limpia lo suyo pase lo que pase.
 */
const { chromium } = require('playwright-core');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join('.pruebas', 'perfil-informe');
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

  // ---------- el escenario: SEIS apuntados, tres con rolls ----------
  const esc = await page.evaluate(async () => {
    const hoy = new Date().toISOString().slice(0, 10);
    const { data: me } = await window.__sb.auth.getUser();
    const { data: p } = await window.__sb.from('practicantes')
      .select('id').eq('user_id', me.user.id);
    const yo = p?.[0]?.id;
    const { data: m } = await window.__sb.from('miembros_equipo')
      .select('equipo_id').eq('practicante_id', yo).eq('rol_en_equipo', 'admin');
    const qid = crypto.randomUUID();
    await window.__sb.from('quedadas').insert({
      id: qid, equipo_id: m?.[0]?.equipo_id, titulo: 'Torneo de Cell',
      fecha: hoy, hora_inicio: '10:00', lugar: 'Cell Games', modalidad: 'nogi',
      creado_por: yo,
    });
    const { data: todos } = await window.__sb.from('practicantes')
      .select('id,nombre').order('nombre');
    const gente = (todos ?? []).filter((x) => x.id !== yo).slice(0, 5);
    for (const g of [{ id: yo }, ...gente]) {
      await window.__sb.rpc('apuntarse_a_quedada',
        { p_quedada: qid, p_token: null, p_practicante: g.id });
    }
    return { qid, yo, gente, hoy };
  });
  comprobar(esc.gente.length === 5, `escenario: 6 apuntados a «Torneo de Cell»`);

  const limpiar = () => sql(`
    delete from eventos where roll_id in (select r.id from rolls r
      join sesiones s on s.id=r.sesion_id where s.quedada_id='${esc.qid}');
    delete from rolls where sesion_id in
      (select id from sesiones where quedada_id='${esc.qid}');
    delete from sesiones where quedada_id='${esc.qid}';
    delete from quedada_informes where quedada_id='${esc.qid}';
    delete from inscripciones where quedada_id='${esc.qid}';
    delete from quedadas where id='${esc.qid}';`);
  process.on('exit', () => { try { limpiar(); } catch { /* ya estaba */ } });

  // Tres personas con rolls y sumisiones distintas; las otras tres, a cero.
  // Se escriben por psql porque lo que se prueba aqui es la PRESENTACION, no
  // el camino de registro — que en esta tanda no se toca.
  const [A, B, C] = esc.gente;
  const rollsDe = (pid, cuantas, subs) => {
    const ses = sql(`insert into sesiones (practicante_id, fecha, modalidad, formato,
        academia, quedada_id, notas)
      values ('${pid}', '${esc.hoy}', 'nogi', 'sparring', 'Cell Games',
              '${esc.qid}', 'prueba informe') returning id`);
    for (let i = 0; i < cuantas; i++) {
      const roll = sql(`insert into rolls (sesion_id, oponente_id, orden_en_sesion,
          modalidad, resultado, registrado_por, origen)
        values ('${ses}', '${pid === A.id ? B.id : A.id}', ${i + 1}, 'nogi',
                '${i < subs ? 'sumision_favor' : 'sin_sumision'}', '${esc.yo}', 'observador')
        returning id`);
      if (i < subs) {
        sql(`insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
               tecnica_id, completado, segundo_roll)
             select '${roll}', 'yo', 'sumision', 'montada', 'arriba', 'cuello',
                    id, true, ${40 + i} from tecnicas where slug = 'mata_leao'`);
      }
    }
  };
  rollsDe(A.id, 4, 3);   // el que mas finaliza
  rollsDe(B.id, 4, 1);   // menos sumisiones, pero rueda igual
  rollsDe(C.id, 2, 0);   // vino y no finalizo nada

  // Se cierra para que existan los titulos congelados (el dato del dia sale de
  // su `z`). Es la unica llamada a `cerrar_quedada`, y no se toca la funcion.
  const cerrado = await page.evaluate(async (qid) => {
    const { error } = await window.__sb.rpc('cerrar_quedada',
      { p_quedada: qid, p_regenerar: false });
    return error?.message ?? null;
  }, esc.qid);
  comprobar(!cerrado, `el Open Mat se cierra y congela sus títulos${cerrado ? ' — ' + cerrado : ''}`);

  // ---------- lo que la REGLA predice sobre estos datos ----------
  const esperado = sql(`
    with ses as (select id, practicante_id from sesiones where quedada_id='${esc.qid}'),
    rl as (select r.id, ses.practicante_id from rolls r join ses on ses.id=r.sesion_id),
    gente as (select practicante_id from inscripciones where quedada_id='${esc.qid}'
                and estado='apuntado'
              union select practicante_id from rl)
    select string_agg(p.nombre || ':' || sub || '/' || pts || '/' || log,
                      '|' order by sub desc, pts desc, log desc, p.nombre)
      from (
        select g.practicante_id,
          (select count(*) from eventos e join rl on rl.id=e.roll_id
            where rl.practicante_id=g.practicante_id and e.actor='yo'
              and e.tipo='sumision' and e.completado) as sub,
          coalesce((select sum(v.puntos_autor) from v_puntos_roll v join rl on rl.id=v.roll_id
                     where v.autor_id=g.practicante_id),0) as pts,
          coalesce((select sum(l.veces) from v_logros_sesion l
                     where l.practicante_id=g.practicante_id
                       and l.sesion_id in (select id from ses)),0) as log
          from gente g) x
      join practicantes p on p.id = x.practicante_id`);

  // ---------- la pantalla ----------
  await page.goto(`${APP}/quedadas`);
  await page.getByTestId(`informe-${esc.qid}`).click({ timeout: 30000 });
  // SI NO LLEGA, DECIR QUE HAY EN PANTALLA. Un `Timeout waiting for
  // ranking-vivo` obliga a montar un diagnostico a mano cada vez; el panel ya
  // sabe si esta cargando, si fallo o si esta vacio, asi que lo dice el.
  try {
    await page.getByTestId('ranking-vivo').waitFor({ timeout: 40000 });
  } catch (e) {
    const dentro = await page.getByTestId('informe').count()
      ? await page.getByTestId('informe').innerText() : '(no se abrio el panel)';
    console.log('FALLO el ranking no llego a pintarse. En pantalla habia:');
    const estados = await page.evaluate(() => ['ranking-cargando', 'informe-error',
      'ranking-vivo', 'dato-del-dia', 'cara-a-cara']
      .filter((t) => document.querySelector(`[data-testid="${t}"]`)).join(', '));
    console.log('      estados presentes: ' + (estados || 'ninguno'));
    console.log(dentro.split(String.fromCharCode(10)).slice(0, 40).join(' / '));
    throw e;
  }

  const filas = page.locator('[data-testid^="rank-"]');
  comprobar(await filas.count() === 6,
    `salen los SEIS que estaban en la lista, no solo los que puntuaron (${await filas.count()})`);

  // La fila es una rejilla: [puesto, nombre, sub, pts, log]. Se leen las
  // CELDAS y no el texto entero — con `innerText` la primera linea es el
  // numero de puesto, y la comparacion salia «1|2|3» contra los nombres:
  // un fallo que parecia de orden y era de lectura.
  const enPantalla = (await page.evaluate(() =>
    [...document.querySelectorAll('[data-testid^="rank-"]')].map((f) => {
      const c = f.children;
      const nombre = c[1].childNodes[0].textContent.trim();
      return nombre + ':' + c[2].textContent.trim()
        + '/' + c[3].textContent.trim() + '/' + c[4].textContent.trim();
    }))).join('|');
  comprobar(enPantalla === esperado,
    `y en el orden que dicta la regla\n        pantalla: ${enPantalla}\n        regla:    ${esperado}`);

  comprobar(await page.getByTestId('aviso-sin-rolls').count() === 1,
    'los que no tienen ningún roll salen avisados, no escondidos');
  const aviso = await page.getByTestId('aviso-sin-rolls').innerText();
  comprobar(/guardarle sus rolls/.test(aviso),
    'y el aviso dice qué mirar: es la señal del espejo, no un adorno');

  comprobar(await page.getByTestId('dato-del-dia').count() === 1,
    'el dato del día sale arriba del todo');
  comprobar(await page.getByTestId('cara-a-cara').count() === 1,
    'y el cara a cara, como lista corta y no como matriz');

  // La cabecera cuenta lo mismo que la tabla: era la contradicción original.
  const cabecera = await page.getByTestId('informe').innerText();
  comprobar(/6 en la lista/.test(cabecera),
    'la cabecera cuenta lo mismo que la tabla: seis');

  // ---------- 390px y tema claro ----------
  const tema = await page.evaluate(() =>
    document.documentElement.getAttribute('data-tema'));
  comprobar(tema === 'claro', `el informe se lee en tema claro, que es el de por defecto (${tema})`);

  const ancho = await page.evaluate(() => document.documentElement.scrollWidth);
  comprobar(ancho <= 390, `con seis personas y cuatro columnas no desborda a 390px (${ancho}px)`);
  const desbordes = await page.evaluate(() =>
    [...document.querySelectorAll('[data-testid^="rank-"]')]
      .filter((e) => e.scrollWidth > e.clientWidth + 1).length);
  comprobar(desbordes === 0, 'y ninguna fila se corta por dentro');

  limpiar();
  comprobar(sql(`select count(*) from quedadas where id='${esc.qid}'`) === '0',
    'la base queda como estaba');

  console.log(`\n######## EL INFORME: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
