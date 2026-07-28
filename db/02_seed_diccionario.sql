-- ============================================================
--  BJJ TRACKER — Seed del diccionario (posiciones + tecnicas)
--  Ejecutar DESPUES de 01-schema.sql
-- ============================================================

-- ------------------------------------------------------------
-- POSICIONES  (filas del heatmap)
--  core_v1 = true  -> las 13 que usais en Sprint 0 para no frenaros
-- ------------------------------------------------------------
insert into posiciones (codigo, nombre, grupo, core_v1) values
  ('de_pie',               'De pie',                    'neutral',    true),
  ('clinch',               'Clinch / agarre de pie',    'neutral',    true),

  ('guardia_cerrada',      'Guardia cerrada',           'guardia',    true),
  ('guardia_abierta',      'Guardia abierta',           'guardia',    true),
  ('media_guardia',        'Media guardia',             'guardia',    true),
  ('mariposa',             'Guardia mariposa',          'guardia',    true),
  ('de_la_riva',           'De la Riva',                'guardia',    true),
  ('de_la_riva_inversa',   'De la Riva inversa (RDLR)', 'guardia',    false),
  ('arana',                'Arana / spider',            'guardia',    false),
  ('lasso',                'Lasso',                     'guardia',    false),
  ('collar_manga',         'Collar y manga',            'guardia',    false),
  ('x_guard',              'X-guard',                   'guardia',    false),
  ('single_leg_x',         'Single leg X / ashi',       'guardia',    false),
  ('guardia_sentada',      'Guardia sentada',           'guardia',    false),
  ('cincuenta_cincuenta',  '50/50',                     'guardia',    false),

  ('montada',              'Montada',                   'dominante',  true),
  ('cien_kilos',           'Cien kilos / side control', 'dominante',  true),
  ('kesa_gatame',          'Kesa gatame',               'dominante',  false),
  ('norte_sur',            'Norte-sur',                 'dominante',  true),
  ('rodilla_en_barriga',   'Rodilla en barriga',        'dominante',  false),
  ('espalda',              'Control de espalda',        'dominante',  true),
  ('tortuga',              'Tortuga',                   'dominante',  true),

  ('scramble',             'Scramble / transicion',     'transicion', true),
  ('otra',                 'Otra',                      'transicion', false);


-- ------------------------------------------------------------
-- TECNICAS  (con alias: resuelve "mata leao" vs "RNC")
-- ------------------------------------------------------------
insert into tecnicas (slug, nombre, alias, tipo, objetivo_default, solo_gi) values
  -- SUMISIONES · cuello
  ('mata_leao',        'Mata leao',              '{"RNC","rear naked choke","estrangulamiento por la espalda"}', 'sumision','cuello',false),
  ('triangulo',        'Triangulo',              '{"sankaku","triangle"}',                  'sumision','cuello',false),
  ('guillotina',       'Guillotina',             '{"guillotine"}',                          'sumision','cuello',false),
  ('darce',            'D''arce',                '{"darce","brabo"}',                  'sumision','cuello',false),
  ('anaconda',         'Anaconda',               '{"anaconda choke"}',                      'sumision','cuello',false),
  ('katagatame',       'Kata gatame',            '{"arm triangle","head and arm"}',         'sumision','cuello',false),
  ('cruzada',          'Estrangulacion cruzada', '{"cross collar","cruz","gravata"}',       'sumision','cuello',true),
  ('bow_and_arrow',    'Bow and arrow',          '{"arco y flecha"}',                       'sumision','cuello',true),
  ('ezekiel',          'Ezekiel',                '{"ezequiel","sode guruma"}',              'sumision','cuello',false),
  ('baseball_bat',     'Baseball bat choke',     '{"bate de beisbol"}',                     'sumision','cuello',true),
  ('lapela',           'Estrangulacion de lapela','{"lapel choke","loop choke"}',           'sumision','cuello',true),
  ('north_south_choke','North-south choke',      '{"estrangulacion norte-sur"}',            'sumision','cuello',false),

  -- SUMISIONES · hombro
  ('kimura',           'Kimura',                 '{"ude garami","doble nelson"}',           'sumision','hombro',false),
  ('americana',        'Americana',              '{"keylock","chave de braco americana"}',  'sumision','hombro',false),
  ('omoplata',         'Omoplata',               '{"omo plata"}',                           'sumision','hombro',false),
  ('baratoplata',      'Baratoplata',            '{"barato plata"}',                        'sumision','hombro',false),

  -- SUMISIONES · codo
  ('armbar',           'Armbar',                 '{"juji gatame","chave de braco","llave de brazo"}','sumision','codo',false),
  ('armbar_triangulo', 'Armbar desde triangulo', '{}',                                      'sumision','codo',false),
  ('americana_recta',  'Straight armlock',       '{"armlock recto"}',                       'sumision','codo',false),

  -- SUMISIONES · otros
  ('muneca',           'Wristlock',              '{"llave de muneca","mao de vaca"}',       'sumision','muneca',false),
  ('biceps_slicer',    'Biceps slicer',          '{"biceps cutter"}',                       'sumision','biceps',false),
  ('pantorrilla_slicer','Calf slicer',           '{"calf crush"}',                          'sumision','pantorrilla',false),
  ('twister',          'Twister',                '{"cabeca de vaca"}',                      'sumision','columna',false),
  ('banana_split',     'Banana split',           '{"apertura de cadera"}',                  'sumision','cadera',false),

  -- SUMISIONES · piernas
  ('heel_hook',        'Heel hook',              '{"llave de talon"}',                      'sumision','rodilla',false),
  ('kneebar',          'Kneebar',                '{"llave de rodilla"}',                    'sumision','rodilla',false),
  ('straight_ankle',   'Straight ankle lock',    '{"botinha","llave de tobillo"}',          'sumision','tobillo_pie',false),
  ('toe_hold',         'Toe hold',               '{"llave de pie"}',                        'sumision','tobillo_pie',false),

  -- BARRIDAS
  ('barrida_tijera',   'Barrida de tijera',      '{"scissor sweep","tesoura"}',             'barrida','ninguno',false),
  ('barrida_pendulo',  'Barrida pendulo',        '{"flower sweep","balancinho"}',           'barrida','ninguno',false),
  ('barrida_mariposa', 'Barrida de mariposa',    '{"butterfly sweep","hook sweep"}',        'barrida','ninguno',false),
  ('barrida_hip_bump', 'Hip bump',               '{"barrida de cadera"}',                   'barrida','ninguno',false),
  ('barrida_dlr',      'Barrida de De la Riva',  '{"berimbolo entry"}',                     'barrida','ninguno',false),
  ('barrida_x_guard',  'Barrida de X-guard',     '{"technical stand up sweep"}',            'barrida','ninguno',false),
  ('barrida_tripode',  'Tripod / sickle',        '{"tripode","hoz"}',                       'barrida','ninguno',false),
  ('barrida_overhead', 'Overhead sweep',         '{"balao","balloon sweep"}',               'barrida','ninguno',false),
  ('barrida_lumberjack','Lumberjack',            '{"lenador"}',                             'barrida','ninguno',false),

  -- PASES DE GUARDIA
  ('pase_toreando',    'Toreando',               '{"bullfighter","toreada"}',               'pase_guardia','ninguno',false),
  ('pase_knee_slice',  'Knee slice',             '{"knee cut","joelhada","corte de rodilla"}','pase_guardia','ninguno',false),
  ('pase_stack',       'Stack pass',             '{"pase apilado"}',                        'pase_guardia','ninguno',false),
  ('pase_over_under',  'Over-under',             '{"sobre-bajo"}',                          'pase_guardia','ninguno',false),
  ('pase_leg_drag',    'Leg drag',               '{"arrastre de pierna"}',                  'pase_guardia','ninguno',false),
  ('pase_long_step',   'Long step',              '{"paso largo"}',                          'pase_guardia','ninguno',false),
  ('pase_smash',       'Smash pass',             '{"pase de presion"}',                     'pase_guardia','ninguno',false),
  ('pase_x_pass',      'X-pass',                 '{"pase en x"}',                           'pase_guardia','ninguno',false),
  ('pase_headquarters','Headquarters (HQ)',      '{"quartel general"}',                     'pase_guardia','ninguno',false),

  -- DERRIBOS
  ('double_leg',       'Double leg',             '{"baiana","doble pierna"}',               'derribo','ninguno',false),
  ('single_leg',       'Single leg',             '{"una pierna"}',                          'derribo','ninguno',false),
  ('osoto_gari',       'Osoto gari',             '{}',                                      'derribo','ninguno',false),
  ('ouchi_gari',       'Ouchi gari',             '{}',                                      'derribo','ninguno',false),
  ('seoi_nage',        'Seoi nage',              '{"cargada"}',                             'derribo','ninguno',false),
  ('uchi_mata',        'Uchi mata',              '{}',                                      'derribo','ninguno',false),
  ('tomoe_nage',       'Tomoe nage',             '{"sacrificio"}',                          'derribo','ninguno',false),
  ('ankle_pick',       'Ankle pick',             '{"toma de tobillo"}',                     'derribo','ninguno',false),
  ('deashi_barai',     'De ashi barai',          '{"barrido de pie"}',                      'derribo','ninguno',false),
  ('puxada',           'Guard pull',             '{"puxada","tirar guardia"}',              'derribo','ninguno',false),

  -- TOMA DE ESPALDA / ESCAPES
  ('toma_espalda_gen', 'Toma de espalda',        '{"back take","pegada de costas"}',        'toma_espalda','ninguno',false),
  ('berimbolo',        'Berimbolo',              '{}',                                      'toma_espalda','ninguno',false),
  ('crazy_dog',        'Crazy dog / back step',  '{}',                                      'toma_espalda','ninguno',false),
  ('escape_upa',       'Upa (escape de montada)','{"bridge and roll","puente"}',            'escape','ninguno',false),
  ('escape_codo_rodilla','Codo-rodilla',         '{"elbow knee escape","shrimp"}',          'escape','ninguno',false),
  ('escape_espalda',   'Escape de espalda',      '{"back escape"}',                         'escape','ninguno',false),
  ('recuperar_guardia','Recuperar guardia',      '{"guard retention","recomposicion"}',     'escape','ninguno',false);
