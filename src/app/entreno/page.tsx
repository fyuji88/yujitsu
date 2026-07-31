'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Marco, type Sesion } from '@/components/Marco';
import { supabase } from '@/lib/supabase';
import { TEXTOS } from '@/lib/textos/es';
import { SIGUE_SIENDO, VARIANTES } from '@/lib/textos/tecnicas.es';
import { usarPantallaEncendida } from '@/lib/pantalla';
import {
  CLAVE_SESION, CLAVE_TECNICAS, encolar, encolarRollObservado, nuevoId, precisar,
} from '@/lib/db';
import { retenerCola, vaciarCola } from '@/lib/sync';
import {
  accionesPosibles, aplicarAccion, CONTEXTO_PROPIO, GUARDIAS_TODAS,
  NOMBRE_OBJETIVO, NOMBRE_POSICION, resultadoDe,
  type Contexto, type EstadoRoll, type EventoBorrador, type Modo, type Pendiente,
} from '@/lib/bjj';
import { puntuar, type Anotacion, type Marcador } from '@/lib/puntos';
import type {
  ArgsRollObservado, Modalidad, Posicion, PracticanteRow, Rol, TipoSesion,
} from '@/lib/database.types';

/** Las salidas que se usan de verdad. El resto está detrás de "Otra…". */
const SALIDAS: Posicion[] = [
  'de_pie', 'guardia_cerrada', 'guardia_abierta', 'media_guardia', 'montada', 'espalda',
];

/** De pie y clinch son simétricas: no hay a quién preguntar quién está arriba. */
const esNeutral = (p: Posicion) => p === 'de_pie' || p === 'clinch';

interface SesionAbierta {
  id: string;
  fecha: string;
  modalidad: Modalidad;
  tipo: TipoSesion;
  rolls: number;
  /**
   * De qué Open Mat es esta sesión, o null si se entrena suelto. Desde bjj_34
   * hay UNA SESIÓN POR OPEN MAT: sin guardarlo aquí no se sabría a cuál
   * pertenece la que está abierta, y no se podría ofrecer cambiar al otro.
   */
  quedadaId?: string | null;
}

/**
 * El cronómetro.
 *
 * Se deriva de marcas de tiempo, nunca de un contador que suma ticks. Si el
 * móvil apaga la pantalla o el navegador manda la pestaña a segundo plano, el
 * intervalo se ralentiza o se para — un contador acumulado se quedaría corto y
 * el observador no se enteraría hasta el final. Aquí el intervalo solo sirve
 * para repintar; la hora la dice `Date.now()`.
 */
interface Crono {
  /** Cuándo se puso en marcha la última vez. null = en pausa. */
  desde: number | null;
  /** Milisegundos acumulados en los tramos anteriores. */
  acumulado: number;
}

const CRONO_PARADO: Crono = { desde: null, acumulado: 0 };
const transcurrido = (c: Crono, ahora: number) =>
  c.acumulado + (c.desde !== null ? Math.max(0, ahora - c.desde) : 0);

function mmss(ms: number) {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

const hoy = () => new Date().toISOString().slice(0, 10);

/** Una foto del roll para poder deshacer. Ver `deshacer()`. */
interface Instantanea {
  estado: EstadoRoll;
  eventos: EventoBorrador[];
  pendiente: Pendiente | null;
  subPendiente: SubPendiente | null;
}

/** Una variante del catálogo, para los chips de precisar. */
interface Variante { id: string; slug: string; nombre: string }

interface SubPendiente {
  slug: string;
  objetivo: string;
  actor: 'yo' | 'oponente';
  posicion: Posicion;
  rol: string;
}

export default function Entreno() {
  return <Marco titulo="Entreno">{(s) => <Flujo sesion={s} />}</Marco>;
}

function Flujo({ sesion }: { sesion: Sesion }) {
  const [abierta, setAbierta] = useState<SesionAbierta | null>(null);
  const [roster, setRoster] = useState<PracticanteRow[]>([]);
  const [tecnicas, setTecnicas] = useState<Record<string, string>>({});
  /**
   * Las variantes de cada mecánica, por slug de la madre. Vacío para las 64 que
   * no tienen: por eso el chip no existe en el 90% de los rolls.
   */
  const [variantes, setVariantes] = useState<Record<string, Variante[]>>({});
  /** Cuánto usas cada variante, para ordenar los chips. De v_tecnicas_practicante. */
  const [usoVariante, setUsoVariante] = useState<Record<string, number>>({});
  /** Las técnicas del enfoque activo: van primero, que es el sentido del enfoque. */
  const [enEnfoque, setEnEnfoque] = useState<Set<string>>(new Set());
  /** Los ids de los eventos del roll que se acaba de cerrar, en el mismo orden. */
  const [idsEventos, setIdsEventos] = useState<string[]>([]);
  /** evento -> técnica elegida. Solo para pintar cuál está marcada. */
  const [precisado, setPrecisado] = useState<Record<string, string>>({});
  const [fase, setFase] = useState<
    'inicio' | 'observadorA' | 'oponente' | 'quienArriba' | 'roll' | 'fin'
  >('inicio');

  /**
   * La pantalla no se apaga mientras se rueda.
   *
   * Atado a `fase === 'roll'` y no a la pantalla entera: retenerlo toda la
   * sesion se come la bateria de quien ha venido a entrenar dos horas, y sin
   * el, cuarenta segundos de roll en el suelo bastan para que el movil se
   * bloquee y se pierda medio registro.
   */
  const pantallaEncendida = usarPantallaEncendida(fase === 'roll');

  const [modo, setModo] = useState<Modo>('propio');
  const [practA, setPractA] = useState<PracticanteRow | null>(null);
  const [modalidadObs, setModalidadObs] = useState<Modalidad>('gi');
  const [posInicio, setPosInicio] = useState<Posicion>('de_pie');
  const [rolInicio, setRolInicio] = useState<Rol>('neutral');
  const [verTodasSalidas, setVerTodasSalidas] = useState(false);

  // roll en curso
  const [oponente, setOponente] = useState<PracticanteRow | null>(null);
  const [estado, setEstado] = useState<EstadoRoll>({ pos: 'de_pie', rol: 'neutral' });
  const [eventos, setEventos] = useState<EventoBorrador[]>([]);
  const [pendiente, setPendiente] = useState<Pendiente | null>(null);
  const [subPendiente, setSubPendiente] = useState<SubPendiente | null>(null);
  const [pila, setPila] = useState<Instantanea[]>([]);

  const [crono, setCrono] = useState<Crono>(CRONO_PARADO);
  const [ahora, setAhora] = useState(() => Date.now());

  // Lo último que se encoló observando, para poder corregirle la duración.
  const [ultimo, setUltimo] = useState<ArgsRollObservado | null>(null);

  /** La quedada de hoy en la que estás apuntado, si la hay. */
  const [quedadaHoy, setQuedadaHoy] = useState<
    { id: string; equipo_id: string; titulo: string; lugar: string | null } | null
  >(null);
  /**
   * Tu equipo, para colgar de él las sesiones que no son de ninguna quedada.
   * Sin esto, una sesión suelta se queda con `equipo_id` a null y no sale en el
   * feed del equipo — que es casi todas.
   */
  const [miEquipo, setMiEquipo] = useState<string | null>(null);
  /** Todas las de hoy a las que estás apuntado. Si hay dos, se pregunta. */
  const [quedadasHoy, setQuedadasHoy] = useState<
    { id: string; equipo_id: string; titulo: string; lugar: string | null }[]>([]);
  /**
   * El Open Mat de la tanda de observación. Se elige UNA vez al empezar y vale
   * para toda la tarde: cuando hay gente esperando en el tatami, un toque al
   * principio es lo que se puede pagar. Preguntarlo en cada roll sería un peaje
   * y la gente dejaría de registrar.
   */
  const [quedadaObs, setQuedadaObs] = useState<string | null>(null);

  useEffect(() => {
    const guardada = localStorage.getItem(CLAVE_SESION);
    if (guardada) {
      const s = JSON.parse(guardada) as SesionAbierta;
      if (s.fecha === hoy()) { setAbierta(s); setModalidadObs(s.modalidad); }
      else localStorage.removeItem(CLAVE_SESION);
    }
    const cache = localStorage.getItem(CLAVE_TECNICAS);
    if (cache) setTecnicas(JSON.parse(cache));
  }, []);

  useEffect(() => {
    void supabase().from('miembros_equipo').select('equipo_id')
      .eq('estado', 'activo').limit(1).maybeSingle()
      .then(({ data }) => {
        if (data) setMiEquipo((data as { equipo_id: string }).equipo_id);
      });
  }, []);

  useEffect(() => {
    // TODAS las de hoy, no una. Con `.maybeSingle()` y dos Open Mats el mismo
    // dia la consulta fallaba y no se enganchaba NINGUNA — el caso raro se
    // llevaba por delante tambien el caso normal.
    void supabase().from('v_mi_quedada_hoy').select('id,equipo_id,titulo,lugar')
      .then(({ data }) => {
        const qs = (data ?? []) as NonNullable<typeof quedadaHoy>[];
        setQuedadasHoy(qs);
        // Una sola: se engancha sola. Dos: se pregunta, porque adivinar aqui
        // es meter los rolls en el Open Mat equivocado.
        if (qs.length === 1) setQuedadaHoy(qs[0]);
      });
  }, []);

  useEffect(() => {
    (async () => {
      const { data } = await supabase().from('practicantes').select('*').order('nombre');
      if (data) setRoster(data as PracticanteRow[]);
      const { data: t } = await supabase()
        .from('tecnicas').select('id,slug,nombre,variante_de');
      if (t) {
        const filas = t as { id: string; slug: string; nombre: string; variante_de: string | null }[];
        const m = Object.fromEntries(filas.map((x) => [x.slug, x.id]));
        setTecnicas(m);
        localStorage.setItem(CLAVE_TECNICAS, JSON.stringify(m));

        // Las variantes, indexadas por el SLUG de la madre, que es lo que
        // lleva el evento borrador.
        const porId = Object.fromEntries(filas.map((x) => [x.id, x]));
        const v: Record<string, Variante[]> = {};
        for (const x of filas) {
          if (!x.variante_de) continue;
          const madre = porId[x.variante_de];
          if (!madre) continue;
          (v[madre.slug] ??= []).push({ id: x.id, slug: x.slug, nombre: x.nombre });
        }
        setVariantes(v);
      }

      // Cuánto usa cada variante, para ordenar los chips. Sale de
      // v_tecnicas_practicante, que es la única fuente de ese recuento.
      const { data: uso } = await supabase()
        .from('v_tecnicas_practicante')
        .select('tecnica_id,intentos')
        .eq('practicante_id', sesion.practicante.id);
      if (uso) {
        setUsoVariante(Object.fromEntries(
          (uso as { tecnica_id: string; intentos: number }[])
            .map((x) => [x.tecnica_id, x.intentos])));
      }

      // El enfoque activo. Si esta semana tu objetivo es la tarikoplata, tiene
      // que ser la PRIMERA opción que ves al precisar una kimura.
      const { data: enf } = await supabase()
        .from('enfoques').select('tecnicas')
        .eq('practicante_id', sesion.practicante.id)
        .is('hasta', null).limit(1).maybeSingle();
      if (enf) setEnEnfoque(new Set((enf as { tecnicas: string[] }).tecnicas ?? []));
    })();
  }, []);

  // Solo repinta. Si la pestaña se va a segundo plano y el intervalo se
  // ralentiza, al volver el primer tick ya muestra la hora real.
  useEffect(() => {
    if (crono.desde === null) return;
    const id = setInterval(() => setAhora(Date.now()), 500);
    return () => clearInterval(id);
  }, [crono.desde]);

  // Al volver de segundo plano, repintar sin esperar al siguiente tick.
  useEffect(() => {
    const despertar = () => setAhora(Date.now());
    document.addEventListener('visibilitychange', despertar);
    window.addEventListener('focus', despertar);
    return () => {
      document.removeEventListener('visibilitychange', despertar);
      window.removeEventListener('focus', despertar);
    };
  }, []);

  // Mientras se mira el resumen del roll observado, la cola espera: ahí todavía
  // se puede corregir la duración. Ver `retenerCola`.
  const reteniendo = modo === 'observador' && fase === 'fin';
  useEffect(() => {
    retenerCola(reteniendo);
    // El cleanup solo suelta si este efecto era el que retenía. Sin la guarda,
    // al pasar de false a true React limpia el efecto anterior primero y esa
    // llamada a retenerCola(false) vacía la cola justo antes de retenerla.
    return () => { if (reteniendo) retenerCola(false); };
  }, [reteniendo]);

  const observando = modo === 'observador';
  const nombreA = observando ? (practA?.nombre ?? '') : 'Yo';
  const nombreB = oponente?.nombre ?? 'Oponente';

  const ctx: Contexto = observando && practA && oponente
    ? { modo: 'observador', a: practA.nombre, b: oponente.nombre }
    : CONTEXTO_PROPIO;

  const marcador = useMemo(() => puntuar(eventos), [eventos]);

  const segundoActual = useCallback(() => (
    crono.desde === null && crono.acumulado === 0
      ? null
      : Math.min(3600, Math.floor(transcurrido(crono, Date.now()) / 1000))
  ), [crono]);

  const foto = useCallback((): Instantanea => (
    { estado, eventos, pendiente, subPendiente }
  ), [estado, eventos, pendiente, subPendiente]);

  const agregar = useCallback((ev: EventoBorrador) => {
    setEventos((e) => [...e, { ...ev, segundo: segundoActual() }]);
  }, [segundoActual]);

  /**
   * Deshacer.
   *
   * Deja de ser un extra en cuanto hay un marcador visible: el observador ve
   * sus propios errores en tiempo real y quiere corregirlos en el momento.
   * Se guarda una foto antes de cada toque y esto la restaura — así vuelve
   * también la posición, no solo el evento. Como el roll no sube hasta que
   * termina, es un pop sobre el estado y no una operación contra la base.
   */
  function deshacer() {
    if (!pila.length) return;
    // Una acción son dos toques (elegir la acción y luego el destino), así que
    // deshacer no puede ser un pop: dejaría al observador dentro de la pregunta
    // que acababa de contestar. Se retrocede hasta la foto anterior al evento,
    // y luego hasta el principio de esa acción.
    let i = pila.length - 1;
    while (i >= 0 && pila[i].eventos.length >= eventos.length) i--;
    if (i < 0) i = 0;
    while (i > 0 && pila[i - 1].eventos.length === pila[i].eventos.length) i--;

    const f = pila[i];
    setEstado(f.estado);
    setEventos(f.eventos);
    setPendiente(f.pendiente);
    setSubPendiente(f.subPendiente);
    setPila(pila.slice(0, i));
  }

  /**
   * `q` explícito y no `quedadaHoy`: desde bjj_34 hay UNA SESIÓN POR OPEN MAT,
   * así que abrir la segunda del día tiene que poder decir cuál, sin depender
   * de lo que estuviera seleccionado antes.
   */
  const abrirSesion = useCallback(async (
    modalidad: Modalidad, tipo: TipoSesion,
    q?: { id: string; equipo_id: string } | null,
  ) => {
    const s: SesionAbierta = {
      id: nuevoId(), fecha: hoy(), modalidad, tipo, rolls: 0, quedadaId: q?.id ?? null,
    };
    await encolar('sesiones', {
      id: s.id,
      practicante_id: sesion.practicante.id,
      fecha: s.fecha,
      modalidad,
      formato: tipo,
      academia: sesion.practicante.academia,
      // Si hay una quedada hoy en tu equipo y estás apuntado, viene sola: en el
      // caso normal son cero toques. "Roll libre" es lo que sale si no hay.
      equipo_id: q?.equipo_id ?? miEquipo,
      quedada_id: q?.id ?? null,
    });
    localStorage.setItem(CLAVE_SESION, JSON.stringify(s));
    setAbierta(s);
    setModalidadObs(modalidad);
    void vaciarCola();
  }, [sesion.practicante, miEquipo]);

  function limpiarRoll() {
    setOponente(null);
    setEstado({ pos: 'de_pie', rol: 'neutral' });
    setEventos([]);
    setPendiente(null);
    setSubPendiente(null);
    setPila([]);
    setCrono(CRONO_PARADO);
    setUltimo(null);
  }

  function nuevoRoll() {
    limpiarRoll();
    setModo('propio');
    setPractA(null);
    setFase('oponente');
  }

  function observar() {
    limpiarRoll();
    setModo('observador');
    setPractA(null);
    setPosInicio('de_pie');
    setRolInicio('neutral');
    setVerTodasSalidas(false);
    setFase('observadorA');
  }

  function salir() {
    limpiarRoll();
    setModo('propio');
    setPractA(null);
    setFase('inicio');
  }

  /** Arranca el roll con la posición de salida elegida y el crono en marcha. */
  function empezarRoll(rol: Rol) {
    setEstado({ pos: posInicio, rol });
    setEventos([]);
    setPendiente(null);
    setSubPendiente(null);
    setPila([]);
    setCrono({ desde: Date.now(), acumulado: 0 });
    setAhora(Date.now());
    setFase('roll');
  }

  function accion(clave: Parameters<typeof aplicarAccion>[0]) {
    setPila((p) => [...p, foto()]);
    const r = aplicarAccion(clave, estado, ctx);
    if (r.evento) agregar(r.evento);
    if (r.estado) setEstado(r.estado);
    setPendiente(r.pendiente ?? null);
  }

  async function terminarPropio() {
    if (!abierta || !oponente) return;
    const rollId = nuevoId();
    await encolar('rolls', {
      id: rollId,
      sesion_id: abierta.id,
      oponente_id: oponente.id,
      orden_en_sesion: abierta.rolls + 1,
      modalidad: abierta.modalidad,
      posicion_inicio: 'de_pie',
      rol_inicio: 'neutral',
      resultado: resultadoDe(eventos),
      origen: 'propio',
      registrado_por: sesion.practicante.id,
    });
    const ids: string[] = [];
    for (const ev of eventos) {
      const evId = nuevoId();
      ids.push(evId);
      await encolar('eventos', {
        id: evId,
        roll_id: rollId,
        actor: ev.actor,
        tipo: ev.tipo,
        posicion: ev.posicion,
        rol: ev.rol,
        objetivo: ev.objetivo,
        tecnica_id: ev.tecnicaSlug ? tecnicas[ev.tecnicaSlug] ?? null : null,
        completado: ev.completado,
        segundo_roll: ev.segundo ?? null,
      });
    }
    setIdsEventos(ids);
    setPrecisado({});
    const s = { ...abierta, rolls: abierta.rolls + 1 };
    localStorage.setItem(CLAVE_SESION, JSON.stringify(s));
    setAbierta(s);
    setFase('fin');
    void vaciarCola();
  }

  async function terminarObservado() {
    if (!practA || !oponente) return;
    // Antes de encolar, no después: el efecto que retiene la cola no corre
    // hasta el siguiente render, y para entonces ya se habría enviado.
    retenerCola(true);
    const seg = Math.floor(transcurrido(crono, Date.now()) / 1000);
    const args: ArgsRollObservado = {
      p_par: nuevoId(),
      p_practicante_a: practA.id,
      p_practicante_b: oponente.id,
      p_fecha: hoy(),
      p_modalidad: modalidadObs,
      p_duracion_min: Math.min(60, Math.max(0, Math.round(seg / 60))),
      p_posicion_inicio: posInicio,
      p_rol_inicio: rolInicio,
      p_resultado: resultadoDe(eventos),
      p_eventos: eventos.map((ev) => ({
        actor: ev.actor,
        tipo: ev.tipo,
        posicion: ev.posicion,
        rol: ev.rol,
        objetivo: ev.objetivo,
        tecnica_slug: ev.tecnicaSlug,
        completado: ev.completado,
        segundo_roll: ev.segundo ?? null,
      })),
    };
    await encolarRollObservado(args);
    setUltimo(args);
    setCrono((c) => ({ desde: null, acumulado: transcurrido(c, Date.now()) }));
    setFase('fin');
    // No envía nada porque está retenida; sirve para que la píldora enseñe que
    // hay un roll esperando en vez de decir "sincronizado".
    void vaciarCola();
  }

  /** Corrige la duración del roll que aún está en la cola. */
  async function corregirDuracion(min: number) {
    if (!ultimo) return;
    const args = { ...ultimo, p_duracion_min: Math.min(60, Math.max(0, min)) };
    await encolarRollObservado(args);
    setUltimo(args);
  }

  /**
   * Precisar una técnica del roll recién cerrado.
   *
   * Se apunta en `precisado` ANTES de esperar a la red: el chip tiene que
   * responder al toque, no al servidor. Si algo falla, `precisar()` lanza y se
   * revierte la marca — es lo único que puede fallar aquí y no debe quedarse
   * mintiendo en pantalla.
   */
  async function elegirPrecision(evId: string, tecnicaId: string | undefined) {
    if (!tecnicaId) return;
    const antes = precisado[evId];
    setPrecisado((p) => ({ ...p, [evId]: tecnicaId }));
    try {
      const via = await precisar(evId, tecnicaId);
      // Si fue por la COLA, hay que empujarla: si no, la correccion se queda
      // esperando a la siguiente sincronizacion y el analisis sigue diciendo
      // 'kimura' un rato largo. No se pierde nada, pero parece que no ha
      // pasado — y un chip que no hace nada visible deja de tocarse.
      if (via === 'cola') void vaciarCola();
    } catch (e) {
      // Se revierte la marca Y se dice por que. Tragarse el error dejaba el
      // chip mintiendo: parecia que habia precisado y no habia pasado nada.
      setPrecisado((p) => ({ ...p, [evId]: antes ?? '' }));
      console.error('precisar fallo:', e instanceof Error ? e.message : e);
    }
  }

  /**
   * Cuelga del Open Mat las sesiones de esta tanda.
   *
   * Va por `enganchar_del_dia()` y no por un parámetro más en
   * `registrar_roll_observado()`: esa función ya tiene DOS firmas por el puente
   * de `p_grupo` y es lo único que la cola serializa dentro de IndexedDB. Una
   * tercera firma es pedir el mismo problema otra vez.
   *
   * Es idempotente, así que llamarla tras cada roll no cuesta nada y cubre el
   * caso de que la tanda se corte a la mitad.
   */
  const enganchar = useCallback(async (quedadaId: string | null) => {
    if (!quedadaId) return;
    await supabase().rpc('enganchar_del_dia', { p_quedada: quedadaId });
  }, []);

  /** Los Open Mats de hoy que no son el de la sesión abierta. */
  const otrosOpenMats = abierta
    ? quedadasHoy.filter((x) => x.id !== abierta.quedadaId)
    : [];

  const terminar = () => (observando ? terminarObservado() : terminarPropio());

  // ---------------------------------------------------------------- pantallas

  if (!abierta && fase === 'inicio') {
    return (
      <>
        <h1>Nuevo entreno</h1>
        <p className="hint">Se abre una vez al llegar. Después, cada roll es un toque.</p>
        {/* AUTOMATICO PERO NUNCA SILENCIOSO. Se ve a que Open Mat va a ir lo
            que registres, y se puede quitar o cambiar. Un enganche que no se
            ve es peor que no engancharlo: cuando esta mal, nadie lo sabe. */}
        {quedadasHoy.length > 0 && (
          <>
            <h2 className="sec">¿Es de un Open Mat?</h2>
            <p className="hint" style={{ marginTop: 0 }}>
              Cada Open Mat tiene su propia sesión y su propio informe. Entrenar
              sin Open Mat es lo normal: «A ninguno» no es un descuido.
            </p>
            <div className="chips" data-testid="elige-quedada">
              {quedadasHoy.map((x) => (
                <button className="chip" key={x.id} data-testid={`quedada-${x.id}`}
                  style={quedadaHoy?.id === x.id
                    ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
                  onClick={() => setQuedadaHoy(x)}>
                  {x.titulo}
                </button>
              ))}
              <button className="chip" data-testid="quedada-ninguna"
                style={!quedadaHoy ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
                onClick={() => setQuedadaHoy(null)}>
                A ninguno
              </button>
            </div>
          </>
        )}
        {quedadaHoy && (
          <p className="hint" data-testid="quedada-hoy" style={{ color: 'var(--marca-texto)' }}>
            Hoy hay <b>{quedadaHoy.titulo}</b>
            {quedadaHoy.lugar && <> en {quedadaHoy.lugar}</>} y estás apuntado:
            lo que registres se guarda en ese {TEXTOS.quedada}.{' '}
            <button className="x" data-testid="quitar-quedada"
              style={{ padding: 0, font: 'inherit', textDecoration: 'underline' }}
              onClick={() => setQuedadaHoy(null)}>quitar</button>
          </p>
        )}
        <h2 className="sec">Modalidad</h2>
        <div className="chips">
          <button className="chip" data-testid="modalidad-gi"
            onClick={() => abrirSesion('gi', 'sparring', quedadaHoy)}>Gi</button>
          <button className="chip" data-testid="modalidad-nogi"
            onClick={() => abrirSesion('nogi', 'sparring', quedadaHoy)}>No-gi</button>
          <button className="chip" data-testid="modalidad-openmat"
            onClick={() => abrirSesion('nogi', 'open_mat', quedadaHoy)}>Open mat</button>
        </div>
        <h2 className="sec">O mira a otros</h2>
        <div style={{ marginTop: 4 }}>
          <button className="ghost" data-testid="observar" onClick={observar}>👁 Observar</button>
        </div>
        <p className="hint">
          Para registrar el roll de otros dos sin entrenar tú, con marcador y cronómetro.
          No hace falta abrir sesión: el roll va a la de ellos, no a la tuya.
        </p>
      </>
    );
  }

  if (fase === 'observadorA') {
    const salidas = verTodasSalidas
      ? (Object.keys(NOMBRE_POSICION) as Posicion[])
      : SALIDAS;
    return (
      <>
        <h1>Modo observador</h1>
        <p className="hint">
          Tú solo miras. El roll se guarda para los dos: uno lo verá como ataque y el otro
          como defensa, sin que ninguno toque el móvil.
        </p>

        <h2 className="sec">Modalidad del roll</h2>
        <div className="chips">
          {(['gi', 'nogi'] as const).map((m) => (
            <button key={m} className="chip" data-testid={`obs-mod-${m}`}
              style={modalidadObs === m
                ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
              onClick={() => setModalidadObs(m)}>
              {m === 'gi' ? 'Gi' : 'No-gi'}
            </button>
          ))}
        </div>

        {quedadasHoy.length > 0 && (
          <>
            <h2 className="sec">¿Es de un Open Mat?</h2>
            <p className="hint" style={{ marginTop: 0 }}>
              Se elige una vez y vale para toda la tarde. De aquí salen el
              informe, el ranking y los títulos.
            </p>
            <div className="chips" data-testid="obs-quedada">
              {quedadasHoy.map((x) => (
                <button className="chip" key={x.id} data-testid={`obs-quedada-${x.id}`}
                  style={quedadaObs === x.id
                    ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
                  onClick={() => setQuedadaObs(x.id)}>
                  {x.titulo}
                </button>
              ))}
              <button className="chip" data-testid="obs-quedada-ninguna"
                style={!quedadaObs ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
                onClick={() => setQuedadaObs(null)}>
                Suelto
              </button>
            </div>
          </>
        )}

        <h2 className="sec">Posición de salida</h2>
        <div className="chips">
          {salidas.map((p) => (
            <button key={p} className="chip" data-testid={`salida-${p}`}
              style={posInicio === p
                ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
              onClick={() => setPosInicio(p)}>
              {NOMBRE_POSICION[p]}
            </button>
          ))}
          {!verTodasSalidas && (
            <button className="chip" data-testid="salida-mas"
              onClick={() => setVerTodasSalidas(true)}>Otra…</button>
          )}
        </div>
        <p className="hint">
          En clase se arranca constantemente desde una posición pactada. Por defecto de pie:
          si lo cambias, luego se pregunta quién empieza arriba.
        </p>

        <h2 className="sec" style={{ color: 'var(--dato-yo-texto)' }}>Primer practicante</h2>
        <div className="chips">
          {roster.map((p) => (
            <button className="chip" key={p.id} data-testid={`obsA-${p.nombre}`}
              onClick={() => { setPractA(p); setFase('oponente'); }}>
              {p.nombre}{p.usa_sistema && <small>app</small>}
            </button>
          ))}
        </div>
        {roster.length < 2 && (
          <p className="hint">
            Hacen falta al menos dos fichas en el roster. Añádelas desde la pestaña Practicantes.
          </p>
        )}
        <div style={{ marginTop: 18 }}>
          <button className="ghost" onClick={salir}>← Atrás</button>
        </div>
      </>
    );
  }

  if (fase === 'oponente') {
    const lista = observando
      ? roster.filter((p) => p.id !== practA?.id)
      : roster.filter((p) => p.id !== sesion.practicante.id);
    return (
      <>
        <h2 className="sec" style={observando ? { color: 'var(--dato-op-texto)' } : undefined}>
          {observando ? `${nombreA} contra…` : '¿Con quién ruedas?'}
        </h2>
        <div className="chips">
          {lista.map((p) => (
            <button className="chip" key={p.id} data-testid={`op-${p.nombre}`}
              onClick={() => {
                setOponente(p);
                if (!observando) { setCrono(CRONO_PARADO); setFase('roll'); setEventos([]); return; }
                if (esNeutral(posInicio)) { setRolInicio('neutral'); empezarRoll('neutral'); }
                else setFase('quienArriba');
              }}>
              {p.nombre}{p.usa_sistema && <small>app</small>}
            </button>
          ))}
        </div>
        {!lista.length && (
          <p className="hint">
            No tienes a nadie más en el roster. Añade compañeros desde la pestaña Practicantes.
          </p>
        )}
        {observando && (
          <p className="hint">
            Empezáis en <b>{NOMBRE_POSICION[posInicio]}</b>. En cuanto elijas, arranca el
            cronómetro.
          </p>
        )}
        <div style={{ marginTop: 18 }}>
          <button className="ghost"
            onClick={() => setFase(observando ? 'observadorA' : 'inicio')}>← Atrás</button>
        </div>
      </>
    );
  }

  if (fase === 'quienArriba' && practA && oponente) {
    return (
      <>
        <h1>{NOMBRE_POSICION[posInicio]}</h1>
        <h2 className="sec">¿Quién empieza arriba?</h2>
        <div className="chips">
          <button className="chip" data-testid="arriba-a"
            style={{ borderColor: 'var(--dato-yo)' }}
            onClick={() => { setRolInicio('arriba'); empezarRoll('arriba'); }}>
            {practA.nombre}
          </button>
          <button className="chip" data-testid="arriba-b"
            style={{ borderColor: 'var(--dato-op)' }}
            onClick={() => { setRolInicio('abajo'); empezarRoll('abajo'); }}>
            {oponente.nombre}
          </button>
        </div>
        <p className="hint">
          La posición es física y es la misma para los dos; lo que cambia es quién la juega.
          Si {practA.nombre} está abajo en guardia cerrada, {oponente.nombre} está dentro
          intentando pasarla.
        </p>
        <div style={{ marginTop: 18 }}>
          <button className="ghost" onClick={() => setFase('oponente')}>← Atrás</button>
        </div>
      </>
    );
  }

  if (fase === 'roll' && oponente && (!observando || practA)) {
    const a = accionesPosibles(estado, modo);
    const quienArriba = estado.rol === 'arriba' ? nombreA : nombreB;
    const responder = (fn: () => void) => { setPila((p) => [...p, foto()]); fn(); };
    return (
      <>
        {observando && (
          <MarcadorEnVivo
            marcador={marcador} a={nombreA} b={nombreB}
            ms={transcurrido(crono, ahora)} enPausa={crono.desde === null}
            onPausa={() => setCrono((c) => (c.desde === null
              ? { desde: Date.now(), acumulado: c.acumulado }
              : { desde: null, acumulado: transcurrido(c, Date.now()) }))}
          />
        )}

        <div className="state">
          <div className="lbl">Posición actual</div>
          <div className="pos">{NOMBRE_POSICION[estado.pos]}</div>
          <div className="rol">
            {estado.rol === 'neutral'
              ? 'nadie controla todavía'
              : observando
                ? <><b>{quienArriba}</b> arriba</>
                : <>estás <b>{estado.rol}</b></>}
          </div>
        </div>

        {pendiente
          ? <Pregunta
              p={pendiente}
              onPosicion={(pos) => responder(() => {
                if (pendiente.tipo !== 'posicion') return;
                if (pendiente.eventoAlElegir) agregar(pendiente.eventoAlElegir(pos));
                setEstado(pendiente.siguiente(pos));
                setPendiente(null);
              })}
              onMas={() => {
                if (pendiente.tipo !== 'posicion') return;
                setPendiente({ ...pendiente, opciones: GUARDIAS_TODAS, mas: false });
              }}
              onTecnica={(slug, objetivo) => responder(() => {
                if (pendiente.tipo !== 'tecnica') return;
                setSubPendiente({
                  slug, objetivo, actor: pendiente.actor,
                  posicion: pendiente.posicion, rol: pendiente.rol,
                });
                setPendiente(null);
              })}
              onCancelar={() => setPendiente(null)}
            />
          : subPendiente
            ? (
              <>
                <h2 className="sec">¿Entró?</h2>
                <div className="chips">
                  {([true, false] as const).map((entro) => (
                    <button key={String(entro)}
                      className={`chip ${entro ? 'ok' : 'no'}`}
                      data-testid={entro ? 'entro-si' : 'entro-no'}
                      onClick={() => responder(() => {
                        agregar({
                          actor: subPendiente.actor, tipo: 'sumision',
                          posicion: subPendiente.posicion,
                          rol: subPendiente.rol as EstadoRoll['rol'],
                          objetivo: subPendiente.objetivo as EventoBorrador['objetivo'],
                          tecnicaSlug: subPendiente.slug, completado: entro,
                        });
                        setSubPendiente(null);
                      })}>
                      {entro ? '✓ Sí, fin del roll' : '✗ Falló, seguimos'}
                    </button>
                  ))}
                </div>
              </>
            )
            : (
              <>
                <h2 className="sec" style={observando ? { color: 'var(--dato-yo-texto)' } : undefined}>
                  {nombreA}
                </h2>
                <div className="grid">
                  {a.yo.map((x) => (
                    <button className="act yo" key={x.clave} data-testid={x.clave}
                      onClick={() => accion(x.clave)}>
                      {!observando && <span className="k">yo</span>}{x.etiqueta}
                    </button>
                  ))}
                </div>
                <h2 className="sec" style={observando ? { color: 'var(--dato-op-texto)' } : undefined}>
                  {nombreB}
                </h2>
                <div className="grid">
                  {a.op.map((x) => (
                    <button className="act op" key={x.clave} data-testid={x.clave}
                      onClick={() => accion(x.clave)}>
                      {!observando && <span className="k">él</span>}{x.etiqueta}
                    </button>
                  ))}
                </div>
              </>
            )}

        {/* QUE SE VEA. El wakeLock es invisible por definición: si funciona no
            pasa nada, y si falla tampoco pasa nada visible hasta que se te
            apaga el móvil a mitad de roll. Sin este indicador nadie sabe en
            cuál de los dos casos está. En navegadores que no lo soportan
            —Safari anterior a 16.4— se dice la verdad en vez de callar. */}
        <p className="hint" data-testid="pantalla-encendida"
          style={{ marginTop: 14, fontSize: 12 }}>
          {pantallaEncendida
            ? '🔆 La pantalla se mantiene encendida mientras dure el roll.'
            : '⚠ Este navegador no puede evitar que la pantalla se apague.'}
        </p>

        <h2 className="sec">Eventos ({eventos.length})</h2>
        <Timeline eventos={eventos} nombreA={nombreA} nombreB={nombreB}
          onBorrar={(i) => setEventos((e) => e.filter((_, j) => j !== i))} />

        <div style={{ display: 'flex', gap: 9, marginTop: 20 }}>
          <button className="primary" data-testid="fin-roll" onClick={terminar}>
            Fin del roll
          </button>
          {observando && (
            <button className="ghost" data-testid="deshacer"
              disabled={!pila.length} onClick={deshacer}>↶ Deshacer</button>
          )}
        </div>
      </>
    );
  }

  if (fase === 'fin') {
    const res = resultadoDe(eventos);
    const txt = observando
      ? (res === 'sumision_favor' ? `Sumisión de ${nombreA}`
        : res === 'sumision_contra' ? `Sumisión de ${nombreB}` : 'Sin sumisión')
      : (res === 'sumision_favor' ? 'Sumisión a favor'
        : res === 'sumision_contra' ? 'Sumisión en contra' : 'Sin sumisión');
    const espeja = observando && oponente?.usa_sistema;

    /**
     * Qué se puede precisar de este roll: los eventos cuya técnica tiene
     * variantes. En LOTE, no una pantalla por evento: si la sesión tuvo tres
     * kimuras se ofrecen juntas.
     *
     * El orden de las opciones no es alfabético y no es un detalle: primero lo
     * que estás trabajando, luego lo que más usas, luego el resto.
     */
    const aPrecisar = eventos
      .map((ev, i) => ({ evId: idsEventos[i], slug: ev.tecnicaSlug }))
      .filter((x): x is { evId: string; slug: string } =>
        !!x.evId && !!x.slug && (variantes[x.slug]?.length ?? 0) > 0)
      .map((x) => ({
        ...x,
        opciones: [...variantes[x.slug]].sort((a, b) => {
          const ea = enEnfoque.has(a.id) ? 1 : 0;
          const eb = enEnfoque.has(b.id) ? 1 : 0;
          if (ea !== eb) return eb - ea;
          return (usoVariante[b.id] ?? 0) - (usoVariante[a.id] ?? 0);
        }),
      }));

    return (
      <>
        <div className="state">
          <div className="lbl">{observando ? 'Roll observado' : 'Roll guardado'}</div>
          <div className="tanteo" data-testid="tanteo-final" style={{ margin: '4px 0 2px' }}>
            <span className="n a">{marcador.a}</span>
            <span className="sep">–</span>
            <span className="n b">{marcador.b}</span>
            <span style={{ fontSize: 13, color: 'var(--texto-2)', marginLeft: 6 }}>
              {observando ? `${nombreA} · ${nombreB}` : `tú · ${nombreB}`}
            </span>
          </div>
          <div className="rol" data-testid="resultado">
            {txt} · {eventos.length} eventos · {mmss(transcurrido(crono, ahora))}
          </div>
        </div>

        <h2 className="sec">De dónde salen los puntos</h2>
        <Desglose marcador={marcador} a={nombreA} b={nombreB} />

        {observando && ultimo && (
          <>
            <label htmlFor="dur">Duración (minutos), del cronómetro</label>
            <input id="dur" type="number" min={0} max={60} data-testid="duracion"
              defaultValue={ultimo.p_duracion_min ?? 0}
              onChange={(e) => void corregirDuracion(Number(e.target.value))} />
            <p className="hint">
              Se rellena sola. Solo hace falta tocarla si el cronómetro se quedó corriendo.
            </p>
          </>
        )}

        {observando ? (
          <>
            <p className="hint" data-testid="resumen-observado">
              {espeja
                ? <>Se guardan <b>dos rolls</b>, uno para {nombreA} y otro para {nombreB},
                    unidos por el mismo <code>par_id</code>. Lo que para uno es ataque
                    para el otro es defensa.</>
                : <>Se guarda <b>un roll</b>, el de {nombreA}. {nombreB} no usa la app, así que
                    no hay a quién espejárselo.</>}
              {' '}Sale hacia Supabase en cuanto salgas de esta pantalla.
            </p>
            <p className="hint">
              Si alguno de los dos registra este mismo roll por su cuenta, <b>gana esta
              versión</b>: el que mira ve cosas que tú no ves.
            </p>
          </>
        ) : (
          <p className="hint">
            Se ha guardado en el móvil y sale hacia Supabase en cuanto haya red.
          </p>
        )}

        {/* ---------------------------------------------------------------
            PRECISAR. Solo aparece si alguna técnica del roll TIENE variantes:
            para las 64 que no, este bloque no existe.

            NUNCA BLOQUEA. No es un modal, no es obligatorio, y un roll sin
            precisar es un roll perfectamente válido. En cuanto precisar sea un
            peaje la gente deja de registrar, y eso es lo único que mata este
            producto.

            Solo en rolls propios: los eventos de un roll observado los crea la
            RPC en el servidor y aquí no tenemos sus ids. Desde el historial sí
            se podrán, cuando exista esa pantalla.
        ---------------------------------------------------------------- */}
        {!observando && aPrecisar.length > 0 && (
          <>
            <h2 className="sec">¿Alguna era más concreta?</h2>
            <p className="hint" style={{ marginTop: 0 }}>
              Opcional. Sirve para que un objetivo de tarikoplata se cumpla
              cuando registras «kimura» con el cronómetro corriendo.
            </p>
            {aPrecisar.map(({ evId, slug, opciones }) => (
              <div key={evId} style={{ marginTop: 10 }}>
                <div className="lbl" style={{ marginBottom: 4 }}>
                  {slug.replace(/_/g, ' ')}
                </div>
                <div className="chips">
                  <button className="chip" data-testid={`precisar-${evId}-madre`}
                    style={!precisado[evId]
                      ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' }
                      : undefined}
                    onClick={() => void elegirPrecision(evId, tecnicas[slug])}>
                    {SIGUE_SIENDO(slug.replace(/_/g, ' '))}
                  </button>
                  {opciones.map((v) => (
                    <button className="chip" key={v.id}
                      data-testid={`precisar-${evId}-${v.slug}`}
                      style={precisado[evId] === v.id
                        ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' }
                        : undefined}
                      onClick={() => void elegirPrecision(evId, v.id)}>
                      {VARIANTES[v.slug]?.nombre ?? v.nombre}
                      {enEnfoque.has(v.id) && <small>enfoque</small>}
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </>
        )}

        <div style={{ display: 'flex', gap: 9, marginTop: 18 }}>
          <button className="primary" data-testid="otro-roll" onClick={() => {
            limpiarRoll();
            setFase(observando ? 'observadorA' : 'oponente');
          }}>+ Otro roll</button>
          <button className="ghost" onClick={salir}>{observando ? 'Salir' : 'Fin sesión'}</button>
        </div>
      </>
    );
  }

  return (
    <>
      <div className="state">
        <div className="lbl">Sesión abierta</div>
        <div className="pos">{abierta?.modalidad === 'gi' ? 'Gi' : 'No-gi'}</div>
        <div className="rol">{abierta?.rolls ?? 0} rolls registrados hoy</div>
      </div>
      {/* EL DOMINGO DE FELIPE: dos Open Mats el mismo dia. Cada uno tiene su
          sesion y su informe, asi que hace falta poder pasar de uno a otro sin
          cerrar nada. Solo se ofrecen los que todavia no tienen sesion abierta
          hoy — el que ya estas usando no se ofrece dos veces. */}
      {otrosOpenMats.length > 0 && (
        <>
          <h2 className="sec">¿Te vas a otro Open Mat?</h2>
          <div className="chips" data-testid="cambiar-openmat">
            {otrosOpenMats.map((x) => (
              <button className="chip" key={x.id}
                data-testid={`cambiar-a-${x.id}`}
                onClick={() => void abrirSesion(abierta!.modalidad, abierta!.tipo, x)}>
                {x.titulo}
              </button>
            ))}
          </div>
          <p className="hint" style={{ marginTop: 6 }}>
            Se abre una sesión nueva para ese Open Mat. La de ahora se queda con
            sus rolls.
          </p>
        </>
      )}

      <div style={{ display: 'flex', gap: 9, marginTop: 18 }}>
        <button className="primary" data-testid="nuevo-roll" onClick={nuevoRoll}>
          + Nuevo roll
        </button>
        <button className="ghost" data-testid="observar" onClick={observar}>👁 Observar</button>
      </div>
      <p className="hint">
        La sesión se cierra sola a medianoche. <b>👁 Observar</b> registra el roll de otros dos,
        con marcador y cronómetro en vivo.
      </p>
    </>
  );
}

/**
 * El marcador de reojo.
 *
 * En modo propio no existe: si estás rodando no lo miras, y ahí el tanteo sale
 * solo en el resumen final.
 */
function MarcadorEnVivo(
  { marcador, a, b, ms, enPausa, onPausa }: {
    marcador: Marcador; a: string; b: string;
    ms: number; enPausa: boolean; onPausa: () => void;
  },
) {
  const [flash, setFlash] = useState<Anotacion | null>(null);
  const previo = useRef(0);

  useEffect(() => {
    const n = marcador.desglose.length;
    if (n > previo.current) {
      setFlash(marcador.desglose[n - 1]);
      previo.current = n;
      const t = setTimeout(() => setFlash(null), 2200);
      return () => clearTimeout(t);
    }
    previo.current = n;
  }, [marcador]);

  return (
    <div className="marcador">
      <div className="lado a">
        <div className="quien">{a}</div>
        <div className="n" data-testid="puntos-a">{marcador.a}</div>
        {flash?.actor === 'yo' && (
          <span className="flash" key={flash.indice}>+{flash.puntos} {flash.etiqueta}</span>
        )}
      </div>

      <div className="medio">
        <button className={`crono${enPausa ? ' pausa' : ''}`} data-testid="crono"
          onClick={onPausa} aria-label={enPausa ? 'Reanudar' : 'Pausar'}>
          {mmss(ms)}
        </button>
        <div className={`aviso${enPausa ? '' : ' tenue'}`} data-testid="crono-estado">
          {enPausa ? '⏸ pausa' : 'toca para pausar'}
        </div>
      </div>

      <div className="lado b">
        <div className="quien">{b}</div>
        <div className="n" data-testid="puntos-b">{marcador.b}</div>
        {flash?.actor === 'oponente' && (
          <span className="flash" key={flash.indice}>+{flash.puntos} {flash.etiqueta}</span>
        )}
      </div>
    </div>
  );
}

function Desglose({ marcador, a, b }: { marcador: Marcador; a: string; b: string }) {
  if (!marcador.desglose.length) {
    return (
      <p className="empty" data-testid="sin-puntos">
        Ninguna acción de las que puntúan. Un roll puede acabar 0–0 y estar bien registrado.
      </p>
    );
  }
  return (
    <div className="tl">
      {marcador.desglose.map((d) => (
        <div className="ev" key={`${d.indice}-${d.clave}`}>
          <span className="dot" style={{
            background: d.actor === 'yo' ? 'var(--dato-yo)' : 'var(--dato-op)',
          }} />
          <span className="tx">
            {d.actor === 'yo' ? a : b} · {d.etiqueta}
            <small>evento {d.indice + 1}</small>
          </span>
          <span className="pill">+{d.puntos}</span>
        </div>
      ))}
    </div>
  );
}

function Pregunta(
  { p, onPosicion, onMas, onTecnica, onCancelar }: {
    p: Pendiente;
    onPosicion: (pos: Posicion) => void;
    onMas: () => void;
    onTecnica: (slug: string, objetivo: string) => void;
    onCancelar: () => void;
  },
) {
  if (p.tipo === 'posicion') {
    return (
      <>
        <h2 className="sec">{p.titulo}</h2>
        <div className="chips">
          {p.opciones.map((pos) => (
            <button className="chip" key={pos} data-testid={`pos-${pos}`}
              onClick={() => onPosicion(pos)}>{NOMBRE_POSICION[pos]}</button>
          ))}
          {p.mas && <button className="chip" onClick={onMas}>Más…</button>}
        </div>
      </>
    );
  }
  return (
    <>
      <h2 className="sec">{p.titulo}</h2>
      <div className="chips">
        {p.opciones.map(([slug, objetivo]) => (
          <button className="chip" key={slug} data-testid={`tec-${slug}`}
            onClick={() => onTecnica(slug, objetivo)}>
            {slug.replace(/_/g, ' ')}<small>{NOMBRE_OBJETIVO[objetivo]}</small>
          </button>
        ))}
      </div>
      <button className="x" style={{ marginTop: 10 }} onClick={onCancelar}>← cancelar</button>
    </>
  );
}

function Timeline(
  { eventos, nombreA, nombreB, onBorrar }:
  { eventos: EventoBorrador[]; nombreA: string; nombreB: string; onBorrar: (i: number) => void },
) {
  const NOMBRE_TIPO: Record<EventoBorrador['tipo'], string> = {
    sumision: 'Sumisión', barrida: 'Barrida', pase_guardia: 'Pase de guardia',
    derribo: 'Derribo', toma_espalda: 'Toma de espalda', escape: 'Escape',
    transicion: 'Transición',
  };
  if (!eventos.length) {
    return <p className="empty">Nada todavía. Toca una acción arriba.</p>;
  }
  return (
    <div className="tl">
      {eventos.map((e, i) => (
        <div className={`ev${e.completado ? '' : ' fail'}`} key={i}>
          <span className="dot" style={{
            background: e.actor === 'yo' ? 'var(--dato-yo)' : 'var(--dato-op)',
          }} />
          <span className="tx">
            {e.actor === 'yo' ? nombreA : nombreB} · {
              e.tecnicaSlug === 'puxada' ? 'Tira guardia' : NOMBRE_TIPO[e.tipo]
            }{e.completado ? '' : ' (falló)'}
            <small>
              {/* En una transición `posicion` es el DESTINO, no el origen. */}
              {e.tipo === 'transicion'
                ? `a ${NOMBRE_POSICION[e.posicion]}`
                : `${NOMBRE_POSICION[e.posicion]} · ${e.rol}`}
              {e.segundo != null ? ` · ${mmss(e.segundo * 1000)}` : ''}
              {e.tecnicaSlug && e.tipo === 'sumision'
                ? ` · ${e.tecnicaSlug.replace(/_/g, ' ')} → ${NOMBRE_OBJETIVO[e.objetivo]}`
                : ''}
            </small>
          </span>
          <button className="x" aria-label="Borrar evento" onClick={() => onBorrar(i)}>✕</button>
        </div>
      ))}
    </div>
  );
}
