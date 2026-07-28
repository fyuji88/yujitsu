# Esquema

Copia de lo que está desplegado en Supabase (proyecto `idzlxkxeadrcolcnmoeo`),
para poder leerlo y probarlo sin entrar al panel.

Migraciones aplicadas en producción, en orden:

| Versión | Nombre | Fichero aquí |
|---|---|---|
| 20260728131027 | bjj_01_esquema_base | `01_esquema_base.sql` |
| 20260728131121 | bjj_02_seed_diccionario | `02_seed_diccionario.sql` |
| 20260728131158 | bjj_03_vistas_analisis | `03_vistas_analisis.sql` |
| 20260728131232 | bjj_04_modo_observador | `04_modo_observador.sql` |
| 20260728131329 | bjj_05_sacar_helper_de_la_api | incluido en `01` |
| 20260728131447 | bjj_06_fk_diferidas_al_borrar | incluido en `01` |
| 20260728133654 | bjj_07_alta_de_companeros | incluido en `01` |
| 20260728134345 | bjj_08_ficha_al_registrarse | `05_ficha_al_registrarse.sql` |

Las migraciones 05 a 07 fueron correcciones que aquí ya están integradas en
`01_esquema_base.sql`, para que ejecutar estos ficheros de cero sobre una base
limpia deje el mismo estado que hay en producción.

`99_datos_demo_opcional.sql` son 3 meses de entrenamientos simulados (41
sesiones, 180 rolls, 679 eventos). Sirve para ver los heatmaps con volumen antes
de tener datos reales. Se borra con `truncate practicantes cascade;`.

## Probar un cambio antes de aplicarlo

Nunca contra producción directamente. Con la CLI de Supabase:

```bash
supabase start                     # Postgres local en Docker
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" -f db/01_esquema_base.sql
```

O con cualquier Postgres 15+ a mano. El esquema necesita que exista `auth.users`
y una función `auth.uid()`; para probar en local basta con:

```sql
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
```
