-- episodes with no report within 1 km and seven days, named after the nearest well within 100 m
SELECT e.*, w.operator, w.api, metres(e.lat, e.lon, w.lat, w.lon) AS well_m
FROM flaring.episodes e
LEFT JOIN ocd.wells w ON abs(w.lat - e.lat) < 0.001 AND abs(w.lon - e.lon) < 0.0012
  AND metres(e.lat, e.lon, w.lat, w.lon) < 100
WHERE e.end < (SELECT max(reported_on) - 15 FROM ocd.reports)
  AND NOT EXISTS (
    FROM ocd.reports r
    WHERE r.reported_on BETWEEN e.start - 7 AND e.end + 7
      AND abs(r.lat - e.lat) < 0.01 AND abs(r.lon - e.lon) < 0.012
      AND metres(e.lat, e.lon, r.lat, r.lon) < 1000)
QUALIFY row_number() OVER (PARTITION BY flare_id, episode ORDER BY well_m) = 1
