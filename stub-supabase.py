"""
Stub local de Supabase para pruebas end-to-end.

Este contenedor no tiene salida a supabase.co, así que la app se prueba contra
esta imitación de GoTrue + PostgREST. Los datos semilla (ids de tecnicas, ficha
del practicante) son los REALES del proyecto, y todo lo que la app escribe se
guarda en /tmp/capturado.json para luego replicarlo contra la base de verdad.
Así se prueba la app entera y se comprueba que sus payloads los acepta el
esquema real, sin poder llegar a la red.
"""
import base64, json, os, re, subprocess, threading, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

# Puente opcional a un Postgres de verdad, para la pantalla de analisis.
#
# Las tablas de mentira de aqui abajo bastan para el logging, pero el analisis
# necesita las vistas, las funciones de agregacion y volumen de datos: con tres
# filas inventadas no se ve si el heatmap esta bien. Con estas dos variables el
# stub deja de fingir y consulta la base:
#
#   PSQL=/ruta/a/psql  PGURL="postgresql://postgres@127.0.0.1:55432/bjj" \
#   CAPTURA=./capturado.json python stub-supabase.py
#
# Solo lectura y solo para lo que la pantalla de analisis necesita.
PSQL = os.environ.get('PSQL')
PGURL = os.environ.get('PGURL')
TABLAS_PUENTE = ('practicantes', 'tecnicas')
RPC_PUENTE = ('analisis', 'analisis_rolls_celda')


def consultar(sql):
    """Devuelve el resultado de una consulta que produce un solo json."""
    r = subprocess.run([PSQL, PGURL, '-At', '-c', sql],
                       capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or 'psql fallo')
    return json.loads(r.stdout.strip() or 'null')


def literal(v):
    """Literal SQL seguro para lo poco que se pasa desde el navegador."""
    if v is None:
        return 'null'
    return "'" + str(v).replace("'", "''") + "'"

USER_ID = '55555555-5555-5555-5555-555555555555'
PRACTICANTE_ID = '66666666-6666-6666-6666-666666666666'
PABLO_ID = '77777777-7777-7777-7777-777777777777'
NURIA_ID = '99999999-9999-9999-9999-999999999999'
MARC_ID = '88888888-8888-8888-8888-888888888888'

# Donde se deja lo capturado. En Windows '/tmp' no existe, asi que se puede
# apuntar a otro sitio con la variable CAPTURA.
SALIDA = os.environ.get('CAPTURA', '/tmp/capturado.json')

# El unico codigo que acepta /auth/v1/verify. Cualquier otro se rechaza como
# lo haria GoTrue, para poder probar tambien el camino del codigo mal tecleado.
CODIGO_BUENO = '123456'

# Cuentas registradas: email -> contraseña. Sirve para distinguir entrar de
# crear cuenta, que es justo lo que la pantalla de entrada separa.
CUENTAS = {'e2e@bjjtracker.test': 'contrasena-e2e'}

TECNICAS = [
    {'id': '9f319790-39b0-4274-a946-80a580850791', 'slug': 'mata_leao'},
    {'id': '2d869a77-1b4e-411c-ab68-f1a221c338f6', 'slug': 'triangulo'},
    {'id': '328ea125-2a29-4142-bb95-de4e34e92999', 'slug': 'kimura'},
    {'id': '2163c8e6-25d1-4c65-af6b-fcbcb2d2695d', 'slug': 'armbar'},
    {'id': 'dffb7c52-f693-4f7b-b33d-ee8a25b8342b', 'slug': 'barrida_tijera'},
    {'id': '8ea42bb9-b1fa-4e65-ba5a-6a34c1933fdd', 'slug': 'pase_knee_slice'},
    {'id': 'd6e80e7d-88e2-42a2-b490-2cb0bda56f58', 'slug': 'puxada'},
]

def ficha(id_, nombre, usa_sistema, user_id=None):
    return {
        'id': id_, 'user_id': user_id, 'nombre': nombre, 'apodo': None,
        'cinturon': 'blanca', 'grados': 0, 'peso_kg': None,
        'academia': 'Academia BCN', 'usa_sistema': usa_sistema,
        'creado_por': USER_ID, 'created_at': '2026-07-28T00:00:00Z',
    }


TABLAS = {
    # Cuatro fichas. Hacen falta dos con cuenta ADEMAS del que registra, para
    # poder probar una observacion de verdad — un tercero mirando a otros dos —
    # y un contacto sin cuenta para el camino en que no hay a quien espejar.
    'practicantes': [
        ficha(PRACTICANTE_ID, 'Felipe (e2e)', True, USER_ID),
        ficha(PABLO_ID, 'Pablo (e2e)', True),
        ficha(NURIA_ID, 'Nuria (e2e)', True),
        ficha(MARC_ID, 'Marc (contacto)', False),
    ],
    'tecnicas': TECNICAS,
    'sesiones': [], 'rolls': [], 'eventos': [],
}

CAPTURADO = {'sesiones': [], 'rolls': [], 'eventos': [], 'practicantes': [], 'rpc': []}
LOCK = threading.Lock()


def jwt():
    """JWT sin firmar: supabase-js lo decodifica para la expiración, no lo verifica."""
    def b64(d):
        return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip('=')
    return '.'.join([
        b64({'alg': 'HS256', 'typ': 'JWT'}),
        b64({'sub': USER_ID, 'aud': 'authenticated', 'role': 'authenticated',
             'email': 'e2e@bjjtracker.test', 'exp': 4102444800, 'iat': 1785000000}),
        'firma-de-mentira',
    ])


USUARIO = {
    'id': USER_ID, 'aud': 'authenticated', 'role': 'authenticated',
    'email': 'e2e@bjjtracker.test', 'email_confirmed_at': '2026-07-28T00:00:00Z',
    'user_metadata': {'nombre': 'Felipe (e2e)'}, 'app_metadata': {'provider': 'email'},
    'created_at': '2026-07-28T00:00:00Z', 'updated_at': '2026-07-28T00:00:00Z',
    'identities': [], 'phone': '',
}

SESION = {
    'access_token': jwt(), 'token_type': 'bearer', 'expires_in': 3600,
    'expires_at': 4102444800, 'refresh_token': 'refresh-de-mentira', 'user': USUARIO,
}


def filtrar(filas, query):
    """Soporte del subconjunto de PostgREST que usa la app: eq y order."""
    out = list(filas)
    for clave, valores in query.items():
        if clave in ('select', 'order', 'on_conflict', 'columns'):
            continue
        v = valores[0]
        m = re.match(r'^eq\.(.*)$', v)
        if m:
            esperado = m.group(1)
            out = [f for f in out if str(f.get(clave)) == esperado]
    if 'order' in query:
        campo = query['order'][0].split('.')[0]
        out = sorted(out, key=lambda f: str(f.get(campo) or ''))
    return out


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS')
        self.send_header('Access-Control-Expose-Headers', '*')

    def responder(self, code, body):
        cuerpo = json.dumps(body).encode()
        self.send_response(code)
        self.cors()
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def do_OPTIONS(self):
        self.send_response(200); self.cors(); self.end_headers()

    def cuerpo(self):
        n = int(self.headers.get('Content-Length') or 0)
        return json.loads(self.rfile.read(n) or b'null')

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == '/auth/v1/user':
            return self.responder(200, USUARIO)
        m = re.match(r'^/rest/v1/(\w+)$', u.path)
        if m:
            tabla = m.group(1)
            if PGURL and tabla in TABLAS_PUENTE:
                try:
                    filas = consultar(
                        f"select coalesce(json_agg(t), '[]'::json) from {tabla} t")
                    return self.responder(200, filtrar(filas, parse_qs(u.query)))
                except Exception as e:            # noqa: BLE001
                    return self.responder(400, {'message': str(e)})
            with LOCK:
                return self.responder(200, filtrar(TABLAS.get(tabla, []),
                                                   parse_qs(u.query)))
        return self.responder(404, {'message': 'no'})

    def do_POST(self):
        u = urlparse(self.path)

        if u.path == '/auth/v1/token':
            c = self.cuerpo() or {}
            # Sin email es el atajo que usan los scripts de prueba para
            # conseguir una sesion sin pasar por la pantalla.
            if not c.get('email'):
                return self.responder(200, SESION)
            if CUENTAS.get(c.get('email')) != c.get('password'):
                return self.responder(400, {
                    'error': 'invalid_grant',
                    'error_description': 'Invalid login credentials',
                    'msg': 'Invalid login credentials',
                })
            return self.responder(200, SESION)

        if u.path.startswith('/auth/v1/signup'):
            c = self.cuerpo() or {}
            if c.get('email') in CUENTAS:
                return self.responder(422, {
                    'error': 'user_already_exists',
                    'error_description': 'User already registered',
                    'msg': 'User already registered',
                })
            CUENTAS[c.get('email')] = c.get('password')
            # Se imita un proyecto con "confirmar correo" activado: hay usuario
            # pero todavia no hay sesion, asi que la app tiene que pedir el codigo.
            return self.responder(200, {**USUARIO, 'email': c.get('email'), 'session': None})

        if u.path.startswith('/auth/v1/recover'):
            return self.responder(200, {})

        if u.path.startswith('/auth/v1/otp'):
            c = self.cuerpo() or {}
            # create_user=false es "entrar": si el correo no existe, GoTrue no
            # crea nada y contesta que no se permiten altas por esta via.
            if c.get('create_user') is False and c.get('email') not in CUENTAS:
                return self.responder(400, {
                    'error': 'otp_disabled',
                    'error_description': 'Signups not allowed for otp',
                    'msg': 'Signups not allowed for otp',
                })
            return self.responder(200, {})

        # verifyOtp: la entrada por codigo de 6 digitos. Es el camino que no
        # depende de abrir un enlace, asi que conviene poder recorrerlo aqui.
        if u.path.startswith('/auth/v1/verify'):
            cuerpo = self.cuerpo() or {}
            if str(cuerpo.get('token', '')) != CODIGO_BUENO:
                return self.responder(403, {
                    'error': 'invalid_grant',
                    'error_description': 'Token has expired or is invalid',
                    'msg': 'Token has expired or is invalid',
                })
            return self.responder(200, SESION)

        # Las RPC. El modo observador no escribe tablas: llama a
        # registrar_roll_observado(), que en la base real hace sesion + roll +
        # eventos + espejo en una transaccion. Aqui solo se captura la llamada
        # tal cual, para poder replicarla despues contra Postgres de verdad.
        m = re.match(r'^/rest/v1/rpc/(\w+)$', u.path)
        if m:
            fn, args = m.group(1), self.cuerpo()
            with LOCK:
                CAPTURADO.setdefault('rpc', []).append({'funcion': fn, 'args': args})
                self.volcar()

            if PGURL and fn in RPC_PUENTE:
                a = args or {}
                try:
                    if fn == 'analisis':
                        sql = (f"select analisis({literal(a.get('p_autor'))}::uuid, "
                               f"{literal(a.get('p_modalidad'))}, "
                               f"{literal(a.get('p_desde'))}::date)")
                    else:
                        sql = (
                            "select coalesce(json_agg(t), '[]'::json) from "
                            f"analisis_rolls_celda({literal(a.get('p_autor'))}::uuid, "
                            f"{literal(a.get('p_actor'))}::bjj_actor, "
                            f"{literal(a.get('p_posicion'))}::bjj_posicion, "
                            f"{literal(a.get('p_objetivo'))}::bjj_objetivo, "
                            f"{literal(a.get('p_modalidad'))}, "
                            f"{literal(a.get('p_desde'))}::date) t")
                    return self.responder(200, consultar(sql))
                except Exception as e:            # noqa: BLE001
                    return self.responder(400, {'message': str(e)})
            if fn != 'registrar_roll_observado':
                return self.responder(404, {'message': f'funcion {fn} desconocida'})
            # Se imita lo justo: sin cuenta no hay espejo, igual que espejar_roll().
            b = next((p for p in TABLAS['practicantes']
                      if p['id'] == (args or {}).get('p_practicante_b')), None)
            return self.responder(200, {
                'roll_a': str(uuid.uuid4()),
                'roll_b': str(uuid.uuid4()) if b and b['usa_sistema'] else None,
                'creado': True,
            })

        m = re.match(r'^/rest/v1/(\w+)$', u.path)
        if m:
            tabla = m.group(1)
            filas = self.cuerpo()
            filas = filas if isinstance(filas, list) else [filas]
            with LOCK:
                destino = TABLAS.setdefault(tabla, [])
                for f in filas:
                    if not f.get('id'):
                        f['id'] = str(uuid.uuid4())   # como hace Postgres con el default
                    destino[:] = [x for x in destino if x.get('id') != f.get('id')]
                    destino.append(f)
                    CAPTURADO.setdefault(tabla, []).append(f)
                self.volcar()
            return self.responder(201, filas)
        return self.responder(404, {'message': 'no'})

    def volcar(self):
        with open(SALIDA, 'w') as f:
            json.dump(CAPTURADO, f, indent=1)

    def do_PUT(self):
        """updateUser: aqui solo se usa para poner una contraseña nueva."""
        u = urlparse(self.path)
        if u.path.startswith('/auth/v1/user'):
            c = self.cuerpo() or {}
            if c.get('password'):
                CUENTAS[USUARIO['email']] = c['password']
            return self.responder(200, USUARIO)
        return self.responder(404, {'message': 'no'})

    def do_PATCH(self):
        u = urlparse(self.path)
        m = re.match(r'^/rest/v1/(\w+)$', u.path)
        if m:
            cambios = self.cuerpo()
            with LOCK:
                for f in filtrar(TABLAS.get(m.group(1), []), parse_qs(u.query)):
                    f.update(cambios)
            return self.responder(200, [])
        return self.responder(404, {'message': 'no'})

    def do_DELETE(self):
        u = urlparse(self.path)
        m = re.match(r'^/rest/v1/(\w+)$', u.path)
        if m:
            with LOCK:
                fuera = {f['id'] for f in filtrar(TABLAS[m.group(1)], parse_qs(u.query))}
                TABLAS[m.group(1)][:] = [f for f in TABLAS[m.group(1)] if f['id'] not in fuera]
            return self.responder(200, [])
        return self.responder(404, {'message': 'no'})


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 54321), H).serve_forever()
