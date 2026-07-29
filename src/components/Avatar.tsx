import type { Cinturon } from '@/lib/database.types';

/**
 * El avatar de alguien: sus iniciales dentro de su cinturón.
 *
 * Un cinturón de BJJ **no es un anillo de un color**. Lleva una barra donde
 * van los grados —negra en los cinturones de color y ROJA en el negro—, y esa
 * barra es lo que resuelve los dos extremos del problema:
 *
 *  - El **negro** sobre el fondo oscuro sería un aro invisible. Con su barra
 *    roja se identifica al instante, y de paso queda más fiel al objeto real.
 *  - El **blanco** sobre el hueso claro desaparecía igual. Con la barra negra
 *    y un filo de 1px por dentro y por fuera, se ve en los dos temas.
 *
 * Los grados van repartidos DENTRO de la barra y no pegados a un lado, para
 * que cuatro se distingan de uno sin ponerse a contarlos.
 *
 * El relleno y las iniciales usan tokens y no colores fijos, así que el avatar
 * sigue al tema sin enterarse de que existe: en una lista de doce personas eso
 * son doce suscripciones al tema que no hacen falta.
 *
 * La insignia del arquetipo va AL LADO, nunca dentro del aro: dentro tapa los
 * grados, que es justo lo que el aro está intentando comunicar.
 */

interface Pinta { aro: string; barra: string; filo: string }

/** Los cinco cinturones. Colores del objeto real, no del tema. */
const CINTURONES: Record<Cinturon, Pinta> = {
  blanca: { aro: '#eeede9', barra: '#141413', filo: 'rgba(0,0,0,.35)' },
  azul:   { aro: '#2a6cc0', barra: '#141413', filo: 'rgba(0,0,0,.25)' },
  morada: { aro: '#6f4499', barra: '#141413', filo: 'rgba(0,0,0,.25)' },
  marron: { aro: '#6b4429', barra: '#141413', filo: 'rgba(0,0,0,.25)' },
  negra:  { aro: '#141413', barra: '#d02a2a', filo: 'rgba(255,255,255,.30)' },
};

/** Para el `aria-label`: en castellano el cinturón es masculino. */
const NOMBRE_CINTURON: Record<Cinturon, string> = {
  blanca: 'blanco', azul: 'azul', morada: 'morado', marron: 'marrón', negra: 'negro',
};

function iniciales(nombre: string) {
  const trozos = nombre.trim().split(/\s+/).filter(Boolean);
  if (trozos.length === 0) return '?';
  return (trozos[0][0] + (trozos[1]?.[0] ?? '')).toUpperCase();
}

export function Avatar({
  nombre, cinturon, grados = 0, tam = 44, insignia, pie = false,
}: {
  nombre: string;
  cinturon: Cinturon;
  grados?: number;
  /** Lado del avatar en px. 44 es el mínimo táctil; 76 para fichas. */
  tam?: number;
  /** La insignia del arquetipo, si la hay. Se pinta al lado, no dentro. */
  insignia?: string;
  /** Enseñar el nombre y el cinturón debajo. */
  pie?: boolean;
}) {
  const c = CINTURONES[cinturon];

  // Geometría en el lienzo de 76 del diseño; `tam` solo escala el SVG.
  const R = 30, CX = 38, CY = 38;
  const CIRC = 2 * Math.PI * R;
  const BARRA = 42;                         // longitud de la barra, en arco
  const desde = 90 - ((BARRA / CIRC) * 360) / 2;   // centrada abajo

  // Los grados, repartidos dentro de la barra.
  const a0 = desde + 8, a1 = desde + (BARRA / CIRC) * 360 - 8;
  const marcas = Array.from({ length: Math.max(0, Math.min(grados, 6)) }, (_, i) => {
    const t = grados === 1 ? 0.5 : i / (grados - 1);
    const ang = ((a0 + (a1 - a0) * t) * Math.PI) / 180;
    return {
      x1: CX + (R - 5.5) * Math.cos(ang), y1: CY + (R - 5.5) * Math.sin(ang),
      x2: CX + (R + 5.5) * Math.cos(ang), y2: CY + (R + 5.5) * Math.sin(ang),
    };
  });

  const etiqueta = `${nombre}, cinturón ${NOMBRE_CINTURON[cinturon]}`
    + (grados > 0 ? `, ${grados} ${grados === 1 ? 'grado' : 'grados'}` : ', sin grados');

  return (
    <span className="av" data-testid={`avatar-${cinturon}`}>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
        <svg width={tam} height={tam} viewBox="0 0 76 76" role="img" aria-label={etiqueta}>
          <circle cx={CX} cy={CY} r={R - 5.5} fill="var(--superficie-2)" />
          <circle cx={CX} cy={CY} r={R} fill="none" stroke={c.aro} strokeWidth={9} />
          <circle cx={CX} cy={CY} r={R} fill="none" stroke={c.barra} strokeWidth={9}
            strokeDasharray={`${BARRA} ${(CIRC - BARRA).toFixed(1)}`}
            transform={`rotate(${desde.toFixed(1)} ${CX} ${CY})`} />
          {marcas.map((m, i) => (
            <line key={i} x1={m.x1.toFixed(1)} y1={m.y1.toFixed(1)}
              x2={m.x2.toFixed(1)} y2={m.y2.toFixed(1)}
              stroke="#fff" strokeWidth={2.6} strokeLinecap="butt" />
          ))}
          {/* El filo, por dentro y por fuera. Es lo que salva al blanco sobre
              el hueso y al negro sobre el fondo oscuro. */}
          <circle cx={CX} cy={CY} r={R + 4.6} fill="none" stroke={c.filo} strokeWidth={1} />
          <circle cx={CX} cy={CY} r={R - 4.6} fill="none" stroke={c.filo} strokeWidth={1} />
          <text x={CX} y={CY + 1} textAnchor="middle" dominantBaseline="middle"
            fill="var(--texto)" fontFamily="system-ui,sans-serif"
            fontSize={17} fontWeight={700}>{iniciales(nombre)}</text>
        </svg>
        {insignia && <span aria-hidden style={{ fontSize: tam * 0.28 }}>{insignia}</span>}
      </span>
      {pie && (
        <>
          <span className="av-nm">{nombre}</span>
          <span className="av-cb">
            {NOMBRE_CINTURON[cinturon]}
            {grados > 0 && ` · ${grados} ${grados === 1 ? 'grado' : 'grados'}`}
          </span>
        </>
      )}
    </span>
  );
}
