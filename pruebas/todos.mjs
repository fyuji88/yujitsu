/**
 * Los recorridos en navegador, todos seguidos.
 *
 *   npm run test:navegador
 *
 * QUÉ COMPRUEBAN Y POR QUÉ EXISTEN. El typecheck no ve la máquina de estados
 * del roll, ni si la rampa del heatmap se invierte, ni si un objetivo táctil
 * baja de 44px, ni si la RLS deja ver algo que no debería. Todo eso solo sale
 * recorriendo la app de verdad, a 390px, contra un Postgres con la RLS puesta.
 *
 * ANTES HAY QUE LEVANTAR DOS COSAS, y este script se planta si faltan en vez
 * de fallar con un error raro veinte segundos después:
 *
 *   1. El Postgres local, sembrado:
 *        psql ... -v confirmar=si -f db/pruebas/semilla-demo.sql
 *   2. El stub y el servidor de desarrollo:
 *        PSQL=/ruta/psql.exe PGURL=... python stub-supabase.py &
 *        NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 \
 *        NEXT_PUBLIC_SUPABASE_ANON_KEY=stub npm run dev
 *
 * Los números que comprueban salen de `db/pruebas/semilla-demo.sql`, que es
 * determinista. Si cambias la semilla, cambian.
 */
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));

const RECORRIDOS = [
  ['tema.js', 'el tema: arranque en claro, interruptor, 44px, cinturones'],
  ['analisis.js', 'el análisis contra la semilla: números, heatmap, filtros'],
  ['analisis-tema.js', 'el panel en los dos temas: rampa, verde fuera de los datos'],
  ['enfoques.js', 'los enfoques: contraste contra la RPC, historial, permisos'],
  ['logros.js', 'los logros: coleccion, ranking del mes y feed sin inundar'],
  ['pantalla.js', 'la pantalla encendida: se pide al rodar y se suelta al acabar'],
  ['precisar.js', 'precisar: el chip, y el invariante contra Postgres de verdad'],
  ['cola.js', 'la cola: modo avion, recarga, 4xx que no se reintenta, y el aviso al cerrar'],
  ['admin-quedadas.js', 'administrar un Open Mat: editar, plazas, apuntar a otro, cancelar'],
  ['observador-openmat.js', 'el domingo de Felipe: dos Open Mats, dos sesiones, y el espejo va al suyo'],
];

async function vivo(url) {
  try {
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), 2500);
    await fetch(url, { signal: c.signal });
    clearTimeout(t);
    return true;
  } catch { return false; }
}

const app = await vivo('http://localhost:3000/entreno');
const stub = await vivo('http://127.0.0.1:54321/rest/v1/grupos?select=id');
if (!app || !stub) {
  console.error(`\n  Falta levantar ${!app && !stub ? 'la app y el stub'
    : !app ? 'la app (localhost:3000)' : 'el stub (127.0.0.1:54321)'}.`);
  console.error('  Cómo, en la cabecera de este fichero.\n');
  process.exit(1);
}

let fallos = 0;
for (const [fichero, que] of RECORRIDOS) {
  console.log(`\n──── ${fichero} · ${que}`);
  const r = spawnSync(process.execPath, [join(AQUI, fichero)], { stdio: 'inherit' });
  if (r.status !== 0) fallos++;
}

console.log(fallos === 0
  ? `\n######## LOS ${RECORRIDOS.length} RECORRIDOS PASAN ########\n`
  : `\n######## ${fallos} DE ${RECORRIDOS.length} RECORRIDOS FALLAN ########\n`);
process.exit(fallos === 0 ? 0 : 1);
