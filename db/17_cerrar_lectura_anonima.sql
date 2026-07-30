-- ============================================================
--  BJJ TRACKER — Cerrar la lectura anonima   ·   Migracion bjj_22
-- ============================================================
--
--  TRES POLITICAS ESTABAN EN `USING (true)` PARA `public`, y `public` incluye
--  a `anon`. Como la clave anonima va dentro del JavaScript que sirve Vercel,
--  cualquiera con un `curl` podia leerlas enteras:
--
--    · practicantes          — nombres, cinturones, pesos y academia
--    · retos                 — que retos hay
--    · reto_participaciones  — QUIEN participo y CUANTO lleva
--
--  La tercera es la peor con diferencia: no es un nombre, es rendimiento por
--  persona. Comprobado en local antes de tocar nada, con filas de verdad:
--  como `anon`, `select ... from reto_participaciones` devolvia "Goku (7)".
--
--  ANTES DE CERRAR SE MIRO QUIEN LAS LEIA SIN AUTENTICAR. Nadie:
--
--    · `practicantes` solo se consulta desde pantallas que van dentro de
--      `<Marco>`, que exige sesion (analisis, entreno, grupo, practicantes,
--      quedadas).
--    · `retos` y `reto_participaciones` no las consulta la app en ningun sitio.
--    · El enlace del invitado externo NO las necesita: `quedada_por_token()`
--      devuelve el plan y CONTADORES, nunca nombres de participantes. Si algun
--      dia hace falta enseñar quien va, se hace con otra funcion estrecha y
--      con proposito — no dejando el roster abierto.
--
--  `posiciones` y `tecnicas` se quedan abiertas a proposito: son el diccionario
--  y no tienen datos personales.
-- ============================================================

-- ------------------------------------------------------------
-- 1 · practicantes
--
-- Sale de `public`, y ademas se estrecha ENTRE AUTENTICADOS. Lo segundo no
-- estaba previsto, pero lo exige la regla del invitado externo: "ni los datos de otros miembros". Con
-- `USING (true)` para `authenticated`, alguien que se apunta a un open mat se
-- lleva de premio el roster entero del gimnasio. Lo cazo el caso 51 de la
-- bateria.
--
-- Se ve: tu ficha, la de quien comparte grupo contigo, y los contactos que
-- diste de alta tu. Es exactamente el mismo criterio que ya rige sesiones,
-- rolls y eventos desde `bjj_15`, asi que deja de haber dos reglas.
drop policy practicantes_lectura on practicantes;
create policy practicantes_lectura on practicantes
  for select to authenticated
  using (id in (select private.practicantes_visibles())
         or creado_por = auth.uid());

-- ------------------------------------------------------------
-- 2 · retos
--
-- Se ven los de la gente con la que compartes grupo, igual que todo lo demas
-- desde `bjj_15`. Un reto que monta otra academia no es asunto tuyo.
-- ------------------------------------------------------------
drop policy retos_lectura on retos;
create policy retos_lectura on retos
  for select to authenticated
  using (creador_id in (select private.practicantes_visibles()));

-- ------------------------------------------------------------
-- 3 · reto_participaciones — la mas grave
--
-- Progreso por persona. Se ve el tuyo y el de quien comparte grupo contigo, y
-- de nadie mas.
-- ------------------------------------------------------------
drop policy participaciones_lectura on reto_participaciones;
create policy participaciones_lectura on reto_participaciones
  for select to authenticated
  using (practicante_id in (select private.practicantes_visibles()));

-- ------------------------------------------------------------
-- 4 · Y el permiso, no solo la politica
--
-- La RLS ya bastaria, pero un `grant` que sobra es una segunda linea que algun
-- dia se cruza sola: basta que alguien escriba una politica nueva con un
-- `USING` mas ancho de la cuenta para que el permiso vuelva a contar. Sin el
-- grant, `anon` recibe un 42501 antes de que ninguna politica llegue a
-- evaluarse.
--
-- Ojo al dato que salio de paso: `anon` tiene INSERT/UPDATE/DELETE/SELECT
-- sobre TODAS las tablas, que es el `grant all` por defecto de Supabase. Hoy
-- no hace daño porque ninguna politica de escritura le aplica, pero es mucha
-- superficie de la que depender. Se revocan estas tres, que son las que tenian
-- agujero; el repaso completo va al backlog.
-- ------------------------------------------------------------
revoke all on practicantes, retos, reto_participaciones from anon;

-- ------------------------------------------------------------
-- 5 · El invitado externo: el acceso sigue al EVENTO, no al grupo
--
-- Ni una cosa ni la otra. Abrir la lectura a cualquiera con inscripcion seria
-- demasiado —te apuntas a un open mat y te lees el feed del gimnasio para
-- siempre— y dejar el enlace como unica puerta es demasiado poco: rodo, se
-- registraron sus rolls, y no puede volver a ver ni la quedada.
--
-- La regla: una inscripcion da acceso A ESA QUEDADA y a su informe. Nada mas.
-- Ni el feed, ni los datos de otros miembros, ni otras quedadas.
--
-- El token sigue siendo la puerta de ANTES de tener cuenta: ver el plan y
-- apuntarse.
-- ------------------------------------------------------------
create or replace function private.mis_quedadas()
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select quedada_id from inscripciones
   where practicante_id = private.practicante_actual()
     and estado <> 'cancelado'
$$;

comment on function private.mis_quedadas() is
  'Las quedadas a las que estoy apuntado. SECURITY DEFINER para que la politica '
  'de `quedadas` pueda mirar `inscripciones` sin que las dos se llamen en '
  'circulo. Vive en `private` para que PostgREST no la publique.';

create policy quedadas_lectura_inscrito on quedadas
  for select to authenticated
  using (id in (select private.mis_quedadas()));

create policy informes_lectura_inscrito on quedada_informes
  for select to authenticated
  using (quedada_id in (select private.mis_quedadas()));

-- ------------------------------------------------------------
-- 6 · El feed es del GRUPO, y eso se dice en el propio feed
--
-- Al dejar que el invitado lea su quedada, `v_feed` empezo a enseñarle los dos
-- elementos que salen de esa fila — el "alguien monto una quedada" y el
-- "alguien se apunto". Lo caza el caso 47 de la bateria.
--
-- No se arregla quitandole la quedada, que es justo lo que si tiene que ver.
-- Se arregla diciendo en la vista lo que el feed es: actividad DE TUS GRUPOS.
-- Antes eso lo garantizaban de rebote las politicas de cada tabla de origen, y
-- de rebote es como se escapan las cosas.
-- ------------------------------------------------------------
-- Se renombra y se envuelve, en vez de repetir el union de ocho ramas: asi el
-- filtro esta en UN sitio y no hay dos copias de la definicion esperando a
-- separarse.
alter view v_feed rename to v_feed_crudo;

create view v_feed with (security_invoker = on) as
select * from v_feed_crudo
 where grupo_id in (select private.mis_grupos());

comment on view v_feed is
  'Actividad de TUS grupos. El filtro esta aqui y no repartido por las ocho '
  'ramas de `v_feed_crudo`: antes lo garantizaban de rebote las politicas de '
  'cada tabla de origen, y al dar acceso al invitado externo a su quedada se '
  'colaron dos elementos. Lo que el feed es, se dice en el feed.';
