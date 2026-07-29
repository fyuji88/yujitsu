/**
 * Tipos de la base de datos.
 *
 * Esto es un subconjunto escrito a mano con las tablas que usa la app. Para el
 * fichero completo (todas las vistas y funciones) regeneradlo con:
 *
 *   npx supabase gen types typescript --project-id idzlxkxeadrcolcnmoeo \
 *     > src/lib/database.types.ts
 *
 * Los valores de los enums salen del esquema real: si alguien cambia el
 * vocabulario en Postgres y no regenera esto, el compilador se queja. Ese es
 * justo el punto de tenerlo tipado.
 */

export type Cinturon = 'blanca' | 'azul' | 'morada' | 'marron' | 'negra';
export type Modalidad = 'gi' | 'nogi' | 'mixto';
export type TipoSesion =
  | 'tecnica' | 'drilling' | 'sparring' | 'open_mat' | 'competicion' | 'privada';
export type Actor = 'yo' | 'oponente';
export type Rol = 'arriba' | 'abajo' | 'neutral';
export type GrupoPosicion = 'neutral' | 'guardia' | 'dominante' | 'transicion';
export type Posicion =
  | 'de_pie' | 'clinch'
  | 'guardia_cerrada' | 'media_guardia' | 'mariposa' | 'de_la_riva'
  | 'de_la_riva_inversa' | 'arana' | 'lasso' | 'collar_manga' | 'x_guard'
  | 'single_leg_x' | 'guardia_sentada' | 'cincuenta_cincuenta' | 'guardia_abierta'
  | 'montada' | 'cien_kilos' | 'kesa_gatame' | 'norte_sur' | 'rodilla_en_barriga'
  | 'espalda' | 'tortuga'
  | 'scramble' | 'otra';
export type Objetivo =
  | 'cuello' | 'hombro' | 'codo' | 'muneca' | 'biceps' | 'columna' | 'cadera'
  | 'rodilla' | 'tobillo_pie' | 'pantorrilla' | 'ninguno';
/**
 * Los tipos de evento.
 *
 * `transicion` es la excepción a la regla de lectura de `posicion`: en todos
 * los demás tipos, `posicion` es desde dónde se hizo la acción; en una
 * transición es **el destino**, dónde acaba el actor. Existe porque lo que
 * interesa de una transición es dónde te deja, y porque sin ella los puntos de
 * montada y rodilla en barriga no se podrían registrar.
 */
export type TipoEvento =
  | 'sumision' | 'barrida' | 'pase_guardia' | 'derribo' | 'toma_espalda' | 'escape'
  | 'transicion';
export type ResultadoRoll =
  | 'sumision_favor' | 'sumision_contra' | 'sin_sumision' | 'no_registrado';
export type OrigenRoll = 'propio' | 'observador';

export interface PracticanteRow {
  id: string;
  user_id: string | null;
  nombre: string;
  apodo: string | null;
  cinturon: Cinturon;
  grados: number;
  peso_kg: number | null;
  academia: string | null;
  usa_sistema: boolean;
  creado_por: string | null;
  created_at: string;
}

export type RolGrupo = 'admin' | 'miembro';
export type EstadoMiembro = 'activo' | 'baja';
export type EstadoQuedada = 'abierta' | 'cerrada' | 'cancelada';
export type EstadoInscripcion = 'apuntado' | 'lista_espera' | 'cancelado';

export interface GrupoRow {
  id: string;
  nombre: string;
  slug: string;
  ciudad: string | null;
  /** Solo lo ve quien es miembro; el admin lo dice en el vestuario. */
  codigo_union: string;
  modo_cachondeo: boolean;
  created_at: string;
}

export interface MiembroRow {
  grupo_id: string;
  practicante_id: string;
  rol: RolGrupo;
  estado: EstadoMiembro;
  created_at: string;
}

export interface QuedadaRow {
  id: string;
  grupo_id: string;
  titulo: string;
  fecha: string;
  hora_inicio: string | null;
  duracion_min: number | null;
  lugar: string | null;
  plazas_max: number | null;
  modalidad: Modalidad;
  admite_externos: boolean;
  token_invitacion: string;
  notas: string | null;
  estado: EstadoQuedada;
  creado_por: string | null;
  created_at: string;
}

export interface InscripcionRow {
  id: string;
  quedada_id: string;
  practicante_id: string;
  estado: EstadoInscripcion;
  orden: number | null;
  es_externo: boolean;
  created_at: string;
}

export interface SesionInsert {
  id: string;
  practicante_id: string;
  fecha: string;
  academia?: string | null;
  /** De qué grupo es. Sustituye al texto libre de `academia`. */
  grupo_id?: string | null;
  /**
   * A qué quedada pertenece, si es que hay una. A nivel de sesión y no de
   * roll: todos los rolls de esa tarde en ese sitio son de esa quedada.
   */
  quedada_id?: string | null;
  modalidad: Modalidad;
  tipo: TipoSesion;
  duracion_min?: number | null;
  tematica?: string | null;
  energia?: number | null;
  animo?: number | null;
  molestias?: string | null;
  notas?: string | null;
}

export interface RollInsert {
  id: string;
  sesion_id: string;
  oponente_id: string | null;
  orden: number | null;
  modalidad: Modalidad;
  duracion_min?: number | null;
  posicion_inicio: Posicion;
  rol_inicio: Rol;
  resultado: ResultadoRoll;
  autovaloracion?: number | null;
  intensidad?: number | null;
  notas?: string | null;
  origen: OrigenRoll;
  registrado_por?: string | null;
}

export interface EventoInsert {
  id: string;
  roll_id: string;
  actor: Actor;
  tipo: TipoEvento;
  posicion: Posicion;
  rol: Rol;
  objetivo: Objetivo;
  tecnica_id: string | null;
  completado: boolean;
  minuto?: number | null;
  /**
   * Segundo del roll en que ocurrió, del cronómetro del observador.
   *
   * Se sella en segundos y no en minutos aunque hoy nadie mida nada por debajo
   * del minuto: el cronómetro ya está corriendo, así que la precisión sale
   * gratis, y el análisis de posesión que viene después la necesita. Un dato
   * que no capturas no lo recuperas luego.
   */
  segundo_roll?: number | null;
  notas?: string | null;
}

/**
 * Un evento tal y como viaja a la RPC del modo observador.
 *
 * La técnica va por **slug**, no por id: el diccionario se resuelve dentro de
 * Postgres. Así el observador no depende de tener la caché de técnicas al día,
 * y un slug que no exista no tira el evento — entra con `tecnica_id` null y
 * sigue alimentando el heatmap por posición y objetivo.
 */
export interface EventoObservado {
  actor: Actor;
  tipo: TipoEvento;
  posicion: Posicion;
  rol: Rol;
  objetivo: Objetivo;
  tecnica_slug: string | null;
  completado: boolean;
  /** El sello del cronómetro. `minuto` lo deriva Postgres a partir de esto. */
  segundo_roll: number | null;
}

/**
 * Argumentos de `registrar_roll_observado()`.
 *
 * Los nombres son literalmente los de los parámetros en Postgres: PostgREST
 * los empareja por nombre, así que renombrar uno aquí rompe la llamada.
 * `p_grupo` es el `roll_grupo_id`, generado en el cliente — es la clave de
 * idempotencia que hace que reintentar no duplique el roll.
 */
export interface ArgsRollObservado {
  p_grupo: string;
  p_practicante_a: string;
  p_practicante_b: string;
  p_fecha: string;
  p_modalidad: Modalidad;
  p_duracion_min: number | null;
  /**
   * Desde dónde arrancó el roll. En clase se empieza constantemente desde una
   * posición pactada ("empezáis con la guardia cerrada puesta"), y antes esa
   * información se perdía: todo entraba como de_pie / neutral.
   *
   * `p_rol_inicio` describe al **practicante A**. Al espejar a B se invierte,
   * mientras que `p_posicion_inicio` se mantiene, porque es física y es la
   * misma para los dos.
   */
  p_posicion_inicio: Posicion;
  p_rol_inicio: Rol;
  p_resultado: ResultadoRoll;
  p_eventos: EventoObservado[];
}

export interface TecnicaRow {
  id: string;
  slug: string;
  nombre: string;
  tipo: TipoEvento;
  objetivo_default: Objetivo | null;
}

export interface PosicionRow {
  codigo: Posicion;
  nombre: string;
  grupo: GrupoPosicion;
  es_guardia: boolean | null;
  core_v1: boolean;
}
