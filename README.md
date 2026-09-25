# duckmake

duckmake is a minimal, highly opinionated build system for local DuckDB
projects, inspired by [dbt](https://www.getdbt.com/) and implemented as a short
Makefile. Write interlinked `SELECT` queries in an organised directory of SQL
files; duckmake parses them into a dependency graph using DuckDB's
`json_serialize_sql` function and builds a corresponding directory of Parquet
tables.

DuckDB and Make are both wonderful 'Swiss army knife' tools -- together, they
make it extremely easy to build multi-stage data pipelines querying local and
external sources, e.g. for research or analytical dashboards. duckmake is a
formalisation of a rough approach that I've developed over many years of working
on *ad hoc* data journalism and corporate research projects at NGOs.

## How it works

duckmake implements the four features that represent 99% of my own dbt use:

- Individual `SELECT` queries map one-to-one to output tables
- A query in one file can refer to the output table from another
- Tables are rebuilt like Make targets, including their dependencies
- Settings can be controlled through project-level variables

Unlike dbt, duckmake requires no configuration or hand-maintained metadata:
table and schema names are derived from filenames and directories, while
internal references are resolved automatically (no need for dbt's
`ref("model")`).

This project does not aim to implement the 'full fat' features of dbt like
incremental rebuilds, automated documentation and tight integration with remote
data warehouses. It's aimed at individual data engineers and small teams who
want to build neat, reproducible data pipelines that run on a single machine.

duckmake is delivered as a single ~150-line `duckmake.mk` file. The recommended
way to use it is to `include` it in your project's existing Makefile, allowing
additional targets for things DuckDB can't do like downloading and extracting
complex source data. See [Example usage](#example-usage) for a simplified project.

## Example usage

A simple project of mine might:

- Build a table of oil and gas infrastructure for a certain geographic area by
  extracting and combining several Excel files from [Global Energy Monitor](https://globalenergymonitor.org/download-data)
- Build a table of emissions observations from satellite data over the same area
  by querying a remote API, e.g. [Carbon Mapper](https://api.carbonmapper.org/api/v1/docs)
- Attribute observed emissions to infrastructure locations with a spatial join,
  generating a new table of matches as GeoParquet
- Display the resulting table on a map

With duckmake, we could structure this like:

```
.
├── Makefile
├── duckmake.mk
├── data/
│   └── plants.xlsx          # downloaded by Make
├── macros/
│   └── spatial.sql          # INSTALL spatial; LOAD spatial;
├── models/
│   ├── gem/
│   │   └── plants.sql       # -> build/gem/plants.parquet
│   ├── carbonmapper/
│   │   └── plumes.sql       # -> build/carbonmapper/plumes.parquet
│   └── matches.sql          # -> build/matches.parquet
└── tests/
    └── matches.sql          # any rows returned are failures
```

Models are plain `SELECT` statements, and refer to each other by schema and
table name:

```sql
-- models/gem/plants.sql
SELECT id, name, ST_Point(lon, lat) AS geom
FROM st_read('data/plants.xlsx')
WHERE country = getenv('COUNTRY')
```

```sql
-- models/matches.sql
SELECT plumes.id AS plume_id, plants.id AS plant_id
FROM carbonmapper.plumes
JOIN gem.plants ON ST_DWithin(plumes.geom, plants.geom, 0.01)
```

```sql
-- tests/matches.sql
SELECT plume_id FROM matches GROUP BY plume_id HAVING count(*) > 1
```

The Makefile includes duckmake and adds anything DuckDB can't do:

```make
export COUNTRY ?= US

include duckmake.mk

data/plants.xlsx:
	curl -o $@ https://example.org/plants.xlsx

build/gem/plants.parquet: data/plants.xlsx
```

`make` builds every table, `make build/matches.parquet` builds one table and
its dependencies, `make test` runs the tests, `make shell` opens DuckDB with a
view for every model, and `make COUNTRY=CA` rebuilds the tables that read
`getenv('COUNTRY')`.
