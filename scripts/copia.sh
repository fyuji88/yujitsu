#!/usr/bin/env bash
# ============================================================
#  Copia de seguridad de produccion
#
#    scripts/copia.sh                 (a la carpeta por defecto)
#    scripts/copia.sh /otra/carpeta
#
#  POR QUE EXISTE. El plan gratuito de Supabase NO TIENE COPIAS DE NINGUNA
#  CLASE. Dentro hay meses de rolls de gente de verdad, y todo lo demas del
#  backlog se puede arreglar tarde — esto no. Si se corrompe algo o alguien
#  ejecuta el `truncate` equivocado, no hay a donde volver.
#
#  ESTO NO SUSTITUYE AL PLAN PRO. Depende de que este portatil se encienda, asi
#  que lo que hace es convertir "lo perdemos todo" en "perdemos como mucho una
#  semana". Cuando haya Pro, con sus copias diarias y su recuperacion a un
#  punto en el tiempo, esto pasa a ser el cinturon de repuesto.
#
#  QUE SE GUARDA: el volcado completo del esquema `public` mas `auth.users`,
#  que es lo que hace falta para reconstruir. No se guarda el resto del esquema
#  `auth` —contraseñas y sesiones— a proposito: son credenciales, no datos
#  nuestros, y las regenera Supabase.
#
#  Se queda con las 8 ultimas y borra las anteriores: una copia que llena el
#  disco deja de hacerse, y una copia que no se hace no es una copia.
# ============================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINO="${1:-$RAIZ/../copias-yujitsu}"
CUANTAS_GUARDAR=8

# Las credenciales salen de .env.local, que esta en .gitignore. Se leen con
# `cut` y no con `eval`: una contraseña con comillas o simbolos rompe el eval
# entero y el error no se parece en nada a la causa.
val() { grep -m1 "^$1=" "$RAIZ/.env.local" | cut -d= -f2- | tr -d '\r'; }

export PGPASSWORD="$(val SUPABASE_DB_PASSWORD)"
HOST="$(val SUPABASE_DB_HOST)"
PUERTO="$(val SUPABASE_DB_PORT)"
USUARIO="$(val SUPABASE_DB_USER)"
BASE="$(val SUPABASE_DB_NAME)"

if [ -z "${PGPASSWORD:-}" ] || [ -z "$HOST" ]; then
  echo "FALTAN las credenciales en .env.local (SUPABASE_DB_*)." >&2
  exit 1
fi

mkdir -p "$DESTINO"
SELLO="$(date +%Y-%m-%d_%H%M)"
FICHERO="$DESTINO/yujitsu_$SELLO.sql.gz"

echo "Copiando $BASE de $HOST ..."
# DOS VOLCADOS, y el porqué importa: con `--table`, pg_dump saca SOLO esas
# tablas — sin los tipos, sin las funciones y sin el esquema. La primera
# versión de este script hacía eso: producía un fichero de 80 KB con 17 bloques
# COPY que parecía perfecto, y al restaurarlo daba 49 errores del tipo "type
# bjj_posicion does not exist". Una copia que no se ha restaurado nunca no es
# una copia.
#
# Así que: los esquemas `public` y `private` ENTEROS —tipos, funciones, vistas,
# políticas y datos— y aparte `auth.users`, que es la única tabla de `auth` que hace falta
# para reconstruir. El resto de `auth` son contraseñas y sesiones: son
# credenciales, no datos nuestros, y las regenera Supabase.
#
# DE `auth.users` SOLO SE LLEVA `id` Y `email`, y en crudo. Volcarla con
# `pg_dump` arrastraba dos problemas: el trigger `crear_ficha_al_registrarse`,
# que necesita el esquema `private` antes de que exista, y —peor— que al
# restaurarla ese trigger SE DISPARA y crea una ficha de practicante por
# usuario, encima de las que trae la copia. Lo único que hace falta de esa
# tabla es qué ids existen, para que `practicantes.user_id` siga resolviendo.
# Del resto —contraseñas y sesiones— se encarga Supabase, y no son datos
# nuestros.
#
# Y va PRIMERO, porque `practicantes.user_id` la referencia por clave foránea.
{
  echo "-- Usuarios: solo id y email. El resto del esquema auth es de Supabase."
  echo "COPY auth.users (id, email) FROM stdin;"
  psql -h "$HOST" -p "$PUERTO" -U "$USUARIO" -d "$BASE" -Atq \
    -c "\\copy (select id, email from auth.users order by id) to stdout"
  echo "\\."
  echo ""
  pg_dump -h "$HOST" -p "$PUERTO" -U "$USUARIO" -d "$BASE" \
    --schema=public --schema=private --no-owner --no-privileges
} | gzip > "$FICHERO"

# Un fichero vacio o truncado es peor que ninguno: da sensacion de estar a
# salvo. Se comprueba que el gzip esta entero y que dentro hay datos de verdad.
gzip -t "$FICHERO"
FILAS="$(gzip -dc "$FICHERO" | grep -c '^COPY ' || true)"
TIPOS="$(gzip -dc "$FICHERO" | grep -c 'CREATE TYPE' || true)"
BYTES="$(wc -c < "$FICHERO")"

# Se comprueba que están los TIPOS además de los datos: es justo lo que
# faltaba en la versión rota, y es lo que distingue una copia restaurable de un
# montón de filas sueltas.
if [ "$FILAS" -lt 5 ] || [ "$BYTES" -lt 10000 ] || [ "$TIPOS" -lt 5 ]; then
  echo "LA COPIA NO SIRVE: $BYTES bytes, $FILAS bloques COPY, $TIPOS tipos. Se borra." >&2
  rm -f "$FICHERO"
  exit 1
fi

echo "  $FICHERO"
echo "  $(( BYTES / 1024 )) KB, $FILAS tablas con datos, $TIPOS tipos"

# Rotacion.
ls -1t "$DESTINO"/yujitsu_*.sql.gz 2>/dev/null | tail -n +$((CUANTAS_GUARDAR + 1)) \
  | while read -r viejo; do echo "  (se borra la vieja) $(basename "$viejo")"; rm -f "$viejo"; done

echo "Guardadas: $(ls -1 "$DESTINO"/yujitsu_*.sql.gz 2>/dev/null | wc -l) copias en $DESTINO"
