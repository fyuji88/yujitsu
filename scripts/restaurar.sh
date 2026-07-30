#!/usr/bin/env bash
# ============================================================
#  Restaurar una copia
#
#    scripts/restaurar.sh                          (la más reciente, a bjj_restaurada)
#    scripts/restaurar.sh copia.sql.gz nombre_bd
#
#  ESTO EXISTE PARA QUE NO SE IMPROVISE. El día que haga falta restaurar va a
#  ser un mal día, y ese no es el momento de descubrir qué flags necesitaba
#  `pg_dump` ni de qué orden van los roles. Aquí está escrito.
#
#  Y ADEMÁS SE CORRE EN FRÍO, sin emergencia, cada vez que se toca el script de
#  copia: una copia que nunca se ha restaurado no es una copia, es un fichero.
#  La primera versión de `copia.sh` producía uno de 80 KB con muy buena pinta
#  que daba 49 errores al restaurarlo. Solo se supo restaurándolo.
#
#  Restaura SIEMPRE en una base LOCAL nueva. Nunca contra producción: si algún
#  día hay que devolver datos allí, se mira primero lo restaurado aquí y se
#  decide qué se sube, a mano y con calma.
# ============================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIA="${1:-$(ls -1t "$RAIZ"/../copias-yujitsu/yujitsu_*.sql.gz 2>/dev/null | head -1)}"
BASE="${2:-bjj_restaurada}"
LOCAL="${PGLOCAL:-postgresql://postgres@127.0.0.1:55432}"

if [ -z "${COPIA:-}" ] || [ ! -f "$COPIA" ]; then
  echo "No encuentro ninguna copia. Pásala como primer argumento." >&2
  exit 1
fi

echo "Restaurando $(basename "$COPIA") en $BASE ..."
psql "$LOCAL/postgres" -q -c "drop database if exists $BASE;"
psql "$LOCAL/postgres" -q -c "create database $BASE;"

# Los tres roles de Supabase. El volcado va con `--no-owner --no-privileges`,
# pero las POLÍTICAS los nombran (`to authenticated`), así que sin ellos la
# restauración falla en cada `create policy`.
psql "$LOCAL/$BASE" -q -c "
do \$\$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end \$\$;
create schema if not exists auth;"

# El mismo bootstrap que usa el CI: roles, esquema `auth`, `auth.users` mínima
# y `auth.uid()`. Nada de eso viene en la copia —vive en el esquema `auth`, que
# es de Supabase— y de `auth.uid()` cuelga media RLS: sin ella, cada
# `create policy` del volcado falla y se cae todo en cascada. Salió
# restaurando, con 77 errores.
#
# Que el CI y la restauración compartan bootstrap no es casualidad: los dos
# necesitan exactamente lo mismo, un Postgres que se parezca a Supabase.
psql "$LOCAL/$BASE" -q -f "$RAIZ/db/ci/00_bootstrap.sql" > /dev/null 2>&1

# El volcado trae su propio `create schema public`, así que se quita el que la
# base trae de fábrica. Si no, da "already exists" y cuenta como error.
psql "$LOCAL/$BASE" -q -c "drop schema if exists public cascade;"

REG="$(mktemp)"
gzip -dc "$COPIA" | psql "$LOCAL/$BASE" -q > "$REG" 2>&1 || true

ERRORES="$(grep -c '^ERROR' "$REG" || true)"
if [ "$ERRORES" -gt 0 ]; then
  echo "LA RESTAURACIÓN DIO $ERRORES ERRORES:" >&2
  grep '^ERROR' "$REG" | sort -u | head -10 >&2
  echo "" >&2
  echo "La copia NO sirve tal cual. No la des por buena." >&2
  exit 1
fi

# El volcado va con `--no-privileges` a propósito —los dueños y permisos de
# Supabase no se pueden reproducir aquí— pero eso deja el esquema sin `usage`
# para los roles, y entonces `authenticated` ve las tablas como si no
# existieran: el error que da Postgres es "relation does not exist", no
# "permission denied", así que despista bastante.
#
# Se repone el mínimo y se vuelve a cerrar `anon` con su propia migración, para
# que la copia restaurada tenga las mismas reglas que producción y se pueda
# pasar la batería de RLS encima.
psql "$LOCAL/$BASE" -q -c "
grant usage on schema public, private to anon, authenticated, service_role;
grant all on all tables in schema public to authenticated, service_role;
grant all on all sequences in schema public to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;

-- Y los privilegios POR DEFECTO, que se van con el esquema al recrearlo. Sin
-- esto la copia restaurada parece igual pero no lo es: una tabla nueva no le
-- llegaria a authenticated. Lo cazo el caso 29 de la bateria.
-- (Sin acentos a proposito: esto viaja en un psql -c, y la linea de comandos
-- de Windows no es UTF-8.)
alter default privileges in schema public grant all on tables to authenticated, service_role;
alter default privileges in schema public grant all on sequences to authenticated, service_role;
alter default privileges in schema public grant execute on functions to authenticated, service_role;"
psql "$LOCAL/$BASE" -q -f "$RAIZ/db/20_anon_sin_privilegios.sql" > /dev/null 2>&1

echo "Sin errores. Lo que hay dentro:"
psql "$LOCAL/$BASE" -Atq -c "
select '  rolls         '||count(*) from rolls
union all select '  eventos       '||count(*) from eventos
union all select '  sesiones      '||count(*) from sesiones
union all select '  practicantes  '||count(*) from practicantes
union all select '  logros        '||count(*) from logros
union all select '  usuarios      '||count(*) from auth.users;"

echo ""
echo "Compáralo con producción antes de darlo por bueno:"
echo "  psql \"\$PROD\" -Atq -c \"select count(*) from rolls;\""
