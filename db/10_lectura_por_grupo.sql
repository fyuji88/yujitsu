-- ============================================================
--  BJJ TRACKER — La lectura se recorta al grupo   ·   FASE 2
--  Migracion bjj_15. Va despues de 09_grupos.sql.
-- ============================================================
--
--  QUE CAMBIA
--
--  `bjj_13` abrio la lectura de sesiones, rolls y eventos a **cualquier
--  autenticado**, para que el selector de practicante de la pantalla de
--  analisis tuviera algo que enseñar. Aquello quedo escrito como aceptable
--  "con dos amigos" y corto "en cuanto entre gente de la academia". Ya hay
--  cuatro cuentas y un grupo: el grupo es la frontera que faltaba.
--
--  Regla nueva: **ves los datos de quien comparte grupo contigo, y los tuyos**.
--
--  Lo que NO cambia: las politicas de escritura. Cada uno sigue escribiendo lo
--  suyo, y los terceros solo por registrar_roll_observado(). Si al recortar la
--  lectura se colara escritura, seria un fallo grave y no lo veria el
--  typecheck — por eso db/pruebas/grupos-rls.sql lo comprueba explicitamente.
--
--
--  POR QUE CONJUNTOS Y NO UN PREDICADO POR FILA  —  ESTO SE MIDIO
--
--  La forma obvia es un predicado: `using (private.puedo_ver_roll(roll_id))`.
--  Funciona y es facil de leer, pero Postgres lo evalua **una vez por fila**, y
--  cada llamada hace dos joins. Medido con 679 eventos: 631 ms para contarlos.
--  Eso es ~1 ms por evento, o sea minuto y medio con 100.000 — que es volumen
--  de un gimnasio, no de una fantasia.
--
--  Con `in (select ...)` sobre una funcion que devuelve el conjunto, el planner
--  la resuelve UNA vez, la mete en una tabla hash y luego cada fila es una
--  busqueda. Se pasa de coste lineal en llamadas a funcion a coste lineal en
--  busquedas hash, que es otra liga.
--
--  Los helpers siguen siendo SECURITY DEFINER por lo de siempre: si leyeran con
--  la RLS puesta, la politica de `sesiones` preguntaria por `sesiones` y se
--  encadenarian politicas dentro de politicas.
-- ============================================================

/* Yo, y todo el que comparta algun grupo activo conmigo. */
create or replace function private.practicantes_visibles()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select private.practicante_actual()
  union
  select m2.practicante_id
    from miembros_grupo m1
    join miembros_grupo m2 on m2.grupo_id = m1.grupo_id
   where m1.practicante_id = private.practicante_actual()
     and m1.estado = 'activo'
     and m2.estado = 'activo'
$$;

create or replace function private.sesiones_visibles()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select s.id from sesiones s
   where s.practicante_id in (select private.practicantes_visibles())
$$;

create or replace function private.rolls_visibles()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select r.id from rolls r
   where r.sesion_id in (select private.sesiones_visibles())
$$;

revoke all on function private.practicantes_visibles() from public;
revoke all on function private.sesiones_visibles()     from public;
revoke all on function private.rolls_visibles()        from public;
grant execute on function private.practicantes_visibles() to authenticated, service_role;
grant execute on function private.sesiones_visibles()     to authenticated, service_role;
grant execute on function private.rolls_visibles()        to authenticated, service_role;


-- ------------------------------------------------------------
-- Fuera la lectura abierta a todo el mundo, dentro la del grupo.
-- ------------------------------------------------------------
drop policy if exists sesiones_lectura_comun on sesiones;
drop policy if exists rolls_lectura_comun    on rolls;
drop policy if exists eventos_lectura_comun  on eventos;

create policy sesiones_lectura_grupo on sesiones
  for select to authenticated
  using (practicante_id in (select private.practicantes_visibles()));

create policy rolls_lectura_grupo on rolls
  for select to authenticated
  using (sesion_id in (select private.sesiones_visibles()));

create policy eventos_lectura_grupo on eventos
  for select to authenticated
  using (roll_id in (select private.rolls_visibles()));

comment on policy sesiones_lectura_grupo on sesiones is
  'Ves lo de quien comparte grupo contigo, y lo tuyo. Sustituye a la lectura '
  'abierta de bjj_13. El razonamiento esta en db/10_lectura_por_grupo.sql.';


-- ------------------------------------------------------------
-- LO QUE SIGUE ABIERTO, A SABIENDAS
--
--  `practicantes` se lee entero (`practicantes_lectura ... using (true)`).
--  El roster comun es lo que hace que puedas dar de alta a alguien que ya
--  existe en vez de crear una ficha duplicada, y lo que evita el problema de
--  fichas partidas. Lo que se ve ahi es nombre, cinturon y academia; los rolls
--  y los eventos ya no.
--
--  Recortarlo tambien es posible y esta anotado en el backlog, pero tiene un
--  coste concreto: sin roster comun, dos personas dan de alta al mismo Marc
--  dos veces y el head-to-head se parte en dos. Es un cambio con contrapartida,
--  no una mejora gratis, y por eso no va aqui.
-- ------------------------------------------------------------
