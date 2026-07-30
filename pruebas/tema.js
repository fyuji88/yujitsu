/**
 * El tema Gullo, a 390px: arranque en claro, interruptor que sobrevive,
 * objetivos tactiles, y los cinco cinturones en los dos temas.
 *
 * Lo que mas importa aqui: que con el SISTEMA EN OSCURO y sin preferencia
 * guardada, la app abra en CLARO. Es el requisito que se rompe solo en cuanto
 * alguien mete un `prefers-color-scheme` en el CSS.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

/** Perfiles del navegador y capturas. Va en .gitignore. */
const SALIDA = '.pruebas';
const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join(process.env.PERFIL ?? SALIDA, 'perfil-tema');

let n = 0;
const ok = (m) => { n++; console.log(`PASS  ${m}`); };
function comprobar(cond, m) {
  if (!cond) { console.log(`FALLO ${m}`); throw new Error(m); }
  ok(m);
}
const lum = (rgb) => {
  const [r, g, b] = rgb.match(/\d+/g).map(Number).map((c) => c / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

async function entrar(ctx) {
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
  return page;
}

(async () => {
  fs.rmSync(PERFIL, { recursive: true, force: true });

  // ---------- 1. Sistema en OSCURO, instalacion nueva: abre en CLARO ----
  // `colorScheme: 'dark'` es exactamente lo que responde
  // `prefers-color-scheme` en el navegador de verdad.
  let ctx = await chromium.launchPersistentContext(PERFIL, {
    channel: 'msedge', headless: true, viewport: { width: 390, height: 844 },
    colorScheme: 'dark',
  });
  let page = await entrar(ctx);
  await page.goto(`${APP}/entreno`);
  await page.getByTestId('sync').waitFor({ timeout: 30000 });

  comprobar(await page.evaluate(() => matchMedia('(prefers-color-scheme: dark)').matches),
    'el sistema simulado esta en oscuro (si no, la prueba no probaria nada)');
  comprobar(await page.evaluate(() => document.documentElement.dataset.tema) === 'claro',
    'con el sistema en oscuro y sin preferencia guardada, la app abre en CLARO');

  const fondoClaro = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  comprobar(lum(fondoClaro) > 0.7, `y el fondo pintado es el hueso, no el oscuro (${fondoClaro})`);

  // ---------- 2. El interruptor, y que sobrevive a recargar -------------
  await page.getByTestId('tema').click();
  await page.waitForTimeout(300);
  comprobar(await page.evaluate(() => document.documentElement.dataset.tema) === 'oscuro',
    'el interruptor pasa a oscuro');
  const fondoOscuro = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  comprobar(lum(fondoOscuro) < 0.05, `y el fondo se vuelve oscuro de verdad (${fondoOscuro})`);

  await page.reload();
  await page.getByTestId('sync').waitFor({ timeout: 30000 });
  comprobar(await page.evaluate(() => document.documentElement.dataset.tema) === 'oscuro',
    'y sobrevive a recargar');

  // Y a cerrar el navegador entero, que es lo que hace el usuario de verdad.
  await ctx.close();
  ctx = await chromium.launchPersistentContext(PERFIL, {
    channel: 'msedge', headless: true, viewport: { width: 390, height: 844 },
    colorScheme: 'dark',
  });
  page = await entrar(ctx);
  await page.goto(`${APP}/entreno`);
  await page.getByTestId('sync').waitFor({ timeout: 30000 });
  comprobar(await page.evaluate(() => document.documentElement.dataset.tema) === 'oscuro',
    'y a cerrar y reabrir el navegador');

  // ---------- 3. Sin destello: el atributo esta puesto antes de pintar ---
  // Si `data-tema` lo pusiera React, el primer HTML llegaria sin el.
  const html = await (await fetch(`${APP}/entreno`)).text();
  comprobar(/dataset\.tema|data-tema/.test(html),
    'el script del tema viaja en el HTML, asi que no hay fogonazo al abrir');

  // ---------- 4. Objetivos tactiles de lo que se toca rodando -----------
  await page.getByTestId('tema').click();          // vuelta a claro
  await page.waitForTimeout(250);
  const pequenos = await page.evaluate(() => {
    const malos = [];
    for (const el of document.querySelectorAll('button, nav.tabs a, select')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;       // oculto
      if (el.closest('.top')) continue;                    // cabecera, no se toca rodando
      if (r.height < 44) malos.push(`${el.className || el.tagName} ${Math.round(r.height)}px`);
    }
    return malos;
  });
  comprobar(pequenos.length === 0,
    `todo lo que se toca rodando llega a 44px${pequenos.length ? ': ' + pequenos.join(', ') : ''}`);

  // ---------- 5. Los cinco cinturones, en los dos temas -----------------
  await page.goto(`${APP}/practicantes`);
  await page.getByTestId('avatar-blanca').first().waitFor({ timeout: 30000 });
  for (const cb of ['blanca', 'azul', 'morada', 'marron', 'negra']) {
    const av = page.getByTestId(`avatar-${cb}`).first();
    comprobar(await av.count() > 0 && await av.isVisible(), `avatar de cinturon ${cb}`);
  }
  const etiqueta = await page.getByTestId('avatar-negra').first()
    .locator('svg').getAttribute('aria-label');
  comprobar(/cinturón negro/.test(etiqueta) && /grado/.test(etiqueta),
    `el avatar dice quien es y que cinturon lleva: "${etiqueta}"`);

  await page.screenshot({ path: path.join(process.env.PERFIL ?? SALIDA, 'tema-claro.png'),
    fullPage: true });
  await page.getByTestId('tema').click();
  await page.waitForTimeout(400);
  await page.screenshot({ path: path.join(process.env.PERFIL ?? SALIDA, 'tema-oscuro.png'),
    fullPage: true });
  ok('los cinco, fotografiados en claro y en oscuro');

  // ---------- 6. El acento del equipo manda sobre el verde por defecto ---
  await page.evaluate(async () => {
    // Sin `.single()`: el stub devuelve el array tal cual, asi que `.single()`
    // deja `data` como lista y `g.id` sale undefined — el update no tocaria
    // ninguna fila y la prueba fallaria por el motivo equivocado.
    const { data: gs } = await window.__sb.from('equipos').select('id').limit(1);
    await window.__sb.from('equipos').update({ color_acento: '#7b3fb8' }).eq('id', gs[0].id);
  });
  await page.reload();
  await page.getByTestId('marca').waitFor({ timeout: 30000 });
  // Se espera a la CONDICION y no a un reloj: el acento llega despues de dos
  // consultas encadenadas, y contra el stub cada una pasa por psql.
  await page.waitForFunction(
    () => getComputedStyle(document.documentElement).getPropertyValue('--marca').trim() === '#7b3fb8',
    null, { timeout: 20000 },
  ).catch(() => {});
  const acento = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue('--marca').trim());
  comprobar(acento === '#7b3fb8', `el equipo cambia el acento (--marca = ${acento})`);

  // Y lo derivado tiene que ser legible sobre el fondo, no el acento a pelo.
  const derivado = await page.evaluate(() => {
    const s = getComputedStyle(document.documentElement);
    return s.getPropertyValue('--marca-texto').trim();
  });
  comprobar(derivado !== '' && derivado !== '#7b3fb8',
    `y el texto de marca se aclara para ser legible (${derivado}, no el acento a pelo)`);

  comprobar((await page.getByTestId('marca').innerText()).includes('ACADEMIA'),
    'y la cabecera lleva el nombre del equipo');

  // Y lo que NO puede cambiar: los colores de datos.
  const datos = await page.evaluate(() => {
    const s = getComputedStyle(document.documentElement);
    return { yo: s.getPropertyValue('--dato-yo').trim(), op: s.getPropertyValue('--dato-op').trim() };
  });
  comprobar(datos.yo !== '#7b3fb8' && datos.op !== '#7b3fb8'
    && /^#[0-9a-f]{6}$/.test(datos.yo),
    `y no toca los colores de datos (yo ${datos.yo}, rival ${datos.op})`);

  // Un valor basura en la base no puede acabar dentro de un style.
  await page.evaluate(async () => {
    const { data: gs } = await window.__sb.from('equipos').select('id').limit(1);
    await window.__sb.from('equipos').update({ color_acento: '#458c50' }).eq('id', gs[0].id);
  });

  console.log(`\n######## TEMA: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
