-- consecutive nights at one flare, with gaps of up to two nights, form one episode
WITH nights AS (
  SELECT *, date - lag(date) OVER (PARTITION BY flare_id ORDER BY date) > 2 AS gap FROM viirs.nights
), numbered AS (
  SELECT *, count(*) FILTER (gap) OVER (PARTITION BY flare_id ORDER BY date) AS episode FROM nights
)
SELECT flare_id, episode, min(date) AS start, max(date) AS "end", count(*) AS nights,
       avg(lat) AS lat, avg(lon) AS lon, sum(rh_mw) AS mw_nights, any_value(county) AS county
FROM numbered JOIN census.counties ON ST_Contains(geom, ST_Point(lon, lat))
GROUP BY flare_id, episode
