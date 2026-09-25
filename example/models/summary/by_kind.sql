select
  coalesce(kind, '(none mapped)') as kind,
  count(*) as plumes,
  round(median(kg_h)) as median_kg_h
from matches
group by all
order by plumes desc
