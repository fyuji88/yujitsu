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
export type TipoEvento =
  | 'sumision' | 'barrida' | 'pase_guardia' | 'derribo' | 'toma_espalda' | 'escape';
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

export interface SesionInsert {
  id: string;
  practicante_id: string;
  fecha: string;
  academia?: string | null;
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
  notas?: string | null;
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
