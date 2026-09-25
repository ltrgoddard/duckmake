-- methane plumes over New Mexico from aircraft and satellite surveys
WITH items AS (SELECT unnest(items) AS p FROM read_json('data/plumes.json', maximum_object_size = 1e9)),
plumes AS (
  SELECT p.plume_id AS id, p.scene_timestamp::TIMESTAMP AS observed, p.platform, p.emission_auto AS kg_h,
         p.geometry_json.coordinates[2] AS lat, p.geometry_json.coordinates[1] AS lon
  FROM items WHERE p.gas = 'CH4'
)
SELECT plumes.*, county FROM plumes JOIN census.counties ON ST_Contains(geom, ST_Point(lon, lat))
