-- oil and gas infrastructure mapped in OpenStreetMap
WITH elements AS (
  SELECT unnest(elements) AS e FROM read_json('data/osm.json', maximum_object_size = 1e9,
    columns = {elements: 'STRUCT(type VARCHAR, id BIGINT, lat DOUBLE, lon DOUBLE,
               center STRUCT(lat DOUBLE, lon DOUBLE), tags MAP(VARCHAR, VARCHAR))[]'})
)
SELECT e.type || '/' || e.id AS id, coalesce(e.tags['man_made'], 'industrial=' || e.tags['industrial']) AS kind,
       e.tags['name'] AS name, e.tags['operator'] AS operator,
       coalesce(e.lat, e.center.lat) AS lat, coalesce(e.lon, e.center.lon) AS lon
FROM elements
