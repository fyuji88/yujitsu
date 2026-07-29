-- ============================================================
--  BJJ TRACKER — El acento del grupo   ·   Migracion bjj_20
-- ============================================================
--
--  El grupo elige UN color: el acento de marca. Nunca la paleta entera.
--
--  De ese acento la app deriva lo demas —el color de texto legible, la tinta
--  de dentro del boton, los rellenos suaves— midiendo el contraste contra el
--  fondo del tema. Asi una academia puede poner el color que quiera y no
--  puede dejarse la interfaz ilegible.
--
--  Y NO TOCA LOS COLORES DE DATOS. Azul para ti y naranja para el rival se
--  quedan fijos en el codigo. Si el grupo pudiera cambiarlos, una academia
--  podria elegir un acento que deje ilegible su propio heatmap; y ademas
--  verde contra naranja es justo el par que se cae con el daltonismo mas
--  comun, que afecta a cerca del 8 % de los hombres.
-- ============================================================

alter table grupos
  add column color_acento text not null default '#458c50';

-- El cliente ya valida el hex antes de meterlo en un `style`, pero la
-- comprobacion buena es la que no se puede saltar: esta columna acaba en CSS,
-- y `red;background:url(...)` es un valor perfectamente legal para un `text`.
alter table grupos
  add constraint grupos_color_acento_chk
  check (color_acento ~* '^#[0-9a-f]{6}$');

comment on column grupos.color_acento is
  'El acento de marca del grupo, en hex. Solo el acento: los colores de datos '
  '(azul = yo, naranja = el rival) no se tematizan nunca. La app deriva de '
  'aqui el texto legible midiendo contraste, asi que un color oscuro o muy '
  'claro no rompe la interfaz.';
