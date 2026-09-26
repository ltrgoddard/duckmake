# duckdb.mk reference

## Requirements

- GNU Make 3.81 or later
- The `duckdb` CLI, version 1.4 or later

## Project layout

| Path                | Role                                                  |
| ------------------- | ----------------------------------------------------- |
| `models/**/*.sql`   | One `SELECT` statement per file, built to Parquet     |
| `tests/**/*.sql`    | One `SELECT` statement per file, failing if it returns rows |
| `macros/*.sql`      | Any SQL, run before every model, test and shell       |
| `$(BUILD)/`         | Output tables and the generated `plan.mk`             |

All directories are optional. Run `make` from the project root.

## Variables

| Variable | Default  | Meaning                     |
| -------- | -------- | --------------------------- |
| `DUCKDB` | `duckdb` | DuckDB executable           |
| `BUILD`  | `build`  | Output directory            |

Set them before the `include` or on the command line.

## Targets

| Target                   | Action                                               |
| ------------------------ | ---------------------------------------------------- |
| `all` (default)          | Build every model                                    |
| `$(BUILD)/<path>.parquet` | Build one model and its dependencies                |
| `test`                   | Build the models that tests need, then run all tests |
| `test/<path>`            | Run one test                                         |
| `shell`                  | Build every model, then open DuckDB with macros and a view per model |
| `clean`                  | Remove `$(BUILD)`                                    |

Standard Make flags apply: `-j` builds in parallel, `-s` hides row counts and
test passes, `-n` shows what would run.

Every run also writes the dependency graph to `$(BUILD)/dag.mmd` as a
[Mermaid](https://mermaid.js.org) flowchart of models, tests and sources.

## Names

- `models/<path>.sql` builds `$(BUILD)/<path>.parquet`.
- The schema is the first directory under `models/`, or `main` for files at the
  top level. The table name is the filename without .sql. Deeper directories
  do not change either: `models/a/b/c.sql` is `a.c`.
- Names are lowercased. Two models with the same schema and name are an error.
- Paths may contain only letters, digits, `_`, `-` and `/`. Files with spaces
  are ignored by Make and rejected by the plan.

## Dependencies

duckdb.mk parses every model and test with `json_serialize_sql`. A file depends
on:

| In the SQL                           | Dependency                              |
| ------------------------------------ | --------------------------------------- |
| `schema.table` or `table`            | The matching model (`main` if no schema) |
| `'build/x.parquet'` or `'schema.table'` as a string | The matching model       |
| A local file path, e.g. `'data/x.csv'` | That file; a Make rule can create it  |
| A bare filename, e.g. `'x.csv'`      | `$(wildcard ...)` of it                 |
| A glob, e.g. `'data/*.csv'` or `'build/marts/*.parquet'` | `$(wildcard ...)` of it and every model it matches; checked on every run |
| `http://`, `s3://` and other URLs    | Checked on every run (see below)        |
| `getenv('NAME')`                     | Checked on every run (see below)        |
| Anything in `macros/`                | Every model and test                    |

Strings count where DuckDB reads them as sources: as a table name
(`from 'data/x.csv'`) or as the first argument of a table function, alone or in
a list (`read_csv(['a.csv', 'b.csv'])`). A URL built at run time, such as
`'https://example.org/?key=' || getenv('KEY')`, is not checked, but the
variable is.

CTE names shadow models of the same name within their scope, following
DuckDB's rules. A table name that matches no model or CTE (e.g. one created in
a macro) depends on the `models/` and `tests/` directories, so adding a model
updates the plan.

Dependency cycles are an error.

## Rebuilds

A model is rebuilt when Make finds a dependency newer than its output. A model
that reads a URL, a glob or an environment variable is also checked on every
run: its output stores a fingerprint of the SQL, the size and modification time
of each URL and each file matching each glob, and each variable's value in the
Parquet metadata. If the fingerprint matches, the model is not rebuilt, and
nothing that depends on it is either. Checking a URL costs a `HEAD` request;
one from a server that sends no `Last-Modified` header is compared by size
alone.

Outputs are written to a temporary file and moved into place, so a failed or
interrupted build leaves the previous output, and the next run tries again.

## Output

Each built model prints `<target>: <n> rows`. Each passing test prints
`test/<path>: pass`. A failing test prints its row count and its three
smallest rows as examples, and stops Make.

## Errors

The plan stops with a message for:

- A file that does not parse, or is not exactly one `SELECT` statement
  (DuckDB cannot yet serialise `PIVOT`, even in a subquery: pivot with
  aggregate `filter` clauses instead)
- A path with characters other than letters, digits, `_`, `-` and `/`
- A duplicate model name
- A dependency cycle

## Include in a Makefile

```make
# visible to getenv('NAME')
export NAME ?= value
# a branch or tag
DUCKDB_MK = v0.1.1
include .duckdb.mk/$(DUCKDB_MK)/duckdb.mk
.duckdb.mk/%/duckdb.mk:
	curl -sSfL --create-dirs -o $@ \
	  https://raw.githubusercontent.com/ltrgoddard/duckdb.mk/$*/duckdb.mk

data/x.csv:           # rules for inputs DuckDB cannot fetch
	curl -o $@ https://example.org/x.csv
```

Define extra targets after the `include` so that `all` stays the default.
Make downloads `.duckdb.mk/$(DUCKDB_MK)/duckdb.mk` once; delete that directory
to update a branch. Tags are listed on the [releases page](https://github.com/ltrgoddard/duckdb.mk/releases).
A local copy also works: `include duckdb.mk`.
