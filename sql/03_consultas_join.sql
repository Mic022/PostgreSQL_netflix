-- =====================================================================
-- 03_consultas_join.sql
-- Taller de Normalizacion - Catalogo Audiovisual de Netflix
-- Fase VI: Explotacion Analitica mediante Consultas SQL (JOIN)
--
-- Responsable: Sergio (implementacion SQL: DDL, ETL y consultas)
-- Documentacion de resultados: Gerogy (ver README, seccion 7)
--
-- Ejecucion recomendada:
--   psql -h localhost -p 5432 -U admin -d netflix_db -f sql/03_consultas_join.sql
--
-- Ambas consultas usan variables psql (:'nombre') para el filtrado
-- parametrizado. Pueden sobreescribirse por linea de comandos, p. ej.:
--   psql -U admin -d netflix_db -v genero='Comedies' -v pais='India' \
--        -f sql/03_consultas_join.sql
-- =====================================================================

\connect netflix_db

-- Valores por defecto de los parametros (se usan si no se pasan con -v)
\if :{?genero}
\else
    \set genero 'Documentaries'
\endif

\if :{?pais}
\else
    \set pais 'India'
\endif

-- =====================================================================
-- CONSULTA A - Catalogo Cinematografico por Genero
-- ---------------------------------------------------------------------
-- Proyecta: titulo, anio de lanzamiento, clasificacion por edad,
-- duracion y genero.
-- Restringida a peliculas ("Movie"), con filtro parametrizado por
-- categoria tematica (:genero) y orden cronologico descendente.
-- Tablas vinculadas (4): titles, ratings, title_genres, genres.
-- =====================================================================
SELECT
    t.title_name                                   AS titulo,
    t.release_year                                  AS anio_lanzamiento,
    COALESCE(r.code, 'Sin clasificar')               AS clasificacion,
    t.duration_value || ' ' || t.duration_unit       AS duracion,
    g.genre_name                                     AS genero
FROM titles t
JOIN title_genres tg ON tg.title_id = t.title_id
JOIN genres g         ON g.genre_id  = tg.genre_id
LEFT JOIN ratings r   ON r.rating_id = t.rating_id
WHERE t.title_type = 'Movie'
  AND g.genre_name = :'genero'
ORDER BY t.release_year DESC, t.title_name ASC;


-- =====================================================================
-- CONSULTA B - Trazabilidad Geografica y de Participacion
-- ---------------------------------------------------------------------
-- Recupera: titulo, tipo de produccion, pais de origen, nombre del
-- participante, rol desempeniado y anio de estreno.
-- Filtro parametrizado por pais (:pais); integra 5 tablas del esquema
-- (titles, title_countries, countries, title_people, people) y ordena
-- alfabeticamente por titulo y rol.
-- =====================================================================
SELECT
    t.title_name    AS titulo,
    t.title_type    AS tipo_produccion,
    c.country_name  AS pais_origen,
    p.full_name     AS participante,
    tp.role         AS rol,
    t.release_year  AS anio_estreno
FROM titles t
JOIN title_countries tc ON tc.title_id   = t.title_id
JOIN countries c        ON c.country_id = tc.country_id
JOIN title_people tp    ON tp.title_id   = t.title_id
JOIN people p           ON p.person_id  = tp.person_id
WHERE c.country_name = :'pais'
ORDER BY t.title_name ASC, tp.role ASC;
