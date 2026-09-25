# Example: methane plumes and oil and gas infrastructure in New Mexico

This project matches methane plumes observed by
[Carbon Mapper](https://carbonmapper.org/) to the nearest oil and gas facility
mapped in [OpenStreetMap](https://www.openstreetmap.org/), and summarises the
matches by facility type and county. All inputs are fetched live from public
sources and need no account.

```sh
cd example
make                # fetch the data and build every table
make test           # run the tests
make shell          # query the tables in DuckDB
make RADIUS=100     # rebuild the matches with a 100 m search radius
```

The first run takes a few minutes, mostly for the Carbon Mapper and Overpass
APIs. Delete `data/` to fetch the data again.

## Sources

| Source | Access | Model |
| ------ | ------ | ----- |
| Carbon Mapper plume catalogue | API, paged by a Make rule to `data/plumes.json` | `carbonmapper.plumes` |
| OpenStreetMap, via the Overpass API | Query in `queries/osm.overpassql`, fetched by a Make rule to `data/osm.json` | `osm.facilities` |
| Census county boundaries | Shapefile, downloaded and unzipped by a Make rule | `census.counties` |
| Census county codes | Text file, read directly by DuckDB over HTTPS | `census.fips` |

## Layout

```
.
├── Makefile               # sets RADIUS, fetches the files in data/
├── queries/osm.overpassql # the OpenStreetMap query
├── macros/
│   ├── geo.sql            # metres(): great-circle distance
│   └── spatial.sql        # loads the spatial extension
├── models/
│   ├── census/fips.sql
│   ├── census/counties.sql       # refers to census.fips
│   ├── carbonmapper/plumes.sql   # refers to census.counties
│   ├── osm/facilities.sql
│   ├── matches.sql               # main.matches: plumes to facilities
│   ├── summary/by_kind.sql       # refers to matches
│   └── summary/by_county.sql     # refers to matches
└── tests/
    ├── emissions_positive.sql
    └── matches_unique.sql
```

## Features shown

- **References.** Models refer to each other as `schema.table`, or by name
  alone for the `main` schema (`matches`). CTEs such as `items` and `plumes` in
  `carbonmapper/plumes.sql` shadow nothing outside their query.
- **Make rules for inputs.** The files in `data/` are made by rules in the
  Makefile the first time that a model needs them. The Overpass rule depends
  on `queries/osm.overpassql`, so an edit to the query fetches the data again and
  rebuilds `osm.facilities` and everything downstream.
- **Remote inputs.** `census/fips.sql` reads a URL. duckmake checks the size
  and modification time of the file on every run, and rebuilds only when the
  file changes.
- **Environment variables.** `matches.sql` reads `getenv('RADIUS')`. A change to
  it rebuilds `matches` and the two summaries, and nothing else.
- **Macros.** `macros/` loads an extension and defines a function for every
  model and test. An edit to a macro rebuilds everything.
- **Tests.** Each file in `tests/` returns the rows that break a rule.
