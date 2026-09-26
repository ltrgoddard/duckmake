DUCKDB ?= duckdb
BUILD  ?= build

self   := $(lastword $(MAKEFILE_LIST))
tree   := $(shell find models tests ! -path '* *' \( -type d -o -name '*.sql' \) 2>/dev/null)
dirs   := $(filter-out %.sql,$(tree))
macros := $(sort $(wildcard macros/*.sql))
duckdb := $(DUCKDB) -init /dev/null -bail -list -noheader
run    := $(duckdb) -cmd '.output /dev/null' $(macros:%=-cmd '.read %') -cmd '.output' -c
views   = $(foreach d,$^,$($d.view))
flags   = $(if $(findstring =,$(firstword $(MAKEFLAGS))),,$(firstword -$(MAKEFLAGS)))
quiet   = $(findstring s,$(flags))

all:
clean: ; rm -rf $(BUILD)
.PHONY: all test shell clean FORCE
.DELETE_ON_ERROR:

ifneq ($(filter-out clean,$(or $(MAKECMDGOALS),all)),)
include $(BUILD)/plan.mk
endif

all: $(models)
test: $(tests)
.PHONY: $(tests)

$(BUILD)/plan.mk: $(self) $(tree)
	@mkdir -p $(@D) && $(duckdb) -c "$$PLAN" > $@

$(BUILD)/%.parquet: models/%.sql $(wildcard macros) $(macros)
	@$(if $(filter-out FORCE,$?)$(findstring B,$(flags)),,$(run) "$$FRESH" 2>/dev/null ||) { mkdir -p $(@D) && $(run) "$$MATERIALISE"; }

$(tests): test/%: tests/%.sql $(macros)
	@$(run) "$$ASSERT"

shell: export VIEWS = $(views)
shell: $(models)
	@$(DUCKDB) $(macros:%=-cmd '.read %') -cmd "$$VIEWS"

define PLAN
create table src as
select
  *,
  if(kind = 'models', '$(BUILD)/' || stem || '.parquet', 'test/' || stem) as target,
  lower(if(stem like '%/%', split_part(stem, '/', 1), 'main')) as schema,
  lower(parse_filename(stem)) as name
from (
  select
    filename as file,
    unnest(regexp_extract(filename, '^(models|tests)/(.+)\.sql$$', ['kind', 'stem'])),
    json_serialize_sql(content, skip_null := true, skip_empty := true)::json as ast
  from read_text(['models/**/*.sql', 'tests/**/*.sql'])
);

select error(file || ': ' || coalesce(ast->>'error_message', 'expected one SELECT statement'))
from src
where json_array_length(ast, '$$.statements') is distinct from 1;

select error(file || ': use only letters, digits, _ - and / in names')
from src
where not regexp_full_match(file, '[\w/-]+\.sql');

select error('duplicate model ' || schema || '.' || name || ': ' || string_agg(file, ', '))
from src
where kind = 'models'
group by schema, name
having count(*) > 1;

create table node as
select target, id, path, fullkey as loc, value as v
from src, json_tree(ast)
where json_extract_string(value, '$$.type') in ('BASE_TABLE', 'TABLE_FUNCTION')
  or json_extract_string(value, '$$.function_name') = 'getenv'
  or path like '%.cte_map.map';

create table cte as
select
  target, id, path, loc,
  regexp_replace(path, 'cte_map\.map$$', '') as scope,
  lower(v->>'key') as name,
  coalesce(v->>'$$.value.query.node.type', v->>'$$.value.query_node.type') = 'RECURSIVE_CTE_NODE' as rec
from node
where path like '%.cte_map.map';

create table ref as
select target, loc, lower(coalesce(v->>'schema_name', '')) as schema, lower(v->>'table_name') as name
from node
where v->>'type' = 'BASE_TABLE';

create table str as
select target, v->>'table_name' as s
from node
where v->>'type' = 'BASE_TABLE'
union
select target, unnest(if(
  a->>'function_name' = 'list_value',
  json_extract_string(a, '$$.children[*].value.value'),
  [a->>'$$.value.value']
))
from (select target, v->'$$.function.children[0]' as a from node where v->>'type' = 'TABLE_FUNCTION');

create table pat as
select
  target, s,
  replace(replace(replace(replace(replace(s, '.', '\.'), '**/', '%'), '*', '[^/]*'), '?', '[^/]'), '%', '(.*/)?') as re
from str
where regexp_full_match(s, '[\w./~-]*[*?][\w./*?~-]*');

create table edge as
select r.target, m.target as dep
from ref as r
left join src as m
  on m.kind = 'models'
  and m.schema = coalesce(nullif(r.schema, ''), 'main')
  and m.name = r.name
where not regexp_matches(r.name, '[./]')
  and (r.schema <> '' or not exists (
    from cte as c
    where c.target = r.target
      and c.name = r.name
      and starts_with(r.loc, c.scope)
      and not exists (
        from cte as d
        where d.target = c.target
          and d.path = c.path
          and starts_with(r.loc, d.loc || '.')
          and (d.id < c.id or d.id = c.id and not c.rec)
      )
  ))
union
select s.target, m.target
from str as s
join src as m on m.kind = 'models' and s.s = m.target
union
select s.target, m.target
from str as s
join src as m on m.kind = 'models' and lower(s.s) = m.schema || '.' || m.name
union
select g.target, m.target
from pat as g
join src as m on m.kind = 'models' and m.target <> g.target and regexp_full_match(m.target, g.re);

with recursive reach(target, dep) as (
  from edge
  union
  select r.target, e.dep
  from reach as r
  join edge as e on e.target = r.dep
)
select error('dependency cycle: ' || string_agg(distinct target, ' ' order by target))
from reach
where target = dep
having count(*) > 0;

with vol as (
  from (
    select target, 'sources' as k, s as x
    from str
    where regexp_matches(s, '^[a-z][a-z0-9+.-]*://')
    union
    select target, 'sources', s
    from pat
    union
    select target, 'env', v->>'$$.children[0].value.value'
    from node
    where v->>'function_name' = 'getenv'
  )
  where target like '%.parquet'
    and not regexp_matches(x, '\s')
)
select distinct line
from (
  select kind || ' += ' || target from src
  union all
  select format(
    '{0}.view := create schema if not exists "{1}"; create view "{1}"."{2}" as from ''{0}'';',
    target, schema, name
  )
  from src
  where kind = 'models'
  union all
  select target || ': ' || coalesce(dep, '$$(dirs)') from edge
  union all
  select target || ': ' || if(regexp_matches(s, '[*?]') or not contains(s, '/'), '$$(wildcard ' || s || ')', s)
  from str
  where regexp_full_match(s, '[\w./*?~-]+\.\w+')
  union all
  select target || ': FORCE' from vol
  union all
  select target || '.' || k || ' += ' || replace(replace(replace(x, '''', ''''''), '$$', '$$$$'), '#', '\#')
  from vol
) as t(line)
order by line;
endef

define PRELUDE
$(views)
set variable sql = (select content from read_text('$<'));
set variable fp = md5(concat_ws(
  chr(10),
  getvariable('sql'),
  (
    select string_agg(concat_ws(' ', filename, size, last_modified), chr(10) order by filename)
    from read_blob(regexp_extract_all('$($@.sources)', '\S+'))
  ),
  (
    select string_agg(n || '=' || coalesce(getenv(n), ''), chr(10) order by n)
    from unnest(regexp_extract_all('$($@.env)', '\S+')) as t(n)
  )
));
endef

define FRESH
$(PRELUDE)
select error('stale')
where getvariable('fp') is distinct from (
  select decode(value)
  from parquet_kv_metadata('$@')
  where decode(key) = 'duckmake'
);
endef

define MATERIALISE
$(PRELUDE)
copy (from query(getvariable('sql'))) to '$@' (format parquet, use_tmp_file true, kv_metadata {duckmake: getvariable('fp')});
$(if $(quiet),,select format('{}: {:,} rows', '$@', count(*)) from '$@';)
endef

define ASSERT
$(PRELUDE)
select error(format('{}: {:,} failing rows, e.g. {}', '$<', count(*), list(t)[:3]))
from query(getvariable('sql')) as t
having count(*) > 0;
$(if $(quiet),,select '$@: pass';)
endef

export PLAN FRESH MATERIALISE ASSERT
