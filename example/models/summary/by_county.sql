SELECT county, count(*) AS plumes, count(facility_id) AS matched, round(sum(kg_h)) AS kg_h
FROM matches
GROUP BY ALL ORDER BY plumes DESC
