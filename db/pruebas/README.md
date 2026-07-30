# Las pruebas contra Postgres

Todo lo de esta carpeta corre **contra el Postgres local**, nunca contra
producción. Cómo levantarlo sin Docker está en [`db/README.md`](../README.md).

```bash
export PATH="$HOME/pgsql/bin:$PATH"
PG="postgresql://postgres@127.0.0.1:55432/bjj"
```

## Qué hay, y en qué orden conviene correrlo

| Fichero | Qué comprueba | ¿Destruye datos? |
|---|---|---|
| `semilla-demo.sql` | no es una prueba: **siembra** el juego de datos | sí, es su trabajo |
| `rls.sql` | las políticas, con 45 casos | no, todo en `rollback` |
| `logros.sql` | los 27 predicados, con su caso que cumple y su caso que no | no |
| `logros-rls.sql` | que los logros no sean una puerta lateral a otro grupo | no |
| `puntos.sql` | el marcador IBJJF contra el fixture compartido | **sí, arrasa** |
| `equipos-rls.sql` | la lectura por equipo de `bjj_15` | sí, toca `auth.users` |
| `quedadas.sql` | plazas, lista de espera e idempotencia | no |
| `informe.sql` | un título por cabeza, y congelado | modifica la quedada |

**El orden importa.** `puntos.sql` hace `truncate practicantes cascade` para
montar su propio mundo, así que se lleva por delante la semilla entera *y* la
cuenta con la que entra el navegador. Si lo ejecutas, vuelve a sembrar después:

```bash
psql "$PG" -v confirmar=si -f db/pruebas/semilla-demo.sql
```

## La batería de RLS

```bash
psql "$PG" -f db/pruebas/rls.sql
```

Imprime una línea por caso y termina con un resumen. **Sale con código distinto
de cero si algo falla**, así que se puede meter en CI tal cual.

```
  1  ok     [lectura  ] A1 ve sus propias sesiones
 21  FALLO  [lectura  ] anon NO ve practicantes
 ...
######## RLS: 2 de 45 casos FALLAN ########
```

### Cómo leerla

Las familias son cuatro:

- **lectura** — quién ve qué. Incluye las **vistas**, que es por donde se
  escapa esto si a alguna le falta `security_invoker`: la tabla queda tapada y
  la vista la enseña igual.
- **escritura** — quién puede tocar qué. El caso más importante de toda la
  batería está aquí: *"A1 NO edita las sesiones de A2 (mismo grupo)"*. `bjj_13`
  y `bjj_15` abrieron la **lectura** por grupo; si de paso se hubiera colado la
  escritura, cualquiera podría borrar los rolls de un compañero y no daría
  ningún error — simplemente desaparecerían datos.
- **rpc** — las funciones `SECURITY DEFINER`, que se saltan la RLS a propósito.
  Lo que se prueba es que la puerta tenga cerradura.
- **externo** — el invitado a una quedada que no es del grupo.

### Por qué no vale probar esto de cualquier manera

Conectado como `postgres` o con la clave de servicio, la RLS **se salta
entera** y todos los casos pasarían siempre. Eso no es una prueba, es
tranquilidad falsa. Por eso cada caso se ejecuta así:

```sql
set local role authenticated;
set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
```

Y todo vive dentro de una transacción que acaba en `rollback`, así que la
batería se puede correr mil veces seguidas sin dejar rastro.

### Si un caso falla

**No cambies la política para que pase.** Puede que el test tenga razón y la
política esté mal, y ese es justamente el trabajo que hace esta carpeta. Un
fallo aquí es información: apúntalo en `docs/CAMBIOS.md` y decide qué hacer con
la cabeza fría.

### Los dos que fallan hoy, y qué significan

**`anon NO ve practicantes`** — la política `practicantes_lectura` es
`FOR SELECT TO public USING (true)`, así que **cualquiera con la clave anónima
puede listar el roster entero**: nombres, cinturones, pesos y academia. Y esa
clave es pública por diseño, va dentro del JavaScript que sirve Vercel. Con
tres amigos es poca cosa; con la academia dentro es una lista de nombres reales
publicada en internet. Viene de `bjj_01`, no es una regresión.

**`el invitado ve la quedada a la que está apuntado`** — no la ve.
`quedadas_lectura_grupo` va por *tus grupos*, y un invitado externo no es
miembro de ninguno. **No es una fuga**: la ve por el enlace de invitación, que
pasa por `quedada_por_token()`, y el caso siguiente lo comprueba. Es una
carencia de producto: sin el enlace a mano no vuelve a encontrar el plan al que
dijo que iba.
