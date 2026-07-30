'use client';

import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { Logro } from '@/components/Logro';
import { FAMILIAS_ES, textoLogro } from '@/lib/textos/logros.es';

/**
 * La coleccion y el ranking del mes.
 *
 * Nada de esto se guarda: sale de `v_logros_conseguidos`, que se deriva de los
 * eventos. Si mañana se corrige un evento mal registrado, la coleccion se
 * corrige sola.
 */

interface FilaCatalogo {
  clave: string;
  familia: string;
  rareza: 'comun' | 'poco_comun' | 'raro';
  requiere_observador: boolean;
}
interface FilaMia { clave: string; veces: number; veces_verificadas: number }
interface FilaRanking {
  clave: string; practicante_id: string; veces: number; veces_verificadas: number;
}

const ORDEN_FAMILIA = ['defensa', 'ataque', 'estilo', 'constancia', 'cachondeo'];

/** El mes en curso, como lo guarda `v_logros_mes`. */
function mesActual() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
}

// ---------------------------------------------------------------- coleccion

export function Coleccion({ practicanteId, nombre, esMio }: {
  practicanteId: string; nombre: string; esMio: boolean;
}) {
  const [catalogo, setCatalogo] = useState<FilaCatalogo[]>([]);
  const [mios, setMios] = useState<Record<string, FilaMia>>({});
  const [abierta, setAbierta] = useState(false);

  useEffect(() => {
    void supabase().from('logros')
      .select('clave,familia,rareza,requiere_observador')
      .then(({ data }) => { if (data) setCatalogo(data as FilaCatalogo[]); });
  }, []);

  useEffect(() => {
    void supabase().from('v_logros_practicante')
      .select('clave,veces,veces_verificadas')
      .eq('practicante_id', practicanteId)
      .then(({ data }) => {
        setMios(Object.fromEntries(((data ?? []) as FilaMia[]).map((f) => [f.clave, f])));
      });
  }, [practicanteId]);

  if (catalogo.length === 0) return null;

  const tengo = catalogo.filter((l) => (mios[l.clave]?.veces ?? 0) > 0).length;
  const total = catalogo.length;

  return (
    <section className="tarjeta" data-testid="coleccion" style={{ marginTop: 14 }}>
      <h2>{esMio ? 'Tu colección' : `La colección de ${nombre}`}</h2>
      <p className="cap" data-testid="coleccion-cuenta" data-tengo={tengo}>
        {tengo} de {total} conseguidos. Los apagados también se enseñan: un logro
        que no sabes que existe no te motiva.
      </p>

      <button className="f" data-testid="ver-coleccion" onClick={() => setAbierta((v) => !v)}>
        {abierta ? 'Ocultar la colección' : 'Ver la colección'}
      </button>

      {abierta && ORDEN_FAMILIA.map((fam) => {
        const dela = catalogo.filter((l) => l.familia === fam);
        if (dela.length === 0) return null;
        return (
          <div key={fam} style={{ marginTop: 14 }}>
            <div className="cap" style={{ fontWeight: 640 }}>{FAMILIAS_ES[fam] ?? fam}</div>
            <div className="col-grid" data-testid={`familia-${fam}`}>
              {dela
                .sort((a, b) => (mios[b.clave]?.veces ?? 0) - (mios[a.clave]?.veces ?? 0))
                .map((l) => (
                  <Logro key={l.clave} clave={l.clave} rareza={l.rareza}
                    veces={mios[l.clave]?.veces ?? 0}
                    verificadas={mios[l.clave]?.veces_verificadas ?? 0} />
                ))}
            </div>
          </div>
        );
      })}
    </section>
  );
}

// ---------------------------------------------------------------- ranking

export function RankingDelMes({ equipoId, practicanteId, roster }: {
  equipoId: string;
  practicanteId: string;
  roster: Record<string, string>;
}) {
  const [filas, setFilas] = useState<FilaRanking[]>([]);
  /**
   * Por defecto, solo lo verificado.
   *
   * Este interruptor hace un trabajo de mas: sin ningun tutorial, le explica a
   * la gente por que importa el modo observador. Se ve la lista corta, se toca,
   * y se entiende de golpe que los datos que registras tu solo valen menos.
   */
  const [soloVerificados, setSoloVerificados] = useState(true);
  const [cargando, setCargando] = useState(true);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data } = await supabase().from('v_logros_mes')
      .select('clave,practicante_id,veces,veces_verificadas')
      .eq('equipo_id', equipoId).eq('mes', mesActual());
    setFilas((data ?? []) as FilaRanking[]);
    setCargando(false);
  }, [equipoId]);

  useEffect(() => { void cargar(); }, [cargar]);

  const cuenta = (f: FilaRanking) => (soloVerificados ? f.veces_verificadas : f.veces);
  const porLogro = new Map<string, FilaRanking[]>();
  for (const f of filas) {
    if (cuenta(f) === 0) continue;
    const l = porLogro.get(f.clave) ?? [];
    l.push(f);
    porLogro.set(f.clave, l);
  }
  const claves = [...porLogro.keys()].sort((a, b) =>
    Math.max(...porLogro.get(b)!.map(cuenta)) - Math.max(...porLogro.get(a)!.map(cuenta)));

  return (
    <section className="tarjeta" data-testid="ranking-mes">
      <h2>El mes</h2>
      <p className="cap">
        Por veces conseguido. Se reinicia cada mes, así que nadie se queda con
        el trono para siempre.
      </p>

      <button className="f" data-testid="solo-verificados"
        aria-pressed={soloVerificados}
        onClick={() => setSoloVerificados((v) => !v)}>
        {soloVerificados ? '👁 Solo los verificados' : 'Todos, verificados o no'}
      </button>

      {cargando && <p className="cap" style={{ marginTop: 10 }}>Contando…</p>}

      {!cargando && claves.length === 0 && (
        <p className="cap" data-testid="ranking-vacio" style={{ marginTop: 10 }}>
          {soloVerificados
            ? 'Este mes no hay nada verificado todavía. Los logros verificados '
              + 'son los que registró un tercero en modo observador.'
            : 'Este mes todavía no hay logros. Registrad un par de rolls.'}
        </p>
      )}

      {!cargando && claves.map((clave) => {
        const l = porLogro.get(clave)!.slice().sort((a, b) => cuenta(b) - cuenta(a));
        return (
          <div key={clave} style={{ marginTop: 14 }} data-testid={`rank-${clave}`}>
            <div className="cap" style={{ fontWeight: 640 }}>{textoLogro(clave).nombre}</div>
            <div className="rank">
              {l.slice(0, 5).map((f, i) => (
                <div key={f.practicante_id}
                  className={`tr${f.practicante_id === practicanteId ? ' yo' : ''}`}>
                  <span className="pos">{i + 1}</span>
                  <span>{roster[f.practicante_id] ?? '—'}</span>
                  <span className="v">×{cuenta(f)}</span>
                </div>
              ))}
            </div>
          </div>
        );
      })}
    </section>
  );
}
