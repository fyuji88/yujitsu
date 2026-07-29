'use client';

import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { DOMINANTES, GUARDIAS_TODAS, NOMBRE_POSICION } from '@/lib/bjj';
import type { EnfoqueRow, Posicion, TecnicaRow } from '@/lib/database.types';

/**
 * Lo que alguien está trabajando, contrastado con lo que de verdad hizo.
 *
 * La gracia no es apuntar un propósito —eso es una nota en el móvil—, es que
 * las posiciones y las técnicas van estructuradas, así que la app puede
 * responder: dijiste De la Riva y la has jugado en 2 de 34 rolls.
 *
 * El contraste mira **el periodo del enfoque**, no el filtro de arriba de la
 * pantalla de análisis. Si el enfoque empezó hace tres semanas, la pregunta es
 * qué hiciste en esas tres semanas, y da igual qué ventana esté seleccionada.
 * Eso hay que decirlo en pantalla o el número parece incoherente con el resto.
 */

interface Contraste {
  enfoque: {
    id: string; desde: string; hasta: string | null; texto: string | null;
    posiciones: Posicion[]; tecnicas: string[];
  };
  rolls: number;
  posiciones: { codigo: Posicion; nombre: string; rolls: number }[];
  tecnicas: { id: string; nombre: string; veces: number }[];
}

/** Igual que en la pantalla de análisis: con poco volumen, cuentas y no %. */
const MINIMO_PARA_PORCENTAJES = 20;

const hoy = () => new Date().toISOString().slice(0, 10);

const fecha = (s: string) =>
  new Date(s + 'T00:00:00').toLocaleDateString('es-ES', { day: 'numeric', month: 'short' });

/** Las 24 posiciones en tres bloques, para que el selector no sea una lista. */
const BLOQUES: { titulo: string; pos: Posicion[] }[] = [
  { titulo: 'Guardias', pos: GUARDIAS_TODAS },
  { titulo: 'Dominantes', pos: DOMINANTES },
  {
    titulo: 'Otras',
    pos: (Object.keys(NOMBRE_POSICION) as Posicion[]).filter(
      (p) => !GUARDIAS_TODAS.includes(p) && !DOMINANTES.includes(p),
    ),
  },
];

export function Enfoque({ practicanteId, esMio, nombre }: {
  practicanteId: string;
  esMio: boolean;
  nombre: string;
}) {
  const [contraste, setContraste] = useState<Contraste | null>(null);
  const [historia, setHistoria] = useState<EnfoqueRow[]>([]);
  const [tecnicas, setTecnicas] = useState<TecnicaRow[]>([]);
  const [editando, setEditando] = useState(false);
  const [verHistoria, setVerHistoria] = useState(false);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const recargar = useCallback(async () => {
    setCargando(true);
    const [c, h] = await Promise.all([
      supabase().rpc('enfoque_contraste', { p_practicante: practicanteId }),
      supabase().from('enfoques').select('*')
        .eq('practicante_id', practicanteId)
        .order('desde', { ascending: false })
        .order('created_at', { ascending: false }),
    ]);
    setContraste((c.data as Contraste | null) ?? null);
    setHistoria((h.data ?? []) as EnfoqueRow[]);
    setCargando(false);
  }, [practicanteId]);

  useEffect(() => { setEditando(false); setVerHistoria(false); void recargar(); }, [recargar]);

  useEffect(() => {
    if (!esMio) return;
    void supabase().from('tecnicas').select('id,slug,nombre,tipo,objetivo_default')
      .order('nombre')
      .then(({ data }) => { if (data) setTecnicas(data as TecnicaRow[]); });
  }, [esMio]);

  const guardar = useCallback(async (
    texto: string, posiciones: Posicion[], tecs: string[],
  ) => {
    setError(null);
    const activo = contraste?.enfoque;
    // Cambiar de enfoque cierra el anterior en vez de borrarlo: el historial
    // es la mitad del valor. Se cierra hoy, que es la verdad —estuvo en vigor
    // hasta hoy— y deja de ser el activo porque activo es `hasta is null`.
    if (activo) {
      const { error: e } = await supabase().from('enfoques')
        .update({ hasta: hoy() }).eq('id', activo.id);
      if (e) { setError(e.message); return; }
    }
    const { error: e2 } = await supabase().from('enfoques').insert({
      practicante_id: practicanteId,
      desde: hoy(),
      texto: texto.trim() || null,
      posiciones,
      tecnicas: tecs,
    });
    if (e2) { setError(e2.message); return; }
    setEditando(false);
    await recargar();
  }, [contraste, practicanteId, recargar]);

  const cerrar = useCallback(async () => {
    const activo = contraste?.enfoque;
    if (!activo) return;
    await supabase().from('enfoques').update({ hasta: hoy() }).eq('id', activo.id);
    await recargar();
  }, [contraste, recargar]);

  if (cargando) return null;

  // Sin enfoque y no es tuyo: no se enseña un hueco vacío de otro.
  if (!contraste && !esMio && historia.length === 0) return null;

  return (
    <section className="tarjeta" data-testid="enfoque" style={{ marginTop: 14 }}>
      <h2 style={{ marginBottom: 2 }}>
        {esMio ? 'Lo que estás trabajando' : `Lo que trabaja ${nombre}`}
      </h2>

      {error && <p className="err">{error}</p>}

      {editando ? (
        <Editor
          inicial={contraste?.enfoque}
          tecnicas={tecnicas}
          onGuardar={guardar}
          onCancelar={() => setEditando(false)}
        />
      ) : contraste ? (
        <Vista c={contraste} esMio={esMio} nombre={nombre}
          onCambiar={() => setEditando(true)} onCerrar={cerrar} />
      ) : (
        <>
          <p className="cap">
            {esMio
              ? 'Apunta qué estás trabajando estas semanas —una guardia, una '
                + 'sumisión, una idea— y la app te dirá cuánto lo has jugado de verdad.'
              : `${nombre} no tiene ningún enfoque abierto.`}
          </p>
          {esMio && (
            <button className="f" data-testid="enfoque-nuevo"
              onClick={() => setEditando(true)}>
              Escribir mi enfoque
            </button>
          )}
        </>
      )}

      {historia.length > (contraste ? 1 : 0) && (
        <div style={{ marginTop: 12 }}>
          <button className="f" data-testid="enfoque-historia"
            onClick={() => setVerHistoria((v) => !v)}>
            {verHistoria ? 'Ocultar los anteriores' : `Enfoques anteriores (${
              historia.length - (contraste ? 1 : 0)})`}
          </button>
          {verHistoria && (
            <ul className="lista" style={{ marginTop: 8 }}>
              {historia
                .filter((e) => e.id !== contraste?.enfoque.id)
                .map((e) => (
                  <li key={e.id}>
                    <div className="cap">
                      {fecha(e.desde)} — {e.hasta ? fecha(e.hasta) : 'en curso'}
                    </div>
                    <div>{e.texto || <i>sin nota</i>}</div>
                    {e.posiciones.length > 0 && (
                      <div className="cap">
                        {e.posiciones.map((p) => NOMBRE_POSICION[p]).join(' · ')}
                      </div>
                    )}
                  </li>
                ))}
            </ul>
          )}
        </div>
      )}
    </section>
  );
}

function Vista({ c, esMio, nombre, onCambiar, onCerrar }: {
  c: Contraste; esMio: boolean; nombre: string;
  onCambiar: () => void; onCerrar: () => void;
}) {
  const { enfoque: e, rolls } = c;
  const pct = rolls >= MINIMO_PARA_PORCENTAJES;
  const quien = esMio ? 'Lo has' : `${nombre} lo ha`;

  return (
    <>
      <p className="cap" data-testid="enfoque-periodo">
        Desde el {fecha(e.desde)} {e.hasta ? `hasta el ${fecha(e.hasta)}` : '· en curso'}
        {' · '}{rolls} {rolls === 1 ? 'roll' : 'rolls'} en ese periodo
      </p>

      {e.texto && <p style={{ margin: '8px 0', fontStyle: 'italic' }}>«{e.texto}»</p>}

      {rolls === 0 ? (
        <p className="cap" data-testid="enfoque-sin-rolls">
          Todavía no hay ningún roll registrado desde que empezó. En cuanto
          haya, aquí sale cuánto de esto se ha jugado de verdad.
        </p>
      ) : (
        <>
          {c.posiciones.length > 0 && (
            <ul className="contraste" data-testid="enfoque-posiciones">
              {c.posiciones.map((p) => (
                <Barra key={p.codigo} nom={p.nombre} n={p.rolls} total={rolls}
                  pct={pct} unidad="rolls" />
              ))}
            </ul>
          )}

          {c.tecnicas.length > 0 && (
            <ul className="contraste" data-testid="enfoque-tecnicas">
              {c.tecnicas.map((t) => (
                <Barra key={t.id} nom={t.nombre} n={t.veces} total={rolls}
                  pct={false} unidad="veces" />
              ))}
            </ul>
          )}

          {/* La frase que justifica la feature entera. Solo aparece cuando hay
              algo declarado que no se ha tocado — decir "bien hecho" cuando sí
              se ha tocado sería ruido. */}
          {(() => {
            const cero = [
              ...c.posiciones.filter((p) => p.rolls === 0).map((p) => p.nombre),
              ...c.tecnicas.filter((t) => t.veces === 0).map((t) => t.nombre),
            ];
            if (cero.length === 0) return null;
            return (
              <p className="cap" data-testid="enfoque-aviso" style={{ marginTop: 8 }}>
                {quien} dicho, pero {cero.join(' y ')}
                {cero.length === 1 ? ' no aparece' : ' no aparecen'} ni una vez en
                {' '}{rolls === 1 ? 'el roll' : `los ${rolls} rolls`} de este periodo.
              </p>
            );
          })()}
        </>
      )}

      {esMio && (
        <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
          <button className="f" data-testid="enfoque-cambiar" onClick={onCambiar}>
            Cambiar de enfoque
          </button>
          <button className="f" data-testid="enfoque-cerrar" onClick={onCerrar}>
            Darlo por terminado
          </button>
        </div>
      )}
    </>
  );
}

function Barra({ nom, n, total, pct, unidad }: {
  nom: string; n: number; total: number; pct: boolean; unidad: 'rolls' | 'veces';
}) {
  const p = total > 0 ? Math.round((n / total) * 100) : 0;
  return (
    <li>
      <div className="enf-fila">
        <span>{nom}</span>
        <b data-testid={`contraste-${nom}`}>
          {unidad === 'rolls'
            ? <>{n} de {total}{pct && <> · {p}%</>}</>
            : <>{n} {n === 1 ? 'vez' : 'veces'}</>}
        </b>
      </div>
      <div className="raya"><i style={{ width: `${unidad === 'rolls' ? p : Math.min(p, 100)}%` }} /></div>
    </li>
  );
}

function Editor({ inicial, tecnicas, onGuardar, onCancelar }: {
  inicial?: Contraste['enfoque'];
  tecnicas: TecnicaRow[];
  onGuardar: (texto: string, pos: Posicion[], tec: string[]) => Promise<void>;
  onCancelar: () => void;
}) {
  const [texto, setTexto] = useState(inicial?.texto ?? '');
  const [pos, setPos] = useState<Posicion[]>(inicial?.posiciones ?? []);
  const [tec, setTec] = useState<string[]>(inicial?.tecnicas ?? []);
  const [guardando, setGuardando] = useState(false);

  const alterna = <T,>(v: T, l: T[], set: (x: T[]) => void) =>
    set(l.includes(v) ? l.filter((x) => x !== v) : [...l, v]);

  return (
    <div data-testid="enfoque-editor">
      <label className="cap" htmlFor="enf-texto">
        En una frase: qué quieres trabajar y por qué
      </label>
      <textarea id="enf-texto" className="f" rows={2} value={texto}
        data-testid="enfoque-texto"
        placeholder="Jugar más De la Riva en vez de correr a la media guardia"
        onChange={(ev) => setTexto(ev.target.value)}
        style={{ width: '100%', marginBottom: 10 }} />

      <p className="cap">
        Y marca las posiciones y técnicas concretas. Esto es lo que permite
        contrastarlo después con lo que hiciste de verdad; sin marcar nada, el
        enfoque es solo una nota.
      </p>

      {BLOQUES.map((b) => (
        <div key={b.titulo} style={{ marginTop: 8 }}>
          <div className="cap">{b.titulo}</div>
          <div className="chips">
            {b.pos.map((p) => (
              <button key={p} className="chip" aria-pressed={pos.includes(p)}
                data-testid={`enf-pos-${p}`}
                onClick={() => alterna(p, pos, setPos)}>
                {NOMBRE_POSICION[p]}
              </button>
            ))}
          </div>
        </div>
      ))}

      <div style={{ marginTop: 10 }}>
        <div className="cap">Técnicas</div>
        <div className="chips">
          {tecnicas.map((t) => (
            <button key={t.id} className="chip" aria-pressed={tec.includes(t.id)}
              data-testid={`enf-tec-${t.slug}`}
              onClick={() => alterna(t.id, tec, setTec)}>
              {t.nombre}
            </button>
          ))}
        </div>
      </div>

      <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
        <button className="f primario" data-testid="enfoque-guardar"
          disabled={guardando}
          onClick={async () => {
            setGuardando(true);
            await onGuardar(texto, pos, tec);
            setGuardando(false);
          }}>
          {guardando ? 'Guardando…' : inicial ? 'Cambiar de enfoque' : 'Guardar'}
        </button>
        <button className="f" onClick={onCancelar}>Cancelar</button>
      </div>
      {inicial && (
        <p className="cap" style={{ marginTop: 6 }}>
          El enfoque de ahora no se borra: se cierra hoy y pasa al historial.
        </p>
      )}
    </div>
  );
}
