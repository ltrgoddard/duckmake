SELECT flare_id, episode FROM flaring.unreported GROUP BY ALL HAVING count(*) > 1
