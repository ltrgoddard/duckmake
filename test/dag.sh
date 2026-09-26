# the dag target: the mermaid flowchart the plan writes to build/dag.mmd
mkdir -p models/s tests data && printf 'id\n1\n' > data/x.csv
echo "from read_csv('data/x.csv')" > models/a.sql
echo "from a, read_csv('http://example.org/it''s#\$1.csv')" > models/s/Up.sql
echo "from read_csv('data/*.csv') where getenv('X') is null" > models/glob.sql
echo "select 1 as id" > models/lone.sql
echo "from lookup" > models/macro.sql
echo "from s.up where id < 0" > tests/t.sql
echo "select 1 as id where false" > tests/none.sql
is "flowchart" "$($MAKE -s DUCKDB="$DUCKDB" dag)" 'flowchart LR
  n10{{"test/t"}}
  n1["main.a"]
  n2["main.glob"]
  n3["main.lone"]
  n4["main.macro"]
  n5["s.up"]
  n6[("data/*.csv")]
  n7[("data/x.csv")]
  n8[("http://example.org/it'"'"'s#$1.csv")]
  n9{{"test/none"}}
  n1 --> n5
  n5 --> n10
  n6 --> n2
  n7 --> n1
  n8 --> n5'
t "builds nothing" "" dag
