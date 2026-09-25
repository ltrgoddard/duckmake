-- oil and gas infrastructure mapped in OpenStreetMap
with elements as (
  select unnest(elements) as e
  from read_json(
    'data/osm.json',
    maximum_object_size = 1e9,
    columns = {elements: 'struct(type varchar, id bigint, lat double, lon double,
      center struct(lat double, lon double), tags map(varchar, varchar))[]'}
  )
)

select
  e.type || '/' || e.id as id,
  coalesce(e.tags['man_made'], 'industrial=' || e.tags['industrial']) as kind,
  e.tags['name'] as name,
  e.tags['operator'] as operator,
  coalesce(e.lat, e.center.lat) as lat,
  coalesce(e.lon, e.center.lon) as lon
from elements
