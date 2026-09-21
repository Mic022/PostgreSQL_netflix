-- =====================================================================
-- 02_carga_datos.sql
-- Taller de Normalizacion - Catalogo Audiovisual de Netflix
-- Fase IV (ETL) + Fase V (DML): carga, limpieza, atomizacion y
-- poblacion del esquema normalizado a partir de netflix_staging.
--
-- Responsable: Sergio (implementacion SQL: DDL, ETL y consultas)
--
-- Requisitos previos: haber ejecutado 01_creacion_base_datos.sql
--
-- SQL puro: se ejecuta en el Query Tool de pgAdmin conectado a netflix_db
-- (seleccionar todo el archivo y F5). Es re-ejecutable: vacia y recarga
-- todas las tablas.
--
-- La carga usa COPY del lado del SERVIDOR: la ruta del CSV es la que ve
-- el servidor PostgreSQL, no la del equipo del usuario.
--   * Docker (docker-compose.yml de este repo): ./data se monta en /data,
--     por lo que la ruta es '/data/netflix_titles.csv' (valor por defecto).
--   * PostgreSQL instalado en Windows: cambiar la ruta a la del CSV, p. ej.
--     'C:/Users/<usuario>/.../data/netflix_titles.csv' (el usuario debe ser
--     superusuario o miembro de pg_read_server_files).
--   * Alternativa sin permisos: pgAdmin > clic derecho sobre netflix_staging
--     > Import/Export Data (Format csv, Header on, Encoding UTF8) y omitir
--     la sentencia COPY de abajo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- FASE IV.1 - Carga cruda del CSV en la tabla de transito
-- ---------------------------------------------------------------------
-- Se vacian primero las tablas del modelo para que el script sea repetible.
TRUNCATE TABLE title_people, title_genres, title_countries,
               titles, people, genres, countries, ratings,
               netflix_staging
    RESTART IDENTITY CASCADE;

COPY netflix_staging (show_id, type, title, director, cast_members, country,
                      date_added, release_year, rating, duration, listed_in, description)
FROM '/data/netflix_titles.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', QUOTE '"');

-- ---------------------------------------------------------------------
-- FASE IV.2 - Limpieza: trim + estandarizacion de cadenas vacias a NULL
-- ---------------------------------------------------------------------
UPDATE netflix_staging SET
    show_id       = NULLIF(TRIM(show_id), ''),
    type          = NULLIF(TRIM(type), ''),
    title         = NULLIF(TRIM(title), ''),
    director      = NULLIF(TRIM(director), ''),
    cast_members  = NULLIF(TRIM(cast_members), ''),
    country       = NULLIF(TRIM(country), ''),
    date_added    = NULLIF(TRIM(date_added), ''),
    release_year  = NULLIF(TRIM(release_year), ''),
    rating        = NULLIF(TRIM(rating), ''),
    duration      = NULLIF(TRIM(duration), ''),
    listed_in     = NULLIF(TRIM(listed_in), ''),
    description   = NULLIF(TRIM(description), '');

-- Correccion de anomalia conocida del dataset: en un puñado de filas
-- (por un campo "country" ausente en el CSV original) el valor de
-- duracion quedo desplazado hacia la columna "rating"
-- (p. ej. rating = '74 min' y duration = NULL). Se reubica el valor en
-- la columna correcta y se anula el rating invalido.
UPDATE netflix_staging
   SET duration = rating,
       rating   = NULL
 WHERE rating ~ '^[0-9]+\s*min$'
   AND duration IS NULL;

-- ---------------------------------------------------------------------
-- FASE V.1 - Tablas maestras y catalogos independientes
-- ---------------------------------------------------------------------

-- Clasificaciones por edad
INSERT INTO ratings (code, description)
SELECT DISTINCT rating,
       CASE rating
           WHEN 'G'      THEN 'Audiencia general'
           WHEN 'PG'     THEN 'Se sugiere supervision de los padres'
           WHEN 'PG-13'  THEN 'Padres: puede no ser apto para menores de 13 anios'
           WHEN 'R'      THEN 'Restringido: menores acompanados de un adulto'
           WHEN 'NC-17'  THEN 'Prohibido para menores de 17 anios'
           WHEN 'NR'     THEN 'No clasificado'
           WHEN 'UR'     THEN 'Version sin clasificar'
           WHEN 'TV-Y'   THEN 'Contenido apto para ninios'
           WHEN 'TV-Y7'  THEN 'Apto para ninios mayores de 7 anios'
           WHEN 'TV-Y7-FV' THEN 'Apto para ninios mayores de 7 anios, con fantasia violenta'
           WHEN 'TV-G'   THEN 'Audiencia general (TV)'
           WHEN 'TV-PG'  THEN 'Se sugiere supervision de los padres (TV)'
           WHEN 'TV-14'  THEN 'Padres: no recomendado para menores de 14 anios'
           WHEN 'TV-MA'  THEN 'Contenido solo para audiencia adulta'
           ELSE NULL
       END
FROM netflix_staging
WHERE rating IS NOT NULL
ON CONFLICT (code) DO NOTHING;

-- Paises de origen (atomizacion de campo multivaluado)
INSERT INTO countries (country_name)
SELECT DISTINCT TRIM(c.country_item)
FROM netflix_staging s,
     LATERAL unnest(string_to_array(s.country, ',')) AS c(country_item)
WHERE s.country IS NOT NULL
  AND TRIM(c.country_item) <> ''
ON CONFLICT (country_name) DO NOTHING;

-- Generos / categorias tematicas (atomizacion de "listed_in")
INSERT INTO genres (genre_name)
SELECT DISTINCT TRIM(g.genre_item)
FROM netflix_staging s,
     LATERAL unnest(string_to_array(s.listed_in, ',')) AS g(genre_item)
WHERE s.listed_in IS NOT NULL
  AND TRIM(g.genre_item) <> ''
ON CONFLICT (genre_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- FASE V.2 - Entidad principal: titulos
-- ---------------------------------------------------------------------
INSERT INTO titles (
    show_id, title_type, title_name, date_added, release_year,
    rating_id, duration_value, duration_unit, description
)
SELECT
    s.show_id,
    s.type,
    s.title,
    CASE WHEN s.date_added IS NOT NULL
         THEN TO_DATE(s.date_added, 'FMMonth DD, YYYY')
    END,
    s.release_year::SMALLINT,
    r.rating_id,
    (regexp_match(s.duration, '^(\d+)'))[1]::NUMERIC,
    CASE
        WHEN s.duration ~* 'season' THEN 'season'
        WHEN s.duration ~* 'min'    THEN 'min'
    END,
    s.description
FROM netflix_staging s
LEFT JOIN ratings r ON r.code = s.rating;

-- ---------------------------------------------------------------------
-- FASE V.3 - Catalogo de personas (actores y directores)
-- ---------------------------------------------------------------------
-- Una misma persona aparece en el CSV con grafias distintas solo en
-- mayusculas/minusculas (p. ej. "Adam Devine" / "Adam DeVine"). Se
-- deduplica sin distinguir mayusculas y se conserva la grafia mas frecuente.
INSERT INTO people (full_name)
SELECT DISTINCT ON (LOWER(nombre)) nombre
FROM (
    SELECT nombre, COUNT(*) AS apariciones
    FROM (
        SELECT TRIM(unnest(string_to_array(director, ','))) AS nombre
        FROM netflix_staging WHERE director IS NOT NULL
        UNION ALL
        SELECT TRIM(unnest(string_to_array(cast_members, ','))) AS nombre
        FROM netflix_staging WHERE cast_members IS NOT NULL
    ) t
    WHERE nombre <> ''
    GROUP BY nombre
) frecuencia
ORDER BY LOWER(nombre), apariciones DESC, nombre;

-- ---------------------------------------------------------------------
-- FASE V.4 - Tablas asociativas N:M
-- ---------------------------------------------------------------------

-- Titulo <-> Pais
INSERT INTO title_countries (title_id, country_id)
SELECT DISTINCT t.title_id, c.country_id
FROM netflix_staging s
JOIN titles t ON t.show_id = s.show_id
CROSS JOIN LATERAL unnest(string_to_array(s.country, ',')) AS cn(country_item)
JOIN countries c ON c.country_name = TRIM(cn.country_item)
WHERE s.country IS NOT NULL
ON CONFLICT DO NOTHING;

-- Titulo <-> Genero
INSERT INTO title_genres (title_id, genre_id)
SELECT DISTINCT t.title_id, g.genre_id
FROM netflix_staging s
JOIN titles t ON t.show_id = s.show_id
CROSS JOIN LATERAL unnest(string_to_array(s.listed_in, ',')) AS gn(genre_item)
JOIN genres g ON g.genre_name = TRIM(gn.genre_item)
WHERE s.listed_in IS NOT NULL
ON CONFLICT DO NOTHING;

-- Titulo <-> Persona (rol Director)
INSERT INTO title_people (title_id, person_id, role)
SELECT DISTINCT t.title_id, p.person_id, 'Director'
FROM netflix_staging s
JOIN titles t ON t.show_id = s.show_id
CROSS JOIN LATERAL unnest(string_to_array(s.director, ',')) AS d(person_item)
JOIN people p ON LOWER(p.full_name) = LOWER(TRIM(d.person_item))
WHERE s.director IS NOT NULL
ON CONFLICT DO NOTHING;

-- Titulo <-> Persona (rol Actor)
INSERT INTO title_people (title_id, person_id, role)
SELECT DISTINCT t.title_id, p.person_id, 'Actor'
FROM netflix_staging s
JOIN titles t ON t.show_id = s.show_id
CROSS JOIN LATERAL unnest(string_to_array(s.cast_members, ',')) AS a(person_item)
JOIN people p ON LOWER(p.full_name) = LOWER(TRIM(a.person_item))
WHERE s.cast_members IS NOT NULL
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- FASE V.5 - Consultas de control / validacion post-carga
-- ---------------------------------------------------------------------
-- Un unico resultado (pgAdmin solo muestra la grilla de la ultima
-- sentencia). La columna "estado" debe ser OK en todas las filas.
SELECT chequeo, valor, esperado,
       CASE WHEN valor = esperado THEN 'OK' ELSE 'REVISAR' END AS estado
FROM (
    -- Coherencia cuantitativa: filas del CSV vs. titulos almacenados
    SELECT 'filas staging = titulos cargados' AS chequeo,
           (SELECT COUNT(*) FROM titles) AS valor,
           (SELECT COUNT(*) FROM netflix_staging) AS esperado
    UNION ALL
    SELECT 'show_id distintos = filas staging',
           (SELECT COUNT(DISTINCT show_id) FROM titles),
           (SELECT COUNT(*) FROM netflix_staging)
    -- Registros huerfanos en tablas asociativas (deben ser 0)
    UNION ALL
    SELECT 'huerfanos title_countries -> titles', COUNT(*), 0
    FROM title_countries tc LEFT JOIN titles t ON t.title_id = tc.title_id
    WHERE t.title_id IS NULL
    UNION ALL
    SELECT 'huerfanos title_countries -> countries', COUNT(*), 0
    FROM title_countries tc LEFT JOIN countries c ON c.country_id = tc.country_id
    WHERE c.country_id IS NULL
    UNION ALL
    SELECT 'huerfanos title_genres -> titles', COUNT(*), 0
    FROM title_genres tg LEFT JOIN titles t ON t.title_id = tg.title_id
    WHERE t.title_id IS NULL
    UNION ALL
    SELECT 'huerfanos title_genres -> genres', COUNT(*), 0
    FROM title_genres tg LEFT JOIN genres g ON g.genre_id = tg.genre_id
    WHERE g.genre_id IS NULL
    UNION ALL
    SELECT 'huerfanos title_people -> titles', COUNT(*), 0
    FROM title_people tp LEFT JOIN titles t ON t.title_id = tp.title_id
    WHERE t.title_id IS NULL
    UNION ALL
    SELECT 'huerfanos title_people -> people', COUNT(*), 0
    FROM title_people tp LEFT JOIN people p ON p.person_id = tp.person_id
    WHERE p.person_id IS NULL
    -- Titulos con rating informado en el CSV pero sin FK resuelta (debe ser 0)
    UNION ALL
    SELECT 'rating del CSV sin FK en titles', COUNT(*), 0
    FROM netflix_staging s JOIN titles t ON t.show_id = s.show_id
    WHERE s.rating IS NOT NULL AND t.rating_id IS NULL
    -- Duracion: todo titulo con duracion en el CSV debe tener valor y unidad
    UNION ALL
    SELECT 'duracion del CSV sin valor/unidad en titles', COUNT(*), 0
    FROM netflix_staging s JOIN titles t ON t.show_id = s.show_id
    WHERE s.duration IS NOT NULL
      AND (t.duration_value IS NULL OR t.duration_unit IS NULL)
) chequeos
ORDER BY estado DESC, chequeo;

-- Resumen de poblacion por tabla (ejecutar aparte si se desea verlo)
-- SELECT 'ratings' AS tabla, COUNT(*) FROM ratings
-- UNION ALL SELECT 'countries', COUNT(*) FROM countries
-- UNION ALL SELECT 'genres', COUNT(*) FROM genres
-- UNION ALL SELECT 'people', COUNT(*) FROM people
-- UNION ALL SELECT 'titles', COUNT(*) FROM titles
-- UNION ALL SELECT 'title_countries', COUNT(*) FROM title_countries
-- UNION ALL SELECT 'title_genres', COUNT(*) FROM title_genres
-- UNION ALL SELECT 'title_people', COUNT(*) FROM title_people;
