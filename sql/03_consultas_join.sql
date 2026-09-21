-- =====================================================================
-- 03_consultas_join.sql
-- Taller de Normalizacion - Catalogo Audiovisual de Netflix
-- Fase VI: Explotacion Analitica mediante Consultas SQL (JOIN)
--
-- Responsable: Sergio (implementacion SQL: DDL, ETL y consultas)
-- Documentacion de resultados: Gerogy (ver README)
--
-- SQL puro: ejecutar en el Query Tool de pgAdmin conectado a netflix_db.
-- pgAdmin muestra solo la grilla de la ULTIMA sentencia de un script, asi
-- que se ejecuta cada consulta por separado: seleccionarla y pulsar F5
-- (o ejecutar el archivo completo y ver la Consulta B).
--
-- El filtrado parametrizado se hace con una CTE "parametros": basta con
-- cambiar el valor literal (genero / pais) y volver a ejecutar.
--   Generos de ejemplo: 'Documentaries', 'Comedies', 'Dramas', 'Action & Adventure'
--   Paises de ejemplo : 'India', 'United States', 'Spain', 'Colombia'
-- =====================================================================


-- =====================================================================
-- CONSULTA A - Catalogo Cinematografico por Genero
-- ---------------------------------------------------------------------
-- Proyecta: titulo, anio de lanzamiento, clasificacion por edad,
-- duracion y genero.
-- Restringida a peliculas ("Movie"), con filtro parametrizado por
-- categoria tematica y orden cronologico descendente.
-- Tablas vinculadas (4): titles, title_genres, genres, ratings.
-- =====================================================================
WITH parametros AS (
    SELECT 'Documentaries'::text AS genero          -- <-- parametro
)
SELECT
    t.title_name                                    AS titulo,
    t.release_year                                  AS anio_lanzamiento,
    COALESCE(r.code, 'Sin clasificar')              AS clasificacion,
    t.duration_value::INTEGER || ' ' || t.duration_unit AS duracion,
    g.genre_name                                    AS genero
FROM parametros p
JOIN genres g         ON g.genre_name = p.genero
JOIN title_genres tg  ON tg.genre_id  = g.genre_id
JOIN titles t         ON t.title_id   = tg.title_id
LEFT JOIN ratings r   ON r.rating_id  = t.rating_id
WHERE t.title_type = 'Movie'
ORDER BY t.release_year DESC, t.title_name ASC;


-- =====================================================================
-- CONSULTA B - Trazabilidad Geografica y de Participacion
-- ---------------------------------------------------------------------
-- Recupera: titulo, tipo de produccion, pais de origen, nombre del
-- participante, rol desempeniado y anio de estreno.
-- Filtro parametrizado por pais; integra 5 tablas del esquema
-- (countries, title_countries, titles, title_people, people) y ordena
-- alfabeticamente por titulo y rol.
-- =====================================================================
WITH parametros AS (
    SELECT 'India'::text AS pais                    -- <-- parametro
)
SELECT
    t.title_name    AS titulo,
    t.title_type    AS tipo_produccion,
    c.country_name  AS pais_origen,
    pe.full_name    AS participante,
    tp.role         AS rol,
    t.release_year  AS anio_estreno
FROM parametros p
JOIN countries c        ON c.country_name = p.pais
JOIN title_countries tc ON tc.country_id  = c.country_id
JOIN titles t           ON t.title_id     = tc.title_id
JOIN title_people tp    ON tp.title_id    = t.title_id
JOIN people pe          ON pe.person_id   = tp.person_id
ORDER BY t.title_name ASC, tp.role ASC, pe.full_name ASC;
