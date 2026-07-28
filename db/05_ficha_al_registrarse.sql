-- Cuando alguien entra por primera vez (magic link), Supabase crea su fila en
-- auth.users. Sin esto habria que crear la ficha de `practicantes` a mano desde
-- la app, con el riesgo de quedarse a medias si algo falla entre las dos cosas.
-- Un trigger lo hace atomico: existe el usuario => existe su ficha.

create or replace function private.crear_ficha_practicante()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_nombre text;
begin
  -- nombre del metadata si la app lo manda; si no, la parte local del email
  v_nombre := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'nombre'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    initcap(split_part(new.email, '@', 1)),
    'Practicante'
  );

  insert into practicantes (user_id, nombre, usa_sistema, creado_por)
  values (new.id, v_nombre, true, new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger crear_ficha_al_registrarse
  after insert on auth.users
  for each row execute function private.crear_ficha_practicante();

comment on function private.crear_ficha_practicante() is
  'Crea la ficha de practicante en cuanto nace el usuario. usa_sistema = true porque, por definicion, tiene cuenta.';
