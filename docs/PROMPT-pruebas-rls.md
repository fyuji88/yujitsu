# Prompt para Claude Code — la red de pruebas de RLS

Copia todo lo que hay debajo de la línea y pégalo en Claude Code, dentro de la
carpeta del repositorio.

---

Vas a montar la **batería automática de pruebas de RLS**. No cambias ni una
política ni una tabla: **solo escribes pruebas**. Si alguna falla, la anotas y la
dejas fallando — no "arregles" una política para que pase el test, porque puede
que el test tenga razón. Lee antes `CLAUDE.md`.

## Por qué esto y por qué ahora

En esta app **la RLS es todo el perímetro de seguridad**. No hay servidor propio:
el navegador habla directamente con Postgres con una clave que es pública por
diseño, y lo único que separa los datos de una persona de los de otra son las
políticas. Ya van veintiuna migraciones, varias han tocado la lectura
(`bjj_13`, `bjj_15`) y la escritura por terceros (`bjj_09`), y **no hay una sola
prueba automática que compruebe que siguen haciendo lo que creemos**.

Es también la condición para poder trabajar más rápido después: con esta red,
tocar políticas deja de ser una operación a pulso.

## Cómo se prueba la RLS de verdad

Lo que **no** vale: conectarse como superusuario o con la clave de servicio.
Ambos se saltan la RLS y todos los tests pasarían siempre.

Lo que sí:

```sql
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"<uuid del usuario>","role":"authenticated"}';
  -- ... la comprobación ...
rollback;
```

Todo dentro de transacciones que **siempre terminan en `rollback`**, para que la
batería se pueda correr mil veces sin dejar rastro.

## Dónde va

`db/pruebas/rls.sql`, siguiendo el estilo de lo que ya hay en `db/pruebas/`. Que
imprima una línea por caso con `ok` o `FALLO`, y que termine con un resumen y con
código de salida distinto de cero si algo falló, para que se pueda meter en CI
más adelante.

Y un `db/pruebas/README.md` corto: cómo levantarlo contra el Postgres local y
cómo interpretarlo.

## Los casos, y no te dejes ninguno

Monta primero un **escenario mínimo** dentro de la propia transacción: dos grupos
(A y B), dos practicantes con cuenta en cada uno, un contacto sin cuenta, y unos
pocos rolls con eventos en cada grupo.

**Lectura**

1. Un miembro del grupo A **ve** sus propios rolls, sesiones y eventos.
2. Un miembro del grupo A **ve** los de otro miembro del grupo A — es lo que
   permite el selector de practicante en Análisis.
3. Un miembro del grupo A **no ve nada** del grupo B: cero filas en `sesiones`,
   `rolls`, `eventos`, y también a través de **las vistas** (`v_eventos`,
   `v_heatmap_ofensivo`, `v_h2h`, `v_puntos_roll`, `v_feed`). Las vistas son
   justo por donde se escapa esto si a alguna le falta `security_invoker`.
4. `anon` **no ve nada** de ninguna tabla de datos.
5. El **catálogo** (`posiciones`, `tecnicas`) sí es legible por cualquier
   autenticado.

**Escritura**

6. Puedo insertar una sesión mía; **no** puedo insertar una sesión a nombre de
   otro practicante.
7. Puedo borrar mis rolls; **no** puedo borrar los de otro.
8. Puedo editar mi ficha de practicante y los contactos que creé yo; **no** la de
   alguien con cuenta propia, ni los contactos de otro.
9. **La apertura de lectura no abrió escritura.** Un miembro del grupo A intenta
   `update` y `delete` sobre datos de otro miembro del mismo grupo: tiene que
   fallar. Este caso es el más importante de la lista — es el fallo que dejaría
   la app rota sin que nadie lo notara.

**Las funciones que se saltan la RLS a propósito**

10. `registrar_roll_observado` funciona para un autenticado con ficha, y **falla**
    para uno sin ficha.
11. Es **idempotente**: dos llamadas con el mismo `roll_grupo_id` dejan un solo
    roll por persona.
12. `unirse_con_codigo` con un código inválido falla; con uno válido no duplica
    la membresía al llamarla dos veces.
13. `apuntarse_a_quedada` respeta las plazas: con una libre, dos llamadas dejan un
    `apuntado` y un `lista_espera`.
14. Ninguna de las funciones `SECURITY DEFINER` es ejecutable por `anon`.
    Compruébalo leyendo `information_schema.routine_privileges`, no de memoria.

**Los invitados externos a una quedada**

15. Un practicante que **no** es miembro del grupo pero está apuntado a una
    quedada ve **esa quedada** y **no** ve el feed del grupo ni los rolls de los
    demás.

## Al terminar

Escribe en la entrada de `docs/CAMBIOS.md` **cuántos casos hay y cuántos pasan**.
Si alguno falla, en "sabido roto" con una frase de qué implica: no es un fallo del
test, es información.

Y añade a `docs/BACKLOG.md`, si no está, el paso siguiente: **meter esta batería
en CI** para que corra en cada push.

## Fuera de alcance

No toques políticas, ni tablas, ni funciones. No es refactor, es red de seguridad.
Y no toques producción en ningún momento: todo contra el Postgres local que está
documentado en `db/README.md`.
