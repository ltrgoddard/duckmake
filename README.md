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

## How to use it

duckmake is delivered as a single ~150-line `duckmake.mk` file. The recommended
way to use it is to `include` it in your project's existing Makefile, allowing
additional targets for things DuckDB can't do like downloading and extracting
complex source data.

A simple project of mine might:

- Build a table of oil and gas infrastructure for a certain geographic area by
  extracting and combining several Excel files from [Global Energy Monitor](https://globalenergymonitor.org/download-data)
- Build a table of emissions observations from satellite data over the same area
  by querying a remote API, e.g. [Carbon Mapper](https://api.carbonmapper.org/api/v1/docs)
- Attribute observed emissions to infrastructure locations with a spatial join,
  generating a new table of matches as GeoParquet
- Display the resulting table on a map

With duckmake, we might structure this as:

```
.
├── Makefile
├── duckmake.mk
├── data/                        # raw inputs, fetched by Make
│   └── gem/
│       ├── oil-gas-plants.xlsx
│       ├── gas-pipelines.xlsx
│       └── oil-gas-extraction.xlsx
├── macros/
│   └── geo.sql                  # LOAD spatial; CREATE MACRO within_area(...)
├── models/
│   ├── gem/
│   │   ├── plants.sql           # -> build/gem/plants.parquet (gem.plants)
│   │   ├── pipelines.sql
│   │   └── extraction.sql
│   ├── carbonmapper/
│   │   └── plumes.sql           # remote API query, rebuilt when the response changes
│   ├── infrastructure.sql       # union of gem.* tables
│   └── attribution.sql          # spatial join of plumes to infrastructure
├── tests/
│   └── attribution_unique.sql   # rows returned = failures
└── build/                       # generated; one Parquet file per model
    ├── gem/plants.parquet
    ├── ...
    └── attribution.parquet
```

The Makefile includes duckmake and adds the steps DuckDB can't do alone:

```make
AREA ?= permian
export AREA

include duckmake.mk

GEM := $(addprefix data/gem/,oil-gas-plants.xlsx gas-pipelines.xlsx oil-gas-extraction.xlsx)

$(GEM):
	mkdir -p $(@D) && curl -fsSL -o $@ https://example.org/gem/$(@F)

build/gem/%.parquet: | $(GEM)

map: build/attribution.parquet
	duckdb -c "INSTALL spatial; LOAD spatial; \
	  COPY (FROM '$<') TO 'www/attribution.geojson' (FORMAT gdal, DRIVER GeoJSON)"

.PHONY: map
```

Models are plain `SELECT` statements. Files are read directly, and references
to other models use their schema and table names:

```sql
-- models/gem/plants.sql
SELECT "Unit ID" AS id, "Unit Name" AS name,
       ST_Point(Longitude, Latitude) AS geom
FROM st_read('data/gem/oil-gas-plants.xlsx')
WHERE within_area(geom, getenv('AREA'))
```

```sql
-- models/attribution.sql
SELECT p.plume_id, p.emission_rate, i.id AS infrastructure_id, i.type,
       ST_Distance_Sphere(p.geom, i.geom) AS distance_m
FROM carbonmapper.plumes p
JOIN infrastructure i ON ST_DWithin_Spheroid(p.geom, i.geom, 500)
QUALIFY row_number() OVER (PARTITION BY p.plume_id ORDER BY distance_m) = 1
```

```sql
-- tests/attribution_unique.sql
SELECT plume_id FROM attribution GROUP BY plume_id HAVING count(*) > 1
```

`make` builds every table, `make build/attribution.parquet` builds one table and
its dependencies, `make test` runs the tests, `make shell` opens DuckDB with a
view for every model, and `make AREA=bakken` rebuilds the tables that read
`getenv('AREA')`.
