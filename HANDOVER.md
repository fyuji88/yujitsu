# Traspaso — dónde estamos y qué falta

**29 julio 2026.** El trabajo ya está en VS Code con terminal. El login funciona
de punta a punta y el modo observador está desplegado.

---

## 1. Las tres cuentas

| Servicio | Qué hay | Plan |
|---|---|---|
| **Supabase** | proyecto `idzlxkxeadrcolcnmoeo`, org `yujitsu`, eu-west-1 (Irlanda) | gratuito |
| **Vercel** | proyecto `yujitsu` → `yujitsu-eight.vercel.app` | Hobby |
| **GitHub** | `fyuji88/yujitsu`, privado, rama `main` | gratuito |

Variables de entorno (las dos son públicas por diseño; lo que protege los datos
es la RLS, no estas claves):

```
NEXT_PUBLIC_SUPABASE_URL       https://idzlxkxeadrcolcnmoeo.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY  sb_publishable_nPlVwNB4No1c1iDtjrwt1w_BjagU7GF
```

### Avisos del plan gratuito

**El proyecto de Supabase se pausa tras una semana sin actividad.** Si volvéis de
vacaciones y la app no responde, hay que despausarlo desde el panel. **No hay
backups** en el plan gratuito: el momento de pasar a Pro (25 $/mes) es cuando
llevéis un mes de datos reales dentro, no antes.

**El SMTP de Supabase va muy limitado de envíos por hora.** Para dos personas
sobra; para invitar a media academia hay que enchufar un SMTP propio (Resend,
Postmark), que son cinco minutos de configuración y cero código.

---

## 2. Qué está hecho

**Base de datos**: 8 tablas, 9 vistas, 12 enums, 11 políticas de RLS, 5
funciones. 9 migraciones aplicadas, con copia en `db/`. Diccionario cargado: 24
posiciones (13 marcadas `core_v1`) y 63 técnicas con alias.

**App (Fase 1)**: entrada por magic link, pestaña de practicantes con alta y
edición, y la pantalla de logging con la máquina de estados contextual. Escritura
local-first: todo entra en IndexedDB y sale a Supabase cuando hay red.

**Modo observador**: el botón 👁 Observar del entreno. Un tercero elige a dos
practicantes y registra el roll en vivo, con cronómetro y con los nombres de los
dos en vez de "yo/él". Al terminar se guardan **dos rolls** unidos por el mismo
`roll_grupo_id`: lo que para uno es ataque, para el otro es defensa. Si el
segundo no tiene cuenta, se guarda solo el lado del primero.

**Marcador estilo IBJJF**: observando, cabecera fija con el tanteo de los dos y
cronómetro con pausa; en modo propio, en el resumen con el desglose de dónde
salió cada punto. Los puntos **se derivan de los eventos, no se guardan**.

**Probado**: el login, entrando de verdad desde el móvil. El logging propio, con
recorrido en navegador y los payloads replicados contra la base real. El modo
observador, con 16 comprobaciones SQL contra un Postgres local (idempotencia,
espejado celda a celda, RLS con `set local role authenticated`, borrado por el
dueño) más 21 recorriéndolo en un navegador de verdad. Y el marcador, con los
mismos 6 casos pasados por TypeScript y por SQL, más 27 comprobaciones en
navegador a 390px — incluido dejar la pestaña un minuto en segundo plano para
comprobar que el cronómetro no se queda parado.

---

## 3. Qué falta ahora mismo — por orden

**a) Las tres plantillas de correo.** Es lo único que queda para que la entrada
funcione entera, y lo tiene que hacer Felipe desde **Authentication → Emails →
pestaña Templates** (en el panel nuevo ya no están en el menú lateral; si no ves
la pestaña es que la ventana es estrecha).

| Plantilla | Para qué | Qué añadir |
|---|---|---|
| **Magic Link** | entrar con código | `{{ .Token }}` |
| **Confirm signup** | terminar un alta | `{{ .Token }}` |
| **Reset Password** | contraseña nueva | `{{ .Token }}` y `{{ .ConfirmationURL }}` |

**b) Activar la protección de contraseñas filtradas.** Ahora que hay
contraseñas, el aviso del linter de Supabase pasa a tener sentido: comprueba
contra HaveIBeenPwned que la contraseña elegida no esté en una filtración
conocida. Está en los ajustes de contraseñas de Authentication.

**b) ~~URL Configuration de Supabase~~ — HECHO.** Site URL y redirect apuntando
a `https://yujitsu-eight.vercel.app`.

**c) ~~Que entre Pablo~~ — HECHO.** Ya tiene ficha con cuenta (`usa_sistema =
true`), creada sola por el trigger `bjj_08`. A partir de ahora un roll observado
entre Felipe y Pablo sí se espeja a los dos.

**d) ~~Decidir `transicion`~~ — HECHO** y aplicado (`bjj_10`). Con él llegó el
marcador estilo IBJJF.

**e) Decidir `de_rodillas`.** Falta en `bjj_posicion`, y empezar de rodillas no
es `de_pie` ni es `clinch`. En un gimnasio es de las salidas más frecuentes, y
ahora que se elige la posición de salida se nota que no está. Es vocabulario, o
sea que lo cerráis vosotros dos.

**f) El tiempo de dominio / posesión.** El dato ya se captura: cada evento lleva
`segundo_roll`, el sello del cronómetro. Falta decidir cómo se cierra el último
tramo y qué cuenta como disputa.

**g) Lo que queda de Fase 2**: heatmaps y head-to-head en la app (los datos y las
vistas ya están, falta la pantalla) y los retos. Diseñado en `docs/`.

**h) Limpieza pendiente en producción**: hay una sesión vacía sin rolls y los
contactos de prueba ("Test Account", "Goku", "Vegeta"). Nada roto, pero conviene
barrerlos antes de que empiecen los datos de verdad.

---

## 4. Decisiones tomadas, y por qué

Las que costaría más redescubrir:

**Eventos, no resultados.** Explicado en `CLAUDE.md`. Es la razón de que features
como los puntos IBJJF salgan casi gratis.

**`sin_sumision`, no "tablas".** Un roll sin sumisión no es un empate: el saldo
posicional lo cuentan los eventos, no ese campo. Se renombró a mitad de camino
por eso.

**Local-first desde la v1**, no como mejora posterior. Retrofitear la cola
significa reescribir la capa de datos entera, porque cambia cómo escribe cada
pantalla. Y en un gimnasio no hay cobertura fiable.

**PWA, no app nativa.** Una URL, instalable desde el navegador, sin store ni
99 €/año. Se pasa a nativa solo si algún día queréis Apple Watch o push en
segundo plano.

**El observador gana en la deduplicación.** Si el coach registra un roll y además
el practicante lo registra por su cuenta, vale la versión del coach: ve cosas que
tú no ves — tu propia espalda, y las sumisiones que intentaste y fallaste. Está
en `v_rolls_unicos`; cambiarlo es una línea del `order by`.

---

## 5. Los bugs y bloqueos que encontramos probando

Se documentan porque todos aparecieron **ejecutando**, no leyendo:

1. **Borrar un practicante fallaba** con `violates foreign key constraint
   rolls_sesion_id_fkey`, por el choque entre el `CASCADE` de sesiones y el `SET
   NULL` de `rolls.oponente_id`. Resuelto difiriendo las FK.

2. **No se podía dar de alta a un compañero.** La política de RLS solo dejaba
   escribir la fila cuyo `user_id` eras tú. La pestaña de practicantes era
   imposible de construir hasta arreglarlo (`bjj_07`).

3. **PKCE rompía el magic link** al pedirlo en un dispositivo y abrirlo en otro.
   El primer arreglo —poner `flowType: 'implicit'`— **fue una operación nula**:
   `@supabase/ssr` fija `flowType: "pkce"` después del spread de las opciones,
   así que se ignoraba. Parecía arreglado y no lo estaba, y fallaba de forma
   intermitente: solo cuando el correo se abría en otro navegador. Resuelto de
   verdad quitando `@supabase/ssr` y usando `createClient`, y sobre todo
   añadiendo la entrada por código de 6 dígitos, que no depende del enlace.

4. **El modo observador no se podía construir solo con frontend.** La RLS impide
   que un tercero escriba datos de otros: autenticado como el coach, crear la
   sesión de otro practicante devuelve `42501: new row violates row-level
   security policy for table "sesiones"`. Hizo falta `registrar_roll_observado()`
   (`bjj_09`), SECURITY DEFINER, como puerta única de escritura.

5. **El primer commit del arreglo del login nunca llegó a `main`.** El código
   estaba bien en local, pero Vercel seguía sirviendo la versión con PKCE. Las
   subidas por el navegador de GitHub habían dejado fuera carpetas enteras
   (`db/`, `docs/`) y el arreglo se quedó sin commitear. Moraleja barata:
   comprobar `git status` antes de dar por desplegado algo.

---

## 6. Lo que hay en el repositorio

```
src/            la app (ver CLAUDE.md para el mapa)
db/             las 8 migraciones SQL, iguales que lo desplegado
docs/           decisiones de producto, backlog, y el prototipo clicable
stub-supabase.py   imitación local de Supabase para pruebas sin red
CLAUDE.md       contexto para Claude Code — se lee solo
HANDOVER.md     este fichero
SETUP-VSCODE.md cómo montar el entorno
```

`docs/BJJ-Log-Prototipo.html` es el prototipo original del flujo de logging, con
el modo observador incluido. Se abre en el navegador y sirve como referencia
viva de cómo debe sentirse la app — la Fase 2 tiene que llegar a eso.
