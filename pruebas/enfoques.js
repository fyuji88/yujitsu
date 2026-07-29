/**
 * Enfoques, a 390px: escribir uno, ver el contraste, cambiarlo, cerrarlo.
 *
 * Lo que de verdad se comprueba aqui es el CONTRASTE: que el numero que sale
 * en pantalla es el que dice Postgres, no uno que la pantalla se invente. Por
 * eso la comprobacion se hace contra la RPC, no contra una constante.
 */
const { chromium } = require('playwright-core');
const path = require('node:path');
const fs = require('node:fs');

/** Perfiles del navegador y capturas. Va en .gitignore. */
const SALIDA = '.pruebas';
const APP = 'http://localhost:3000';
const STUB = 'http://127.0.0.1:54321';
const PERFIL = path.join(process.env.PERFIL ?? SALIDA, 'perfil-enfoques');

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

  const s = await (await fetch(`${STUB}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  })).json();
  await page.goto(`${APP}/login`);
  await page.waitForFunction(() => !!window.__sb, null, { timeout: 30000 });
  await page.evaluate(async (t) => {
    await window.__sb.auth.setSession(
      { access_token: t.access_token, refresh_token: t.refresh_token });
  }, s);

  // Se limpia lo que dejara una corrida anterior: si no, "enfoques
  // anteriores (2)" cuenta tambien los de la vez pasada y falla por una razon
  // que no tiene que ver con lo que se esta probando.
  await page.goto(`${APP}/analisis`);
  await page.waitForFunction(() => !!window.__sb, null, { timeout: 30000 });
  await page.evaluate(async () => {
    const { data } = await window.__sb.from('enfoques').select('id');
    for (const e of data ?? []) await window.__sb.from('enfoques').delete().eq('id', e.id);
  });
  await page.reload();
  await page.getByTestId('enfoque').waitFor({ timeout: 30000 });

  // Quien soy, segun la propia pantalla. Preguntarselo a la base con
  // `.not('user_id','is',null)` no vale: el stub no traduce ese filtro y
  // devuelve el primer practicante cualquiera, que no es el de la sesion.
  const mio = await page.getByTestId('selector-practicante').inputValue();

  // ---------- 1. Sin enfoque: invitacion, no hueco vacio ----------
  comprobar(await page.getByTestId('enfoque-nuevo').isVisible(),
    'sin enfoque, se ofrece escribir uno');

  // ---------- 2. Escribirlo ----------
  await page.getByTestId('enfoque-nuevo').click();
  await page.getByTestId('enfoque-editor').waitFor();
  await page.getByTestId('enfoque-texto')
    .fill('Jugar mas De la Riva y dejar de correr a la media guardia');
  await page.getByTestId('enf-pos-de_la_riva').click();
  await page.getByTestId('enf-pos-media_guardia').click();
  // Y una que en estos datos esta a cero, para que salga el aviso. La espalda
  // no valia: en los datos demo tiene 3 rolls, y entonces no hay nada que
  // avisar — que es el comportamiento correcto, pero no el que se prueba aqui.
  await page.getByTestId('enf-pos-arana').click();
  comprobar(await page.getByTestId('enf-pos-de_la_riva')
    .getAttribute('aria-pressed') === 'true', 'la posicion marcada se queda marcada');

  await page.getByTestId('enfoque-guardar').click();
  // Se espera el PERIODO y no las barras: un enfoque nuevo empieza hoy, y lo
  // normal es que hoy no haya rolls todavia. Ese es justo el estado que hay
  // que ver primero.
  await page.getByTestId('enfoque-periodo').waitFor({ timeout: 15000 });
  ok('el enfoque se guarda y se pinta');

  // Que haya rolls hoy o no depende de la semilla, asi que se comprueba la
  // regla y no el caso: sin rolls en el periodo se dice con palabras, y con
  // rolls se pintan las barras. Lo que no vale es "0 de 0".
  const sinRolls = await page.getByTestId('enfoque-sin-rolls').isVisible().catch(() => false);
  if (sinRolls) {
    ok('recien escrito y sin rolls todavia, lo dice en vez de enseñar 0 de 0');
  } else {
    comprobar(await page.getByTestId('enfoque-posiciones').isVisible(),
      'con rolls ya dentro del periodo, el contraste se pinta desde el primer dia');
  }

  // ---------- 3 y 4. El contraste, y el aviso de lo que no se ha tocado ----
  // Se retrasa el `desde` para que el periodo coja los rolls de verdad; es la
  // unica forma de ver la frase que justifica la feature.
  await page.evaluate(async (id) => {
    await window.__sb.from('enfoques').update({ desde: '2020-01-01' })
      .eq('practicante_id', id);
  }, mio);
  await page.reload();
  await page.getByTestId('enfoque-posiciones').waitFor({ timeout: 30000 });

  // Lo que pinta la pantalla tiene que ser lo que dice Postgres, no una
  // cuenta que la pantalla se invente: se compara contra la RPC en crudo.
  const real = await page.evaluate(async (id) => {
    const { data } = await window.__sb.rpc('enfoque_contraste', { p_practicante: id });
    return data;
  }, mio);
  const barras = await page.getByTestId('enfoque-posiciones').innerText();
  for (const p of real.posiciones) {
    comprobar(barras.includes(`${p.rolls} de ${real.rolls}`),
      `${p.nombre}: la pantalla dice "${p.rolls} de ${real.rolls}", igual que la RPC`);
  }

  await page.getByTestId('enfoque').screenshot({
    path: path.join(process.env.PERFIL ?? SALIDA, 'enfoque-contraste.png') });

  const aviso = await page.getByTestId('enfoque-aviso').innerText().catch(() => '');
  comprobar(/no aparece[n]? ni una vez/.test(aviso),
    `sale el aviso de lo declarado y no jugado: "${aviso.trim().slice(0, 90)}…"`);

  // ---------- 5. Cambiar de enfoque no borra el anterior ----------
  await page.getByTestId('enfoque-cambiar').click();
  await page.getByTestId('enfoque-editor').waitFor();
  await page.getByTestId('enfoque-texto').fill('Ahora la espalda');
  await page.getByTestId('enfoque-guardar').click();
  await page.getByTestId('enfoque-historia').waitFor({ timeout: 15000 });
  comprobar((await page.getByTestId('enfoque-historia').innerText())
    .includes('anteriores (1)'), 'cambiar de enfoque manda el viejo al historial');

  await page.getByTestId('enfoque-historia').click();
  comprobar((await page.getByTestId('enfoque').innerText()).includes('De la Riva'),
    'y el historial enseña lo que decia el anterior');

  // ---------- 6. El de otro se ve, pero sin botones ----------
  const otros = await page.evaluate(async () => {
    const { data } = await window.__sb.from('practicantes').select('id,nombre')
      .order('nombre');
    return data;
  });
  const otro = otros.find((p) => p.id !== mio);
  await page.getByTestId('selector-practicante').selectOption(otro.id);
  await page.waitForTimeout(1500);
  const hayTarjeta = await page.getByTestId('enfoque').isVisible().catch(() => false);
  if (hayTarjeta) {
    comprobar(!(await page.getByTestId('enfoque-cambiar').isVisible().catch(() => false)),
      `en la ficha de ${otro.nombre} no hay boton de editar su enfoque`);
  } else {
    ok(`${otro.nombre} no tiene enfoque y no se enseña una tarjeta vacia`);
  }

  // ---------- 7. Darlo por terminado ----------
  await page.getByTestId('selector-practicante').selectOption(mio);
  await page.getByTestId('enfoque-cerrar').waitFor({ timeout: 15000 });
  await page.getByTestId('enfoque-cerrar').click();
  await page.waitForTimeout(1500);
  comprobar(await page.getByTestId('enfoque-nuevo').isVisible(),
    'al terminarlo se vuelve a ofrecer escribir uno');
  comprobar((await page.getByTestId('enfoque-historia').innerText())
    .includes('anteriores (2)'), 'y los dos cerrados quedan en el historial');

  await page.screenshot({
    path: path.join(process.env.PERFIL ?? SALIDA, 'enfoque.png'), fullPage: true });

  console.log(`\n######## ENFOQUES: ${n} comprobaciones ########`);
  await ctx.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
