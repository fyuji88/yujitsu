#!/usr/bin/env bash
# ============================================================
#  FASE 3 · Dos personas, una plaza, a la vez
#
#    PGURL="postgresql://postgres@127.0.0.1:55432/bjj" \
#    bash db/pruebas/quedadas-concurrencia.sh
#
#  Esto NO se puede probar desde un solo fichero .sql: hace falta que dos
#  sesiones distintas esten dentro de la funcion al mismo tiempo. Razonar
#  sobre el codigo no vale — el caso clasico es que los dos lean "queda una
#  plaza" antes de que ninguno haya escrito, y eso solo se ve ejecutando.
#
#  Lo que tiene que pasar: uno entra apuntado, el otro a lista_espera. Nunca
#  dos apuntados con plazas_max = 1.
# ============================================================
set -u
PSQL=${PSQL:-psql}
PGURL=${PGURL:-postgresql://postgres@127.0.0.1:55432/bjj}

q() { "$PSQL" "$PGURL" -v ON_ERROR_STOP=1 -Atq -c "$1"; }

# --- preparacion: una quedada con UNA sola plaza -------------------------
q "delete from quedadas where titulo = 'PRUEBA concurrencia';" >/dev/null
q "insert into quedadas (id, grupo_id, titulo, fecha, plazas_max, creado_por)
   values ('77770000-0000-0000-0000-000000000007',
           'dddd0000-0000-0000-0000-00000000000d',
           'PRUEBA concurrencia', current_date, 1,
           'aaaa0000-0000-0000-0000-00000000000a');" >/dev/null

# El admin ya es miembro; el segundo tambien tiene que serlo.
q "insert into miembros_grupo (grupo_id, practicante_id, rol)
   values ('dddd0000-0000-0000-0000-00000000000d',
           'bbbb0000-0000-0000-0000-00000000000b', 'miembro')
   on conflict do nothing;" >/dev/null

# --- dos sesiones, a la vez ---------------------------------------------
# El pg_sleep dentro de la transaccion garantiza que se solapan: la segunda
# llega al advisory lock mientras la primera lo tiene cogido.
intento() {
  "$PSQL" "$PGURL" -Atq -c "
    begin;
      select set_config('request.jwt.claims', '{\"sub\":\"$1\"}', true);
      set local role authenticated;
      select pg_sleep(0.3);
      select apuntarse_a_quedada('77770000-0000-0000-0000-000000000007')->>'estado';
    commit;" 2>&1 | tail -1
}

intento '11110000-0000-0000-0000-000000000001' > /tmp/_c1.txt &
P1=$!
intento '22220000-0000-0000-0000-000000000002' > /tmp/_c2.txt &
P2=$!
wait $P1 $P2

R1=$(cat /tmp/_c1.txt); R2=$(cat /tmp/_c2.txt)
rm -f /tmp/_c1.txt /tmp/_c2.txt
echo "  sesion 1 -> $R1"
echo "  sesion 2 -> $R2"

APUNTADOS=$(q "select count(*) from inscripciones
                where quedada_id = '77770000-0000-0000-0000-000000000007'
                  and estado = 'apuntado';")
ESPERA=$(q "select count(*) from inscripciones
             where quedada_id = '77770000-0000-0000-0000-000000000007'
               and estado = 'lista_espera';")

if [ "$APUNTADOS" = "1" ] && [ "$ESPERA" = "1" ]; then
  echo "PASS  con una plaza y dos a la vez: 1 apuntado y 1 en lista de espera"
  echo ""
  echo "######## LA PLAZA SE DECIDE EN LA BASE, NO EN EL CLIENTE ########"
  exit 0
fi

echo "FALLO  quedaron $APUNTADOS apuntados y $ESPERA en espera (se esperaba 1 y 1)"
exit 1
