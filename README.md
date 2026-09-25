# duckmake

duckmake is a minimal, highly opinionated build system for local DuckDB
projects, inspired by [dbt](https://www.getdbt.com/) and implemented as a short
Makefile. Write interlinked `SELECT` queries in an organised directory of SQL
files; duckmake parses them into a dependency graph using DuckDB's
`json_serialize_sql` function and builds a corresponding directory of Parquet
tables. See [`example/`](example/) for a project that builds from public data, and
[REFERENCE.md](REFERENCE.md) for the full interface.

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
complex source data.
