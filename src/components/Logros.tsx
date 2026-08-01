'use client';

import { useCallback, useEffect, useState } from 'react';
import type { PostgrestError } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';
import { Logro } from '@/components/Logro';
import { Cargando, PanelError } from '@/components/Estado';
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
  const [fallo, setFallo] = useState<PostgrestError | null>(null);
  const [listo, setListo] = useState(false);
  const [intento, setIntento] = useState(0);

  useEffect(() => {
    void supabase().from('logros')
      .select('clave,familia,rareza,requiere_observador')
      .then(({ data, error }) => {
        if (error) { setFallo(error); return; }
        setCatalogo((data ?? []) as FilaCatalogo[]);
      });
  }, [intento]);

  useEffect(() => {
    void supabase().from('v_logros_practicante')
      .select('clave,veces,veces_verificadas')
      .eq('practicante_id', practicanteId)
      .then(({ data, error }) => {
        // SIN ESTE ERROR, «0 de 28 conseguidos» es lo que se pinta cuando el
        // backend falla. Y esa frase no se lee como un fallo: se lee como que
        // no has conseguido nada.
        if (error) { setFallo(error); return; }
        setMios(Object.fromEntries(((data ?? []) as FilaMia[]).map((f) => [f.clave, f])));
        setListo(true);
      });
  }, [practicanteId, intento]);

  // Antes esto era `if (catalogo.length === 0) return null`, o sea que un fallo
  // hacía DESAPARECER la sección entera. Es el peor de los tres estados malos:
  // no hay nada que mirar, así que nadie lo reporta nunca.
  if (fallo) {
    return (
      <section className="tarjeta" style={{ marginTop: 14 }}>
        <PanelError error={fallo} que="la colección de logros" testid="coleccion-error"
          onReintentar={() => { setFallo(null); setIntento((n) => n + 1); }} />
      </section>
    );
  }
  if (catalogo.length === 0 || !listo) {
    return <Cargando que="la colección" testid="coleccion-cargando" />;
  }

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
  const [fallo, setFallo] = useState<PostgrestError | null>(null);

  /**
   * Este es el que hay que vigilar. `v_logros_mes` tarda 3,2 s medido con el
   * rol `authenticated`, contra un `statement_timeout` de 8 s: hoy cabe, pero
   * con dos veces y media más de historia deja de caber. Y cuando deje, lo que
   * se pintaría sin este error es «Este mes todavía no hay logros».
   */
  const cargar = useCallback(async () => {
    setCargando(true); setFallo(null);
    const { data, error } = await supabase().from('v_logros_mes')
      .select('clave,practicante_id,veces,veces_verificadas')
      .eq('equipo_id', equipoId).eq('mes', mesActual());
    if (error) { setFallo(error); setCargando(false); return; }
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

      {/* Antes que el vacío, siempre: «este mes no hay logros» y «no pude
          contarlos» son cosas distintas y solo una es culpa del equipo. */}
      {!cargando && fallo && (
        <PanelError error={fallo} que="el ranking del mes" testid="ranking-error"
          onReintentar={() => void cargar()} />
      )}

      {!cargando && !fallo && claves.length === 0 && (
        <p className="cap" data-testid="ranking-vacio" style={{ marginTop: 10 }}>
          {soloVerificados
            ? 'Este mes no hay nada verificado todavía. Los logros verificados '
              + 'son los que registró un tercero en modo observador.'
            : 'Este mes todavía no hay logros. Registrad un par de rolls.'}
        </p>
      )}

      {!cargando && !fallo && claves.map((clave) => {
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
