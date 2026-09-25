-- flaring and venting reports filed with the New Mexico Oil Conservation Division
SELECT report_id, reported_on, operator, facility, kind, volume_mcf, lat, lon
FROM 'https://s3.WAW3-2.cloudferro.com/data-desk-archive/nm-ocd/releases/data.parquet'
WHERE kind IN ('flare', 'vent', 'vent_and_flare') AND reported_on >= getenv('START')::DATE
  AND lat IS NOT NULL
