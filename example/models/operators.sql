SELECT coalesce(operator, '(no well within 100 m)') AS operator,
       count(*) AS episodes, sum(nights) AS nights, round(sum(mw_nights)) AS mw_nights
FROM flaring.unreported GROUP BY ALL ORDER BY nights DESC
