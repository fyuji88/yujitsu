# Prompt para Claude Code — el espejo no se está creando

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Un roll observado tiene que crear **dos** rolls, uno por jugador. Ahora mismo
crea uno. Mañana hay Open Mat de verdad. Lee antes `CLAUDE.md`.

## Lo medido en producción, ahora

```
rolls observados de HOY  ·  con espejo: 0  ·  SIN espejo: 8
rolls observados de antes ·  con espejo: 198 · sin espejo: 55
```

Ocho de ocho hoy. Los rolls llevan `par_id`, pero son huérfanos: un solo roll por
par. Los oponentes no tienen ni sesión ni rolls.

## Diagnostica antes de arreglar

**No supongas la causa.** Las candidatas, y hay que descartarlas con datos:

- ¿Se está llamando a `espejar_roll` desde `registrar_roll_observado`?
- ¿Se llama, falla, y alguien se traga el error? Un `exception when others` en el
  camino lo explicaría entero, y es la forma que más veces nos ha mordido.
- ¿Crea el roll espejo pero no la sesión del oponente, y muere en la clave
  foránea?
- ¿Se rompió al meter `p_quedada` en `bjj_35`? `espejar_roll` pasó a leer la
  quedada de la sesión del original — si esa lectura falla o devuelve algo
  inesperado, ahí está.

**Y mira los 55 huérfanos viejos**: ¿de qué fechas son, de qué camino vienen?
Si se concentran en una ventana concreta son otra causa distinta y conviene
saberlo; si están repartidos, puede que llevemos con esto más tiempo del que
creemos.

Dime la causa antes de tocar nada.

## El listón

Un roll registrado en modo observador deja, cuando termina:

- **dos rolls**, uno en la sesión de cada jugador;
- **las dos sesiones creadas** y las dos enganchadas al **mismo Open Mat**;
- los eventos duplicados, con **`par_evento_id` compartido** entre cada pareja;
- y el espejo **invirtiendo** lo que tiene que invertir: `resultado`, `rol_inicio`
  y el `actor` de cada evento. Nada más se invierte.

## Y que no vuelva a pasar en silencio

Esto es lo que quiero de verdad, más que el arreglo.

**Un invariante en la batería**: ningún roll con `origen = 'observador'` creado a
partir de ahora puede existir sin su pareja. En SQL es una línea —los rolls cuyo
`par_id` no aparece exactamente dos veces— y tiene que dar **cero**.

Los 55 huérfanos viejos van a una lista de excepciones **con fecha de corte**, no
metidos debajo de la alfombra: la comprobación ignora lo anterior a hoy y es
estricta a partir de hoy.

Y **pruébala viéndola fallar** antes de fiarte: rompe el espejo a propósito, mira
que se pone roja, y deshaz.

## Cómo lo verificas

1. `npm run build` con typecheck estricto.
2. **De punta a punta contra el Postgres local**: un roll observado entre dos
   personas → dos rolls, dos sesiones, mismo Open Mat, eventos espejados. Y una
   segunda llamada con el mismo par sigue siendo idempotente.
3. **El invariante nuevo, en verde y visto fallar.**
4. La batería entera: RLS, las SQL y los recorridos.
5. **Y en producción, después de desplegar**: registra un roll observado de
   prueba entre dos Saiyans y comprueba con una consulta que salen los dos lados.
   No te fíes de la pantalla — mira las filas.

## Cuidado con la hora

Mañana por la mañana hay Open Mat con gente. **Despliega esta noche o no
despliegues.** Si a última hora no está claro, dilo y lo dejamos roto a
propósito: mañana se registra igual y el lunes se reconstruyen los espejos que
falten, porque el `par_id` está y los eventos están. Se puede rehacer.

Lo que no se puede rehacer es un despliegue a medias en mitad del entreno.

Cuando termines, escribe la entrada en `docs/CAMBIOS.md` —decisiones y sabido roto
obligatorios, con la causa raíz explicada— y tacha lo que corresponda en
`docs/BACKLOG.md`.
