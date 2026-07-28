"""
Stub local de Supabase para pruebas end-to-end.

Este contenedor no tiene salida a supabase.co, así que la app se prueba contra
esta imitación de GoTrue + PostgREST. Los datos semilla (ids de tecnicas, ficha
del practicante) son los REALES del proyecto, y todo lo que la app escribe se
guarda en /tmp/capturado.json para luego replicarlo contra la base de verdad.
Así se prueba la app entera y se comprueba que sus payloads los acepta el
esquema real, sin poder llegar a la red.
"""
import base64, json, re, threading, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

USER_ID = '55555555-5555-5555-5555-555555555555'
PRACTICANTE_ID = '66666666-6666-6666-6666-666666666666'

TECNICAS = [
    {'id': '9f319790-39b0-4274-a946-80a580850791', 'slug': 'mata_leao'},
    {'id': '2d869a77-1b4e-411c-ab68-f1a221c338f6', 'slug': 'triangulo'},
    {'id': '328ea125-2a29-4142-bb95-de4e34e92999', 'slug': 'kimura'},
    {'id': '2163c8e6-25d1-4c65-af6b-fcbcb2d2695d', 'slug': 'armbar'},
    {'id': 'dffb7c52-f693-4f7b-b33d-ee8a25b8342b', 'slug': 'barrida_tijera'},
    {'id': '8ea42bb9-b1fa-4e65-ba5a-6a34c1933fdd', 'slug': 'pase_knee_slice'},
    {'id': 'd6e80e7d-88e2-42a2-b490-2cb0bda56f58', 'slug': 'puxada'},
]

TABLAS = {
    'practicantes': [{
        'id': PRACTICANTE_ID, 'user_id': USER_ID, 'nombre': 'Felipe (e2e)',
        'apodo': None, 'cinturon': 'blanca', 'grados': 0, 'peso_kg': None,
        'academia': 'Academia BCN', 'usa_sistema': True, 'creado_por': USER_ID,
        'created_at': '2026-07-28T00:00:00Z',
    }],
    'tecnicas': TECNICAS,
    'sesiones': [], 'rolls': [], 'eventos': [],
}

CAPTURADO = {'sesiones': [], 'rolls': [], 'eventos': [], 'practicantes': []}
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
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS')
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
            with LOCK:
                return self.responder(200, filtrar(TABLAS.get(m.group(1), []),
                                                   parse_qs(u.query)))
        return self.responder(404, {'message': 'no'})

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == '/auth/v1/token':
            return self.responder(200, SESION)
        if u.path.startswith('/auth/v1/otp'):
            return self.responder(200, {})
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
                json.dump(CAPTURADO, open('/tmp/capturado.json', 'w'), indent=1)
            return self.responder(201, filas)
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
