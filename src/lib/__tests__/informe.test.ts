/**
 * El orden del ranking del Open Mat, con los empates fabricados.
 *
 *     npm run test:informe
 *
 * Lo que se prueba es que el orden es LEXICOGRÁFICO y no una suma ponderada:
 * cada escalón solo entra a decidir cuando el anterior empata. La forma de
 * verlo es fabricar los empates uno a uno — sin ellos, cualquier orden pasa.
 *
 * Y el caso que de verdad separa lexicográfico de ponderado: alguien con UNA
 * sumisión y cero puntos va por delante de alguien con cero sumisiones y
 * cincuenta puntos. Con pesos eso no pasa; con escalones, sí, y es lo que
 * Felipe pidió.
 */
import { armarRanking, caraACara, datoDelDia, ordenarRanking } from '../informe';
import type { FilaRanking, FuentesInforme } from '../informe';

let fallos = 0;
let hechas = 0;
function comprobar(cond: boolean, que: string) {
  hechas++;
  if (cond) { console.log(`PASS  ${que}`); } else { console.log(`FALLO ${que}`); fallos++; }
}

const fila = (p: Partial<FilaRanking> & { nombre: string }): FilaRanking => ({
  practicante_id: p.nombre, cinturon: 'azul', rolls: 3,
  sumisiones: 0, puntos: 0, logros: 0, dominancia: null, sinRolls: false,
  ...p,
});
const orden = (f: FilaRanking[]) => ordenarRanking(f).map((x) => x.nombre).join(' ');

// ============================================ 1 · manda el primer escalón
comprobar(
  orden([
    fila({ nombre: 'Krilin', sumisiones: 1, puntos: 0, logros: 0 }),
    fila({ nombre: 'Goku', sumisiones: 3, puntos: 0, logros: 0 }),
  ]) === 'Goku Krilin',
  'ordena por sumisiones antes que nada',
);

// EL CASO QUE DISTINGUE LEXICOGRÁFICO DE PONDERADO. Con cualquier suma con
// pesos razonable, cincuenta puntos se comen una sumisión. Aquí no.
comprobar(
  orden([
    fila({ nombre: 'Vegeta', sumisiones: 0, puntos: 50, logros: 9 }),
    fila({ nombre: 'Goku', sumisiones: 1, puntos: 0, logros: 0 }),
  ]) === 'Goku Vegeta',
  'una sumisión gana a cincuenta puntos: es orden por escalones, no suma con pesos',
);

// ============================================ 2 · empate en sumisiones
comprobar(
  orden([
    fila({ nombre: 'Krilin', sumisiones: 2, puntos: 4, logros: 9 }),
    fila({ nombre: 'Goku', sumisiones: 2, puntos: 11, logros: 0 }),
  ]) === 'Goku Krilin',
  'con las mismas sumisiones, desempatan los puntos (y los logros no mandan)',
);

// ============================================ 3 · empate en sumisiones y puntos
comprobar(
  orden([
    fila({ nombre: 'Krilin', sumisiones: 2, puntos: 7, logros: 1 }),
    fila({ nombre: 'Goku', sumisiones: 2, puntos: 7, logros: 4 }),
  ]) === 'Goku Krilin',
  'con las mismas sumisiones y los mismos puntos, desempatan los logros',
);

// ============================================ 4 · empate en los tres
// El cuarto escalón no existe todavía, así que aquí NO tiene que pasar nada:
// el orden de entrada se conserva. Si alguien activa la dominancia sin datos,
// esta comprobación se cae y avisa.
comprobar(
  orden([
    fila({ nombre: 'Goku', sumisiones: 1, puntos: 1, logros: 1 }),
    fila({ nombre: 'Krilin', sumisiones: 1, puntos: 1, logros: 1 }),
  ]) === 'Goku Krilin',
  'empate en los tres escalones vivos: se conserva el orden de entrada (sort estable)',
);

// ============================================ 5 · el cuarto escalón, preparado
comprobar(
  orden([
    fila({ nombre: 'Krilin', sumisiones: 1, puntos: 1, logros: 1, dominancia: 10 }),
    fila({ nombre: 'Goku', sumisiones: 1, puntos: 1, logros: 1, dominancia: 300 }),
  ]) === 'Goku Krilin',
  'y el día que haya reloj de posesión, el cuarto escalón desempata sin tocar el orden',
);

// ============================================ 6 · TODOS los participantes
const fuentes: FuentesInforme = {
  sesiones: [{ id: 's1', practicante_id: 'goku' }],
  rolls: [
    { id: 'r1', sesion_id: 's1', oponente_id: 'krilin' },
    { id: 'r2', sesion_id: 's1', oponente_id: 'krilin' },
  ],
  eventos: [
    { roll_id: 'r1', actor: 'yo', tipo: 'sumision', completado: true, segundo_roll: 15 },
    { roll_id: 'r1', actor: 'oponente', tipo: 'sumision', completado: true, segundo_roll: 40 },
    { roll_id: 'r2', actor: 'yo', tipo: 'sumision', completado: false, segundo_roll: 20 },
  ],
  puntos: [
    { roll_id: 'r1', autor_id: 'goku', puntos_autor: 4 },
    { roll_id: 'r2', autor_id: 'goku', puntos_autor: 2 },
  ],
  logros: [{ sesion_id: 's1', practicante_id: 'goku', veces: 3 }],
  inscritos: ['goku', 'krilin', 'freezer'],
  fichas: {
    goku: { nombre: 'Goku', cinturon: 'negra' },
    krilin: { nombre: 'Krilin', cinturon: 'azul' },
    freezer: { nombre: 'Freezer', cinturon: 'morada' },
  },
};
const r = armarRanking(fuentes);
comprobar(r.length === 3, `salen los tres que vinieron, no solo el que puntuó (${r.length})`);
comprobar(r[0].nombre === 'Goku' && r[0].sumisiones === 1 && r[0].puntos === 6
  && r[0].logros === 3,
  'y sus números: 1 sumisión completada, 6 puntos, 3 logros');
comprobar(r.filter((x) => x.sinRolls).length === 2,
  'los dos que no tienen ni un roll salen marcados: es la señal del espejo, no un hueco');
comprobar(r.find((x) => x.nombre === 'Krilin')!.rolls === 0,
  'Krilin sale con 0 rolls aunque aparezca como oponente: su lado no se creó');

// La sumisión que le hicieron A Goku no cuenta como suya.
comprobar(r[0].sumisiones === 1,
  'la sumisión que encajó no se le cuenta a favor: solo `actor = yo`');

// ============================================ 7 · el cara a cara
const parejas = caraACara(fuentes);
comprobar(parejas.length === 1 && parejas[0].veces === 1,
  `dos rolls del mismo combate cuentan como uno (${parejas[0]?.veces})`);
comprobar(parejas[0].a === 'Goku' && parejas[0].b === 'Krilin',
  'y la pareja sale normalizada por nombre, no por quién registró');

// ============================================ 8 · el dato del día
const dato = datoDelDia([
  { titulo: 'EL MOCHILERO', quien: 'Goku', porque: 'mas espaldas tomadas', z: 1.0, valor: 1 },
  { titulo: 'HOUDINI', quien: 'Krilin', porque: 'mas escapes', z: 2.4, valor: 3 },
]);
comprobar(dato?.quien === 'Krilin', 'el dato del día es el de mayor z, no el primero de la lista');
comprobar(datoDelDia([]) === null, 'y sin títulos no se inventa ninguno');

console.log(`\n######## INFORME: ${hechas} comprobaciones, ${fallos} fallan ########`);
process.exit(fallos === 0 ? 0 : 1);
