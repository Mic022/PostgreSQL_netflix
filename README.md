# netflix-postgresql

Normalización (1FN → 3FN) del catálogo de Netflix en **PostgreSQL**.
Taller de laboratorio de bases de datos.

## Contexto

Partimos del archivo plano `netflix_titles.csv` (8.807 títulos, dataset de
[Kaggle](https://www.kaggle.com/datasets/shivamb/netflix-titles)), que
mezcla en una sola fila datos multivaluados (elenco, directores, países,
géneros). El proyecto lo normaliza a 3FN, carga los datos con SQL y
plantea consultas JOIN sobre el modelo resultante.

## Integrantes

- michael
- sergio
- Georgy

## Estructura del proyecto

```
PostgreSQL_netflix/
├── data/
│   └── netflix_titles.csv       # dataset fuente
├── sql_1/
│   ├── 02_carga_datos.sql       # ETL: staging -> esquema normalizado
│   └── 03_consultas_join.sql    # consultas JOIN
└── README.md
```
