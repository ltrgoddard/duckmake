DUCKDB ?= duckdb
BUILD  ?= build

self   := $(lastword $(MAKEFILE_LIST))
tree   := $(shell find models tests ! -path '* *' \( -type d -o -name '*.sql' \) 2>/dev/null)
dirs   := $(filter-out %.sql,$(tree))
macros := $(sort $(wildcard macros/*.sql))
duckdb := $(DUCKDB) -init /dev/null -bail -list -noheader
run    := $(duckdb) -cmd '.output /dev/null' $(macros:%=-cmd '.read %') -cmd '.output' -c
views   = $(foreach d,$^,$($d.view))
flags   = $(firstword -$(MAKEFLAGS))
quiet   = $(if $(findstring =,$(flags)),,$(findstring s,$(flags)))

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
	@$(if $(filter-out FORCE,$?),,$(run) "$$FRESH" 2>/dev/null ||) { mkdir -p $(@D) && $(run) "$$MATERIALISE"; }

$(tests): test/%: tests/%.sql $(macros)
	@$(run) "$$ASSERT"

shell: export VIEWS = $(views)
shell: $(models)
	@$(DUCKDB) $(macros:%=-cmd '.read %') -cmd "$$VIEWS"

define PLAN
CREATE TABLE src AS
SELECT *, if(kind = 'models', '$(BUILD)/' || stem || '.parquet', 'test/' || stem) AS target,
       lower(if(stem LIKE '%/%', split_part(stem, '/', 1), 'main')) AS schema, lower(parse_filename(stem)) AS name
FROM (SELECT filename AS file, unnest(regexp_extract(filename, '^(models|tests)/(.+)\.sql$$', ['kind', 'stem'])),
             json_serialize_sql(content)::JSON AS ast
      FROM read_text(['models/**/*.sql', 'tests/**/*.sql']));

SELECT error(file || ': ' || coalesce(ast->>'error_message', 'expected one SELECT statement'))
FROM src WHERE json_array_length(ast, '$$.statements') IS DISTINCT FROM 1;
SELECT error(file || ': use only letters, digits, _ - and / in names')
FROM src WHERE NOT regexp_full_match(file, '[\w/-]+\.sql');
SELECT error('duplicate model ' || schema || '.' || name || ': ' || string_agg(file, ', '))
FROM src WHERE kind = 'models' GROUP BY schema, name HAVING count(*) > 1;

SET VARIABLE project = (SELECT to_json(list(ast ORDER BY target)) FROM src);
CREATE TABLE node AS
SELECT target, id, path, fullkey AS loc, value AS v FROM json_tree(getvariable('project'))
JOIN (SELECT target, (row_number() OVER (ORDER BY target) - 1)::VARCHAR AS i FROM src)
  ON i = regexp_extract(fullkey, '^\$$\[(\d+)\]', 1)
WHERE json_extract_string(value, '$$.type') IN ('BASE_TABLE', 'TABLE_FUNCTION')
   OR json_extract_string(value, '$$.function_name') = 'getenv' OR path LIKE '%.cte_map.map';

CREATE TABLE cte AS
SELECT id, path, loc, regexp_replace(path, 'cte_map\.map$$', '') AS scope, lower(v->>'key') AS name,
       coalesce(v->>'$$.value.query.node.type', v->>'$$.value.query_node.type') = 'RECURSIVE_CTE_NODE' AS rec
FROM node WHERE path LIKE '%.cte_map.map';

CREATE TABLE ref AS
SELECT target, loc, lower(v->>'schema_name') AS schema, lower(v->>'table_name') AS name
FROM node WHERE v->>'type' = 'BASE_TABLE';

CREATE TABLE str AS
SELECT target, v->>'table_name' AS s FROM node WHERE v->>'type' = 'BASE_TABLE'
UNION SELECT target, unnest(json_extract_string(v, '$$..value.value')) FROM node WHERE v->>'type' = 'TABLE_FUNCTION';

CREATE TABLE edge AS
SELECT r.target, m.target AS dep FROM ref r
LEFT JOIN src m ON m.kind = 'models' AND m.schema = coalesce(nullif(r.schema, ''), 'main') AND m.name = r.name
WHERE NOT regexp_matches(r.name, '[./]') AND (r.schema <> '' OR NOT EXISTS (
  FROM cte c WHERE c.name = r.name AND starts_with(r.loc, c.scope)
  AND NOT EXISTS (FROM cte d WHERE d.path = c.path AND starts_with(r.loc, d.loc || '.')
                  AND (d.id < c.id OR d.id = c.id AND NOT c.rec))))
UNION SELECT s.target, m.target FROM str s
JOIN src m ON m.kind = 'models' AND (s.s = m.target OR lower(s.s) = m.schema || '.' || m.name);

WITH RECURSIVE reach(target, dep) AS (FROM edge UNION SELECT r.target, e.dep FROM reach r JOIN edge e ON e.target = r.dep)
SELECT error('dependency cycle: ' || string_agg(DISTINCT target, ' ' ORDER BY target))
FROM reach WHERE target = dep HAVING count(*) > 0;

WITH vol AS (
  FROM (SELECT target, 'remote' AS k, s AS x FROM str WHERE regexp_matches(s, '^[a-z][a-z0-9+.-]*://')
        UNION SELECT target, 'env', json_extract_string(v, '$$..value.value')[1] FROM node
        WHERE v->>'function_name' = 'getenv')
  WHERE target LIKE '%.parquet' AND regexp_full_match(x, '[^\s''$$]+'))
SELECT DISTINCT line FROM (
  SELECT kind || ' += ' || target FROM src
  UNION ALL SELECT format('{0}.view := CREATE SCHEMA IF NOT EXISTS "{1}"; CREATE VIEW "{1}"."{2}" AS FROM ''{0}'';',
                          target, schema, name) FROM src WHERE kind = 'models'
  UNION ALL SELECT target || ': ' || coalesce(dep, '$$(dirs)') FROM edge
  UNION ALL SELECT target || ': $$(wildcard ' || s || ')' FROM str
            WHERE regexp_full_match(s, '[\w./*?~-]+\.\w+')
  UNION ALL SELECT target || ': FORCE' FROM vol
  UNION ALL SELECT target || '.' || k || ' += ' || x FROM vol
) t(line) ORDER BY line;
endef

define PRELUDE
$(views)
SET VARIABLE sql = (SELECT content FROM read_text('$<'));
SET VARIABLE fp = md5(concat_ws(chr(10), getvariable('sql'),
  (SELECT string_agg(concat_ws(' ', filename, size, last_modified), chr(10) ORDER BY filename)
   FROM read_blob(regexp_extract_all('$($@.remote)', '\S+'))),
  (SELECT string_agg(n || '=' || coalesce(getenv(n), ''), chr(10) ORDER BY n)
   FROM unnest(regexp_extract_all('$($@.env)', '\S+')) t(n))));
endef

define FRESH
$(PRELUDE)
SELECT error('stale') WHERE getvariable('fp') IS DISTINCT FROM
  (SELECT decode(value) FROM parquet_kv_metadata('$@') WHERE decode(key) = 'duckmake');
endef

define MATERIALISE
$(PRELUDE)
COPY (FROM query(getvariable('sql'))) TO '$@' (FORMAT parquet, KV_METADATA {duckmake: getvariable('fp')});
$(if $(quiet),,SELECT format('{}: {:,} rows', '$@', count(*)) FROM '$@';)
endef

define ASSERT
$(PRELUDE)
SELECT error(format('{}: {:,} failing rows, e.g. {}', '$<', count(*), list(t)[:3]))
FROM query(getvariable('sql')) t HAVING count(*) > 0;
$(if $(quiet),,SELECT '$@: pass';)
endef

export PLAN FRESH MATERIALISE ASSERT
