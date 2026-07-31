/* eslint-disable */
/**
 * GENERADO POR scripts/generar-tipos.py. NO SE EDITA A MANO.
 *
 * Es el esquema tal cual esta en Postgres. No lleva comentarios ni
 * decisiones: para eso esta `database.types.ts`, que es un subconjunto
 * escrito a mano y que COMPRUEBA CONTRA ESTE en tiempo de compilacion.
 *
 * Si esto y la base se separan, el CI se pone rojo: regenera y commitea.
 */

export interface Tablas {
  enfoques: {
    id: string;
    practicante_id: string;
    desde: string;
    hasta: string | null;
    texto: string | null;
    posiciones: ('de_pie' | 'clinch' | 'guardia_cerrada' | 'media_guardia' | 'mariposa' | 'de_la_riva' | 'de_la_riva_inversa' | 'arana' | 'lasso' | 'collar_manga' | 'x_guard' | 'single_leg_x' | 'guardia_sentada' | 'cincuenta_cincuenta' | 'guardia_abierta' | 'montada' | 'cien_kilos' | 'kesa_gatame' | 'norte_sur' | 'rodilla_en_barriga' | 'espalda' | 'tortuga' | 'scramble' | 'otra')[];
    tecnicas: string[];
    created_at: string;
  };
  equipos: {
    id: string;
    nombre: string;
    slug: string;
    ciudad: string | null;
    codigo_union: string;
    modo_cachondeo: boolean;
    creado_por: string | null;
    created_at: string;
    color_acento: string;
  };
  eventos: {
    id: string;
    roll_id: string;
    actor: 'yo' | 'oponente';
    tipo: 'sumision' | 'barrida' | 'pase_guardia' | 'derribo' | 'toma_espalda' | 'escape' | 'transicion';
    posicion: 'de_pie' | 'clinch' | 'guardia_cerrada' | 'media_guardia' | 'mariposa' | 'de_la_riva' | 'de_la_riva_inversa' | 'arana' | 'lasso' | 'collar_manga' | 'x_guard' | 'single_leg_x' | 'guardia_sentada' | 'cincuenta_cincuenta' | 'guardia_abierta' | 'montada' | 'cien_kilos' | 'kesa_gatame' | 'norte_sur' | 'rodilla_en_barriga' | 'espalda' | 'tortuga' | 'scramble' | 'otra';
    rol: 'arriba' | 'abajo' | 'neutral';
    objetivo: 'cuello' | 'hombro' | 'codo' | 'muneca' | 'biceps' | 'columna' | 'cadera' | 'rodilla' | 'tobillo_pie' | 'pantorrilla' | 'ninguno';
    tecnica_id: string | null;
    completado: boolean;
    minuto: number | null;
    notas: string | null;
    created_at: string;
    segundo_roll: number | null;
    tecnica_precisada_por: string | null;
    tecnica_precisada_en: string | null;
    par_evento_id: string | null;
  };
  inscripciones: {
    id: string;
    quedada_id: string;
    practicante_id: string;
    estado: 'apuntado' | 'lista_espera' | 'cancelado';
    orden_en_lista: number | null;
    es_externo: boolean;
    created_at: string;
  };
  logros: {
    clave: string;
    nombre: string;
    descripcion: string;
    descripcion_tecnica: string;
    familia: 'defensa' | 'ataque' | 'estilo' | 'constancia' | 'cachondeo';
    rareza: 'comun' | 'poco_comun' | 'raro';
    ambito: 'roll' | 'quedada' | 'semana' | 'mes' | 'dia';
    requiere_observador: boolean;
    solo_nogi: boolean;
    min_volumen: unknown;
  };
  miembros_equipo: {
    equipo_id: string;
    practicante_id: string;
    rol_en_equipo: 'admin' | 'miembro';
    estado: 'activo' | 'baja';
    created_at: string;
  };
  posiciones: {
    codigo: 'de_pie' | 'clinch' | 'guardia_cerrada' | 'media_guardia' | 'mariposa' | 'de_la_riva' | 'de_la_riva_inversa' | 'arana' | 'lasso' | 'collar_manga' | 'x_guard' | 'single_leg_x' | 'guardia_sentada' | 'cincuenta_cincuenta' | 'guardia_abierta' | 'montada' | 'cien_kilos' | 'kesa_gatame' | 'norte_sur' | 'rodilla_en_barriga' | 'espalda' | 'tortuga' | 'scramble' | 'otra';
    nombre: string;
    categoria: 'neutral' | 'guardia' | 'dominante' | 'transicion';
    es_guardia: boolean | null;
    core_v1: boolean;
  };
  practicantes: {
    id: string;
    user_id: string | null;
    nombre: string;
    apodo: string | null;
    cinturon: 'blanca' | 'azul' | 'morada' | 'marron' | 'negra';
    grados: number;
    peso_kg: number | null;
    academia: string | null;
    usa_sistema: boolean;
    creado_por: string | null;
    created_at: string;
  };
  quedada_informes: {
    quedada_id: string;
    datos: unknown;
    generado_por: string | null;
    generado_at: string;
  };
  quedadas: {
    id: string;
    equipo_id: string;
    titulo: string;
    fecha: string;
    hora_inicio: string | null;
    duracion_min: number | null;
    lugar: string | null;
    plazas_max: number | null;
    modalidad: 'gi' | 'nogi' | 'mixto';
    admite_externos: boolean;
    token_invitacion: string;
    notas: string | null;
    estado: 'abierta' | 'cerrada' | 'cancelada';
    creado_por: string | null;
    created_at: string;
  };
  reacciones: {
    id: string;
    practicante_id: string;
    item_tipo: string;
    referencia_id: string;
    emoji: string;
    created_at: string;
  };
  reto_participaciones: {
    id: string;
    reto_id: string;
    practicante_id: string;
    progreso: number;
    completado: boolean;
    created_at: string;
  };
  retos: {
    id: string;
    creador_id: string;
    nombre: string;
    descripcion: string | null;
    tipo_regla: 'solo_objetivo' | 'solo_posicion' | 'solo_tecnica' | 'solo_tipo_evento' | 'conteo_libre';
    regla: unknown;
    objetivo_cantidad: number;
    fecha_inicio: string;
    fecha_fin: string;
    created_at: string;
  };
  rolls: {
    id: string;
    sesion_id: string;
    oponente_id: string | null;
    orden_en_sesion: number | null;
    modalidad: 'gi' | 'nogi' | 'mixto';
    duracion_min: number | null;
    posicion_inicio: 'de_pie' | 'clinch' | 'guardia_cerrada' | 'media_guardia' | 'mariposa' | 'de_la_riva' | 'de_la_riva_inversa' | 'arana' | 'lasso' | 'collar_manga' | 'x_guard' | 'single_leg_x' | 'guardia_sentada' | 'cincuenta_cincuenta' | 'guardia_abierta' | 'montada' | 'cien_kilos' | 'kesa_gatame' | 'norte_sur' | 'rodilla_en_barriga' | 'espalda' | 'tortuga' | 'scramble' | 'otra';
    rol_inicio: 'arriba' | 'abajo' | 'neutral';
    resultado: 'sumision_favor' | 'sumision_contra' | 'sin_sumision' | 'no_registrado';
    autovaloracion: number | null;
    intensidad: number | null;
    notas: string | null;
    created_at: string;
    registrado_por: string | null;
    origen: 'propio' | 'observador';
    par_id: string;
  };
  sesiones: {
    id: string;
    practicante_id: string;
    fecha: string;
    academia: string | null;
    modalidad: 'gi' | 'nogi' | 'mixto';
    formato: 'tecnica' | 'drilling' | 'sparring' | 'open_mat' | 'competicion' | 'privada';
    duracion_min: number | null;
    tematica: string | null;
    energia: number | null;
    animo: number | null;
    notas: string | null;
    created_at: string;
    equipo_id: string | null;
    quedada_id: string | null;
  };
  tecnicas: {
    id: string;
    slug: string;
    nombre: string;
    alias: string[];
    tipo: 'sumision' | 'barrida' | 'pase_guardia' | 'derribo' | 'toma_espalda' | 'escape' | 'transicion';
    objetivo_default: 'cuello' | 'hombro' | 'codo' | 'muneca' | 'biceps' | 'columna' | 'cadera' | 'rodilla' | 'tobillo_pie' | 'pantorrilla' | 'ninguno' | null;
    solo_gi: boolean;
    created_at: string;
    variante_de: string | null;
    control: 'brazo' | 'pierna' | 'cuerpo' | null;
    nivel: number;
    nivel_referido: number | null;
    mecanica_id: string | null;
  };
}
