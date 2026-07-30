-- ============================================================
--  yujitsu · catálogo de logros
--  Pensado para pegarse dentro de la migración bjj_21_logros.
--  Los nombres están cerrados; el `predicado` de cada fila es la
--  especificación en lenguaje natural, y va como comentario en la
--  columna `descripcion_tecnica` para que quien lo lea después sepa
--  qué se quiso decir sin volver a esta conversación.
-- ============================================================
--
--  DOS COSAS QUE NO SE PUEDEN CAMBIAR SIN ROMPER EL DISEÑO
--
--  1. `ambito` no es decorativo. Un logro de ámbito `roll` se evalúa
--     roll a roll; uno de ámbito `quedada` necesita todos los rolls de
--     esa quedada; uno de `semana` o `mes` necesita la ventana entera.
--     "Veces conseguido" = número de instancias del ámbito en las que
--     el predicado se cumplió, no número de eventos.
--
--  2. `requiere_observador` marca los logros que se definen por la
--     AUSENCIA de algo. Se inflan solos con no registrar el evento, así
--     que solo cuentan si el roll tiene `origen = 'observador'`. Los de
--     presencia no lo necesitan: para conseguirlos hubo que registrar
--     algo activamente. Está explicado en docs/04-logros-privacidad-y-grupo.md.
-- ============================================================

insert into logros
  (clave, nombre, descripcion, familia, rareza, ambito, requiere_observador, solo_nogi,
   min_volumen, descripcion_tecnica) values

-- ---------- DEFENSA ----------
('impasable', 'IMPASABLE', 'Ningún pase de guardia encajado en el roll',
 'defensa', 'comun', 'roll', true, false,
 '{"eventos_guardia_propios": 1}',
 'Cero eventos pase_guardia del oponente en el roll, exigiendo al menos un evento propio con rol=abajo en una posicion es_guardia. Sin esa guarda, un roll que nunca pasó por la guardia lo conseguiría gratis.'),

('muro', 'MURO', 'El rival lo intenta tres veces y no entra ninguna',
 'defensa', 'poco_comun', 'roll', true, false,
 '{"intentos_del_rival": 3}',
 'El oponente tiene >=3 eventos tipo sumision en el roll y ninguno con completado = true.'),

('houdini', 'HOUDINI', 'Tres escapes desde posiciones dominantes',
 'defensa', 'poco_comun', 'roll', false, false,
 '{"escapes": 3}',
 '>=3 eventos propios tipo escape desde posiciones con grupo = dominante o desde espalda.'),

('de_vuelta', 'HIGHLANDER', 'Te montan o te toman la espalda, y acabas ganando',
 'defensa', 'raro', 'roll', false, false, '{}',
 'El oponente llegó a montada o espalda en algún momento del roll, y el resultado del roll es sumision_favor.'),

('cuello_de_acero', 'CUELLO DE ACERO', 'Te atacan el cuello tres veces y no cae ninguna',
 'defensa', 'poco_comun', 'roll', true, false,
 '{"ataques_al_cuello": 3}',
 '>=3 eventos del oponente tipo sumision con objetivo = cuello, ninguno completado.'),

('sin_marcar', 'FLAWLESS VICTORY', 'El rival no consigue ni un punto en todo el roll',
 'defensa', 'poco_comun', 'roll', true, false, '{}',
 'puntos_oponente = 0 en v_puntos_roll para ese roll. Requiere observador porque es una ausencia.'),

-- ---------- ATAQUE ----------
('rodillo', 'EL RODILLO', 'Tres pases de guardia en un roll',
 'ataque', 'comun', 'roll', false, false, '{"pases": 3}',
 '>=3 eventos propios tipo pase_guardia con completado = true.'),

('limpio', 'LIMPIO', 'Finalizas sin haber fallado ni un intento antes',
 'ataque', 'comun', 'roll', true, false, '{}',
 'Hay una sumision propia completada y ninguna sumision propia con completado = false anterior en el roll. Requiere observador: no registrar los fallos lo consigue gratis.'),

('relampago', 'RELÁMPAGO', 'Finalizas en menos de sesenta segundos',
 'ataque', 'poco_comun', 'roll', false, false, '{}',
 'Sumision propia completada con segundo_roll < 60. Si segundo_roll es null, el logro no cuenta — no lo estimes desde minuto.'),

('la_cadena', 'LA CADENA', 'Pasas, montas y tomas la espalda en el mismo roll',
 'ataque', 'raro', 'roll', false, false, '{}',
 'En el mismo roll, y en este orden temporal por segundo_roll: un pase_guardia propio, una transicion propia a montada, y una toma_espalda propia o una transicion propia a espalda.'),

('quince', 'QUINCE', 'Quince puntos estimados en un solo roll',
 'ataque', 'raro', 'roll', false, false, '{}',
 'puntos_autor >= 15 en v_puntos_roll.'),

('primera_vez', 'PRIMERA VEZ', 'Finalizas desde una posición nueva para ti',
 'ataque', 'poco_comun', 'roll', false, false, '{}',
 'Sumision propia completada desde una posicion desde la que el practicante no habia finalizado nunca antes, mirando todo su histórico anterior a ese roll. Es acumulable: cada posicion nueva cuenta una vez.'),

('juguete_nuevo', 'JUGUETE NUEVO', 'Finalizas con una técnica que nunca habías usado',
 'ataque', 'poco_comun', 'roll', false, false, '{}',
 'Igual que primera_vez pero por tecnica_id. Los eventos con tecnica_id null no cuentan.'),

('guardia_de_hierro', 'GUARDIA DE HIERRO', 'Tres barridas en un roll',
 'ataque', 'comun', 'roll', false, false, '{"barridas": 3}',
 '>=3 eventos propios tipo barrida completados.'),

('mochilero', 'EL MOCHILERO', 'Dos espaldas tomadas en un roll',
 'ataque', 'comun', 'roll', false, false, '{"espaldas": 2}',
 '>=2 eventos propios tipo toma_espalda completados.'),

('piernas', 'PIERNAS', 'Finalizas atacando una pierna',
 'ataque', 'poco_comun', 'roll', false, true, '{}',
 'Sumision propia completada con objetivo en (rodilla, tobillo_pie, pantorrilla). Solo nogi.'),

('cinturon_invisible', 'CINTURÓN INVISIBLE', 'Finalizas a alguien de cinturón superior',
 'ataque', 'poco_comun', 'roll', false, false, '{}',
 'Sumision propia completada en un roll cuyo oponente tiene un cinturon mas alto en el orden del enum bjj_cinturon. Si el oponente no tiene cinturon registrado, no cuenta.'),

-- ---------- ESTILO ----------
('pulpo', 'EL PULPO', 'Cinco intentos de sumisión en un roll',
 'estilo', 'comun', 'roll', false, false, '{"intentos": 5}',
 '>=5 eventos propios tipo sumision, completados o no. Es a prueba de trampas por construccion: inflarlo exige registrar tus propios fallos.'),

('artista', 'EL ARTISTA', 'Tres sumisiones distintas en la misma quedada',
 'estilo', 'poco_comun', 'quedada', false, false, '{}',
 '>=3 tecnica_id distintas en sumisiones propias completadas dentro de la misma quedada.'),

('ambidiestro', 'AMBIDIESTRO', 'Finalizas desde arriba y desde abajo el mismo día',
 'estilo', 'poco_comun', 'quedada', false, false, '{}',
 'En la misma quedada, al menos una sumision propia completada con rol = arriba y otra con rol = abajo.'),

('sin_gi_sin_problema', 'SIN GI, SIN PROBLEMA', 'Finalizas en gi y en nogi la misma semana',
 'estilo', 'poco_comun', 'semana', false, false, '{}',
 'En la misma semana ISO, sumisiones propias completadas en una sesion gi y en una sesion nogi.'),

-- ---------- CONSTANCIA ----------
-- Estos cuatro no premian rendimiento, premian REGISTRAR, que es el unico
-- riesgo que mata el producto. Si hay que implementar una sola familia, esta.
('notario', 'EL NOTARIO', 'Registras todos los rolls de la quedada, sin dejarte ninguno',
 'constancia', 'comun', 'quedada', false, false,
 '{"rolls_en_la_quedada": 3}',
 'El practicante tiene rolls registrados en la quedada y ninguno de sus rolls de ese dia quedo sin eventos. Minimo 3 rolls para que cuente.'),

('ojo_del_coach', 'OJO DEL COACH', 'Diez rolls registrados como observador en un mes',
 'constancia', 'poco_comun', 'mes', false, false, '{}',
 '>=10 rolls con registrado_por = este practicante y origen = observador dentro del mes.'),

('semana_completa', 'SEMANA COMPLETA', 'Registras en tres días distintos de la misma semana',
 'constancia', 'comun', 'semana', false, false, '{}',
 '>=3 fechas distintas con al menos un roll propio registrado, dentro de la misma semana ISO.'),

('el_ultimo_en_irse', 'EL ÚLTIMO EN IRSE', 'Tuyo es el último roll registrado de la quedada',
 'constancia', 'comun', 'quedada', false, false, '{}',
 'El roll con el mayor orden de la quedada es del practicante.'),

-- ---------- CACHONDEO ----------
-- Solo se evalúan y se muestran si grupos.modo_cachondeo = true.
-- Apagados por defecto: un logro negativo automatico le sienta mal a
-- alguien tarde o temprano, y esa decision la toma un humano.
('peaje', 'PEAJE', 'Te pasan la guardia cuatro veces en un roll',
 'cachondeo', 'comun', 'roll', false, false, '{"pases_encajados": 4}',
 '>=4 eventos pase_guardia del oponente completados en el roll.'),

('el_ancla', 'EL ANCLA', 'Más de dos minutos en la misma posición sin que pase nada',
 'cachondeo', 'comun', 'roll', false, false, '{}',
 'Hueco de >120 segundos entre dos eventos consecutivos del roll sin cambio de posicion. Necesita segundo_roll en los dos eventos.'),

('donante', 'DONANTE', 'Encajas tres sumisiones en un roll',
 'cachondeo', 'comun', 'roll', false, false, '{"sumisiones_encajadas": 3}',
 '>=3 sumisiones del oponente completadas en el mismo roll.');
