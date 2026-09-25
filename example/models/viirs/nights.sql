-- nights on which VIIRS Nightfire detected a flare within the bounds of New Mexico
SELECT flare_id, date, lat, lon, rh_mw
FROM 'https://s3.WAW3-2.cloudferro.com/data-desk-archive/data-desk/vnf/data.parquet'
WHERE detected AND date >= getenv('START')::DATE
  AND lat BETWEEN 31.3 AND 37.0 AND lon BETWEEN -109.05 AND -103.0
