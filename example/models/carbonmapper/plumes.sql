-- methane plumes over New Mexico from aircraft and satellite surveys
with items as (
  select unnest(items) as p
  from read_json('data/plumes.json', maximum_object_size = 1e9)
),

plumes as (
  select
    p.plume_id as id,
    p.scene_timestamp::timestamp as observed,
    p.platform,
    p.emission_auto as kg_h,
    p.geometry_json.coordinates[2] as lat,
    p.geometry_json.coordinates[1] as lon
  from items
  where p.gas = 'CH4'
)

select plumes.*, county
from plumes
join census.counties on ST_Contains(geom, ST_Point(lon, lat))
