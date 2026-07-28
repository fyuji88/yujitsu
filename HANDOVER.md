# Traspaso — dónde estamos y qué falta

**28 julio 2026.** Cierre de la fase construida en Cowork; a partir de aquí el
trabajo sigue en VS Code con terminal.

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

**Base de datos**: 8 tablas, 9 vistas, 12 enums, 11 políticas de RLS, 4
funciones. 8 migraciones aplicadas, con copia en `db/`. Diccionario cargado: 24
posiciones (13 marcadas `core_v1`) y 63 técnicas con alias.

**App (Fase 1)**: entrada por magic link, pestaña de practicantes con alta y
edición, y la pantalla de logging con la máquina de estados contextual. Escritura
local-first: todo entra en IndexedDB y sale a Supabase cuando hay red.

**Probado**: recorrido completo en navegador contra un stub local (entrar, dar de
alta un compañero, registrar un roll de tres eventos, ver la cola vaciarse), y
los payloads que genera la app replicados contra la base real, que los aceptó y
los reflejó en `v_heatmap_ofensivo`.

---

## 3. Qué falta ahora mismo — por orden

**a) Confirmar que el login funciona de punta a punta.** Es lo único que no se ha
podido probar contra el Supabase real, porque los magic links llegan al correo de
Felipe. Estado: se cambió el flujo de PKCE a implícito para arreglar el error
`PKCE code verifier not found in storage`; **falta verificar que el commit con ese
cambio esté en `main`** y que el login entre de verdad.

Comprobar en `src/lib/supabase.ts` que dice `flowType: 'implicit'`.

**b) En Supabase → Authentication → URL Configuration**, que estén:

```
Site URL:       https://yujitsu-eight.vercel.app
Redirect URLs:  https://yujitsu-eight.vercel.app/**
```

**c) Que entren Felipe y Pablo** con sus emails. La ficha de practicante se crea
sola con un trigger (`bjj_08`), con `usa_sistema = true`. A Pablo **no hay que
darlo de alta a mano**: si lo creas como contacto y luego él se registra, acabáis
con dos fichas suyas y el head-to-head partido en dos.

**d) Decidir `transicion`.** Es un `ALTER TYPE bjj_tipo_evento ADD VALUE
'transicion'`, no rompe nada, y desbloquea la puntuación estilo IBJJF. La
decisión es de vocabulario, así que la toman Felipe y Pablo.

**e) Fase 2**: modo observador en la app, heatmaps y head-to-head, retos. Todo
diseñado ya en `docs/`.

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

## 5. Los tres bugs que encontramos probando

Se documentan porque los tres aparecieron **ejecutando**, no leyendo:

1. **Borrar un practicante fallaba** con `violates foreign key constraint
   rolls_sesion_id_fkey`, por el choque entre el `CASCADE` de sesiones y el `SET
   NULL` de `rolls.oponente_id`. Resuelto difiriendo las FK.

2. **No se podía dar de alta a un compañero.** La política de RLS solo dejaba
   escribir la fila cuyo `user_id` eras tú. La pestaña de practicantes era
   imposible de construir hasta arreglarlo (`bjj_07`).

3. **PKCE rompía el magic link** al pedirlo en un dispositivo y abrirlo en otro.

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
