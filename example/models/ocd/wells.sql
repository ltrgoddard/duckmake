SELECT api, name, operator, status, lat, lon
FROM 'https://s3.WAW3-2.cloudferro.com/data-desk-archive/nm-ocd/wells/data.parquet'
WHERE lat IS NOT NULL
