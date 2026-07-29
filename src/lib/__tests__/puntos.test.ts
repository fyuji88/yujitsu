/**
 * Los casos del fixture, en TypeScript.
 *
 *   npm run test:puntos
 *
 * El mismo fichero de casos lo ejecuta `db/pruebas/puntos.sql` contra Postgres.
 * Si los dos no dan los mismos números, es que el cálculo en vivo y el del
 * histórico se han separado, y eso es un bug aunque los dos "funcionen".
 */
import { readFileSync } from 'node:fs';
import { espejar, puntuar, type EventoPuntuable } from '../puntos';

interface Caso {
  nombre: string;
  descripcion: string;
  esperado: { a: number; b: number };
  eventos: EventoPuntuable[];
}

const fixture = JSON.parse(
  readFileSync('src/lib/__fixtures__/puntos.json', 'utf8'),
) as { casos: Caso[] };

let fallos = 0;

function comprobar(ok: boolean, mensaje: string) {
  console.log(`${ok ? 'PASS ' : 'FALLO'}  ${mensaje}`);
  if (!ok) fallos++;
}

for (const caso of fixture.casos) {
  const m = puntuar(caso.eventos);
  comprobar(
    m.a === caso.esperado.a && m.b === caso.esperado.b,
    `${caso.nombre}: ${m.a}-${m.b} (esperado ${caso.esperado.a}-${caso.esperado.b})`,
  );

  // El invariante del espejo, en todos los casos y no solo en uno: el mismo
  // roll visto desde el otro lado tiene que dar el tanteo cambiado de sitio.
  // Si falla, o el espejo o la puntuación están mal, y da igual cuál.
  const e = puntuar(espejar(caso.eventos));
  comprobar(
    e.a === m.b && e.b === m.a,
    `${caso.nombre}: espejo ${e.a}-${e.b} es el reflejo de ${m.a}-${m.b}`,
  );
}

// El desglose tiene que cuadrar con el total: es lo que se enseña en pantalla.
for (const caso of fixture.casos) {
  const m = puntuar(caso.eventos);
  const suma = (actor: 'yo' | 'oponente') => m.desglose
    .filter((d) => d.actor === actor)
    .reduce((n, d) => n + d.puntos, 0);
  comprobar(
    suma('yo') === m.a && suma('oponente') === m.b,
    `${caso.nombre}: el desglose suma el total`,
  );
}

console.log(
  fallos === 0
    ? `\n######## ${fixture.casos.length} CASOS, TODO OK ########`
    : `\n######## ${fallos} COMPROBACIONES FALLADAS ########`,
);
process.exit(fallos === 0 ? 0 : 1);
