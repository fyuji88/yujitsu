-- ============================================================
--  LOGROS · un caso que lo cumple y otro que no, por cada uno
--
--    psql ... -f db/pruebas/logros.sql
--
--  Es tedioso a proposito. Los errores de un predicado no se ven mirandolo:
--  se ven cuando `>= 3` era `> 3`, cuando se contaron los intentos fallados
--  que no tocaba, o cuando falto la guarda de volumen. La unica forma de
--  cazarlos es fabricar el roll que lo cumple y el que casi.
--
--  Cada assert apunta a un ROLL CONCRETO, asi que no importa que un roll
--  fabricado para MURO cumpla ademas IMPASABLE: se pregunta por la pareja
--  (logro, roll), no por el total.
--
--  Se limpia solo al final: todo cuelga de un practicante de pruebas.
-- ============================================================
\set ON_ERROR_STOP on

begin;

-- ------------------------------------------------------------
-- Ayudantes. Viven solo lo que dura la transaccion.
-- ------------------------------------------------------------
create or replace function pl_ses(p_pract uuid, p_fecha date, p_mod bjj_modalidad,
                                  p_quedada uuid default null)
returns uuid language sql as $$
  insert into sesiones (practicante_id, fecha, modalidad, tipo, quedada_id)
  values (p_pract, p_fecha, p_mod, 'sparring', p_quedada) returning id;
$$;

create or replace function pl_roll(p_sesion uuid, p_orden int,
                                   p_origen bjj_origen_roll default 'propio',
                                   p_resultado bjj_resultado_roll default 'sin_sumision',
                                   p_oponente uuid default null,
                                   p_registrado_por uuid default null)
returns uuid language sql as $$
  insert into rolls (sesion_id, orden, origen, resultado, oponente_id,
                     registrado_por, posicion_inicio, rol_inicio)
  values (p_sesion, p_orden, p_origen, p_resultado, p_oponente,
          p_registrado_por, 'de_pie', 'neutral')
  returning id;
$$;

create or replace function pl_ev(p_roll uuid, p_actor bjj_actor, p_tipo bjj_tipo_evento,
                                 p_pos bjj_posicion, p_rol bjj_rol,
                                 p_obj bjj_objetivo default 'ninguno',
                                 p_ok boolean default true,
                                 p_seg int default 30,
                                 p_tec uuid default null)
returns void language sql as $$
  insert into eventos (roll_id, actor, tipo, posicion, rol, objetivo,
                       completado, segundo_roll, tecnica_id)
  values (p_roll, p_actor, p_tipo, p_pos, p_rol, p_obj, p_ok, p_seg, p_tec);
$$;

-- El marcador de los asserts. Se acumulan y se cuentan al final: asi una
-- ejecucion enseña TODOS los fallos, no solo el primero.
create temporary table pl_fallos (que text) on commit drop;

create or replace function pl_toca(p_pract uuid, p_clave text, p_ref text,
                                   p_espera boolean, p_que text)
returns void language plpgsql as $$
declare v_hay boolean;
begin
  select exists (select 1 from v_logros_conseguidos
                  where practicante_id = p_pract and clave = p_clave and ref_id = p_ref)
    into v_hay;
  if v_hay <> p_espera then
    insert into pl_fallos values (
      format('%-22s %s  (esperaba %s y salio %s)', p_clave, p_que,
             case when p_espera then 'SI' else 'NO' end,
             case when v_hay then 'SI' else 'NO' end));
  end if;
end $$;

-- ------------------------------------------------------------
-- El reparto
-- ------------------------------------------------------------
do $$
declare
  v_yo    uuid;  v_rival uuid;  v_igual uuid;  v_virgen uuid;  v_coach uuid;
  v_grupo uuid;  v_quedada uuid; v_quedada2 uuid;
  v_gi uuid; v_nogi uuid; v_s uuid;
  r uuid;
  t1 uuid; t2 uuid; t3 uuid;
  d date := date '2026-06-01';           -- un lunes, para que la semana cuadre
begin
  select id into t1 from tecnicas where slug = 'armbar';
  select id into t2 from tecnicas where slug = 'kimura';
  select id into t3 from tecnicas where slug = 'mata_leao';
  select id into v_grupo from grupos order by created_at limit 1;

  -- Gente de pruebas. El rival es cinturon negro y yo blanco, para CINTURON
  -- INVISIBLE; `v_igual` es del mismo color, para el caso que NO lo cumple.
  insert into practicantes (nombre, cinturon, academia) values
    ('PL-Yo', 'blanca', 'PRUEBAS')      returning id into v_yo;
  insert into practicantes (nombre, cinturon, academia) values
    ('PL-Rival', 'negra', 'PRUEBAS')    returning id into v_rival;
  insert into practicantes (nombre, cinturon, academia) values
    ('PL-Igual', 'blanca', 'PRUEBAS')   returning id into v_igual;
  insert into practicantes (nombre, cinturon, academia) values
    ('PL-Virgen', 'blanca', 'PRUEBAS')  returning id into v_virgen;
  insert into practicantes (nombre, cinturon, academia) values
    ('PL-Coach', 'marron', 'PRUEBAS')   returning id into v_coach;

  insert into miembros_grupo (grupo_id, practicante_id, rol, estado)
  select v_grupo, x, 'miembro', 'activo'
    from unnest(array[v_yo, v_rival, v_igual, v_virgen, v_coach]) x;

  insert into quedadas (grupo_id, titulo, fecha, hora_inicio, lugar, creado_por)
  values (v_grupo, 'PL-Quedada', d, '19:00', 'PRUEBAS', v_yo) returning id into v_quedada;
  insert into quedadas (grupo_id, titulo, fecha, hora_inicio, lugar, creado_por)
  values (v_grupo, 'PL-Quedada2', d + 7, '19:00', 'PRUEBAS', v_yo) returning id into v_quedada2;

  v_gi   := pl_ses(v_yo, d, 'gi');
  v_nogi := pl_ses(v_yo, d, 'nogi');

  -- ============================================================
  --  DEFENSA
  -- ============================================================

  -- IMPASABLE. Observado, sin ningun pase del rival, y con guardia jugada.
  r := pl_roll(v_gi, 1, 'observador');
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo');
  perform pl_toca(v_yo, 'impasable', r::text, true, 'sin pases y con guardia jugada');

  -- Y la GUARDA DE VOLUMEN, que es media mitad del logro: mismo roll sin un
  -- solo evento propio desde la guardia. Sin la guarda saldria gratis.
  r := pl_roll(v_gi, 2, 'observador');
  perform pl_ev(r, 'yo', 'derribo', 'de_pie', 'neutral');
  perform pl_toca(v_yo, 'impasable', r::text, false, 'nunca jugo la guardia');

  -- Y con un pase del rival, aunque sea fallado: no cuenta.
  r := pl_roll(v_gi, 3, 'observador');
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo');
  perform pl_ev(r, 'oponente', 'pase_guardia', 'guardia_cerrada', 'arriba', 'ninguno', false);
  perform pl_toca(v_yo, 'impasable', r::text, false, 'el rival lo intento');

  -- MURO. Tres intentos del rival, ninguno dentro.
  r := pl_roll(v_gi, 4, 'observador');
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'cuello', false, 30);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'codo',   false, 60);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'hombro', false, 90);
  perform pl_toca(v_yo, 'muro', r::text, true, 'tres intentos y ninguno entra');

  -- Con DOS no llega: aqui es donde se caza el >= 3 escrito como > 3.
  r := pl_roll(v_gi, 5, 'observador');
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'cuello', false, 30);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'codo',   false, 60);
  perform pl_toca(v_yo, 'muro', r::text, false, 'solo dos intentos');

  -- Y con tres pero uno dentro, tampoco.
  r := pl_roll(v_gi, 6, 'observador');
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'cuello', false, 30);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'codo',   false, 60);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'hombro', true,  90);
  perform pl_toca(v_yo, 'muro', r::text, false, 'uno de los tres entro');

  -- HOUDINI. Tres escapes desde dominantes.
  r := pl_roll(v_gi, 7);
  perform pl_ev(r, 'yo', 'escape', 'montada', 'abajo', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'escape', 'espalda', 'abajo', 'ninguno', true, 40);
  perform pl_ev(r, 'yo', 'escape', 'cien_kilos', 'abajo', 'ninguno', true, 60);
  perform pl_toca(v_yo, 'houdini', r::text, true, 'tres escapes de dominantes');

  -- Dos desde dominante y uno desde la guardia: no.
  r := pl_roll(v_gi, 8);
  perform pl_ev(r, 'yo', 'escape', 'montada', 'abajo', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'escape', 'espalda', 'abajo', 'ninguno', true, 40);
  perform pl_ev(r, 'yo', 'escape', 'guardia_cerrada', 'abajo', 'ninguno', true, 60);
  perform pl_toca(v_yo, 'houdini', r::text, false, 'uno de los tres no era dominante');

  -- DE VUELTA. Te montan y ganas.
  r := pl_roll(v_gi, 9, 'propio', 'sumision_favor');
  perform pl_ev(r, 'oponente', 'transicion', 'montada', 'arriba', 'ninguno', true, 30);
  perform pl_ev(r, 'yo', 'sumision', 'espalda', 'arriba', 'cuello', true, 200, t3);
  perform pl_toca(v_yo, 'de_vuelta', r::text, true, 'te montan y ganas');

  -- Montas TU y ganas: no es de vuelta. Aqui se caza leer `rol` al reves.
  r := pl_roll(v_gi, 10, 'propio', 'sumision_favor');
  perform pl_ev(r, 'oponente', 'escape', 'montada', 'abajo', 'ninguno', true, 30);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 200, t3);
  perform pl_toca(v_yo, 'de_vuelta', r::text, false, 'el que monto fuiste tu');

  -- CUELLO DE ACERO
  r := pl_roll(v_gi, 11, 'observador');
  perform pl_ev(r, 'oponente', 'sumision', 'espalda', 'arriba', 'cuello', false, 30);
  perform pl_ev(r, 'oponente', 'sumision', 'espalda', 'arriba', 'cuello', false, 60);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'cuello', false, 90);
  perform pl_toca(v_yo, 'cuello_de_acero', r::text, true, 'tres al cuello y ninguna cae');

  -- Tres intentos pero uno al codo: no son tres al cuello.
  r := pl_roll(v_gi, 12, 'observador');
  perform pl_ev(r, 'oponente', 'sumision', 'espalda', 'arriba', 'cuello', false, 30);
  perform pl_ev(r, 'oponente', 'sumision', 'espalda', 'arriba', 'cuello', false, 60);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'codo',   false, 90);
  perform pl_toca(v_yo, 'cuello_de_acero', r::text, false, 'uno era al codo');

  -- SIN MARCAR. El rival no puntua.
  r := pl_roll(v_gi, 13, 'observador');
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 30);
  perform pl_toca(v_yo, 'sin_marcar', r::text, true, 'el rival no puntua');

  -- Con una barrida del rival ya puntua.
  r := pl_roll(v_gi, 14, 'observador');
  perform pl_ev(r, 'oponente', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 30);
  perform pl_toca(v_yo, 'sin_marcar', r::text, false, 'el rival barrio y puntuo');

  -- Y LA GUARDA DE VOLUMEN, que es el bug que tenia. Un roll donde no pasa
  -- nada posicional da cero puntos a los DOS, asi que sin guarda se lo
  -- llevaban los dos por no hacer nada. Aqui solo hay intentos de sumision:
  -- el rival no marca, pero el roll no se ha movido.
  r := pl_roll(v_gi, 46, 'observador');
  perform pl_ev(r, 'yo', 'sumision', 'guardia_cerrada', 'abajo', 'codo', false, 30, t1);
  perform pl_ev(r, 'oponente', 'sumision', 'guardia_cerrada', 'arriba', 'cuello', false, 60);
  perform pl_toca(v_yo, 'sin_marcar', r::text, false, 'no paso nada posicional');

  -- Con un solo evento posicional ya cuenta: el que barre una vez y no encaja
  -- nada se lo ha ganado.
  r := pl_roll(v_gi, 47, 'observador');
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 30);
  perform pl_ev(r, 'oponente', 'sumision', 'guardia_cerrada', 'arriba', 'cuello', false, 60);
  perform pl_toca(v_yo, 'sin_marcar', r::text, true, 'una barrida basta de actividad');


  -- ============================================================
  --  ATAQUE
  -- ============================================================

  -- EL RODILLO
  r := pl_roll(v_gi, 15);
  perform pl_ev(r, 'yo', 'pase_guardia', 'guardia_cerrada', 'arriba', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'pase_guardia', 'media_guardia',   'arriba', 'ninguno', true, 40);
  perform pl_ev(r, 'yo', 'pase_guardia', 'guardia_abierta', 'arriba', 'ninguno', true, 60);
  perform pl_toca(v_yo, 'rodillo', r::text, true, 'tres pases completados');

  -- Tres pases pero uno fallado: no.
  r := pl_roll(v_gi, 16);
  perform pl_ev(r, 'yo', 'pase_guardia', 'guardia_cerrada', 'arriba', 'ninguno', true,  20);
  perform pl_ev(r, 'yo', 'pase_guardia', 'media_guardia',   'arriba', 'ninguno', true,  40);
  perform pl_ev(r, 'yo', 'pase_guardia', 'guardia_abierta', 'arriba', 'ninguno', false, 60);
  perform pl_toca(v_yo, 'rodillo', r::text, false, 'uno de los tres fallo');

  -- LIMPIO. Finalizas sin fallar antes.
  r := pl_roll(v_gi, 17, 'observador');
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 100, t3);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'codo',   false, 200, t1);
  perform pl_toca(v_yo, 'limpio', r::text, true, 'el fallo fue despues, no antes');

  -- Fallas y luego finalizas: no es limpio.
  r := pl_roll(v_gi, 18, 'observador');
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'codo',   false, 100, t1);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true,  200, t3);
  perform pl_toca(v_yo, 'limpio', r::text, false, 'fallo antes de entrar');

  -- RELAMPAGO
  r := pl_roll(v_gi, 19);
  perform pl_ev(r, 'yo', 'sumision', 'guardia_cerrada', 'abajo', 'cuello', true, 45, t3);
  perform pl_toca(v_yo, 'relampago', r::text, true, 'finaliza en el segundo 45');

  -- En el 61 ya no. Y sin sello, tampoco: no se estima.
  r := pl_roll(v_gi, 20);
  perform pl_ev(r, 'yo', 'sumision', 'guardia_cerrada', 'abajo', 'cuello', true, 61, t3);
  perform pl_toca(v_yo, 'relampago', r::text, false, 'finaliza en el 61');
  r := pl_roll(v_gi, 21);
  perform pl_ev(r, 'yo', 'sumision', 'guardia_cerrada', 'abajo', 'cuello', true, null, t3);
  perform pl_toca(v_yo, 'relampago', r::text, false, 'sin sello de segundo');

  -- LA CADENA, en orden.
  r := pl_roll(v_gi, 22);
  perform pl_ev(r, 'yo', 'pase_guardia', 'guardia_cerrada', 'arriba', 'ninguno', true, 30);
  perform pl_ev(r, 'yo', 'transicion',   'montada',         'arriba', 'ninguno', true, 60);
  perform pl_ev(r, 'yo', 'toma_espalda', 'montada',         'arriba', 'ninguno', true, 90);
  perform pl_toca(v_yo, 'la_cadena', r::text, true, 'pase, monta y espalda en orden');

  -- Los mismos tres eslabones DESORDENADOS no valen.
  r := pl_roll(v_gi, 23);
  perform pl_ev(r, 'yo', 'toma_espalda', 'montada',         'arriba', 'ninguno', true, 30);
  perform pl_ev(r, 'yo', 'transicion',   'montada',         'arriba', 'ninguno', true, 60);
  perform pl_ev(r, 'yo', 'pase_guardia', 'guardia_cerrada', 'arriba', 'ninguno', true, 90);
  perform pl_toca(v_yo, 'la_cadena', r::text, false, 'los eslabones al reves');

  -- QUINCE. Monta (4) + espalda (4) + rodilla en barriga (2) + pase (3) +
  -- barrida (2) = 15.
  r := pl_roll(v_gi, 24);
  perform pl_ev(r, 'yo', 'barrida',      'guardia_cerrada',    'abajo',  'ninguno', true, 10);
  perform pl_ev(r, 'yo', 'pase_guardia', 'guardia_cerrada',    'arriba', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'transicion',   'rodilla_en_barriga', 'arriba', 'ninguno', true, 30);
  perform pl_ev(r, 'yo', 'transicion',   'montada',            'arriba', 'ninguno', true, 40);
  perform pl_ev(r, 'yo', 'toma_espalda', 'montada',            'arriba', 'ninguno', true, 50);
  perform pl_toca(v_yo, 'quince', r::text, true, 'quince puntos justos');

  -- Quitando la barrida se queda en 13.
  r := pl_roll(v_gi, 25);
  perform pl_ev(r, 'yo', 'pase_guardia', 'guardia_cerrada',    'arriba', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'transicion',   'rodilla_en_barriga', 'arriba', 'ninguno', true, 30);
  perform pl_ev(r, 'yo', 'transicion',   'montada',            'arriba', 'ninguno', true, 40);
  perform pl_ev(r, 'yo', 'toma_espalda', 'montada',            'arriba', 'ninguno', true, 50);
  perform pl_toca(v_yo, 'quince', r::text, false, 'trece no son quince');

  -- GUARDIA DE HIERRO
  r := pl_roll(v_gi, 26);
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'barrida', 'mariposa',        'abajo', 'ninguno', true, 40);
  perform pl_ev(r, 'yo', 'barrida', 'de_la_riva',      'abajo', 'ninguno', true, 60);
  perform pl_toca(v_yo, 'guardia_de_hierro', r::text, true, 'tres barridas');
  r := pl_roll(v_gi, 27);
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'barrida', 'mariposa',        'abajo', 'ninguno', true, 40);
  perform pl_toca(v_yo, 'guardia_de_hierro', r::text, false, 'solo dos barridas');

  -- EL MOCHILERO
  r := pl_roll(v_gi, 28);
  perform pl_ev(r, 'yo', 'toma_espalda', 'montada', 'arriba', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'toma_espalda', 'tortuga', 'arriba', 'ninguno', true, 60);
  perform pl_toca(v_yo, 'mochilero', r::text, true, 'dos espaldas');
  r := pl_roll(v_gi, 29);
  perform pl_ev(r, 'yo', 'toma_espalda', 'montada', 'arriba', 'ninguno', true, 20);
  perform pl_toca(v_yo, 'mochilero', r::text, false, 'solo una espalda');

  -- PIERNAS. Solo nogi: el MISMO roll en gi no cuenta, y ahi se ve que la
  -- regla la aplica el catalogo y no el predicado.
  r := pl_roll(v_nogi, 1);
  perform pl_ev(r, 'yo', 'sumision', 'cincuenta_cincuenta', 'neutral', 'rodilla', true, 100);
  perform pl_toca(v_yo, 'piernas', r::text, true, 'pierna en nogi');
  r := pl_roll(v_gi, 30);
  perform pl_ev(r, 'yo', 'sumision', 'cincuenta_cincuenta', 'neutral', 'rodilla', true, 100);
  perform pl_toca(v_yo, 'piernas', r::text, false, 'la misma pierna, pero en gi');

  -- CINTURON INVISIBLE
  r := pl_roll(v_gi, 31, 'propio', 'sumision_favor', v_rival);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 100, t3);
  perform pl_toca(v_yo, 'cinturon_invisible', r::text, true, 'finaliza a un negro');
  r := pl_roll(v_gi, 32, 'propio', 'sumision_favor', v_igual);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 100, t3);
  perform pl_toca(v_yo, 'cinturon_invisible', r::text, false, 'el rival es del mismo color');

  -- ============================================================
  --  ESTILO
  -- ============================================================

  -- EL PULPO. Cinco intentos, entren o no.
  r := pl_roll(v_gi, 33);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', false, 10, t3);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'codo',   false, 20, t1);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'hombro', false, 30, t2);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', false, 40, t3);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'codo',   true,  50, t1);
  perform pl_toca(v_yo, 'pulpo', r::text, true, 'cinco intentos');
  r := pl_roll(v_gi, 34);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', false, 10, t3);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'codo',   false, 20, t1);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'hombro', false, 30, t2);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true,  40, t3);
  perform pl_toca(v_yo, 'pulpo', r::text, false, 'cuatro intentos');

  -- EL ARTISTA. Tres tecnicas distintas EN LA MISMA QUEDADA. Repartidas en
  -- dos quedadas no cuenta, que es la prueba del ambito.
  v_s := pl_ses(v_yo, d, 'gi', v_quedada);
  r := pl_roll(v_s, 1);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 100, t3);
  r := pl_roll(v_s, 2);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'codo',   true, 100, t1);
  r := pl_roll(v_s, 3);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'hombro', true, 100, t2);
  perform pl_toca(v_yo, 'artista', v_quedada::text, true, 'tres tecnicas en una quedada');

  v_s := pl_ses(v_yo, d + 7, 'gi', v_quedada2);
  r := pl_roll(v_s, 1);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 100, t3);
  r := pl_roll(v_s, 2);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'codo',   true, 100, t1);
  perform pl_toca(v_yo, 'artista', v_quedada2::text, false, 'solo dos en esta quedada');

  -- AMBIDIESTRO. Arriba y abajo en la misma quedada. La primera ya tiene tres
  -- desde arriba; le falta una desde abajo.
  perform pl_toca(v_yo, 'ambidiestro', v_quedada::text, false, 'todas desde arriba');
  v_s := pl_ses(v_yo, d, 'gi', v_quedada);
  r := pl_roll(v_s, 9);
  perform pl_ev(r, 'yo', 'sumision', 'guardia_cerrada', 'abajo', 'cuello', true, 100, t3);
  perform pl_toca(v_yo, 'ambidiestro', v_quedada::text, true, 'y ahora una desde abajo');

  -- SIN GI, SIN PROBLEMA. Finaliza en gi y en nogi la misma semana.
  -- `v_gi` y `v_nogi` son del mismo dia y ya tienen sumisiones completadas.
  perform pl_toca(v_yo, 'sin_gi_sin_problema',
                  date_trunc('week', d)::date::text, true, 'gi y nogi la misma semana');

  -- ============================================================
  --  CONSTANCIA
  -- ============================================================

  -- EL NOTARIO. La quedada 1 tiene cuatro rolls suyos y todos con eventos.
  perform pl_toca(v_yo, 'notario', v_quedada::text, true, 'cuatro rolls y ninguno vacio');

  -- Un roll sin eventos en la quedada 2, y ya no cuenta. Antes hacen falta
  -- tres para pasar la guarda de volumen.
  v_s := pl_ses(v_yo, d + 7, 'gi', v_quedada2);
  r := pl_roll(v_s, 5);
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 20);
  r := pl_roll(v_s, 6);                                  -- este se queda vacio
  perform pl_toca(v_yo, 'notario', v_quedada2::text, false, 'un roll quedo sin eventos');

  -- OJO DEL COACH. Diez rolls observados en el mes, contados por observacion
  -- y no por fila: una observacion escribe DOS rolls espejados.
  v_s := pl_ses(v_rival, d, 'gi');
  for i in 1..9 loop
    r := pl_roll(v_s, i, 'observador', 'sin_sumision', v_igual, v_coach);
    update rolls set roll_grupo_id = gen_random_uuid() where id = r;
    perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 20);
  end loop;
  perform pl_toca(v_coach, 'ojo_del_coach', date_trunc('month', d)::date::text,
                  false, 'nueve observaciones');
  r := pl_roll(v_s, 10, 'observador', 'sin_sumision', v_igual, v_coach);
  update rolls set roll_grupo_id = gen_random_uuid() where id = r;
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 20);
  perform pl_toca(v_coach, 'ojo_del_coach', date_trunc('month', d)::date::text,
                  true, 'y con la decima, si');

  -- DOBLE SESION. `v_gi` y `v_nogi` son del mismo dia y a estas alturas los dos
  -- tienen rolls. Ojo con el sitio: puesto mas arriba fallaba, porque el roll
  -- de la sesion nogi todavia no existia — los asserts miran el estado DEL
  -- MOMENTO, no el final.
  perform pl_toca(v_yo, 'doble_sesion', d::text, true, 'dos sesiones el mismo dia');
  perform pl_toca(v_virgen, 'doble_sesion', d::text, false, 'solo una sesion ese dia');

  -- SEMANA COMPLETA. Tres dias distintos en la misma semana. `v_gi` y
  -- `v_nogi` son el mismo dia, asi que hacen falta dos dias mas.
  perform pl_toca(v_yo, 'semana_completa', date_trunc('week', d)::date::text,
                  false, 'todo el mismo dia');
  v_s := pl_ses(v_yo, d + 1, 'gi');   r := pl_roll(v_s, 1);
  v_s := pl_ses(v_yo, d + 2, 'gi');   r := pl_roll(v_s, 1);
  perform pl_toca(v_yo, 'semana_completa', date_trunc('week', d)::date::text,
                  true, 'tres dias distintos');

  -- ============================================================
  --  CACHONDEO — apagados mientras el grupo no los pida
  -- ============================================================
  r := pl_roll(v_gi, 40);
  perform pl_ev(r, 'oponente', 'pase_guardia', 'guardia_cerrada', 'arriba', 'ninguno', true, 10);
  perform pl_ev(r, 'oponente', 'pase_guardia', 'media_guardia',   'arriba', 'ninguno', true, 20);
  perform pl_ev(r, 'oponente', 'pase_guardia', 'guardia_abierta', 'arriba', 'ninguno', true, 30);
  perform pl_ev(r, 'oponente', 'pase_guardia', 'de_la_riva',      'arriba', 'ninguno', true, 40);
  perform pl_toca(v_yo, 'peaje', r::text, false, 'con el cachondeo apagado no existe');

  update grupos set modo_cachondeo = true where id = v_grupo;
  perform pl_toca(v_yo, 'peaje', r::text, true, 'y encendido, si');

  r := pl_roll(v_gi, 41);
  perform pl_ev(r, 'oponente', 'pase_guardia', 'guardia_cerrada', 'arriba', 'ninguno', true, 10);
  perform pl_ev(r, 'oponente', 'pase_guardia', 'media_guardia',   'arriba', 'ninguno', true, 20);
  perform pl_ev(r, 'oponente', 'pase_guardia', 'guardia_abierta', 'arriba', 'ninguno', true, 30);
  perform pl_toca(v_yo, 'peaje', r::text, false, 'tres pases no son cuatro');

  -- EL ANCLA. Mas de dos minutos entre dos eventos seguidos SIN cambio de
  -- posicion.
  r := pl_roll(v_gi, 42);
  perform pl_ev(r, 'yo', 'sumision', 'media_guardia', 'abajo', 'codo', false, 30, t1);
  perform pl_ev(r, 'yo', 'sumision', 'media_guardia', 'abajo', 'codo', false, 200, t1);
  perform pl_toca(v_yo, 'el_ancla', r::text, true, 'ciento setenta segundos clavado ahi');
  r := pl_roll(v_gi, 43);
  perform pl_ev(r, 'yo', 'sumision', 'media_guardia',   'abajo', 'codo', false, 30, t1);
  perform pl_ev(r, 'yo', 'sumision', 'guardia_cerrada', 'abajo', 'codo', false, 200, t1);
  perform pl_toca(v_yo, 'el_ancla', r::text, false, 'hubo hueco, pero cambio de posicion');

  -- DONANTE
  r := pl_roll(v_gi, 44);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'cuello', true, 30);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'codo',   true, 60);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'hombro', true, 90);
  perform pl_toca(v_yo, 'donante', r::text, true, 'tres encajadas');
  r := pl_roll(v_gi, 45);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'cuello', true,  30);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'codo',   true,  60);
  perform pl_ev(r, 'oponente', 'sumision', 'montada', 'arriba', 'hombro', false, 90);
  perform pl_toca(v_yo, 'donante', r::text, false, 'la tercera no entro');

  update grupos set modo_cachondeo = false where id = v_grupo;

  -- ============================================================
  --  PRIMERA VEZ y JUGUETE NUEVO — con practicante virgen, que dependen de
  --  todo el historico y se contaminan con lo de arriba.
  -- ============================================================
  v_s := pl_ses(v_virgen, d, 'gi');
  r := pl_roll(v_s, 1);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 100, t3);
  perform pl_toca(v_virgen, 'primera_vez',   r::text, true, 'estrena la montada');
  perform pl_toca(v_virgen, 'juguete_nuevo', r::text, true, 'estrena el mata leao');

  -- La misma posicion y la misma tecnica otra vez: ya no estrena nada.
  v_s := pl_ses(v_virgen, d + 1, 'gi');
  r := pl_roll(v_s, 1);
  perform pl_ev(r, 'yo', 'sumision', 'montada', 'arriba', 'cuello', true, 100, t3);
  perform pl_toca(v_virgen, 'primera_vez',   r::text, false, 'la montada ya no es nueva');
  perform pl_toca(v_virgen, 'juguete_nuevo', r::text, false, 'el mata leao tampoco');

  -- Posicion nueva con tecnica vieja: estrena posicion y no tecnica.
  v_s := pl_ses(v_virgen, d + 2, 'gi');
  r := pl_roll(v_s, 1);
  perform pl_ev(r, 'yo', 'sumision', 'espalda', 'arriba', 'cuello', true, 100, t3);
  perform pl_toca(v_virgen, 'primera_vez',   r::text, true,  'la espalda si es nueva');
  perform pl_toca(v_virgen, 'juguete_nuevo', r::text, false, 'pero la tecnica no');

  -- ============================================================
  --  LA REGLA DEL OBSERVADOR, en su propia prueba
  --
  --  El MISMO roll, cambiando solo `origen`. Los cinco de ausencia solo
  --  cuentan observados; los otros cuentan en los dos.
  -- ============================================================
  r := pl_roll(v_gi, 50, 'propio');
  perform pl_ev(r, 'yo', 'barrida', 'guardia_cerrada', 'abajo', 'ninguno', true, 20);
  perform pl_ev(r, 'yo', 'barrida', 'mariposa',        'abajo', 'ninguno', true, 40);
  perform pl_ev(r, 'yo', 'barrida', 'de_la_riva',      'abajo', 'ninguno', true, 60);
  perform pl_toca(v_yo, 'impasable', r::text, false, 'de ausencia y sin observador');
  perform pl_toca(v_yo, 'sin_marcar', r::text, false, 'de ausencia y sin observador');
  perform pl_toca(v_yo, 'guardia_de_hierro', r::text, true, 'de presencia: cuenta igual');

  update rolls set origen = 'observador' where id = r;
  perform pl_toca(v_yo, 'impasable', r::text, true, 'el mismo roll, ya observado');
  perform pl_toca(v_yo, 'sin_marcar', r::text, true, 'el mismo roll, ya observado');
  perform pl_toca(v_yo, 'guardia_de_hierro', r::text, true, 'y el de presencia no cambia');
end $$;

-- ------------------------------------------------------------
-- El recuento
-- ------------------------------------------------------------
do $$
declare v_n int; f record;
begin
  select count(*) into v_n from pl_fallos;
  if v_n = 0 then
    raise notice 'PASS  los 28 logros, cada uno con su caso que cumple y su caso que no';
  else
    for f in select que from pl_fallos loop
      raise notice 'FALLO %', f.que;
    end loop;
    raise exception '% predicados dan un resultado distinto del esperado', v_n;
  end if;
end $$;

-- Todo lo fabricado cuelga de los practicantes de pruebas.
delete from practicantes where academia = 'PRUEBAS';
delete from quedadas where lugar = 'PRUEBAS';
drop function pl_ses(uuid, date, bjj_modalidad, uuid);
drop function pl_roll(uuid, int, bjj_origen_roll, bjj_resultado_roll, uuid, uuid);
drop function pl_ev(uuid, bjj_actor, bjj_tipo_evento, bjj_posicion, bjj_rol,
                    bjj_objetivo, boolean, int, uuid);
drop function pl_toca(uuid, text, text, boolean, text);

commit;

\echo ''
\echo '######## LOGROS: CADA PREDICADO, CON SU SI Y SU NO ########'
