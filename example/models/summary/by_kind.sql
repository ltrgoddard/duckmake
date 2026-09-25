SELECT coalesce(kind, '(none mapped)') AS kind, count(*) AS plumes, round(median(kg_h)) AS median_kg_h
FROM matches GROUP BY ALL ORDER BY plumes DESC
