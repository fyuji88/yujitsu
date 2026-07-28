# BJJ Tracker — Documento de proyecto

**Bloque 0 · v1.0 · 27 julio 2026**
Equipo: Felipe · Pablo
Stack decidido: Supabase (Postgres) + Next.js/TypeScript · camino híbrido

---

## 1. Qué estamos construyendo

Un sistema para registrar rolls de BJJ de forma minimalista, acumular datos durante meses y
convertirlos en una lectura visual de nuestro juego: dónde atacamos, dónde nos pillan, qué
guardias nos funcionan y cómo vamos contra cada compañero.

Tres productos en uno:

**Journal** — logging rápido después de cada entrenamiento. Si tarda más de 2 minutos, se
abandona. Esta es la única métrica de éxito real del proyecto.

**Análisis de juego** — heatmaps de posición × articulación (ofensivo y defensivo),
rendimiento por guardia, evolución temporal, fuertes y débiles.

**Gamificación** — head-to-head contra cada oponente, retos semanales auto-validables,
comparativa entre los que usan el sistema.

---

## 2. La decisión de arquitectura que sostiene todo

**Modelamos eventos, no resultados.**

En vez de guardar campos fijos tipo "gané / perdí", cada acción del roll se guarda como una
fila en `eventos` con cinco datos:

> **quién** la hizo (`actor`) · **qué** hizo (`tipo`) · **desde dónde** (`posicion` + `rol`) ·
> **a qué articulación** (`objetivo`) · **con qué técnica** (`tecnica_id`)

De ese único modelo salen gratis el heatmap ofensivo, el defensivo, el análisis de guardias,
el head-to-head y la validación automática de retos. Ninguna de esas features necesita una
tabla nueva: todas son filtros y agregaciones sobre `eventos`.

Consecuencia práctica: `eventos` es el **contrato** entre vosotros dos. Si esa tabla está bien
definida, Felipe y Pablo pueden trabajar en paralelo sin pisarse.

### El truco de `posicion` + `rol`

La posición se guarda de forma **física** (montada, guardia cerrada, cien kilos...) y aparte se
guarda el **rol del actor** (arriba / abajo / neutral). Así evitamos duplicar el vocabulario:

| posición | rol | significado |
|---|---|---|
| `guardia_cerrada` | `abajo` | estabas jugando la guardia |
| `guardia_cerrada` | `arriba` | estabas dentro intentando pasar |
| `montada` | `arriba` | tú montado |
| `montada` | `abajo` | te montaron |

Un solo enum de 24 valores en vez de 40+, y el heatmap se lee natural en ambas direcciones.

---

## 3. Los tres niveles del journal

| Nivel | Frecuencia | Para qué sirve |
|---|---|---|
| **Sesión** | 1 por entrenamiento | contexto: energía, ánimo, temática, gi/nogi, molestias |
| **Roll** | 1 por asalto | oponente, duración, posición de inicio, resultado, autovaloración |
| **Evento** | 0..n por roll | la acción concreta — de aquí sale todo el análisis |

Un roll sin eventos sigue siendo válido (cuenta para el H2H y la evolución). Eso quita presión:
los días que no tengas ganas de detallar, logueas solo el nivel roll.

**Data points por nivel** — están todos en el esquema; los principales:

- *Sesión*: fecha, academia, modalidad, tipo (técnica/drilling/sparring/open mat/competición/privada), duración, temática, energía 1-5, ánimo 1-5, molestias, notas.
- *Roll*: oponente, orden, modalidad, duración, posición de inicio + rol, resultado, autovaloración 1-5, intensidad 1-5, notas.
- *Evento*: actor, tipo, posición, rol, objetivo, técnica, completado (sí/no), minuto, notas.

`completado = false` es lo que convierte un intento fallado en dato. Sin eso no se puede
calcular tasa de éxito por técnica, que a medio plazo es la métrica más útil de todas.

---

## 4. El vocabulario (el entregable crítico del Bloque 0)

Sin listas cerradas compartidas, el heatmap se rompe: uno escribe "mata leão" y el otro "RNC".
El diccionario v1 está cerrado y es idéntico en Postgres, en TypeScript y en la plantilla:

| Dimensión | Valores | Nota |
|---|---|---|
| Posiciones | **24** | 13 marcadas `core_v1` para empezar sin abrumaros |
| Guardias | **13** | no es un enum aparte: son las posiciones con `grupo = 'guardia'` |
| Objetivos de ataque | **11** | cuello, hombro, codo, muñeca, bíceps, columna, cadera, rodilla, tobillo/pie, pantorrilla, ninguno |
| Tipos de evento | **6** | sumisión, barrida, pase de guardia, derribo, toma de espalda, escape |
| Técnicas | **63** | con `alias[]`: "mata leão", "RNC" y "rear naked choke" apuntan a la misma fila |

Las **13 posiciones core** para Sprint 0: de pie, clinch, guardia cerrada, guardia abierta,
media guardia, mariposa, De la Riva, montada, cien kilos, norte-sur, espalda, tortuga, scramble.
El resto queda disponible en el desplegable para cuando lo necesitéis.

> **Esto es lo que hay que revisar juntos antes de nada.** Si en vuestra academia se usan otras
> palabras, cambiadlas ahora — mover una etiqueta el día 1 cuesta cero, el día 90 cuesta una
> migración.

---

## 5. Modelo de datos

Seis tablas más dos de referencia:

```
practicantes ──┬── sesiones ── rolls ── eventos ──┬── tecnicas (diccionario)
               │                    │             └── posiciones (diccionario)
               └── retos ── reto_participaciones
```

| Tabla | Rol |
|---|---|
| `practicantes` | roster; `usa_sistema` marca quién tiene cuenta (habilita H2H cruzado) |
| `sesiones` | contexto del entrenamiento |
| `rolls` | el asalto |
| **`eventos`** | **la tabla estrella** |
| `posiciones` | referencia: nombre legible, grupo, `es_guardia` (columna generada) |
| `tecnicas` | diccionario con alias, tipo y objetivo por defecto |
| `retos` + `reto_participaciones` | gamificación; la regla se guarda como `jsonb` |

Incluye RLS: cada uno ve y edita solo sus sesiones, el roster y los retos son compartidos.

### Cómo sale cada visualización

| Visualización | Vista SQL | Cómo se calcula |
|---|---|---|
| Heatmap ofensivo | `v_heatmap_ofensivo` | `actor='yo'`, `tipo='sumision'`, agrupado por posición × objetivo |
| Heatmap defensivo | `v_heatmap_defensivo` | lo mismo con `actor='oponente'` |
| Qué guardia funciona | `v_guardias` | barridas y tomas de espalda a favor − pases en contra |
| Fuertes / débiles | `v_fuertes_debiles` | % de dominio por posición |
| Head-to-head | `v_h2h` | agregado por `oponente_id` |
| Evolución | `v_evolucion_semanal` | series por semana |
| Progreso de retos | `progreso_reto()` | filtro declarativo desde el `jsonb` |

Los retos se auto-validan sin código extra:

| Reto | Regla |
|---|---|
| "Solo sumisiones de hombro" | `{"objetivo":"hombro","tipo":"sumision"}` |
| "Juega siempre De la Riva" | `{"posicion":"de_la_riva","rol":"abajo"}` |
| "5 barridas esta semana" | `{"tipo":"barrida"}` con `objetivo_cantidad = 5` |
| "3 mata leões" | `{"tecnica":"mata_leao"}` |

---

## 6. Stack y por qué

**Base de datos → Supabase (Postgres).** SQL puro, que es terreno conocido para Felipe. Free
tier de sobra para dos personas. Trae auth, API REST y realtime sin escribir backend.

**Lenguaje → TypeScript, sin dudarlo.** El proyecto es todo vocabularios cerrados: posiciones,
objetivos, tipos de evento. Eso son *union types* de manual, y el compilador os obliga a los dos
a usar las mismas palabras — el problema de taxonomía resuelto a nivel de código. Además
Supabase genera los tipos solo desde el esquema:

```bash
npx supabase gen types typescript --project-id <id> > src/lib/database.types.ts
```

Eso da tipado end-to-end: si uno cambia el esquema, al otro le falla la compilación al instante
en vez de descubrirlo en producción. Con dos personas programando en paralelo esto es lo que
convierte `eventos` de un acuerdo verbal en un contrato verificado.

**Frontend → Next.js (App Router) + Recharts/visx, como PWA instalable.** Se instala en el móvil
desde el navegador, sin App Store, sin cuenta de desarrollador, sin coste.

**Dashboards intermedios → Metabase o Looker Studio** apuntando a Postgres. Os da gráficos en
la Fase 1 sin escribir una línea de frontend.

**Lo que descartamos y por qué:** Notion (perfecto para loguear, incapaz de hacer heatmaps o
validar retos) · Airtable/Glide como destino final (rápido de montar, pero el análisis se queda
corto justo cuando el proyecto se pone interesante) · backend propio (Supabase ya lo es).

---

## 7. Bloques de trabajo

| Bloque | Contenido | Estado |
|---|---|---|
| **0 · Producto & Taxonomía** | diccionario + esquema + plantilla de logging | ✅ **entregado** |
| **1 · Captura / Journal** | logging móvil de mínima fricción | Sprint 0-2 |
| **2 · Backend** | Supabase, esquema, auth, RLS | Sprint 1 |
| **3 · Análisis & Visualización** | heatmaps, guardias, fuertes/débiles | Sprint 1-2 |
| **4 · Gamificación** | H2H, retos, rachas | Sprint 3 |
| **5 · Iteración / Ops** | compartir, invitar gente, roadmap | después |

**Corte MVP** = Bloque 0 + Bloque 1 + Bloque 2 + heatmap básico del Bloque 3.

---

## 8. Plan de sprints

### Sprint 0 — esta semana · "empezar a loguear ya"

Sin código. Subís `BJJ-Tracker-Sprint0.xlsx` a Google Drive, lo abrís como Google Sheet y
logueáis cada entreno. La pestaña **Heatmap** ya se calcula sola con fórmulas: veréis vuestro
primer heatmap con los datos de la primera semana.

Objetivo real del sprint: **validar la taxonomía con datos de verdad**. Apuntad cada vez que
queráis escribir algo que no está en el desplegable — esa lista es el input de la v2 del
diccionario.

- [ ] Revisar juntos el diccionario y ajustar nombres a la jerga de la academia
- [ ] Subir la plantilla a Drive, una copia cada uno
- [ ] Loguear 3-4 entrenos cada uno
- [ ] Anotar las palabras que faltaban

### Sprint 1 — semana 2 · backend real

- [ ] Proyecto en Supabase, ejecutar `01`, `02`, `03` (y `05` si queréis datos de prueba)
- [ ] Importar los CSV del Sheet de Sprint 0
- [ ] Auth (magic link) y comprobar que la RLS aísla bien los datos
- [ ] Conectar Metabase o Looker Studio y reproducir los heatmaps

**Reparto:** uno monta Supabase + auth + RLS + importación · el otro las queries de análisis y
el dashboard.

### Sprint 2 — semanas 3-4 · la app

- [ ] Next.js + TS + PWA, tipos generados desde Supabase
- [ ] Pantalla de logging rápido (sesión → roll → eventos, pensada para el móvil en el tatami)
- [ ] Heatmaps ofensivo y defensivo + panel de guardias

**Reparto:** uno el eje de **captura** (formularios, offline-first) · el otro el eje de
**análisis** (heatmaps, charts). Se tocan solo en los tipos generados de `eventos`.

### Sprint 3 — gamificación

- [ ] H2H por oponente · vincular cuentas de los que usan el sistema
- [ ] Retos semanales con progreso automático · rachas y badges

---

## 9. Riesgos y cómo los cubrimos

| Riesgo | Mitigación |
|---|---|
| **El logging se abandona** (el riesgo nº1 de todo proyecto así) | Sprint 0 sin código: si el hábito no aguanta 2 semanas en un Sheet, tampoco aguantaría en una app. Barato descubrirlo ya |
| Taxonomía equivocada | 24 posiciones con 13 core; se ajusta después de Sprint 0, antes de que haya volumen |
| Datos asimétricos (uno loguea, el otro no) | el H2H funciona igual con oponentes que no usan el sistema |
| Sobre-ingeniería | Bloques 4 y 5 no se tocan hasta que Bloques 0-3 estén en uso real |
| Fricción en el tatami | el nivel evento es opcional: un roll sin eventos sigue contando |

---

## 10. Definición de "hecho" del MVP

1. Los dos logueáis desde el móvil en menos de 2 minutos por entreno.
2. Los datos están en Supabase con RLS funcionando.
3. Se ven el heatmap ofensivo y el defensivo con datos reales.
4. Se ve el head-to-head Felipe vs Pablo.
5. Al menos un reto semanal se ha validado solo.

---

## Anexo · Ficheros entregados

| Fichero | Qué es |
|---|---|
| `00-PROYECTO.md` | este documento |
| `01-schema.sql` | enums, 8 tablas, índices, RLS — pegar en Supabase |
| `02-seed-diccionario.sql` | 24 posiciones + 63 técnicas con alias |
| `03-analytics.sql` | 7 vistas de análisis + `progreso_reto()` |
| `04-types.ts` | vocabulario e interfaces en TypeScript |
| `05-datos-ejemplo.sql` | datos de prueba para ver los heatmaps antes de tener datos reales |
| `BJJ-Tracker-Sprint0.xlsx` | plantilla de logging con desplegables y heatmap en vivo |

**Todo verificado**: el SQL se ejecutó contra un Postgres 16 real (esquema + seed + vistas +
datos de ejemplo, sin errores), los tipos pasan `tsc --strict`, los 10 enums coinciden valor por
valor entre SQL, TypeScript y la plantilla, y las 528 fórmulas del workbook recalculan sin un
solo error.
