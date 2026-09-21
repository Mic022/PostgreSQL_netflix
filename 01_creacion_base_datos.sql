-- =====================================================================
-- 01_creacion_base_datos.sql
-- Taller de Normalizacion - Catalogo Audiovisual de Netflix
-- Fase III: Definicion del Esquema Fisico (DDL)
--
-- Responsable: Sergio (implementacion SQL: DDL, ETL y consultas)
--
-- Crea la base de datos netflix_db, la tabla de transito
-- (netflix_staging) y el esquema relacional normalizado hasta 3FN.
--
-- Ejecucion recomendada (desde la raiz del repositorio):
--   psql -h localhost -p 5432 -U admin -d postgres -f sql/01_creacion_base_datos.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Creacion de la base de datos
-- ---------------------------------------------------------------------
-- DROP DATABASE IF EXISTS netflix_db;  -- descomentar para reinicios limpios
CREATE DATABASE netflix_db
    WITH ENCODING 'UTF8';


-- A partir de aqui, todas las sentencias se ejecutan dentro de netflix_db.
-- Si se corre este archivo completo con psql, \connect cambia de sesion.
\connect netflix_db


-- ---------------------------------------------------------------------
-- 2. Tabla de transito (staging) para el proceso ETL
-- ---------------------------------------------------------------------
-- Refleja el CSV fuente tal cual, sin tipar ni normalizar, para permitir
-- una carga masiva simple (COPY/\copy) y transformaciones posteriores
-- en SQL puro (Fase IV).
DROP TABLE IF EXISTS netflix_staging;
CREATE TABLE netflix_staging (
    staging_id      SERIAL PRIMARY KEY,
    show_id         TEXT,
    type            TEXT,
    title           TEXT,
    director        TEXT,
    cast_members    TEXT,
    country         TEXT,
    date_added      TEXT,
    release_year    TEXT,
    rating          TEXT,
    duration        TEXT,
    listed_in       TEXT,
    description     TEXT
);

COMMENT ON TABLE netflix_staging IS
    'Tabla de transito temporal para el ETL de netflix_titles.csv (Fase IV).';

-- ---------------------------------------------------------------------
-- 3. Tablas maestras / catalogos independientes
-- ---------------------------------------------------------------------

-- Clasificaciones por edad (rating): G, PG, PG-13, R, TV-MA, etc.
DROP TABLE IF EXISTS ratings CASCADE;
CREATE TABLE ratings (
    rating_id       SERIAL PRIMARY KEY,
    code            VARCHAR(10)  NOT NULL UNIQUE,
    description     VARCHAR(120)
);
COMMENT ON TABLE ratings IS 'Catalogo de clasificaciones por edad/audiencia.';

-- Paises de origen de la produccion
DROP TABLE IF EXISTS countries CASCADE;
CREATE TABLE countries (
    country_id      SERIAL PRIMARY KEY,
    country_name    VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE countries IS 'Catalogo de paises de origen de las producciones.';

-- Generos / categorias tematicas (antes "listed_in")
DROP TABLE IF EXISTS genres CASCADE;
CREATE TABLE genres (
    genre_id        SERIAL PRIMARY KEY,
    genre_name      VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE genres IS 'Catalogo de generos/categorias audiovisuales.';

-- Personas: directores e interpretes (rol desacoplado, participacion cruzada)
DROP TABLE IF EXISTS people CASCADE;
CREATE TABLE people (
    person_id       SERIAL PRIMARY KEY,
    full_name       VARCHAR(200) NOT NULL UNIQUE
);
COMMENT ON TABLE people IS
    'Catalogo unico de personas; una misma persona puede participar como director y/o actor.';

-- ---------------------------------------------------------------------
-- 4. Entidad principal: titulos y producciones audiovisuales
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS titles CASCADE;
CREATE TABLE titles (
    title_id        SERIAL PRIMARY KEY,
    show_id         VARCHAR(10)  NOT NULL UNIQUE,           -- id original del CSV (trazabilidad)
    title_type      VARCHAR(10)  NOT NULL
                        CHECK (title_type IN ('Movie', 'TV Show')),
    title_name      VARCHAR(300) NOT NULL,
    date_added      DATE,
    release_year    SMALLINT     NOT NULL
                        CHECK (release_year BETWEEN 1900 AND 2100),
    rating_id       INTEGER REFERENCES ratings(rating_id),
    duration_value  NUMERIC(6,1) CHECK (duration_value > 0),
    duration_unit   VARCHAR(10)  CHECK (duration_unit IN ('min', 'season')),
    description     TEXT,
    -- Coherencia semantica entre el tipo de produccion y la unidad de duracion
    CONSTRAINT chk_duration_unit_matches_type CHECK (
        (title_type = 'Movie'   AND (duration_unit = 'min'    OR duration_unit IS NULL)) OR
        (title_type = 'TV Show' AND (duration_unit = 'season' OR duration_unit IS NULL))
    )
);
COMMENT ON TABLE titles IS
    'Entidad principal: peliculas y series de television (diferenciadas por title_type).';
COMMENT ON COLUMN titles.show_id IS 'Identificador original de netflix_titles.csv (s1, s2, ...).';
COMMENT ON COLUMN titles.duration_value IS 'Valor cuantitativo de la duracion (minutos o temporadas).';
COMMENT ON COLUMN titles.duration_unit  IS 'Unidad de medida de duration_value: min | season.';

CREATE INDEX idx_titles_release_year ON titles(release_year);
CREATE INDEX idx_titles_title_name   ON titles(title_name);
CREATE INDEX idx_titles_rating_id    ON titles(rating_id);

-- ---------------------------------------------------------------------
-- 5. Tablas asociativas (relaciones N:M)
-- ---------------------------------------------------------------------

-- Titulo <-> Pais (un titulo puede coproducirse en varios paises)
DROP TABLE IF EXISTS title_countries;
CREATE TABLE title_countries (
    title_id    INTEGER NOT NULL REFERENCES titles(title_id)   ON DELETE CASCADE,
    country_id  INTEGER NOT NULL REFERENCES countries(country_id) ON DELETE RESTRICT,
    PRIMARY KEY (title_id, country_id)
);
CREATE INDEX idx_title_countries_country ON title_countries(country_id);

-- Titulo <-> Genero (un titulo puede pertenecer a varias categorias)
DROP TABLE IF EXISTS title_genres;
CREATE TABLE title_genres (
    title_id    INTEGER NOT NULL REFERENCES titles(title_id) ON DELETE CASCADE,
    genre_id    INTEGER NOT NULL REFERENCES genres(genre_id) ON DELETE RESTRICT,
    PRIMARY KEY (title_id, genre_id)
);
CREATE INDEX idx_title_genres_genre ON title_genres(genre_id);

-- Titulo <-> Persona, con rol (Director | Actor). Permite participacion
-- cruzada: la misma persona puede figurar como Director en un titulo y
-- como Actor en otro (o incluso ambos roles en el mismo titulo).
DROP TABLE IF EXISTS title_people;
CREATE TABLE title_people (
    title_id    INTEGER NOT NULL REFERENCES titles(title_id)  ON DELETE CASCADE,
    person_id   INTEGER NOT NULL REFERENCES people(person_id) ON DELETE RESTRICT,
    role        VARCHAR(10) NOT NULL CHECK (role IN ('Director', 'Actor')),
    PRIMARY KEY (title_id, person_id, role)
);
CREATE INDEX idx_title_people_person ON title_people(person_id);
CREATE INDEX idx_title_people_role   ON title_people(role);

-- ---------------------------------------------------------------------
-- Fin del script de creacion de esquema
-- ---------------------------------------------------------------------
