'use client';

import { TRAZOS_LOGRO, TRAZO_POR_DEFECTO } from '@/lib/logros-iconos';
import { textoLogro } from '@/lib/textos/logros.es';

/**
 * Una casilla de logro.
 *
 * TRES NIVELES DE BRILLO, y ninguno es un degradado:
 *
 *  - **Apagado**: lo que aún no tienes. Se enseña igualmente, con su
 *    descripción. Un logro que no sabes que existe no te motiva — ver LA
 *    CADENA apagada es lo que hace que un martes intentes justo eso. Es la
 *    misma razón por la que el heatmap deja las celdas vacías a la vista.
 *  - **Conseguido**: el acento de marca, y la cuenta al lado.
 *  - **Raro**: además, filo dorado. Solo el borde: un icono con degradado
 *    brilla siempre y deja de significar nada.
 *
 * El brillo de verdad va en el MOMENTO, no en el icono: `recien` enciende una
 * animación corta al desbloquear. Medio segundo que se recuerda, en vez de un
 * adorno permanente que se vuelve invisible.
 */
export function Logro({
  clave, veces = 0, verificadas = 0, rareza = 'comun', recien = false, tam = 44,
}: {
  clave: string;
  veces?: number;
  verificadas?: number;
  rareza?: 'comun' | 'poco_comun' | 'raro';
  recien?: boolean;
  tam?: number;
}) {
  const t = textoLogro(clave);
  const trazos = TRAZOS_LOGRO[clave] ?? TRAZO_POR_DEFECTO;
  const conseguido = veces > 0;

  return (
    <div className={`logro${conseguido ? ' on' : ''}${rareza === 'raro' ? ' raro' : ''}`
      + `${recien ? ' recien' : ''}`}
      data-testid={`logro-${clave}`} data-veces={veces}>
      <svg width={tam} height={tam} viewBox="0 0 24 24" fill="none"
        stroke="currentColor" strokeWidth={1.75} strokeLinecap="round"
        strokeLinejoin="round" role="img"
        aria-label={`${t.nombre}${conseguido ? `, conseguido ${veces} ${veces === 1 ? 'vez' : 'veces'}`
          : ', todavía no conseguido'}`}>
        {trazos.map((d, i) => <path key={i} d={d} />)}
      </svg>
      <div className="logro-nm">{t.nombre}</div>
      {conseguido ? (
        <div className="logro-n">
          ×{veces}
          {/* La procedencia se enseña, no se esconde: es parte del dato. */}
          {verificadas > 0 && (
            <span className="logro-ver" title={`${verificadas} registrados por un observador`}>
              {' '}· {verificadas} 👁
            </span>
          )}
        </div>
      ) : (
        <div className="logro-d">{t.descripcion}</div>
      )}
    </div>
  );
}
