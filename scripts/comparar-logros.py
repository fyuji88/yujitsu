# -*- coding: utf-8 -*-
"""
Cruza las cuatro fuentes de verdad del catalogo de logros y lista lo que no
coincide.

    psql ... -Atq -c "select jsonb_object_agg(clave, nombre) from logros;" > /tmp/db.json
    python scripts/comparar-logros.py /tmp/db.json

POR QUE HACE FALTA. El catalogo vive en cuatro sitios a la vez y cada uno tiene
su motivo: `docs/logros-catalogo.sql` es la fuente de diseño, la migracion es lo
que se aplica, `logros.es.ts` es lo unico que ve la gente, y la base es la
verdad. Cuatro copias se separan solas — de hecho ya paso: se quito un logro y
se añadio otro, y el fichero de diseño se quedo con los dos antiguos.

LO QUE DE VERDAD IMPORTA es la seccion de CLAVES. Un nombre distinto es un
despiste; una CLAVE distinta rompe los iconos, las vistas y todo lo que la gente
ya tenia conseguido, porque la clave es lo que se guarda. Si esa seccion saca
algo, no lo arregles sin preguntar.
"""
import io, re, sys, json

def del_sql(ruta):
    """(clave, nombre) de un insert into logros."""
    s = io.open(ruta, encoding='utf-8').read()
    if 'insert into logros' not in s:
        return {}
    s = s[s.index('insert into logros'):]
    # Con sangría opcional: `db/18` indenta su fila y sin esto no la veía.
    return dict(re.findall(r"^\s*\('([a-z_]+)',\s*'([^']*)'", s, re.M))

def del_ts(ruta):
    s = io.open(ruta, encoding='utf-8').read()
    return dict(re.findall(r"^\s+([a-z_]+):\s*\{\s*nombre:\s*'((?:[^'\\]|\\')*)'", s, re.M))

fuentes = {
    'catalogo (docs/logros-catalogo.sql)': del_sql('docs/logros-catalogo.sql'),
    'migracion (db/16_logros.sql)':        del_sql('db/16_logros.sql'),
    'textos (logros.es.ts)':               del_ts('src/lib/textos/logros.es.ts'),
}
# La migracion 18 añade uno suelto.
extra = del_sql('db/18_logros_flawless_y_doble_sesion.sql')
fuentes['migracion (db/16 + db/18)'] = {**fuentes['migracion (db/16_logros.sql)'], **extra}
del fuentes['migracion (db/16_logros.sql)']

# La base, que es la verdad de verdad.
fuentes['base de datos'] = json.load(io.open(sys.argv[1], encoding='utf-8'))

for k, v in fuentes.items():
    print(f'{k:38} {len(v)} logros')

claves = set()
for v in fuentes.values():
    claves |= set(v)

print('\n--- CLAVES que no estan en todas partes ---')
hay = False
for c in sorted(claves):
    donde = [k for k, v in fuentes.items() if c in v]
    if len(donde) != len(fuentes):
        hay = True
        faltan = [k for k in fuentes if k not in donde]
        print(f'  {c:22} esta en: {", ".join(donde)}')
        print(f'  {"":22} FALTA en: {", ".join(faltan)}')
if not hay:
    print('  (ninguna: las claves coinciden en las cuatro)')

print('\n--- NOMBRES que no coinciden ---')
hay = False
for c in sorted(claves):
    nombres = {k: v[c] for k, v in fuentes.items() if c in v}
    if len(set(nombres.values())) > 1:
        hay = True
        print(f'  {c}:')
        for k, n in nombres.items():
            print(f'      {k:38} "{n}"')
if not hay:
    print('  (ninguno: donde la clave existe, el nombre es el mismo)')
