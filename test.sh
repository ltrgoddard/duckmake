#!/usr/bin/env bash
# end-to-end checks for duckmake.mk: ./test.sh [duckdb] [make]
DUCKDB=${1:-duckdb} MAKE=${2:-make} PORT=$((20000 + RANDOM % 20000)) fails=0
here=$(cd "$(dirname "$0")" && pwd) dir=$(mktemp -d)
cd "$dir" && cp "$here/duckmake.mk" . && echo "include duckmake.mk" > Makefile && mkdir -p models/staging models/marts tests macros seeds www
python3 -m http.server $PORT --bind 127.0.0.1 --directory www >/dev/null 2>&1 & server=$!
trap 'kill $server; wait $server 2>/dev/null; rm -rf "$dir"' EXIT

# t <label> <want> [make args]: want lists the targets that should be made, or is !fragment of an expected error
t() {
  local label=$1 want=$2 out got; shift 2
  out=$($MAKE DUCKDB="$DUCKDB" "$@" 2>&1); sleep 1 # make 3.81 has one-second mtime resolution
  got=$(grep -oE '^(build|test)/[^:]+' <<<"$out" | sort | xargs)
  [[ $want == !* ]] || want=$(xargs -n1 <<<"$want" | sort | xargs)
  if [[ $want == !* && $out == *"${want#!}"* || $want != !* && $got == "$want" ]]; then echo "ok   $label"
  else echo "FAIL $label: want [$want] got [$got]"; sed 's/^/     /' <<<"$out"; fails=$((fails + 1)); fi
}

printf 'id,customer_id,amount\n1,1,10.5\n2,1,20\n3,2,5\n' > seeds/orders.csv
printf 'id,name\n1,ann\n2,bob\n' > seeds/customers.csv
printf 'k,v\na,1\n' > www/remote.csv
echo "CREATE MACRO cents(x) AS (x * 100)::INT;" > macros/cents.sql
echo "CREATE MACRO not_null(t, c) AS TABLE FROM query_table(t) WHERE COLUMNS(c) IS NULL;" > macros/tests.sql
echo "FROM read_csv('seeds/orders.csv')" > models/raw_orders.sql
echo "SELECT id, customer_id, cents(amount) AS amount_cents FROM raw_orders" > models/staging/orders.sql
echo "FROM 'seeds/customers.csv'" > models/staging/customers.sql
echo "FROM staging.customers" > models/customers.sql
echo "FROM read_csv('seeds/*.csv', union_by_name = true)" > models/seeds.sql
echo "FROM read_csv('http://127.0.0.1:$PORT/remote.csv')" > models/remote.sql
cat > models/marts/revenue.sql <<'SQL'
WITH orders AS (FROM staging.orders)
SELECT c.name, sum(orders.amount_cents) AS total, staging.customers.id
FROM orders JOIN staging.customers c ON c.id = orders.customer_id
JOIN staging.customers ON staging.customers.id = c.id
GROUP BY ALL;
SQL
cat > models/marts/shadow.sql <<'SQL'
-- the inner customers is the model, and early reads the model raw_orders, not the later cte
WITH customers AS (FROM customers WHERE id > 0),
     early AS (FROM raw_orders),
     raw_orders AS (FROM early),
     tree AS (WITH RECURSIVE tree AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM tree WHERE n < 3) FROM tree)
SELECT c.name, count(*) AS n, getenv('REGION') AS region
FROM customers c, raw_orders, (SELECT max(n) FROM tree) GROUP BY ALL
SQL
echo "FROM marts.revenue WHERE total < 0" > tests/revenue_positive.sql
echo "FROM not_null('marts.revenue', 'id')" > tests/revenue_ids.sql
echo "FROM remote WHERE v < 0" > tests/remote_ok.sql
export REGION=eu
all="build/customers.parquet build/marts/revenue.parquet build/marts/shadow.parquet build/raw_orders.parquet \
build/remote.parquet build/seeds.parquet build/staging/customers.parquet build/staging/orders.parquet"
tests="test/remote_ok test/revenue_ids test/revenue_positive"

t "clean build" "$all $tests" all test
t "no-op" ""
echo "FROM read_csv('seeds/orders.csv') WHERE id > 0" > models/raw_orders.sql
t "upstream edit" "build/marts/revenue.parquet build/marts/shadow.parquet build/raw_orders.parquet build/staging/orders.parquet"
touch seeds/customers.csv
t "seed edit" "build/customers.parquet build/marts/revenue.parquet build/marts/shadow.parquet build/seeds.parquet build/staging/customers.parquet"
printf 'id,extra\n9,x\n' > seeds/extra.csv
t "new file matching a glob" "build/seeds.parquet"
t "env change" "build/marts/shadow.parquet" REGION=us
t "env unchanged" "" REGION=us
t "env reverted" "build/marts/shadow.parquet"
printf 'k,v\na,1\nb,2\n' > www/remote.csv
t "remote change" "build/remote.parquet"
t "remote unchanged" ""
echo "CREATE MACRO cents(x) AS (x * 100)::BIGINT;" > macros/cents.sql
t "macro edit" "$all"
echo "FROM marts.revenue WHERE total > 0" > tests/fails.sql
t "failing test" "!tests/fails.sql: 2 failing rows" test; rm tests/fails.sql
echo "SELEC 1" > models/bad.sql
t "parse error" "!models/bad.sql: syntax error"
echo "SELECT 1; SELECT 2" > models/bad.sql
t "two statements" "!models/bad.sql: expected one SELECT statement"; rm models/bad.sql
mkdir models/staging/sub && echo "SELECT 1" > models/staging/sub/customers.sql
t "duplicate name" "!duplicate model staging.customers"; rm -r models/staging/sub
echo "FROM b" > models/a.sql && echo "FROM a" > models/b.sql
t "cycle" "!dependency cycle: build/a.parquet build/b.parquet"; rm models/a.sql models/b.sql
echo "SELECT 1" > "models/bad name.sql"
t "bad name" "!models/bad name.sql: use only"; rm "models/bad name.sql"
mv models/customers.sql .
t "deleted dependency" "!shadow.parquet] Error"
mv customers.sql models
t "restored dependency" ""
echo "FROM 'build/customers.parquet'" > models/by_path.sql
t "reference by path" "build/by_path.parquet"
echo "CREATE TABLE lookup AS SELECT 1 AS k;" > macros/lookup.sql && echo "FROM lookup" > models/uses_lookup.sql
t "table from a macro" "$all build/by_path.parquet build/uses_lookup.parquet"
rm macros/lookup.sql
t "deleted macro" "!lookup does not exist"; rm models/uses_lookup.sql
[[ $(echo "SELECT count(*) FROM marts.revenue, staging.orders;" | $MAKE -s DUCKDB="$DUCKDB" shell) == *6* ]] \
  && echo "ok   shell" || { echo "FAIL shell"; fails=$((fails + 1)); }
touch models/customers.sql
t "silent" "" -s
rm -r build
t "parallel" "$all build/by_path.parquet $tests" -j8 all test
t "clean" "" clean; [[ ! -e build ]] || { echo "FAIL clean"; fails=$((fails + 1)); }
exit $fails
