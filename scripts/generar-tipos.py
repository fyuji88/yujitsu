# -*- coding: utf-8 -*-
"""
Genera `src/lib/esquema.generado.ts` desde la base.

    PSQL=/ruta/psql.exe PGURL=postgresql://... python scripts/generar-tipos.py

POR QUE ESTO Y NO REGENERAR `database.types.ts` ENTERO. Ese fichero esta escrito
a mano a proposito: es un SUBCONJUNTO del esquema y lleva dentro el porque de
cada decision —por que `p_par` se llama asi, por que `posicion` es fisica, por
que `orden_en_sesion` no es el orden de la quedada—. Regenerarlo borraria todo
eso, que es justo lo que hace que el fichero valga algo.

Asi que se genera un fichero APARTE, que nadie lee, y `database.types.ts`
COMPRUEBA CONTRA EL en tiempo de compilacion. Las dos mitades se quedan: el
comentario donde hace falta y la verdad donde tiene que estar.

EL AGUJERO QUE CIERRA. `bjj_27` renombro `sesiones.tipo` -> `formato` y
`rolls.orden` -> `orden_en_sesion`, el cliente siguio escribiendo los viejos, y
NADA lo vio: el typecheck da verde porque el tipo escrito a mano ES la unica
fuente que consulta, y los recorridos daban verde porque el stub capturaba las
escrituras sin aplicarlas. Cada sesion y cada roll propio fallaban al
sincronizar. Con esto, el mismo error es un fallo de compilacion.

En el CI se regenera y se compara con lo commiteado: si el esquema se movio y
nadie regenero, el paso se pone rojo.
"""
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8')
except AttributeError:
    pass

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
DESTINO = os.path.join(RAIZ, 'src', 'lib', 'esquema.generado.ts')

PSQL = os.environ.get('PSQL', 'psql')
PGURL = os.environ.get('PGURL', '')

# Postgres -> TypeScript. Las fechas y las horas viajan como texto en JSON, que
# es lo que devuelve PostgREST: ponerlas como Date seria mentir.
TIPOS = {
    'uuid': 'string', 'text': 'string', 'varchar': 'string', 'bpchar': 'string',
    'int2': 'number', 'int4': 'number', 'int8': 'number',
    'numeric': 'number', 'float4': 'number', 'float8': 'number',
    'bool': 'boolean',
    'date': 'string', 'timestamptz': 'string', 'timestamp': 'string', 'time': 'string',
    'json': 'unknown', 'jsonb': 'unknown',
}


def consultar(sql):
    if not PGURL:
        sys.exit('Falta PGURL. Uso: PSQL=... PGURL=... python %s' % sys.argv[0])
    r = subprocess.run([PSQL, PGURL, '-Atq', '-F', '\t', '-c', sql],
                       capture_output=True, text=True, encoding='utf-8')
    if r.returncode != 0:
        sys.exit('psql fallo:\n' + (r.stderr or '').strip())
    return [l.split('\t') for l in (r.stdout or '').splitlines() if l.strip()]


# Los enums, para que salgan como uniones de literales y no como `string`. Es la
# mitad del valor: un `formato: 'sparing'` mal escrito tiene que doler aqui.
enums = {}
for nombre, valores in consultar("""
select t.typname, string_agg(e.enumlabel, '|' order by e.enumsortorder)
  from pg_type t join pg_enum e on e.enumtypid = t.oid
  join pg_namespace n on n.oid = t.typnamespace
 where n.nspname = 'public'
 group by t.typname;
"""):
    enums[nombre] = ' | '.join("'%s'" % v for v in valores.split('|'))


def tipo_ts(udt, nullable):
    array = udt.startswith('_')
    base = udt[1:] if array else udt
    ts = enums.get(base) or TIPOS.get(base)
    if ts is None:
        ts = 'unknown'
    elif array and '|' in ts:
        ts = '(%s)' % ts
    if array:
        ts += '[]'
    return ts + (' | null' if nullable == 'YES' else '')


tablas = {}
for tabla, columna, udt, nullable in consultar("""
select c.table_name, c.column_name, c.udt_name, c.is_nullable
  from information_schema.columns c
  join information_schema.tables t
    on t.table_schema = c.table_schema and t.table_name = c.table_name
 where c.table_schema = 'public' and t.table_type = 'BASE TABLE'
 order by c.table_name, c.ordinal_position;
"""):
    tablas.setdefault(tabla, []).append((columna, tipo_ts(udt, nullable)))

lineas = [
    '/* eslint-disable */',
    '/**',
    ' * GENERADO POR scripts/generar-tipos.py. NO SE EDITA A MANO.',
    ' *',
    ' * Es el esquema tal cual esta en Postgres. No lleva comentarios ni',
    ' * decisiones: para eso esta `database.types.ts`, que es un subconjunto',
    ' * escrito a mano y que COMPRUEBA CONTRA ESTE en tiempo de compilacion.',
    ' *',
    ' * Si esto y la base se separan, el CI se pone rojo: regenera y commitea.',
    ' */',
    '',
    'export interface Tablas {',
]
for tabla in sorted(tablas):
    lineas.append('  %s: {' % tabla)
    for columna, ts in tablas[tabla]:
        lineas.append('    %s: %s;' % (columna, ts))
    lineas.append('  };')
lineas.append('}')
lineas.append('')

nuevo = '\n'.join(lineas)
anterior = ''
if os.path.exists(DESTINO):
    with open(DESTINO, encoding='utf-8') as f:
        anterior = f.read()

with open(DESTINO, 'w', encoding='utf-8', newline='\n') as f:
    f.write(nuevo)

print('%s: %d tablas, %d columnas'
      % (os.path.relpath(DESTINO, RAIZ), len(tablas),
         sum(len(v) for v in tablas.values())))
if anterior and anterior != nuevo:
    print('CAMBIO respecto a lo que habia. Si esto sale en CI, es que el')
    print('esquema se movio y nadie regenero los tipos.')
