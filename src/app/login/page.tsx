'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';

/**
 * Entrar, crear cuenta y recuperar la contraseña.
 *
 * ENTRAR Y CREAR CUENTA SON DOS COSAS DISTINTAS, A PROPÓSITO
 *
 * Antes había una sola pantalla que llamaba a `signInWithOtp` con
 * `shouldCreateUser` por defecto, o sea `true`. Con eso, **un correo mal
 * tecleado no daba error: creaba una cuenta nueva**, y con ella una ficha de
 * practicante nueva por el trigger `bjj_08`. El historial se partía en dos sin
 * que nadie se enterara — justo el problema de fichas duplicadas que hay que
 * evitar. Al entrar se pasa `shouldCreateUser: false`, así que un correo que no
 * existe dice que no existe.
 *
 * DOS VÍAS PARA ENTRAR
 *
 * Contraseña, que es lo rápido, y código del correo por si no te acuerdas.
 * El código sigue existiendo porque no depende de nada guardado en el navegador
 * ni de abrir un enlace en el sitio correcto.
 */

type Modo = 'entrar' | 'alta';
type Paso = 'formulario' | 'codigo' | 'reset';

const MINIMO = 8;

/**
 * Largo del código del correo.
 *
 * No es 6. Supabase deja configurarlo entre 6 y 10 en Authentication →
 * Sign In / Providers → Email, y este proyecto lo tiene en 8. Dar por hecho
 * que eran 6 hacía que el campo truncase el código y que GoTrue lo rechazara
 * con "ese código no vale", que es un mensaje que manda a buscar al sitio
 * equivocado. Se aceptan los dos extremos y ya rechaza el servidor si no toca.
 */
const LARGO_MINIMO = 6;
const LARGO_MAXIMO = 10;

/** Los mensajes de GoTrue llegan en inglés y de espaldas al usuario. */
function traducir(mensaje: string): string {
  const m = mensaje.toLowerCase();
  if (m.includes('invalid login credentials')) return 'Correo o contraseña incorrectos.';
  if (m.includes('signups not allowed') || m.includes('user not found')) {
    return 'No hay ninguna cuenta con ese correo. ¿Querías crearla?';
  }
  if (m.includes('already registered') || m.includes('already been registered')) {
    return 'Ya hay una cuenta con ese correo. Entra en vez de crearla.';
  }
  if (m.includes('email not confirmed')) {
    return 'Falta confirmar el correo. Pide el código y termina el alta.';
  }
  if (m.includes('token has expired') || m.includes('invalid')) {
    return 'Ese código no vale o ha caducado. Pide otro.';
  }
  if (m.includes('rate limit') || m.includes('too many')) {
    return 'Demasiados intentos seguidos. Espera un minuto.';
  }
  return mensaje;
}

export default function Login() {
  const router = useRouter();
  const [modo, setModo] = useState<Modo>('entrar');
  const [paso, setPaso] = useState<Paso>('formulario');
  const [email, setEmail] = useState('');
  const [nombre, setNombre] = useState('');
  const [clave, setClave] = useState('');
  const [codigo, setCodigo] = useState('');
  /** Qué está esperando el código: confirmar un alta, entrar, o recuperar. */
  const [tipoCodigo, setTipoCodigo] = useState<'email' | 'signup' | 'recovery'>('email');
  const [ocupado, setOcupado] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const campoCodigo = useRef<HTMLInputElement>(null);

  useEffect(() => {
    void supabase().auth.getUser().then(({ data }) => {
      if (data.user) router.replace('/entreno');
    });
  }, [router]);

  function fallo(e: { message: string } | null) {
    setError(e ? traducir(e.message) : null);
    setOcupado(false);
  }

  function pedirCodigo(tipo: 'email' | 'signup' | 'recovery', texto: string) {
    setTipoCodigo(tipo);
    setPaso('codigo');
    setAviso(texto);
    setOcupado(false);
    setTimeout(() => campoCodigo.current?.focus(), 50);
  }

  // ---------------------------------------------------------------- acciones

  async function entrarConClave(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setError(null);
    const { error } = await supabase().auth.signInWithPassword({
      email: email.trim(), password: clave,
    });
    if (error) return fallo(error);
    router.replace('/entreno');
  }

  async function entrarConCodigo() {
    setOcupado(true); setError(null);
    // shouldCreateUser: false — entrar es entrar. Un correo que no existe tiene
    // que decir que no existe, no crear una cuenta a la callada.
    const { error } = await supabase().auth.signInWithOtp({
      email: email.trim(), options: { shouldCreateUser: false },
    });
    if (error) return fallo(error);
    pedirCodigo('email', `Le hemos mandado un código a ${email.trim()}.`);
  }

  async function crearCuenta(e: React.FormEvent) {
    e.preventDefault();
    if (clave.length < MINIMO) {
      setError(`La contraseña necesita al menos ${MINIMO} caracteres.`);
      return;
    }
    setOcupado(true); setError(null);
    // El nombre viaja como metadata: el trigger de Postgres lo usa para crear
    // la ficha de practicante. Sin esto, el nombre se deduce del email.
    const { data, error } = await supabase().auth.signUp({
      email: email.trim(),
      password: clave,
      options: {
        data: { nombre: nombre.trim() || undefined },
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });
    if (error) return fallo(error);
    // Si el proyecto no exige confirmar el correo, ya hay sesión y se entra.
    if (data.session) { router.replace('/entreno'); return; }
    pedirCodigo('signup', `Cuenta creada. Confirma ${email.trim()} con el código que te llega.`);
  }

  async function pedirReset() {
    if (!email.trim()) { setError('Escribe tu correo primero.'); return; }
    setOcupado(true); setError(null);
    const { error } = await supabase().auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/auth/reset`,
    });
    if (error) return fallo(error);
    setPaso('reset');
    setOcupado(false);
  }

  async function verificar(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setError(null);
    const { data, error } = await supabase().auth.verifyOtp({
      email: email.trim(), token: codigo.trim(), type: tipoCodigo,
    });
    if (error || !data.session) {
      return fallo(error ?? { message: 'Ese código no vale. Comprueba que está entero.' });
    }
    // El código de recuperación abre sesión, pero para cambiar la contraseña.
    router.replace(tipoCodigo === 'recovery' ? '/auth/reset' : '/entreno');
  }

  // ---------------------------------------------------------------- pantallas

  const cabecera = (
    <div className="top"><div><div className="t1">BJJ Tracker</div>
      <div className="t2">diario de rolls</div></div></div>
  );

  if (paso === 'codigo') {
    return (
      <div className="phone">
        {cabecera}
        <main>
          <form onSubmit={verificar}>
            <h1>Mira tu correo</h1>
            <p className="hint">{aviso}</p>
            <label htmlFor="codigo">Código</label>
            {/* La longitud del código NO es 6 fija: Supabase la deja configurar
                entre 6 y 10 (Authentication → Sign In/Providers → Email), y
                este proyecto la tiene en 8. Con maxLength={6} el campo cortaba
                el código por la mitad y GoTrue lo rechazaba con razón. */}
            <input id="codigo" ref={campoCodigo} data-testid="codigo"
              value={codigo} inputMode="numeric" autoComplete="one-time-code"
              maxLength={LARGO_MAXIMO} placeholder="el que te llega al correo"
              style={{ fontSize: 24, letterSpacing: '.3em', textAlign: 'center' }}
              onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ''))} />
            {error && <p className="err" data-testid="error">{error}</p>}
            <div style={{ marginTop: 20 }}>
              <button className="primary" type="submit" data-testid="verificar"
                disabled={ocupado || codigo.length < LARGO_MINIMO}>
                {ocupado ? 'Entrando…' : 'Entrar'}
              </button>
            </div>
            <p className="hint">
              El mismo correo lleva un enlace. Si lo abres en este navegador entras
              directo; el código funciona lo abras donde lo abras.
            </p>
            <div style={{ marginTop: 14 }}>
              <button className="ghost" type="button" data-testid="volver"
                onClick={() => { setPaso('formulario'); setCodigo(''); setError(null); }}>
                ← Volver
              </button>
            </div>
          </form>
        </main>
      </div>
    );
  }

  if (paso === 'reset') {
    return (
      <div className="phone">
        {cabecera}
        <main>
          <h1>Revisa tu correo</h1>
          <p className="hint" data-testid="reset-enviado">
            Le hemos mandado a <b>{email}</b> un enlace para poner una contraseña
            nueva. Ábrelo y elige la que quieras.
          </p>
          <p className="hint">
            Si lo abres en otro dispositivo y no te deja, usa el código del mismo
            correo aquí abajo.
          </p>
          <div style={{ marginTop: 16, display: 'flex', gap: 9 }}>
            <button className="primary" type="button" data-testid="reset-codigo"
              onClick={() => pedirCodigo('recovery', `Teclea el código que le llegó a ${email}.`)}>
              Tengo un código
            </button>
            <button className="ghost" type="button"
              onClick={() => { setPaso('formulario'); setError(null); }}>← Volver</button>
          </div>
        </main>
      </div>
    );
  }

  return (
    <div className="phone">
      {cabecera}
      <main>
        <div className="chips" style={{ marginBottom: 4 }}>
          {([['entrar', 'Entrar'], ['alta', 'Crear cuenta']] as const).map(([m, t]) => (
            <button key={m} className="chip" type="button" data-testid={`modo-${m}`}
              style={modo === m ? { borderColor: 'var(--marca)', color: 'var(--marca-texto)' } : undefined}
              onClick={() => { setModo(m); setError(null); setClave(''); }}>{t}</button>
          ))}
        </div>

        <form onSubmit={modo === 'entrar' ? entrarConClave : crearCuenta}>
          <h1>{modo === 'entrar' ? 'Entrar' : 'Crear cuenta'}</h1>

          {modo === 'alta' && (
            <>
              <label htmlFor="nombre">Cómo te llamas</label>
              <input id="nombre" value={nombre} data-testid="nombre"
                onChange={(e) => setNombre(e.target.value)}
                placeholder="Felipe" autoComplete="given-name" />
            </>
          )}

          <label htmlFor="email">Tu email</label>
          <input id="email" type="email" required value={email} inputMode="email"
            data-testid="email" autoComplete="email" placeholder="tu@email.com"
            onChange={(e) => setEmail(e.target.value)} />

          <label htmlFor="clave">Contraseña</label>
          <input id="clave" type="password" required value={clave} data-testid="clave"
            autoComplete={modo === 'entrar' ? 'current-password' : 'new-password'}
            placeholder={modo === 'alta' ? `mínimo ${MINIMO} caracteres` : ''}
            onChange={(e) => setClave(e.target.value)} />

          {error && <p className="err" data-testid="error">{error}</p>}

          <div style={{ marginTop: 20 }}>
            <button className="primary" type="submit" data-testid="enviar" disabled={ocupado}>
              {ocupado ? 'Un momento…' : modo === 'entrar' ? 'Entrar' : 'Crear cuenta'}
            </button>
          </div>
        </form>

        {modo === 'entrar' ? (
          <>
            <h2 className="sec">¿Sin contraseña a mano?</h2>
            <div style={{ display: 'flex', gap: 9, flexWrap: 'wrap' }}>
              <button className="ghost" type="button" data-testid="pedir-codigo"
                disabled={ocupado || !email.trim()} onClick={entrarConCodigo}>
                Mandarme un código
              </button>
              <button className="ghost" type="button" data-testid="olvidada"
                disabled={ocupado || !email.trim()} onClick={pedirReset}>
                He olvidado la contraseña
              </button>
            </div>
            <p className="hint">
              Las dos necesitan tu correo escrito arriba. El código entra sin cambiar
              la contraseña; el otro botón te deja poner una nueva.
            </p>
          </>
        ) : (
          <p className="hint">
            Te mandaremos un código para confirmar que el correo es tuyo. Usa el correo
            de verdad: la ficha de practicante se crea con él, y tener dos cuentas parte
            tu historial en dos.
          </p>
        )}
      </main>
    </div>
  );
}
