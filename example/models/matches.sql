-- each plume and the nearest mapped facility within RADIUS metres, if any
SELECT p.*, f.id AS facility_id, f.kind, f.operator, metres(p.lat, p.lon, f.lat, f.lon) AS metres
FROM carbonmapper.plumes p
LEFT JOIN osm.facilities f ON abs(f.lat - p.lat) < 0.01 AND abs(f.lon - p.lon) < 0.012
  AND metres(p.lat, p.lon, f.lat, f.lon) < getenv('RADIUS')::DOUBLE
QUALIFY row_number() OVER (PARTITION BY p.id ORDER BY metres) = 1
