# netflix-postgresql

Normalización (1FN → 3FN) del catálogo de Netflix en **PostgreSQL**.
Taller de laboratorio de bases de datos.

## Contexto

Partimos del archivo plano `netflix_titles.csv` (8.807 títulos, dataset de
[Kaggle](https://www.kaggle.com/datasets/shivamb/netflix-titles)), que mezcla en una sola
fila datos multivaluados (elenco, directores, países, géneros). El proyecto lo normaliza a
3FN, carga los datos con un ETL en SQL y plantea consultas `JOIN` sobre el modelo resultante.

## Integrantes

- Michael
- Sergio
- Georgy

## Estructura del proyecto

```
PostgreSQL_netflix/
├── data/
│   └── netflix_titles.csv           # dataset fuente
├── diagram/
│   └── modelo_entidad_relacion.png  # diagrama entidad-relación (3FN)
├── sql/
│   ├── 01_creacion_base_datos.sql   # DDL: base de datos, staging y tablas
│   ├── 02_carga_datos.sql           # ETL: staging -> esquema normalizado + chequeos
│   └── 03_consultas_join.sql        # consultas JOIN (A y B)
├── dump/
│   └── netflix_db.dump              # respaldo restaurable (estructura + datos)
├── docker-compose.yml               # PostgreSQL + pgAdmin
└── README.md
```
