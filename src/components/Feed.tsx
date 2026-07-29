'use client';

import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

/**
 * El feed del grupo.
 *
 * No hay tabla de entradas: `v_feed` deriva de lo que ya pasó, así que si
 * mañana se corrige una sesión el feed se corrige solo. Aquí no se agrega
 * nada — todo viene de `feed()`, incluidas las reacciones ya contadas.
 *
 * Se pagina por `cuando`, no por offset: con offset, si alguien registra algo
 * mientras lees, la página siguiente repite o se salta filas.
 */

/** Cerrados a propósito. Con selector libre, en un mes hay cuarenta. */
const EMOJIS = ['🔥', '💪', '😂', '🫡', '🥋'] as const;

interface Reaccion { emoji: string; cuantos: number; mia: boolean }

interface Item {
  grupo_id: string;
  grupo: string;
  tipo: string;
  referencia_id: string;
  practicante_id: string | null;
  quien: string;
  cuando: string;
  datos: Record<string, unknown>;
  reacciones: Reaccion[];
}

function haceCuanto(iso: string) {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return 'ahora';
  const m = s / 60;
  if (m < 60) return `hace ${Math.round(m)} min`;
  const h = m / 60;
  if (h < 24) return `hace ${Math.round(h)} h`;
  const d = h / 24;
  if (d < 7) return `hace ${Math.round(d)} d`;
  return new Date(iso).toISOString().slice(0, 10);
}

const ICONO: Record<string, string> = {
  sesion: '🥋', posicion: '🗺️', reto: '🏅',
  quedada: '📅', inscripcion: '✋', miembro: '👋',
};

function texto(i: Item) {
  const d = i.datos;
  switch (i.tipo) {
    case 'sesion': {
      const n = Number(d.rolls ?? 0);
      return <>
        <b>{i.quien}</b> entrenó · {n} {n === 1 ? 'roll' : 'rolls'}
        {d.quedada ? <> en {String(d.quedada)}</> : null}
      </>;
    }
    case 'posicion':
      return <><b>{i.quien}</b> estrenó <b>{String(d.nombre)}</b> por primera vez</>;
    case 'reto':
      return <><b>{i.quien}</b> completó el reto {String(d.reto)}</>;
    case 'quedada':
      return <>
        <b>{i.quien}</b> montó <b>{String(d.titulo)}</b> para el {String(d.fecha)}
        {d.lugar ? <> en {String(d.lugar)}</> : null}
      </>;
    case 'inscripcion':
      return <>
        <b>{i.quien}</b> se apuntó a {String(d.titulo)}
        {d.externo ? ' (viene de otro gimnasio)' : ''}
      </>;
    case 'miembro':
      return <><b>{i.quien}</b> entró en el grupo</>;
    default:
      return <>{i.quien}</>;
  }
}

/**
 * `practicanteId` llega por parámetro y no se busca aquí: la pantalla que
 * monta el feed ya lo tiene resuelto, y pedirlo otra vez por cada reacción es
 * una llamada de red por gusto.
 */
export function Feed({ practicanteId }: { practicanteId: string }) {
  const [items, setItems] = useState<Item[]>([]);
  const [cargando, setCargando] = useState(true);
  const [masHay, setMasHay] = useState(true);
  const [ocupado, setOcupado] = useState(false);

  const traer = useCallback(async (antes: string | null) => {
    const { data } = await supabase().rpc('feed', { p_antes: antes, p_limite: 20 });
    const nuevos = (data ?? []) as Item[];
    setItems((v) => (antes ? [...v, ...nuevos] : nuevos));
    setMasHay(nuevos.length === 20);
    setCargando(false);
  }, []);

  useEffect(() => { void traer(null); }, [traer]);

  /**
   * La reacción apunta a la FILA DE ORIGEN (`tipo` + `referencia_id`), nunca a
   * una fila del feed: el feed es una vista y sus filas no tienen identidad
   * estable. Si apuntara ahí, al cambiar la vista las reacciones se
   * despegarían de su contenido.
   */
  async function reaccionar(i: Item, emoji: string) {
    const mia = i.reacciones.find((r) => r.emoji === emoji)?.mia;
    setOcupado(true);
    const sb = supabase();
    if (mia) {
      await sb.from('reacciones').delete()
        .eq('practicante_id', practicanteId)
        .eq('item_tipo', i.tipo).eq('referencia_id', i.referencia_id).eq('emoji', emoji);
    } else {
      await sb.from('reacciones').insert({
        practicante_id: practicanteId,
        item_tipo: i.tipo, referencia_id: i.referencia_id, emoji,
      });
    }
    setOcupado(false);
    void traer(null);
  }

  if (cargando) return <p className="empty">Cargando el feed…</p>;

  if (!items.length) {
    return (
      <p className="hint" data-testid="feed-vacio">
        Todavía no ha pasado nada en el grupo. En cuanto alguien registre un entreno
        o monte una quedada, aparecerá aquí.
      </p>
    );
  }

  return (
    <div data-testid="feed">
      {items.map((i) => (
        <div className="fila" key={`${i.tipo}-${i.referencia_id}-${i.cuando}`}
          style={{ alignItems: 'flex-start', marginTop: 8 }}>
          <span style={{ fontSize: 17, lineHeight: 1.2 }}>{ICONO[i.tipo] ?? '•'}</span>
          <span className="n">
            {texto(i)}
            <small>{haceCuanto(i.cuando)}</small>
            <span style={{ display: 'flex', gap: 4, marginTop: 7, flexWrap: 'wrap' }}>
              {EMOJIS.map((e) => {
                const r = i.reacciones.find((x) => x.emoji === e);
                return (
                  <button key={e} disabled={ocupado}
                    data-testid={`reaccion-${e}`}
                    onClick={() => void reaccionar(i, e)}
                    style={{
                      font: 'inherit', fontSize: 13, cursor: 'pointer',
                      background: r?.mia ? 'var(--marca-suave)' : 'transparent',
                      border: `1px solid ${r?.mia ? 'var(--marca)' : 'var(--borde)'}`,
                      borderRadius: 999, padding: '2px 7px', color: 'var(--texto-2)',
                      opacity: r ? 1 : 0.55,
                    }}>
                    {e}{r ? ` ${r.cuantos}` : ''}
                  </button>
                );
              })}
            </span>
          </span>
        </div>
      ))}

      {masHay && (
        <div style={{ marginTop: 12 }}>
          <button className="ghost" data-testid="feed-mas" disabled={ocupado}
            onClick={() => void traer(items[items.length - 1].cuando)}>
            Ver más
          </button>
        </div>
      )}
    </div>
  );
}
