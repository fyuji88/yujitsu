-- ============================================================
--  ¿Ya hay datos suficientes para calibrar las rarezas de los logros?
--
--    psql "$PROD" -f scripts/listo-para-calibrar.sql
--
--  Un elemento de backlog que dice "cuando haya datos reales" se pudre: nadie
--  sabe cuándo se cumple, así que nunca se cumple. Esto lo convierte en una
--  pregunta con respuesta de sí o no, para poder mirarla en la retro de los
--  domingos en diez segundos.
--
--  EL DISPARADOR: 200 rolls reales de al menos 5 personas distintas.
--
--  "Reales" quiere decir sin Goku ni Vegeta. No es que sus datos sean malos,
--  es que salen de un generador que **solo emite evento cuando pasa algo** —
--  así que "el rival no marcó" sale artificialmente común, y calibrar contra
--  eso sería calibrar contra las manías del simulador, no contra el jiu-jitsu.
--
--  LA DIANA, cuando toque: común entre el 10 % y el 25 % de los rolls, poco
--  común entre el 3 % y el 10 %, raro por debajo del 2 %. Lo que se salga por
--  arriba se endurece — se le añade guarda de volumen o se le sube el umbral.
-- ============================================================

with reales as (
  select r.id, s.practicante_id
    from rolls r
    join sesiones s on s.id = r.sesion_id
    join practicantes p on p.id = s.practicante_id
   where p.nombre not in ('Goku', 'Vegeta')
),
listo as (
  select count(*) as rolls, count(distinct practicante_id) as gente from reales
)
select case when rolls >= 200 and gente >= 5
            then 'SI — ' || rolls || ' rolls de ' || gente || ' personas. Toca calibrar.'
            else 'Todavia no: ' || rolls || '/200 rolls y ' || gente || '/5 personas.'
       end as veredicto
  from listo;

-- Y si sale que sí, esto es lo que hay que mirar: qué porcentaje de los rolls
-- se lleva cada logro. Los de ámbito distinto de `roll` no entran, porque su
-- denominador no son los rolls.
with reales as (
  select r.id, s.practicante_id
    from rolls r
    join sesiones s on s.id = r.sesion_id
    join practicantes p on p.id = s.practicante_id
   where p.nombre not in ('Goku', 'Vegeta')
)
select l.rareza,
       l.clave,
       count(c.*)                                                as veces,
       round(100.0 * count(c.*) / nullif((select count(*) from reales), 0), 1) as pct,
       case
         when l.rareza = 'comun'      and 100.0 * count(c.*) / nullif((select count(*) from reales),0) > 25 then 'ENDURECER'
         when l.rareza = 'poco_comun' and 100.0 * count(c.*) / nullif((select count(*) from reales),0) > 10 then 'ENDURECER'
         when l.rareza = 'raro'       and 100.0 * count(c.*) / nullif((select count(*) from reales),0) >  2 then 'ENDURECER'
         else ''
       end                                                       as veredicto
  from logros l
  left join v_logros_conseguidos c
    on c.clave = l.clave and c.ref_id in (select id::text from reales)
 where l.ambito = 'roll'
 group by l.rareza, l.clave
 order by pct desc nulls last;
