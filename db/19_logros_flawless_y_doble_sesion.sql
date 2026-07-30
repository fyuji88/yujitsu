-- ============================================================
--  BJJ TRACKER — Ajustes del catalogo de logros   ·   Migracion bjj_24
--
--  (La etiqueta decia bjj_23, que ya era de `18_ambito_dia.sql`. La buena es
--  bjj_24, que es la que registra produccion en
--  supabase_migrations.schema_migrations. Corregido en bjj_28, cuando el
--  comprobador de vocabulario empezo a mirar tambien esto.)
-- ============================================================
--
--  Tres cosas, y las tres son de DEFINICION, no de calibracion. Los umbrales
--  no se tocan todavia: los datos que hay son de un generador que solo emite
--  evento cuando pasa algo, asi que ajustar contra ellos seria ajustar a las
--  manias del simulador. Eso espera a rolls reales.
-- ============================================================

-- ------------------------------------------------------------
-- 1 · FLAWLESS VICTORY tenia un bug de definicion
--
-- "El rival no consigue ni un punto" se cumple SOLO por no pasar nada. Un roll
-- tranquilo, sin nada posicional, da cero puntos a los dos — y se lo llevaban
-- LOS DOS. Es el mismo agujero que tenia IMPASABLE y que se tapo con su guarda
-- de volumen: un logro definido por una ausencia necesita que la situacion
-- haya existido.
--
-- La guarda: en el roll tuvo que PASAR algo. Al menos un evento que cambia la
-- posicion o puntua, de cualquiera de los dos. Si nadie hizo nada, "el rival no
-- marco" no dice nada de nadie.
--
-- Uno y no dos a proposito: con dos se caian rolls legitimos —el que barre una
-- vez y no encaja nada se lo ha ganado— y el bug que hay que tapar es solo el
-- roll VACIO. La guarda mas floja que cierra el agujero es la correcta.
--
-- Va en `min_volumen`, que es donde el diseño manda que vivan las guardas: en
-- el catalogo y no repartidas por el codigo.
-- ------------------------------------------------------------
update logros
   set min_volumen = '{"eventos_posicionales": 1}',
       descripcion_tecnica =
         'puntos_oponente = 0 en v_puntos_roll para ese roll, Y al menos 1 '
         'evento posicional (barrida, pase_guardia, derribo, toma_espalda o '
         'transicion) de cualquiera de los dos. Sin esa guarda, un roll en el '
         'que no pasa nada da cero puntos a ambos y se lo llevan los dos. '
         'Requiere observador porque es una ausencia.'
 where clave = 'sin_marcar';

-- ------------------------------------------------------------
-- 2 · DOBLE SESION, para que constancia siga siendo de cuatro
--
-- Entra en el hueco que deja EL ULTIMO EN IRSE, que se cae del catalogo.
--
-- Por que ese se cae: su predicado era "el roll con el mayor orden de la
-- quedada es tuyo", y `rolls.orden` es el orden DENTRO DE TU SESION, no de la
-- quedada. Y las tres alternativas eran peores que no tenerlo:
--   (a) el ultimo `created_at` mide quien tenia mejor cobertura, no quien se
--       fue el ultimo — con la cola sin conexion eso es literalmente asi. Un
--       logro que miente es peor que un logro que falta.
--   (b) una hora de fin pide un dato nuevo en el peor momento posible, cuando
--       todo el mundo esta recogiendo para irse.
--   (c) quitarlo. Y la virtud que perseguia ya la cubren EL NOTARIO y SEMANA
--       COMPLETA.
--
-- DOBLE SESION es derivable HOY, no pide ningun dato nuevo, y premia justo la
-- conducta que interesa: aparecer dos veces el mismo dia.
-- ------------------------------------------------------------

-- El ambito `dia` lo añade `db/18_ambito_dia.sql`, que va ANTES y suelto:
-- Postgres no deja usar un valor de enum en la misma transaccion en que se
-- crea ("unsafe use of new value"), y las migraciones se aplican envueltas en
-- una. Por eso son dos ficheros y no uno.

insert into logros
  (clave, nombre, descripcion, familia, rareza, ambito, requiere_observador,
   solo_nogi, min_volumen, descripcion_tecnica)
values
  ('doble_sesion', 'DOBLE SESIÓN', 'Registras dos sesiones el mismo día',
   'constancia', 'poco_comun', 'dia', false, false, '{}',
   '>=2 sesiones propias con rolls registrados en la misma fecha. No pide '
   'ningun dato nuevo: sale de lo que ya hay.')
on conflict (clave) do nothing;
