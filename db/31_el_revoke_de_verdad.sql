-- ============================================================
--  BJJ TRACKER — El revoke, esta vez de verdad   ·   Migracion bjj_36
-- ============================================================
--
--  LA CAUSA, POR FIN. Desde `bjj_25` toda migracion que crea o recrea una
--  funcion ha tenido que llevar su `revoke all ... from public` a mano, y las
--  tres veces que se me olvido —bjj_27, bjj_31, bjj_34— lo cazo el caso 48 de
--  `db/pruebas/rls.sql`, no yo. Tres veces el mismo fallo es un defecto del
--  sistema, no tres despistes.
--
--  `bjj_25` intento cerrarlo en el sitio correcto, con esta linea:
--
--      alter default privileges IN SCHEMA public revoke execute on functions
--        from public;
--
--  Y ESA LINEA ES UN NO-OP. Medido, no supuesto: se ejecuta sin error, no
--  cambia `pg_default_acl`, y la siguiente funcion nace igualmente con `=X`
--  —que es PUBLIC— en su ACL. La entrada por esquema convive con el default de
--  fabrica en vez de sustituirlo, asi que revocar de ella no quita lo que
--  concede el otro.
--
--  LA QUE SI FUNCIONA ES LA GLOBAL, sin `in schema`:
--
--      alter default privileges revoke execute on functions from public;
--
--  Con ella, una funcion nueva en `public` sale con anon=false,
--  authenticated=true, service_role=true — exactamente el estado que
--  queriamos— y una en `private` con las dos a false. Las tablas no se tocan.
--
--  Y COMO NO ME LO CREO SOLO POR ESCRIBIRLO, al final de esta migracion se
--  crea una funcion de prueba, se mide, y se tira. Si `anon` pudiera
--  ejecutarla, esto falla aqui y no dentro de seis meses en la bateria.
--
--  LO QUE ESTO NO ARREGLA es la mitad de `supabase_admin`, que necesita un
--  permiso que `postgres` no tiene. Va aparte, en `db/32`, y esa SI falla a
--  proposito para que se vea.
-- ============================================================

begin;

-- El arreglo. Sin `in schema`: esa es toda la diferencia.
alter default privileges revoke execute on functions from public;

-- Y el barrido de lo que ya existe, que la linea de arriba solo vale para lo
-- que se cree a partir de ahora. Hoy no deberia sobrar ninguna —la bateria
-- pasa—, pero dejarlo depender de eso seria confiar en que nadie ha creado una
-- funcion por el panel desde la ultima vez que se corrio.
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;

-- ------------------------------------------------------------
--  `private` NECESITA SU PERMISO EXPLICITO, y esto casi me muerde.
-- ------------------------------------------------------------
--  Los ayudantes de la RLS viven en `private` y los llaman las POLITICAS, que
--  corren como quien consulta: `authenticated` tiene que poder ejecutarlos.
--  Hasta hoy podia... por el regalo a PUBLIC, el mismo que esta migracion viene
--  a quitar. Al revocarlo a secas, la bateria de RLS se planto en el caso 1 con
--  `permission denied for function mis_quedadas`.
--
--  Asi que se cambia un permiso implicito por uno explicito, en vez de
--  quitarlo. Y la linea que de verdad importa es la de `alter default`: sin
--  ella, el siguiente ayudante que alguien añada nacera sin permiso y lo que
--  fallara sera una POLITICA — un error que no se parece en nada a su causa.
revoke execute on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;
alter default privileges in schema private
  grant execute on functions to authenticated, service_role;

-- ------------------------------------------------------------
--  LA COMPROBACION. Una funcion de mentira, se mide, se tira.
-- ------------------------------------------------------------
do $$
declare puede boolean;
begin
  create function public.zzz_cobaya_bjj36() returns int language sql as 'select 1';
  puede := has_function_privilege('anon', 'public.zzz_cobaya_bjj36()', 'execute');
  if puede then
    raise exception 'EL ARREGLO NO SIRVE: una funcion recien creada la sigue '
      'pudiendo ejecutar anon. No apliques esto y revisa pg_default_acl.';
  end if;
  if not has_function_privilege('authenticated', 'public.zzz_cobaya_bjj36()', 'execute') then
    raise exception 'PASADA DE FRENADO: se cerro tanto que `authenticated` ya no '
      'puede ejecutar las funciones nuevas. Eso rompe la app entera.';
  end if;
  drop function public.zzz_cobaya_bjj36();

  -- Y lo mismo en `private`, que es donde estaba la trampa.
  create function private.zzz_cobaya_bjj36() returns int language sql as 'select 1';
  if has_function_privilege('anon', 'private.zzz_cobaya_bjj36()', 'execute') then
    raise exception 'anon puede ejecutar una funcion nueva de private';
  end if;
  if not has_function_privilege('authenticated', 'private.zzz_cobaya_bjj36()', 'execute') then
    raise exception 'UN AYUDANTE NUEVO DE LA RLS NACERIA SIN PERMISO: la '
      'siguiente politica que lo use fallara con `permission denied`, y el '
      'error no se parecera a su causa.';
  end if;
  drop function private.zzz_cobaya_bjj36();

  raise notice 'OK  una funcion nueva nace SIN anon y CON authenticated, en public y en private';
end $$;

commit;
