'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import type { PostgrestError } from '@supabase/supabase-js';
import { PanelError } from '@/components/Estado';
import {
  arrancarSync, observarSync, retenerCola, vaciarCola, type EstadoSync,
} from '@/lib/sync';
import {
  contarPendientes, descartar, olvidarDatosDelUsuario, reintentarYa, todoLoPendiente,
  type EnvioPendiente,
} from '@/lib/db';
import { BotonTema, useTema } from '@/components/Tema';
import { aplicarAcento } from '@/lib/tema';
import { TEXTOS } from '@/lib/textos/es';
import type { PracticanteRow } from '@/lib/database.types';

export interface Sesion {
  userId: string;
  practicante: PracticanteRow;
}

/**
 * Marco común: comprueba la sesión, arranca el vaciado de la cola y pinta la
 * píldora de sincronización. Las páginas reciben ya el practicante resuelto,
 * así no tienen que preocuparse de la autenticación.
 */
export function Marco(
  { titulo, sub, children, pie, sesion }:
  {
    titulo: string;
    sub?: string;
    children: (s: Sesion) => React.ReactNode;
    pie?: React.ReactNode;
    sesion?: never;
  },
) {
  const router = useRouter();
  const ruta = usePathname();
  const [s, setS] = useState<Sesion | null>(null);
  const [cargando, setCargando] = useState(true);
  /**
   * Por qué no hay ficha. «No existe» y «no pude preguntarlo» se pintaban igual.
   *
   * Y no era un matiz: el mensaje de «no tienes ficha» dice «sal y vuelve a
   * entrar», y salir llama a `olvidarDatosDelUsuario()`, que **borra la cola de
   * salida**. O sea que un fallo de red le pedía a la gente que tirara los rolls
   * que aún no había subido. De todos los estados vacíos mal puestos, este era
   * el único que además destruía datos.
   */
  const [falloFicha, setFalloFicha] = useState<PostgrestError | null>(null);
  const [intentoFicha, setIntentoFicha] = useState(0);
  const [verCola, setVerCola] = useState(false);
  const [sync, setSync] = useState<EstadoSync>({ enCola: 0, enviando: false, error: null, conError: 0 });
  const [saliendo, setSaliendo] = useState(false);
  const [pendientesAlSalir, setPendientesAlSalir] = useState<number | null>(null);
  const [equipo, setEquipo] = useState<{ nombre: string; color_acento: string | null } | null>(null);
  const [tema] = useTema();

  useEffect(() => {
    let vivo = true;
    (async () => {
      const { data } = await supabase().auth.getUser();
      if (!vivo) return;
      if (!data.user) { router.replace('/login'); return; }

      const { data: p, error } = await supabase()
        .from('practicantes').select('*').eq('user_id', data.user.id).maybeSingle();
      if (!vivo) return;
      if (error) setFalloFicha(error);
      else if (p) { setFalloFicha(null); setS({ userId: data.user.id, practicante: p as PracticanteRow }); }
      setCargando(false);
    })();
    return () => { vivo = false; };
  }, [router, intentoFicha]);

  useEffect(() => {
    // La PWA: sin esto la app no abre sin conexion ni se puede instalar.
    if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
      void navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
    arrancarSync();
    const parar = observarSync(setSync);
    void contarPendientes().then((n) => setSync((v) => ({ ...v, enCola: n })));
    return () => { parar(); };
  }, []);

  // El equipo activo: da la marca de la cabecera y el acento del tema.
  // Dos consultas planas en vez de un `select('equipos(...)')`: el embedding de
  // PostgREST aquí ahorra un viaje y cuesta que esto no se pueda probar contra
  // el stub, que no lo sabe hacer. Por un viaje de red al abrir, no compensa.
  useEffect(() => {
    if (!s) return;
    (async () => {
      const { data: m } = await supabase()
        .from('miembros_equipo').select('equipo_id')
        .eq('estado', 'activo').limit(1).maybeSingle();
      const id = (m as { equipo_id: string } | null)?.equipo_id;
      if (!id) return;
      const { data: g } = await supabase()
        .from('equipos').select('nombre,color_acento').eq('id', id).maybeSingle();
      if (g) setEquipo(g as { nombre: string; color_acento: string | null });
    })();
  }, [s]);

  /**
   * El acento del equipo, cada vez que cambia el equipo o el tema.
   *
   * El equipo elige **solo el acento**: `aplicarAcento()` deriva de ahí el
   * color de texto legible y la tinta del botón, midiendo el contraste contra
   * el fondo del tema actual. Una academia puede poner el color que quiera y
   * no puede dejarse la interfaz ilegible — y no toca nunca los colores de
   * datos, que es lo que protege el heatmap.
   */
  useEffect(() => {
    aplicarAcento(equipo?.color_acento, tema);
  }, [equipo, tema]);

  /**
   * Salir.
   *
   * Lo importante no es cerrar la sesión —eso es una línea— sino no dejarle al
   * siguiente cosas del anterior. Primero se intenta vaciar la cola: los rolls
   * que queden dentro se subirían con la sesión de quien entre después, y la
   * RLS los rechazaría por ajenos. Si no se puede vaciar (sin cobertura), se
   * dice cuántos hay y se pregunta, en vez de tirarlos a la callada.
   */
  async function pedirSalir() {
    setSaliendo(true);
    retenerCola(false);          // por si veníamos del resumen del observador
    await vaciarCola();
    const quedan = await contarPendientes();
    setSaliendo(false);
    if (quedan > 0) { setPendientesAlSalir(quedan); return; }
    await salir();
  }

  async function salir() {
    setSaliendo(true);
    await olvidarDatosDelUsuario();
    await supabase().auth.signOut();
    router.replace('/login');
  }

  /**
   * LA PILDORA DICE LA VERDAD, Y DISTINGUE DOS COSAS QUE NO SON LA MISMA:
   *
   *   - `sin subir`  todavia no ha llegado, pero va a llegar: la cola lo sigue
   *                  intentando con espera creciente.
   *   - `con error`  el servidor lo ha rechazado y reintentar no lo arregla.
   *                  Necesita que una persona mire y decida.
   *
   * Meterlo todo en un "error al sincronizar" hacia que lo primero pareciera
   * grave y lo segundo pareciera pasajero. Son justo al reves.
   */
  const pastilla = sync.conError > 0
    ? { cls: 'sync err', txt: `⚠ ${sync.conError} con error` }
    : sync.enviando
      ? { cls: 'sync', txt: '↑ subiendo…' }
      : sync.enCola > 0
        ? { cls: 'sync off', txt: `● ${sync.enCola} sin subir` }
        : { cls: 'sync ok', txt: '✓ al día' };
  const hayCola = sync.enCola + sync.conError > 0;

  return (
    <div className="phone">
      <div className="top">
        <div style={{ minWidth: 0 }}>
          {/* La marca del equipo, encima del título: es lo único de la app que
              lleva el acento a pelo. Sin equipo todavía, la app se nombra a sí
              misma. */}
          <span className="marca" data-testid="marca">
            {(equipo?.nombre ?? 'yujitsu').toUpperCase()}
          </span>
          <div className="t1">{titulo}</div>
          <div className="t2">{sub ?? (s ? s.practicante.nombre : '…')}</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          {/* Tocable SOLO si hay algo que mirar: una pildora que se puede
              pulsar y no lleva a ningun sitio enseña a no pulsarla. */}
          {hayCola ? (
            <button className={pastilla.cls} data-testid="sync"
              style={{ border: 0, font: 'inherit', cursor: 'pointer' }}
              onClick={() => setVerCola(true)}>{pastilla.txt}</button>
          ) : (
            <span className={pastilla.cls} data-testid="sync">{pastilla.txt}</span>
          )}
          <BotonTema />
          {s && (
            <button className="salir" data-testid="salir" disabled={saliendo}
              onClick={() => void pedirSalir()}>Salir</button>
          )}
        </div>
      </div>

      {verCola && <DetalleCola onCerrar={() => setVerCola(false)} />}

      <main>
        {pendientesAlSalir !== null && (
          <div className="state" data-testid="aviso-salir" style={{ marginBottom: 14 }}>
            <div className="lbl">Antes de salir</div>
            <div className="pos" style={{ fontSize: 17 }}>
              {pendientesAlSalir} {pendientesAlSalir === 1 ? 'cosa sin subir' : 'cosas sin subir'}
            </div>
            <p className="hint" style={{ margin: '8px 0 0' }}>
              No hay conexión, o Supabase no las acepta. Si sales ahora se pierden: no
              se pueden dejar para el siguiente que entre, porque se subirían con su
              cuenta y la base las rechazaría por ajenas.
            </p>
            <div style={{ display: 'flex', gap: 9, marginTop: 14 }}>
              <button className="ghost" data-testid="salir-cancelar"
                onClick={() => setPendientesAlSalir(null)}>Me quedo</button>
              <button className="ghost" data-testid="salir-descartar"
                style={{ color: 'var(--error)' }} disabled={saliendo}
                onClick={() => void salir()}>Salir y descartarlas</button>
            </div>
          </div>
        )}

        {cargando && <p className="empty">Cargando…</p>}
        {/* PRIMERO EL FALLO, y sin sugerir salir: salir borra la cola. */}
        {!cargando && !s && falloFicha && (
          <PanelError error={falloFicha} que="tu ficha" testid="marco-error"
            onReintentar={() => { setCargando(true); setIntentoFicha((n) => n + 1); }} />
        )}
        {!cargando && !s && !falloFicha && (
          <p className="err" data-testid="marco-sin-ficha">
            Tu cuenta existe pero no tiene ficha de practicante. Sal y vuelve a entrar.
          </p>
        )}
        {s && children(s)}
      </main>

      {pie}

      {/* Cinco pestañas caben en 390px con etiquetas cortas: "Gente" en vez de
          "Practicantes", que se comía el ancho de dos. */}
      <nav className="tabs">
        <Link href="/entreno" className={ruta === '/entreno' ? 'on' : ''}>Entreno</Link>
        <Link href="/quedadas" className={ruta === '/quedadas' ? 'on' : ''}>{TEXTOS.quedadas}</Link>
        <Link href="/analisis" className={ruta === '/analisis' ? 'on' : ''}>Análisis</Link>
        <Link href="/equipo" className={ruta === '/equipo' ? 'on' : ''}>{TEXTOS.equipo}</Link>
        <Link href="/practicantes" className={ruta === '/practicantes' ? 'on' : ''}>Gente</Link>
      </nav>
    </div>
  );
}

/**
 * Qué hay sin subir, desde cuándo, y qué se puede hacer con ello.
 *
 * EXISTE PORQUE UN NÚMERO NO BASTA. "3 sin subir" tranquiliza o alarma según el
 * día; lo que hace falta es poder mirar qué son, desde cuándo esperan, y —si el
 * servidor los rechaza— leer el motivo y decidir. Descartar es una decisión de
 * una persona, nunca de la cola: es la única forma de que algo salga de aquí
 * sin haber llegado.
 */
function DetalleCola({ onCerrar }: { onCerrar: () => void }) {
  const [filas, setFilas] = useState<EnvioPendiente[]>([]);
  const [ocupado, setOcupado] = useState(false);

  const cargar = useCallback(async () => {
    setFilas(await todoLoPendiente());
  }, []);
  useEffect(() => { void cargar(); }, [cargar]);

  const cuando = (ms: number) => {
    const min = Math.round((Date.now() - ms) / 60000);
    if (min < 1) return 'ahora mismo';
    if (min < 60) return `hace ${min} min`;
    const h = Math.round(min / 60);
    return h < 24 ? `hace ${h} h` : `hace ${Math.round(h / 24)} días`;
  };

  const QUE_ES: Record<string, string> = {
    sesiones: 'sesión', rolls: 'roll', eventos: 'acción', roll_observado: 'roll observado',
  };

  return (
    <div className="hoja" data-testid="detalle-cola"
      style={{ margin: '10px 0', padding: 12, border: '1px solid var(--rejilla)',
        borderRadius: 12, background: 'var(--superficie)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <h2 className="sec" style={{ margin: 0, flex: 1 }}>Lo que falta por subir</h2>
        <button className="ghost" data-testid="cerrar-cola" onClick={onCerrar}>Cerrar</button>
      </div>

      {!filas.length && (
        <p className="hint" data-testid="cola-vacia">
          No queda nada: todo lo que has registrado está guardado.
        </p>
      )}

      {filas.map((p) => (
        <div key={p.id} className="fila" data-testid={`cola-${p.id}`}
          style={{ alignItems: 'flex-start', gap: 8, padding: '8px 0' }}>
          <span className="n" style={{ flex: 1, minWidth: 0 }}>
            {QUE_ES[p.tabla] ?? p.tabla}
            <small>
              {cuando(p.creado)}
              {p.intentos > 0 && ` · ${p.intentos} ${p.intentos === 1 ? 'intento' : 'intentos'}`}
            </small>
            {p.estado === 'atencion' && (
              <small data-testid={`error-${p.id}`} style={{ color: 'var(--error)' }}>
                {p.ultimoError ?? 'el servidor lo rechazó'}
              </small>
            )}
          </span>
          {/* Descartar SOLO lo que el servidor rechaza. Lo que sigue en cola va
              a entrar solo, y ofrecer un botón de tirarlo sería invitar a
              perder un roll por impaciencia. */}
          {p.estado === 'atencion' && (
            <button className="ghost" disabled={ocupado}
              data-testid={`descartar-${p.id}`}
              style={{ padding: '7px 10px', fontSize: 12, color: 'var(--error)' }}
              onClick={async () => {
                setOcupado(true);
                await descartar(p.id);
                await cargar();
                await vaciarCola();
                setOcupado(false);
              }}>Descartar</button>
          )}
        </div>
      ))}

      {filas.length > 0 && (
        <div style={{ marginTop: 10 }}>
          <button className="primary" disabled={ocupado} data-testid="reintentar-ya"
            onClick={async () => {
              setOcupado(true);
              // Reintentar de verdad: lo que estaba en "necesita atención"
              // vuelve a la cola, porque si el usuario le da al botón es que
              // cree que la causa ya no está.
              for (const p of filas) if (p.estado === 'atencion') await reintentarYa(p.id);
              await vaciarCola(true);   // el usuario manda: sin esperas
              await cargar();
              setOcupado(false);
            }}>Reintentar ahora</button>
        </div>
      )}
    </div>
  );
}
