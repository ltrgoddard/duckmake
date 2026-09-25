# duckmake reference

## Requirements

- GNU Make 3.81 or later
- A `duckdb` CLI recent enough for `json_serialize_sql`, `read_text` and
  `parquet_kv_metadata`

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

Set them before `include duckmake.mk` or on the command line.

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

## Names

- `models/<path>.sql` builds `$(BUILD)/<path>.parquet`.
- The schema is the first directory under `models/`, or `main` for files at the
  top level. The table name is the filename without `.sql`. Deeper directories
  do not change either: `models/a/b/c.sql` is `a.c`.
- Names are lowercased. Two models with the same schema and name are an error.
- Paths may contain only letters, digits, `_`, `-` and `/`. Files with spaces
  are ignored by Make and rejected by the plan.

## Dependencies

duckmake parses every model and test with `json_serialize_sql`. A file depends
on:

| In the SQL                           | Dependency                              |
| ------------------------------------ | --------------------------------------- |
| `schema.table` or `table`            | The matching model (`main` if no schema) |
| `'build/x.parquet'` or `'schema.table'` as a string | The matching model       |
| A local file path, e.g. `'data/x.csv'` | That file; a Make rule can create it  |
| A glob or a bare filename, e.g. `'data/*.csv'` | `$(wildcard ...)` of it       |
| `http://`, `s3://` and other URLs    | Checked on every run (see below)        |
| `getenv('NAME')`                     | Checked on every run (see below)        |
| Anything in `macros/`                | Every model and test                    |

CTE names shadow models of the same name within their scope, following
DuckDB's rules. A table name that matches no model or CTE (e.g. one created in
a macro) depends on the `models/` and `tests/` directories, so adding a model
updates the plan.

Dependency cycles are an error.

## Rebuilds

A model is rebuilt when Make finds a dependency newer than its output. A model
that reads a URL or an environment variable is also checked on every run: its
output stores a fingerprint of the SQL, each URL's size and modification time,
and each variable's value in the Parquet metadata. If the fingerprint matches,
the model is not rebuilt.

A failed build deletes its partial output.

## Output

Each built model prints `<target>: <n> rows`. Each passing test prints
`test/<path>: pass`. A failing test prints its row count and up to three
example rows, and stops Make.

## Errors

The plan stops with a message for:

- A file that does not parse, or has more or less than one statement
- A path with characters other than letters, digits, `_`, `-` and `/`
- A duplicate model name
- A dependency cycle

## Include in a Makefile

```make
export NAME ?= value  # visible to getenv('NAME')
include duckmake.mk

data/x.csv:           # rules for inputs DuckDB cannot fetch
	curl -o $@ https://example.org/x.csv
```

Define extra targets after the `include` so that `all` stays the default.
