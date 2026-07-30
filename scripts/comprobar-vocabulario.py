# -*- coding: utf-8 -*-
"""
Comprueba que el esquema sigue la regla de "una palabra, un concepto".

    PSQL=/ruta/psql.exe PGURL=postgresql://... python scripts/comprobar-vocabulario.py

Sale con codigo distinto de cero si algo falla, para que el CI se pare.

POR QUE EXISTE. En esta base la seguridad entera son politicas de RLS y el
analisis entero son vistas. Un nombre ambiguo no produce un error: produce una
consulta correcta que devuelve otra cosa. Eso no se cae, da un numero — y un
numero equivocado no se distingue de uno bueno mirandolo.

Ya paso una vez. El logro EL ULTIMO EN IRSE se definio como "el roll con el
mayor `orden` de la quedada", y `rolls.orden` era el orden dentro de la sesion
de cada uno: cada persona numera los suyos del 1 al n. El logro no premiaba
irse el ultimo, premiaba haber rodado mas. Hubo que sacarlo del catalogo. La
columna no mentia — simplemente no decia de quien era la secuencia, y quien la
leyo relleno el hueco con lo que le parecio razonable.

=============================================================================
LO QUE ESTE SCRIPT NO VE, Y HAY QUE DECIRLO
=============================================================================
La comprobacion 1 solo caza AMBIGUEDAD CON DIVERGENCIA DE TIPO: dos columnas
que se llaman igual y no pueden ser lo mismo porque ni siquiera comparten tipo.

Dos columnas `text` que signifiquen cosas distintas se le escapan enteras. Dos
`uuid` tambien. `posiciones.grupo` y `sesiones.grupo_id` habrian pasado esta
comprobacion sin despeinarse si las dos hubieran sido uuid.

De esa otra mitad se encarga la regla escrita en CLAUDE.md y quien revisa, no
la maquina. Un comprobador que se vende como completo es peor que ninguno:
convierte "lo he mirado" en "el CI esta verde", y esas dos frases no significan
lo mismo.

Las comprobaciones 2, 3 y 4 si son exhaustivas dentro de lo suyo — la lista de
nombres prohibidos, el `security_invoker` de las vistas y las etiquetas de
migracion son cerradas.

Y tampoco mira NOMBRES DE PARAMETRO: `private.es_admin(p_grupo)` y el puente
`registrar_roll_observado(p_grupo, ...)` de bjj_28 pasan esta comprobacion sin
despeinarse. Los dos estan ahi a proposito y anotados en docs/CAMBIOS.md.
"""
import os
import re
import subprocess
import sys

# La consola de Windows no es UTF-8 y se come los acentos y las rayas del texto
# de ayuda, que es justo lo que hay que leer cuando esto falla.
try:
    sys.stdout.reconfigure(encoding='utf-8')
except AttributeError:                        # Python < 3.7
    pass

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)

PSQL = os.environ.get('PSQL', 'psql')
PGURL = os.environ.get('PGURL', '')

# -----------------------------------------------------------------------------
# NOMBRES PROHIBIDOS. Los que la migracion bjj_27 renombro. Ninguno puede
# sobrevivir en `public`, ni como tabla, ni como vista, ni como columna, ni como
# funcion, ni como tipo.
#
# Esto es lo que convierte "¿me acorde de renombrar todas las vistas?" en una
# respuesta que da la maquina en vez de en un acto de fe. Una vista que expone
# `grupo_id` despues del renombrado no da ningun error: sigue funcionando y
# publica el nombre viejo hacia fuera, y el cliente pide `equipo_id` y recibe
# undefined. Ese fallo es mudo por los dos lados.
COLUMNAS_PROHIBIDAS = ('grupo_id', 'roll_grupo_id', 'posicion_grupo')
COLUMNAS_PROHIBIDAS_EN = (('sesiones', 'tipo'),
                          ('rolls', 'orden'),
                          ('inscripciones', 'orden'))
RELACIONES_PROHIBIDAS = ('grupos', 'miembros_grupo')
TIPOS_PROHIBIDOS = ('bjj_rol_grupo', 'bjj_grupo_posicion')
FUNCIONES_PROHIBIDAS = ('mis_grupos', 'comparte_grupo', 'crear_grupo')


def consultar(sql):
    if not PGURL:
        sys.exit('Falta PGURL. Uso: PSQL=... PGURL=... python %s' % sys.argv[0])
    r = subprocess.run([PSQL, PGURL, '-Atq', '-F', '|', '-c', sql],
                       capture_output=True, text=True, encoding='utf-8')
    if r.returncode != 0:
        sys.exit('psql fallo:\n' + (r.stderr or '').strip())
    return [l for l in (r.stdout or '').splitlines() if l.strip()]


def excepciones():
    """Los nombres perdonados, con su motivo escrito al lado."""
    ruta = os.path.join(AQUI, 'excepciones-vocabulario.txt')
    fuera = set()
    with open(ruta, encoding='utf-8') as f:
        for linea in f:
            linea = linea.strip()
            if not linea or linea.startswith('#'):
                continue
            fuera.add(linea.split('#')[0].strip())
    return fuera


fallos = []
perdonados = excepciones()

# ---------------------------------------------------------------- 1 · ambiguas
print('1 - Columnas con el mismo nombre y distinto tipo')
filas = consultar("""
select c.column_name, count(distinct c.udt_name), string_agg(distinct c.table_name, ', ')
from information_schema.columns c
join information_schema.tables t
  on t.table_schema = c.table_schema and t.table_name = c.table_name
 and t.table_type = 'BASE TABLE'
where c.table_schema = 'public'
group by c.column_name
having count(distinct c.udt_name) > 1
order by 1;
""")
for fila in filas:
    nombre, cuantos, tablas = fila.split('|')
    if nombre in perdonados:
        print('    (perdonada) %-14s %s tipos en %s' % (nombre, cuantos, tablas))
    else:
        fallos.append('"%s" significa %s cosas distintas: %s' % (nombre, cuantos, tablas))
        print('    FALLO       %-14s %s tipos en %s' % (nombre, cuantos, tablas))
if not filas:
    print('    ninguna')

# -------------------------------------------------------------- 2 · prohibidos
print('')
print('2 - Nombres que la migracion bjj_27 tenia que hacer desaparecer')
sobrevive = []

sobrevive += consultar(
    "select 'columna ' || table_name || '.' || column_name"
    "  from information_schema.columns"
    " where table_schema = 'public' and column_name in (%s);"
    % ', '.join("'%s'" % c for c in COLUMNAS_PROHIBIDAS))

for tabla, columna in COLUMNAS_PROHIBIDAS_EN:
    sobrevive += consultar(
        "select 'columna ' || table_name || '.' || column_name"
        "  from information_schema.columns"
        " where table_schema = 'public' and table_name = '%s' and column_name = '%s';"
        % (tabla, columna))

sobrevive += consultar(
    "select 'tabla o vista ' || table_name from information_schema.tables"
    " where table_schema = 'public' and table_name in (%s);"
    % ', '.join("'%s'" % r for r in RELACIONES_PROHIBIDAS))

# Las funciones se miran tambien en `private`: ahi viven los ayudantes de la RLS.
sobrevive += consultar(
    "select 'funcion ' || n.nspname || '.' || p.proname"
    "  from pg_proc p join pg_namespace n on n.oid = p.pronamespace"
    " where n.nspname in ('public', 'private') and p.proname in (%s);"
    % ', '.join("'%s'" % f for f in FUNCIONES_PROHIBIDAS))

sobrevive += consultar(
    "select 'tipo ' || typname from pg_type where typname in (%s);"
    % ', '.join("'%s'" % t for t in TIPOS_PROHIBIDOS))

for s in sobrevive:
    fallos.append('sobrevive un nombre prohibido: ' + s)
    print('    FALLO  ' + s)
if not sobrevive:
    print('    ninguno sobrevive')

# --------------------------------------------------------- 3 · security_invoker
print('')
print('3 - Todas las vistas de public con security_invoker')
#
# OJO CON EL LITERAL. Postgres lo guarda como `security_invoker=on`, NO como
# `=true`, aunque las dos formas se aceptan al crearla. Una comprobacion escrita
# contra `=true` devuelve cero filas SIEMPRE y da verde sin haber comprobado
# nada. Ese error ya se cometio una vez en este proyecto, asi que queda escrito.
#
# Y por eso esta tanda renombro las columnas de las vistas con
# `alter view ... rename column` y no recreandolas: recrear es drop + create, y
# ahi es donde se pierde el ajuste. Una vista sin `security_invoker` lee con los
# permisos de su dueño en vez de con los de quien consulta, o sea que cualquiera
# ve los datos de otro equipo. En una app donde la RLS es todo el perimetro, un
# renombrado cosmetico no puede ser la via por la que se abre un agujero.
abiertas = consultar("""
select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'v' and n.nspname = 'public'
  and coalesce(c.reloptions::text, '') not like '%security_invoker=on%'
order by 1;
""")
total = consultar("select count(*) from pg_class c join pg_namespace n"
                  " on n.oid = c.relnamespace where c.relkind = 'v' and n.nspname = 'public';")
for v in abiertas:
    fallos.append('la vista %s no tiene security_invoker=on' % v)
    print('    FALLO  ' + v)
if not abiertas:
    print('    %s de %s vistas, todas' % (total[0], total[0]))

# ------------------------------------------- 4 · etiquetas de migracion unicas
print('')
print('4 - Cada migracion reclama una etiqueta bjj_NN distinta')
#
# Esta no consulta la base: lee `db/*.sql`. La etiqueta vive en un comentario y
# por eso se desincroniza sin que nada proteste — dos ficheros diciendo ser la
# misma migracion, o una que no existe.
#
# Lo cazo Felipe a ojo, no yo: `db/18_ambito_dia.sql` y
# `db/19_logros_flawless_y_doble_sesion.sql` decian los dos `bjj_23`, y `bjj_24`
# no aparecia por ningun lado. La verdad estaba en produccion, en
# `supabase_migrations.schema_migrations`, que registra
# `bjj_24_logros_flawless_y_doble_sesion`. Un numero de migracion que miente es
# exactamente el mismo problema que un nombre de columna que miente: no falla,
# despista.
etiquetas = {}
db = os.path.join(RAIZ, 'db')
for fichero in sorted(os.listdir(db)):
    if not fichero.endswith('.sql'):
        continue
    with open(os.path.join(db, fichero), encoding='utf-8') as f:
        hallado = re.search(r'\bbjj_(\d{2})\b', f.read())
    if hallado:
        etiquetas.setdefault('bjj_' + hallado.group(1), []).append(fichero)

repetidas = {e: fs for e, fs in etiquetas.items() if len(fs) > 1}
for etiqueta, ficheros in sorted(repetidas.items()):
    fallos.append('%s la reclaman %d ficheros: %s'
                  % (etiqueta, len(ficheros), ', '.join(ficheros)))
    print('    FALLO  %s <- %s' % (etiqueta, ', '.join(ficheros)))
if not repetidas:
    print('    %d etiquetas, ninguna repetida' % len(etiquetas))

# ------------------------------- 5 · lo que el cliente dice que va a escribir
print('')
print('5 - Los *Insert de database.types.ts existen como columnas')
#
# ESTA ES LA QUE FALTABA, y su ausencia costo un bug en produccion.
#
# `src/lib/database.types.ts` es un subconjunto del esquema ESCRITO A MANO. Si
# una migracion renombra una columna y el fichero no se entera, TypeScript no
# dice nada —el tipo es la unica fuente que consulta— y los recorridos en
# navegador tampoco, porque el stub CAPTURA las escrituras en vez de aplicarlas.
# El fallo aparece en el movil de alguien, semanas despues, como un roll que no
# sube.
#
# Paso de verdad: bjj_27 renombro `sesiones.tipo` -> `formato` y `rolls.orden`
# -> `orden_en_sesion`, y el cliente siguio escribiendo los viejos. Cada sesion
# y cada roll propio fallaba al sincronizar.
tipos = os.path.join(RAIZ, 'src', 'lib', 'database.types.ts')
with open(tipos, encoding='utf-8') as f:
    fuente = f.read()

# `XxxInsert` -> la tabla que le toca. Solo los Insert: los Row se leen, y leer
# una columna que no existe si lo caza el typecheck contra la respuesta.
TABLA_DE = {'SesionInsert': 'sesiones', 'RollInsert': 'rolls', 'EventoInsert': 'eventos'}
malas = []
for interfaz, tabla in sorted(TABLA_DE.items()):
    m = re.search(r'export interface %s \{(.*?)\n\}' % interfaz, fuente, re.S)
    if not m:
        malas.append('no encuentro la interfaz %s' % interfaz)
        continue
    campos = set(re.findall(r'^\s{2}([a-z_]+)\??:', m.group(1), re.M))
    reales = set(consultar(
        "select column_name from information_schema.columns"
        " where table_schema = 'public' and table_name = '%s';" % tabla))
    sobran = sorted(campos - reales)
    if sobran:
        malas.append('%s declara campos que no son columnas de %s: %s'
                     % (interfaz, tabla, ', '.join(sobran)))
    print('    %-14s -> %-10s %d campos, %s'
          % (interfaz, tabla, len(campos),
             'todos existen' if not sobran else 'FALLO: ' + ', '.join(sobran)))

fallos += malas

# ---------------------------------------------------------------------- final
print('')
if fallos:
    print('######## %d FALLOS DE VOCABULARIO ########' % len(fallos))
    for f in fallos:
        print('  - ' + f)
    print('')
    print('La regla esta en CLAUDE.md: una palabra, un concepto. Si el nombre')
    print('nuevo es legitimo, va a scripts/excepciones-vocabulario.txt CON EL')
    print('MOTIVO ESCRITO — no basta con añadirlo a la lista.')
    sys.exit(1)

print('######## VOCABULARIO OK ########')
print('Recuerda lo que esto NO ve: dos columnas del mismo tipo que signifiquen')
print('cosas distintas se le escapan. De eso se encarga quien revisa.')
