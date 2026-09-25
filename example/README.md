# Example: unreported flaring in New Mexico

This project compares gas flares seen from space with the flaring reports that
operators file with the New Mexico Oil Conservation Division (OCD). It finds
each flaring episode with no report nearby, and names the operator of the
nearest well. All inputs are public.

```sh
cd example
make            # build every table (about 15 s on first run)
make test       # run the tests
make shell      # query the tables in DuckDB
make START=2025-06-01  # rebuild from a later start date
```

## Sources

- [VIIRS Nightfire](https://eogdata.mines.edu/products/vnf/) flare detections
  and OCD release reports and well register, from the public
  [Data Desk archive](https://s3.WAW3-2.cloudferro.com/data-desk-archive)
- US county boundaries from the [Census Bureau](https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html),
  downloaded by the Makefile

## Layout

```
.
├── Makefile                 # sets START, downloads data/counties.shp
├── macros/
│   ├── geo.sql              # metres(): great-circle distance
│   └── spatial.sql          # loads the spatial extension
├── models/
│   ├── census/counties.sql  # local file made by a Make rule
│   ├── ocd/reports.sql      # remote file, filtered on getenv('START')
│   ├── ocd/wells.sql        # remote file
│   ├── viirs/nights.sql     # remote file, filtered on getenv('START')
│   ├── flaring/episodes.sql # nights grouped into episodes, CTEs, spatial join
│   ├── flaring/unreported.sql  # episodes with no report within 1 km, 7 days
│   └── operators.sql        # main.operators: unreported episodes by operator
└── tests/
    ├── episodes_ordered.sql
    └── unreported_unique.sql
```

## Features shown

- **Remote inputs.** The models in `ocd/` and `viirs/` read Parquet over HTTPS.
  duckmake checks the size and modification time of each file on every run,
  and rebuilds a model only when the file changes.
- **Environment variables.** `START` is read with `getenv('START')`. A change to
  it rebuilds only the models that read it, and the models that depend on them.
- **Make rules for inputs.** `data/counties.shp` is created by a rule in the
  Makefile the first time that `census/counties.sql` needs it.
- **Macros.** `macros/` loads an extension and defines a function for every
  model and test.
- **References.** Models refer to each other as `schema.table`. The CTEs `nights` and `numbered`
  in `flaring/episodes.sql` do not create dependencies.
