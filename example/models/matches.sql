-- each plume and the nearest mapped facility within RADIUS metres, if any
select
  p.*,
  f.id as facility_id,
  f.kind,
  f.operator,
  metres(p.lat, p.lon, f.lat, f.lon) as metres
from carbonmapper.plumes as p
left join osm.facilities as f
  on abs(f.lat - p.lat) < 0.01
  and abs(f.lon - p.lon) < 0.012
  and metres(p.lat, p.lon, f.lat, f.lon) < getenv('RADIUS')::double
qualify row_number() over (partition by p.id order by metres) = 1
