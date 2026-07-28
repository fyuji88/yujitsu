# Montar el entorno en VS Code

Pensado para Windows; entre paréntesis va lo de Mac cuando cambia. La idea es
tenerlo todo funcionando en local para poder ejecutar, probar y desplegar sin
copiar y pegar ficheros por el navegador.

---

## 1. Instalar tres cosas

**Node.js** — desde [nodejs.org](https://nodejs.org), la versión **LTS**. Es lo
que hace falta para que existan `npm` y `npx`.

**Git** — desde [git-scm.com](https://git-scm.com). En Windows instala también
Git Bash; acepta las opciones por defecto.

**VS Code** — desde [code.visualstudio.com](https://code.visualstudio.com).

Comprueba que funcionan: abre VS Code, y en el menú **Terminal → New Terminal**
escribe:

```bash
node -v
npm -v
git --version
```

Si los tres responden con un número, vas bien. Si `node` no responde, cierra y
vuelve a abrir VS Code (después de instalar Node hay que reiniciarlo para que
coja el PATH).

---

## 2. Traerte el repositorio

En la terminal de VS Code, colócate donde quieras guardar el proyecto y clona:

```bash
cd Documents
git clone https://github.com/fyuji88/yujitsu.git
cd yujitsu
```

La primera vez te pedirá entrar en GitHub; se abre el navegador y confirmas.

Luego **File → Open Folder** y elige la carpeta `yujitsu`, para que VS Code
trabaje dentro del proyecto.

---

## 3. Poner las claves

Crea un fichero llamado `.env.local` en la raíz del proyecto con esto:

```
NEXT_PUBLIC_SUPABASE_URL=https://idzlxkxeadrcolcnmoeo.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_nPlVwNB4No1c1iDtjrwt1w_BjagU7GF
```

El `.gitignore` ya impide que ese fichero se suba. **Nunca lo subas al
repositorio**, aunque estas dos claves concretas sean públicas por diseño: es la
costumbre lo que te protege el día que haya una clave que sí sea secreta.

---

## 4. Arrancar

```bash
npm install
npm run dev
```

Abre `http://localhost:3000`. Para parar el servidor, `Ctrl+C` en la terminal.

Antes de dar por bueno cualquier cambio:

```bash
npm run build
```

Eso compila y hace el typecheck en modo estricto. Si pasa, Vercel también va a
pasar.

---

## 5. Conectar las cuentas desde la terminal

Esto es lo que te permite que un agente con terminal haga el trabajo entero sin
que tú vayas al navegador.

**Vercel:**

```bash
npm i -g vercel
vercel login
vercel link          # enlaza esta carpeta con el proyecto yujitsu que ya existe
```

Con eso ya puedes ver los logs de un despliegue fallido sin salir de VS Code:

```bash
vercel logs
vercel --prod        # desplegar a mano, sin pasar por git
```

**Supabase:**

```bash
npm i -g supabase
supabase login
supabase link --project-ref idzlxkxeadrcolcnmoeo
```

Y a partir de ahí:

```bash
supabase gen types typescript --linked > src/lib/database.types.ts
supabase migration list
```

**GitHub** ya quedó configurado al clonar. El ciclo normal es:

```bash
git add -A
git commit -m "lo que sea"
git push
```

Y Vercel despliega solo al recibir el push.

---

## 6. Claude Code

Instálalo con:

```bash
npm i -g @anthropic-ai/claude-code
```

Y luego, dentro de la carpeta del proyecto:

```bash
claude
```

También hay extensión de VS Code, búscala como **Claude Code** en el panel de
extensiones.

Lo primero que hace al arrancar es leer el `CLAUDE.md` de la raíz, que ya tiene
el contexto del proyecto: el modelo de datos, los invariantes que no hay que
romper y los tres bugs que nos mordieron. No hace falta que le expliques nada de
eso.

Para empezar, algo así:

> Lee HANDOVER.md. Quiero terminar el punto 3.a: confirmar que el login por
> magic link funciona de punta a punta contra el Supabase real.

---

## 7. Lo primero que conviene hacer

**Comprobar que el arreglo del login está en `main`.** Abre
`src/lib/supabase.ts` y busca `flowType: 'implicit'`. Si no está, el repositorio
se quedó con la versión vieja y hay que subir la corregida.

**Comprobar que el repositorio está completo.** Al subir por el navegador se
quedaron fuera carpetas la primera vez. Debe haber `src/`, `public/`, `db/`,
`docs/`, y en `src/app/` las cuatro pantallas: `login`, `auth/callback`,
`practicantes` y `entreno`.

Con `npm run build` pasando en local, ya sabes que el repositorio está sano.
