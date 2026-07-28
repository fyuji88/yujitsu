# Interfaz, almacenamiento y distribución

**Decisiones de producto · Bloques 1 y 2 · 26 julio 2026**
Acompaña al prototipo clicable `BJJ-Log-Prototipo.html`

---

## 1. La interfaz: la app sigue el roll, no es un formulario

El error clásico de estos trackers es presentar un formulario con desplegables: posición,
técnica, objetivo. Con 24 posiciones y 63 técnicas eso son tres listas largas por evento, y a
las dos semanas nadie lo rellena.

La alternativa es tratar el logging como **la misma máquina de estados que usa el simulador**:
la app sabe dónde estás en cada momento y solo te ofrece lo que puede pasar desde ahí.

Estás en guardia cerrada abajo, así que los botones son *barrida, sumisión, tomo espalda* por tu
lado y *me pasa, me somete* por el suyo. Nada más. Si tocas "sumisión", las técnicas que aparecen
no son 63: son las cinco que se hacen desde ahí, cada una con su articulación ya asociada. Si
tocas "barrida", te pregunta dónde acabas y actualiza la posición sola.

El resultado medido sobre el prototipo:

| Camino | Toques | Qué queda registrado |
|---|---|---|
| Roll con 3 eventos | **9** | secuencia completa con posiciones y técnicas |
| Roll largo, 5 eventos con un intento fallado | **16** | ídem, incluida la sumisión que no entró |
| Solo resultado ("hoy no tengo cuerpo") | **4** | el roll cuenta para H2H, volumen y evolución |
| Abrir la sesión | **4** | una vez por entrenamiento |

Un entreno normal de 5 rolls sale por debajo de los 60 toques y de los dos minutos, sin teclado,
sin scroll y sin buscar en ninguna lista.

Tres decisiones que sostienen esto:

**Nadie loguea durante el roll.** Se loguea entre asaltos o en el vestuario. Por eso la pantalla
tiene botones grandes y estado persistente: puedes dejarla a medias, coger el móvil dos minutos
después y seguir.

**El nivel evento es opcional.** El botón "solo resultado" existe para que los días malos no
rompan la racha. Un roll sin eventos sigue alimentando el head-to-head y la evolución; solo se
pierde el heatmap de ese roll. Es preferible a que dejes de abrir la app.

**Todo evento es reversible.** Cada línea del timeline tiene su ✕. Sin diálogos de confirmación,
sin fricción para corregir — si equivocarse es caro, la gente deja de registrar.

### Hallazgo del prototipo: falta un tipo de evento

Al construirlo apareció un hueco en el modelo. Cuando alguien mejora de cien kilos a montada, eso
no es ninguno de los seis tipos que definimos (`sumision`, `barrida`, `pase_guardia`, `derribo`,
`toma_espalda`, `escape`). En el prototipo lo resolví actualizando la posición **sin generar
evento** — la mejora se acaba reflejando igual, porque la posición queda registrada en el
siguiente evento que ocurra desde ahí.

Funciona, pero se pierde información: cuántas veces te montan después de pasarte la guardia es un
dato interesante. Propuesta para la v2 del diccionario: añadir `transicion` al enum
`bjj_tipo_evento`. Es un `ALTER TYPE ... ADD VALUE`, no rompe nada de lo ya escrito. Lo dejo
apuntado en vez de decidirlo yo porque cambia el vocabulario, y el vocabulario lo cerráis vosotros
dos.

---

## 2. Almacenamiento: local primero, sincronizar después

**No se escribe directamente contra la base de datos.** En un gimnasio no hay cobertura fiable, la
red del móvil va y viene, y una escritura fallida a mitad de un roll significa datos perdidos y un
usuario que no vuelve a fiarse de la app.

El patrón correcto aquí es *local-first con cola de salida*:

1. Tocas un botón → el evento se escribe **en el móvil**, en IndexedDB (con Dexie, que es una capa
   fina y cómoda encima). Esto es instantáneo y funciona en modo avión.
2. El evento entra en una tabla `outbox` marcado como pendiente.
3. Un worker vacía la cola contra Supabase cuando hay conexión, y marca lo enviado.
4. La UI nunca espera a la red. La píldora de arriba a la derecha en el prototipo enseña el estado
   — tócala para simular quedarte sin cobertura y verás que se sigue pudiendo loguear.

Dos detalles que evitan dolor más adelante:

**Los IDs se generan en el cliente** (UUID v4). Así un reintento nunca duplica: si no estás seguro
de si el evento llegó, lo reenvías y Postgres lo rechaza por clave primaria. Sin esto acabáis con
rolls duplicados el día que el móvil pierda la red a mitad de sincronización.

**El local es caché, no el archivo.** Safari en iOS es agresivo borrando almacenamiento de sitios
que no se abren en una semana, y su cuota es bastante menor que la de Chrome. Con la cola
vaciándose en cuanto hay wifi eso da igual, pero significa que **nunca** debe haber datos que
existan solo en el móvil durante días. Es un argumento más para sincronizar pronto y a menudo.

### Google Sheets vs Supabase

Sheets es perfecto para el Sprint 0 y malo como backend de una app:

| | Google Sheets | Supabase |
|---|---|---|
| Escribir desde el móvil sin conexión | no | sí (con la cola local) |
| Auth por usuario | no real | sí, integrada |
| Aislar tus datos de los de Pablo | no | sí, con RLS |
| Queries para heatmaps | fórmulas frágiles | SQL |
| Cuotas de API | sí, y estrictas | generosas |
| Tipos y validación | ninguna | enums de Postgres |

Sobre el plan gratuito de Supabase, para que lo tengáis presente: 500 MB de base de datos, 50.000
usuarios activos al mes, 1 GB de ficheros, 5 GB de tráfico, máximo 2 proyectos activos — y **el
proyecto se pausa tras una semana sin actividad**. Para dos personas os sobra por años (679
eventos ocupan menos de 100 KB), y la pausa no os va a afectar si entrenáis; pero si dejáis el
proyecto parado un mes, al volver hay que despausarlo a mano desde el panel.

---

## 3. Distribución: PWA, no app nativa

| | HTML suelto | **PWA** | App nativa (Expo) |
|---|---|---|---|
| Instalar en el móvil | no | sí, desde el navegador | sí, desde la store |
| Funciona sin conexión | no | sí | sí |
| Coste | 0 | 0 | 99 €/año Apple + tiempo |
| Publicar una versión nueva | — | al instante | revisión de la store |
| Compartir con un amigo | — | mandas un link | tiene que instalarla |
| Notificaciones push | no | sí, si está instalada | sí |

**Recomendación: PWA**, desplegada en Vercel (gratis). Mandáis una URL, cada uno le da a "Añadir a
pantalla de inicio" y a partir de ahí es un icono más, a pantalla completa, sin barra del
navegador y con acceso offline. Cero fricción para invitar a alguien de la academia, que es
justo lo que necesita la parte de gamificación.

Lo que hay que saber de iOS antes de prometer nada:

Las notificaciones push funcionan desde iOS 16.4, **pero solo si la app está añadida a la pantalla
de inicio** — en una pestaña normal de Safari no hay push. Y no existe el botón de "instalar" que
sí tiene Android: hay que ir al menú compartir y darle a "Añadir a pantalla de inicio" a mano, así
que la app tiene que explicarlo la primera vez. (Apple llegó a anunciar que retiraba las web apps
de pantalla de inicio en la UE por el DMA, pero dio marcha atrás en marzo de 2024; siguen
funcionando aquí.)

Tampoco hay Background Sync en iOS: la cola solo se vacía con la app abierta. En la práctica no
importa — abres la app para loguear y ahí mismo se sincroniza.

**Cuándo pasar a nativa:** si algún día queréis app de Apple Watch (cronómetro de rolls desde la
muñeca sería un caso de uso precioso), notificaciones fiables en segundo plano, o publicar en las
stores. Con Expo se reaprovecha casi todo el código React. No antes de tener el hábito validado.

### Cómo se comparte lo que generáis

- **La app**: una URL. Nada más.
- **Invitar a un compañero**: link con código, que crea su fila en `practicantes` con
  `usa_sistema = true` y activa el head-to-head cruzado.
- **Un heatmap concreto**: página pública de solo lectura con un token en la URL — se manda por
  WhatsApp al grupo de la academia y se ve sin instalar nada. Es el mejor canal de crecimiento que
  vais a tener.

---

## Resumen para el sprint

| Decisión | Elección |
|---|---|
| Paradigma de logging | máquina de estados contextual, no formulario |
| Objetivo de fricción | < 12 toques por roll, < 2 min por entreno |
| Almacenamiento en el móvil | IndexedDB (Dexie) + tabla `outbox` |
| Base de datos | Supabase (Postgres), plan gratuito |
| IDs | UUID v4 generados en el cliente |
| Distribución | PWA en Vercel, instalable |
| Nativa | solo si llega el caso de Apple Watch o push en segundo plano |
| Pendiente de decidir entre vosotros | añadir `transicion` al enum de tipos de evento |

**Fuentes:** [Supabase Pricing](https://supabase.com/pricing) ·
[PWA iOS limitations and Safari support](https://www.magicbell.com/blog/pwa-ios-limitations-safari-support-complete-guide) ·
[Apple reverses decision on EU home screen web apps](https://pushalert.co/blog/apple-reverses-decision-will-continue-to-support-home-screen-web-apps-in-the-eu/)
